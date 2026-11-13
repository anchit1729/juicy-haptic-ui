import AppKit
import XCTest
@testable import AmbientHaptics

final class CursorEffectOverlayTests: XCTestCase {
    func testOverlayLetsPointerEventsPassThrough() async throws {
        try await MainActor.run {
            guard let screen = NSScreen.screens.first else {
                throw XCTSkip("No display is available for the overlay test.")
            }
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
                throw XCTSkip("Reduce Motion hides cursor accents.")
            }

            let before = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
            let overlay = CursorEffectOverlay()
            overlay.show(TrackpadFeedbackEvent(kind: .scrollGrain, location: NSPoint(x: screen.frame.midX, y: screen.frame.midY)))
            defer { overlay.stop() }

            let panels = NSApplication.shared.windows.compactMap { $0 as? NSPanel }
                .filter { !before.contains(ObjectIdentifier($0)) }
            XCTAssertFalse(panels.isEmpty)
            XCTAssertTrue(panels.allSatisfy(\.ignoresMouseEvents))
            XCTAssertTrue(panels.allSatisfy { !$0.isOpaque })
        }
    }
}
