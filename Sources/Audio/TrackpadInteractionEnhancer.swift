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
    case horizontalGrain
    case dragTick
    case clickRipple(isDouble: Bool, stage: Int)
    case secondaryClick
    case zoom(outward: Bool)
    case smartZoom
    case swipe(horizontal: Bool, positive: Bool)
    case sourceCue(sourceID: String, stage: Int)
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

/// Reads pointer and gesture events. It never changes or stores the input events.
@MainActor
final class TrackpadInteractionEnhancer {
    var onTick: ((TrackpadFeedbackEvent) -> Void)?

    private let output: TrackpadHapticOutput
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var scrollGate = DistanceTickGate(spacing: 18, minimumInterval: 0.10)
    private var dragGate = DistanceTickGate(spacing: 32, minimumInterval: 0.15)
    private var zoomGate = DistanceTickGate(spacing: 0.12, minimumInterval: 0.15)
    private var lastDragPoint: NSPoint?
    private var dragDistance = 0.0
    private var lastFeedbackAt = -Double.infinity
    private var lastSwipeAt = -Double.infinity
    private var scrollEnabled = false
    private var dragEnabled = false
    private var clickEnabled = false
    private var secondaryClickEnabled = false
    private var gesturesEnabled = false
    private var secondaryPressed = false
    private var clickClassifier = ClickRippleClassifier()
    private var clickTask: Task<Void, Never>?

    init(output: TrackpadHapticOutput) { self.output = output }

    /// Returns false when macOS declines the systemwide monitor.
    @discardableResult
    func configure(scroll: Bool, drag: Bool, clicks: Bool, secondaryClicks: Bool, gestures: Bool, grainSpacing: Double) -> Bool {
        scrollEnabled = scroll
        dragEnabled = drag
        clickEnabled = clicks
        secondaryClickEnabled = secondaryClicks
        gesturesEnabled = gestures
        scrollGate.spacing = min(40, max(8, grainSpacing))
        if !clicks { cancelClickRipple() }
        guard scroll || drag || clicks || secondaryClicks || gestures else { stop(); return true }
        if globalMonitor == nil && localMonitor == nil {
            let mask: NSEvent.EventTypeMask = [
                .scrollWheel, .leftMouseDown, .leftMouseDragged, .leftMouseUp,
                .rightMouseDown, .rightMouseDragged, .rightMouseUp,
                .magnify, .smartMagnify, .swipe
            ]
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
        zoomGate.reset()
        lastDragPoint = nil
        dragDistance = 0
        lastFeedbackAt = -Double.infinity
        lastSwipeAt = -Double.infinity
        secondaryPressed = false
        clickClassifier.reset()
    }

    private func handle(_ event: NSEvent) {
        let time = ProcessInfo.processInfo.systemUptime
        switch event.type {
        case .scrollWheel where scrollEnabled:
            guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return }
            let movement = abs(event.scrollingDeltaX) + abs(event.scrollingDeltaY)
            if scrollGate.feed(movement, at: time) {
                let kind: TrackpadVisualKind = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                    ? .horizontalGrain : .scrollGrain
                tick(at: time, kind: kind, location: NSEvent.mouseLocation)
            }
        case .leftMouseDown:
            lastDragPoint = NSEvent.mouseLocation
            dragDistance = 0
            dragGate.reset()
            if clickClassifier.mouseDown(clickCount: event.clickCount) { cancelClickRipple() }
        case .leftMouseDragged where dragEnabled:
            clickClassifier.mouseDragged()
            let point = NSEvent.mouseLocation
            defer { lastDragPoint = point }
            guard let previous = lastDragPoint else { return }
            let movement = hypot(point.x - previous.x, point.y - previous.y)
            if movement.isFinite { dragDistance = min(8, dragDistance + movement) }
            if dragGate.feed(movement, at: time) {
                tick(at: time, kind: .dragTick, location: point)
            }
        case .leftMouseDragged:
            clickClassifier.mouseDragged()
        case .leftMouseUp:
            if dragEnabled && dragDistance >= 8 {
                tick(at: time, kind: .dragTick, location: NSEvent.mouseLocation)
            }
            lastDragPoint = nil
            dragDistance = 0
            dragGate.reset()
            if let ripple = clickClassifier.mouseUp(clickCount: event.clickCount), clickEnabled {
                playClickRipple(ripple, at: NSEvent.mouseLocation)
            }
        case .rightMouseDown where secondaryClickEnabled:
            secondaryPressed = true
        case .rightMouseDragged:
            secondaryPressed = false
        case .rightMouseUp:
            let wasPressed = secondaryPressed
            secondaryPressed = false
            guard secondaryClickEnabled, wasPressed else { return }
            playDelayedTick(kind: .secondaryClick, at: NSEvent.mouseLocation)
        case .magnify where gesturesEnabled:
            if event.phase.contains(.began) { zoomGate.reset() }
            if zoomGate.feed(abs(event.magnification), at: time) {
                tick(at: time, kind: .zoom(outward: event.magnification > 0), location: NSEvent.mouseLocation)
            }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) { zoomGate.reset() }
        case .smartMagnify where gesturesEnabled:
            tick(at: time, kind: .smartZoom, location: NSEvent.mouseLocation)
        case .swipe where gesturesEnabled:
            guard time - lastSwipeAt >= 0.5 else { return }
            lastSwipeAt = time
            let horizontal = abs(event.deltaX) >= abs(event.deltaY)
            tick(
                at: time,
                kind: .swipe(horizontal: horizontal, positive: horizontal ? event.deltaX > 0 : event.deltaY > 0),
                location: NSEvent.mouseLocation
            )
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

    private func playDelayedTick(kind: TrackpadVisualKind, at location: NSPoint) {
        cancelClickRipple()
        clickTask = Task {
            do { try await Task.sleep(for: .milliseconds(90)) }
            catch { return }
            tick(at: ProcessInfo.processInfo.systemUptime, kind: kind, location: location)
        }
    }

    private func tick(at time: TimeInterval, kind: TrackpadVisualKind, location: NSPoint) {
        guard time - lastFeedbackAt >= 0.10 else { return }
        guard output.tick() else { return }
        lastFeedbackAt = time
        onTick?(TrackpadFeedbackEvent(kind: kind, location: location))
    }
}
