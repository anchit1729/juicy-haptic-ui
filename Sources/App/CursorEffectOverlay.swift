import AppKit
import QuartzCore

/// Shows brief accents near the pointer without changing its shape or receiving input.
@MainActor
final class CursorEffectOverlay {
    private struct Surface {
        let frame: NSRect
        let window: NSPanel
        let layer: CALayer
    }

    private var surfaces: [Surface] = []

    func show(_ feedback: TrackpadFeedbackEvent) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        refreshScreensIfNeeded()
        guard let surface = surfaces.first(where: { $0.frame.contains(feedback.location) }) else { return }
        let point = NSPoint(
            x: feedback.location.x - surface.frame.minX,
            y: feedback.location.y - surface.frame.minY
        )

        switch feedback.kind {
        case .scrollGrain:
            showGrains(at: point, on: surface.layer)
        case .dragTick:
            showDragMark(at: point, on: surface.layer)
        case let .clickRipple(isDouble, stage):
            showRipple(at: point, on: surface.layer, isDouble: isDouble, stage: stage)
        }
    }

    func stop() {
        for surface in surfaces { surface.window.close() }
        surfaces.removeAll()
    }

    private func refreshScreensIfNeeded() {
        let screens = NSScreen.screens
        guard surfaces.count != screens.count || zip(surfaces, screens).contains(where: { $0.frame != $1.frame }) else {
            return
        }
        stop()
        surfaces = screens.compactMap { screen in
            let window = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.hidesOnDeactivate = false
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.clear.cgColor
            window.contentView = view
            guard let layer = view.layer else { return nil }
            window.orderFrontRegardless()
            return Surface(frame: screen.frame, window: window, layer: layer)
        }
    }

    private func showGrains(at point: NSPoint, on parent: CALayer) {
        let sand = NSColor(calibratedRed: 0.91, green: 0.66, blue: 0.33, alpha: 0.9)
        for (index, offset) in [NSPoint(x: -10, y: 6), NSPoint(x: 8, y: 10), NSPoint(x: 12, y: -5)].enumerated() {
            let size: CGFloat = index == 1 ? 3 : 2
            let centre = NSPoint(x: point.x + offset.x, y: point.y + offset.y)
            let grain = CAShapeLayer()
            grain.frame = NSRect(x: centre.x - size / 2, y: centre.y - size / 2, width: size, height: size)
            grain.path = CGPath(ellipseIn: NSRect(x: 0, y: 0, width: size, height: size), transform: nil)
            grain.fillColor = sand.cgColor
            animate(grain, on: parent, duration: 0.23, scale: (1, 0.6), travel: NSPoint(x: offset.x * 0.4, y: offset.y * 0.4))
        }
    }

    private func showDragMark(at point: NSPoint, on parent: CALayer) {
        let mark = CAShapeLayer()
        mark.frame = NSRect(x: point.x + 7, y: point.y + 5, width: 9, height: 9)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 4.5, y: 0))
        path.addLine(to: CGPoint(x: 9, y: 4.5))
        path.addLine(to: CGPoint(x: 4.5, y: 9))
        path.addLine(to: CGPoint(x: 0, y: 4.5))
        path.closeSubpath()
        mark.path = path
        mark.fillColor = NSColor(calibratedRed: 0.37, green: 0.75, blue: 0.92, alpha: 0.9).cgColor
        animate(mark, on: parent, duration: 0.22, scale: (0.7, 1.25))
    }

    private func showRipple(at point: NSPoint, on parent: CALayer, isDouble: Bool, stage: Int) {
        let diameter: CGFloat = isDouble ? 22 + CGFloat(stage * 6) : 18 + CGFloat(stage * 5)
        let ring = CAShapeLayer()
        ring.frame = NSRect(
            x: point.x - diameter / 2,
            y: point.y - diameter / 2,
            width: diameter,
            height: diameter
        )
        ring.path = CGPath(ellipseIn: NSRect(x: 1, y: 1, width: diameter - 2, height: diameter - 2), transform: nil)
        ring.fillColor = NSColor.clear.cgColor
        ring.strokeColor = (isDouble
            ? NSColor(calibratedRed: 0.49, green: 0.75, blue: 1, alpha: 0.8)
            : NSColor(calibratedRed: 0.43, green: 0.86, blue: 0.76, alpha: 0.8)).cgColor
        ring.lineWidth = 1.5
        animate(ring, on: parent, duration: 0.38, scale: (0.55, 1.45))
    }

    private func animate(
        _ shape: CAShapeLayer,
        on parent: CALayer,
        duration: TimeInterval,
        scale: (CGFloat, CGFloat),
        travel: NSPoint = .zero
    ) {
        shape.opacity = 0
        parent.addSublayer(shape)

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        fade.duration = duration
        shape.add(fade, forKey: "fade")

        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = scale.0
        grow.toValue = scale.1
        grow.duration = duration
        shape.add(grow, forKey: "grow")

        if travel != .zero {
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(point: shape.position)
            move.toValue = NSValue(point: NSPoint(x: shape.position.x + travel.x, y: shape.position.y + travel.y))
            move.duration = duration
            shape.add(move, forKey: "move")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak shape] in
            shape?.removeFromSuperlayer()
        }
    }
}
