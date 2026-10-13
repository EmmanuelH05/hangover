import AppKit
import QuartzCore

/// The lasers: thin beams that fan out from under the notch, or come
/// straight down beside it (D56).
///
/// Every beam is drawn once, as two gradients: a soft colored edge and a
/// white hot core that fades to the color and then to nothing. A fan only
/// moves them: a place, a lean, a length and an opacity for each, which
/// are transforms and opacities of pictures that already exist (D48).
/// Nothing is drawn again while the music plays, and no view body runs for
/// a level. The beams are made again only when "How many lasers" changes.
///
/// The beams lie in one plane, which hangs from the notch's lower edge. A
/// fan that comes toward the viewer turns that plane about the edge, and
/// the layer above it draws it with perspective from an eye in front of
/// the notch: real depth on the layer tree, which makes a beam spread,
/// lengthen and thicken as it comes forward. Such a beam is also drawn
/// the other way around: faint at the notch and brightest at its far end.
///
/// The layer's space has y growing upward, as AppKit counts. A host whose
/// own layer is flipped sets `container.isGeometryFlipped`.
///
/// A show's half is in `IslandLaserLayer+Show.swift`, and what the tests
/// read in `IslandLaserLayer+Reading.swift`. The parts they reach for are
/// open inside the module for that and for nothing else.
@MainActor
final class IslandLaserLayer {
    /// How fast the beams follow a level up between hits, and how slowly
    /// they let go. A hit itself has no rise at all.
    static let rise: TimeInterval = 0.08
    static let fall: TimeInterval = 0.26
    /// How wide a beam's soft edge and its core are, in points.
    static let softWidth = CGFloat(IslandLaserLimits.softHalfWidth * 2)
    static let coreWidth: CGFloat = 2
    /// How far the faint glow under the beams goes past the notch's sides,
    /// and how far down.
    static let hazeSide: CGFloat = 46
    static let hazeDepth: CGFloat = 54

    static let tiltKey = "laser.tilt"
    static let leanKey = "laser.lean"
    static let lengthKey = "laser.length"
    static let opacityKey = "laser.opacity"
    static let colorKey = "laser.color"

    /// One beam: `holder` leans, `stem` is as long as the bass says, and the
    /// two gradients are the picture.
    struct Beam {
        let holder: CALayer
        let stem: CALayer
        let soft: CAGradientLayer
        let core: CAGradientLayer
    }

    /// Holds the haze and the beams. The host adds it and gives it a frame.
    let container = CALayer()
    /// The eye: it draws the plane under it with perspective, from a
    /// point in front of the middle of the notch's lower edge.
    let lens = CALayer()
    /// The plane the beams lie in. It turns about the notch's lower edge.
    let plane = CALayer()
    let haze = CAGradientLayer()
    /// The faint glow under the notch, for the tests.
    var hazeLayer: CALayer { haze }
    private(set) var beams: [Beam] = []
    /// The fan that shows, and nil while the lasers are off.
    var fan: IslandLaserFan?
    /// How many changes were animated, for the tests.
    var animationStarts = 0
    /// How many times the beams were made again for a new count.
    private(set) var rebuilds = 0

    /// The middle of the notch's lower edge, in the container's space.
    var origin = CGPoint.zero
    /// The length the beams are drawn at: the longest one the reach allows.
    var drawnLength: CGFloat = 1
    private var contentsScale: CGFloat = 2
    var color: IslandHaloRGB?
    /// True while the beams are drawn as ones that come toward the viewer.
    var isForward = false
    /// The show's scene that is on, and nil while there is none.
    var scene: IslandLaserScene?
    /// What each beam was last painted as by a show, which has a color
    /// for every beam.
    var inks: [Ink?] = []

    struct Ink: Equatable {
        var color: IslandHaloRGB
        var isForward: Bool
    }

    init() {
        container.masksToBounds = false
        container.opacity = 0
        haze.type = .radial
        haze.startPoint = CGPoint(x: 0.5, y: 1)
        haze.endPoint = CGPoint(x: 1, y: 0)
        haze.locations = [0, 0.5, 1]
        haze.opacity = 0
        container.addSublayer(haze)
        lens.masksToBounds = false
        plane.masksToBounds = false
        container.addSublayer(lens)
        lens.addSublayer(plane)
        build(IslandLaserCount.standard)
    }

