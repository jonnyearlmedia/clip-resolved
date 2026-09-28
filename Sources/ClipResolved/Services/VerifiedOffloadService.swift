import Foundation
import OffloadCore
import OffloadEngine

struct OffloadResult: Sendable {
    let projectRoot: URL
    let mediaRoot: URL
    let filesVerified: Int
    let bytesVerified: Int64
}

actor VerifiedOffloadService {
    func offload(
        group: ShootGroup,
        sourceRoot: URL,
        activeProjectsRoot: URL,
        volumeUUID: String,
        progress: @escaping @Sendable (String) -> Void
    ) async throws -> OffloadResult {
        let safeName = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safeName.isEmpty, !safeName.contains("/"), safeName != ".", safeName != ".." else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let projectRoot = activeProjectsRoot
            .appendingPathComponent(group.kind.rawValue, isDirectory: true)
            .appendingPathComponent(safeName, isDirectory: true)
        let mediaRoot = projectRoot.appendingPathComponent("Media/Osmo", isDirectory: true)
        let manifestRoot = projectRoot.appendingPathComponent(".clip-resolved/manifests", isDirectory: true)
        for folder in [mediaRoot, projectRoot.appendingPathComponent("Assets"), projectRoot.appendingPathComponent("Project"), projectRoot.appendingPathComponent(".clip-resolved/analysis"), manifestRoot] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let required = group.totalBytes + max(512 * 1024 * 1024, group.totalBytes / 20)
        let capacity = try projectRoot.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        guard capacity >= required else {
            throw CocoaError(.fileWriteOutOfSpace, userInfo: [
                NSLocalizedDescriptionKey: "Not enough free space. Need \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)); only \(ByteCountFormatter.string(fromByteCount: capacity, countStyle: .file)) is available."
            ])
        }

        let sourcePrefix = sourceRoot.standardizedFileURL.path + "/"
        let records = try group.files.map { file -> FileRecord in
            let source = URL(fileURLWithPath: file.path).standardizedFileURL
            guard source.path.hasPrefix(sourcePrefix) else {
                throw CocoaError(.fileReadNoPermission)
            }
            let values = try source.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            return FileRecord(
                relPath: file.relativePath,
                size: file.size,
                mtime: values.contentModificationDate ?? Date(),
                creationDate: values.creationDate,
                destRelPath: source.lastPathComponent
            )
        }
        var stats = SessionStats()
        stats.filesPlanned = records.count
        stats.bytesPlanned = records.reduce(0) { $0 + $1.size }
        let session = SessionRecord(
            cardVolumeUUID: volumeUUID,
            cardVolumeName: sourceRoot.lastPathComponent,
            cardCapacityBytes: 0,
            state: .transferring,
            files: records,
            stats: stats
        )
        let journal = Journal(
            directory: manifestRoot.appendingPathComponent("journal"),
            historyDir: manifestRoot.appendingPathComponent("history")
        )
        try await journal.begin(session)

        var verified = 0
        var bytes: Int64 = 0
        var manifestItems: [[String: Any]] = []
        do {
            for (index, pair) in zip(group.files, records).enumerated() {
                let (file, record) = pair
                let source = URL(fileURLWithPath: file.path)
                let desired = mediaRoot.appendingPathComponent(source.lastPathComponent)
                var destination = desired
                if FileManager.default.fileExists(atPath: desired.path) {
                    let sourceHash = try await ChunkedIO.hashFile(source, noCache: true)
                    let existingHash = try await ChunkedIO.hashFile(desired, noCache: true)
                    if sourceHash == existingHash {
                        await journal.transition(file: record.id, to: .copying, in: session.id)
                        await journal.setSourceHash(file: record.id, hex: sourceHash, in: session.id)
                        await journal.transition(file: record.id, to: .staged, in: session.id)
                        await journal.transition(file: record.id, to: .stagedVerified, in: session.id)
                        await journal.transition(file: record.id, to: .uploading, in: session.id)
                        await journal.transition(file: record.id, to: .skippedDuplicate, in: session.id)
                        verified += 1
                        bytes += file.size
                        manifestItems.append([
                            "source": source.path,
                            "destination": desired.path,
                            "bytes": file.size,
                            "sha256": sourceHash,
                            "verified": true,
                            "duplicate": true,
                        ])
                        continue
                    }
                    destination = uniqueDestination(desired)
                }
                let partial = destination.appendingPathExtension("crpartial")
                try? FileManager.default.removeItem(at: partial)
                progress("\(safeName): \(index + 1)/\(records.count) \(source.lastPathComponent)")
                await journal.transition(file: record.id, to: .copying, in: session.id)

                let result = try await ChunkedIO.copyAndHash(from: source, to: partial)
                await journal.setSourceHash(file: record.id, hex: result.sha256Hex, in: session.id)
                await journal.transition(file: record.id, to: .staged, in: session.id)
                let verifiedHash = try await ChunkedIO.hashFile(partial, noCache: true)
                guard verifiedHash == result.sha256Hex else {
                    try? FileManager.default.removeItem(at: partial)
                    throw OffloadError(.hashMismatch(stage: "destination reread"))
                }
                await journal.transition(file: record.id, to: .stagedVerified, in: session.id)
                await journal.transition(file: record.id, to: .uploading, in: session.id)
                try FileManager.default.moveItem(at: partial, to: destination)
                try? FileManager.default.setAttributes([.modificationDate: record.mtime], ofItemAtPath: destination.path)
                await journal.transition(file: record.id, to: .uploaded, in: session.id)
                await journal.transition(file: record.id, to: .nasVerified, in: session.id)
                verified += 1
                bytes += result.bytes
                manifestItems.append([
                    "source": source.path,
                    "destination": destination.path,
                    "bytes": result.bytes,
                    "sha256": result.sha256Hex,
                    "verified": true,
                ])
            }
            await journal.setSessionState(.done, in: session.id)
            await journal.setEnded(in: session.id)
            try await journal.flushNow(session.id)
            try await journal.complete(session.id)
        } catch {
            await journal.setSessionState(.failed, in: session.id)
            try? await journal.flushNow(session.id)
            throw error
        }

        let manifest: [String: Any] = [
            "schema": 1,
            "project": safeName,
            "classification": group.kind.rawValue,
            "source_root": sourceRoot.path,
            "project_root": projectRoot.path,
            "created_at": ISO8601DateFormatter().string(from: Date()),
            "files": manifestItems,
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: manifestRoot.appendingPathComponent("ingest-manifest.json"), options: .atomic)
        return OffloadResult(projectRoot: projectRoot, mediaRoot: mediaRoot, filesVerified: verified, bytesVerified: bytes)
    }

    private func uniqueDestination(_ desired: URL) -> URL {
        let stem = desired.deletingPathExtension().lastPathComponent
        let ext = desired.pathExtension
        for counter in 2...9999 {
            let name = ext.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(ext)"
            let candidate = desired.deletingLastPathComponent().appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return desired.deletingLastPathComponent().appendingPathComponent("\(stem)-\(UUID().uuidString).\(ext)")
    }
}
