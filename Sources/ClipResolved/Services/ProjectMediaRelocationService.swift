import Foundation

struct RelocatedProjectSource: Codable, Hashable, Sendable {
    let label: String
    let path: String
}

struct ProjectMediaPathMove: Codable, Hashable, Sendable {
    let source: String
    let destination: String
    let bytes: Int64
    let isVideo: Bool
}

struct ProjectMediaRelocationResult: Sendable {
    let destinationProjectRoot: String
    let sources: [RelocatedProjectSource]
    let moves: [ProjectMediaPathMove]
    let manifestPath: String
    let takesMoved: Int
    let filesMoved: Int
    let bytesMoved: Int64

    var videoMoves: [ProjectMediaPathMove] { moves.filter(\.isVideo) }
}

actor ProjectMediaRelocationService {
    private let videoExtensions = Set(["mp4", "mov", "mxf", "m4v", "insv"])
    private let attachedExtensions = Set(["wav", "m4a", "mp3", "aif", "aiff", "flac", "srt", "xml", "xmp", "lrf"])

    func relocate(
        videoPaths: [String],
        sourceProject: ProjectRecord,
        destinationProjectRoot: URL,
        progress: @escaping @Sendable (String) -> Void
    ) throws -> ProjectMediaRelocationResult {
        let requested = Array(Set(videoPaths)).sorted()
        guard !requested.isEmpty else {
            throw CocoaError(.validationMissingMandatoryProperty, userInfo: [
                NSLocalizedDescriptionKey: "Select at least one video take to move."
            ])
        }
        let sourceRoot = URL(fileURLWithPath: sourceProject.rootPath).standardizedFileURL
        let destinationRoot = destinationProjectRoot.standardizedFileURL
        guard sourceRoot.path != destinationRoot.path else {
            throw CocoaError(.fileWriteInvalidFileName, userInfo: [
                NSLocalizedDescriptionKey: "Choose a different project as the destination."
            ])
        }

        let sourceVolume = try sourceRoot.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        let destinationParent = nearestExistingParent(of: destinationRoot)
        let destinationVolume = try destinationParent.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        guard String(describing: sourceVolume) == String(describing: destinationVolume) else {
            throw CocoaError(.fileWriteUnsupportedScheme, userInfo: [
                NSLocalizedDescriptionKey: "Project corrections must stay on the same drive so every move is atomic."
            ])
        }

        var moves: [ProjectMediaPathMove] = []
        var relocatedSources: [String: RelocatedProjectSource] = [:]
        for path in requested {
            let video = URL(fileURLWithPath: path).standardizedFileURL
            guard videoExtensions.contains(video.pathExtension.lowercased()),
                  FileManager.default.fileExists(atPath: video.path),
                  video.path.hasPrefix(sourceRoot.path + "/") else {
                throw CocoaError(.fileReadNoSuchFile, userInfo: [
                    NSLocalizedDescriptionKey: "The selected take is no longer inside \(sourceProject.name): \(video.lastPathComponent)"
                ])
            }
            guard let source = matchingSource(for: video, in: sourceProject) else {
                throw CocoaError(.fileReadNoPermission, userInfo: [
                    NSLocalizedDescriptionKey: "Clip Resolved could not match \(video.lastPathComponent) to a registered camera source."
                ])
            }
            let destinationMedia = destinationRoot
                .appendingPathComponent("Media", isDirectory: true)
                .appendingPathComponent(safeSourceFolder(source.label), isDirectory: true)
            relocatedSources[destinationMedia.path] = RelocatedProjectSource(label: source.label, path: destinationMedia.path)
            moves.append(try plannedMove(from: video, to: destinationMedia, isVideo: true))

            let stem = video.deletingPathExtension().lastPathComponent.lowercased()
            let siblings = try FileManager.default.contentsOfDirectory(
                at: video.deletingLastPathComponent(),
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            for sibling in siblings where sibling != video {
                guard sibling.deletingPathExtension().lastPathComponent.lowercased() == stem,
                      attachedExtensions.contains(sibling.pathExtension.lowercased()) else { continue }
                moves.append(try plannedMove(from: sibling, to: destinationMedia, isVideo: false))
            }
        }

        let uniqueMoves = Dictionary(grouping: moves, by: { $0.source }).compactMap(\.value.first).sorted { $0.source < $1.source }
        for move in uniqueMoves where FileManager.default.fileExists(atPath: move.destination) {
            throw CocoaError(.fileWriteFileExists, userInfo: [
                NSLocalizedDescriptionKey: "The destination already contains \(URL(fileURLWithPath: move.destination).lastPathComponent). Nothing was moved."
            ])
        }

        for source in relocatedSources.values {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: source.path),
                withIntermediateDirectories: true
            )
        }
        let manifestRoot = destinationRoot.appendingPathComponent(".clip-resolved/manifests", isDirectory: true)
        try FileManager.default.createDirectory(at: manifestRoot, withIntermediateDirectories: true)
        let operationID = UUID()
        let manifestURL = manifestRoot.appendingPathComponent("media-correction-\(operationID.uuidString).json")
        try writeManifest(
            state: "moving",
            operationID: operationID,
            sourceProject: sourceProject,
            destinationRoot: destinationRoot,
            moves: uniqueMoves,
            to: manifestURL
        )

        var completed: [ProjectMediaPathMove] = []
        do {
            for (index, move) in uniqueMoves.enumerated() {
                progress("Moving verified project file \(index + 1) of \(uniqueMoves.count): \(URL(fileURLWithPath: move.source).lastPathComponent)")
                try FileManager.default.moveItem(
                    at: URL(fileURLWithPath: move.source),
                    to: URL(fileURLWithPath: move.destination)
                )
                completed.append(move)
            }
        } catch {
            for move in completed.reversed() where FileManager.default.fileExists(atPath: move.destination) {
                try? FileManager.default.moveItem(
                    at: URL(fileURLWithPath: move.destination),
                    to: URL(fileURLWithPath: move.source)
                )
            }
            try? writeManifest(
                state: "rolled-back",
                operationID: operationID,
                sourceProject: sourceProject,
                destinationRoot: destinationRoot,
                moves: uniqueMoves,
                to: manifestURL
            )
            throw error
        }
        try writeManifest(
            state: "moved",
            operationID: operationID,
            sourceProject: sourceProject,
            destinationRoot: destinationRoot,
            moves: uniqueMoves,
            to: manifestURL
        )
        return ProjectMediaRelocationResult(
            destinationProjectRoot: destinationRoot.path,
            sources: relocatedSources.values.sorted { $0.label < $1.label },
            moves: uniqueMoves,
            manifestPath: manifestURL.path,
            takesMoved: uniqueMoves.filter(\.isVideo).count,
            filesMoved: uniqueMoves.count,
            bytesMoved: uniqueMoves.reduce(0) { $0 + $1.bytes }
        )
    }

    private func matchingSource(for video: URL, in project: ProjectRecord) -> ProjectSourceRecord? {
        project.sources
            .filter { $0.kind == .camera }
            .filter {
                let root = URL(fileURLWithPath: $0.path).standardizedFileURL.path
                return video.path == root || video.path.hasPrefix(root + "/")
            }
            .max { $0.path.count < $1.path.count }
    }

    private func plannedMove(from source: URL, to destinationDirectory: URL, isVideo: Bool) throws -> ProjectMediaPathMove {
        let values = try source.resourceValues(forKeys: [.fileSizeKey])
        return ProjectMediaPathMove(
            source: source.path,
            destination: destinationDirectory.appendingPathComponent(source.lastPathComponent).path,
            bytes: Int64(values.fileSize ?? 0),
            isVideo: isVideo
        )
    }

    private func safeSourceFolder(_ label: String) -> String {
        let cleaned = label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "CAMERA" : cleaned.uppercased()
    }

    private func nearestExistingParent(of url: URL) -> URL {
        var candidate = url
        while !FileManager.default.fileExists(atPath: candidate.path), candidate.path != "/" {
            candidate.deleteLastPathComponent()
        }
        return candidate
    }

    private func writeManifest(
        state: String,
        operationID: UUID,
        sourceProject: ProjectRecord,
        destinationRoot: URL,
        moves: [ProjectMediaPathMove],
        to url: URL
    ) throws {
        let payload: [String: Any] = [
            "schema": 1,
            "operation_id": operationID.uuidString,
            "state": state,
            "created_at": ISO8601DateFormatter().string(from: Date()),
            "source_project": sourceProject.rootPath,
            "destination_project": destinationRoot.path,
            "moves": moves.map {
                ["source": $0.source, "destination": $0.destination, "bytes": $0.bytes, "is_video": $0.isVideo]
            },
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
