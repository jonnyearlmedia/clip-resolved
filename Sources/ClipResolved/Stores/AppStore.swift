import Foundation
import Observation
import OffloadCore
import OffloadEngine

@MainActor
@Observable
final class AppStore {
    var selection: WorkspaceSection = .ingest
    var sourcePath = ""
    var scanPayload: ScanPayload?
    var shootGroups: [ShootGroup] = []
    var projects: [ProjectRecord] = []
    var selectedProjectID: ProjectRecord.ID?
    var query = ""
    var searchMode: SearchMode = .visual
    var timelineName = ""
    var moments: [MomentResult] = []
    var cards: [CardInfo] = []
    var activity: [ActivityEntry] = []
    var isBusy = false
    var progressMessage = "Ready"
    var errorMessage: String?
    var resolveMessage = "Not checked"

    var activeProjectsRoot: String {
        didSet { UserDefaults.standard.set(activeProjectsRoot, forKey: "activeProjectsRoot") }
    }
    var gapHours: Double {
        didSet { UserDefaults.standard.set(gapHours, forKey: "gapHours") }
    }
    var sampleInterval: Double {
        didSet { UserDefaults.standard.set(sampleInterval, forKey: "sampleInterval") }
    }
    var minScore: Double {
        didSet { UserDefaults.standard.set(minScore, forKey: "minScore") }
    }
    var preHandle: Double {
        didSet { UserDefaults.standard.set(preHandle, forKey: "preHandle") }
    }
    var postHandle: Double {
        didSet { UserDefaults.standard.set(postHandle, forKey: "postHandle") }
    }
    var minimumDuration: Double {
        didSet { UserDefaults.standard.set(minimumDuration, forKey: "minimumDuration") }
    }

    private let backend = BackendService()
    private let offloader = VerifiedOffloadService()
    private let watcher = CardWatcher()
    private var cardTask: Task<Void, Never>?

    var selectedProject: ProjectRecord? {
        guard let selectedProjectID else { return projects.first }
        return projects.first { $0.id == selectedProjectID }
    }

    init() {
        activeProjectsRoot = UserDefaults.standard.string(forKey: "activeProjectsRoot") ?? "/Volumes/Extreme SSD/ACTIVE PROJECTS"
        gapHours = UserDefaults.standard.object(forKey: "gapHours") as? Double ?? 3.0
        sampleInterval = UserDefaults.standard.object(forKey: "sampleInterval") as? Double ?? 2.0
        minScore = UserDefaults.standard.object(forKey: "minScore") as? Double ?? 0.24
        preHandle = UserDefaults.standard.object(forKey: "preHandle") as? Double ?? 2.0
        postHandle = UserDefaults.standard.object(forKey: "postHandle") as? Double ?? 3.0
        minimumDuration = UserDefaults.standard.object(forKey: "minimumDuration") as? Double ?? 6.0
        projects = Self.loadProjects()
        if projects.isEmpty {
            let osaka = "/Volumes/Extreme SSD/ACTIVE PROJECTS/OSAKA"
            if FileManager.default.fileExists(atPath: osaka) {
                projects = [ProjectRecord(name: "OSAKA", rootPath: osaka, sourcePath: osaka + "/RAW FOOTAGE", kind: .client)]
                saveProjects()
            }
        }
        selectedProjectID = projects.first?.id
        startCardWatcher()
    }

    func startCardWatcher() {
        watcher.start()
        cardTask = Task { [weak self] in
            guard let self else { return }
            for await event in watcher.events {
                switch event {
                case .volumeMounted(let candidate):
                    guard candidate.info.hasMediaRoot, !candidate.isInternal, !candidate.isNetwork else { continue }
                    if !cards.contains(where: { $0.volumeUUID == candidate.info.volumeUUID }) {
                        cards.append(candidate.info)
                        log("Detected camera media: \(candidate.info.volumeName)")
                    }
                case .volumeUnmounted(let uuid, _):
                    cards.removeAll { $0.volumeUUID == uuid }
                    log("Camera media disconnected")
                }
            }
        }
    }

    func useCard(_ card: CardInfo) {
        sourcePath = card.mountPath
        Task { await scanSource() }
    }

    func scanSource() async {
        guard !sourcePath.isEmpty else { return }
        await perform("Scanning source read-only") {
            let payload = try await backend.scan(source: sourcePath, gapHours: gapHours)
            scanPayload = payload
            shootGroups = payload.groups.map {
                ShootGroup(id: $0.id, name: $0.suggestedName, kind: .client, files: $0.files, start: $0.start, end: $0.end)
            }
            log("Found \(payload.videoCount) videos in \(payload.groups.count) proposed shoot group(s)")
            if !payload.unassignedSidecars.isEmpty {
                log("Kept \(payload.unassignedSidecars.count) unassigned sidecar(s) untouched")
            }
        }
    }

