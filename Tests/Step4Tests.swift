import XCTest
@testable import AmbientHaptics

final class Step4Tests: XCTestCase {
    func testOutlookStartsWithBaselineAndCuesOnlyNewMail() throws {
        let first = try OutlookGraphSource.decodeInbox(
            messages: Data(#"{"value":[{"id":"old","receivedDateTime":"2026-10-30T12:00:00Z","isRead":false}]}"#.utf8),
            folder: Data(#"{"unreadItemCount":1}"#.utf8)
        )
        var tracker = OutlookInboxTracker()
        let now = Date(timeIntervalSince1970: 1_793_362_000)
        XCTAssertTrue(tracker.newEvents(from: first, at: now).isEmpty)

        let second = try OutlookGraphSource.decodeInbox(
            messages: Data(#"{"value":[{"id":"new","receivedDateTime":"2026-10-30T12:01:00Z","isRead":false},{"id":"old","receivedDateTime":"2026-10-30T12:00:00Z","isRead":false}]}"#.utf8),
            folder: Data(#"{"unreadItemCount":2}"#.utf8)
        )
        let receivedAt = ISO8601DateFormatter().date(from: "2026-10-30T12:02:00Z")!
        let events = tracker.newEvents(from: second, at: receivedAt)
        XCTAssertEqual(events.map(\.id), ["outlook:new"])
        XCTAssertTrue(tracker.newEvents(from: second, at: receivedAt).isEmpty)
    }

    func testSlackDecodingAndAcknowledgement() throws {
        let now = Date(timeIntervalSince1970: 1_793_362_000)
        let payload = #"{"envelope_id":"env-1","payload":{"type":"event_callback","team_id":"T1","event_id":"Ev1","event":{"type":"message","channel_type":"im","ts":"1793362000"}}}"#
        let envelope = try SlackSocketSource.decode(Data(payload.utf8))
        XCTAssertEqual(envelope.directMessage(allowedTeams: ["T1"], at: now)?.id, "slack:Ev1")
        XCTAssertNil(envelope.directMessage(allowedTeams: ["T2"], at: now))
        XCTAssertEqual(try SlackSocketSource.acknowledgement(for: envelope), #"{"envelope_id":"env-1"}"#)
    }

    func testEventGateRemovesDuplicatesAndGroupsBursts() {
        var gate = EventGate(minimumGap: 5)
        let time = Date(timeIntervalSince1970: 1_000)
        let first = SourceEvent(id: "1", sourceID: "slack", kind: "directMessage", occurredAt: time)
        let second = SourceEvent(id: "2", sourceID: "slack", kind: "directMessage", occurredAt: time)
        XCTAssertTrue(gate.shouldPlay(first, at: time))
        XCTAssertFalse(gate.shouldPlay(first, at: time.addingTimeInterval(1)))
        XCTAssertFalse(gate.shouldPlay(second, at: time.addingTimeInterval(2)))
        let third = SourceEvent(id: "3", sourceID: "slack", kind: "directMessage", occurredAt: time)
        XCTAssertTrue(gate.shouldPlay(third, at: time.addingTimeInterval(6)))
    }
}
