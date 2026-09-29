import Foundation
import OffloadCore
import OffloadEngine

struct OffloadResult: Sendable {
    let projectRoot: URL
    let mediaRoot: URL
    let filesVerified: Int
    let bytesVerified: Int64
    let cleanupPlan: VerifiedCleanupPlan
}

struct OffloadCapacityRequest: Sendable {
    let destinationRoot: URL
    let bytes: Int64
}

struct OffloadCapacityStatus: Sendable, Hashable, Identifiable {
    let volumeID: String
    let destinationName: String
    let selectedBytes: Int64
    let requiredBytes: Int64
    let availableBytes: Int64

    var id: String { volumeID }
    var shortfallBytes: Int64 { max(0, requiredBytes - availableBytes) }
    var hasCapacity: Bool { shortfallBytes == 0 }
}

/// Durable evidence for an optional, later source cleanup. Copying never uses
/// this plan to erase anything; it is consumed only after a second explicit
/// confirmation in the UI.
struct VerifiedCleanupPlan: Codable, Identifiable, Sendable {
    let id: UUID
    let sourceRoot: String
    let volumeUUID: String
    let projectRoot: String
    let manifestRoot: String
    let session: SessionRecord
    let destinationByFileID: [String: String]

    var fileCount: Int { session.files.count }
    var totalBytes: Int64 { session.files.reduce(0) { $0 + $1.size } }
}

actor VerifiedOffloadService {
    func validateCapacity(for requests: [OffloadCapacityRequest]) throws {
        for status in try Self.capacityStatuses(for: requests) {
            guard status.hasCapacity else {
                throw CocoaError(.fileWriteOutOfSpace, userInfo: [
                    NSLocalizedDescriptionKey: "The selected shoots need \(Self.formatted(status.requiredBytes)) including verification headroom, but \(status.destinationName) has \(Self.formatted(status.availableBytes)) available. Deselect at least \(Self.formatted(status.shortfallBytes)) before importing. Nothing was copied."
                ])
            }
        }
    }

    nonisolated static func capacityStatuses(for requests: [OffloadCapacityRequest]) throws -> [OffloadCapacityStatus] {
        struct VolumeRequirement {
            var volumeID: String
            var destinationName: String
            var bytes: Int64
            var available: Int64
        }

        var requirements: [String: VolumeRequirement] = [:]
        for request in requests {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: request.destinationRoot.path)
            let volumeID = (attributes[.systemNumber] as? NSNumber)?.stringValue ?? request.destinationRoot.path
            let available = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            let volumeName = (try? request.destinationRoot.resourceValues(forKeys: [.volumeNameKey]).volumeName)
                ?? request.destinationRoot.path
            var requirement = requirements[volumeID]
                ?? VolumeRequirement(volumeID: volumeID, destinationName: volumeName, bytes: 0, available: available)
            requirement.bytes += request.bytes
            requirement.available = min(requirement.available, available)
            requirements[volumeID] = requirement
        }

        return requirements.values.map { requirement in
            OffloadCapacityStatus(
                volumeID: requirement.volumeID,
                destinationName: requirement.destinationName,
                selectedBytes: requirement.bytes,
                requiredBytes: Self.requiredCapacity(for: requirement.bytes),
                availableBytes: requirement.available
            )
        }
        .sorted { $0.destinationName.localizedStandardCompare($1.destinationName) == .orderedAscending }
    }

    func offload(
        group: ShootGroup,
        sourceRoot: URL,
        activeProjectsRoot: URL,
        volumeUUID: String,
        destinationProjectRoot: URL? = nil,
        progress: @escaping @Sendable (String) -> Void
    ) async throws -> OffloadResult {
        let safeName = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safeName.isEmpty, !safeName.contains("/"), safeName != ".", safeName != ".." else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let projectRoot = destinationProjectRoot?.standardizedFileURL ?? activeProjectsRoot
            .appendingPathComponent(group.kind.rawValue, isDirectory: true)
            .appendingPathComponent(safeName, isDirectory: true)
        let sourceFolder = safeSourceFolder(group.sourceLabel)
        let sourceCollection = group.sourceKind == .audio ? "Audio" : "Media"
        let mediaRoot = projectRoot.appendingPathComponent("\(sourceCollection)/\(sourceFolder)", isDirectory: true)
        let manifestRoot = projectRoot.appendingPathComponent(".clip-resolved/manifests", isDirectory: true)
        for folder in [mediaRoot, projectRoot.appendingPathComponent("Assets"), projectRoot.appendingPathComponent("Project"), projectRoot.appendingPathComponent(".clip-resolved/analysis"), manifestRoot] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let required = Self.requiredCapacity(for: group.totalBytes)
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: projectRoot.path)
        let capacity = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        guard capacity >= required else {
            throw CocoaError(.fileWriteOutOfSpace, userInfo: [
                NSLocalizedDescriptionKey: "Not enough free space. Need \(Self.formatted(required)); only \(Self.formatted(capacity)) is available. Nothing was copied."
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
        var destinationByFileID: [String: String] = [:]
        var verifiedSession: SessionRecord?
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
                        destinationByFileID[record.id.uuidString] = desired.path
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
                destinationByFileID[record.id.uuidString] = destination.path
            }
            await journal.setSessionState(.done, in: session.id)
            await journal.setEnded(in: session.id)
            try await journal.flushNow(session.id)
            verifiedSession = await journal.session(id: session.id)
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
            "source_label": group.sourceLabel,
            "source_root": sourceRoot.path,
            "project_root": projectRoot.path,
            "created_at": ISO8601DateFormatter().string(from: Date()),
            "files": manifestItems,
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: manifestRoot.appendingPathComponent("ingest-\(session.id.uuidString).json"), options: .atomic)
        try data.write(to: manifestRoot.appendingPathComponent("ingest-manifest.json"), options: .atomic)
        guard let verifiedSession else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSLocalizedDescriptionKey: "The verified ingest journal could not be read back. Source cleanup remains disabled."
            ])
        }
        let cleanupPlan = VerifiedCleanupPlan(
            id: session.id,
            sourceRoot: sourceRoot.standardizedFileURL.path,
            volumeUUID: volumeUUID,
            projectRoot: projectRoot.path,
            manifestRoot: manifestRoot.path,
            session: verifiedSession,
            destinationByFileID: destinationByFileID
        )
        let cleanupData = try JSONEncoder().encode(cleanupPlan)
        try cleanupData.write(
            to: manifestRoot.appendingPathComponent("cleanup-plan-\(session.id.uuidString).json"),
            options: .atomic
        )
        return OffloadResult(
            projectRoot: projectRoot,
            mediaRoot: mediaRoot,
            filesVerified: verified,
            bytesVerified: bytes,
            cleanupPlan: cleanupPlan
        )
    }

    nonisolated static func requiredCapacity(for bytes: Int64) -> Int64 {
        bytes + max(512 * 1024 * 1024, bytes / 20)
    }

    private nonisolated static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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

    private func safeSourceFolder(_ label: String) -> String {
        let cleaned = label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "CAMERA" : cleaned.uppercased()
    }
}
