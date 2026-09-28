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
        var candidates = [Bundle.main.bundleURL, URL(fileURLWithPath: FileManager.default.currentDirectoryPath)]
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
        let executable = repositoryRoot.appendingPathComponent(".venv/bin/clip-resolved")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw BackendError.executableMissing(executable.path)
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = repositoryRoot
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
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

    func index(projectRoot: String, source: String, interval: Double) async throws -> ProjectStatus {
        _ = try await run(["index", "--project-root", projectRoot, "--source", source, "--interval", String(interval)])
        return try await status(projectRoot: projectRoot)
    }

    func moments(projectRoot: String, query: String, minScore: Double, pre: Double, post: Double, minimum: Double) async throws -> [MomentResult] {
        try await decode(
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

    func createSmartSelects(projectRoot: String, profile: String, minScore: Double, pre: Double, post: Double, minimum: Double) async throws -> SmartSelectsResult {
        try await decode(
            SmartSelectsResult.self,
            arguments: [
                "smart-selects", "--project-root", projectRoot,
                "--profile", profile,
                "--min-score", String(minScore),
                "--pre-handle", String(pre),
                "--post-handle", String(post),
                "--minimum-duration", String(minimum),
            ]
        )
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

    func scaffold(project: ProjectRecord, timelineFPS: Double) async throws -> ResolveScaffoldResult {
        try await decode(
            ResolveScaffoldResult.self,
            arguments: [
                "resolve-scaffold",
                "--project-root", project.rootPath,
                "--project-name", project.name,
                "--source", project.sourcePath,
                "--timeline-fps", String(timelineFPS),
            ]
        )
    }
}
