import XCTest
@testable import AmbientHaptics

final class TrackpadPulsePlanTests: XCTestCase {
    func testMessageCuesKeepTheirTapCounts() {
        let outlook = TrackpadPulsePlan(pattern: StarterPatterns.all[3])
        let slack = TrackpadPulsePlan(pattern: StarterPatterns.all[4])
        XCTAssertEqual(outlook.count, 2)
        XCTAssertEqual(slack.count, 3)
        XCTAssertGreaterThanOrEqual(outlook.interval, .milliseconds(180))
    }

    func testFastPatternsStayWithinTrackpadPreviewLimits() {
        let pattern = HapticPattern(
            name: "Fast preview",
            bands: [],
            rhythmHz: 12,
            variation: 0,
            pulseLength: 0.05,
            strength: 1,
            pulseCount: 12
        )
        let plan = TrackpadPulsePlan(pattern: pattern)
        XCTAssertEqual(plan.count, 4)
        XCTAssertEqual(plan.interval, .milliseconds(180))
    }

    func testInteractionAndMessageTapsShareOneRateLimit() {
        var gate = TrackpadTapGate(minimumInterval: 0.10)
        XCTAssertTrue(gate.allow(at: 10))
        XCTAssertFalse(gate.allow(at: 10.05))
        XCTAssertTrue(gate.allow(at: 10.11))
    }
}
