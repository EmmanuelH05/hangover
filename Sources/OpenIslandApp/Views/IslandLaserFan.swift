import CoreGraphics
import Foundation

/// The numbers the lasers hold to (D56).
enum IslandLaserLimits {
    /// The widest a beam leans from straight down: 72 degrees, in radians.
    static let widestLean = 72.0 * Double.pi / 180
    /// A hat moves one beam's length by this share at most.
    static let hatCeiling = 0.15
    /// How long a hat's nudge takes to let go.
    static let hatRelease: TimeInterval = 0.12
    /// A beam's length with no bass at all, as a share of its full length.
    static let restingShare = 0.22
    /// A beam's full length at each end of "How far it reaches" and in the
    /// middle, in points.
    static let leastLength = 70.0
    static let standardLength = 150.0
    static let mostLength = 260.0
    /// The slow sway between hits: how far a beam leans with it, and how
    /// long one sway takes.
    static let driftLean = 4.0 * Double.pi / 180
    static let driftPeriod: TimeInterval = 7
    /// The fastest a beam may lean while it drifts, in degrees a second.
    /// The sway above stays under it.
    static let mostDriftDegreesASecond = 6.0
    /// Half the width of a beam's soft edge. The room leaves this much
    /// beside the outermost beam and under the longest one.
    static let softHalfWidth = 9.0
    /// How far the curtain goes past each end of the notch's lower edge.
    static let curtainBeyond = 24.0
    /// The wide curtain at a reach of 0, as a multiple of the curtain.
    static let wideStart = 2.0
    /// How much shorter the wide curtain's outermost beams are than its
    /// middle ones, as a share of the full length.
    static let wideDip = 0.3
    /// The share of each side of the split that is left empty, from the
    /// middle outward.
    static let splitGap = 1.0 / 3

    /// A beam's full length for a reach of 0 to 1: a straight line from the
    /// least to the standard, and another from there to the most.
    static func fullLength(reach: Double) -> Double {
        let held = IslandBeatReach.clamped(reach)
        if held <= IslandBeatReach.standard {
            let share = held / IslandBeatReach.standard
            return leastLength + (standardLength - leastLength) * share
        }
        let share = (held - IslandBeatReach.standard) / (1 - IslandBeatReach.standard)
        return standardLength + (mostLength - standardLength) * share
    }
}

/// How long the lasers' beams are, from the lasers' own "How far the
/// lasers reach" (D56). It is a longer range than the glow's by far: the
/// beams are light, and the owner wants them able to cross the screen.
enum IslandLaserReach {
    /// Where the slider starts: a quarter of the way.
    static let standard = 0.25

    /// A reach held inside 0 to 1. Anything that is not a number is the
    /// standard.
    static func clamped(_ reach: Double) -> Double {
        guard reach.isFinite else { return standard }
        return min(1, max(0, reach))
    }

    /// How far it is from the middle of the closed island's lower edge to
    /// the far bottom corner of its screen, which is as far as a beam can
    /// usefully go. Both rectangles are in the same space, y up.
    static func farthest(pill: CGRect, screen: CGRect) -> Double {
        let across = max(pill.midX - screen.minX, screen.maxX - pill.midX)
        let down = pill.minY - screen.minY
        return Double(hypot(max(across, 0), max(down, 0)))
    }

    /// A beam's full length for a reach of 0 to 1. At 0 it is what the
    /// longest beam was before this slider. At 1 it reaches the far bottom
    /// corner of the island's screen. A straight line between the two,
    /// which puts the standard a quarter of the way.
    static func length(reach: Double, farthest: Double) -> Double {
        let least = IslandLaserLimits.mostLength
        let most = max(farthest.isFinite ? farthest : least, least)
        return least + (most - least) * clamped(reach)
    }
}

/// One beam, as plain numbers.
struct IslandLaserBeam: Equatable, Sendable {
    /// Where it leaves the line of the notch's lower edge, in points from
    /// the middle of the edge. Positive is to the right.
    var start: Double
    /// How far it leans from straight down, in radians. Positive leans to
    /// the right.
    var lean: Double
    /// From its start to its tip, in points.
    var length: Double
    /// 0 to 1.
    var brightness: Double
}

/// The whole fan at one moment: what a frame of the song, the reach, the
/// art's color and a lineup of beams come to. Plain values, which the layer
/// turns into transforms of beams that are already drawn (D48).
struct IslandLaserFan: Equatable, Sendable {
    var beams: [IslandLaserBeam]
    var color: IslandHaloRGB
    /// The faint glow under the beams, 0 to 1.
    var haze: Double
    /// True for a fan that answers a hit. It is shown at once, with no rise.
    var landsAtOnce: Bool
    /// How far the beams' plane is tilted out of the screen toward the
    /// viewer, in degrees. 0 is flat.
    var tilt: Double
    /// How far the viewer's eye is in front of the screen, in points:
    /// what the perspective is drawn with. Infinity when flat.
    var eye: Double

