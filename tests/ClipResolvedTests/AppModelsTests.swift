import XCTest
@testable import ClipResolved

final class AppModelsTests: XCTestCase {
    func testEditorTimecode() {
        XCTAssertEqual(65.25.editorTimecode, "00:01:05.25")
    }

    func testProjectKindPathsAreStable() {
        XCTAssertEqual(ProjectKind.client.rawValue, "Client")
        XCTAssertEqual(ProjectKind.personal.rawValue, "Personal")
    }

    func testClaudeStructuredIntentDecodesWithMemory() throws {
        let payload = #"{"is_error":false,"structured_output":{"message":"I will search the existing index.","action":"propose_selects","query":"food shots","timeline_name":"FOOD SHOTS SELECTS","search_mode":"Visual","profile":null,"memory_updates":[{"scope":"All projects","category":"Editing preference","content":"Use two-second pre-roll handles."}],"pre_handle_seconds":2,"post_handle_seconds":null,"minimum_duration_seconds":null}}"#
        let intent = try ClaudeChatService.decodeIntent(Data(payload.utf8))

        XCTAssertEqual(intent.action, .proposeSelects)
        XCTAssertEqual(intent.query, "food shots")
        XCTAssertEqual(intent.searchMode, .visual)
        XCTAssertEqual(intent.memoryUpdates.count, 1)
        XCTAssertEqual(intent.memoryUpdates.first?.scope, .global)
        XCTAssertEqual(intent.memoryUpdates.first?.content, "Use two-second pre-roll handles.")
        XCTAssertEqual(intent.preHandleSeconds, 2)
    }

    func testSmartSelectsResultDecodesProfessionalPackage() throws {
        let payload = #"{"project":"OSAKA","profile":"restaurant","categories":[{"name":"FOOD SHOTS SELECTS","query":"food dishes plated meals","timeline":"FOOD SHOTS SELECTS","moments":12,"ranges_requested":12,"ranges_appended":12}],"category_timelines_created":1,"selected_ranges":12,"stringout_timeline":"00 ALL RAW FOOTAGE STRINGOUT","stringout_ranges_requested":65,"stringout_ranges_appended":65,"remainder_timeline":"ALL FOOTAGE NOT SELECTED REVIEW","remainder_ranges_requested":20,"remainder_ranges_appended":20,"indexed_assets":65,"coverage_complete":true}"#
        let result = try JSONDecoder().decode(SmartSelectsResult.self, from: Data(payload.utf8))

        XCTAssertEqual(result.categoryTimelinesCreated, 1)
        XCTAssertEqual(result.categories.first?.timeline, "FOOD SHOTS SELECTS")
        XCTAssertEqual(result.stringoutTimeline, "00 ALL RAW FOOTAGE STRINGOUT")
        XCTAssertEqual(result.remainderTimeline, "ALL FOOTAGE NOT SELECTED REVIEW")
        XCTAssertTrue(result.coverageComplete)
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
        let group = ShootGroup(id: "test", name: "Test Shoot", kind: .client, files: [file], start: file.captureTime, end: file.captureTime)
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.projectRoot.appendingPathComponent(".clip-resolved/manifests/ingest-manifest.json").path))
        XCTAssertEqual(result.filesVerified, 1)
    }
}
