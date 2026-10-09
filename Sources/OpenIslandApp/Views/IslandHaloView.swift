import AppKit
import SwiftUI

extension View {
    /// Draws the status halo: a soft single-color glow behind the view,
    /// following a rounded rect of the view's bounds (inset 6pt, shifted down
    /// by `state.drop`) and spreading `state.radius` past its edges.
    ///
    /// The glow lives in a Core Animation layer that is larger than the view
    /// (it reaches into the window's transparent insets) but never changes the
    /// view's own layout size and never takes a hit. The layer is padded by one
    /// constant, `IslandHaloLayerView.maxSpread`, for every state, so that
    /// padding never animates with the island's spring and the pill stays
    /// exactly where the host view is. Applying an equal state is a no-op, so
    /// SwiftUI re-renders do not restart any animation.
    func islandHalo(_ state: IslandHaloState, cornerRadius: CGFloat) -> some View {
        background(
            IslandHaloLayerRepresentable(state: state, cornerRadius: cornerRadius)
                .padding(-IslandHaloLayerView.maxSpread)
                .allowsHitTesting(false)
        )
    }
}

private struct IslandHaloLayerRepresentable: NSViewRepresentable {
    let state: IslandHaloState
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> IslandHaloLayerView {
        let view = IslandHaloLayerView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: IslandHaloLayerView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: IslandHaloLayerView) {
        view.cornerRadius = cornerRadius
        view.apply(state: state)
    }
}

/// Hosts the glow layer. The view is `maxSpread` larger than the pill on every
/// side, whatever the state, so the pill is always the bounds inset by
/// `maxSpread`.
@MainActor
final class IslandHaloLayerView: NSView {
    /// How far the view reaches past the pill: twice the largest blur radius
    /// plus the largest drop of any metrics set. One constant for every state
    /// (including `.off`), so the padding the modifier applies never changes
    /// while the island's spring is moving the host view.
    static let maxSpread: CGFloat = {
        let all = [IslandHaloMetrics.subtle, .vivid, .opened]
        let radius = all.map(\.radius).max() ?? 0
        let drop = all.map(\.drop).max() ?? 0
        return max(0, radius * 2 + drop)
    }()

    /// Kept for callers of the old per-state API. It is `maxSpread` for every state.
    static func spread(for state: IslandHaloState) -> CGFloat {
        maxSpread
    }

    /// The glow is drawn from a path this far inside the pill, so the pill
    /// edge stays crisp over it.
    /// The glow's core sits on the pill's edge, which lets half the blur fall
    /// outside the pill. A positive inset hid most of it under the black fill.
    static let pillInset: CGFloat = 0

    private static let opacityKey = "halo.opacity"
    private static let envelopeKey = "halo.envelope"
    private static let colorKey = "halo.color"
    private static let radiusKey = "halo.radius"
    /// Opacity below which the glow counts as not on screen.
    private static let visibleThreshold: Float = 0.01
    /// How long past its fade an outgoing copy lives before it is removed.
    private static let outgoingSlack: TimeInterval = 0.1

    /// The one live layer: it has no contents, its shadow is the glow.
    let glowLayer = CALayer()

    /// The pill's corner radius.
    var cornerRadius: CGFloat = 0 {
        didSet { if cornerRadius != oldValue { needsLayout = true } }
    }

    /// What the system allows right now. Read when a flash starts, to turn the
    /// rise and settle into one fade under Reduce Motion. Tests replace it.
    var policyProvider: @MainActor () -> IslandMotionPolicy = { SystemMotionMonitor.shared.policy }

    private(set) var lastState: IslandHaloState?
    /// How many opacity animations were added to the live layer, which lets
    /// tests prove that re-applying a state never restarts one.
    private(set) var opacityAnimationStarts = 0
    /// How many fading copies of the previous look are still on screen.
    var outgoingLayerCount: Int { outgoing.count }

    private var appliedColor: IslandHaloRGB?
    private var drop: CGFloat = 0
    private var appliedPath: PathKey?