    // MARK: How many

    /// Makes the layer hold `count` beams, held inside the least and the
    /// most. The same count again does nothing: the beams are made anew
    /// only when the count is a new one, and they come back hidden.
    func setBeamCount(_ count: Int) {
        let wanted = IslandLaserCount.clamped(count)
        guard wanted != beams.count else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        build(wanted)
        for beam in beams {
            size(beam)
            beam.soft.contentsScale = contentsScale
            beam.core.contentsScale = contentsScale
        }
        if let color { setColor(color, isForward: isForward, duration: 0) }
        CATransaction.commit()
        rebuilds += 1
        if let fan { place(fan, duration: 0) }
    }

    private func build(_ count: Int) {
        inks = Array(repeating: nil, count: count)
        beams.forEach { $0.holder.removeFromSuperlayer() }
        beams = (0..<count).map { _ in
            let beam = Self.makeBeam()
            plane.addSublayer(beam.holder)
            return beam
        }
    }

    // MARK: Geometry

    /// Where the notch sits in the container's space, and how far the reach
    /// lets a beam go. The beams leave the line of the notch's lower edge.
    func layout(notch: CGRect, reach: Double) {
        layout(notch: notch, length: IslandLaserLimits.fullLength(reach: reach))
    }

    /// The same for beams whose full length is `length` points.
    func layout(notch: CGRect, length: Double) {
        origin = CGPoint(x: notch.midX, y: notch.minY)
        drawnLength = max(IslandLaserRoom.longestBeam(length: length), 1)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The lens and the plane share the container's space, and each is
        // anchored at the middle of the notch's lower edge: the plane
        // turns about that edge, and the eye is in front of it.
        let space = container.bounds
        for layer in [lens, plane] {
            layer.bounds = space
            if space.width > 0, space.height > 0 {
                layer.anchorPoint = CGPoint(x: origin.x / space.width, y: origin.y / space.height)
            }
            layer.position = origin
        }
        haze.frame = CGRect(
            x: notch.minX - Self.hazeSide,
            y: notch.minY - Self.hazeDepth,
            width: notch.width + Self.hazeSide * 2,
            height: Self.hazeDepth
        )
        beams.forEach(size)
        CATransaction.commit()
        if let fan { place(fan, duration: 0) }
    }

    /// Gives a beam the size the beams are drawn at.
    private func size(_ beam: Beam) {
        let drawn = CGSize(width: Self.softWidth, height: drawnLength)
        // Bounds and position, never `frame`: the layers are turned and
        // scaled, and `frame` of such a layer is not its own size.
        beam.holder.bounds = CGRect(origin: .zero, size: drawn)
        beam.stem.bounds = CGRect(origin: .zero, size: drawn)
        beam.stem.position = CGPoint(x: drawn.width / 2, y: drawn.height)
        beam.soft.frame = CGRect(origin: .zero, size: drawn)
        beam.core.frame = CGRect(
            x: (drawn.width - Self.coreWidth) / 2, y: 0, width: Self.coreWidth, height: drawn.height
        )
    }

    func setContentsScale(_ scale: CGFloat) {
        contentsScale = scale
        haze.contentsScale = scale
        for beam in beams {
            beam.soft.contentsScale = scale
            beam.core.contentsScale = scale
        }
    }

    // MARK: Following the song

    /// Shows a fan. One that answers a hit is on screen with the next frame
    /// the system draws, with no rise. Between hits the beams follow the
    /// levels, fast when they grow and slower when they let go.
    func apply(_ fan: IslandLaserFan) {
        let previous = self.fan
        self.fan = fan
        let duration: TimeInterval
        if fan.landsAtOnce || previous == nil {
            duration = 0
        } else {
            duration = Self.span(of: fan) > Self.span(of: previous) ? Self.rise : Self.fall
        }
        place(fan, duration: duration)
        if container.opacity != 1 {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            container.opacity = 1
            CATransaction.commit()
        }
    }

    /// How bright the faint glow under the notch is with nothing playing
    /// on it.
    static let restingHaze: Float = 0.1
    /// A beam that is all the way back has this share of its length: as
    /// good as none, and still a transform that can be turned around.
    static let retracted: CGFloat = 0.001

