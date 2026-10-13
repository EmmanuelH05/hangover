import AppKit
import QuartzCore

// MARK: - The show

/// What a show asks of the beams (D56). A scene has a color for every
/// beam, and its beams stay on between hits. All of it is still places,
/// transforms, opacities and gradient colors of beams that are drawn
/// once. A wave or a breath is one animation the system runs through
/// once and then the beams are still: nothing here repeats, because an
/// endless animation is composed for every frame it is up (D60).
extension IslandLaserLayer {
    /// The whole picture's brightness at rest in a show. A hit lifts it
    /// to full and a hat a little.
    static let showRest: Float = 0.8
    /// How bright the faint glow under the notch is in a show.
    static let showHaze: Float = 0.25
    /// How many points of a wave the system is given to draw it through.
    private static let waveSteps = 8
    private static let burstKey = "laser.burst"

    /// Cuts to a scene: every beam where the scene says and in its own
    /// color, at once. A scene that moves makes its one move here.
    func show(_ scene: IslandLaserScene) {
        fan = nil
        color = nil
        self.scene = scene
        let faces = scene.tilt > 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var perspective = CATransform3DIdentity
        if faces, scene.eye.isFinite, scene.eye > 0 { perspective.m34 = -1 / CGFloat(scene.eye) }
        lens.sublayerTransform = perspective
        plane.removeAnimation(forKey: Self.tiltKey)
        plane.transform = Self.turned(scene.tilt)
        haze.removeAnimation(forKey: Self.opacityKey)
        haze.removeAnimation(forKey: Self.colorKey)
        haze.colors = Self.hazeColors(for: scene.haze)
        haze.opacity = Self.showHaze
        for (index, beam) in beams.enumerated() {
            still(beam)
            guard index < scene.beams.count else {
                beam.holder.opacity = 0
                continue
            }
            let values = scene.beams[index]
            paint(beamAt: index, Ink(color: values.color, isForward: faces))
            beam.holder.position = CGPoint(x: origin.x + CGFloat(values.start), y: origin.y)
            beam.holder.transform = CATransform3DMakeRotation(CGFloat(values.lean), 0, 0, 1)
            beam.stem.transform = CATransform3DMakeScale(1, share(of: values.length), 1)
            beam.holder.opacity = Float(min(max(values.brightness, 0), 1))
        }
        move(scene)
        container.removeAnimation(forKey: Self.opacityKey)
        container.opacity = Self.showRest
        CATransaction.commit()
    }

