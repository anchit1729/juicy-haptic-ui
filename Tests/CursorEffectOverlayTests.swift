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

    func testCommonAccentsCreateAnimatedLayers() async throws {
        try await MainActor.run {
            guard let screen = NSScreen.screens.first else {
                throw XCTSkip("No display is available for the overlay test.")
            }
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
                throw XCTSkip("Reduce Motion hides cursor accents.")
            }

            let before = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
            let overlay = CursorEffectOverlay()
            defer { overlay.stop() }
            let point = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
            let kinds: [TrackpadVisualKind] = [
                .scrollGrain, .horizontalGrain, .dragTick,
                .clickRipple(isDouble: false, stage: 0), .clickRipple(isDouble: true, stage: 1),
                .secondaryClick, .zoom(outward: true), .zoom(outward: false),
                .smartZoom, .swipe(horizontal: true, positive: false),
                .sourceCue(sourceID: "outlook", stage: 0)
            ]
            for kind in kinds { overlay.show(TrackpadFeedbackEvent(kind: kind, location: point)) }

            let newPanels = NSApplication.shared.windows.compactMap { $0 as? NSPanel }
                .filter { !before.contains(ObjectIdentifier($0)) }
            let layerCount = newPanels.reduce(0) { $0 + ($1.contentView?.layer?.sublayers?.count ?? 0) }
            XCTAssertGreaterThanOrEqual(layerCount, kinds.count)
        }
    }
}
