import Foundation

/// Removes repeated events and groups rapid cues from one source.
struct EventGate {
    private var seen = Set<String>()
    private var order: [String] = []
    private var lastCueAt: [String: Date] = [:]
    let minimumGap: TimeInterval

    init(minimumGap: TimeInterval = 5) {
        self.minimumGap = minimumGap
    }

    mutating func shouldPlay(_ event: SourceEvent, at now: Date = Date()) -> Bool {
        guard !seen.contains(event.id) else { return false }
        seen.insert(event.id)
        order.append(event.id)
        if order.count > 500 {
            seen.remove(order.removeFirst())
        }
        guard now.timeIntervalSince(lastCueAt[event.sourceID] ?? .distantPast) >= minimumGap else {
            return false
        }
        lastCueAt[event.sourceID] = now
        return true
    }
}
