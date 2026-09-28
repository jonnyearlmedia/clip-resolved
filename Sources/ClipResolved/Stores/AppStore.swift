import Foundation
import Observation
import OffloadCore
import OffloadEngine

@MainActor
@Observable
final class AppStore {
    var selection: WorkspaceSection = .project
    var sourcePath = ""
    var scanPayload: ScanPayload?
    var shootGroups: [ShootGroup] = []
    var projects: [ProjectRecord] = []
    var selectedProjectID: ProjectRecord.ID?
    var ingestDestinationProjectID: ProjectRecord.ID?
    var query = ""
    var searchMode: SearchMode = .visual
    var timelineName = ""
    var moments: [MomentResult] = []
    var previewEvidence: ChatEvidence?
    var cards: [CardInfo] = []
    var activity: [ActivityEntry] = []
    var chatMessages: [ChatMessage] = []
    var chatMemories: [ChatMemoryItem] = []
    var pendingChatAction: PendingChatAction?
    var isChatBusy = false
    var claudeStatus = "Checking Claude…"
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
    private let claude = ClaudeChatService()
    private let offloader = VerifiedOffloadService()
    private let watcher = CardWatcher()
    private var cardTask: Task<Void, Never>?

    var selectedProject: ProjectRecord? {
        guard let selectedProjectID else { return projects.first }
        return projects.first { $0.id == selectedProjectID }
    }

    var selectedProjectMessages: [ChatMessage] {
        guard let projectID = selectedProject?.id else { return [] }
        return chatMessages.filter { $0.projectID == projectID }
    }

    var selectedProjectMemories: [ChatMemoryItem] {
        guard let projectID = selectedProject?.id else {
            return chatMemories.filter { $0.scope == .global }
        }
        return chatMemories.filter {
            $0.scope == .global || ($0.scope == .project && $0.projectID == projectID)
        }
    }

