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
            showGrains(at: point, on: surface.layer, horizontal: false)
        case .horizontalGrain:
            showGrains(at: point, on: surface.layer, horizontal: true)
        case .dragTick:
            showDragMark(at: point, on: surface.layer)
        case let .clickRipple(isDouble, stage):
            showRipple(at: point, on: surface.layer, isDouble: isDouble, stage: stage)
        case .secondaryClick:
            showSecondaryClick(at: point, on: surface.layer)
        case let .zoom(outward):
            showZoom(at: point, on: surface.layer, outward: outward)
        case .smartZoom:
            showZoom(at: point, on: surface.layer, outward: true)
        case let .swipe(horizontal, positive):
            showSwipe(at: point, on: surface.layer, horizontal: horizontal, positive: positive)
        case let .sourceCue(sourceID, stage):
            showSourceCue(at: point, on: surface.layer, sourceID: sourceID, stage: stage)
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

    private func showGrains(at point: NSPoint, on parent: CALayer, horizontal: Bool) {
        let sand = NSColor.black.withAlphaComponent(0.9)
        for (index, offset) in [NSPoint(x: -10, y: 6), NSPoint(x: 8, y: 10), NSPoint(x: 12, y: -5)].enumerated() {
            let size: CGFloat = index == 1 ? 3 : 2
            let direction = horizontal ? NSPoint(x: offset.y, y: offset.x) : offset
            let centre = NSPoint(x: point.x + direction.x, y: point.y + direction.y)
            let grain = CAShapeLayer()
            grain.frame = NSRect(x: centre.x - size / 2, y: centre.y - size / 2, width: size, height: size)
            grain.path = CGPath(ellipseIn: NSRect(x: 0, y: 0, width: size, height: size), transform: nil)
            grain.fillColor = sand.cgColor
            animate(grain, on: parent, duration: 0.23, scale: (1, 0.6), travel: NSPoint(x: direction.x * 0.4, y: direction.y * 0.4))
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
        mark.fillColor = NSColor.black.withAlphaComponent(0.9).cgColor
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
        ring.strokeColor = NSColor.black.withAlphaComponent(0.85).cgColor
        ring.lineWidth = 1.5
        animate(ring, on: parent, duration: 0.38, scale: (0.55, 1.45))
    }

    private func showSecondaryClick(at point: NSPoint, on parent: CALayer) {
        let square = CAShapeLayer()
        square.frame = NSRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20)
        square.path = CGPath(roundedRect: NSRect(x: 1, y: 1, width: 18, height: 18), cornerWidth: 5, cornerHeight: 5, transform: nil)
        square.fillColor = NSColor.clear.cgColor
        square.strokeColor = NSColor.black.cgColor
        square.lineWidth = 1.5
        animate(square, on: parent, duration: 0.28, scale: (0.7, 1.2))
    }

    private func showZoom(at point: NSPoint, on parent: CALayer, outward: Bool) {
        for diameter: CGFloat in [14, 24] {
            let ring = CAShapeLayer()
            ring.frame = NSRect(x: point.x - diameter / 2, y: point.y - diameter / 2, width: diameter, height: diameter)
            ring.path = CGPath(ellipseIn: NSRect(x: 1, y: 1, width: diameter - 2, height: diameter - 2), transform: nil)
            ring.fillColor = NSColor.clear.cgColor
            ring.strokeColor = NSColor.black.cgColor
            ring.lineWidth = 1.2
            animate(ring, on: parent, duration: 0.3, scale: outward ? (0.65, 1.3) : (1.3, 0.65))
        }
    }

    private func showSwipe(at point: NSPoint, on parent: CALayer, horizontal: Bool, positive: Bool) {
        let arrow = CAShapeLayer()
        arrow.frame = horizontal
            ? NSRect(x: point.x + 7, y: point.y + 7, width: 18, height: 10)
            : NSRect(x: point.x + 7, y: point.y + 7, width: 10, height: 18)
        let path = CGMutablePath()
        let end: CGFloat = positive ? 17 : 1
        let base: CGFloat = positive ? 1 : 17
        let head: CGFloat = positive ? 12 : 6
        if horizontal {
            path.move(to: CGPoint(x: base, y: 5))
            path.addLine(to: CGPoint(x: end, y: 5))
            path.move(to: CGPoint(x: head, y: 1))
            path.addLine(to: CGPoint(x: end, y: 5))
            path.addLine(to: CGPoint(x: head, y: 9))
        } else {
            path.move(to: CGPoint(x: 5, y: base))
            path.addLine(to: CGPoint(x: 5, y: end))
            path.move(to: CGPoint(x: 1, y: head))
            path.addLine(to: CGPoint(x: 5, y: end))
            path.addLine(to: CGPoint(x: 9, y: head))
        }
        arrow.path = path
        arrow.fillColor = NSColor.clear.cgColor
        arrow.strokeColor = NSColor.black.cgColor
        arrow.lineWidth = 1.5
        animate(arrow, on: parent, duration: 0.28, scale: (0.8, 1.2))
    }

    private func showSourceCue(at point: NSPoint, on parent: CALayer, sourceID: String, stage: Int) {
        let badge = CAShapeLayer()
        badge.frame = NSRect(x: point.x + 15, y: point.y + 14, width: 23, height: 23)
        badge.path = CGPath(ellipseIn: NSRect(x: 1, y: 1, width: 21, height: 21), transform: nil)
        badge.fillColor = NSColor.clear.cgColor
        badge.strokeColor = NSColor.black.cgColor
        badge.lineWidth = 1.2

        let letter = CATextLayer()
        letter.frame = NSRect(x: 0, y: 4, width: 23, height: 14)
        letter.string = String(sourceID.prefix(1)).uppercased()
        letter.fontSize = 11
        letter.alignmentMode = .center
        letter.foregroundColor = NSColor.black.cgColor
        letter.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        badge.addSublayer(letter)
        animate(badge, on: parent, duration: 0.42, scale: (0.8, 1.05 + CGFloat(stage) * 0.08))
    }

    private func animate(
        _ shape: CALayer,
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
