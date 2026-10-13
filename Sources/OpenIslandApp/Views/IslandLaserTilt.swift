import CoreGraphics
import Foundation

/// The numbers of a fan that comes out of the screen toward the viewer
/// (D56).
///
/// The beams lie in a plane that hangs from the notch's lower edge. Flat,
/// that plane is the screen's own. Tilted, it turns about the edge and its
/// far side comes forward. The eye sits in front of the notch at a
/// distance, and what is nearer the eye is drawn larger, which is real
/// perspective: a beam that comes forward spreads, gets longer on the
/// screen and thicker toward its far end.
enum IslandLaserTilt {
    /// The usual tilt toward the viewer, in degrees.
    static let standard = 50.0
    /// How much further the fan tilts for a moment on a low hit.
    static let lunge = 8.0
    /// The most a fan may tilt at rest. A lunge on top of it is still
    /// short of pointing straight out of the screen.
    static let most = 90.0 - lunge
    /// How near the eye the tip of a full beam that points straight down
    /// comes at the top of a lunge, as a share of the eye's distance. It
    /// is what keeps every beam in front of the eye, where it can be drawn.
    static let depthShare = 0.6

    /// A tilt held between flat and the most. Anything that is no number
    /// is flat.
    static func held(_ degrees: Double) -> Double {
        degrees.isFinite ? min(max(degrees, 0), most) : 0
    }

    /// How far the eye is in front of the screen, in points, for beams
    /// whose full length is `fullLength`. It grows with the beams, which
    /// keeps the picture the same at every reach. A flat fan has no eye:
    /// infinity.
    static func eyeDistance(fullLength: Double, tilt: Double) -> Double {
        let tilt = held(tilt)
        guard tilt > 0, fullLength.isFinite, fullLength > 0 else { return .infinity }
        return fullLength * sin((tilt + lunge) * .pi / 180) / depthShare
    }

    /// Where a point of a beam lands on the screen.
    struct Spot: Equatable, Sendable {
        /// To the right of the middle of the notch's lower edge, in points.
        var x: Double
        /// Below that edge, in points.
        var down: Double
        /// How many times larger the beam is drawn there than on the flat
        /// screen: its thickness.
        var scale: Double
    }

    /// The spot for a point `along` a beam, in points from where it leaves
    /// the notch's lower edge.
    ///
    /// - Parameters:
    ///   - start: where the beam leaves the edge, in points from its middle.
    ///   - lean: how far the beam leans from straight down inside its
    ///     plane, in radians. Positive leans to the right.
    ///   - tilt: how far the plane is turned toward the viewer, in degrees.
    ///   - eye: the eye's distance, from `eyeDistance`.
    static func spot(start: Double, lean: Double, along: Double, tilt: Double, eye: Double) -> Spot {
        let turn = tilt * .pi / 180
        let across = start + along * sin(lean)
        let inPlane = along * cos(lean)
        // How far the point has come out of the screen.
        let forward = inPlane * sin(turn)
        let scale = eye.isFinite && eye > 0 ? eye / max(eye - forward, eye * 0.01) : 1
        return Spot(x: across * scale, down: inPlane * cos(turn) * scale, scale: scale)
    }
}
