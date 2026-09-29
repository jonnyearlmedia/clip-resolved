import Foundation

struct CommandResult {
    let stdout: Data
    let stderr: String
}

enum BackendError: LocalizedError {
    case repositoryNotFound
    case executableMissing(String)
    case commandFailed(Int32, String)
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .repositoryNotFound: "Clip Resolved repository could not be located."
        case .executableMissing(let path): "Backend executable is missing at \(path). Run bootstrap_upstreams.sh."
        case .commandFailed(let status, let output): "Backend failed (\(status)): \(output)"
        case .invalidOutput(let output): "Backend returned invalid data: \(output)"
        }
    }
}

actor BackendService {
    let repositoryRoot: URL
    private let decoder = JSONDecoder()

    init() {
        repositoryRoot = Self.findRepositoryRoot() ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private static func findRepositoryRoot() -> URL? {
        if let configured = ProcessInfo.processInfo.environment["CLIP_RESOLVED_REPO"] {
            return URL(fileURLWithPath: configured)
        }
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var candidates = [
            applicationSupport.appendingPathComponent("Clip Resolved/Runtime", isDirectory: true),
            Bundle.main.resourceURL?.appendingPathComponent("Runtime", isDirectory: true),
            Bundle.main.bundleURL,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        ].compactMap { $0 }
        while let candidate = candidates.first {
            candidates.removeFirst()
            var current = candidate
            for _ in 0..<8 {
                if FileManager.default.fileExists(atPath: current.appendingPathComponent("pyproject.toml").path),
                   FileManager.default.fileExists(atPath: current.appendingPathComponent("src/clip_resolved").path) {
                    return current
                }
                current.deleteLastPathComponent()
            }
        }
        return nil
    }

    func run(_ arguments: [String]) async throws -> CommandResult {
        let python = repositoryRoot.appendingPathComponent(".venv/bin/python")
        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            throw BackendError.executableMissing(python.path)
        }
        let process = Process()
        process.executableURL = python
        process.arguments = ["-m", "clip_resolved.cli"] + arguments
        process.currentDirectoryURL = repositoryRoot
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PYTHONPATH"] = repositoryRoot.appendingPathComponent("src").path
        process.environment = environment
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutTask = Task.detached { stdoutPipe.fileHandleForReading.readDataToEndOfFile() }
        let stderrTask = Task.detached { stderrPipe.fileHandleForReading.readDataToEndOfFile() }
        try process.run()
        let status = await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in continuation.resume(returning: finished.terminationStatus) }
        }
        let stdout = await stdoutTask.value
        let stderrData = await stderrTask.value
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        guard status == 0 else { throw BackendError.commandFailed(status, stderr) }
        return CommandResult(stdout: stdout, stderr: stderr)
    }

    func decode<T: Decodable>(_ type: T.Type, arguments: [String]) async throws -> T {
        let result = try await run(arguments)
        do {
            return try decoder.decode(type, from: result.stdout)
        } catch {
            throw BackendError.invalidOutput(String(data: result.stdout, encoding: .utf8) ?? error.localizedDescription)
        }
    }

    func scan(source: String, gapHours: Double) async throws -> ScanPayload {
        try await decode(ScanPayload.self, arguments: ["scan", "--source", source, "--gap-hours", String(gapHours)])
    }

    func status(projectRoot: String) async throws -> ProjectStatus {
        try await decode(ProjectStatus.self, arguments: ["status", "--project-root", projectRoot])
    }

    func index(projectRoot: String, source: String, sourceLabel: String, interval: Double) async throws -> ProjectStatus {
        _ = try await run([
            "index", "--project-root", projectRoot,
            "--source", source,
            "--source-label", sourceLabel,
            "--interval", String(interval),
        ])
        return try await status(projectRoot: projectRoot)
    }

    func registerSource(
        projectRoot: String,
        source: String,
        sourceLabel: String,
        kind: ProjectSourceKind
    ) async throws {
        _ = try await run([
            "register-source", "--project-root", projectRoot,
            "--source", source,
            "--source-label", sourceLabel,
            "--source-kind", kind.backendName,
        ])
    }

    func relocateIndexedAssets(
        sourceProjectRoot: String,
        destinationProjectRoot: String,
        mappingFile: String
    ) async throws -> IndexRelocationResult {
        try await decode(
            IndexRelocationResult.self,
            arguments: [
                "relocate-indexed-assets",
                "--source-project-root", sourceProjectRoot,
                "--destination-project-root", destinationProjectRoot,
                "--mapping-file", mappingFile,
            ]
        )
    }

    func moments(projectRoot: String, query: String, minScore: Double, pre: Double, post: Double, minimum: Double) async throws -> [MomentResult] {
        return try await decode(
            [MomentResult].self,
            arguments: [
                "moments", "--project-root", projectRoot, query,
                "--min-score", String(minScore),
                "--pre-handle", String(pre),
                "--post-handle", String(post),
                "--minimum-duration", String(minimum),
            ]
        )
    }

    func transcribe(projectRoot: String, source: String, model: String = "base.en") async throws -> ProjectStatus {
        _ = try await run([
            "transcribe", "--project-root", projectRoot, "--source", source, "--model", model,
        ])
        return try await status(projectRoot: projectRoot)
    }

    func transcriptMoments(projectRoot: String, query: String, pre: Double, post: Double, minimum: Double) async throws -> [MomentResult] {
        try await decode(
            [MomentResult].self,
            arguments: [
                "transcript-moments", "--project-root", projectRoot, query,
                "--pre-handle", String(pre),
                "--post-handle", String(post),
                "--minimum-duration", String(minimum),
            ]
        )
    }

    func transcriptContext(projectRoot: String, maxCharacters: Int = 40_000) async throws -> TranscriptContext {
        try await decode(
            TranscriptContext.self,
            arguments: [
                "transcript-context", "--project-root", projectRoot,
                "--max-characters", String(maxCharacters),
            ]
        )
    }

    func createSelects(projectRoot: String, query: String, name: String, minScore: Double, pre: Double, post: Double, minimum: Double) async throws -> SelectsResult {
        try await decode(
            SelectsResult.self,
            arguments: [
                "selects", "--project-root", projectRoot, query,
                "--timeline-name", name,
                "--min-score", String(minScore),
                "--pre-handle", String(pre),
                "--post-handle", String(post),
                "--minimum-duration", String(minimum),
            ]
        )
    }

    func resolveTimelines() async throws -> ResolveTimelineState {
        try await decode(ResolveTimelineState.self, arguments: ["resolve-timelines"])
    }

    func openTimeline(_ name: String) async throws -> OpenTimelineResult {
        try await decode(
            OpenTimelineResult.self,
            arguments: ["open-timeline", "--timeline-name", name]
        )
    }

    func createSmartSelects(
        projectRoot: String,
        profile: String?,
        minScore: Double,
        pre: Double,
        post: Double,
        minimum: Double,
        discover: Bool = true,
        adaptive: Bool = true,
        visionVerify: Bool = true
    ) async throws -> SmartSelectsResult {
        var arguments = ["smart-selects", "--project-root", projectRoot]
        if let profile {
            arguments += ["--profile", profile]
        }
        arguments += [
            "--min-score", String(minScore),
            "--pre-handle", String(pre),
            "--post-handle", String(post),
            "--minimum-duration", String(minimum),
        ]
        if discover { arguments.append("--discover") }
        if adaptive { arguments.append("--adaptive") }
        if visionVerify { arguments.append("--vision-verify") }
        return try await decode(SmartSelectsResult.self, arguments: arguments)
    }

    func createTranscriptSelects(projectRoot: String, query: String, name: String, pre: Double, post: Double, minimum: Double) async throws -> SelectsResult {
        try await decode(
            SelectsResult.self,
            arguments: [
                "transcript-selects", "--project-root", projectRoot, query,
                "--timeline-name", name,
                "--pre-handle", String(pre),
                "--post-handle", String(post),
                "--minimum-duration", String(minimum),
            ]
        )
    }

    func createExactRangeSelects(projectRoot: String, ranges: [ChatEvidence], name: String) async throws -> SelectsResult {
        let payload = [
            "ranges": ranges.map { range in
                [
                    "source_path": range.sourcePath,
                    "start": range.start,
                    "end": range.end,
                    "transcript": range.transcript ?? "",
                ] as [String: Any]
            }
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-resolved-ranges-\(UUID().uuidString).json")
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        return try await decode(
            SelectsResult.self,
            arguments: [
                "exact-range-selects", "--project-root", projectRoot,
                "--ranges-file", url.path,
                "--timeline-name", name,
            ]
        )
    }

    func scaffold(project: ProjectRecord, timelineFPS: Double) async throws -> ResolveScaffoldResult {
        guard let primaryCamera = project.sources.first(where: { $0.kind == .camera }) else {
            throw BackendError.invalidOutput("Add at least one camera source before preparing Resolve.")
        }
        let source = project.sourcePath.isEmpty ? primaryCamera.path : project.sourcePath
        let sourceLabel = project.sources.first(where: { $0.path == source })?.label ?? primaryCamera.label
        return try await decode(
            ResolveScaffoldResult.self,
            arguments: [
                "resolve-scaffold",
                "--project-root", project.rootPath,
                "--project-name", project.resolveProjectName,
                "--source", source,
                "--source-label", sourceLabel,
                "--timeline-fps", String(timelineFPS),
            ]
        )
    }

    func syncAudio(projectRoot: String) async throws -> AudioSyncResult {
        try await decode(
            AudioSyncResult.self,
            arguments: ["sync-audio", "--project-root", projectRoot]
        )
    }

    func createMulticam(
        projectRoot: String,
        name: String,
        syncMode: String
    ) async throws -> MulticamResult {
        try await decode(
            MulticamResult.self,
            arguments: [
                "create-multicam", "--project-root", projectRoot,
                "--name", name,
                "--sync-mode", syncMode,
            ]
        )
    }
}
