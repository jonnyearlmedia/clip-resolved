import XCTest
import OffloadCore
@testable import OffloadEngine
@testable import ClipResolved

/// Exercises VerifiedCleanupService.cleanup() — the destructive step — against real
/// disposable temp-directory fixtures only. Every test proves the all-or-nothing safety
/// property on-disk (source files really deleted or really untouched), not just the
/// thrown error. This is disposable-fixture evidence, not the real-card proof Gate 2
/// ultimately requires. Never point this at a real removable card.
///
/// AppModelsTests.swift already covers the happy path and a single-file destination-
/// tamper block; these cover a wrong-source-root block and a multi-file batch where only
/// one of several destinations is tampered, proving the block isn't per-file but per-batch.
final class VerifiedCleanupServiceTests: XCTestCase {
    var tempRoot: URL!
    var sourceRoot: URL!
    var destRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cr-cleanup-tests-\(UUID().uuidString)", isDirectory: true)
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
        try Data((0..<bytes).map { _ in UInt8.random(in: 0...255) }).write(to: url)
        return url
    }

    private func scannedFile(for url: URL, relativePath: String) throws -> ScannedFile {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return ScannedFile(
            path: url.path, relativePath: relativePath, groupKey: relativePath, kind: "video",
            size: Int64(values.fileSize ?? 0),
            captureTime: ISO8601DateFormatter().string(from: Date()),
            duration: 5.0, fps: 29.97, width: 1920, height: 1080, hasAudio: true
        )
    }

    /// Runs a real offload of two fixture files and returns the resulting cleanup plan
    /// plus the original source file URLs, ready for a cleanup() call.
    private func offloadedFixture(volumeUUID: String = "TEST-VOLUME-UUID") async throws -> (plan: VerifiedCleanupPlan, sources: [URL]) {
        let file1 = try writeDummyFile(named: "DJI_0001.MP4", in: sourceRoot)
        let file2 = try writeDummyFile(named: "DJI_0002.MP4", in: sourceRoot)
        let group = ShootGroup(
            id: UUID().uuidString, name: "TEST SHOOT", kind: .personal,
            sourceLabel: "OSMO", sourceKind: .camera,
            files: [
                try scannedFile(for: file1, relativePath: "DJI_0001.MP4"),
                try scannedFile(for: file2, relativePath: "DJI_0002.MP4"),
            ],
            start: "2026-09-29T00:00:00Z", end: "2026-09-29T00:05:00Z"
        )
        let offloadResult = try await VerifiedOffloadService().offload(
            group: group, sourceRoot: sourceRoot, activeProjectsRoot: destRoot,
            volumeUUID: volumeUUID, progress: { _ in }
        )
        return (offloadResult.cleanupPlan, [file1, file2])
    }

    func testCleanupBlockedWhenSourceRootDoesNotMatchImportedSource() async throws {
        let (plan, sources) = try await offloadedFixture()
        let wrongSource = tempRoot.appendingPathComponent("not-the-real-card", isDirectory: true)
        try FileManager.default.createDirectory(at: wrongSource, withIntermediateDirectories: true)

        do {
            _ = try await VerifiedCleanupService().cleanup(
                plans: [plan], currentSourceRoot: wrongSource, currentVolumeUUID: "TEST-VOLUME-UUID",
                progress: { _ in }
            )
            XCTFail("cleanup must refuse when the source root does not match the imported source")
        } catch {
            // expected
        }

        for source in sources {
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "nothing may be deleted when the source check fails: \(source.path)")
        }
    }

    func testCleanupBlockedForEntireBatchWhenOneDestinationFileIsTampered() async throws {
        let (plan, sources) = try await offloadedFixture()

        // Tamper with exactly one destination file after the verified copy completed.
        guard let tamperedDestination = plan.destinationByFileID.values.first(where: { $0.hasSuffix("DJI_0002.MP4") }) else {
            XCTFail("expected a destination path for DJI_0002.MP4")
            return
        }
        try Data("tampered after verified copy".utf8).write(to: URL(fileURLWithPath: tamperedDestination))

        do {
            _ = try await VerifiedCleanupService().cleanup(
                plans: [plan], currentSourceRoot: sourceRoot, currentVolumeUUID: "TEST-VOLUME-UUID",
                progress: { _ in }
            )
            XCTFail("cleanup must refuse the whole batch when any destination no longer matches its verified hash")
        } catch {
            // expected
        }

        // All-or-nothing: even DJI_0001.MP4, whose destination was untouched, must
        // survive on the source because its sibling in the same batch failed recheck.
        for source in sources {
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "one tampered destination must block the entire batch: \(source.path)")
        }
    }
}
