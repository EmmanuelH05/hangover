import AppKit
import QuartzCore

/// The glow that follows a song (D56).
///
/// It is one copy of the pill's shadow for each color, drawn once and kept
/// as a picture. The layer that holds them has two things that move: its
/// scale, which is how far the glow reaches, and its opacity, which is how
/// bright it is. Nothing is blurred again while the music plays, which is
/// the rule for anything that stays on screen (D48): no shadow radius is
/// set or animated.
///
/// What moves what, by the owner's word: "one color per 808, retract all
/// the way back to the notch". A low hit, a kick or an 808 starting, is a
/// punch: the glow is out and bright at once, in its next color, and comes
/// all the way back in about 140 ms. Nothing holds it out: a long 808 is
/// one punch, where it starts. A snare or a clap is a flash of brightness,
/// and the next color only when no punch is on its way back. A hat is a
/// small flicker at the notch. Between hits the glow rests.
@MainActor
final class IslandBeatGlow {
    /// How long a punch takes to come all the way back to the notch, and
    /// a flash to fade. Neither has a rise: a hit is on screen at once.
    static let punchFall: TimeInterval = 0.14
    static let flashFall: TimeInterval = 0.12
    /// How long a hat's flicker lasts.
    static let shimmerFall: TimeInterval = 0.08
    /// How long one color takes to give way to the next: short enough to
    /// read as on the hit, and still a fade and not a cut.
    static let hueCrossfade: TimeInterval = 0.03
    /// The least a punch goes out, as a share of the full reach: a hit
    /// that counts is a hit you can see.
    static let leastPunch: Float = 0.3

    private static let levelKey = "beat.level"
    private static let scaleKey = "beat.scale"
    private static let hueKey = "beat.hue"
    private static let colorKey = "beat.color"

    /// Holds the colors. Its opacity is the brightness, its scale the reach.
    let container = CALayer()
    /// One layer a color, in the order the flashes step through them.
    private(set) var hueLayers: [CALayer] = []
    /// What the glow moves between, and nil while it is not pulsing.
    private(set) var pulse: IslandHaloPulse?
    /// Which color shows.
    private(set) var hueIndex = 0
    /// How far the last punch went out, 0 to 1.
    private(set) var lastPunch: Float = 0
    /// How many punches, flashes and flickers were shown, for the tests.
    private(set) var punches = 0
    private(set) var flashes = 0
    private(set) var flickers = 0
    /// Until when a punch is on its way back, and a flash is fading, on
    /// the wall clock.
    private var punchEnds: CFTimeInterval = -.infinity
    private var flashEnds: CFTimeInterval = -.infinity
    /// The scale of the container at a full reach, along each side.
    private(set) var peakScale = CGSize(width: 1, height: 1)

    /// The wall clock. A test hands in its own.
    var now: () -> CFTimeInterval = CACurrentMediaTime
    /// Whether the user asked macOS to dim flashing lights. A test hands
    /// in a fake.
    var flashingLights: any IslandFlashingLightsSetting = SystemFlashingLightsSetting.shared
    /// When the flashes of the last second were shown, oldest first.
    private var flashTimes: [CFTimeInterval] = []

    /// How far past the pill the glow may paint to the side and below. The
    /// layer's view sets it from the island's window before a frame.
    var room: (side: CGFloat, below: CGFloat) = (0, 0) {
        didSet {
            guard room != oldValue else { return }
            updatePeakScale()
        }
    }

    private var frame = CGRect.zero
    private var pill = CGSize.zero
    private var path: CGPath?
    private var scale: CGFloat = 2
    private var radius: CGFloat = 0
    private var drop: CGFloat = 0

    var isActive: Bool { pulse != nil }

    init() {
        container.masksToBounds = false
        container.opacity = 0
        // Each color is a finished picture. Blending them one by one costs
        // less than drawing the group offscreen first.
        container.allowsGroupOpacity = false
    }

