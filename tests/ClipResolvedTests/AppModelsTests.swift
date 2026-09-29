import XCTest
import OffloadCore
@testable import OffloadEngine
@testable import ClipResolved

final class AppModelsTests: XCTestCase {
    func testResolveStartupFailureIsRecognizedForAutomaticRetry() {
        XCTAssertTrue(
            BackendError.commandFailed(
                1,
                "Failed to get Resolve object. Could not connect to DaVinci Resolve Studio."
            ).isResolveConnectionUnavailable
        )
        XCTAssertFalse(
            BackendError.commandFailed(
                1,
                "Resolve project frame-rate mismatch: timeline=30 playback=24"
            ).isResolveConnectionUnavailable
        )
    }

    func testEditorTimecode() {
        XCTAssertEqual(65.25.editorTimecode, "00:01:05.25")
    }

    func testTranscriptContextDecodesSourceIdentityAndCueTimes() throws {
        let payload = #"{"files":[{"source_path":"/Volumes/Extreme SSD/Audio/DJI_01.WAV","duration":12.5,"cues":[{"start":1.25,"end":3.5,"text":"Welcome to Andaan."}]}],"cue_count":1,"transcript_file_count":31,"truncated":false}"#
        let context = try JSONDecoder().decode(TranscriptContext.self, from: Data(payload.utf8))

        XCTAssertEqual(context.transcriptFileCount, 31)
        XCTAssertEqual(context.files.first?.fileName, "DJI_01.WAV")
        XCTAssertEqual(context.files.first?.cues.first?.start, 1.25)
        XCTAssertFalse(context.truncated)
    }

    func testScanPayloadDecodesBlockingFileIssuesAndOlderPayloads() throws {
        let issuePayload = #"{"source":"/Volumes/SD_Card","video_count":2,"audio_count":0,"sidecar_count":0,"total_bytes":100,"groups":[],"unassigned_sidecars":[],"scan_issues":[{"path":"/Volumes/SD_Card/DCIM/DJI_0002.MP4","relative_path":"DCIM/DJI_0002.MP4","kind":"video","reason":"ffprobe could not read this file after 2 attempts"}]}"#
        let withIssue = try JSONDecoder().decode(ScanPayload.self, from: Data(issuePayload.utf8))

        XCTAssertEqual(withIssue.scanIssues.count, 1)
        XCTAssertEqual(withIssue.scanIssues.first?.relativePath, "DCIM/DJI_0002.MP4")

        let oldPayload = #"{"source":"/Volumes/SD_Card","video_count":1,"audio_count":0,"sidecar_count":0,"total_bytes":50,"groups":[],"unassigned_sidecars":[]}"#
        let withoutIssue = try JSONDecoder().decode(ScanPayload.self, from: Data(oldPayload.utf8))

        XCTAssertTrue(withoutIssue.scanIssues.isEmpty)
    }

    func testProjectKindPathsAreStable() {
        XCTAssertEqual(ProjectKind.client.rawValue, "Client")
        XCTAssertEqual(ProjectKind.personal.rawValue, "Personal")
    }

    func testResolveProjectNameKeepsDisplayNameButRemovesRejectedPunctuation() {
        let project = ProjectRecord(
            name: "Andaan Gallery: Ray Colosky PROMO",
            rootPath: "/tmp/andaan",
            sourcePath: "/tmp/andaan/Media/OSMO",
            kind: .client
        )

        XCTAssertEqual(project.name, "Andaan Gallery: Ray Colosky PROMO")
        XCTAssertEqual(project.resolveProjectName, "Andaan Gallery - Ray Colosky PROMO")
    }

    func testClaudeStructuredIntentDecodesWithMemory() throws {
        let payload = #"{"is_error":false,"structured_output":{"message":"I will search the existing index.","action":"propose_selects","query":"food shots","timeline_name":"FOOD SHOTS SELECTS","search_mode":"Visual","profile":null,"memory_updates":[{"scope":"All projects","category":"Editing preference","content":"Use two-second pre-roll handles."}],"pre_handle_seconds":2,"post_handle_seconds":null,"minimum_duration_seconds":null,"ranges":[]}}"#
        let intent = try ClaudeChatService.decodeIntent(Data(payload.utf8))

        XCTAssertEqual(intent.action, .proposeSelects)
        XCTAssertEqual(intent.query, "food shots")
        XCTAssertEqual(intent.searchMode, .visual)
        XCTAssertEqual(intent.memoryUpdates.count, 1)
        XCTAssertEqual(intent.memoryUpdates.first?.scope, .global)
        XCTAssertEqual(intent.memoryUpdates.first?.content, "Use two-second pre-roll handles.")
        XCTAssertEqual(intent.preHandleSeconds, 2)
    }

    func testClaudeCanOfferRecorderTranscriptionFromProjectChat() throws {
        let payload = #"{"is_error":false,"structured_output":{"message":"Maggie's recorder audio should be transcribed first.","action":"transcribe_audio","query":null,"timeline_name":null,"search_mode":null,"profile":null,"memory_updates":[{"scope":"This project","category":"Project fact","content":"Maggie narrates on the DJI Mic while the camera captures B-roll."}],"pre_handle_seconds":null,"post_handle_seconds":null,"minimum_duration_seconds":null,"ranges":[]}}"#

        let intent = try ClaudeChatService.decodeIntent(Data(payload.utf8))

        XCTAssertEqual(intent.action, .transcribeAudio)
        XCTAssertEqual(intent.memoryUpdates.first?.scope, .project)
    }

    func testClaudeCanProposeExactTranscriptRanges() throws {
        let payload = #"{"is_error":false,"structured_output":{"message":"Take 3 is ready for review.","action":"propose_exact_ranges","query":null,"timeline_name":"MAGGIE NARRATION SELECTS","search_mode":null,"profile":null,"memory_updates":[],"pre_handle_seconds":null,"post_handle_seconds":null,"minimum_duration_seconds":null,"ranges":[{"source_path":"/Audio/DJI_47.WAV","start":156.72,"end":200.44,"transcript":"Complete take"}]}}"#
        let intent = try ClaudeChatService.decodeIntent(Data(payload.utf8))

        XCTAssertEqual(intent.action, .proposeExactRanges)
        XCTAssertEqual(intent.ranges?.first?.sourcePath, "/Audio/DJI_47.WAV")
        XCTAssertEqual(intent.ranges?.first?.start, 156.72)
    }

