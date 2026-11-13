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

@MainActor
final class TrackpadHapticOutput {
    private var previewTask: Task<Void, Never>?

    func playTestPulse() {
        stop()
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    func playPreview(_ pattern: HapticPattern) {
        stop()
        let plan = TrackpadPulsePlan(pattern: pattern)
        previewTask = Task {
            for index in 0..<plan.count {
                guard !Task.isCancelled else { return }
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
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