    /// A low hit inside a scene: every lit beam `push` of its length
    /// longer and the whole picture at full brightness, at once, and
    /// both back over `duration`. A scene that is not the one on, the
    /// Odd Even's other group for one, is cut to first. Beams that move
    /// by themselves keep their motion and only brighten.
    func push(_ scene: IslandLaserScene, by push: Double, over duration: TimeInterval) {
        if scene != self.scene { show(scene) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if scene.motion == .still {
            for (index, beam) in beams.enumerated() where index < scene.beams.count {
                let values = scene.beams[index]
                guard values.brightness > IslandLaserScene.dimGroup else { continue }
                let rest = share(of: values.length)
                let peak = min(rest * CGFloat(1 + max(push, 0)), 1)
                beam.stem.add(
                    Self.change(
                        keyPath: "transform",
                        from: NSValue(caTransform3D: CATransform3DMakeScale(1, peak, 1)),
                        to: NSValue(caTransform3D: CATransform3DMakeScale(1, rest, 1)),
                        duration: duration
                    ),
                    forKey: Self.lengthKey
                )
            }
        }
        fall(container, key: Self.opacityKey, from: 1, to: Self.showRest, over: duration)
        CATransaction.commit()
        animationStarts += 1
    }

    /// A snare or a clap: every beam white at once, and the scene's own
    /// colors, which have changed places, when the white is gone.
    func flashWhite(into scene: IslandLaserScene, over duration: TimeInterval) {
        show(scene)
        let white = Self.gradients(for: IslandLaserScene.white, isForward: scene.tilt > 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, beam) in beams.enumerated() where index < scene.beams.count {
            guard let soft = beam.soft.colors, let core = beam.core.colors else { continue }
            beam.soft.add(
                Self.change(keyPath: "colors", from: white.soft, to: soft, duration: duration), forKey: Self.colorKey
            )
            beam.core.add(
                Self.change(keyPath: "colors", from: white.core, to: core, duration: duration), forKey: Self.colorKey
            )
        }
        fall(container, key: Self.opacityKey, from: 1, to: Self.showRest, over: duration)
        CATransaction.commit()
        animationStarts += 1
    }

    /// A quiet look moves once more: one breath, or one wave across the
    /// fan. A scene that is not the one on is cut to, which moves it too.
    func stir(_ scene: IslandLaserScene) {
        guard scene == self.scene else {
            show(scene)
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        move(scene)
        CATransaction.commit()
        animationStarts += 1
    }

    /// A hat: the whole picture a little brighter for a moment. Nothing
    /// while there is no scene.
    func shimmer(_ strength: Double, over duration: TimeInterval) {
        guard scene != nil else { return }
        let room = (1 - Self.showRest) * Float(min(max(strength, 0.5), 1))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fall(container, key: Self.opacityKey, from: Self.showRest + room, to: Self.showRest, over: duration)
        CATransaction.commit()
        animationStarts += 1
    }

    /// Darkness: the picture fades out over `fade` and nothing moves
    /// under it.
    func blackOut(over fade: TimeInterval) {
        guard scene != nil || container.opacity > 0 else { return }
        scene = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        beams.forEach(still)
        CATransaction.commit()
        set(container, key: Self.opacityKey, keyPath: "opacity", to: Float(0), duration: fade)
    }

    /// The drop: the scene's beams light from the middle pair outward
    /// over `spread`, hold, and come back to the notch from the outside
    /// in, each over `fall`. Nothing is left on when it is over.
    func burst(_ scene: IslandLaserScene, spread: TimeInterval, hold: TimeInterval, fall: TimeInterval) {
        show(scene)
        self.scene = nil
        let total = spread + hold + spread + fall
        let ranks = IslandLaserScene.ranks(count: scene.beams.count)
        let last = Double(max(ranks.max() ?? 0, 1))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, beam) in beams.enumerated() where index < scene.beams.count {
            let lit = spread * Double(ranks[index]) / last
            let back = spread + hold + spread * (1 - Double(ranks[index]) / last)
            let times = [0, lit, lit, back, back + fall, total].map { NSNumber(value: $0 / total) }
            let full = share(of: scene.beams[index].length)

            let length = CAKeyframeAnimation(keyPath: "transform.scale.y")
            length.values = [Self.retracted, Self.retracted, full, full, Self.retracted, Self.retracted]
            let light = CAKeyframeAnimation(keyPath: "opacity")
            light.values = [0, 0, 1, 1, 0, 0]
            for animation in [length, light] {
                animation.keyTimes = times
                animation.duration = total
                animation.calculationMode = .linear
                animation.preferredFrameRateRange = Motion.Halo.hitFrameRateRange
            }
            beam.stem.transform = CATransform3DMakeScale(1, Self.retracted, 1)
            beam.holder.opacity = 0
            beam.stem.add(length, forKey: Self.burstKey)
            beam.holder.add(light, forKey: Self.burstKey)
        }
        self.fall(haze, key: Self.opacityKey, from: 1, to: Self.restingHaze, over: total)
        container.opacity = 1
        CATransaction.commit()
        animationStarts += 1
    }

    /// A scene's one move. The system runs it through once: nothing here
    /// is called again for a frame of it, and when it is over the beams
    /// are where they were, with nothing left running.
    private func move(_ scene: IslandLaserScene) {
        switch scene.motion {
        case .still:
            break
        case let .breathe(narrow, period):
            for (index, beam) in beams.enumerated() where index < scene.beams.count {
                let lean = CGFloat(scene.beams[index].lean)
                let breath = CABasicAnimation(keyPath: "transform")
                breath.fromValue = NSValue(caTransform3D: CATransform3DMakeRotation(lean, 0, 0, 1))
                breath.toValue = NSValue(caTransform3D: CATransform3DMakeRotation(lean * CGFloat(narrow), 0, 0, 1))
                // In and out again: one breath.
                breath.duration = period / 2
                breath.autoreverses = true
                breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                breath.preferredFrameRateRange = Motion.Halo.slowFrameRateRange
                beam.holder.add(breath, forKey: Self.leanKey)
            }
        case let .wave(depth, period):
            let count = Double(max(scene.beams.count, 1))
            for (index, beam) in beams.enumerated() where index < scene.beams.count {
                let rest = Double(share(of: scene.beams[index].length))
                let wave = CAKeyframeAnimation(keyPath: "transform.scale.y")
                // One turn of the wave, with this beam's place in it
                // written into the values.
                wave.values = (0...Self.waveSteps).map { step in
                    let turn = Double(step) / Double(Self.waveSteps) - Double(index) / count
                    return min(rest * (1 + depth * sin(2 * Double.pi * turn)), 1)
                }
                wave.duration = period
                wave.calculationMode = .cubic
                wave.preferredFrameRateRange = Motion.Halo.slowFrameRateRange
                beam.stem.add(wave, forKey: Self.lengthKey)
            }
        }
    }

    /// Stops whatever a beam was doing.
    private func still(_ beam: Beam) {
        beam.holder.removeAllAnimations()
        beam.stem.removeAllAnimations()
        beam.soft.removeAnimation(forKey: Self.colorKey)
        beam.core.removeAnimation(forKey: Self.colorKey)
    }

    /// Leaves a show: its motion stops, and the next fan paints every
    /// beam again, because a show left each in a color of its own.
    func leaveScene() {
        scene = nil
        color = nil
        inks = Array(repeating: nil, count: beams.count)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        beams.forEach(still)
        container.removeAnimation(forKey: Self.opacityKey)
        CATransaction.commit()
    }

    private func paint(beamAt index: Int, _ ink: Ink) {
        guard inks.indices.contains(index), inks[index] != ink else { return }
        let beam = beams[index]
        if inks[index]?.isForward != ink.isForward { Self.shape(beam, isForward: ink.isForward) }
        let paints = Self.gradients(for: ink.color, isForward: ink.isForward)
        beam.soft.colors = paints.soft
        beam.core.colors = paints.core
        inks[index] = ink
        isForward = ink.isForward
    }

    /// A length as a share of the length the beams are drawn at.
    private func share(of length: Double) -> CGFloat {
        min(max(CGFloat(length) / drawnLength, Self.retracted), 1)
    }
}
