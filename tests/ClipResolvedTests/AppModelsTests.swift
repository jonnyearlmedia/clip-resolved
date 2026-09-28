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