    /// A hit: the fan is out at once, as `peak` says, and every beam
    /// comes all the way back to the notch over `duration`. Nothing is
    /// left out when it is over: the layers' own values are the rest, and
    /// the fall is one animation from the peak.
    ///
    /// `lunge` is for a fan that comes toward the viewer: it starts that
    /// many degrees further forward and is back at its own tilt when the
    /// beams are back, inside the same `duration`.
    func shoot(_ peak: IslandLaserFan, over duration: TimeInterval, lunge: Double = 0) {
        var rest = peak
        rest.beams = peak.beams.map { beam in
            var back = beam
            back.length = 0
            back.brightness = 0
            return back
        }
        rest.haze = Double(Self.restingHaze)
        rest.landsAtOnce = false
        fan = rest

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        paint(peak, duration: 0)
        turn(to: peak, duration: 0)
        if peak.tilt > 0, lunge > 0 {
            plane.add(
                Self.change(
                    keyPath: "transform",
                    from: NSValue(caTransform3D: Self.turned(peak.tilt + min(lunge, IslandLaserTilt.lunge))),
                    to: NSValue(caTransform3D: Self.turned(peak.tilt)),
                    duration: duration
                ),
                forKey: Self.tiltKey
            )
        }
        fall(haze, key: Self.opacityKey, from: Float(min(max(peak.haze, 0), 1)), to: Self.restingHaze, over: duration)
        for (index, beam) in beams.enumerated() {
            guard index < peak.beams.count else {
                set(beam.holder, key: Self.opacityKey, keyPath: "opacity", to: Float(0), duration: 0)
                continue
            }
            let values = peak.beams[index]
            beam.holder.position = CGPoint(x: origin.x + CGFloat(values.start), y: origin.y)
            set(
                beam.holder, key: Self.leanKey, keyPath: "transform",
                to: CATransform3DMakeRotation(CGFloat(values.lean), 0, 0, 1), duration: 0
            )
            let share = min(max(CGFloat(values.length) / drawnLength, Self.retracted), 1)
            beam.stem.transform = CATransform3DMakeScale(1, Self.retracted, 1)
            beam.stem.removeAnimation(forKey: Self.lengthKey)
            beam.stem.add(
                Self.change(
                    keyPath: "transform",
                    from: NSValue(caTransform3D: CATransform3DMakeScale(1, share, 1)),
                    to: NSValue(caTransform3D: CATransform3DMakeScale(1, Self.retracted, 1)),
                    duration: duration
                ),
                forKey: Self.lengthKey
            )
            fall(
                beam.holder, key: Self.opacityKey, from: Float(min(max(values.brightness, 0), 1)), to: 0,
                over: duration
            )
        }
        container.opacity = 1
        CATransaction.commit()
        animationStarts += 1
    }

    /// The faint glow under the notch at `peak` at once, and back to its
    /// rest over `duration`: a flash with no beam in it, or a hat's flicker.
    func flashHaze(to peak: Float, over duration: TimeInterval) {
        guard fan != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fall(haze, key: Self.opacityKey, from: min(max(peak, 0), 1), to: Self.restingHaze, over: duration)
        CATransaction.commit()
        animationStarts += 1
    }

    /// A layer's opacity at `peak` with the next frame, easing to `rest`.
    func fall(_ layer: CALayer, key: String, from peak: Float, to rest: Float, over duration: TimeInterval) {
        layer.opacity = rest
        layer.removeAnimation(forKey: key)
        layer.add(Self.change(keyPath: "opacity", from: peak, to: rest, duration: duration), forKey: key)
    }

    /// Takes the lasers off. The beams are kept for the next song.
    func end(animated: Bool) {
        guard fan != nil || scene != nil else { return }
        fan = nil
        if scene != nil { leaveScene() }
        set(container, key: Self.opacityKey, keyPath: "opacity", to: Float(0), duration: animated ? Motion.Halo.fade : 0)
    }

    /// Gives the beams the fan's color, drawn for the way the fan faces.
    private func paint(_ fan: IslandLaserFan, duration: TimeInterval) {
        if scene != nil { leaveScene() }
        let faces = fan.tilt > 0
        guard fan.color != color || faces != isForward else { return }
        color = fan.color
        setColor(fan.color, isForward: faces, duration: faces == isForward ? duration : 0)
        isForward = faces
    }

