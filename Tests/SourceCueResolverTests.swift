import XCTest
@testable import AmbientHaptics

final class SourceCueResolverTests: XCTestCase {
    func testEachSourceUsesItsOwnCueAndDisabledSourcesStayQuiet() {
        let patterns = StarterPatterns.all
        var sources = SourceCatalogue.initialConfigurations(patterns: patterns)
        let outlook = SourceEvent(id: "mail-1", sourceID: "outlook", kind: "newEmail", occurredAt: .now)
        let slack = SourceEvent(id: "slack-1", sourceID: "slack", kind: "directMessage", occurredAt: .now)

        let mailPattern = SourceCueResolver.pattern(for: outlook, configurations: sources, patterns: patterns)
        let slackPattern = SourceCueResolver.pattern(for: slack, configurations: sources, patterns: patterns)
        XCTAssertEqual(mailPattern?.name, "Outlook email")
        XCTAssertEqual(slackPattern?.name, "Slack message")

        sources[sourceIndex("slack", in: sources)].enabled = false
        XCTAssertNil(SourceCueResolver.pattern(for: slack, configurations: sources, patterns: patterns))
        XCTAssertNil(SourceCueResolver.pattern(
            for: SourceEvent(id: "unknown", sourceID: "outlook", kind: "other", occurredAt: .now),
            configurations: sources,
            patterns: patterns
        ))
    }

    private func sourceIndex(_ id: String, in sources: [SourceConfiguration]) -> Int {
        sources.firstIndex(where: { $0.id == id })!
    }
}