    func testSmartSelectsResultDecodesProfessionalPackage() throws {
        let payload = #"{"project":"OSAKA","profile":"restaurant","categories":[{"name":"FOOD SHOTS SELECTS","query":"food dishes plated meals","timeline":"FOOD SHOTS SELECTS","moments":12,"ranges_requested":12,"ranges_appended":12}],"category_timelines_created":1,"selected_ranges":12,"all_broll_timeline":"ALL B-ROLL SELECTS","all_broll_ranges_requested":10,"all_broll_ranges_appended":10,"stringout_timeline":"00 ALL RAW FOOTAGE STRINGOUT","stringout_ranges_requested":65,"stringout_ranges_appended":65,"remainder_timeline":"ALL FOOTAGE NOT SELECTED REVIEW","remainder_ranges_requested":20,"remainder_ranges_appended":20,"indexed_assets":65,"coverage_complete":true}"#
        let result = try JSONDecoder().decode(SmartSelectsResult.self, from: Data(payload.utf8))

        XCTAssertEqual(result.categoryTimelinesCreated, 1)
        XCTAssertEqual(result.categories.first?.timeline, "FOOD SHOTS SELECTS")
        XCTAssertEqual(result.allBrollTimeline, "ALL B-ROLL SELECTS")
        XCTAssertEqual(result.allBrollRangesAppended, 10)
        XCTAssertEqual(result.stringoutTimeline, "00 ALL RAW FOOTAGE STRINGOUT")
        XCTAssertEqual(result.remainderTimeline, "ALL FOOTAGE NOT SELECTED REVIEW")
        XCTAssertTrue(result.coverageComplete)
    }

    func testExactAudioSelectsResultDecodesWithoutLegacyQueryField() throws {
        let payload = #"{"project":"Andaan Gallery - Ray Colosky PROMO","timeline":"MAGGIE NARRATION SELECTS","ranges_requested":1,"ranges_appended":1,"timeline_fps":30.0,"snapshot":"/Project/Andaan.drp","snapshot_exported":true,"remainder_timeline":"MAGGIE NARRATION NOT SELECTED","remainder_ranges_requested":2,"remainder_ranges_appended":2,"coverage_complete":true,"moments":1}"#

        let result = try JSONDecoder().decode(SelectsResult.self, from: Data(payload.utf8))

        XCTAssertEqual(result.timeline, "MAGGIE NARRATION SELECTS")
        XCTAssertEqual(result.rangesAppended, 1)
        XCTAssertEqual(result.remainderRangesAppended, 2)
        XCTAssertNil(result.query)
    }

    func testProjectMemoryDoesNotBecomeGlobal() throws {
        let projectID = UUID()
        let memory = ChatMemoryItem(
            scope: .project,
            projectID: projectID,
            category: "Project fact",
            content: "The final piece should foreground food and hospitality."
        )
        let encoded = try JSONEncoder().encode(memory)
        let decoded = try JSONDecoder().decode(ChatMemoryItem.self, from: encoded)

        XCTAssertEqual(decoded.scope, .project)
        XCTAssertEqual(decoded.projectID, projectID)
    }

    func testOlderPersistedChatWithoutSuggestedActionStillDecodes() throws {
        let projectID = UUID()
        let messageID = UUID()
        let payload = #"{"id":"\#(messageID.uuidString)","projectID":"\#(projectID.uuidString)","role":"assistant","text":"Found matches.","evidence":[],"createdAt":0}"#
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: Data(payload.utf8))