    /// Turns the beams' plane to the fan's tilt, and sets the eye.
    private func turn(to fan: IslandLaserFan, duration: TimeInterval) {
        var perspective = CATransform3DIdentity
        if fan.tilt > 0, fan.eye.isFinite, fan.eye > 0 { perspective.m34 = -1 / CGFloat(fan.eye) }
        lens.sublayerTransform = perspective
        set(plane, key: Self.tiltKey, keyPath: "transform", to: Self.turned(fan.tilt), duration: duration)
    }

    /// The plane turned `degrees` toward the viewer about the notch's
    /// lower edge. With y growing upward, what hangs below the edge comes
    /// forward for a turn the other way around the x axis.
    static func turned(_ degrees: Double) -> CATransform3D {
        degrees > 0 ? CATransform3DMakeRotation(-CGFloat(degrees) * .pi / 180, 1, 0, 0) : CATransform3DIdentity
    }

    private func place(_ fan: IslandLaserFan, duration: TimeInterval) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        paint(fan, duration: duration)
        turn(to: fan, duration: duration)
        set(haze, key: Self.opacityKey, keyPath: "opacity", to: Float(min(max(fan.haze, 0), 1)), duration: duration)
        for (index, beam) in beams.enumerated() {
            guard index < fan.beams.count else {
                set(beam.holder, key: Self.opacityKey, keyPath: "opacity", to: Float(0), duration: duration)
                continue
            }
            let values = fan.beams[index]
            // Where a beam starts moves only with the arrangement, which a
            // hit brings: it is never a slide.
            beam.holder.position = CGPoint(x: origin.x + CGFloat(values.start), y: origin.y)
            set(
                beam.holder, key: Self.leanKey, keyPath: "transform",
                to: CATransform3DMakeRotation(CGFloat(values.lean), 0, 0, 1), duration: duration
            )
            let share = min(max(CGFloat(values.length) / drawnLength, 0), 1)
            set(
                beam.stem, key: Self.lengthKey, keyPath: "transform",
                to: CATransform3DMakeScale(1, share, 1), duration: duration
            )
            set(
                beam.holder, key: Self.opacityKey, keyPath: "opacity",
                to: Float(min(max(values.brightness, 0), 1)), duration: duration
            )
        }
        CATransaction.commit()
    }

    /// The fan's size as one number: what tells growing from letting go.
    private static func span(of fan: IslandLaserFan?) -> Double {
        fan?.beams.reduce(0) { $0 + $1.length } ?? 0
    }

    // MARK: Layers

    private static func makeBeam() -> Beam {
        let holder = CALayer()
        holder.anchorPoint = CGPoint(x: 0.5, y: 1)
        holder.opacity = 0
        holder.masksToBounds = false
        // Light adds up where two beams cross, as it does in haze.
        holder.compositingFilter = "plusL"

        let stem = CALayer()
        stem.anchorPoint = CGPoint(x: 0.5, y: 1)
        stem.masksToBounds = false
        holder.addSublayer(stem)

        // The soft edge: brightest where the beam leaves the notch, gone at
        // its sides and at its tip.
        let soft = CAGradientLayer()
        soft.type = .radial
        soft.startPoint = CGPoint(x: 0.5, y: 1)
        soft.endPoint = CGPoint(x: 1, y: 0)
        soft.locations = [0, 0.45, 1]
        stem.addSublayer(soft)

        // The core: white hot, then the color, then nothing.
        let core = CAGradientLayer()
        core.startPoint = CGPoint(x: 0.5, y: 1)
        core.endPoint = CGPoint(x: 0.5, y: 0)
        core.locations = [0, 0.3, 1]
        core.cornerRadius = coreWidth / 2
        stem.addSublayer(core)
        return Beam(holder: holder, stem: stem, soft: soft, core: core)
    }

    /// How bright a beam that comes toward the viewer is where it leaves
    /// the notch, and how bright its soft edge is at its far end.
    static let forwardRoot: CGFloat = 0.45
    static let forwardHalo: CGFloat = 0.7
    /// Where along such a beam it is white hot. The little that is left
    /// after it fades out, which keeps the far end from looking cut off.
    static let forwardPeak = 0.9

    /// Paints every beam. A flat beam is brightest where it leaves the
    /// notch and gone at its tip. One that comes toward the viewer is the
    /// other way around: thin and faint at the notch, and at its far end
    /// white hot inside a soft edge that is widest there. The perspective
    /// adds to that: the far end is also drawn larger.
    private func setColor(_ color: IslandHaloRGB, isForward: Bool, duration: TimeInterval) {
        let paints = Self.gradients(for: color, isForward: isForward)
        // Every beam is this color now, whatever a show had left on it.
        inks = Array(repeating: nil, count: beams.count)
        setColors(haze, Self.hazeColors(for: color), duration: duration)
        for beam in beams {
            if isForward != self.isForward || beam.soft.colors == nil { Self.shape(beam, isForward: isForward) }
            setColors(beam.soft, paints.soft, duration: duration)
            setColors(beam.core, paints.core, duration: duration)
        }
    }

    /// A beam's two gradients in a color, for the way it faces.
    static func gradients(for color: IslandHaloRGB, isForward: Bool) -> (soft: [CGColor], core: [CGColor]) {
        let tint = color.cgColor
        let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        guard isForward else {
            return (
                soft: [tint.copy(alpha: 0.5) ?? tint, tint.copy(alpha: 0.16) ?? tint, tint.copy(alpha: 0) ?? tint],
                core: [white, tint.copy(alpha: 0.95) ?? tint, tint.copy(alpha: 0) ?? tint]
            )
        }
        return (
            soft: [
                tint.copy(alpha: forwardHalo) ?? tint, tint.copy(alpha: 0.22) ?? tint, tint.copy(alpha: 0) ?? tint,
            ],
            core: [
                tint.copy(alpha: forwardRoot) ?? tint, tint.copy(alpha: 0.95) ?? tint, white,
                white.copy(alpha: 0) ?? white,
            ]
        )
    }

    static func hazeColors(for color: IslandHaloRGB) -> [CGColor] {
        let tint = color.cgColor
        return [tint.copy(alpha: 0.55) ?? tint, tint.copy(alpha: 0.18) ?? tint, tint.copy(alpha: 0) ?? tint]
    }

    /// Where a beam's two gradients start and end. In a beam's own space
    /// y is 1 at the notch and 0 at its far end.
    static func shape(_ beam: Beam, isForward: Bool) {
        // The soft edge is a glow around one end: the notch's for a flat
        // beam, the far one for a beam that comes toward the viewer,
        // which tapers it to nothing at the notch.
        beam.soft.startPoint = CGPoint(x: 0.5, y: isForward ? 0 : 1)
        beam.soft.endPoint = CGPoint(x: 1, y: isForward ? 1 : 0)
        beam.soft.locations = [0, 0.45, 1]
        beam.core.locations = isForward ? [0, 0.55, NSNumber(value: forwardPeak), 1] : [0, 0.3, 1]
    }

    private func setColors(_ layer: CAGradientLayer, _ colors: [CGColor], duration: TimeInterval) {
        let from = layer.presentation()?.colors ?? layer.colors
        layer.colors = colors
        layer.removeAnimation(forKey: Self.colorKey)
        guard duration > 0, let from else { return }
        layer.add(Self.change(keyPath: "colors", from: from, to: colors, duration: duration), forKey: Self.colorKey)
        animationStarts += 1
    }

    func set(_ layer: CALayer, key: String, keyPath: String, to target: Float, duration: TimeInterval) {
        let from = layer.presentation()?.opacity ?? layer.opacity
        layer.opacity = target
        layer.removeAnimation(forKey: key)
        guard duration > 0, abs(from - target) > 0.001 else { return }
        layer.add(Self.change(keyPath: keyPath, from: from, to: target, duration: duration), forKey: key)
        animationStarts += 1
    }

    private func set(_ layer: CALayer, key: String, keyPath: String, to target: CATransform3D, duration: TimeInterval) {
        let from = layer.presentation()?.transform ?? layer.transform
        layer.transform = target
        layer.removeAnimation(forKey: key)
        guard duration > 0, !CATransform3DEqualToTransform(from, target) else { return }
        layer.add(
            Self.change(
                keyPath: keyPath, from: NSValue(caTransform3D: from), to: NSValue(caTransform3D: target),
                duration: duration
            ),
            forKey: key
        )
        animationStarts += 1
    }

    static func change(keyPath: String, from: Any, to: Any, duration: TimeInterval) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        // Named, or the window system composes it at the display's own
        // rate (D60).
        animation.preferredFrameRateRange = Motion.Halo.hitFrameRateRange
        return animation
    }
}