    /// The previous look of the glow, kept alive while it fades out under a
    /// loop that is fading in.
    private struct OutgoingGlow {
        let layer: CALayer
        let drop: CGFloat
    }

    private var outgoing: [OutgoingGlow] = []

    private struct PathKey: Equatable {
        var size: CGSize
        var drop: CGFloat
        var cornerRadius: CGFloat
        var isFlipped: Bool
    }

    /// One endless low-high-low opacity loop. `cycle` is one full there-and-back trip.
    private struct LoopSpec: Equatable {
        var low: Double
        var high: Double
        var duration: TimeInterval
        var cycle: TimeInterval
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never

        glowLayer.masksToBounds = false
        glowLayer.opacity = 0
        glowLayer.shadowOpacity = 1
        glowLayer.shadowOffset = .zero
        glowLayer.shadowRadius = 0
        glowLayer.shouldRasterize = true
        layer?.addSublayer(glowLayer)
        updateScale()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Layer coordinates run top to bottom, so "down" is +y.
    override var isFlipped: Bool { true }

    // The glow never takes a hit.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func isAccessibilityElement() -> Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateScale()
    }

    /// Geometry only. Never touches animations.
    override func layout() {
        super.layout()
        updatePath()
    }

    // MARK: Applying a state

    /// Idempotent: an equal state returns at once, so nothing restarts.
    func apply(state: IslandHaloState) {
        guard state != lastState else { return }
        let previous = lastState
        lastState = state
        let animated = previous != nil
        let startsLoop = animated && Self.startsNewLoop(state, previous: previous)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // A new loop fades in over a copy of what was on screen, which fades
        // out. The copy is taken first, while the layer still has the old look.
        if startsLoop { spawnOutgoingGlow() }
        applyColor(of: state, animated: animated && !startsLoop)
        applyGeometry(of: state, animated: animated && !startsLoop)
        applyMotion(of: state, previous: previous, animated: animated)
        CATransaction.commit()
    }

    // MARK: Color and geometry

    /// A glow that is fading out keeps the color it had.
    private func applyColor(of state: IslandHaloState, animated: Bool) {
        guard state.motion != .none, state.color != appliedColor else { return }
        let from = glowLayer.presentation()?.shadowColor ?? glowLayer.shadowColor
        let shouldCrossfade = animated && appliedColor != nil && visibleAlpha > Self.visibleThreshold
        appliedColor = state.color
        let target = state.color.cgColor
        glowLayer.shadowColor = target
        guard shouldCrossfade, let from else {
            glowLayer.removeAnimation(forKey: Self.colorKey)
            return
        }
        glowLayer.add(
            Self.fade(keyPath: "shadowColor", from: from, to: target, duration: Motion.Halo.colorCrossfade),
            forKey: Self.colorKey
        )
    }

    /// A glow that is fading out keeps its size, so it does not tighten while it goes.
    private func applyGeometry(of state: IslandHaloState, animated: Bool) {
        guard state.motion != .none else { return }
        if state.drop != drop {
            drop = state.drop
            updatePath()
        }
        let radius = state.radius
        guard radius != glowLayer.shadowRadius else { return }
        let from = glowLayer.presentation()?.shadowRadius ?? glowLayer.shadowRadius
        glowLayer.shadowRadius = radius
        guard animated, visibleAlpha > Self.visibleThreshold else {
            glowLayer.removeAnimation(forKey: Self.radiusKey)
            return
        }
        glowLayer.add(
            Self.fade(keyPath: "shadowRadius", from: from, to: radius, duration: Motion.Halo.fade),
            forKey: Self.radiusKey
        )
    }

    private func updatePath() {
        let key = PathKey(size: bounds.size, drop: drop, cornerRadius: cornerRadius, isFlipped: glowLayer.contentsAreFlipped())
        guard key != appliedPath else { return }
        appliedPath = key

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glowLayer.frame = bounds
        glowLayer.shadowPath = Self.pillPath(for: key, inset: Self.pillInset)
        for glow in outgoing {
            var outgoingKey = key
            outgoingKey.drop = glow.drop
            glow.layer.frame = bounds
            glow.layer.shadowPath = Self.pillPath(for: outgoingKey, inset: Self.pillInset)
        }
        CATransaction.commit()
    }