    // MARK: Starting and stopping

    /// Shows the pulse at rest. Calling it again with the same values does
    /// nothing. New colors, which a new track brings, fade in over the one
    /// that shows. A new reach only changes how far the pictures are scaled.
    func begin(_ pulse: IslandHaloPulse, radius: CGFloat, drop: CGFloat, animated: Bool) {
        guard pulse != self.pulse || radius != self.radius || drop != self.drop else { return }
        let wasActive = isActive
        self.pulse = pulse
        self.radius = radius
        self.drop = drop
        updatePeakScale()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        matchLayers(to: pulse.hues.count)
        setColors(pulse.hues, crossfadesShowing: wasActive && animated)
        for layer in hueLayers where layer.shadowRadius != radius { layer.shadowRadius = radius }
        if !wasActive {
            hueIndex = 0
            for (index, layer) in hueLayers.enumerated() {
                layer.removeAnimation(forKey: Self.hueKey)
                layer.opacity = index == 0 ? 1 : 0
            }
        }
        CATransaction.commit()

        // At rest. A punch that was on its way back when only the reach or
        // the colors changed goes on.
        if !wasActive {
            let duration = animated ? Motion.Halo.fade : 0
            setOpacity(Float(pulse.low), duration: duration)
            setTransform(CGSize(width: 1, height: 1), duration: duration)
        }
    }

    /// Back to rest at once, where the glow stays while the lasers have
    /// the song.
    func rest(animated: Bool) {
        guard let pulse else { return }
        punchEnds = -.infinity
        flashEnds = -.infinity
        let duration = animated ? Motion.Halo.fade : 0
        setOpacity(Float(pulse.low), duration: duration)
        setTransform(CGSize(width: 1, height: 1), duration: duration)
    }

    /// Fades the pulse out. The pictures are kept for the next song.
    func end(animated: Bool) {
        guard isActive else { return }
        pulse = nil
        punchEnds = -.infinity
        flashEnds = -.infinity
        let duration = animated ? Motion.Halo.fade : 0
        setOpacity(0, duration: duration)
        setTransform(CGSize(width: 1, height: 1), duration: duration)
    }

    // MARK: Following the song

    /// One frame from the listener. Only a hit moves the glow, and it is
    /// shown the moment it comes, with no rise.
    func follow(_ frame: IslandBeatFrame) {
        guard let pulse else { return }
        switch frame.hit {
        case .kick:
            guard mayFlash() else { return }
            punch(strength: Float(min(max(frame.low, 0), 1)), in: pulse)
        case .snare:
            guard mayFlash() else { return }
            flash(in: pulse)
        case .hat:
            flicker(high: Float(min(max(frame.high, 0), 1)), in: pulse)
        case nil:
            break
        }
    }

    /// A low hit: the next color, and the glow out and bright at once,
    /// then all the way back to the notch. A punch that lands while the
    /// last one is still coming back starts over from its own peak.
    private func punch(strength: Float, in pulse: IslandHaloPulse) {
        stepHue()
        let reach = CGFloat(max(strength, Self.leastPunch))
        lastPunch = Float(reach)
        punches += 1
        let time = now()
        punchEnds = time + Self.punchFall
        flashEnds = punchEnds
        fall(
            fromScale: CGSize(
                width: 1 + (peakScale.width - 1) * reach,
                height: 1 + (peakScale.height - 1) * reach
            ),
            over: Self.punchFall
        )
        fall(fromOpacity: Float(pulse.high), to: Float(pulse.low), over: Self.punchFall)
    }

    /// A mid hit: bright at once and back in about 120 ms. It takes the
    /// next color unless a punch is on its way back, whose color it keeps:
    /// one color for a low hit's whole trip. The reach is not touched.
    private func flash(in pulse: IslandHaloPulse) {
        let time = now()
        if time >= punchEnds || time < punchEnds - Self.punchFall { stepHue() }
        flashes += 1
        flashEnds = max(flashEnds, time + Self.flashFall)
        fall(fromOpacity: Float(pulse.high), to: Float(pulse.low), over: Self.flashFall)
    }