        XCTAssertNil(decoded.suggestedAction)
    }

    func testOlderProjectMigratesToSourceManifestAndProfile() throws {
        let projectID = UUID()
        let payload = #"{"id":"\#(projectID.uuidString)","name":"OSAKA","rootPath":"/Projects/OSAKA","sourcePath":"/Projects/OSAKA/RAW FOOTAGE","kind":"Client","createdAt":0,"indexedAssets":65,"visualSamples":848}"#
        let decoded = try JSONDecoder().decode(ProjectRecord.self, from: Data(payload.utf8))

        XCTAssertEqual(decoded.profile, .communityStory)
        XCTAssertEqual(decoded.sources.count, 1)
        XCTAssertEqual(decoded.sources.first?.label, "OSMO")
        XCTAssertEqual(decoded.sources.first?.path, decoded.sourcePath)
    }

    func testProjectRecordPreservesExplicitEmptySourcesForProjectFirstWorkflow() throws {
        let project = ProjectRecord(
            name: "BABY SHOWER",
            rootPath: "/Projects/BABY SHOWER",
            sourcePath: "",
            kind: .personal,
            profile: .event,
            sources: []
        )

        let decoded = try JSONDecoder().decode(ProjectRecord.self, from: JSONEncoder().encode(project))

        XCTAssertTrue(decoded.sources.isEmpty)
        XCTAssertTrue(decoded.sourcePath.isEmpty)
        XCTAssertEqual(decoded.profile, .event)
    }

    @MainActor
    func testIndexedOrTranscribedProjectIsNotReadyUntilVisualSelectsCoverCurrentCameraIndex() {
        let store = AppStore(startServices: false)
        var project = ProjectRecord(
            name: "Andaan",
            rootPath: "/Projects/Andaan",
            sourcePath: "/Projects/Andaan/Media/OSMO",
            kind: .client,
            indexedAssets: 31,
            visualSamples: 403,
            transcripts: 31
        )

        XCTAssertFalse(store.isVisualPreparationCurrent(project))

        project.visualPreparation = VisualPreparationRecord(
            kind: .reviewedQuery,
            mainTimelines: ["ANDAAN BROLL COVERAGE SELECTS"],
            reviewTimeline: "ANDAAN BROLL COVERAGE NOT SELECTED",
            indexedAssets: 31,
            coverageComplete: true,
            createdAt: Date()
        )
        XCTAssertTrue(store.hasCurrentReviewedVisualSearch(project))
        XCTAssertFalse(store.isVisualPreparationCurrent(project))

        project.visualPreparation = VisualPreparationRecord(
            kind: .fullPackage,
            mainTimelines: ["ALL B-ROLL SELECTS", "INTERIOR ATMOSPHERE SELECTS", "EXTERIOR LOCATION SELECTS"],
            reviewTimeline: "ALL FOOTAGE NOT SELECTED REVIEW",
            indexedAssets: 31,
            coverageComplete: true,
            createdAt: Date()
        )
        XCTAssertTrue(store.isVisualPreparationCurrent(project))

        project.indexedAssets = 32
        XCTAssertFalse(store.isVisualPreparationCurrent(project))
    }

    @MainActor
    func testLatestVisualSuggestionIgnoresNewerNarrationAction() {
        let store = AppStore(startServices: false)
        let projectID = UUID()
        let visual = ChatSuggestedAction(
            query: "gallery interior and blue artwork",
            timelineName: "ANDAAN BROLL COVERAGE SELECTS",
            searchMode: .visual,
            rangeCount: 35
        )
        let narration = ChatSuggestedAction(
            query: "Maggie take three",
            timelineName: "MAGGIE NARRATION SELECTS",
            searchMode: .spoken,
            rangeCount: 1
        )
        store.chatMessages = [
            ChatMessage(projectID: projectID, role: .assistant, text: "B-roll", suggestedAction: visual),
            ChatMessage(projectID: projectID, role: .assistant, text: "Narration", suggestedAction: narration),
        ]

        XCTAssertEqual(store.latestVisualSuggestion(for: projectID), visual)
    }

    @MainActor
    func testVisualReadinessRecoversFromExistingResolveTimelinePair() {
        let project = ProjectRecord(
            name: "Andaan Gallery: Ray Colosky PROMO",
            rootPath: "/Projects/Andaan",
            sourcePath: "/Projects/Andaan/Media/OSMO",
            kind: .client,
            indexedAssets: 31,
            visualSamples: 403,
            transcripts: 31
        )
        let suggestion = ChatSuggestedAction(
            query: "gallery coverage",
            timelineName: "ANDAAN BROLL COVERAGE SELECTS",
            searchMode: .visual,
            rangeCount: 35
        )
        let state = ResolveTimelineState(
            project: project.resolveProjectName,
            timelines: [
                "ANDAAN GALLERY PROMO V1",
                "ANDAAN BROLL COVERAGE SELECTS",
                "ANDAAN BROLL COVERAGE NOT SELECTED",
            ],
            currentTimeline: "ANDAAN BROLL COVERAGE SELECTS"
        )

        let recovered = AppStore.recoveredVisualPreparation(
            project: project,
            state: state,
            suggestion: suggestion
        )

        XCTAssertEqual(recovered?.mainTimelines, ["ANDAAN BROLL COVERAGE SELECTS"])
        XCTAssertEqual(recovered?.reviewTimeline, "ANDAAN BROLL COVERAGE NOT SELECTED")
        XCTAssertEqual(recovered?.indexedAssets, 31)
        XCTAssertEqual(recovered?.coverageComplete, true)
        XCTAssertEqual(recovered?.kind, .reviewedQuery)
        XCTAssertNil(
            AppStore.recoveredVisualPreparation(
                project: project,
                state: ResolveTimelineState(
                    project: project.resolveProjectName,
                    timelines: ["ANDAAN BROLL COVERAGE SELECTS"],
                    currentTimeline: nil
                ),
                suggestion: suggestion
            )
        )

        let fullPackage = AppStore.recoveredFullVisualPackage(
            project: project,
            state: ResolveTimelineState(
                project: project.resolveProjectName,
                timelines: [
                    "00 ALL RAW FOOTAGE STRINGOUT",
                    "ALL B-ROLL SELECTS",
                    "INTERIOR ATMOSPHERE SELECTS",
                    "EXTERIOR LOCATION SELECTS",
                    "ALL FOOTAGE NOT SELECTED REVIEW",
                ],
                currentTimeline: "ALL B-ROLL SELECTS"
            )
        )
        XCTAssertEqual(fullPackage?.kind, .fullPackage)
        XCTAssertEqual(
            fullPackage?.mainTimelines,
            ["ALL B-ROLL SELECTS", "EXTERIOR LOCATION SELECTS", "INTERIOR ATMOSPHERE SELECTS"]
        )
    }

    func testAudioSourceLabelsDoNotMisclassifyDJIMicsAsOsmo() {
        XCTAssertEqual(ProjectRecord.inferSourceLabel("/Volumes/DJI MIC 2", kind: .audio), "DJI MIC 2")
        XCTAssertEqual(ProjectRecord.inferSourceLabel("/Volumes/DJI MIC MINI", kind: .audio), "DJI MIC MINI")
        XCTAssertEqual(ProjectRecord.inferSourceLabel("/Volumes/OSMO", kind: .camera), "OSMO")
    }

    func testVerifiedOffloadCapacityIncludesVerificationHeadroom() {
        XCTAssertEqual(
            VerifiedOffloadService.requiredCapacity(for: 100 * 1024 * 1024),
            612 * 1024 * 1024
        )
        XCTAssertEqual(
            VerifiedOffloadService.requiredCapacity(for: 20 * 1024 * 1024 * 1024),
            21 * 1024 * 1024 * 1024
        )
    }

    func testCapacityStatusAggregatesSelectedShootsOnSameDestinationVolume() throws {
        let temporary = FileManager.default.temporaryDirectory
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: temporary.path)
        let available = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        let statuses = try VerifiedOffloadService.capacityStatuses(for: [
            OffloadCapacityRequest(destinationRoot: temporary, bytes: 1_000_000),
            OffloadCapacityRequest(destinationRoot: temporary, bytes: 2_000_000),
        ])

        XCTAssertEqual(statuses.count, 1)
        XCTAssertEqual(statuses[0].selectedBytes, 3_000_000)
        XCTAssertEqual(statuses[0].requiredBytes, VerifiedOffloadService.requiredCapacity(for: 3_000_000))
        XCTAssertEqual(statuses[0].availableBytes, available)
        XCTAssertEqual(statuses[0].shortfallBytes, max(0, statuses[0].requiredBytes - available))
    }

    func testProjectMediaRelocationMovesCameraSidecarWithVideo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceRoot = root.appendingPathComponent("Source Project", isDirectory: true)
        let sourceMedia = sourceRoot.appendingPathComponent("Media/OSMO", isDirectory: true)
        let destinationRoot = root.appendingPathComponent("Downtown Shots", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceMedia, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let video = sourceMedia.appendingPathComponent("DJI_0001.MP4")
        let wav = sourceMedia.appendingPathComponent("DJI_0001.WAV")
        try Data("video".utf8).write(to: video)
        try Data("audio".utf8).write(to: wav)
        let project = ProjectRecord(
            name: "Andaan",
            rootPath: sourceRoot.path,
            sourcePath: sourceMedia.path,
            kind: .client,
            sources: [ProjectSourceRecord(label: "OSMO", path: sourceMedia.path, kind: .camera)]
        )

        let result = try await ProjectMediaRelocationService().relocate(
            videoPaths: [video.path],
            sourceProject: project,
            destinationProjectRoot: destinationRoot,
            progress: { _ in }
        )

        XCTAssertEqual(result.takesMoved, 1)
        XCTAssertEqual(result.filesMoved, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: video.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: wav.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationRoot.appendingPathComponent("Media/OSMO/DJI_0001.MP4").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationRoot.appendingPathComponent("Media/OSMO/DJI_0001.WAV").path))
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: result.manifestPath))) as? [String: Any]
        XCTAssertEqual(manifest?["state"] as? String, "moved")
    }

    func testProjectMediaRelocationBlocksDestinationCollisionBeforeMovingAnything() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceRoot = root.appendingPathComponent("Source Project", isDirectory: true)
        let sourceMedia = sourceRoot.appendingPathComponent("Media/OSMO", isDirectory: true)
        let destinationRoot = root.appendingPathComponent("Existing Project", isDirectory: true)
        let destinationMedia = destinationRoot.appendingPathComponent("Media/OSMO", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceMedia, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationMedia, withIntermediateDirectories: true)
        let video = sourceMedia.appendingPathComponent("DJI_0001.MP4")
        let wav = sourceMedia.appendingPathComponent("DJI_0001.WAV")
        try Data("video".utf8).write(to: video)
        try Data("audio".utf8).write(to: wav)
        try Data("different".utf8).write(to: destinationMedia.appendingPathComponent(video.lastPathComponent))
        let project = ProjectRecord(
            name: "Andaan",
            rootPath: sourceRoot.path,
            sourcePath: sourceMedia.path,
            kind: .client,
            sources: [ProjectSourceRecord(label: "OSMO", path: sourceMedia.path, kind: .camera)]
        )

        do {
            _ = try await ProjectMediaRelocationService().relocate(
                videoPaths: [video.path],
                sourceProject: project,
                destinationProjectRoot: destinationRoot,
                progress: { _ in }
            )
            XCTFail("Expected an existing-file collision")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: video.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: wav.path))
        }
    }

    @MainActor
    func testDetectedCardImmediatelyBecomesActiveIngestSource() {
        let store = AppStore(startServices: false)
        store.activeProjectsRoot = "/Volumes/Extreme SSD/ACTIVE PROJECTS"
        store.selection = .project
        let card = CardInfo(
            volumeUUID: "camera-card",
            bsdName: "disk99s1",
            mountPath: "/Volumes/OSMO CARD",
            volumeName: "OSMO CARD",
            capacityBytes: 64_000,
            freeBytes: 32_000,
            hasMediaRoot: true
        )

        store.ingestDestinationProjectID = UUID()
        XCTAssertTrue(store.prepareDetectedMedia(card))
        XCTAssertEqual(store.sourcePath, card.mountPath)
        XCTAssertEqual(store.selection, .ingest)
        XCTAssertNil(store.ingestDestinationProjectID)
        XCTAssertTrue(store.progressMessage.contains("Reading media metadata"))
    }

    @MainActor
    func testAutomaticDestinationNeverBlindlyAttachesCameraOrRecorderGroups() {
        let store = AppStore(startServices: false)
        let project = ProjectRecord(
            name: "Current Edit",
            rootPath: "/tmp/current-edit",
            sourcePath: "",
            kind: .client,
            sources: []
        )
        store.projects = [project]
        store.selectedProjectID = project.id

        store.shootGroups = [
            ShootGroup(
                id: "camera-a",
                name: "Camera Shoot A",
                kind: .client,
                sourceLabel: "OSMO",
                sourceKind: .camera,
                files: [],
                start: "",
                end: ""
            ),
            ShootGroup(
                id: "camera-b",
                name: "Camera Shoot B",
                kind: .client,
                sourceLabel: "OSMO",
                sourceKind: .camera,
                files: [],
                start: "",
                end: ""
            ),
        ]
        store.ingestDestinationProjectID = project.id
        store.applySafeAutomaticDestination()
        XCTAssertNil(store.ingestDestinationProjectID)

        store.shootGroups = [
            ShootGroup(
                id: "audio-a",
                name: "Recorder Session",
                kind: .client,
                sourceLabel: "DJI MIC 2 A",
                sourceKind: .audio,
                files: [],
                start: "",
                end: ""
            )
        ]
        store.applySafeAutomaticDestination()
        XCTAssertNil(store.ingestDestinationProjectID)
        XCTAssertNil(store.destinationProjectID(for: "audio-a"))
    }

    @MainActor
    func testEachShootCanChooseItsOwnDestinationAndImportSelection() {
        let store = AppStore(startServices: false)
        let andaan = ProjectRecord(
            name: "Andaan Gallery",
            rootPath: "/tmp/andaan",
            sourcePath: "/tmp/andaan/Media/OSMO",
            kind: .client
        )
        let osaka = ProjectRecord(
            name: "OSAKA",
            rootPath: "/tmp/osaka",
            sourcePath: "/tmp/osaka/Media/OSMO",
            kind: .client
        )
        store.projects = [andaan, osaka]
        store.shootGroups = [
            ShootGroup(id: "new", name: "New Job", kind: .client, sourceLabel: "OSMO", sourceKind: .camera, files: [scannedFile(name: "NEW.MP4", groupKey: "NEW", kind: "video")], start: "", end: ""),
            ShootGroup(id: "andaan", name: "Andaan Pickup", kind: .client, sourceLabel: "OSMO", sourceKind: .camera, files: [scannedFile(name: "ANDAAN.MP4", groupKey: "ANDAAN", kind: "video")], start: "", end: ""),
            ShootGroup(id: "later", name: "Leave on Card", kind: .client, sourceLabel: "OSMO", sourceKind: .camera, files: [scannedFile(name: "LATER.MP4", groupKey: "LATER", kind: "video")], start: "", end: ""),
        ]
        store.ingestIncludedShootIDs = Set(store.shootGroups.map(\.id))

        store.setDestinationProjectID(andaan.id, for: "andaan")
        store.setShootIncluded(false, shootID: "later")

        XCTAssertNil(store.destinationProjectID(for: "new"), "An unmapped shoot creates its own project")
        XCTAssertEqual(store.destinationProjectID(for: "andaan"), andaan.id)
        XCTAssertTrue(store.isShootIncluded("new"))
        XCTAssertTrue(store.isShootIncluded("andaan"))
        XCTAssertFalse(store.isShootIncluded("later"))
        XCTAssertEqual(store.shootGroupsSelectedForIngest.map(\.id), ["new", "andaan"])
    }

    @MainActor
    func testMixedCardClearsUnverifiedDestinationsForEverySourceType() {
        let store = AppStore(startServices: false)
        let current = ProjectRecord(
            name: "Current Edit",
            rootPath: "/tmp/current",
            sourcePath: "",
            kind: .client,
            sources: []
        )
        store.projects = [current]
        store.selectedProjectID = current.id
        store.shootGroups = [
            ShootGroup(id: "camera", name: "Camera", kind: .client, sourceLabel: "OSMO", sourceKind: .camera, files: [], start: "", end: ""),
            ShootGroup(id: "recorder", name: "Recorder", kind: .client, sourceLabel: "DJI MIC 2", sourceKind: .audio, files: [], start: "", end: ""),
        ]
        store.setDestinationProjectID(current.id, for: "camera")

        store.applySafeAutomaticDestination()

        XCTAssertNil(store.destinationProjectID(for: "camera"))
        XCTAssertNil(store.destinationProjectID(for: "recorder"))
        XCTAssertNil(store.ingestDestinationProjectID)
    }

    func testRecorderMatchFindsExactProjectByCountAndCaptureWindow() {
        let project = ProjectRecord(
            name: "Andaan Gallery",
            rootPath: "/tmp/andaan",
            sourcePath: "/tmp/andaan/Media/OSMO",
            kind: .client
        )
        let recorderFiles = (0..<31).map { index in
            ScannedFile(
                path: "/Volumes/DJI/REC\(index).WAV",
                relativePath: "REC\(index).WAV",
                groupKey: "recorder",
                kind: "audio",
                size: 1_000,
                captureTime: "2026-09-25T23:12:30Z",
                duration: 10,
                fps: 0,
                width: 0,
                height: 0,
                hasAudio: true
            )
        }
        let recorder = ShootGroup(
            id: "recorder",
            name: "Recorder Session",
            kind: .client,
            sourceLabel: "DJI MIC MINI",
            sourceKind: .audio,
            files: recorderFiles,
            start: "2026-09-25T23:12:30Z",
            end: "2026-09-25T23:31:40Z"
        )
        let camera = ScannedGroupPayload(
            id: "camera",
            suggestedName: "Camera Session",
            sourceKind: .camera,
            start: "2026-09-25T23:12:32Z",
            end: "2026-09-25T23:31:41Z",
            videoCount: 31,
            audioCount: 31,
            fileCount: 62,
            totalBytes: 100_000,
            files: []
        )

        let match = AppStore.recorderMatch(recorder: recorder, camera: camera, project: project)

        XCTAssertEqual(match?.projectID, project.id)
        XCTAssertEqual(match?.projectName, "Andaan Gallery")
        XCTAssertEqual(match?.startDeltaSeconds, 2)
        XCTAssertEqual(match?.endDeltaSeconds, 1)
        XCTAssertEqual(match?.recorderTakeCount, 31)
        XCTAssertEqual(match?.cameraTakeCount, 31)
        XCTAssertEqual(match?.isExact, true)
    }

    func testRecorderMatchRejectsDifferentShoot() {
        let project = ProjectRecord(
            name: "Different Project",
            rootPath: "/tmp/different",
            sourcePath: "/tmp/different/Media/OSMO",
            kind: .client
        )
        let file = ScannedFile(
            path: "/Volumes/DJI/REC.WAV",
            relativePath: "REC.WAV",
            groupKey: "recorder",
            kind: "audio",
            size: 1_000,
            captureTime: "2026-09-25T23:12:30Z",
            duration: 10,
            fps: 0,
            width: 0,
            height: 0,
            hasAudio: true
        )
        let recorder = ShootGroup(
            id: "recorder",
            name: "Recorder Session",
            kind: .client,
            sourceLabel: "DJI MIC MINI",
            sourceKind: .audio,
            files: [file],
            start: "2026-09-25T23:12:30Z",
            end: "2026-09-25T23:31:40Z"
        )
        let camera = ScannedGroupPayload(
            id: "camera",
            suggestedName: "Other Day",
            sourceKind: .camera,
            start: "2026-09-26T20:00:00Z",
            end: "2026-09-26T20:20:00Z",
            videoCount: 1,
            audioCount: 1,
            fileCount: 2,
            totalBytes: 2_000,
            files: []
        )

        XCTAssertNil(AppStore.recorderMatch(recorder: recorder, camera: camera, project: project))
    }

    @MainActor
    func testRealisticMixedSourcesCanRouteIndependentlyAndLeaveLargeShootOnCard() {
        let store = AppStore(startServices: false)
        let andaan = ProjectRecord(
            name: "Andaan Gallery",
            rootPath: "/tmp/projects/Andaan Gallery",
            sourcePath: "/tmp/projects/Andaan Gallery/Media/OSMO",
            kind: .client
        )
        store.projects = [andaan]
        store.shootGroups = [
            ShootGroup(id: "new-osmo", name: "New Client", kind: .client, sourceLabel: "OSMO", sourceKind: .camera, files: [scannedFile(name: "DJI_0001.MP4", groupKey: "DJI_0001", kind: "video")], start: "", end: ""),
            ShootGroup(id: "andaan-pickup", name: "Andaan Pickup", kind: .client, sourceLabel: "OSMO", sourceKind: .camera, files: [scannedFile(name: "DJI_0002.MP4", groupKey: "DJI_0002", kind: "video")], start: "", end: ""),
            ShootGroup(id: "leave-large", name: "Later", kind: .personal, sourceLabel: "OSMO", sourceKind: .camera, files: [scannedFile(name: "DJI_0200.MP4", groupKey: "DJI_0200", kind: "video")], start: "", end: ""),
            ShootGroup(id: "mic", name: "Andaan Mic", kind: .client, sourceLabel: "DJI MIC MINI", sourceKind: .audio, files: [scannedFile(name: "DJI_MIC_001.WAV", groupKey: "DJI_MIC_001", kind: "audio")], start: "", end: ""),
            ShootGroup(id: "iphone", name: "Family iPhone", kind: .personal, sourceLabel: "IPHONE", sourceKind: .camera, files: [scannedFile(name: "IMG_4001.MOV", groupKey: "IMG_4001", kind: "video")], start: "", end: ""),
        ]

        store.setShootIncluded(true, shootID: "new-osmo")
        store.setShootIncluded(true, shootID: "andaan-pickup")
        store.setShootIncluded(false, shootID: "leave-large")
        store.setShootIncluded(true, shootID: "mic")
        store.setShootIncluded(true, shootID: "iphone")
        store.setDestinationProjectID(andaan.id, for: "andaan-pickup")
        store.setDestinationProjectID(andaan.id, for: "mic")

        XCTAssertNil(store.destinationProjectID(for: "new-osmo"))
        XCTAssertNil(store.destinationProjectID(for: "iphone"))
        XCTAssertEqual(store.destinationProjectID(for: "andaan-pickup"), andaan.id)
        XCTAssertEqual(store.destinationProjectID(for: "mic"), andaan.id)
        XCTAssertEqual(store.shootGroupsSelectedForIngest.map(\.id), ["new-osmo", "andaan-pickup", "mic", "iphone"])
        XCTAssertFalse(store.shootGroupsSelectedForIngest.contains { $0.id == "leave-large" })
    }

    @MainActor
    func testDownloadedIPhoneAndRecorderFilesInferIdentityWithoutUserTyping() {
        let store = AppStore(startServices: false)
        store.sourcePath = "/Users/example/Downloads"
        let iPhoneFile = scannedFile(name: "IMG_8123.MOV", groupKey: "IMG_8123", kind: "video")
        let iPhoneGroup = ScannedGroupPayload(
            id: "iphone",
            suggestedName: "iPhone",
            sourceKind: .camera,
            start: "",
            end: "",
            videoCount: 1,
            audioCount: 0,
            fileCount: 1,
            totalBytes: iPhoneFile.size,
            files: [iPhoneFile]
        )
        XCTAssertEqual(store.inferredSourceLabel(for: iPhoneGroup), "IPHONE")

        let micFile = scannedFile(name: "DJI_MIC_0001.WAV", groupKey: "DJI_MIC_0001", kind: "audio")
        let micGroup = ScannedGroupPayload(
            id: "mic",
            suggestedName: "Recorder",
            sourceKind: .audio,
            start: "",
            end: "",
            videoCount: 0,
            audioCount: 1,
            fileCount: 1,
            totalBytes: micFile.size,
            files: [micFile]
        )
        XCTAssertEqual(store.inferredSourceLabel(for: micGroup), "DJI MIC")
    }

    @MainActor
    func testMovingMultipleCameraTakesCarriesWAVSidecarsWithoutDuplicatingThem() {
        let store = AppStore(startServices: false)
        let videoA = scannedFile(name: "DJI_0001.MP4", groupKey: "DJI_0001", kind: "video")
        let audioA = scannedFile(name: "DJI_0001.WAV", groupKey: "DJI_0001", kind: "audio")
        let videoB = scannedFile(name: "DJI_0002.MP4", groupKey: "DJI_0002", kind: "video")
        let audioB = scannedFile(name: "DJI_0002.WAV", groupKey: "DJI_0002", kind: "audio")
        let remaining = scannedFile(name: "DJI_0003.MP4", groupKey: "DJI_0003", kind: "video")

        store.shootGroups = [
            ShootGroup(id: "one", name: "Shoot 1", kind: .client, sourceLabel: "OSMO", sourceKind: .camera, files: [videoA, audioA, videoB, audioB, remaining], start: "", end: ""),
            ShootGroup(id: "two", name: "Shoot 2", kind: .client, sourceLabel: "OSMO", sourceKind: .camera, files: [], start: "", end: ""),
        ]

        store.move(files: [videoA, videoB], from: "one", to: "two")

        XCTAssertEqual(store.shootGroups.first { $0.id == "one" }?.files, [remaining])
        XCTAssertEqual(Set(store.shootGroups.first { $0.id == "two" }?.files.map(\.id) ?? []), Set([videoA.id, audioA.id, videoB.id, audioB.id]))
        XCTAssertEqual(store.shootGroups.flatMap(\.files).filter { $0.id == audioA.id }.count, 1)
        XCTAssertEqual(store.shootGroups.flatMap(\.files).filter { $0.id == audioB.id }.count, 1)
    }

    @MainActor
    func testSplittingSelectedCameraTakesCreatesOneShootWithSidecars() {
        let store = AppStore(startServices: false)
        let videoA = scannedFile(name: "DJI_0101.MP4", groupKey: "DJI_0101", kind: "video")
        let audioA = scannedFile(name: "DJI_0101.WAV", groupKey: "DJI_0101", kind: "audio")
        let videoB = scannedFile(name: "DJI_0102.MP4", groupKey: "DJI_0102", kind: "video")
        let audioB = scannedFile(name: "DJI_0102.WAV", groupKey: "DJI_0102", kind: "audio")
        let remaining = scannedFile(name: "DJI_0103.MP4", groupKey: "DJI_0103", kind: "video")
        store.shootGroups = [
            ShootGroup(id: "source", name: "Original", kind: .client, sourceLabel: "OSMO", sourceKind: .camera, files: [videoA, audioA, videoB, audioB, remaining], start: "", end: "")
        ]

        store.splitIntoNewShoot(files: [videoA, videoB], from: "source")

        XCTAssertEqual(store.shootGroups.count, 2)
        XCTAssertEqual(store.shootGroups[0].files, [remaining])
        XCTAssertEqual(Set(store.shootGroups[1].files.map(\.id)), Set([videoA.id, audioA.id, videoB.id, audioB.id]))
    }

    @MainActor
    func testGroupingUndoRedoAndResetRestoreLogicalTakesWithSidecars() {
        let store = AppStore(startServices: false)
        let videoA = scannedFile(name: "DJI_0201.MP4", groupKey: "DJI_0201", kind: "video")
        let audioA = scannedFile(name: "DJI_0201.WAV", groupKey: "DJI_0201", kind: "audio")
        let videoB = scannedFile(name: "DJI_0202.MP4", groupKey: "DJI_0202", kind: "video")
        store.shootGroups = [
            ShootGroup(id: "one", name: "Shoot 1", kind: .client, sourceLabel: "OSMO", sourceKind: .camera, files: [videoA, audioA, videoB], start: "", end: ""),
            ShootGroup(id: "two", name: "Shoot 2", kind: .client, sourceLabel: "OSMO", sourceKind: .camera, files: [], start: "", end: ""),
        ]

        store.move(file: videoA, from: "one", to: "two")
        XCTAssertTrue(store.canUndoImportPlan)
        XCTAssertEqual(Set(store.shootGroups[1].files.map(\.id)), Set([videoA.id, audioA.id]))

        store.undoImportPlanChange()
        XCTAssertEqual(store.shootGroups[0].files, [videoA, audioA, videoB])
        XCTAssertTrue(store.shootGroups[1].files.isEmpty)
        XCTAssertTrue(store.canRedoImportPlan)

        store.redoImportPlanChange()
        XCTAssertEqual(Set(store.shootGroups[1].files.map(\.id)), Set([videoA.id, audioA.id]))

        store.resetImportPlanToScan()
        XCTAssertEqual(store.shootGroups[0].files, [videoA, audioA, videoB])
        XCTAssertTrue(store.shootGroups[1].files.isEmpty)
        XCTAssertEqual(store.shootGroups.flatMap(\.files).filter { $0.id == audioA.id }.count, 1)
    }

    @MainActor
    func testDestinationDriveIsNeverMistakenForInsertedSourceMedia() {
        let store = AppStore(startServices: false)
        store.activeProjectsRoot = "/Volumes/Extreme SSD/ACTIVE PROJECTS"
        let destinationDrive = CardInfo(
            volumeUUID: "destination-drive",
            bsdName: "disk4s1",
            mountPath: "/Volumes/Extreme SSD",
            volumeName: "Extreme SSD",
            capacityBytes: 1_000_000,
            freeBytes: 20_000,
            hasMediaRoot: false
        )

        XCTAssertFalse(store.prepareDetectedMedia(destinationDrive))
    }

    func testMountedExternalHardDriveWithMediaIsNotRecognizedAsCaptureMedia() {
        let drive = CardInfo(
            volumeUUID: "archive-drive",
            bsdName: "disk8s1",
            mountPath: "/Volumes/queue",
            volumeName: "queue",
            capacityBytes: 2_000_000_000_000,
            freeBytes: 1_900_000_000_000,
            hasMediaRoot: false
        )

        XCTAssertFalse(AppStore.shouldRecognizeMountedMedia(
            drive,
            isRemovable: false,
            isEjectable: true,
            isInternal: false,
            isNetwork: false
        ))
    }

    func testRemovableCardAndKnownRecorderRemainAutomatic() {
        let card = CardInfo(
            volumeUUID: "camera-card",
            bsdName: "disk7s1",
            mountPath: "/Volumes/SD_Card",
            volumeName: "SD_Card",
            capacityBytes: 250_000_000_000,
            freeBytes: 20_000_000_000,
            hasMediaRoot: false
        )
        let recorder = CardInfo(
            volumeUUID: "recorder",
            bsdName: "disk9s1",
            mountPath: "/Volumes/DJI MIC MINI",
            volumeName: "DJI_MIC_MINI",
            capacityBytes: 32_000_000_000,
            freeBytes: 16_000_000_000,
            hasMediaRoot: false
        )

        XCTAssertTrue(AppStore.shouldRecognizeMountedMedia(
            card,
            isRemovable: true,
            isEjectable: true,
            isInternal: false,
            isNetwork: false
        ))
        XCTAssertTrue(AppStore.shouldRecognizeMountedMedia(
            recorder,
            isRemovable: false,
            isEjectable: true,
            isInternal: false,
            isNetwork: false
        ))
    }

    func testWatcherRecognizesShallowMicRecorderAudioWithoutDCIM() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let recordingFolder = root.appendingPathComponent("RECORD", isDirectory: true)
        try FileManager.default.createDirectory(at: recordingFolder, withIntermediateDirectories: true)
        try Data("audio-fixture".utf8).write(to: recordingFolder.appendingPathComponent("DJI_001.WAV"))
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertTrue(CardWatcher.containsSupportedMedia(at: root.path, hasMediaRoot: false))
    }

    private func scannedFile(name: String, groupKey: String, kind: String) -> ScannedFile {
        ScannedFile(
            path: "/Volumes/SD_Card/DCIM/\(name)",
            relativePath: "DCIM/\(name)",
            groupKey: groupKey,
            kind: kind,
            size: 100,
            captureTime: "2026-09-28T12:00:00Z",
            duration: kind == "video" ? 10 : 0,
            fps: kind == "video" ? 59.94 : 0,
            width: kind == "video" ? 3840 : 0,
            height: kind == "video" ? 2160 : 0,
            hasAudio: kind == "video"
        )
    }

    func testVerifiedOffloadCopiesAndPreservesSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let card = root.appendingPathComponent("card/DCIM", isDirectory: true)
        let active = root.appendingPathComponent("active", isDirectory: true)
        try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
        let source = card.appendingPathComponent("DJI_TEST.MP4")
        let original = Data("camera-original".utf8)
        try original.write(to: source)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = ScannedFile(
            path: source.path,
            relativePath: "DJI_TEST.MP4",
            groupKey: "DJI_TEST",
            kind: "video",
            size: Int64(original.count),
            captureTime: ISO8601DateFormatter().string(from: Date()),
            duration: 1,
            fps: 30,
            width: 1920,
            height: 1080,
            hasAudio: true
        )
        let group = ShootGroup(id: "test", name: "Test Shoot", kind: .client, sourceLabel: "OSMO", sourceKind: .camera, files: [file], start: file.captureTime, end: file.captureTime)
        let result = try await VerifiedOffloadService().offload(
            group: group,
            sourceRoot: card,
            activeProjectsRoot: active,
            volumeUUID: "fixture",
            progress: { _ in }
        )

        let destination = result.mediaRoot.appendingPathComponent("DJI_TEST.MP4")
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try Data(contentsOf: destination), original)
        XCTAssertEqual(result.mediaRoot.lastPathComponent, "OSMO")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.projectRoot.appendingPathComponent(".clip-resolved/manifests/ingest-manifest.json").path))
        XCTAssertEqual(result.filesVerified, 1)

        let laterGroup = ShootGroup(
            id: "later",
            name: "Later Card",
            kind: .client,
            sourceLabel: "IPHONE",
            sourceKind: .camera,
            files: [file],
            start: file.captureTime,
            end: file.captureTime
        )
        let later = try await VerifiedOffloadService().offload(
            group: laterGroup,
            sourceRoot: card,
            activeProjectsRoot: active,
            volumeUUID: "fixture-later",
            destinationProjectRoot: result.projectRoot,
            progress: { _ in }
        )
        XCTAssertEqual(later.projectRoot, result.projectRoot)
        XCTAssertEqual(later.mediaRoot.lastPathComponent, "IPHONE")
        XCTAssertEqual(try Data(contentsOf: later.mediaRoot.appendingPathComponent("DJI_TEST.MP4")), original)
        let manifests = try FileManager.default.contentsOfDirectory(
            at: result.projectRoot.appendingPathComponent(".clip-resolved/manifests"),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("ingest-") }
        XCTAssertGreaterThanOrEqual(manifests.count, 2)

        let micSource = card.appendingPathComponent("DJI_MIC_001.WAV")
        let micData = Data("mic-original".utf8)
        try micData.write(to: micSource)
        let micFile = ScannedFile(
            path: micSource.path,
            relativePath: micSource.lastPathComponent,
            groupKey: "DJI_MIC_001",
            kind: "audio",
            size: Int64(micData.count),
            captureTime: file.captureTime,
            duration: 10,
            fps: 0,
            width: 0,
            height: 0,
            hasAudio: true
        )
        let micGroup = ShootGroup(
            id: "mic",
            name: "Mic Card",
            kind: .client,
            sourceLabel: "DJI MIC 2",
            sourceKind: .audio,
            files: [micFile],
            start: micFile.captureTime,
            end: micFile.captureTime
        )
        let mic = try await VerifiedOffloadService().offload(
            group: micGroup,
            sourceRoot: card,
            activeProjectsRoot: active,
            volumeUUID: "fixture-mic",
            destinationProjectRoot: result.projectRoot,
            progress: { _ in }
        )
        XCTAssertEqual(mic.mediaRoot.lastPathComponent, "DJI MIC 2")
        XCTAssertEqual(mic.mediaRoot.deletingLastPathComponent().lastPathComponent, "Audio")
        XCTAssertEqual(try Data(contentsOf: mic.mediaRoot.appendingPathComponent("DJI_MIC_001.WAV")), micData)
    }

    func testVerifiedCleanupDeletesOnlyImportedFileAfterDestinationRehash() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let card = root.appendingPathComponent("card", isDirectory: true)
        let active = root.appendingPathComponent("active", isDirectory: true)
        try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
        let imported = card.appendingPathComponent("DJI_SELECTED.MP4")
        let unselected = card.appendingPathComponent("DJI_LEAVE_ON_CARD.MP4")
        let importedData = Data("selected-original".utf8)
        let unselectedData = Data("unselected-original".utf8)
        try importedData.write(to: imported)
        try unselectedData.write(to: unselected)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = ScannedFile(
            path: imported.path,
            relativePath: imported.lastPathComponent,
            groupKey: "DJI_SELECTED",
            kind: "video",
            size: Int64(importedData.count),
            captureTime: ISO8601DateFormatter().string(from: Date()),
            duration: 1,
            fps: 30,
            width: 1920,
            height: 1080,
            hasAudio: true
        )
        let group = ShootGroup(id: "selected", name: "Selected Shoot", kind: .client, sourceLabel: "OSMO", sourceKind: .camera, files: [file], start: file.captureTime, end: file.captureTime)
        let offload = try await VerifiedOffloadService().offload(
            group: group,
            sourceRoot: card,
            activeProjectsRoot: active,
            volumeUUID: "fixture-card",
            progress: { _ in }
        )

        let result = try await VerifiedCleanupService().cleanup(
            plans: [offload.cleanupPlan],
            currentSourceRoot: card,
            currentVolumeUUID: "fixture-card",
            progress: { _ in }
        )

        XCTAssertEqual(result.filesDeleted, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: imported.path))
        XCTAssertEqual(try Data(contentsOf: unselected), unselectedData)
        XCTAssertEqual(try Data(contentsOf: offload.mediaRoot.appendingPathComponent(imported.lastPathComponent)), importedData)
    }

    func testVerifiedCleanupBlocksAllDeletionWhenDestinationChanged() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let card = root.appendingPathComponent("card", isDirectory: true)
        let active = root.appendingPathComponent("active", isDirectory: true)
        try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
        let source = card.appendingPathComponent("IMG_1001.MOV")
        let sourceData = Data("iphone-original".utf8)
        try sourceData.write(to: source)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = ScannedFile(
            path: source.path,
            relativePath: source.lastPathComponent,
            groupKey: "IMG_1001",
            kind: "video",
            size: Int64(sourceData.count),
            captureTime: ISO8601DateFormatter().string(from: Date()),
            duration: 1,
            fps: 30,
            width: 1920,
            height: 1080,
            hasAudio: true
        )
        let group = ShootGroup(id: "iphone", name: "iPhone Shoot", kind: .personal, sourceLabel: "IPHONE", sourceKind: .camera, files: [file], start: file.captureTime, end: file.captureTime)
        let offload = try await VerifiedOffloadService().offload(
            group: group,
            sourceRoot: card,
            activeProjectsRoot: active,
            volumeUUID: "iphone-card",
            progress: { _ in }
        )
        try Data("tampered-copy".utf8).write(to: offload.mediaRoot.appendingPathComponent(source.lastPathComponent))

        do {
            _ = try await VerifiedCleanupService().cleanup(
                plans: [offload.cleanupPlan],
                currentSourceRoot: card,
                currentVolumeUUID: "iphone-card",
                progress: { _ in }
            )
            XCTFail("Cleanup should have been blocked")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("no longer matches"))
        }
        XCTAssertEqual(try Data(contentsOf: source), sourceData)
    }
}
