import AppKit
import QuartzCore

// MARK: - What the tests read

extension IslandLaserLayer {
    /// The fall of a beam's length that is running, if one is.
    func lengthFall(ofBeam index: Int) -> CABasicAnimation? {
        beams[index].stem.animation(forKey: Self.lengthKey) as? CABasicAnimation
    }

    /// The fall of the faint glow under the notch, if one is running.
    var hazeFall: CABasicAnimation? { hazeLayer.animation(forKey: Self.opacityKey) as? CABasicAnimation }

    /// How many beams show.
    var shownBeamCount: Int { beams.filter { $0.holder.opacity > 0 }.count }

    /// The color a beam's core is in: the middle stop of its gradient.
    func coreColor(ofBeam index: Int) -> CGColor? {
        (beams[index].core.colors as? [CGColor]).flatMap { $0.count > 1 ? $0[1] : nil }
    }

    /// The white flash on a beam that is running, if one is.
    func colorFlash(ofBeam index: Int) -> CABasicAnimation? {
        beams[index].core.animation(forKey: Self.colorKey) as? CABasicAnimation
    }

    /// The wave on a beam's length, and the breath on its lean.
    func wave(ofBeam index: Int) -> CAKeyframeAnimation? {
        beams[index].stem.animation(forKey: Self.lengthKey) as? CAKeyframeAnimation
    }

    func breath(ofBeam index: Int) -> CABasicAnimation? {
        beams[index].holder.animation(forKey: Self.leanKey) as? CABasicAnimation
    }

    /// The burst on a beam's length, if one is running.
    func burstLength(ofBeam index: Int) -> CAKeyframeAnimation? {
        beams[index].stem.animation(forKey: "laser.burst") as? CAKeyframeAnimation
    }

    /// The lift of the whole picture's brightness that is running.
    var lift: CABasicAnimation? { container.animation(forKey: Self.opacityKey) as? CABasicAnimation }

    /// How many layers the beams' plane holds: one for each beam.
    var beamLayerCount: Int { plane.sublayers?.count ?? 0 }

    /// How far the beams' plane is turned toward the viewer as its layer
    /// holds it, in degrees.
    var tilt: Double { Self.tilt(of: plane.transform) }

    /// The eye's distance as the layer above the plane holds it, in
    /// points, and infinity with no perspective.
    var eye: Double {
        let depth = lens.sublayerTransform.m34
        return depth < 0 ? Double(-1 / depth) : .infinity
    }

    /// The middle of the notch's lower edge in the container's space,
    /// which the plane turns about and the eye is in front of.
    var pivot: CGPoint { plane.position }

    /// The lunge of the plane that is running, if one is.
    var tiltFall: CABasicAnimation? { plane.animation(forKey: Self.tiltKey) as? CABasicAnimation }

    /// The degrees toward the viewer a plane's transform stands for.
    static func tilt(of transform: CATransform3D) -> Double {
        Double(-atan2(transform.m23, transform.m22)) * 180 / .pi
    }

    /// A beam's lean as its layer holds it, in radians.
    func lean(ofBeam index: Int) -> Double {
        let transform = beams[index].holder.transform
        return Double(atan2(transform.m12, transform.m11))
    }

    /// A beam's length as its layer holds it, in points.
    func length(ofBeam index: Int) -> Double {
        Double(beams[index].stem.transform.m22 * drawnLength)
    }
}