    /// A hat: a small flicker at the notch, by the hats' own loudness and
    /// never past the shimmer's ceiling. While a punch or a flash is still
    /// fading it is left alone: a flicker would cut the fade short.
    private func flicker(high: Float, in pulse: IslandHaloPulse) {
        let time = now()
        guard time >= flashEnds || time < flashEnds - Self.punchFall else { return }
        flickers += 1
        let lift = Double(IslandBeatLimits.shimmerCeiling * max(0.5, high)) * (pulse.high - pulse.low)
        fall(fromOpacity: Float(pulse.low + lift), to: Float(pulse.low), over: Self.shimmerFall)
    }

    /// Whether a punch or a flash may be shown now (D56). They follow the
    /// hits, with only the gap that keeps a roll from smearing. A user who
    /// asked macOS to dim flashing lights gets no more than three in any
    /// one second, counted here on the wall clock, at the one place every
    /// flash goes through. A hit that is turned away shows nothing.
    private func mayFlash() -> Bool {
        let time = now()
        flashTimes.removeAll { time - $0 >= 1 || time < $0 }
        let rule = IslandFlashRule.rule(dimsFlashingLights: flashingLights.dimsFlashingLights)
        guard rule.allows(at: time, after: flashTimes) else { return false }
        flashTimes.append(time)
        return true
    }