    /// - Parameters:
    ///   - lineup: where each beam stands, from an arrangement.
    ///   - nudges: each beam's length as a hat left it, 1 when untouched.
    ///     Anything past the hat's ceiling is held to it.
    ///   - time: the clock the slow sway runs on, in seconds.
    init(
        frame: IslandBeatFrame,
        reach: Double,
        tint: IslandHaloRGB?,
        lineup: IslandLaserLineup,
        hueIndex: Int,
        nudges: [Double] = [],
        time: TimeInterval,
        fullLength: Double? = nil
    ) {
        // A kick is the bass at its top, whatever the level had reached.
        let low = frame.hit == .kick ? 1 : Self.held(frame.low)
        let mid = Self.held(frame.mid)
        // The length the lasers' own slider gives, when the caller has one.
        let full = fullLength ?? IslandLaserLimits.fullLength(reach: reach)
        let grown = IslandLaserLimits.restingShare + (1 - IslandLaserLimits.restingShare) * low
        var brightness = min(1, 0.35 + 0.4 * low + 0.35 * mid)
        if frame.hit == .kick { brightness = max(brightness, 0.9) }
        if frame.hit == .snare { brightness = 1 }

        let ceiling = IslandLaserLimits.hatCeiling
        beams = lineup.stands.enumerated().map { index, stand in
            // Beams that come straight down stay side by side: no sway.
            let sway = lineup.sways
                ? IslandLaserLimits.driftLean
                    * sin(2 * Double.pi * time / IslandLaserLimits.driftPeriod + Double(index) * 0.7)
                : 0
            let lean = stand.lean * Double.pi / 180 + sway
            let nudge = index < nudges.count ? min(max(nudges[index], 1 - ceiling), 1 + ceiling) : 1
            return IslandLaserBeam(
                start: stand.start,
                lean: min(max(lean, -IslandLaserLimits.widestLean), IslandLaserLimits.widestLean),
                length: min(full * stand.share * grown * nudge, lineup.longest),
                brightness: brightness
            )
        }
        let hues = IslandBeatHues.hues(around: tint)
        color = hues[((hueIndex % hues.count) + hues.count) % hues.count]
        haze = 0.1 + 0.3 * low
        landsAtOnce = frame.hit != nil
        tilt = IslandLaserTilt.held(lineup.tilt)
        eye = IslandLaserTilt.eyeDistance(fullLength: full, tilt: lineup.tilt)
    }

    private static func held(_ level: Double) -> Double {
        level.isFinite ? min(max(level, 0), 1) : 0
    }
}

/// What the fan remembers from one frame to the next: which arrangement and
/// which color show, and what the hats did to single beams. A snare moves
/// it to the next arrangement, fans and curtains in one list, and to the
/// next color. A hat nudges one beam, and a hat alone changes neither of
/// the two.
struct IslandLaserScore: Equatable, Sendable {
    private(set) var arrangementIndex = 0
    private(set) var hueIndex = 0
    /// Each beam's length as a hat left it, 1 when untouched.
    private(set) var nudges: [Double] = []
    private var hats = 0
    private var lastTime: TimeInterval?

    var arrangement: IslandLaserArrangement { IslandLaserArrangement.at(arrangementIndex) }

    /// The fan for a frame, with `count` beams in the room `space` gives.
    /// `time` is the caller's clock, in seconds: it runs the slow sway and
    /// lets a hat's nudge go.
    mutating func fan(
        for frame: IslandBeatFrame,
        reach: Double,
        tint: IslandHaloRGB?,
        count: Int = IslandLaserCount.standard,
        space: IslandLaserSpace,
        time: TimeInterval,
        fullLength: Double? = nil
    ) -> IslandLaserFan {
        release(until: time)
        if frame.hit == .snare {
            arrangementIndex = (arrangementIndex + 1) % IslandLaserArrangement.all.count
            hueIndex = (hueIndex + 1) % IslandBeatHues.offsets.count
            nudges = []
        }
        let lineup = arrangement.lineup(count: count, space: space, reach: reach)
        if nudges.count != lineup.stands.count { nudges = Array(repeating: 1, count: lineup.stands.count) }
        if frame.hit == .hat { nudge(strength: frame.high) }
        return IslandLaserFan(
            frame: frame,
            reach: reach,
            tint: tint,
            lineup: lineup,
            hueIndex: hueIndex,
            nudges: nudges,
            time: time,
            fullLength: fullLength
        )
    }

    /// A hat takes the next beam in a fixed walk across the fan, longer one
    /// time and shorter the next. A loud hat moves it by the whole ceiling
    /// and a soft one by half of it.
    private mutating func nudge(strength: Double) {
        guard !nudges.isEmpty else { return }
        let index = (hats * 3 + 1) % nudges.count
        let share = strength.isFinite ? min(max(strength, 0.5), 1) : 0.5
        let direction: Double = hats.isMultiple(of: 2) ? 1 : -1
        nudges[index] = 1 + direction * IslandLaserLimits.hatCeiling * share
        hats += 1
    }