    /// The pill in the glow layer's coordinates. "Down" is +y when the layer's
    /// contents are flipped (the AppKit view is flipped) and -y otherwise.
    private static func pillPath(for key: PathKey, inset: CGFloat) -> CGPath? {
        let margin = maxSpread + inset
        let pill = CGRect(origin: .zero, size: key.size).insetBy(dx: margin, dy: margin)
        guard pill.width > 0, pill.height > 0 else { return nil }
        let radius = max(0, min(key.cornerRadius, pill.width / 2, pill.height / 2))
        let shifted = pill.offsetBy(dx: 0, dy: key.isFlipped ? key.drop : -key.drop)
        return CGPath(roundedRect: shifted, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private func updateScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glowLayer.contentsScale = scale
        glowLayer.rasterizationScale = scale
        for glow in outgoing {
            glow.layer.contentsScale = scale
            glow.layer.rasterizationScale = scale
        }
        CATransaction.commit()
    }

    // MARK: Motion

    /// What the glow shows right now: its layer opacity times the envelope
    /// that fades a new loop in, read from the presentation layer.
    private var visibleAlpha: Float {
        let current = glowLayer.presentation() ?? glowLayer
        return current.opacity * current.shadowOpacity
    }

    private static func loopSpec(for state: IslandHaloState) -> LoopSpec? {
        switch state.motion {
        case let .breathing(period, low, high):
            return LoopSpec(low: low, high: high, duration: period / 2, cycle: period)
        case let .drift(period):
            // The range is built around the rest opacity, so a new rest
            // opacity is a new loop.
            return LoopSpec(
                low: state.restOpacity * 0.75,
                high: min(1, state.restOpacity * 1.15),
                duration: period,
                cycle: period * 2
            )
        case .none, .steady, .flash:
            return nil
        }
    }

    private static func startsNewLoop(_ state: IslandHaloState, previous: IslandHaloState?) -> Bool {
        guard let spec = loopSpec(for: state) else { return false }
        return spec != previous.flatMap { loopSpec(for: $0) }
    }

    private func applyMotion(of state: IslandHaloState, previous: IslandHaloState?, animated: Bool) {
        let motionChanged = previous?.motion != state.motion
        guard motionChanged || previous?.restOpacity != state.restOpacity else { return }
        let rest = Float(state.restOpacity)

        switch state.motion {
        case .none:
            fadeOpacity(to: 0, animated: animated)
        case .steady:
            fadeOpacity(to: rest, animated: animated)
        case .breathing, .drift:
            guard let spec = Self.loopSpec(for: state) else { return }
            if spec == previous.flatMap({ Self.loopSpec(for: $0) }) {
                // The same loop is running; only the stored rest opacity moved.
                glowLayer.opacity = rest
            } else {
                startLoop(rest: rest, spec: spec, fadesIn: animated)
            }
        case let .flash(token, peak, duration):
            // Only a new token restarts the flash.
            if case let .flash(previousToken, _, _)? = previous?.motion, previousToken == token {
                glowLayer.opacity = rest
            } else {
                startFlash(rest: rest, peak: Float(peak), duration: duration)
            }
        }
    }

    /// Replaces any loop or flash with a fade from what is on screen.
    private func fadeOpacity(to target: Float, animated: Bool) {
        let from = visibleAlpha
        glowLayer.removeAnimation(forKey: Self.opacityKey)
        removeEnvelope()
        glowLayer.opacity = target
        guard animated, abs(from - target) > 0.001 else { return }
        addOpacityAnimation(Self.fade(keyPath: "opacity", from: from, to: target, duration: Motion.Halo.fade))
    }

    /// An endless low-high-low opacity loop. The begin time snaps to a global
    /// grid of one cycle, so adding the loop again later lands on the same
    /// phase and never visibly jumps. That puts the loop at full strength on
    /// its first frame, so when `fadesIn` an envelope on `shadowOpacity` brings
    /// it up from nothing over `Motion.Halo.fade`.
    private func startLoop(rest: Float, spec: LoopSpec, fadesIn: Bool) {
        glowLayer.opacity = rest
        removeEnvelope()
        guard spec.duration > 0 else {
            glowLayer.removeAnimation(forKey: Self.opacityKey)
            return
        }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = Float(spec.low)
        animation.toValue = Float(spec.high)
        animation.duration = spec.duration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.beginTime = Self.gridBeginTime(cycle: spec.cycle)
        addOpacityAnimation(animation)
        if fadesIn {
            glowLayer.add(
                Self.fade(keyPath: "shadowOpacity", from: Float(0), to: Float(1), duration: Motion.Halo.fade),
                forKey: Self.envelopeKey
            )
        }
    }

    /// Rise to the peak, settle back, then rest. Starts from what is on screen.
    /// With Reduce Motion it is one fade instead: start at the peak and ease
    /// out to rest.
    private func startFlash(rest: Float, peak: Float, duration: TimeInterval) {
        let from = visibleAlpha
        removeEnvelope()
        glowLayer.opacity = rest
        guard duration > 0 else {
            glowLayer.removeAnimation(forKey: Self.opacityKey)
            return
        }
        guard policyProvider().animates else {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = peak
            fade.toValue = rest
            fade.duration = duration
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            addOpacityAnimation(fade)
            return
        }
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [from, peak, peak * 0.55, rest]
        animation.keyTimes = [0, 0.18, 0.5, 1]
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeIn),
        ]
        animation.duration = duration
        addOpacityAnimation(animation)
    }

    private func removeEnvelope() {
        glowLayer.removeAnimation(forKey: Self.envelopeKey)
        glowLayer.shadowOpacity = 1
    }

    private func addOpacityAnimation(_ animation: CAAnimation) {
        glowLayer.add(animation, forKey: Self.opacityKey)
        opacityAnimationStarts += 1
    }

    // MARK: Outgoing copy

    /// Puts a copy of what is on screen (same path, color, radius, at the
    /// current opacity) under the live layer and fades it to nothing, so a new
    /// loop can fade in without the old glow vanishing under it. Does nothing
    /// when no glow is visible.
    private func spawnOutgoingGlow() {
        let alpha = visibleAlpha
        guard alpha > Self.visibleThreshold, let host = layer else { return }
        let current = glowLayer.presentation() ?? glowLayer

        let copy = CALayer()
        copy.frame = glowLayer.frame
        copy.masksToBounds = false
        copy.shadowOpacity = 1
        copy.shadowOffset = .zero
        copy.shadowColor = current.shadowColor
        copy.shadowRadius = current.shadowRadius
        copy.shadowPath = glowLayer.shadowPath
        copy.shouldRasterize = true
        copy.contentsScale = glowLayer.contentsScale
        copy.rasterizationScale = glowLayer.rasterizationScale
        copy.opacity = 0
        host.insertSublayer(copy, below: glowLayer)
        copy.add(
            Self.fade(keyPath: "opacity", from: alpha, to: Float(0), duration: Motion.Halo.fade),
            forKey: Self.opacityKey
        )
        outgoing.append(OutgoingGlow(layer: copy, drop: drop))

        Task { [weak self, weak copy] in
            try? await Task.sleep(for: .seconds(Motion.Halo.fade + Self.outgoingSlack))
            guard let self, let copy else { return }
            copy.removeFromSuperlayer()
            outgoing.removeAll { $0.layer === copy }
        }
    }

    static func gridBeginTime(cycle: TimeInterval, now: CFTimeInterval = CACurrentMediaTime()) -> CFTimeInterval {
        guard cycle > 0 else { return now }
        return (now / cycle).rounded(.down) * cycle
    }

    private static func fade(keyPath: String, from: Any, to: Any, duration: TimeInterval) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return animation
    }
}