    /// The brightness is at `peak` with the next frame the system draws
    /// and eases back to `rest`. The layer's own value is the rest: when
    /// the animation is over, or is taken off, the glow is at rest.
    private func fall(fromOpacity peak: Float, to rest: Float, over duration: TimeInterval) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.opacity = rest
        container.removeAnimation(forKey: Self.levelKey)
        let animation = Self.fade(keyPath: "opacity", from: peak, to: rest, duration: duration)
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        container.add(animation, forKey: Self.levelKey)
        CATransaction.commit()
    }

    /// The reach is at `peak` at once and eases all the way back to the
    /// notch.
    private func fall(fromScale peak: CGSize, over duration: TimeInterval) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.transform = CATransform3DIdentity
        container.removeAnimation(forKey: Self.scaleKey)
        let animation = Self.fade(
            keyPath: "transform",
            from: NSValue(caTransform3D: CATransform3DMakeScale(peak.width, peak.height, 1)),
            to: NSValue(caTransform3D: CATransform3DIdentity),
            duration: duration
        )
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        container.add(animation, forKey: Self.scaleKey)
        CATransaction.commit()
    }

    /// The next color fades in while the one that shows fades out.
    private func stepHue() {
        guard hueLayers.count > 1 else { return }
        let next = (hueIndex + 1) % hueLayers.count
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, layer) in hueLayers.enumerated() {
            let target: Float = index == next ? 1 : 0
            let from = layer.presentation()?.opacity ?? layer.opacity
            layer.opacity = target
            layer.removeAnimation(forKey: Self.hueKey)
            guard abs(from - target) > 0.001 else { continue }
            layer.add(Self.fade(keyPath: "opacity", from: from, to: target, duration: Self.hueCrossfade), forKey: Self.hueKey)
        }
        CATransaction.commit()
        hueIndex = next
    }

    // MARK: Geometry

    /// The pill's place and outline, the same ones the resting glow uses.
    /// `pill` is the pill's own size inside `frame`.
    func layout(frame: CGRect, pill: CGSize, path: CGPath?) {
        self.frame = frame
        self.pill = pill
        self.path = path
        // The frame is set through bounds and position: the layer may be
        // scaled, and `frame` of a scaled layer is not its own size.
        container.bounds = CGRect(origin: .zero, size: frame.size)
        container.position = CGPoint(x: frame.midX, y: frame.midY)
        for layer in hueLayers {
            layer.frame = CGRect(origin: .zero, size: frame.size)
            layer.shadowPath = path
        }
        updatePeakScale()
    }

    func setContentsScale(_ scale: CGFloat) {
        self.scale = scale
        for layer in hueLayers {
            layer.contentsScale = scale
            layer.rasterizationScale = scale
        }
    }

    /// How far the pictures are scaled at a full reach, from the user's
    /// "How far it reaches" and the room. The pill is wide and low, which
    /// is why each side has a scale of its own: the glow goes the same
    /// distance out on every side.
    private func updatePeakScale() {
        guard let pulse else {
            peakScale = CGSize(width: 1, height: 1)
            return
        }
        peakScale = CGSize(
            width: IslandBeatReach.fittedScale(
                half: pill.width / 2, radius: radius, drop: 0, reach: pulse.reach, room: room.side
            ),
            height: IslandBeatReach.fittedScale(
                half: pill.height / 2, radius: radius, drop: drop, reach: pulse.reach, room: room.below
            )
        )
    }

    // MARK: Layers

    private func matchLayers(to count: Int) {
        while hueLayers.count > count {
            hueLayers.removeLast().removeFromSuperlayer()
        }
        while hueLayers.count < count {
            let layer = CALayer()
            layer.masksToBounds = false
            layer.opacity = 0
            layer.shadowOpacity = 1
            layer.shadowOffset = .zero
            layer.shadowRadius = radius
            layer.shadowPath = path
            layer.frame = CGRect(origin: .zero, size: frame.size)
            layer.shouldRasterize = true
            layer.contentsScale = scale
            layer.rasterizationScale = scale
            container.addSublayer(layer)
            hueLayers.append(layer)
        }
        if hueIndex >= count { hueIndex = 0 }
    }

    /// A hidden layer takes its new color at once. The one that shows
    /// fades to it, because a color never cuts.
    private func setColors(_ hues: [IslandHaloRGB], crossfadesShowing: Bool) {
        for (index, layer) in hueLayers.enumerated() where index < hues.count {
            let target = hues[index].cgColor
            guard layer.shadowColor != target else { continue }
            let from = layer.presentation()?.shadowColor ?? layer.shadowColor
            layer.shadowColor = target
            layer.removeAnimation(forKey: Self.colorKey)
            guard crossfadesShowing, index == hueIndex, let from else { continue }
            layer.add(
                Self.fade(keyPath: "shadowColor", from: from, to: target, duration: Motion.Halo.colorCrossfade),
                forKey: Self.colorKey
            )
        }
    }

    private func setOpacity(_ target: Float, duration: TimeInterval) {
        let from = container.presentation()?.opacity ?? container.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.opacity = target
        container.removeAnimation(forKey: Self.levelKey)
        if duration > 0, abs(from - target) > 0.001 {
            let animation = Self.fade(keyPath: "opacity", from: from, to: target, duration: duration)
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            container.add(animation, forKey: Self.levelKey)
        }
        CATransaction.commit()
    }

    private func setTransform(_ target: CGSize, duration: TimeInterval) {
        let transform = CATransform3DMakeScale(target.width, target.height, 1)
        let from = container.presentation()?.transform ?? container.transform
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.transform = transform
        container.removeAnimation(forKey: Self.scaleKey)
        if duration > 0, !CATransform3DEqualToTransform(from, transform) {
            let animation = Self.fade(
                keyPath: "transform",
                from: NSValue(caTransform3D: from),
                to: NSValue(caTransform3D: transform),
                duration: duration
            )
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            container.add(animation, forKey: Self.scaleKey)
        }
        CATransaction.commit()
    }

    private static func fade(keyPath: String, from: Any, to: Any, duration: TimeInterval) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        // Named, or the window system composes it at the display's own
        // rate (D60).
        animation.preferredFrameRateRange = Motion.Halo.hitFrameRateRange
        return animation
    }
}
