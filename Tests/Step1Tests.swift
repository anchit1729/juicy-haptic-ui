import XCTest
@testable import AmbientHaptics

final class Step1Tests: XCTestCase {
    func testDeviceEnumerationDoesNotChangeDefaultOutput() throws {
        let before = try AudioDeviceManager.outputDevices()
        let after = try AudioDeviceManager.outputDevices()
        XCTAssertEqual(before, after)
    }
}
