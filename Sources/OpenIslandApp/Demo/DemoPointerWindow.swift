import AppKit
import QuartzCore

/// The drawn pointer (D65): a clear window of this app over the whole of
/// the island's screen, with a macOS style arrow on it. The recorder films
/// only this app's windows, which leaves the real pointer out of every
/// take; this one is in them. The window ignores the mouse, never becomes
/// key and sits above the island, the tour and the backdrop. Only the demo
/// mode makes it.
@MainActor
final class DemoPointerWindow: DemoPointerDrawing {
    /// A panel, like the island's. An ordinary window of an app in the
    /// background stays off a full screen Space, which left it out of takes
    /// made with a full screen app in front.
    private final class Window: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }

        /// A borderless window may cover the menu bar. The default keeps
        /// it below.
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
            frameRect
        }
    }

    private let window: Window
    private let arrow: CAShapeLayer
    private let ring: CAShapeLayer

    init(screen: NSScreen) {
        let window = Window(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = DemoWindowLevels.pointer
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        let scale = screen.backingScaleFactor
        ring = DemoPointerArt.ringLayer(contentsScale: scale)
        arrow = DemoPointerArt.arrowLayer(contentsScale: scale)
        view.layer?.addSublayer(ring)
        view.layer?.addSublayer(arrow)
        window.contentView = view
        window.setFrame(screen.frame, display: false)
        self.window = window
        window.orderFrontRegardless()
    }

    func close() {
        window.orderOut(nil)
    }

    /// A screen point in the window's own space.
    private func local(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - window.frame.minX, y: point.y - window.frame.minY)
    }

    private func still(_ change: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        change()
        CATransaction.commit()
    }

    // MARK: DemoPointerDrawing

    func show(at point: CGPoint) {
        still { arrow.position = local(point) }
    }

    func glide(through points: [CGPoint], duration: TimeInterval) {
        guard let last = points.last else { return }
        let animation = CAKeyframeAnimation(keyPath: "position")
        animation.values = points.map { NSValue(point: local($0)) }
        animation.duration = duration
        animation.calculationMode = .linear
        still {
            arrow.position = local(last)
            arrow.add(animation, forKey: "glide")
        }
    }

    func press(at point: CGPoint) {
        let down = CABasicAnimation(keyPath: "transform.scale")
        down.fromValue = 1
        down.toValue = DemoPointerArt.pressedScale
        down.duration = DemoGlide.pressDown
        down.timingFunction = CAMediaTimingFunction(name: .easeOut)
        still {
            arrow.setValue(DemoPointerArt.pressedScale, forKeyPath: "transform.scale")
            arrow.add(down, forKey: "press")
        }
    }

    func release(at point: CGPoint, showsRing: Bool) {
        let up = CABasicAnimation(keyPath: "transform.scale")
        up.fromValue = DemoPointerArt.pressedScale
        up.toValue = 1
        up.duration = DemoGlide.pressUp
        up.timingFunction = CAMediaTimingFunction(name: .easeOut)
        still {
            arrow.setValue(1, forKeyPath: "transform.scale")
            arrow.add(up, forKey: "press")
        }
        guard showsRing else { return }
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = DemoPointerArt.ringStartScale
        grow.toValue = 1
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = DemoPointerArt.ringStartOpacity
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = DemoGlide.ringFade
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        still {
            ring.position = local(point)
            ring.opacity = 0
            ring.add(group, forKey: "ring")
        }
    }
}

/// How the drawn pointer looks.
enum DemoPointerArt {
    /// A little larger than the system's arrow, which keeps it readable in
    /// a recording shown smaller than the screen.
    static let scale: CGFloat = 1.2
    /// The arrow's outline in points, the tip at (0, 0) and y growing
    /// downward, the shape of the macOS arrow.
    static let outline: [CGPoint] = [
        CGPoint(x: 0, y: 0),
        CGPoint(x: 0, y: 16.6),
        CGPoint(x: 4.0, y: 12.9),
        CGPoint(x: 6.9, y: 19.4),
        CGPoint(x: 9.6, y: 18.2),
        CGPoint(x: 6.8, y: 11.9),
        CGPoint(x: 12.1, y: 11.9),
    ]
    /// Room round the outline for the white edge.
    static let padding: CGFloat = 3
    static let pressedScale: CGFloat = 0.86
    static let ringRadius: CGFloat = 15
    static let ringStartScale: CGFloat = 0.35
    static let ringStartOpacity: Float = 0.8

    /// The arrow, its anchor on the tip: the layer's position is where the
    /// pointer points.
    static func arrowLayer(contentsScale: CGFloat) -> CAShapeLayer {
        let width = (outline.map(\.x).max() ?? 0) * scale + padding * 2
        let height = (outline.map(\.y).max() ?? 0) * scale + padding * 2
        let path = CGMutablePath()
        let points = outline.map { CGPoint(x: padding + $0.x * scale, y: height - padding - $0.y * scale) }
        path.addLines(between: points)
        path.closeSubpath()

        let layer = CAShapeLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        layer.anchorPoint = CGPoint(x: padding / width, y: (height - padding) / height)
        layer.path = path
        layer.fillColor = NSColor.black.cgColor
        layer.strokeColor = NSColor.white.cgColor
        layer.lineWidth = 1.5
        layer.lineJoin = .round
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.4
        layer.shadowRadius = 2.5
        layer.shadowOffset = CGSize(width: 0.5, height: -1.8)
        layer.contentsScale = contentsScale
        return layer
    }

    /// The ring a click leaves round the tip.
    static func ringLayer(contentsScale: CGFloat) -> CAShapeLayer {
        let side = ringRadius * 2
        let layer = CAShapeLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        layer.path = CGPath(ellipseIn: layer.bounds.insetBy(dx: 1, dy: 1), transform: nil)
        layer.fillColor = NSColor.white.withAlphaComponent(0.14).cgColor
        layer.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        layer.lineWidth = 2
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 2
        layer.shadowOffset = .zero
        layer.opacity = 0
        layer.contentsScale = contentsScale
        return layer
    }
}
