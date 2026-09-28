import AppKit
import AVFoundation
import AVKit
import XCTest
@testable import ClipResolved

final class FootagePreviewTests: XCTestCase {
    @MainActor
    func testNativeSidebarOwnsPlayerAndExactHandledRange() {
        _ = NSApplication.shared
        let evidence = ChatEvidence(
            sourcePath: "/tmp/example.mp4",
            start: 15,
            end: 30,
            score: 0.5,
            transcript: nil
        )

        let controller = FootagePreviewSidebarController(evidence: evidence)
        _ = controller.view

        XCTAssertTrue(controller.playerView.player === controller.player)
        XCTAssertEqual(controller.selectedDuration, 15, accuracy: 0.001)
        XCTAssertEqual(controller.evidence.start, 15)
        XCTAssertEqual(controller.evidence.end, 30)

        controller.stop()
    }
}
