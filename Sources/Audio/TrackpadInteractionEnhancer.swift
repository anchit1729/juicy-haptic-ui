import AppKit
import Foundation

/// Limits tactile requests by travel distance and time.
struct DistanceTickGate {
    var spacing: Double
    let minimumInterval: TimeInterval
    private(set) var distance = 0.0
    private(set) var lastTickAt = -Double.infinity

    mutating func feed(_ movement: Double, at time: TimeInterval) -> Bool {
        guard movement.isFinite, movement > 0, time.isFinite else { return false }
        distance = min(spacing, distance + min(movement, spacing))
        guard distance >= spacing, time - lastTickAt >= minimumInterval else { return false }
        distance = 0
        lastTickAt = time
        return true
    }

    mutating func reset() { distance = 0 }
}

/// Reads only scroll and drag motion. It never changes or stores the input events.
@MainActor
final class TrackpadInteractionEnhancer {
    var onTick: (() -> Void)?

    private let output: TrackpadHapticOutput
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var scrollGate = DistanceTickGate(spacing: 18, minimumInterval: 0.10)
    private var dragGate = DistanceTickGate(spacing: 32, minimumInterval: 0.15)
    private var lastDragPoint: NSPoint?
    private var lastFeedbackAt = -Double.infinity
    private var scrollEnabled = false
    private var dragEnabled = false

    init(output: TrackpadHapticOutput) { self.output = output }

    /// Returns false when macOS declines the systemwide monitor.
    @discardableResult
    func configure(scroll: Bool, drag: Bool, grainSpacing: Double) -> Bool {
        scrollEnabled = scroll
        dragEnabled = drag
        scrollGate.spacing = min(40, max(8, grainSpacing))
        guard scroll || drag else { stop(); return true }
        if globalMonitor == nil && localMonitor == nil {
            let mask: NSEvent.EventTypeMask = [.scrollWheel, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) }
            }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) }
                return event
            }
        }
        return globalMonitor != nil
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        scrollGate.reset()
        dragGate.reset()
        lastDragPoint = nil
        lastFeedbackAt = -Double.infinity
    }

    private func handle(_ event: NSEvent) {
        let time = ProcessInfo.processInfo.systemUptime
        switch event.type {
        case .scrollWheel where scrollEnabled:
            guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return }
            let movement = abs(event.scrollingDeltaX) + abs(event.scrollingDeltaY)
            if scrollGate.feed(movement, at: time) { tick(at: time) }
        case .leftMouseDown:
            lastDragPoint = NSEvent.mouseLocation
            dragGate.reset()
        case .leftMouseDragged where dragEnabled:
            let point = NSEvent.mouseLocation
            defer { lastDragPoint = point }
            guard let previous = lastDragPoint else { return }
            let movement = hypot(point.x - previous.x, point.y - previous.y)
            if dragGate.feed(movement, at: time) { tick(at: time) }
        case .leftMouseUp:
            lastDragPoint = nil
            dragGate.reset()
        default:
            break
        }
    }

    private func tick(at time: TimeInterval) {
        guard time - lastFeedbackAt >= 0.10 else { return }
        lastFeedbackAt = time
        output.tick()
        onTick?()
    }
}
