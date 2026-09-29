import XCTest
import OffloadCore
@testable import OffloadEngine
@testable import ClipResolved

/// Exercises VerifiedOffloadService.offload() against real disposable temp-directory
/// fixtures on this Mac's local disk. This is real file-copy/hash/journal code running
/// for real — not mocked — but it is NOT a substitute for the still-outstanding real-card
/// interrupted-copy-and-relaunch proof Gate 2 ultimately requires. Never point this at a
/// real removable card or a real project drive.
///
/// AppModelsTests.swift already covers the offload happy path (incl. later-source and
/// mic-audio routing); these two cover the crash/retry edges it doesn't.
final class VerifiedOffloadServiceTests: XCTestCase {
    var tempRoot: URL!
    var sourceRoot: URL!
    var destRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cr-offload-tests-\(UUID().uuidString)", isDirectory: true)
        sourceRoot = tempRoot.appendingPathComponent("source", isDirectory: true)
        destRoot = tempRoot.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func writeDummyFile(named name: String, in directory: URL, bytes: Int = 4096) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        let data = Data((0..<bytes).map { _ in UInt8.random(in: 0...255) })
        try data.write(to: url)
        return url
    }

    private func scannedFile(for url: URL, relativePath: String) throws -> ScannedFile {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return ScannedFile(
            path: url.path,
            relativePath: relativePath,
            groupKey: relativePath,
            kind: "video",
            size: Int64(values.fileSize ?? 0),
            captureTime: ISO8601DateFormatter().string(from: Date()),
            duration: 5.0,
            fps: 29.97,
            width: 1920,
            height: 1080,
            hasAudio: true
        )
    }

    private func makeGroup(files: [ScannedFile]) -> ShootGroup {
        ShootGroup(
            id: UUID().uuidString,
            name: "TEST SHOOT",
            kind: .personal,
            sourceLabel: "OSMO",
            sourceKind: .camera,
            files: files,
            start: "2026-09-29T00:00:00Z",
            end: "2026-09-29T00:05:00Z"
        )
    }

    func testOffloadRerunIsIdempotentAndDoesNotDuplicateFiles() async throws {
        let file1 = try writeDummyFile(named: "DJI_0010.MP4", in: sourceRoot)
        let group = makeGroup(files: [try scannedFile(for: file1, relativePath: "DJI_0010.MP4")])
        let service = VerifiedOffloadService()

        let first = try await service.offload(
            group: group, sourceRoot: sourceRoot, activeProjectsRoot: destRoot,
            volumeUUID: "TEST-VOLUME-UUID", progress: { _ in }
        )
        XCTAssertEqual(first.filesVerified, 1)

        let second = try await service.offload(
            group: group, sourceRoot: sourceRoot, activeProjectsRoot: destRoot,
            volumeUUID: "TEST-VOLUME-UUID", progress: { _ in }
        )
        XCTAssertEqual(second.filesVerified, 1)

        // A second run must recognize the already-present, hash-matching file as a
        // duplicate rather than error, overwrite, or create a "-2" sibling.
        let siblingsInMediaRoot = try FileManager.default.contentsOfDirectory(atPath: second.mediaRoot.path)
        XCTAssertEqual(siblingsInMediaRoot, ["DJI_0010.MP4"])
    }

    func testOffloadDiscardsStrayPartialFileFromAPreviousCrash() async throws {
        let file1 = try writeDummyFile(named: "DJI_0020.MP4", in: sourceRoot, bytes: 8192)
        let group = makeGroup(files: [try scannedFile(for: file1, relativePath: "DJI_0020.MP4")])

        // Simulate a prior run that crashed mid-copy: a stray .crpartial with garbage
        // bytes sitting where the real destination file would land, but no final file yet.
        let expectedMediaRoot = destRoot
            .appendingPathComponent("Personal", isDirectory: true)
            .appendingPathComponent("TEST SHOOT", isDirectory: true)
            .appendingPathComponent("Media/OSMO", isDirectory: true)
        try FileManager.default.createDirectory(at: expectedMediaRoot, withIntermediateDirectories: true)
        let strayPartial = expectedMediaRoot.appendingPathComponent("DJI_0020.MP4.crpartial")
        try Data("not the real file".utf8).write(to: strayPartial)

        let service = VerifiedOffloadService()
        let result = try await service.offload(
            group: group, sourceRoot: sourceRoot, activeProjectsRoot: destRoot,
            volumeUUID: "TEST-VOLUME-UUID", progress: { _ in }
        )

        XCTAssertEqual(result.filesVerified, 1)
        let destFile = result.mediaRoot.appendingPathComponent("DJI_0020.MP4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destFile.path))
        // The final file must be the real, correctly verified copy, not the stray garbage.
        XCTAssertEqual(try Data(contentsOf: destFile), try Data(contentsOf: file1))
        // No leftover partial file after a successful run.
        XCTAssertFalse(FileManager.default.fileExists(atPath: strayPartial.path))
    }
}
