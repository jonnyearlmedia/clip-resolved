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

    @MainActor
    func testPreviewControlsRemainActionableInsideLargePlaybackSheet() throws {
        _ = NSApplication.shared
        var closed = false
        let evidence = ChatEvidence(
            sourcePath: "/tmp/example.mp4",
            start: 15,
            end: 30,
            score: 0.5,
            transcript: nil
        )
        let controller = FootagePreviewSidebarController(evidence: evidence, onClose: { closed = true })
        let root = controller.view
        let buttons = root.allSubviews.compactMap { $0 as? NSButton }

        XCTAssertNotNil(buttons.first { $0.title == "Replay Range" })
        XCTAssertNotNil(buttons.first { $0.title == "View Full Source" })
        XCTAssertNotNil(buttons.first { $0.title == "Reveal in Finder" })
        let close = try XCTUnwrap(buttons.first { $0.image?.accessibilityDescription == "Close preview" })
        close.performClick(nil)
        XCTAssertTrue(closed)
        controller.stop()
    }
}

private extension NSView {
    var allSubviews: [NSView] {
        subviews + subviews.flatMap(\.allSubviews)
    }
}
