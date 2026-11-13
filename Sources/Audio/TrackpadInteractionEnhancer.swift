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

enum ClickRipple: Equatable {
    case single
    case double

    /// Each wait follows the preceding tap. The built-in click provides the first impact.
    var waits: [Duration] {
        switch self {
        case .single: [.milliseconds(90), .milliseconds(140)]
        case .double: [.milliseconds(90), .milliseconds(120), .milliseconds(160)]
        }
    }
}

enum TrackpadVisualKind {
    case scrollGrain
    case dragTick
    case clickRipple(isDouble: Bool, stage: Int)
}

struct TrackpadFeedbackEvent {
    let kind: TrackpadVisualKind
    let location: NSPoint
}

/// Distinguishes a click from a drag and recognises AppKit's double-click count.
struct ClickRippleClassifier {
    private var sawDown = false
    private var dragged = false

    mutating func mouseDown(clickCount: Int) -> Bool {
        sawDown = true
        dragged = false
        return clickCount >= 2
    }

    mutating func mouseDragged() { dragged = true }

    mutating func mouseUp(clickCount: Int) -> ClickRipple? {
        defer { sawDown = false }
        guard sawDown, !dragged else { return nil }
        switch clickCount {
        case 1: return .single
        case 2: return .double
        default: return nil
        }
    }

    mutating func reset() {
        sawDown = false
        dragged = false
    }
}

/// Reads scroll, drag, and click events. It never changes or stores the input events.
@MainActor
final class TrackpadInteractionEnhancer {
    var onTick: ((TrackpadFeedbackEvent) -> Void)?

    private let output: TrackpadHapticOutput
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var scrollGate = DistanceTickGate(spacing: 18, minimumInterval: 0.10)
    private var dragGate = DistanceTickGate(spacing: 32, minimumInterval: 0.15)
    private var lastDragPoint: NSPoint?
    private var lastFeedbackAt = -Double.infinity
    private var scrollEnabled = false
    private var dragEnabled = false
    private var clickEnabled = false
    private var clickClassifier = ClickRippleClassifier()
    private var clickTask: Task<Void, Never>?

    init(output: TrackpadHapticOutput) { self.output = output }

    /// Returns false when macOS declines the systemwide monitor.
    @discardableResult
    func configure(scroll: Bool, drag: Bool, clicks: Bool, grainSpacing: Double) -> Bool {
        scrollEnabled = scroll
        dragEnabled = drag
        clickEnabled = clicks
        scrollGate.spacing = min(40, max(8, grainSpacing))
        if !clicks { cancelClickRipple() }
        guard scroll || drag || clicks else { stop(); return true }
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
        cancelClickRipple()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        scrollGate.reset()
        dragGate.reset()
        lastDragPoint = nil
        lastFeedbackAt = -Double.infinity
        clickClassifier.reset()
    }

    private func handle(_ event: NSEvent) {
        let time = ProcessInfo.processInfo.systemUptime
        switch event.type {
        case .scrollWheel where scrollEnabled:
            guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return }
            let movement = abs(event.scrollingDeltaX) + abs(event.scrollingDeltaY)
            if scrollGate.feed(movement, at: time) {
                tick(at: time, kind: .scrollGrain, location: NSEvent.mouseLocation)
            }
        case .leftMouseDown:
            lastDragPoint = NSEvent.mouseLocation
            dragGate.reset()
            if clickClassifier.mouseDown(clickCount: event.clickCount) { cancelClickRipple() }
        case .leftMouseDragged where dragEnabled:
            clickClassifier.mouseDragged()
            let point = NSEvent.mouseLocation
            defer { lastDragPoint = point }
            guard let previous = lastDragPoint else { return }
            let movement = hypot(point.x - previous.x, point.y - previous.y)
            if dragGate.feed(movement, at: time) {
                tick(at: time, kind: .dragTick, location: point)
            }
        case .leftMouseDragged:
            clickClassifier.mouseDragged()
        case .leftMouseUp:
            lastDragPoint = nil
            dragGate.reset()
            if let ripple = clickClassifier.mouseUp(clickCount: event.clickCount), clickEnabled {
                playClickRipple(ripple, at: NSEvent.mouseLocation)
            }
        default:
            break
        }
    }

    private func playClickRipple(_ ripple: ClickRipple, at location: NSPoint) {
        cancelClickRipple()
        clickTask = Task {
            for (stage, wait) in ripple.waits.enumerated() {
                do { try await Task.sleep(for: wait) }
                catch { return }
                guard !Task.isCancelled else { return }
                tick(
                    at: ProcessInfo.processInfo.systemUptime,
                    kind: .clickRipple(isDouble: ripple == .double, stage: stage),
                    location: location
                )
            }
        }
    }

    private func cancelClickRipple() {
        clickTask?.cancel()
        clickTask = nil
    }

    private func tick(at time: TimeInterval, kind: TrackpadVisualKind, location: NSPoint) {
        guard time - lastFeedbackAt >= 0.10 else { return }
        lastFeedbackAt = time
        output.tick()
        onTick?(TrackpadFeedbackEvent(kind: kind, location: location))
    }
}