    func move(file: ScannedFile, from sourceID: String, to destinationID: String) {
        guard sourceID != destinationID,
              let sourceIndex = shootGroups.firstIndex(where: { $0.id == sourceID }),
              let destinationIndex = shootGroups.firstIndex(where: { $0.id == destinationID }),
              let fileIndex = shootGroups[sourceIndex].files.firstIndex(of: file) else { return }
        let moved = shootGroups[sourceIndex].files.remove(at: fileIndex)
        shootGroups[destinationIndex].files.append(moved)
        if moved.kind == "video" {
            let sidecars = shootGroups[sourceIndex].files.filter { $0.groupKey == moved.groupKey }
            shootGroups[sourceIndex].files.removeAll { $0.groupKey == moved.groupKey }
            shootGroups[destinationIndex].files.append(contentsOf: sidecars)
        }
    }

    func splitIntoNewShoot(file: ScannedFile, from sourceID: String) {
        guard let sourceIndex = shootGroups.firstIndex(where: { $0.id == sourceID }),
              shootGroups[sourceIndex].videos.count > 1 else { return }
        let related = shootGroups[sourceIndex].files.filter {
            $0.id == file.id || ($0.kind != "video" && $0.groupKey == file.groupKey)
        }
        shootGroups[sourceIndex].files.removeAll { candidate in related.contains(candidate) }
        shootGroups.append(
            ShootGroup(
                id: UUID().uuidString,
                name: "Shoot \(shootGroups.count + 1)",
                kind: shootGroups[sourceIndex].kind,
                files: related,
                start: file.captureTime,
                end: file.captureTime
            )
        )
        log("Split \(URL(fileURLWithPath: file.path).lastPathComponent) into a new shoot")
    }

    func mergeShoot(_ sourceID: String, into destinationID: String) {
        guard sourceID != destinationID,
              let sourceIndex = shootGroups.firstIndex(where: { $0.id == sourceID }),
              let destinationIndex = shootGroups.firstIndex(where: { $0.id == destinationID }) else { return }
        let files = shootGroups[sourceIndex].files
        shootGroups[destinationIndex].files.append(contentsOf: files)
        shootGroups.remove(at: sourceIndex)
        log("Merged shoot groups; every scanned file remains assigned")
    }

    func confirmAndIngest() async {
        guard !sourcePath.isEmpty, !shootGroups.isEmpty else { return }
        let sourceURL = URL(fileURLWithPath: sourcePath)
        await perform("Verified ingest") {
            for group in shootGroups where !group.videos.isEmpty {
                let volumeID = cards.first(where: { $0.mountPath == sourcePath })?.volumeUUID ?? "manual-\(sourceURL.lastPathComponent)"
                let result = try await offloader.offload(
                    group: group,
                    sourceRoot: sourceURL,
                    activeProjectsRoot: URL(fileURLWithPath: activeProjectsRoot),
                    volumeUUID: volumeID,
                    progress: { [weak self] message in Task { @MainActor in self?.progressMessage = message } }
                )
                var project = ProjectRecord(name: group.name, rootPath: result.projectRoot.path, sourcePath: result.mediaRoot.path, kind: group.kind)
                log("\(group.name): \(result.filesVerified) files copied and checksum-verified")
                let status = try await backend.index(projectRoot: project.rootPath, source: project.sourcePath, interval: sampleInterval)
                project.indexedAssets = status.assets
                project.visualSamples = status.visualSamples
                project.transcripts = status.transcripts
                upsertProject(project)
                do {
                    let resolve = try await backend.scaffold(project: project, timelineFPS: 30)
                    resolveMessage = resolve.frameRatesMatch
                        ? "Resolve \(resolve.project) ready — \(resolve.sourceFiles) originals"
                        : "Resolve created. Set Playback frame rate to \(resolve.timelineFPS ?? 30) in Project Settings."
                    log(resolveMessage)
                } catch {
                    log("Ingest/index complete; Resolve preparation is waiting: \(error.localizedDescription)", error: true)
                }
            }
            selection = .search
        }
    }

    func addExistingProject(name: String, root: String, source: String, kind: ProjectKind) async {
        guard !name.isEmpty, !root.isEmpty, !source.isEmpty else { return }
        var project = ProjectRecord(name: name, rootPath: root, sourcePath: source, kind: kind)
        do {
            let status = try await backend.status(projectRoot: root)
            project.indexedAssets = status.assets
            project.visualSamples = status.visualSamples
            project.transcripts = status.transcripts
        } catch { }
        upsertProject(project)
        selection = .search
    }

