import AppKit
import Foundation

/// AppKit offers fixed trackpad taps. A preview uses only a pattern's pulse timing.
struct TrackpadPulsePlan {
    let count: Int
    let interval: Duration

    init(pattern: HapticPattern) {
        count = min(4, max(1, pattern.pulseCount ?? (pattern.rhythmHz == 0 ? 1 : 3)))
        let milliseconds = pattern.rhythmHz > 0 ? 1_000 / pattern.rhythmHz : 250
        interval = .milliseconds(Int(min(1_000, max(180, milliseconds))))
    }
}

struct TrackpadTapGate {
    let minimumInterval: TimeInterval
    private var lastTapAt = -Double.infinity

    mutating func allow(at time: TimeInterval) -> Bool {
        guard time.isFinite, time - lastTapAt >= minimumInterval else { return false }
        lastTapAt = time
        return true
    }
}

@MainActor
final class TrackpadHapticOutput {
    private var previewTask: Task<Void, Never>?
    private var tapGate = TrackpadTapGate(minimumInterval: 0.10)

    @discardableResult
    func tick() -> Bool {
        guard tapGate.allow(at: ProcessInfo.processInfo.systemUptime) else { return false }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        return true
    }

    func playTestPulse() {
        stop()
        tick()
    }

    func playPreview(_ pattern: HapticPattern, onTick: (@MainActor (Int) -> Void)? = nil) {
        stop()
        let plan = TrackpadPulsePlan(pattern: pattern)
        previewTask = Task {
            for index in 0..<plan.count {
                guard !Task.isCancelled else { return }
                if tick() { onTick?(index) }
                if index + 1 < plan.count {
                    try? await Task.sleep(for: plan.interval)
                }
            }
        }
    }

    func stop() {
        previewTask?.cancel()
        previewTask = nil
    }
}
