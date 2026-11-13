import XCTest
@testable import AmbientHaptics

final class TrackpadInteractionTests: XCTestCase {
    func testTravelAndTimeLimitScrollTicks() {
        var gate = DistanceTickGate(spacing: 18, minimumInterval: 0.10)
        XCTAssertFalse(gate.feed(8, at: 10))
        XCTAssertTrue(gate.feed(10, at: 10.01))
        XCTAssertFalse(gate.feed(40, at: 10.05))
        XCTAssertTrue(gate.feed(1, at: 10.12))
        XCTAssertFalse(gate.feed(0, at: 10.30))
    }

    func testResetDropsUnfinishedDragTravel() {
        var gate = DistanceTickGate(spacing: 32, minimumInterval: 0.15)
        XCTAssertFalse(gate.feed(20, at: 1))
        gate.reset()
        XCTAssertFalse(gate.feed(20, at: 2))
        XCTAssertTrue(gate.feed(12, at: 2.1))
    }
}