    func indexSelectedProject() async {
        guard var project = selectedProject else { return }
        await perform("Indexing \(project.name)") {
            let status = try await backend.index(projectRoot: project.rootPath, source: project.sourcePath, interval: sampleInterval)
            project.indexedAssets = status.assets
            project.visualSamples = status.visualSamples
            project.transcripts = status.transcripts
            upsertProject(project)
            log("Indexed \(status.assets) clips / \(status.visualSamples) visual samples")
        }
    }

    func prepareResolve() async {
        guard let project = selectedProject else { return }
        await perform("Preparing Resolve") {
            let result = try await backend.scaffold(project: project, timelineFPS: 30)
            resolveMessage = result.frameRatesMatch
                ? "Connected: \(result.project), \(result.sourceFiles) originals"
                : "Action needed: Project Settings > Master Settings > Playback frame rate = \(result.timelineFPS ?? 30)"
            log(resolveMessage, error: !result.frameRatesMatch)
        }
    }

    func search() async {
        guard let project = selectedProject, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        await perform("Searching \(project.name)") {
            if searchMode == .visual {
                moments = try await backend.moments(
                    projectRoot: project.rootPath,
                    query: query,
                    minScore: minScore,
                    pre: preHandle,
                    post: postHandle,
                    minimum: minimumDuration
                )
            } else {
                moments = try await backend.transcriptMoments(
                    projectRoot: project.rootPath,
                    query: query,
                    pre: preHandle,
                    post: postHandle,
                    minimum: minimumDuration
                )
            }
            timelineName = defaultTimelineName(query)
            log("\(query): \(moments.count) handled moment(s)")
        }
    }

    func transcribeSelectedProject() async {
        guard var project = selectedProject else { return }
        await perform("Transcribing (project.name)") {
            let status = try await backend.transcribe(projectRoot: project.rootPath, source: project.sourcePath)
            project.indexedAssets = status.assets
            project.visualSamples = status.visualSamples
            project.transcripts = status.transcripts
            upsertProject(project)
            log("Created timed transcripts for \(status.transcripts) clip(s)")
        }
    }

    func createSelects() async {
        guard let project = selectedProject, !query.isEmpty, !timelineName.isEmpty else { return }
        await perform("Creating \(timelineName)") {
            let result: SelectsResult
            if searchMode == .visual {
                result = try await backend.createSelects(
                    projectRoot: project.rootPath,
                    query: query,
                    name: timelineName,
                    minScore: minScore,
                    pre: preHandle,
                    post: postHandle,
                    minimum: minimumDuration
                )
            } else {
                result = try await backend.createTranscriptSelects(
                    projectRoot: project.rootPath,
                    query: query,
                    name: timelineName,
                    pre: preHandle,
                    post: postHandle,
                    minimum: minimumDuration
                )
            }
            log("Created \(result.timeline) in Resolve with \(result.rangesAppended) source ranges")
            resolveMessage = "Created \(result.timeline)"
        }
    }

    func refreshSelectedProject() async {
        guard var project = selectedProject else { return }
        do {
            let status = try await backend.status(projectRoot: project.rootPath)
            project.indexedAssets = status.assets
            project.visualSamples = status.visualSamples
            project.transcripts = status.transcripts
            upsertProject(project)
        } catch { }
    }

    private func perform(_ title: String, operation: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        progressMessage = title
        log(title)
        defer { isBusy = false; progressMessage = "Ready" }
        do { try await operation() }
        catch {
            errorMessage = error.localizedDescription
            log(error.localizedDescription, error: true)
        }
    }

    func log(_ message: String, error: Bool = false) {
        activity.insert(ActivityEntry(message: message, isError: error), at: 0)
    }

    private func upsertProject(_ project: ProjectRecord) {
        if let index = projects.firstIndex(where: { $0.rootPath == project.rootPath }) {
            let replacement = ProjectRecord(
                id: projects[index].id,
                name: project.name,
                rootPath: project.rootPath,
                sourcePath: project.sourcePath,
                kind: project.kind,
                createdAt: projects[index].createdAt,
                indexedAssets: project.indexedAssets,
                visualSamples: project.visualSamples,
                transcripts: project.transcripts
            )
            projects[index] = replacement
            selectedProjectID = replacement.id
        } else {
            projects.append(project)
            selectedProjectID = project.id
        }
        saveProjects()
    }

    private func defaultTimelineName(_ query: String) -> String {
        let words = query.uppercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(words).split(separator: " ").joined(separator: " ") + " SELECTS"
    }

    private static var projectsURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Clip Resolved/projects.json")
    }

    private static func loadProjects() -> [ProjectRecord] {
        guard let data = try? Data(contentsOf: projectsURL) else { return [] }
        return (try? JSONDecoder().decode([ProjectRecord].self, from: data)) ?? []
    }

    private func saveProjects() {
        let url = Self.projectsURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(projects) { try? data.write(to: url, options: .atomic) }
    }
}