    /// Lets every nudge go a little, by the time since the last frame.
    private mutating func release(until time: TimeInterval) {
        defer { lastTime = time }
        guard let lastTime, time > lastTime, !nudges.isEmpty else { return }
        let kept = exp(-(time - lastTime) / IslandLaserLimits.hatRelease)
        nudges = nudges.map { 1 + ($0 - 1) * kept }
    }
}

/// How much room the beams need around the notch (D56): every
/// arrangement, the sway and a hat's nudge fit inside it.
enum IslandLaserRoom {
    /// The longest a beam gets for a reach.
    static func longestBeam(reach: Double) -> CGFloat {
        longestBeam(length: IslandLaserLimits.fullLength(reach: reach))
    }

    /// The longest a beam gets when its full length is `length` points.
    static func longestBeam(length: Double) -> CGFloat {
        CGFloat(max(length, 0) * (1 + IslandLaserLimits.hatCeiling))
    }

    /// How far past the notch's two sides and below its lower edge the
    /// beams paint at most.
    static func insets(reach: Double) -> (side: CGFloat, below: CGFloat) {
        insets(length: IslandLaserLimits.fullLength(reach: reach))
    }

    /// The same for beams whose full length is `length` points.
    static func insets(length: Double) -> (side: CGFloat, below: CGFloat) {
        let longest = longestBeam(length: length)
        let soft = CGFloat(IslandLaserLimits.softHalfWidth)
        return (
            side: longest * CGFloat(sin(IslandLaserLimits.widestLean)) + soft,
            below: longest + soft
        )
    }

    /// The rectangle that holds the notch and every beam under it, in the
    /// space `notch` is given in, with y growing upward as AppKit counts.
    static func rect(reach: Double, notch: CGRect) -> CGRect {
        rect(length: IslandLaserLimits.fullLength(reach: reach), notch: notch)
    }

    /// The same for beams whose full length is `length` points. It holds
    /// the beams that lean, and it may be far larger than the screen.
    static func rect(length: Double, notch: CGRect) -> CGRect {
        let room = insets(length: length)
        return CGRect(
            x: notch.minX - room.side,
            y: notch.minY - room.below,
            width: notch.width + room.side * 2,
            height: notch.height + room.below
        )
    }

    /// How far to each side of the middle of the notch's lower edge, and
    /// how far below it, a fan tilted toward the viewer paints at most.
    /// It is further than the flat fan on both counts: what comes forward
    /// is drawn larger. Every lean is counted, at rest and at the top of a
    /// lunge, with the soft edge as large as it is drawn out there.
    static func tiltedReach(length: Double, tilt: Double, halfEdge: Double) -> (side: CGFloat, below: CGFloat) {
        let tilt = IslandLaserTilt.held(tilt)
        guard tilt > 0 else { return (0, 0) }
        let longest = Double(longestBeam(length: length))
        let eye = IslandLaserTilt.eyeDistance(fullLength: length, tilt: tilt)
        let soft = IslandLaserLimits.softHalfWidth
        var side = 0.0
        var below = 0.0
        for turn in [tilt, tilt + IslandLaserTilt.lunge] {
            for step in 0...tiltedSteps {
                let lean = IslandLaserLimits.widestLean * Double(step) / Double(tiltedSteps)
                let tip = IslandLaserTilt.spot(
                    start: max(halfEdge, 0), lean: lean, along: longest, tilt: turn, eye: eye
                )
                side = max(side, tip.x + soft * tip.scale)
                below = max(below, tip.down + soft * tip.scale)
            }
        }
        // A point for what lies between two of the leans that were tried.
        return (side: CGFloat(side + 1), below: CGFloat(below + 1))
    }

    /// How many leans `tiltedReach` tries between straight down and the
    /// widest: one every quarter of a degree.
    private static let tiltedSteps = 288

    /// The room for every arrangement on one screen: the beams that lean,
    /// flat and tilted toward the viewer, and the curtains at their widest
    /// for the lasers' `reach`, cut to the island's screen. A beam that
    /// would go past the screen is cut at its edge. `pill` is the closed
    /// island and `screen` its screen, both in one space with y growing
    /// upward.
    static func rect(length: Double, reach: Double, pill: CGRect, screen: CGRect) -> CGRect {
        let leaning = rect(length: length, notch: pill)
        let wide = IslandLaserSpace(pill: pill, screen: screen).wide(reach: reach)
        let soft = CGFloat(IslandLaserLimits.softHalfWidth)
        let standing = CGRect(
            x: pill.midX - CGFloat(wide.left) - soft,
            y: leaning.minY,
            width: CGFloat(wide.left + wide.right) + soft * 2,
            height: leaning.height
        )
        let tilted = tiltedReach(length: length, tilt: widestTilt, halfEdge: Double(pill.width) / 2)
        let forward = CGRect(
            x: pill.midX - tilted.side,
            y: pill.minY - tilted.below,
            width: tilted.side * 2,
            height: pill.height + tilted.below
        )
        return leaning.union(standing).union(forward).intersection(screen)
    }

    /// The furthest any arrangement in the list tilts toward the viewer.
    static var widestTilt: Double {
        IslandLaserArrangement.all.map(\.orientation.tilt).max() ?? 0
    }
}
