import CoreGraphics
import Foundation

/// A show's picture as beams (D56): where each one stands, how long and
/// how bright it is, and its own color. Plain values, which the layer
/// turns into transforms of beams that are already drawn.
struct IslandLaserScene: Equatable, Sendable {
    /// One beam at rest.
    struct Beam: Equatable, Sendable {
        /// Where it leaves the line of the notch's lower edge, in points
        /// from the middle of the edge.
        var start: Double
        /// How far it leans from straight down, in radians.
        var lean: Double
        /// From its start to its tip, in points.
        var length: Double
        /// 0 to 1.
        var brightness: Double
        var color: IslandHaloRGB
    }

    /// What the beams do when the look comes on, and again when a hit
    /// stirs it. Each is one turn and then the beams are still: nothing
    /// here runs on by itself.
    enum Motion: Equatable, Sendable {
        case still
        /// The fan narrows to `narrow` of its leans and opens again, over
        /// `period` seconds.
        case breathe(narrow: Double, period: TimeInterval)
        /// A wave runs along the beams' lengths, `depth` of the length up
        /// and down, once across the fan in `period` seconds.
        case wave(depth: Double, period: TimeInterval)
    }

    /// A still beam rests at this share of its full length, which leaves
    /// a low hit the rest to push it out by.
    static let restShare = 1 / (1 + IslandLaserShow.pushLength)
    /// The Odd Even's group that is not lit, and the dim beams of a wave.
    static let dimGroup = 0.12
    static let waveBrightness = 0.55
    /// A wave's beams rest at this share of their full length and move
    /// by this share of it.
    static let waveRest = 0.6
    static let waveDepth = 0.3
    /// How narrow a breathing fan gets, as a share of its leans: 40
    /// degrees of the 128 it opens to.
    static let breatheNarrow = 40.0 / 128
    /// One breath, and one wave across the fan.
    static let slowPeriod = IslandLaserShow.slowPeriod
    static let white = IslandHaloRGB(red: 1, green: 1, blue: 1)

    var beams: [Beam]
    var motion: Motion
    /// How far the beams' plane is tilted toward the viewer, in degrees,
    /// and the eye's distance for it.
    var tilt: Double
    var eye: Double
    /// The color of the faint glow under the notch.
    var haze: IslandHaloRGB

    /// The beams for a picture.
    ///
    /// - Parameters:
    ///   - hues: the four colors around the art's own. The picture's base
    ///     and accent are places among them.
    ///   - fullLength: a beam's full length for the lasers' reach.
    init(
        picture: IslandLaserPicture,
        hues: [IslandHaloRGB],
        count: Int,
        space: IslandLaserSpace,
        reach: Double,
        fullLength: Double
    ) {
        let lineup = picture.look.arrangement.lineup(count: count, space: space, reach: reach)
        let base = Self.hue(picture.base, of: hues)
        let accent = Self.hue(picture.accent, of: hues)
        let total = lineup.stands.count
        let kind = picture.look.kind
        let share = kind == .wave ? Self.waveRest : Self.restShare
        beams = lineup.stands.enumerated().map { index, stand in
            let color: IslandHaloRGB
            var brightness = 1.0
            switch kind {
            case .still:
                // The outer quarter on each side is the accent.
                color = min(index, total - 1 - index) < total / 4 ? accent : base
            case .oddEven:
                // One color for each group, and one group lit.
                color = index.isMultiple(of: 2) ? base : accent
                brightness = index % 2 == picture.litGroup % 2 ? 1 : Self.dimGroup
            case .breathe:
                color = base
            case .wave:
                color = base
                brightness = Self.waveBrightness
            }
            return Beam(
                start: stand.start,
                lean: stand.lean * Double.pi / 180,
                length: min(fullLength * stand.share * share, lineup.longest),
                brightness: brightness,
                color: color
            )
        }
        switch kind {
        case .still, .oddEven: motion = .still
        case .breathe: motion = .breathe(narrow: Self.breatheNarrow, period: Self.slowPeriod)
        case .wave: motion = .wave(depth: Self.waveDepth / Self.waveRest, period: Self.slowPeriod)
        }
        tilt = IslandLaserTilt.held(lineup.tilt)
        eye = IslandLaserTilt.eyeDistance(fullLength: fullLength, tilt: lineup.tilt)
        haze = base
    }

    /// The same beams as a drop shows them: every one white, lit, and at
    /// its full length.
    var burst: IslandLaserScene {
        var scene = self
        scene.beams = beams.map { beam in
            var full = beam
            full.length = beam.length / Self.restShare
            full.brightness = 1
            full.color = Self.white
            return full
        }
        scene.motion = .still
        return scene
    }

    /// How far each beam is from the middle pair, in beams: 0 for the
    /// two in the middle. A burst lights them in that order.
    static func ranks(count: Int) -> [Int] {
        (0..<count).map { index in
            let fromEnd = min(index, count - 1 - index)
            return (count - 1) / 2 - fromEnd
        }
    }

    private static func hue(_ index: Int, of hues: [IslandHaloRGB]) -> IslandHaloRGB {
        guard !hues.isEmpty else { return white }
        return hues[((index % hues.count) + hues.count) % hues.count]
    }
}
