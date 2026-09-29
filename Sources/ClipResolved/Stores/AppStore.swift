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
    var selectedProjectID: ProjectRecord.ID? {
        didSet {
            if let selectedProjectID {
                UserDefaults.standard.set(selectedProjectID.uuidString, forKey: "selectedProjectID")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedProjectID")
            }
        }
    }
    /// A legacy launch hint used when the editor enters Import from a project.
    /// Once a source is scanned, destinations are stored per shoot below.
    var ingestDestinationProjectID: ProjectRecord.ID?
    var ingestDestinationProjectIDs: [String: ProjectRecord.ID] = [:]
    var ingestIncludedShootIDs: Set<String> = []
    var recorderProjectMatches: [String: RecorderProjectMatch] = [:]
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
    var completedIngestSummary: IngestCompletionSummary?
    var completedCleanupResult: VerifiedCleanupResult?

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
    private let cleanupService = VerifiedCleanupService()
    private let projectMediaRelocationService = ProjectMediaRelocationService()
    private let resolveApplication = ResolveApplicationService()
    private let watcher = CardWatcher()
    private var cardTask: Task<Void, Never>?
    private var pendingCardActivationTask: Task<Void, Never>?
    private var pendingCardPath: String?
    private var cardScanInProgressPath: String?
    private var preferredSourcePath: String?

    private struct ImportPlanSnapshot {
        let shootGroups: [ShootGroup]
        let destinationProjectIDs: [String: ProjectRecord.ID]
        let includedShootIDs: Set<String>
        let recorderProjectMatches: [String: RecorderProjectMatch]
    }

    private var importPlanBaseline: ImportPlanSnapshot?
    private var importPlanUndoStack: [ImportPlanSnapshot] = []
    private var importPlanRedoStack: [ImportPlanSnapshot] = []

    var canUndoImportPlan: Bool { !importPlanUndoStack.isEmpty }
    var canRedoImportPlan: Bool { !importPlanRedoStack.isEmpty }
    var canResetImportPlan: Bool {
        guard let baseline = importPlanBaseline else { return false }
        return shootGroups != baseline.shootGroups
            || ingestDestinationProjectIDs != baseline.destinationProjectIDs
            || ingestIncludedShootIDs != baseline.includedShootIDs
    }

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
        preferredSourcePath = UserDefaults.standard.string(forKey: "preferredSourcePath")
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
        let savedProjectID = UserDefaults.standard.string(forKey: "selectedProjectID").flatMap(UUID.init(uuidString:))
        selectedProjectID = projects.first(where: { $0.id == savedProjectID })?.id ?? projects.first?.id
        selection = projects.isEmpty ? .ingest : .project
        if let pending = Self.loadPendingIngestSummary() ?? Self.recoverRecentIngestSummary(projects: projects) {
            completedIngestSummary = pending
            sourcePath = pending.cleanupPlans.first?.sourceRoot ?? sourcePath
            selection = .ingest
            Self.savePendingIngestSummary(pending)
        }
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
                    guard Self.shouldRecognizeMountedMedia(
                        candidate.info,
                        isRemovable: candidate.isRemovable,
                        isEjectable: candidate.isEjectable,
                        isInternal: candidate.isInternal,
                        isNetwork: candidate.isNetwork
                    ) else { continue }
                    guard !isDestinationVolume(candidate.info.mountPath) else { continue }
                    let isNewlyListed = !cards.contains(where: { $0.volumeUUID == candidate.info.volumeUUID })
                    if isNewlyListed {
                        cards.append(candidate.info)
                    }
                    guard isNewlyListed else { continue }
                    if cardScanInProgressPath != nil {
                        // Disk Arbitration replays every already-mounted volume at
                        // launch. Keep the first automatic scan stable instead of
                        // switching sources after a long queued scan. The other
                        // cards remain visible with their own explicit Rescan button.
                        log("Detected media: \(candidate.info.volumeName). Ready when you choose it.")
                    } else {
                        let preferredIsQueued = pendingCardPath == preferredSourcePath
                        if preferredIsQueued, candidate.info.mountPath != preferredSourcePath {
                            log("Detected media: \(candidate.info.volumeName). Ready when you choose it.")
                            continue
                        }
                        // Mount callbacks for already-connected volumes arrive in
                        // a short burst at launch. Debounce that burst so we scan
                        // one source, preferring the source the editor last chose,
                        // instead of beginning a long scan for every mounted card.
                        pendingCardActivationTask?.cancel()
                        pendingCardPath = candidate.info.mountPath
                        log("Detected media: \(candidate.info.volumeName). Queued for automatic scan…")
                        pendingCardActivationTask = Task { @MainActor [weak self] in
                            guard let self else { return }
                            try? await Task.sleep(for: .milliseconds(900))
                            guard !Task.isCancelled else { return }
                            // Project status refresh and Claude availability checks
                            // may briefly own the shared busy state at launch. Wait
                            // behind that work instead of silently dropping the card.
                            while self.isBusy {
                                try? await Task.sleep(for: .milliseconds(200))
                                guard !Task.isCancelled else { return }
                            }
                            self.pendingCardActivationTask = nil
                            self.pendingCardPath = nil
                            self.cardScanInProgressPath = candidate.info.mountPath
                            self.log("Scanning \(candidate.info.volumeName) automatically…")
                            await self.activateDetectedMedia(candidate.info)
                            self.cardScanInProgressPath = nil
                        }
                    }
                case .volumeUnmounted(let uuid, _):
                    let removedCard = cards.first { $0.volumeUUID == uuid }
                    cards.removeAll { $0.volumeUUID == uuid }
                    let removedPath = removedCard.map {
                        URL(fileURLWithPath: $0.mountPath).standardizedFileURL.path
                    }
                    let activePath = URL(fileURLWithPath: sourcePath).standardizedFileURL.path
                    if let removedPath,
                       activePath == removedPath || activePath.hasPrefix(removedPath + "/") {
                        progressMessage = "Media disconnected. Ready for the next card."
                        selection = selectedProject == nil ? .ingest : .project
                        Task { @MainActor [weak self] in
                            await Task.yield()
                            guard let self else { return }
                            let currentPath = URL(fileURLWithPath: self.sourcePath).standardizedFileURL.path
                            guard currentPath == removedPath || currentPath.hasPrefix(removedPath + "/") else {
                                return
                            }
                            self.sourcePath = ""
                            self.scanPayload = nil
                            self.shootGroups = []
                        }
                    }
                    log("Media disconnected")
                }
            }
        }
    }

    /// Disk Arbitration calls both SD cards and ordinary USB hard drives
    /// "ejectable." Never use that flag alone to decide that a volume is capture
    /// media: it made archival drives containing MP4s eligible for an automatic
    /// recursive scan. Real removable media, camera-standard roots, and known
    /// recorder volumes remain automatic.
    nonisolated static func shouldRecognizeMountedMedia(
        _ info: CardInfo,
        isRemovable: Bool,
        isEjectable _: Bool,
        isInternal: Bool,
        isNetwork: Bool
    ) -> Bool {
        guard !isInternal, !isNetwork else { return false }
        if info.hasMediaRoot || isRemovable { return true }
        return isKnownRecorderVolumeName(info.volumeName)
    }

    nonisolated private static func isKnownRecorderVolumeName(_ value: String) -> Bool {
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let recorderNames = [
            "dji mic", "mic mini", "wireless go", "rode wireless",
            "tascam", "zoom h", "zoom f", "mixpre", "sound devices",
            "tentacle track",
        ]
        return recorderNames.contains { normalized.contains($0) }
    }

    func useCard(_ card: CardInfo) {
        Task { await activateDetectedMedia(card) }
    }

    func prepareDetectedMedia(_ card: CardInfo) -> Bool {
        guard !isDestinationVolume(card.mountPath) else { return false }
        // A newly inserted camera card may contain unrelated shoots from many
        // dates. Never inherit whichever project happened to be selected before
        // the card was connected; default to one new project per confirmed shoot.
        ingestDestinationProjectID = nil
        ingestDestinationProjectIDs = [:]
        ingestIncludedShootIDs = []
        recorderProjectMatches = [:]
        sourcePath = card.mountPath
        preferredSourcePath = card.mountPath
        UserDefaults.standard.set(card.mountPath, forKey: "preferredSourcePath")
        scanPayload = nil
        shootGroups = []
        selection = .ingest
        progressMessage = "Detected \(card.volumeName). Reading media metadata…"
        return true
    }

    private func activateDetectedMedia(_ card: CardInfo) async {
        guard prepareDetectedMedia(card) else { return }
        await scanSource()
    }

    func applySafeAutomaticDestination() {
        guard !shootGroups.isEmpty else { return }
        // Camera shoots default to independent projects. Recorder sessions do
        // not inherit the current project merely because it is selected; only
        // verified capture-time matching may attach one automatically below.
        ingestDestinationProjectID = nil
        for group in shootGroups {
            ingestDestinationProjectIDs.removeValue(forKey: group.id)
        }
    }

    func destinationProjectID(for shootID: String) -> ProjectRecord.ID? {
        ingestDestinationProjectIDs[shootID]
    }

    func setDestinationProjectID(_ projectID: ProjectRecord.ID?, for shootID: String) {
        if let projectID {
            ingestDestinationProjectIDs[shootID] = projectID
        } else {
            ingestDestinationProjectIDs.removeValue(forKey: shootID)
        }
    }

    func isShootIncluded(_ shootID: String) -> Bool {
        ingestIncludedShootIDs.contains(shootID)
    }

    func setShootIncluded(_ included: Bool, shootID: String) {
        if included {
            ingestIncludedShootIDs.insert(shootID)
        } else {
            ingestIncludedShootIDs.remove(shootID)
        }
    }

    var shootGroupsSelectedForIngest: [ShootGroup] {
        shootGroups.filter { ingestIncludedShootIDs.contains($0.id) && !$0.files.isEmpty }
    }

    func isVisualPreparationCurrent(_ project: ProjectRecord) -> Bool {
        guard let preparation = project.visualPreparation else { return false }
        return preparation.kind == .fullPackage
            && preparation.coverageComplete
            && preparation.indexedAssets == project.indexedAssets
            && project.indexedAssets > 0
            && preparation.mainTimelines.contains("ALL B-ROLL SELECTS")
            && !preparation.mainTimelines.isEmpty
    }

    func hasCurrentReviewedVisualSearch(_ project: ProjectRecord) -> Bool {
        guard let preparation = project.visualPreparation else { return false }
        return preparation.kind == .reviewedQuery
            && preparation.coverageComplete
            && preparation.indexedAssets == project.indexedAssets
            && project.indexedAssets > 0
            && !preparation.mainTimelines.isEmpty
    }

    static func recoveredVisualPreparation(
        project: ProjectRecord,
        state: ResolveTimelineState,
        suggestion: ChatSuggestedAction?
    ) -> VisualPreparationRecord? {
        guard state.project == project.resolveProjectName,
              project.indexedAssets > 0,
              let suggestion,
              suggestion.searchMode == .visual,
              state.timelines.contains(suggestion.timelineName) else { return nil }

        let suffix = " SELECTS"
        let base = suggestion.timelineName.uppercased().hasSuffix(suffix)
            ? String(suggestion.timelineName.dropLast(suffix.count))
            : suggestion.timelineName
        let reviewTimeline = "\(base) NOT SELECTED"
        guard state.timelines.contains(reviewTimeline) else { return nil }

        return VisualPreparationRecord(
            kind: .reviewedQuery,
            mainTimelines: [suggestion.timelineName],
            reviewTimeline: reviewTimeline,
            indexedAssets: project.indexedAssets,
            coverageComplete: true,
            createdAt: Date()
        )
    }

    static func recoveredFullVisualPackage(
        project: ProjectRecord,
        state: ResolveTimelineState
    ) -> VisualPreparationRecord? {
        guard state.project == project.resolveProjectName,
              project.indexedAssets > 0,
              state.timelines.contains("00 ALL RAW FOOTAGE STRINGOUT"),
              state.timelines.contains("ALL B-ROLL SELECTS"),
              state.timelines.contains("ALL FOOTAGE NOT SELECTED REVIEW") else { return nil }

        let expectedCategories: [String]
        switch project.profile {
        case .restaurant:
            expectedCategories = [
                "FOOD SHOTS SELECTS", "EXTERIOR STOREFRONT SELECTS",
                "INTERIOR DINING ROOM SELECTS", "DRINKS SELECTS",
                "SIGNAGE LOGO SELECTS", "JAPANESE FOOD CLOSE UPS SELECTS",
                "SAKE BOTTLES SELECTS",
            ]
        case .communityStory:
            expectedCategories = [
                "INTERVIEW SETUPS SELECTS", "PEOPLE COMMUNITY SELECTS",
                "PROCESS ACTION SELECTS", "PRODUCT FOOD SELECTS",
                "EXTERIOR LOCATION SELECTS", "INTERIOR ATMOSPHERE SELECTS",
                "DETAILS CUTAWAYS SELECTS",
            ]
        case .event:
            expectedCategories = [
                "CEREMONY KEY MOMENTS SELECTS", "SPEECHES TOASTS SELECTS",
                "FAMILY REACTIONS SELECTS", "GROUPS PORTRAITS SELECTS",
                "CANDID MOMENTS SELECTS", "DETAILS DECOR GIFTS SELECTS",
                "FOOD CAKE SELECTS", "VENUE ESTABLISHING SELECTS",
            ]
        }
        let createdCategories = expectedCategories.filter(state.timelines.contains)
        guard !createdCategories.isEmpty else { return nil }

        return VisualPreparationRecord(
            kind: .fullPackage,
            mainTimelines: ["ALL B-ROLL SELECTS"] + createdCategories,
            reviewTimeline: "ALL FOOTAGE NOT SELECTED REVIEW",
            indexedAssets: project.indexedAssets,
            coverageComplete: true,
            createdAt: Date()
        )
    }

    func latestVisualSuggestion(for projectID: UUID) -> ChatSuggestedAction? {
        chatMessages.reversed().compactMap { message -> ChatSuggestedAction? in
            guard message.projectID == projectID,
                  let action = message.suggestedAction,
                  action.searchMode == .visual else { return nil }
            return action
        }.first
    }

    private func isDestinationVolume(_ mountPath: String) -> Bool {
        let mount = URL(fileURLWithPath: mountPath).standardizedFileURL.path
        let destination = URL(fileURLWithPath: activeProjectsRoot).standardizedFileURL.path
        return destination == mount || destination.hasPrefix(mount + "/")
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
                    sourceLabel: inferredSourceLabel(for: $0),
                    sourceKind: $0.sourceKind,
                    files: $0.files,
                    start: $0.start,
                    end: $0.end
                )
            }
            // Scanning is review-only. Require the editor to opt into the exact
            // shoots that should be copied so a large card never defaults to a
            // full-card ingest when storage is limited.
            ingestIncludedShootIDs = []
            ingestDestinationProjectIDs = [:]
            recorderProjectMatches = [:]
            if let destinationID = ingestDestinationProjectID {
                for group in shootGroups {
                    ingestDestinationProjectIDs[group.id] = destinationID
                }
            }
            let sessionWord = payload.groups.count == 1 ? "session" : "sessions"
            log("Automatically separated \(payload.videoCount) videos and \(payload.audioCount) audio files into \(payload.groups.count) proposed \(sessionWord)")
            if payload.audioCount > 0 {
                log("Found \(payload.audioCount) external audio file(s)")
            }
            if !payload.unassignedSidecars.isEmpty {
                log("Kept \(payload.unassignedSidecars.count) unassigned sidecar(s) untouched")
            }
            if !payload.scanIssues.isEmpty {
                log("Blocked confirmation: \(payload.scanIssues.count) source file(s) could not be read safely")
            }
        }
        applySafeAutomaticDestination()
        await matchRecorderSessionsToProjects()
        setImportPlanBaseline()
    }

    private func matchRecorderSessionsToProjects() async {
        let recorderGroups = shootGroups.filter { $0.sourceKind == .audio && !$0.audioFiles.isEmpty }
        guard !recorderGroups.isEmpty else { return }

        struct CameraCandidate {
            let project: ProjectRecord
            let group: ScannedGroupPayload
        }

        var candidates: [CameraCandidate] = []
        await perform("Matching recorder sessions to camera projects") {
            for project in projects where project.indexedAssets > 0 {
                for source in project.sources where source.kind == .camera {
                    guard FileManager.default.fileExists(atPath: source.path) else { continue }
                    guard let payload = try? await backend.scan(source: source.path, gapHours: gapHours) else {
                        log("Could not inspect \(project.name)'s \(source.label) source while matching recorder audio")
                        continue
                    }
                    candidates.append(contentsOf: payload.groups
                        .filter { $0.videoCount > 0 }
                        .map { CameraCandidate(project: project, group: $0) })
                }
            }

            for recorder in recorderGroups {
                let ranked = candidates.compactMap { candidate -> (RecorderProjectMatch, Double)? in
                    guard let evidence = Self.recorderMatch(recorder: recorder, camera: candidate.group, project: candidate.project) else {
                        return nil
                    }
                    let timePenalty = Double(evidence.startDeltaSeconds + evidence.endDeltaSeconds) / 1_200
                    let countRatio = Double(min(evidence.recorderTakeCount, evidence.cameraTakeCount))
                        / Double(max(evidence.recorderTakeCount, evidence.cameraTakeCount))
                    return (evidence, countRatio - timePenalty)
                }
                .sorted { $0.1 > $1.1 }

                guard let best = ranked.first,
                      ranked.count == 1 || best.1 - ranked[1].1 >= 0.08 else { continue }
                recorderProjectMatches[recorder.id] = best.0
                ingestDestinationProjectIDs[recorder.id] = best.0.projectID

                // Auto-select only an exact match to the project the editor
                // deliberately had active. Other matches remain suggestions.
                if best.0.isExact, best.0.projectID == selectedProjectID {
                    ingestIncludedShootIDs.insert(recorder.id)
                    if let index = shootGroups.firstIndex(where: { $0.id == recorder.id }) {
                        shootGroups[index].name = "\(best.0.projectName) — \(shootGroups[index].sourceLabel) Audio"
                    }
                }
            }

            if let exact = recorderProjectMatches.values.first(where: { $0.isExact && $0.projectID == selectedProjectID }) {
                log("Exact recorder match: \(exact.recorderTakeCount) audio files align with \(exact.projectName)'s \(exact.cameraTakeCount) camera clips")
            }
        }
    }

    nonisolated static func recorderMatch(
        recorder: ShootGroup,
        camera: ScannedGroupPayload,
        project: ProjectRecord
    ) -> RecorderProjectMatch? {
        guard recorder.sourceKind == .audio,
              let recorderStart = parseCaptureDate(recorder.start),
              let recorderEnd = parseCaptureDate(recorder.end),
              let cameraStart = parseCaptureDate(camera.start),
              let cameraEnd = parseCaptureDate(camera.end),
              Calendar.current.isDate(recorderStart, inSameDayAs: cameraStart) else { return nil }

        let startDelta = Int(abs(recorderStart.timeIntervalSince(cameraStart)).rounded())
        let endDelta = Int(abs(recorderEnd.timeIntervalSince(cameraEnd)).rounded())
        let recorderCount = recorder.audioFiles.count
        let cameraCount = camera.videoCount
        let exact = recorderCount == cameraCount && startDelta <= 90 && endDelta <= 90

        let overlap = max(0, min(recorderEnd, cameraEnd).timeIntervalSince(max(recorderStart, cameraStart)))
        let union = max(recorderEnd, cameraEnd).timeIntervalSince(min(recorderStart, cameraStart))
        let overlapRatio = union > 0 ? overlap / union : 0
        let countRatio = Double(min(recorderCount, cameraCount)) / Double(max(max(recorderCount, cameraCount), 1))
        guard exact || (overlapRatio >= 0.70 && countRatio >= 0.70) else { return nil }

        return RecorderProjectMatch(
            projectID: project.id,
            projectName: project.name,
            recorderTakeCount: recorderCount,
            cameraTakeCount: cameraCount,
            startDeltaSeconds: startDelta,
            endDeltaSeconds: endDelta,
            isExact: exact
        )
    }

    nonisolated private static func parseCaptureDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    func inferredSourceLabel(for group: ScannedGroupPayload) -> String {
        if group.sourceKind == .camera {
            let names = group.files.map { URL(fileURLWithPath: $0.path).lastPathComponent.uppercased() }
            let looksLikeOsmo = group.files.contains { file in
                let name = URL(fileURLWithPath: file.path).lastPathComponent.uppercased()
                let path = file.relativePath.uppercased()
                return name.hasPrefix("DJI_") || path.contains("/DJI_") || path.contains("/OSMO")
            }
            if looksLikeOsmo { return "OSMO" }
            if names.contains(where: { $0.hasPrefix("IMG_") && ($0.hasSuffix(".MOV") || $0.hasSuffix(".MP4")) }) {
                return "IPHONE"
            }
            if names.contains(where: { $0.hasSuffix(".INSV") || $0.contains("INSTA360") }) {
                return "INSTA360"
            }
            return ProjectRecord.inferSourceLabel(sourcePath)
        }
        let audioNames = group.files.map { URL(fileURLWithPath: $0.path).lastPathComponent.uppercased() }
        if audioNames.contains(where: { $0.contains("DJI") }) {
            return sourcePath.uppercased().contains("MINI") ? "DJI MIC MINI" : "DJI MIC"
        }
        if audioNames.contains(where: { $0.hasPrefix("ZOOM") || $0.hasPrefix("H1") || $0.hasPrefix("H4") || $0.hasPrefix("H6") }) {
            return "ZOOM"
        }
        return ProjectRecord.inferSourceLabel(sourcePath, kind: .audio)
    }

    func move(file: ScannedFile, from sourceID: String, to destinationID: String) {
        move(files: [file], from: sourceID, to: destinationID)
    }

    /// Moves one or more visible takes as logical units. Camera WAV/LRF/SRT
    /// sidecars sharing a video's group key always travel with that MP4.
    func move(files: [ScannedFile], from sourceID: String, to destinationID: String) {
        guard sourceID != destinationID,
              let sourceIndex = shootGroups.firstIndex(where: { $0.id == sourceID }),
              let destinationIndex = shootGroups.firstIndex(where: { $0.id == destinationID }),
              shootGroups[sourceIndex].sourceKind == shootGroups[destinationIndex].sourceKind else { return }

        let requestedIDs = Set(files.map(\.id))
        let requestedGroupKeys = Set(files.filter { $0.kind == "video" }.map(\.groupKey))
        let moving = shootGroups[sourceIndex].files.filter { candidate in
            requestedIDs.contains(candidate.id)
                || (candidate.kind != "video" && requestedGroupKeys.contains(candidate.groupKey))
        }
        guard !moving.isEmpty else { return }

        recordImportPlanChange()

        let movingIDs = Set(moving.map(\.id))
        let sourceWasIncluded = ingestIncludedShootIDs.contains(sourceID)
        shootGroups[sourceIndex].files.removeAll { movingIDs.contains($0.id) }
        shootGroups[destinationIndex].files.append(contentsOf: moving)
        shootGroups[destinationIndex].files.sort { $0.captureTime < $1.captureTime }

        if shootGroups[sourceIndex].files.isEmpty {
            ingestDestinationProjectIDs.removeValue(forKey: sourceID)
            ingestIncludedShootIDs.remove(sourceID)
            if sourceWasIncluded { ingestIncludedShootIDs.insert(destinationID) }
            shootGroups.remove(at: sourceIndex)
        }
        log("Moved \(files.count) take\(files.count == 1 ? "" : "s"); attached sidecars followed automatically")
    }

    func splitIntoNewShoot(file: ScannedFile, from sourceID: String) {
        splitIntoNewShoot(files: [file], from: sourceID)
    }

    /// Splits selected visible takes into one new shoot while preserving their
    /// logical sidecar relationships.
    func splitIntoNewShoot(files: [ScannedFile], from sourceID: String) {
        guard let sourceIndex = shootGroups.firstIndex(where: { $0.id == sourceID }),
              !files.isEmpty else { return }

        let source = shootGroups[sourceIndex]
        let visibleFiles = source.sourceKind == .camera ? source.videos : source.audioFiles
        let requestedIDs = Set(files.map(\.id))
        guard requestedIDs.count < visibleFiles.count else { return }

        let requestedGroupKeys = Set(files.filter { $0.kind == "video" }.map(\.groupKey))
        let related = source.files.filter { candidate in
            requestedIDs.contains(candidate.id)
                || (candidate.kind != "video" && requestedGroupKeys.contains(candidate.groupKey))
        }
        guard !related.isEmpty else { return }
        recordImportPlanChange()
        let relatedIDs = Set(related.map(\.id))
        shootGroups[sourceIndex].files.removeAll { relatedIDs.contains($0.id) }

        let sorted = related.sorted { $0.captureTime < $1.captureTime }
        let firstCapture = sorted.first?.captureTime ?? source.start
        let lastCapture = sorted.last?.captureTime ?? source.end
        shootGroups.append(
            ShootGroup(
                id: UUID().uuidString,
                name: "Shoot \(shootGroups.count + 1)",
                kind: source.kind,
                sourceLabel: source.sourceLabel,
                sourceKind: source.sourceKind,
                files: sorted,
                start: firstCapture,
                end: lastCapture
            )
        )
        if ingestIncludedShootIDs.contains(sourceID) {
            ingestIncludedShootIDs.insert(shootGroups.last!.id)
        }
        log("Split \(files.count) take\(files.count == 1 ? "" : "s") into a new shoot; attached sidecars followed automatically")
    }

    func mergeShoot(_ sourceID: String, into destinationID: String) {
        guard sourceID != destinationID,
              let sourceIndex = shootGroups.firstIndex(where: { $0.id == sourceID }),
              let destinationIndex = shootGroups.firstIndex(where: { $0.id == destinationID }),
              shootGroups[sourceIndex].sourceKind == shootGroups[destinationIndex].sourceKind else { return }
        recordImportPlanChange()
        let files = shootGroups[sourceIndex].files
        let sourceWasIncluded = ingestIncludedShootIDs.contains(sourceID)
        shootGroups[destinationIndex].files.append(contentsOf: files)
        ingestDestinationProjectIDs.removeValue(forKey: sourceID)
        ingestIncludedShootIDs.remove(sourceID)
        if sourceWasIncluded { ingestIncludedShootIDs.insert(destinationID) }
        shootGroups.remove(at: sourceIndex)
        log("Merged shoot groups; every scanned file remains assigned")
    }

    func undoImportPlanChange() {
        guard let previous = importPlanUndoStack.popLast() else { return }
        importPlanRedoStack.append(importPlanSnapshot())
        restoreImportPlan(previous)
        log("Undid the last take-grouping change. Nothing has been copied.")
    }

    func redoImportPlanChange() {
        guard let next = importPlanRedoStack.popLast() else { return }
        importPlanUndoStack.append(importPlanSnapshot())
        restoreImportPlan(next)
        log("Redid the take-grouping change. Nothing has been copied.")
    }

    func resetImportPlanToScan() {
        guard let baseline = importPlanBaseline else { return }
        if canResetImportPlan {
            importPlanUndoStack.append(importPlanSnapshot())
        }
        importPlanRedoStack = []
        restoreImportPlan(baseline)
        log("Reset take grouping to the original scan. Nothing has been copied.")
    }

    private func importPlanSnapshot() -> ImportPlanSnapshot {
        ImportPlanSnapshot(
            shootGroups: shootGroups,
            destinationProjectIDs: ingestDestinationProjectIDs,
            includedShootIDs: ingestIncludedShootIDs,
            recorderProjectMatches: recorderProjectMatches
        )
    }

    private func setImportPlanBaseline() {
        importPlanBaseline = importPlanSnapshot()
        importPlanUndoStack = []
        importPlanRedoStack = []
    }

    private func recordImportPlanChange() {
        if importPlanBaseline == nil {
            importPlanBaseline = importPlanSnapshot()
        }
        importPlanUndoStack.append(importPlanSnapshot())
        importPlanRedoStack = []
    }

    private func restoreImportPlan(_ snapshot: ImportPlanSnapshot) {
        shootGroups = snapshot.shootGroups
        ingestDestinationProjectIDs = snapshot.destinationProjectIDs
        ingestIncludedShootIDs = snapshot.includedShootIDs
        recorderProjectMatches = snapshot.recorderProjectMatches
    }

    func ingestCapacityStatuses() throws -> [OffloadCapacityStatus] {
        let requests = shootGroupsSelectedForIngest.map { group in
            let existingProject = ingestDestinationProjectIDs[group.id].flatMap { destinationID in
                projects.first { $0.id == destinationID }
            }
            return OffloadCapacityRequest(
                destinationRoot: existingProject.map { URL(fileURLWithPath: $0.rootPath) }
                    ?? URL(fileURLWithPath: activeProjectsRoot),
                bytes: group.totalBytes
            )
        }
        return try VerifiedOffloadService.capacityStatuses(for: requests)
    }

    func confirmAndIngest() async {
        guard !sourcePath.isEmpty, !shootGroups.isEmpty else { return }
        let groupsToIngest = shootGroupsSelectedForIngest
        guard !groupsToIngest.isEmpty else {
            errorMessage = "Choose at least one shoot to import."
            return
        }
        let sourceURL = URL(fileURLWithPath: sourcePath)
        await perform("Verified ingest") {
            let capacityRequests = groupsToIngest.map { group in
                let existingProject = ingestDestinationProjectIDs[group.id].flatMap { destinationID in
                    projects.first { $0.id == destinationID }
                }
                return OffloadCapacityRequest(
                    destinationRoot: existingProject.map { URL(fileURLWithPath: $0.rootPath) }
                        ?? URL(fileURLWithPath: activeProjectsRoot),
                    bytes: group.totalBytes
                )
            }
            try await offloader.validateCapacity(for: capacityRequests)

            var cleanupPlans: [VerifiedCleanupPlan] = []
            var completedProjects: [String] = []
            var completedShoots: [CompletedIngestShoot] = []
            var totalFilesVerified = 0
            var totalBytesVerified: Int64 = 0
            for (groupIndex, group) in groupsToIngest.enumerated() {
                progressMessage = "Preparing \(group.name) (shoot \(groupIndex + 1) of \(groupsToIngest.count))"
                let existingProject = ingestDestinationProjectIDs[group.id].flatMap { destinationID in
                    projects.first { $0.id == destinationID }
                }
                let addedToExistingProject = existingProject != nil
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
                cleanupPlans.append(result.cleanupPlan)
                totalFilesVerified += result.filesVerified
                totalBytesVerified += result.bytesVerified
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
                // Persist the verified destination before optional indexing so a
                // backend failure can never hide a successful copy from the app.
                upsertProject(project)
                do {
                    if group.sourceKind == .camera {
                        progressMessage = "Indexing \(project.name) (shoot \(groupIndex + 1) of \(groupsToIngest.count))"
                        let status = try await backend.index(
                            projectRoot: project.rootPath,
                            source: result.mediaRoot.path,
                            sourceLabel: group.sourceLabel,
                            interval: sampleInterval
                        )
                        project.indexedAssets = status.assets
                        project.visualSamples = status.visualSamples
                        project.transcripts = status.transcripts
                        if project.profile == .communityStory {
                            progressMessage = "Transcribing spoken material in \(project.name)"
                            let transcriptStatus = try await backend.transcribe(
                                projectRoot: project.rootPath,
                                source: result.mediaRoot.path
                            )
                            project.indexedAssets = transcriptStatus.assets
                            project.visualSamples = transcriptStatus.visualSamples
                            project.transcripts = transcriptStatus.transcripts
                        }
                    } else {
                        try await backend.registerSource(
                            projectRoot: project.rootPath,
                            source: result.mediaRoot.path,
                            sourceLabel: group.sourceLabel,
                            kind: .audio
                        )
                        progressMessage = "Transcribing \(group.sourceLabel) for \(project.name)"
                        let transcriptStatus = try await backend.transcribe(
                            projectRoot: project.rootPath,
                            source: result.mediaRoot.path
                        )
                        project.indexedAssets = transcriptStatus.assets
                        project.visualSamples = transcriptStatus.visualSamples
                        project.transcripts = transcriptStatus.transcripts
                    }
                    upsertProject(project)
                    if (project.transcripts ?? 0) > 0 {
                        progressMessage = "Understanding takes and story beats in \(project.name)"
                        await appendAutomaticEditorialBrief(for: project)
                    }
                } catch {
                    log("Copy verified; indexing can be retried later: \(error.localizedDescription)", error: true)
                }
                completedShoots.append(
                    CompletedIngestShoot(
                        shootName: group.name,
                        projectName: project.name,
                        projectRoot: result.projectRoot.path,
                        mediaRoot: result.mediaRoot.path,
                        sourceLabel: group.sourceLabel,
                        filesVerified: result.filesVerified,
                        bytesVerified: result.bytesVerified,
                        addedToExistingProject: addedToExistingProject,
                        indexedAssets: project.indexedAssets
                    )
                )
                completedProjects.append(project.name)
            }
            completedCleanupResult = nil
            let summary = IngestCompletionSummary(
                projectNames: Array(Set(completedProjects)).sorted(),
                filesVerified: totalFilesVerified,
                bytesVerified: totalBytesVerified,
                cleanupPlans: cleanupPlans,
                shoots: completedShoots,
                shootsLeftOnSource: max(0, shootGroups.count - groupsToIngest.count)
            )
            completedIngestSummary = summary
            Self.savePendingIngestSummary(summary)
            resolveMessage = "Media verified. Resolve preparation waits for your confirmation."
        }
    }

    func cleanupCompletedIngest() async {
        guard let summary = completedIngestSummary else { return }
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let volumeID = cards.first(where: { $0.mountPath == sourcePath })?.volumeUUID
            ?? summary.cleanupPlans.first?.volumeUUID
            ?? "manual-\(sourceURL.lastPathComponent)"
        await perform("Rechecking verified copies before card cleanup") {
            let result = try await cleanupService.cleanup(
                plans: summary.cleanupPlans,
                currentSourceRoot: sourceURL,
                currentVolumeUUID: volumeID,
                progress: { [weak self] message in Task { @MainActor in self?.progressMessage = message } }
            )
            completedCleanupResult = result
            log("Safely removed \(result.filesDeleted) verified imported files from the source; unselected files were untouched")
        }
    }

    func finishCompletedIngest() {
        if let summary = completedIngestSummary {
            Self.rememberDismissedCleanupPlans(summary.cleanupPlans.map(\.id))
        }
        completedIngestSummary = nil
        completedCleanupResult = nil
        Self.clearPendingIngestSummary()
        selection = .project
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
            let result = try await ensureResolveProjectReady(project)
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

    func importedMediaFiles(for project: ProjectRecord) async throws -> [ScannedFile] {
        var filesByPath: [String: ScannedFile] = [:]
        for source in project.sources where source.kind == .camera {
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let payload = try await backend.scan(source: source.path, gapHours: 24)
            for file in payload.groups.flatMap(\.files) {
                filesByPath[file.path] = file
            }
        }
        return filesByPath.values.sorted {
            if $0.captureTime == $1.captureTime { return $0.path < $1.path }
            return $0.captureTime < $1.captureTime
        }
    }

    @discardableResult
    func relocateImportedTakes(
        videoPaths: [String],
        from sourceProjectID: ProjectRecord.ID,
        to destinationProjectID: ProjectRecord.ID?,
        newProjectName: String,
        newProjectKind: ProjectKind
    ) async -> ProjectMediaRelocationResult? {
        guard !isBusy, var sourceProject = projects.first(where: { $0.id == sourceProjectID }) else { return nil }
        let cleanName = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        var destinationProject: ProjectRecord
        if let destinationProjectID {
            guard let existing = projects.first(where: { $0.id == destinationProjectID }), existing.id != sourceProjectID else {
                errorMessage = "Choose a different destination project."
                return nil
            }
            destinationProject = existing
        } else {
            guard !cleanName.isEmpty,
                  !cleanName.contains("/"),
                  cleanName != ".",
                  cleanName != ".." else {
                errorMessage = "Enter a project name without slashes."
                return nil
            }
            let root = URL(fileURLWithPath: activeProjectsRoot)
                .appendingPathComponent(newProjectKind.rawValue, isDirectory: true)
                .appendingPathComponent(cleanName, isDirectory: true)
            guard !FileManager.default.fileExists(atPath: root.path) else {
                errorMessage = "A project folder named \(cleanName) already exists. Choose it from Existing project or use another name."
                return nil
            }
            destinationProject = ProjectRecord(
                name: cleanName,
                rootPath: root.path,
                sourcePath: "",
                kind: newProjectKind,
                profile: newProjectKind == .personal ? .event : .communityStory,
                sources: []
            )
        }

        isBusy = true
        errorMessage = nil
        progressMessage = "Preparing a safe project correction"
        log("Preparing to move \(videoPaths.count) imported take\(videoPaths.count == 1 ? "" : "s") out of \(sourceProject.name)")
        defer { isBusy = false; progressMessage = "Ready" }
        do {
            let result = try await projectMediaRelocationService.relocate(
                videoPaths: videoPaths,
                sourceProject: sourceProject,
                destinationProjectRoot: URL(fileURLWithPath: destinationProject.rootPath),
                progress: { [weak self] message in Task { @MainActor in self?.progressMessage = message } }
            )
            for folder in ["Assets", "Project", ".clip-resolved/analysis", ".clip-resolved/manifests"] {
                try FileManager.default.createDirectory(
                    at: URL(fileURLWithPath: destinationProject.rootPath).appendingPathComponent(folder, isDirectory: true),
                    withIntermediateDirectories: true
                )
            }

            for movedSource in result.sources {
                if !destinationProject.sources.contains(where: { $0.path == movedSource.path }) {
                    destinationProject.sources.append(
                        ProjectSourceRecord(label: movedSource.label, path: movedSource.path, kind: .camera)
                    )
                }
            }
            if destinationProject.sourcePath.isEmpty {
                destinationProject.sourcePath = destinationProject.sources.first(where: { $0.kind == .camera })?.path ?? ""
            }

            sourceProject.sources.removeAll { source in
                source.kind == .camera && !Self.folderContainsVideo(source.path)
            }
            if !sourceProject.sources.contains(where: { $0.path == sourceProject.sourcePath }) {
                sourceProject.sourcePath = sourceProject.sources.first(where: { $0.kind == .camera })?.path ?? ""
            }
            upsertProject(sourceProject)
            upsertProject(destinationProject)

            progressMessage = "Moving existing search intelligence to \(destinationProject.name)"
            do {
                for movedSource in result.sources {
                    try await backend.registerSource(
                        projectRoot: destinationProject.rootPath,
                        source: movedSource.path,
                        sourceLabel: movedSource.label,
                        kind: .camera
                    )
                }
                let relocation = try await backend.relocateIndexedAssets(
                    sourceProjectRoot: sourceProject.rootPath,
                    destinationProjectRoot: destinationProject.rootPath,
                    mappingFile: result.manifestPath
                )
                if !relocation.missingFromIndex.isEmpty {
                    log("\(relocation.missingFromIndex.count) moved take(s) were not previously indexed and can be added with Index New Media")
                }
                let sourceStatus = try await backend.status(projectRoot: sourceProject.rootPath)
                sourceProject.indexedAssets = sourceStatus.assets
                sourceProject.visualSamples = sourceStatus.visualSamples
                sourceProject.transcripts = sourceStatus.transcripts
                let destinationStatus = try await backend.status(projectRoot: destinationProject.rootPath)
                destinationProject.indexedAssets = destinationStatus.assets
                destinationProject.visualSamples = destinationStatus.visualSamples
                destinationProject.transcripts = destinationStatus.transcripts
                upsertProject(sourceProject)
                upsertProject(destinationProject)
            } catch {
                errorMessage = "The media moved safely, but its search index needs repair: \(error.localizedDescription)"
                log(errorMessage ?? "Search index repair needed", error: true)
            }

            moments = []
            query = ""
            timelineName = ""
            previewEvidence = nil
            selectedProjectID = destinationProject.id
            selection = .project
            log("Moved \(result.takesMoved) take\(result.takesMoved == 1 ? "" : "s") and \(result.filesMoved - result.takesMoved) attached file\(result.filesMoved - result.takesMoved == 1 ? "" : "s") into \(destinationProject.name)")
            return result
        } catch {
            errorMessage = error.localizedDescription
            log(error.localizedDescription, error: true)
            return nil
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
            _ = try await ensureResolveProjectReady(project)
            let result = try await backend.syncAudio(projectRoot: project.rootPath)
            resolveMessage = "Synced \(result.videos) video clips with \(result.audioFiles) audio clips"
            log(resolveMessage)
        }
    }

    func createMulticam(syncMode: String = "audio") async {
        guard let project = selectedProject else { return }
        let name = "\(project.name.uppercased()) MULTICAM"
        await perform("Creating multicam in Resolve") {
            _ = try await ensureResolveProjectReady(project)
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
            let transcriptionSources = preferredTranscriptionSources(for: project)
            guard !transcriptionSources.isEmpty else {
                throw BackendError.invalidOutput("This project has no registered audio source.")
            }
            var status = try await backend.status(projectRoot: project.rootPath)
            for source in transcriptionSources {
                status = try await backend.transcribe(projectRoot: project.rootPath, source: source.path)
            }
            project.indexedAssets = status.assets
            project.visualSamples = status.visualSamples
            project.transcripts = status.transcripts
            upsertProject(project)
            log("Created timed transcripts for \(status.transcripts) spoken-audio file(s)")
            progressMessage = "Understanding takes and story beats in \(project.name)"
            await appendAutomaticEditorialBrief(for: project)
        }
    }

    private func appendAutomaticEditorialBrief(for project: ProjectRecord) async {
        do {
            let context = try await backend.transcriptContext(projectRoot: project.rootPath)
            guard context.cueCount > 0 else {
                appendChat(
                    projectID: project.id,
                    role: .assistant,
                    text: "Automatic footage brief: transcription finished, but no usable spoken cues were detected yet. The files remain indexed for later sources and visual search."
                )
                return
            }
            let memories = chatMemories.filter {
                $0.scope == .global || ($0.scope == .project && $0.projectID == project.id)
            }
            let brief = try await claude.editorialBrief(
                project: project,
                transcriptContext: context,
                memories: memories
            )
            appendChat(
                projectID: project.id,
                role: .assistant,
                text: "Automatic footage brief\n\n\(brief)"
            )
            resolveMessage = "Editorial brief ready in Project Chat"
            log("Updated the automatic editorial brief for \(project.name)")
        } catch {
            log("Transcripts are ready; automatic editorial brief can be retried in Project Chat: \(error.localizedDescription)", error: true)
        }
    }

    private func preferredTranscriptionSources(for project: ProjectRecord) -> [ProjectSourceRecord] {
        let recorderSources = project.sources.filter { $0.kind == .audio }
        if !recorderSources.isEmpty { return recorderSources }
        // When there is no dedicated recorder, camera originals may still carry
        // the only usable dialogue track.
        return project.sources.filter { $0.kind == .camera }
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
            let transcriptContext: TranscriptContext?
            if (project.transcripts ?? 0) > 0 {
                transcriptContext = try? await backend.transcriptContext(projectRoot: project.rootPath)
            } else {
                transcriptContext = nil
            }
            let resolveState = try? await backend.resolveTimelines()
            let intent = try await claude.interpret(
                message: message,
                project: project,
                history: Array(history),
                memories: selectedProjectMemories,
                transcriptContext: transcriptContext,
                resolveState: resolveState
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
            case .transcribeAudio:
                appendChat(projectID: project.id, role: .assistant, text: intent.message)
                let sourceLabel = preferredTranscriptionSources(for: project).first?.label ?? "spoken audio"
                pendingChatAction = PendingChatAction(
                    projectID: project.id,
                    kind: .transcribeAudio,
                    title: "Transcribe \(sourceLabel)",
                    query: nil,
                    timelineName: nil,
                    searchMode: nil,
                    profile: nil,
                    rangeCount: 0
                )
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
            case .proposeExactRanges:
                let exactRanges = (intent.ranges ?? []).map {
                    ChatEvidence(
                        sourcePath: $0.sourcePath,
                        start: $0.start,
                        end: $0.end,
                        score: 1,
                        transcript: $0.transcript
                    )
                }
                guard !exactRanges.isEmpty else {
                    appendChat(projectID: project.id, role: .assistant, text: "I couldn't tie that request to an exact source range yet. Preview or identify the take you want, then ask again.")
                    return
                }
                let name = normalizedChatTimelineName(
                    intent.timelineName,
                    displayQuery: message,
                    fallbackQuery: "NARRATION SELECTS"
                )
                appendChat(
                    projectID: project.id,
                    role: .assistant,
                    text: intent.message,
                    evidence: exactRanges
                )
                pendingChatAction = PendingChatAction(
                    projectID: project.id,
                    kind: .createExactRanges,
                    title: "Create \(name) in Resolve",
                    query: nil,
                    timelineName: name,
                    searchMode: nil,
                    profile: nil,
                    rangeCount: exactRanges.count,
                    exactRanges: exactRanges
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
                let fallback = mode == .spoken && (project.transcripts ?? 0) == 0
                    ? "There are no timed transcripts for this project yet. Run Transcribe Audio, then ask again."
                    : "I found no sufficiently relevant handled ranges for “\(searchQuery)”. Try different wording or lower the search threshold."
                summary = (try? await claude.narrateSearchResult(
                    userMessage: displayQuery,
                    project: project,
                    searchMode: mode,
                    searchQuery: searchQuery,
                    timelineName: timelineName,
                    results: results,
                    preHandle: preHandle,
                    postHandle: postHandle,
                    minimumDuration: minimumDuration
                )) ?? fallback
            } else {
                let sourceCount = Set(results.map(\.sourcePath)).count
                let pre = preHandle.formatted(.number.precision(.fractionLength(0...1)))
                let post = postHandle.formatted(.number.precision(.fractionLength(0...1)))
                let minimum = minimumDuration.formatted(.number.precision(.fractionLength(0...1)))
                let fallback = "I found \(results.count) useful range\(results.count == 1 ? "" : "s") across \(sourceCount) original clip\(sourceCount == 1 ? "" : "s"). Preview the strongest matches below; when they look right, Clip Resolved can build \(timelineName) plus the complete NOT SELECTED review timeline with \(pre)s before, \(post)s after, and a \(minimum)s minimum."
                summary = (try? await claude.narrateSearchResult(
                    userMessage: displayQuery,
                    project: project,
                    searchMode: mode,
                    searchQuery: searchQuery,
                    timelineName: timelineName,
                    results: results,
                    preHandle: preHandle,
                    postHandle: postHandle,
                    minimumDuration: minimumDuration
                )) ?? fallback
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
            case .transcribeAudio:
                var updatedProject = project
                let sources = preferredTranscriptionSources(for: project)
                guard !sources.isEmpty else {
                    throw BackendError.invalidOutput("This project has no registered audio source.")
                }
                var status = try await backend.status(projectRoot: project.rootPath)
                for source in sources {
                    status = try await backend.transcribe(projectRoot: project.rootPath, source: source.path)
                }
                updatedProject.indexedAssets = status.assets
                updatedProject.visualSamples = status.visualSamples
                updatedProject.transcripts = status.transcripts
                upsertProject(updatedProject)
                appendChat(
                    projectID: project.id,
                    role: .assistant,
                    text: "Created timed transcripts for \(status.transcripts) spoken-audio file\(status.transcripts == 1 ? "" : "s"). Maggie's narration is now searchable without changing Resolve."
                )
                log("Created timed transcripts for \(status.transcripts) spoken-audio file(s)")
                progressMessage = "Understanding takes and story beats in \(project.name)"
                await appendAutomaticEditorialBrief(for: updatedProject)
            case .prepareResolve:
                let result = try await ensureResolveProjectReady(project)
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
                _ = try await ensureResolveProjectReady(project)
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
                if mode == .visual {
                    recordVisualPreparation(projectID: project.id, result: result)
                }
                log("Created \(result.timeline) from project chat")
            case .createExactRanges:
                guard let name = action.timelineName, !action.exactRanges.isEmpty else { return }
                _ = try await ensureResolveProjectReady(project)
                let result = try await backend.createExactRangeSelects(
                    projectRoot: project.rootPath,
                    ranges: action.exactRanges,
                    name: name
                )
                resolveMessage = result.remainderTimeline == nil
                    ? "Created \(result.timeline)"
                    : "Created exact SELECTS + NOT SELECTED"
                let remainderSummary = result.remainderTimeline.map {
                    " I also created \($0) with \(result.remainderRangesAppended ?? 0) source range\((result.remainderRangesAppended ?? 0) == 1 ? "" : "s") outside the chosen take."
                } ?? ""
                appendChat(
                    projectID: project.id,
                    role: .assistant,
                    text: "Created \(result.timeline) in Resolve from \(result.rangesAppended) exact source range\(result.rangesAppended == 1 ? "" : "s").\(remainderSummary)"
                )
                log("Created \(result.timeline) from exact transcript ranges")
                await stageVisualPreparationAfterNarration(for: project, narrationTimeline: result.timeline)
            case .createSmartSelects:
                _ = try await ensureResolveProjectReady(project)
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
                recordVisualPreparation(projectID: project.id, result: result)
                log("Created \(project.profile.packageTitle) from project chat")
            case .openTimeline:
                guard let name = action.timelineName else { return }
                _ = try await ensureResolveProjectReady(project)
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
            let message = resolveErrorMessage(error)
            errorMessage = message
            let prefix = action.kind == .transcribeAudio
                ? "I couldn't transcribe the spoken audio"
                : "I couldn't complete that Resolve action"
            appendChat(projectID: project.id, role: .assistant, text: "\(prefix): \(message)")
            log(message, error: true)
        }
    }

    func cancelPendingChatAction() {
        guard let action = pendingChatAction else { return }
        pendingChatAction = nil
        let text = action.kind == .transcribeAudio
            ? "Cancelled. No transcription was started."
            : "Cancelled. Resolve was not changed."
        appendChat(projectID: action.projectID, role: .assistant, text: text)
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
        } catch let error as BackendError where error.isResolveConnectionUnavailable {
            // Do not launch or change Resolve before confirmation. If the editor
            // is closed, stage creation and let the confirmed workflow open it.
            pendingChatAction = PendingChatAction(
                projectID: projectID,
                kind: .createSelects,
                title: "Create \(suggested.timelineName) in Resolve",
                query: suggested.query,
                timelineName: suggested.timelineName,
                searchMode: suggested.searchMode,
                profile: nil,
                rangeCount: suggested.rangeCount
            )
        } catch {
            let message = resolveErrorMessage(error)
            errorMessage = message
            log(message, error: true)
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
            _ = try await ensureResolveProjectReady(project)
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
            if searchMode == .visual {
                recordVisualPreparation(projectID: project.id, result: result)
            }
        }
    }

    func createSmartSelects(profile: String? = nil) async {
        guard let project = selectedProject else { return }
        await perform("Building professional SELECTS package") {
            _ = try await ensureResolveProjectReady(project)
            let result = try await backend.createSmartSelects(
                projectRoot: project.rootPath,
                profile: profile ?? project.profile.backendName,
                minScore: minScore,
                pre: preHandle,
                post: postHandle,
                minimum: minimumDuration
            )
            resolveMessage = "Created \(result.categoryTimelinesCreated) organized SELECTS timelines"
            recordVisualPreparation(projectID: project.id, result: result)
            log(smartSelectsSummary(result))
        }
    }

    private func recordVisualPreparation(projectID: UUID, result: SelectsResult) {
        guard var project = projects.first(where: { $0.id == projectID }) else { return }
        project.visualPreparation = VisualPreparationRecord(
            kind: .reviewedQuery,
            mainTimelines: [result.timeline],
            reviewTimeline: result.remainderTimeline,
            indexedAssets: project.indexedAssets,
            coverageComplete: result.coverageComplete == true,
            createdAt: Date()
        )
        upsertProject(project)
    }

    private func recordVisualPreparation(projectID: UUID, result: SmartSelectsResult) {
        guard var project = projects.first(where: { $0.id == projectID }) else { return }
        let organizedTimelines = [result.allBrollTimeline].compactMap { $0 }
            + result.categories.compactMap(\.timeline)
        project.visualPreparation = VisualPreparationRecord(
            kind: .fullPackage,
            mainTimelines: organizedTimelines,
            reviewTimeline: result.remainderTimeline,
            indexedAssets: result.indexedAssets,
            coverageComplete: result.coverageComplete,
            createdAt: Date()
        )
        upsertProject(project)
    }

    private func stageVisualPreparationAfterNarration(
        for project: ProjectRecord,
        narrationTimeline: String
    ) async {
        guard project.indexedAssets > 0,
              !isVisualPreparationCurrent(project) else { return }

        if let suggestion = latestVisualSuggestion(for: project.id) {
            appendChat(
                projectID: project.id,
                role: .assistant,
                text: "\(narrationTimeline) covers the voice-over only. The \(project.indexedAssets) indexed camera clips still need visual SELECTS. Your reviewed \(suggestion.timelineName) search is staged next, with its complete NOT SELECTED review timeline."
            )
            await stageSuggestedChatAction(suggestion, projectID: project.id)
            return
        }

        appendChat(
            projectID: project.id,
            role: .assistant,
            text: "\(narrationTimeline) covers the voice-over only. The \(project.indexedAssets) indexed camera clips still need visual organization, so the project’s complete visual SELECTS package is staged next."
        )
        pendingChatAction = PendingChatAction(
            projectID: project.id,
            kind: .createSmartSelects,
            title: "Build Visual SELECTS for \(project.name)",
            query: nil,
            timelineName: nil,
            searchMode: nil,
            profile: project.profile.backendName,
            rangeCount: 0
        )
    }

    private func smartSelectsSummary(_ result: SmartSelectsResult) -> String {
        let created = result.categories.compactMap(\.timeline)
        let skipped = result.categories.filter { $0.timeline == nil }.map(\.name)
        var parts = [
            "Created \(result.stringoutTimeline) with all \(result.stringoutRangesAppended) indexed original clips in source order.",
            result.allBrollTimeline.map {
                "Created \($0) with \(result.allBrollRangesAppended ?? 0) merged useful ranges across all populated categories."
            } ?? "",
            "Created \(result.categoryTimelinesCreated) category timeline\(result.categoryTimelinesCreated == 1 ? "" : "s") in Resolve: \(created.joined(separator: ", ")).",
            "\(result.remainderTimeline ?? "ALL FOOTAGE NOT SELECTED REVIEW") contains \(result.remainderRangesAppended) exact source range\(result.remainderRangesAppended == 1 ? "" : "s") outside the union of those categories."
        ]
        if !skipped.isEmpty {
            parts.append("Skipped empty categories: \(skipped.joined(separator: ", ")).")
        }
        parts.append(result.coverageComplete ? "The package accounts for the complete indexed source set." : "Coverage verification did not complete.")
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
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

        guard let refreshed = selectedProject,
              !isVisualPreparationCurrent(refreshed) else { return }
        do {
            let state = try await backend.resolveTimelines()
            let recovered = Self.recoveredFullVisualPackage(project: refreshed, state: state)
                ?? Self.recoveredVisualPreparation(
                project: refreshed,
                state: state,
                suggestion: latestVisualSuggestion(for: refreshed.id)
            )
            if let recovered {
                var updated = refreshed
                updated.visualPreparation = recovered
                upsertProject(updated)
                log("Verified existing visual SELECTS in Resolve for \(updated.name)")
            }
        } catch {
            // Resolve may be closed while the user is organizing or searching.
            // Readiness recovery is best-effort and must never launch or mutate it.
        }
    }

    private func ensureResolveProjectReady(_ project: ProjectRecord) async throws -> ResolveScaffoldResult {
        let launched = try await resolveApplication.openIfNeeded()
        progressMessage = launched ? "Opening DaVinci Resolve…" : "Connecting to DaVinci Resolve…"

        // Resolve exposes its scripting bridge only after the application has
        // finished startup. Retry that one expected startup failure while the
        // visible status keeps the user informed; fail immediately for all
        // project, media, or frame-rate errors.
        for attempt in 1...45 {
            progressMessage = launched
                ? "Opening Resolve and preparing \(project.name)… \(attempt)/45"
                : "Preparing \(project.name) in Resolve…"
            do {
                let result = try await backend.scaffold(project: project, timelineFPS: 30)
                guard result.frameRatesMatch else {
                    throw ResolveApplicationError.frameRateMismatch(result.timelineFPS ?? 30)
                }
                return result
            } catch let error as BackendError where error.isResolveConnectionUnavailable {
                guard attempt < 45 else { throw ResolveApplicationError.startupTimedOut }
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        throw ResolveApplicationError.startupTimedOut
    }

    private func resolveErrorMessage(_ error: Error) -> String {
        if let backendError = error as? BackendError,
           backendError.isResolveConnectionUnavailable {
            return ResolveApplicationError.startupTimedOut.localizedDescription
        }
        return error.localizedDescription
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
                transcripts: project.transcripts,
                visualPreparation: project.visualPreparation
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

    private static var pendingIngestSummaryURL: URL {
        projectsURL.deletingLastPathComponent().appendingPathComponent("pending-ingest-summary.json")
    }

    private static func savePendingIngestSummary(_ summary: IngestCompletionSummary) {
        guard let data = try? JSONEncoder().encode(summary) else { return }
        try? data.write(to: pendingIngestSummaryURL, options: .atomic)
    }

    private static func loadPendingIngestSummary() -> IngestCompletionSummary? {
        guard let data = try? Data(contentsOf: pendingIngestSummaryURL) else { return nil }
        guard let summary = try? JSONDecoder().decode(IngestCompletionSummary.self, from: data) else {
            return nil
        }
        let dismissed = Set(UserDefaults.standard.stringArray(forKey: dismissedCleanupPlansKey) ?? [])
        guard summary.cleanupPlans.contains(where: { !dismissed.contains($0.id.uuidString) }) else {
            clearPendingIngestSummary()
            return nil
        }
        return summary
    }

    private static func clearPendingIngestSummary() {
        try? FileManager.default.removeItem(at: pendingIngestSummaryURL)
    }

    private static let dismissedCleanupPlansKey = "dismissedCleanupPlanIDs"

    private static func rememberDismissedCleanupPlans(_ ids: [UUID]) {
        var dismissed = Set(UserDefaults.standard.stringArray(forKey: dismissedCleanupPlansKey) ?? [])
        dismissed.formUnion(ids.map(\.uuidString))
        UserDefaults.standard.set(Array(dismissed).sorted(), forKey: dismissedCleanupPlansKey)
    }

    /// Recovers the most recent verified cleanup choice after an app restart or
    /// upgrade. Plans are already checksum-backed artifacts written by ingest.
    private static func recoverRecentIngestSummary(projects: [ProjectRecord]) -> IngestCompletionSummary? {
        struct Candidate {
            let plan: VerifiedCleanupPlan
            let modified: Date
        }

        let fileManager = FileManager.default
        let dismissed = Set(UserDefaults.standard.stringArray(forKey: dismissedCleanupPlansKey) ?? [])
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        var candidates: [Candidate] = []
        for project in projects {
            let manifests = URL(fileURLWithPath: project.rootPath)
                .appendingPathComponent(".clip-resolved/manifests", isDirectory: true)
            guard let urls = try? fileManager.contentsOfDirectory(
                at: manifests,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in urls where url.lastPathComponent.hasPrefix("cleanup-plan-") && url.pathExtension == "json" {
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                      let modified = values.contentModificationDate,
                      modified >= cutoff,
                      let data = try? Data(contentsOf: url),
                      let plan = try? JSONDecoder().decode(VerifiedCleanupPlan.self, from: data),
                      !dismissed.contains(plan.id.uuidString),
                      fileManager.fileExists(atPath: plan.sourceRoot),
                      plan.session.files.contains(where: {
                          fileManager.fileExists(atPath: URL(fileURLWithPath: plan.sourceRoot).appendingPathComponent($0.relPath).path)
                      }) else { continue }
                candidates.append(Candidate(plan: plan, modified: modified))
            }
        }

        guard let newest = candidates.max(by: { $0.modified < $1.modified }) else { return nil }
        let matching = candidates
            .filter {
                $0.plan.sourceRoot == newest.plan.sourceRoot
                    && abs($0.modified.timeIntervalSince(newest.modified)) < 2 * 60 * 60
            }
            .sorted { $0.modified < $1.modified }
        guard !matching.isEmpty else { return nil }

        let shoots = matching.map { candidate -> CompletedIngestShoot in
            let plan = candidate.plan
            let project = projects.first { $0.rootPath == plan.projectRoot }
            let manifestURL = URL(fileURLWithPath: plan.manifestRoot)
                .appendingPathComponent("ingest-\(plan.id.uuidString).json")
            let manifest = (try? Data(contentsOf: manifestURL))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let shootName = manifest?["project"] as? String ?? project?.name ?? URL(fileURLWithPath: plan.projectRoot).lastPathComponent
            let sourceLabel = manifest?["source_label"] as? String ?? "Camera"
            let mediaRoot = plan.destinationByFileID.values.first.map {
                URL(fileURLWithPath: $0).deletingLastPathComponent().path
            } ?? plan.projectRoot
            return CompletedIngestShoot(
                shootName: shootName,
                projectName: project?.name ?? URL(fileURLWithPath: plan.projectRoot).lastPathComponent,
                projectRoot: plan.projectRoot,
                mediaRoot: mediaRoot,
                sourceLabel: sourceLabel,
                filesVerified: plan.fileCount,
                bytesVerified: plan.totalBytes,
                addedToExistingProject: project?.name != shootName,
                indexedAssets: project?.indexedAssets ?? 0
            )
        }
        return IngestCompletionSummary(
            projectNames: Array(Set(shoots.map(\.projectName))).sorted(),
            filesVerified: shoots.reduce(0) { $0 + $1.filesVerified },
            bytesVerified: shoots.reduce(0) { $0 + $1.bytesVerified },
            cleanupPlans: matching.map(\.plan),
            shoots: shoots,
            shootsLeftOnSource: nil
        )
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

    private static func folderContainsVideo(_ path: String) -> Bool {
        let extensions = Set(["mp4", "mov", "mxf", "m4v", "insv"])
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return false }
        for case let url as URL in enumerator where extensions.contains(url.pathExtension.lowercased()) {
            return true
        }
        return false
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
