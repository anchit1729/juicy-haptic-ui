import XCTest
@testable import AmbientHaptics

final class ClickRippleTests: XCTestCase {
    func testSingleAndDoubleClickClassification() {
        var classifier = ClickRippleClassifier()
        XCTAssertFalse(classifier.mouseDown(clickCount: 1))
        XCTAssertEqual(classifier.mouseUp(clickCount: 1), .single)
        XCTAssertTrue(classifier.mouseDown(clickCount: 2))
        XCTAssertEqual(classifier.mouseUp(clickCount: 2), .double)
        XCTAssertEqual(ClickRipple.single.waits.count, 2)
        XCTAssertEqual(ClickRipple.double.waits.count, 3)
    }

    func testDragAndTripleClickDoNotStartSplash() {
        var classifier = ClickRippleClassifier()
        XCTAssertFalse(classifier.mouseDown(clickCount: 1))
        classifier.mouseDragged()
        XCTAssertNil(classifier.mouseUp(clickCount: 1))
        XCTAssertTrue(classifier.mouseDown(clickCount: 3))
        XCTAssertNil(classifier.mouseUp(clickCount: 3))
        XCTAssertNil(classifier.mouseUp(clickCount: 1))
    }
}