    init(startServices: Bool = true) {
        activeProjectsRoot = UserDefaults.standard.string(forKey: "activeProjectsRoot") ?? "/Volumes/Extreme SSD/ACTIVE PROJECTS"
        gapHours = UserDefaults.standard.object(forKey: "gapHours") as? Double ?? 3.0
        sampleInterval = UserDefaults.standard.object(forKey: "sampleInterval") as? Double ?? 2.0
        minScore = UserDefaults.standard.object(forKey: "minScore") as? Double ?? 0.24
        preHandle = UserDefaults.standard.object(forKey: "preHandle") as? Double ?? 2.0
        postHandle = UserDefaults.standard.object(forKey: "postHandle") as? Double ?? 3.0
        minimumDuration = UserDefaults.standard.object(forKey: "minimumDuration") as? Double ?? 6.0
        projects = Self.loadProjects()
        chatMessages = Self.backfillSuggestedActions(Self.loadChatMessages())
        chatMemories = Self.loadChatMemories()
        saveChatMessages()
        if projects.isEmpty {
            let osaka = "/Volumes/Extreme SSD/ACTIVE PROJECTS/OSAKA"
            if FileManager.default.fileExists(atPath: osaka) {
                projects = [ProjectRecord(name: "OSAKA", rootPath: osaka, sourcePath: osaka + "/RAW FOOTAGE", kind: .client)]
                saveProjects()
            }
        }
        selectedProjectID = projects.first?.id
        selection = projects.isEmpty ? .ingest : .project
        if startServices {
            startCardWatcher()
            Task { await refreshClaudeStatus() }
        } else {
            claudeStatus = "Claude connected"
        }
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
                ShootGroup(
                    id: $0.id,
                    name: $0.suggestedName,
                    kind: .client,
                    sourceLabel: $0.sourceKind == .audio
                        ? ProjectRecord.inferSourceLabel(sourcePath, kind: .audio)
                        : ProjectRecord.inferSourceLabel(sourcePath),
                    sourceKind: $0.sourceKind,
                    files: $0.files,
                    start: $0.start,
                    end: $0.end
                )
            }
            log("Found \(payload.videoCount) videos in \(payload.groups.count) proposed shoot group(s)")
            if payload.audioCount > 0 {
                log("Found \(payload.audioCount) external audio file(s)")
            }
            if !payload.unassignedSidecars.isEmpty {
                log("Kept \(payload.unassignedSidecars.count) unassigned sidecar(s) untouched")
            }
        }
    }

    func move(file: ScannedFile, from sourceID: String, to destinationID: String) {
        guard sourceID != destinationID,
              let sourceIndex = shootGroups.firstIndex(where: { $0.id == sourceID }),
              let destinationIndex = shootGroups.firstIndex(where: { $0.id == destinationID }),
              shootGroups[sourceIndex].sourceKind == shootGroups[destinationIndex].sourceKind,
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
                sourceLabel: shootGroups[sourceIndex].sourceLabel,
                sourceKind: shootGroups[sourceIndex].sourceKind,
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
              let destinationIndex = shootGroups.firstIndex(where: { $0.id == destinationID }),
              shootGroups[sourceIndex].sourceKind == shootGroups[destinationIndex].sourceKind else { return }
        let files = shootGroups[sourceIndex].files
        shootGroups[destinationIndex].files.append(contentsOf: files)
        shootGroups.remove(at: sourceIndex)
        log("Merged shoot groups; every scanned file remains assigned")
    }

    func confirmAndIngest() async {
        guard !sourcePath.isEmpty, !shootGroups.isEmpty else { return }
        let sourceURL = URL(fileURLWithPath: sourcePath)
        await perform("Verified ingest") {
            for group in shootGroups where !group.files.isEmpty {
                let existingProject = ingestDestinationProjectID.flatMap { destinationID in
                    projects.first { $0.id == destinationID }
                }
                if group.sourceKind == .audio, existingProject == nil {
                    throw BackendError.invalidOutput(
                        "Choose an existing project before importing an audio-only Mic card."
                    )
                }
                let volumeID = cards.first(where: { $0.mountPath == sourcePath })?.volumeUUID ?? "manual-\(sourceURL.lastPathComponent)"
                let result = try await offloader.offload(
                    group: group,
                    sourceRoot: sourceURL,
                    activeProjectsRoot: URL(fileURLWithPath: activeProjectsRoot),
                    volumeUUID: volumeID,
                    destinationProjectRoot: existingProject.map { URL(fileURLWithPath: $0.rootPath) },
                    progress: { [weak self] message in Task { @MainActor in self?.progressMessage = message } }
                )
                var project: ProjectRecord
                if var existingProject {
                    if !existingProject.sources.contains(where: { $0.path == result.mediaRoot.path }) {
                        existingProject.sources.append(
                            ProjectSourceRecord(
                                label: group.sourceLabel,
                                path: result.mediaRoot.path,
                                kind: group.sourceKind
                            )
                        )
                    }
                    if group.sourceKind == .camera, existingProject.sourcePath.isEmpty {
                        existingProject.sourcePath = result.mediaRoot.path
                    }
                    project = existingProject
                } else {
                    let profile: ShootProfile = group.kind == .personal ? .event : .communityStory
                    project = ProjectRecord(
                        name: group.name,
                        rootPath: result.projectRoot.path,
                        sourcePath: result.mediaRoot.path,
                        kind: group.kind,
                        profile: profile,
                        sources: [
                            ProjectSourceRecord(
                                label: group.sourceLabel,
                                path: result.mediaRoot.path,
                                kind: group.sourceKind
                            )
                        ]
                    )
                }
                log("\(group.name): \(result.filesVerified) files copied and checksum-verified into \(project.name)")
                if group.sourceKind == .camera {
                    let status = try await backend.index(
                        projectRoot: project.rootPath,
                        source: result.mediaRoot.path,
                        sourceLabel: group.sourceLabel,
                        interval: sampleInterval
                    )
                    project.indexedAssets = status.assets
                    project.visualSamples = status.visualSamples
                    project.transcripts = status.transcripts
                } else {
                    try await backend.registerSource(
                        projectRoot: project.rootPath,
                        source: result.mediaRoot.path,
                        sourceLabel: group.sourceLabel,
                        kind: .audio
                    )
                }
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
            selection = .project
        }
    }

    func addExistingProject(
        name: String,
        root: String,
        source: String,
        kind: ProjectKind,
        profile: ShootProfile? = nil
    ) async {
        guard !name.isEmpty, !root.isEmpty, !source.isEmpty else { return }
        let label = ProjectRecord.inferSourceLabel(source)
        var project = ProjectRecord(
            name: name,
            rootPath: root,
            sourcePath: source,
            kind: kind,
            profile: profile,
            sources: [ProjectSourceRecord(label: label, path: source)]
        )
        do {
            try await backend.registerSource(
                projectRoot: root,
                source: source,
                sourceLabel: label,
                kind: .camera
            )
            let status = try await backend.status(projectRoot: root)
            project.indexedAssets = status.assets
            project.visualSamples = status.visualSamples
            project.transcripts = status.transcripts
        } catch { }
        upsertProject(project)
        selection = .project
    }

    func createProject(name: String, parentRoot: String, kind: ProjectKind, profile: ShootProfile) {
        errorMessage = nil
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              !cleanName.contains("/"),
              cleanName != ".",
              cleanName != ".." else {
            errorMessage = "Choose a project name without slashes."
            return
        }
        let root = URL(fileURLWithPath: parentRoot)
            .appendingPathComponent(kind.rawValue, isDirectory: true)
            .appendingPathComponent(cleanName, isDirectory: true)
        do {
            for relative in ["Media", "Audio", "Assets", "Project", ".clip-resolved/analysis", ".clip-resolved/manifests"] {
                try FileManager.default.createDirectory(
                    at: root.appendingPathComponent(relative, isDirectory: true),
                    withIntermediateDirectories: true
                )
            }
            let project = ProjectRecord(
                name: cleanName,
                rootPath: root.path,
                sourcePath: "",
                kind: kind,
                profile: profile,
                sources: []
            )
            upsertProject(project)
            ingestDestinationProjectID = project.id
            selection = .project
            log("Created empty \(profile.rawValue) project: \(cleanName)")
        } catch {
            errorMessage = "Could not create project: \(error.localizedDescription)"
        }
    }

    func indexSelectedProject() async {
        guard var project = selectedProject else { return }
        await perform("Indexing \(project.name)") {
            let cameraSources = project.sources.filter { $0.kind == .camera }
            guard !cameraSources.isEmpty else {
                throw BackendError.invalidOutput("This project has no registered camera source.")
            }
            var status = try await backend.status(projectRoot: project.rootPath)
            for source in cameraSources {
                status = try await backend.index(
                    projectRoot: project.rootPath,
                    source: source.path,
                    sourceLabel: source.label,
                    interval: sampleInterval
                )
            }
            project.indexedAssets = status.assets
            project.visualSamples = status.visualSamples
            project.transcripts = status.transcripts
            upsertProject(project)
            log("Indexed \(status.assets) clips / \(status.visualSamples) visual samples")
        }
    }

    func prepareResolve() async {
        guard let project = selectedProject else { return }
        guard project.sources.contains(where: { $0.kind == .camera }) else {
            errorMessage = "Add at least one camera source before preparing Resolve."
            return
        }
        await perform("Preparing Resolve") {
            for source in project.sources {
                try await backend.registerSource(
                    projectRoot: project.rootPath,
                    source: source.path,
                    sourceLabel: source.label,
                    kind: source.kind
                )
            }
            let result = try await backend.scaffold(project: project, timelineFPS: 30)
            resolveMessage = result.frameRatesMatch
                ? "Connected: \(result.project), \(result.sourceFiles) originals"
                : "Action needed: Project Settings > Master Settings > Playback frame rate = \(result.timelineFPS ?? 30)"
            log(resolveMessage, error: !result.frameRatesMatch)
        }
    }

    func addSource(label: String, path: String, kind: ProjectSourceKind, indexNow: Bool) async {
        guard var project = selectedProject else { return }
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanLabel.isEmpty, !cleanPath.isEmpty else { return }
        guard FileManager.default.fileExists(atPath: cleanPath) else {
            errorMessage = "That source folder does not exist: \(cleanPath)"
            return
        }
        await perform("Adding \(cleanLabel)") {
            try await backend.registerSource(
                projectRoot: project.rootPath,
                source: cleanPath,
                sourceLabel: cleanLabel,
                kind: kind
            )
            if let existing = project.sources.firstIndex(where: { $0.path == cleanPath }) {
                project.sources[existing].label = cleanLabel
                project.sources[existing].kind = kind
            } else {
                project.sources.append(ProjectSourceRecord(label: cleanLabel, path: cleanPath, kind: kind))
            }
            if kind == .camera, project.sourcePath.isEmpty {
                project.sourcePath = cleanPath
            }
            if kind == .camera, indexNow {
                let status = try await backend.index(
                    projectRoot: project.rootPath,
                    source: cleanPath,
                    sourceLabel: cleanLabel,
                    interval: sampleInterval
                )
                project.indexedAssets = status.assets
                project.visualSamples = status.visualSamples
                project.transcripts = status.transcripts
            }
            upsertProject(project)
            log("Added \(cleanLabel) to \(project.name)\(indexNow && kind == .camera ? " and indexed it" : "")")
        }
    }

    func setSelectedProjectProfile(_ profile: ShootProfile) {
        guard var project = selectedProject else { return }
        project.profile = profile
        upsertProject(project)
    }

    func syncExternalAudio() async {
        guard let project = selectedProject else { return }
        await perform("Syncing external audio in Resolve") {
            let result = try await backend.syncAudio(projectRoot: project.rootPath)
            resolveMessage = "Synced \(result.videos) video clips with \(result.audioFiles) audio clips"
            log(resolveMessage)
        }
    }

    func createMulticam(syncMode: String = "audio") async {
        guard let project = selectedProject else { return }
        let name = "\(project.name.uppercased()) MULTICAM"
        await perform("Creating multicam in Resolve") {
            let result = try await backend.createMulticam(
                projectRoot: project.rootPath,
                name: name,
                syncMode: syncMode
            )
            resolveMessage = "Created \(result.multicamClipsCreated) multicam clip(s)"
            log("\(resolveMessage) using \(syncMode) sync")
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
        await perform("Transcribing \(project.name)") {
            let cameraSources = project.sources.filter { $0.kind == .camera }
            guard !cameraSources.isEmpty else {
                throw BackendError.invalidOutput("This project has no registered camera source.")
            }
            var status = try await backend.status(projectRoot: project.rootPath)
            for source in cameraSources {
                status = try await backend.transcribe(projectRoot: project.rootPath, source: source.path)
            }
            project.indexedAssets = status.assets
            project.visualSamples = status.visualSamples
            project.transcripts = status.transcripts
            upsertProject(project)
            log("Created timed transcripts for \(status.transcripts) clip(s)")
        }
    }

    func refreshClaudeStatus() async {
        claudeStatus = await claude.availability()
    }

    func sendChat(_ rawMessage: String) async {
        guard let project = selectedProject, !isBusy, !isChatBusy else { return }
        let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        pendingChatAction = nil
        appendChat(projectID: project.id, role: .user, text: message)
        isChatBusy = true
        progressMessage = "Asking Claude about \(project.name)"
        defer {
            isChatBusy = false
            progressMessage = "Ready"
        }

        do {
            let history = selectedProjectMessages.dropLast()
            let intent = try await claude.interpret(
                message: message,
                project: project,
                history: Array(history),
                memories: selectedProjectMemories
            )
            let changedPreferences = applyPreferenceUpdates(intent)
            if !changedPreferences.isEmpty {
                appendChat(
                    projectID: project.id,
                    role: .assistant,
                    text: "Updated your saved SELECTS defaults: \(changedPreferences.joined(separator: ", "))."
                )
            }
            let savedCount = applyMemoryUpdates(intent.memoryUpdates, projectID: project.id)
            if savedCount > 0 {
                appendChat(
                    projectID: project.id,
                    role: .assistant,
                    text: "Remembered \(savedCount) \(savedCount == 1 ? "detail" : "details"). You can review or delete \(savedCount == 1 ? "it" : "them") in Memory."
                )
            }

            switch intent.action {
            case .answer:
                appendChat(projectID: project.id, role: .assistant, text: intent.message)
            case .searchVisual:
                await runChatSearch(
                    project: project,
                    query: intent.query ?? message,
                    displayQuery: message,
                    mode: .visual,
                    timelineName: intent.timelineName
                )
            case .searchTranscript:
                await runChatSearch(
                    project: project,
                    query: intent.query ?? message,
                    displayQuery: message,
                    mode: .spoken,
                    timelineName: intent.timelineName
                )
            case .proposeSelects:
                await runChatSearch(
                    project: project,
                    query: intent.query ?? message,
                    displayQuery: message,
                    mode: intent.searchMode ?? .visual,
                    timelineName: intent.timelineName
                )
            case .proposeSmartSelects:
                appendChat(projectID: project.id, role: .assistant, text: intent.message)
                pendingChatAction = PendingChatAction(
                    projectID: project.id,
                    kind: .createSmartSelects,
                    title: "Build \(project.profile.packageTitle) in Resolve",
                    query: nil,
                    timelineName: nil,
                    searchMode: nil,
                    profile: intent.profile ?? project.profile.backendName,
                    rangeCount: 0
                )
            case .prepareResolve:
                appendChat(projectID: project.id, role: .assistant, text: intent.message)
                pendingChatAction = PendingChatAction(
                    projectID: project.id,
                    kind: .prepareResolve,
                    title: "Prepare \(project.name) in Resolve",
                    query: nil,
                    timelineName: nil,
                    searchMode: nil,
                    profile: nil,
                    rangeCount: 0
                )
            }
        } catch {
            appendChat(
                projectID: project.id,
                role: .assistant,
                text: "I couldn't reach Claude: \(error.localizedDescription)"
            )
            log(error.localizedDescription, error: true)
        }
    }

    private func runChatSearch(
        project: ProjectRecord,
        query searchQuery: String,
        displayQuery: String,
        mode: SearchMode,
        timelineName requestedName: String?
    ) async {
        do {
            let results: [MomentResult]
            if mode == .visual {
                results = try await backend.moments(
                    projectRoot: project.rootPath,
                    query: searchQuery,
                    minScore: minScore,
                    pre: preHandle,
                    post: postHandle,
                    minimum: minimumDuration
                )
            } else {
                results = try await backend.transcriptMoments(
                    projectRoot: project.rootPath,
                    query: searchQuery,
                    pre: preHandle,
                    post: postHandle,
                    minimum: minimumDuration
                )
            }

            query = searchQuery
            searchMode = mode
            moments = results
            timelineName = normalizedChatTimelineName(
                requestedName,
                displayQuery: displayQuery,
                fallbackQuery: searchQuery
            )
            let evidence = results.prefix(12).map {
                ChatEvidence(
                    sourcePath: $0.sourcePath,
                    start: $0.handledStart ?? $0.detectedStart,
                    end: $0.handledEnd ?? $0.detectedEnd,
                    score: $0.score,
                    transcript: $0.transcript
                )
            }
            let summary: String
            if results.isEmpty {
                summary = mode == .spoken && (project.transcripts ?? 0) == 0
                    ? "There are no timed transcripts for this project yet. Run Transcribe Audio, then ask again."
                    : "I found no sufficiently relevant handled ranges for “\(searchQuery)”. Try different wording or lower the search threshold."
            } else {
                let sourceCount = Set(results.map(\.sourcePath)).count
                let pre = preHandle.formatted(.number.precision(.fractionLength(0...1)))
                let post = postHandle.formatted(.number.precision(.fractionLength(0...1)))
                let minimum = minimumDuration.formatted(.number.precision(.fractionLength(0...1)))
                summary = "I searched the existing local index and found \(results.count) handled source range\(results.count == 1 ? "" : "s") across \(sourceCount) original clip\(sourceCount == 1 ? "" : "s") for “\(displayQuery)”. These use \(pre)s before, \(post)s after, and a \(minimum)s minimum. Review the strongest timestamped matches below, or create \(timelineName) plus its complete NOT SELECTED review timeline in Resolve."
            }
            let suggestedAction = results.isEmpty ? nil : ChatSuggestedAction(
                query: searchQuery,
                timelineName: timelineName,
                searchMode: mode,
                rangeCount: results.count
            )
            appendChat(
                projectID: project.id,
                role: .assistant,
                text: summary,
                evidence: Array(evidence),
                suggestedAction: suggestedAction
            )
            log("Claude search — \(searchQuery): \(results.count) handled moment(s)")

            if !results.isEmpty {
                pendingChatAction = PendingChatAction(
                    projectID: project.id,
                    kind: .createSelects,
                    title: "Create \(timelineName) in Resolve",
                    query: searchQuery,
                    timelineName: timelineName,
                    searchMode: mode,
                    profile: nil,
                    rangeCount: results.count
                )
            }
        } catch {
            appendChat(projectID: project.id, role: .assistant, text: "The footage search failed: \(error.localizedDescription)")
            log(error.localizedDescription, error: true)
        }
    }

    func confirmPendingChatAction() async {
        guard let action = pendingChatAction,
              let project = projects.first(where: { $0.id == action.projectID }),
              !isBusy, !isChatBusy else { return }
        pendingChatAction = nil
        isChatBusy = true
        progressMessage = action.title
        defer {
            isChatBusy = false
            progressMessage = "Ready"
        }

        do {
            switch action.kind {
            case .prepareResolve:
                let result = try await backend.scaffold(project: project, timelineFPS: 30)
                resolveMessage = result.frameRatesMatch
                    ? "Connected: \(result.project), \(result.sourceFiles) originals"
                    : "Action needed: set Resolve Playback frame rate to \(result.timelineFPS ?? 30)"
                appendChat(
                    projectID: project.id,
                    role: .assistant,
                    text: result.frameRatesMatch
                        ? "Resolve is prepared with \(result.sourceFiles) original source files."
                        : "Resolve was prepared, but its timeline and playback frame rates do not match. Fix that in Project Settings before creating SELECTS."
                )
            case .createSelects:
                guard let searchQuery = action.query,
                      let name = action.timelineName,
                      let mode = action.searchMode else { return }
                let result: SelectsResult
                if mode == .visual {
                    result = try await backend.createSelects(
                        projectRoot: project.rootPath,
                        query: searchQuery,
                        name: name,
                        minScore: minScore,
                        pre: preHandle,
                        post: postHandle,
                        minimum: minimumDuration
                    )
                } else {
                    result = try await backend.createTranscriptSelects(
                        projectRoot: project.rootPath,
                        query: searchQuery,
                        name: name,
                        pre: preHandle,
                        post: postHandle,
                        minimum: minimumDuration
                    )
                }
                resolveMessage = result.remainderTimeline == nil
                    ? "Created \(result.timeline)"
                    : "Created SELECTS + NOT SELECTED"
                let remainderSummary = result.remainderTimeline.map {
                    " I also created \($0) with \(result.remainderRangesAppended ?? 0) exact source ranges covering everything outside the main SELECTS."
                } ?? ""
                appendChat(
                    projectID: project.id,
                    role: .assistant,
                    text: "Created \(result.timeline) in Resolve with \(result.rangesAppended) exact source range\(result.rangesAppended == 1 ? "" : "s").\(remainderSummary)"
                )
                log("Created \(result.timeline) from project chat")
            case .createSmartSelects:
                let result = try await backend.createSmartSelects(
                    projectRoot: project.rootPath,
                    profile: action.profile ?? project.profile.backendName,
                    minScore: minScore,
                    pre: preHandle,
                    post: postHandle,
                    minimum: minimumDuration
                )
                resolveMessage = "Created \(result.categoryTimelinesCreated) organized SELECTS timelines"
                appendChat(
                    projectID: project.id,
                    role: .assistant,
                    text: smartSelectsSummary(result)
                )
                log("Created \(project.profile.packageTitle) from project chat")
            case .openTimeline:
                guard let name = action.timelineName else { return }
                let result = try await backend.openTimeline(name)
                resolveMessage = "Opened \(result.timeline)"
                appendChat(
                    projectID: project.id,
                    role: .assistant,
                    text: "Opened the existing \(result.timeline) timeline in Resolve. No duplicate timeline was created."
                )
                log("Opened existing Resolve timeline: \(result.timeline)")
            }
        } catch {
            errorMessage = error.localizedDescription
            appendChat(projectID: project.id, role: .assistant, text: "I couldn't complete that Resolve action: \(error.localizedDescription)")
            log(error.localizedDescription, error: true)
        }
    }

    func cancelPendingChatAction() {
        guard let action = pendingChatAction else { return }
        pendingChatAction = nil
        appendChat(projectID: action.projectID, role: .assistant, text: "Cancelled. Resolve was not changed.")
    }

    func stageSuggestedChatAction(_ suggested: ChatSuggestedAction, projectID: UUID) async {
        guard projects.contains(where: { $0.id == projectID }) else { return }
        do {
            let state = try await backend.resolveTimelines()
            let exists = state.timelines.contains(suggested.timelineName)
            pendingChatAction = PendingChatAction(
                projectID: projectID,
                kind: exists ? .openTimeline : .createSelects,
                title: exists
                    ? "Open existing \(suggested.timelineName) in Resolve"
                    : "Create \(suggested.timelineName) in Resolve",
                query: suggested.query,
                timelineName: suggested.timelineName,
                searchMode: suggested.searchMode,
                profile: nil,
                rangeCount: suggested.rangeCount
            )
        } catch {
            errorMessage = error.localizedDescription
            log(error.localizedDescription, error: true)
        }
    }

    func clearSelectedProjectChat() {
        guard let projectID = selectedProject?.id else { return }
        chatMessages.removeAll { $0.projectID == projectID }
        pendingChatAction = nil
        saveChatMessages()
    }

    func addMemory(scope: ChatMemoryScope, category: String, content: String) {
        let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanContent.isEmpty else { return }
        let projectID = scope == .project ? selectedProject?.id : nil
        guard scope == .global || projectID != nil else { return }
        let item = ChatMemoryItem(
            scope: scope,
            projectID: projectID,
            category: cleanCategory.isEmpty ? "Preference" : cleanCategory,
            content: cleanContent
        )
        guard !containsMemoryLike(item) else { return }
        chatMemories.append(item)
        saveChatMemories()
    }

    func deleteMemory(_ id: ChatMemoryItem.ID) {
        chatMemories.removeAll { $0.id == id }
        saveChatMemories()
    }

    func clearSelectedProjectMemory() {
        guard let projectID = selectedProject?.id else { return }
        chatMemories.removeAll { $0.scope == .project && $0.projectID == projectID }
        saveChatMemories()
    }

    @discardableResult
    private func applyMemoryUpdates(_ updates: [ClaudeMemoryUpdate], projectID: UUID) -> Int {
        var added = 0
        for update in updates {
            let category = update.category.trimmingCharacters(in: .whitespacesAndNewlines)
            let content = update.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            let item = ChatMemoryItem(
                scope: update.scope,
                projectID: update.scope == .project ? projectID : nil,
                category: category.isEmpty ? "Preference" : category,
                content: content
            )
            guard !containsMemoryLike(item) else { continue }
            chatMemories.append(item)
            added += 1
        }
        if added > 0 { saveChatMemories() }
        return added
    }

    private func applyPreferenceUpdates(_ intent: ClaudeIntent) -> [String] {
        var changes: [String] = []
        if let requested = intent.preHandleSeconds {
            let value = min(max(requested, 0), 15)
            if preHandle != value {
                preHandle = value
                changes.append("\(value.formatted(.number.precision(.fractionLength(0...1))))s before")
            }
        }
        if let requested = intent.postHandleSeconds {
            let value = min(max(requested, 0), 15)
            if postHandle != value {
                postHandle = value
                changes.append("\(value.formatted(.number.precision(.fractionLength(0...1))))s after")
            }
        }
        if let requested = intent.minimumDurationSeconds {
            let value = min(max(requested, 1), 30)
            if minimumDuration != value {
                minimumDuration = value
                changes.append("\(value.formatted(.number.precision(.fractionLength(0...1))))s minimum range")
            }
        }
        return changes
    }

    private func containsMemoryLike(_ candidate: ChatMemoryItem) -> Bool {
        let normalized = candidate.content.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return chatMemories.contains { item in
            item.scope == candidate.scope
                && item.projectID == candidate.projectID
                && item.content.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    .trimmingCharacters(in: .whitespacesAndNewlines) == normalized
        }
    }

    private func appendChat(
        projectID: UUID,
        role: ChatRole,
        text: String,
        evidence: [ChatEvidence] = [],
        suggestedAction: ChatSuggestedAction? = nil
    ) {
        chatMessages.append(
            ChatMessage(
                projectID: projectID,
                role: role,
                text: text,
                evidence: evidence,
                suggestedAction: suggestedAction
            )
        )
        saveChatMessages()
    }

    private func normalizedTimelineName(_ requested: String?, query: String) -> String {
        let cleaned = requested?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cleaned.isEmpty {
            return cleaned.uppercased().hasSuffix("SELECTS") ? cleaned : "\(cleaned) SELECTS"
        }
        return defaultTimelineName(query)
    }

    private func normalizedChatTimelineName(
        _ requested: String?,
        displayQuery: String,
        fallbackQuery: String
    ) -> String {
        let supplied = requested?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !supplied.isEmpty {
            return normalizedTimelineName(supplied, query: fallbackQuery)
        }

        var cleaned = displayQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let leadingRequest = #"(?i)^(please\s+)?(find|show\s+me|give\s+me|search\s+for|look\s+for)\s+"#
        cleaned = cleaned.replacingOccurrences(
            of: leadingRequest,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"(?i)\s+(in|from)\s+(this|the)\s+footage\s*[?.!]*$"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return defaultTimelineName(cleaned.isEmpty ? fallbackQuery : cleaned)
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
            if let remainder = result.remainderTimeline {
                log("Created \(remainder) with \(result.remainderRangesAppended ?? 0) unselected source ranges")
                resolveMessage = "Created SELECTS + NOT SELECTED"
            } else {
                resolveMessage = "Created \(result.timeline)"
            }
        }
    }

    func createSmartSelects(profile: String? = nil) async {
        guard let project = selectedProject else { return }
        await perform("Building professional SELECTS package") {
            let result = try await backend.createSmartSelects(
                projectRoot: project.rootPath,
                profile: profile ?? project.profile.backendName,
                minScore: minScore,
                pre: preHandle,
                post: postHandle,
                minimum: minimumDuration
            )
            resolveMessage = "Created \(result.categoryTimelinesCreated) organized SELECTS timelines"
            log(smartSelectsSummary(result))
        }
    }

    private func smartSelectsSummary(_ result: SmartSelectsResult) -> String {
        let created = result.categories.compactMap(\.timeline)
        let skipped = result.categories.filter { $0.timeline == nil }.map(\.name)
        var parts = [
            "Created \(result.stringoutTimeline) with all \(result.stringoutRangesAppended) indexed original clips in source order.",
            "Created \(result.categoryTimelinesCreated) category timeline\(result.categoryTimelinesCreated == 1 ? "" : "s") in Resolve: \(created.joined(separator: ", ")).",
            "\(result.remainderTimeline ?? "ALL FOOTAGE NOT SELECTED REVIEW") contains \(result.remainderRangesAppended) exact source range\(result.remainderRangesAppended == 1 ? "" : "s") outside the union of those categories."
        ]
        if !skipped.isEmpty {
            parts.append("Skipped empty categories: \(skipped.joined(separator: ", ")).")
        }
        parts.append(result.coverageComplete ? "The package accounts for the complete indexed source set." : "Coverage verification did not complete.")
        return parts.joined(separator: " ")
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
                profile: project.profile,
                sources: project.sources,
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

    private static var chatMessagesURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Clip Resolved/chat-messages.json")
    }

    private static var chatMemoriesURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Clip Resolved/chat-memories.json")
    }

    private static func loadProjects() -> [ProjectRecord] {
        guard let data = try? Data(contentsOf: projectsURL) else { return [] }
        return (try? JSONDecoder().decode([ProjectRecord].self, from: data)) ?? []
    }

    private static func loadChatMessages() -> [ChatMessage] {
        guard let data = try? Data(contentsOf: chatMessagesURL) else { return [] }
        return (try? JSONDecoder().decode([ChatMessage].self, from: data)) ?? []
    }

    private static func backfillSuggestedActions(_ messages: [ChatMessage]) -> [ChatMessage] {
        var lastUserMessage: [UUID: String] = [:]
        return messages.map { message in
            if message.role == .user {
                lastUserMessage[message.projectID] = message.text
                return message
            }
            guard message.suggestedAction == nil,
                  !message.evidence.isEmpty,
                  let request = lastUserMessage[message.projectID] else { return message }

            var phrase = request.trimmingCharacters(in: .whitespacesAndNewlines)
            phrase = phrase.replacingOccurrences(
                of: #"(?i)^(please\s+)?(find|show\s+me|give\s+me|search\s+for|look\s+for)\s+"#,
                with: "",
                options: .regularExpression
            )
            phrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if phrase.isEmpty { phrase = request }
            let words = phrase.uppercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
            let timeline = String(words).split(separator: " ").joined(separator: " ") + " SELECTS"
            let rangeCount = message.text
                .components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap(Int.init)
                .first ?? message.evidence.count
            let suggested = ChatSuggestedAction(
                query: phrase,
                timelineName: timeline,
                searchMode: message.evidence.contains { $0.transcript != nil } ? .spoken : .visual,
                rangeCount: rangeCount
            )
            return ChatMessage(
                id: message.id,
                projectID: message.projectID,
                role: message.role,
                text: message.text,
                evidence: message.evidence,
                suggestedAction: suggested,
                createdAt: message.createdAt
            )
        }
    }

    private static func loadChatMemories() -> [ChatMemoryItem] {
        guard let data = try? Data(contentsOf: chatMemoriesURL) else { return [] }
        return (try? JSONDecoder().decode([ChatMemoryItem].self, from: data)) ?? []
    }

    private func saveProjects() {
        let url = Self.projectsURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(projects) { try? data.write(to: url, options: .atomic) }
    }

    private func saveChatMessages() {
        let url = Self.chatMessagesURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(chatMessages) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func saveChatMemories() {
        let url = Self.chatMemoriesURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(chatMemories) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
