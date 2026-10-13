import CoreGraphics
import Foundation

/// How many beams there are, from "How many lasers" (D56).
enum IslandLaserCount {
    static let least = 8
    static let most = 24
    /// Where the slider starts.
    static let standard = 16
    /// The slider moves two at a time: an even count keeps the left half
    /// of every arrangement the same as the right.
    static let step = 2
    static let titleKey = "settings.appearance.nook.halo.beat.laserCount"

    /// A count held inside the least and the most.
    static func clamped(_ count: Int) -> Int {
        min(most, max(least, count))
    }

    /// What a saved value reads as, and nil for one that is no number.
    /// Settings from before the choice have none, and get the standard.
    static func stored(_ value: Any?) -> Int? {
        if let count = value as? Int { return clamped(count) }
        guard let number = value as? Double, number.isFinite else { return nil }
        return Int(min(max(number, Double(least)), Double(most)).rounded())
    }
}

/// The room the beams have, in points, measured from the middle of the
/// closed island's lower edge: the edge's own width, how far it is to each
/// side of the island's screen, and how far down to the screen's bottom.
struct IslandLaserSpace: Equatable, Sendable {
    var notchWidth: Double
    var left: Double
    var right: Double
    var down: Double
}

extension IslandLaserSpace {
    /// `pill` is the closed island and `screen` its screen, both in one
    /// space with y growing upward.
    init(pill: CGRect, screen: CGRect) {
        self.init(
            notchWidth: Double(pill.width),
            left: Double(pill.midX - screen.minX),
            right: Double(screen.maxX - pill.midX),
            down: Double(pill.minY - screen.minY)
        )
    }

    /// Half the notch's lower edge.
    var halfEdge: Double {
        notchWidth.isFinite ? max(notchWidth, 0) / 2 : 0
    }

    /// How far from the middle a beam may stand on one side with its soft
    /// edge still on the screen.
    private func farthest(_ side: Double) -> Double {
        side.isFinite ? max(side - IslandLaserLimits.softHalfWidth, 0) : 0
    }

    /// How far the curtain goes to each side: the notch's edge and a
    /// little beyond, and never off the screen.
    var curtain: (left: Double, right: Double) {
        let half = halfEdge + IslandLaserLimits.curtainBeyond
        return (left: min(half, farthest(left)), right: min(half, farthest(right)))
    }

    /// How far the wide curtain goes to each side for the lasers' reach,
    /// 0 to 1: twice the curtain at 0, and the screen's own sides at 1.
    func wide(reach: Double) -> (left: Double, right: Double) {
        let share = IslandLaserReach.clamped(reach)
        let near = curtain
        func extent(near: Double, side: Double) -> Double {
            let most = farthest(side)
            let least = min(near * IslandLaserLimits.wideStart, most)
            return least + (most - least) * share
        }
        return (left: extent(near: near.left, side: left), right: extent(near: near.right, side: right))
    }

    /// The longest a beam that points straight down may be: to the bottom
    /// of the screen.
    var longestDown: Double {
        down.isFinite ? max(down, 0) : .infinity
    }
}

/// Where one beam stands.
struct IslandLaserStand: Equatable, Sendable {
    /// Where it leaves the line of the notch's lower edge, in points from
    /// the middle of the edge. Positive is to the right.
    var start: Double
    /// How far it leans from straight down, in degrees. Positive leans to
    /// the right.
    var lean: Double
    /// Its length as a share of the full one.
    var share: Double
}

/// Every beam of one arrangement, for one count on one screen.
struct IslandLaserLineup: Equatable, Sendable {
    var stands: [IslandLaserStand]
    /// False for beams that stay side by side: they get no slow sway.
    var sways: Bool
    /// No beam is longer than this, in points.
    var longest: Double
    /// How far the beams' plane is tilted out of the screen toward the
    /// viewer, in degrees. 0 is flat.
    var tilt: Double = 0
}

/// The shape the beams make.
enum IslandLaserShape: String, Sendable {
    /// A wide fan.
    case fan
    /// Two wings, with nothing in the middle.
    case wings
    /// A comb, long and short in turn.
    case comb
    /// Beams that cross: the left ones lean right and the right ones left.
    case crossed
    /// Straight down, across the notch and a little beyond.
    case curtain
    /// A curtain that widens with the lasers' reach, up to the whole
    /// screen, longest in the middle.
    case wideCurtain
    /// Two curtains, one on each side, with the middle left empty.
    case split

    /// True for the ones whose beams come straight down, side by side.
    var isUpright: Bool {
        switch self {
        case .fan, .wings, .comb, .crossed: false
        case .curtain, .wideCurtain, .split: true
        }
    }
}

/// Which way the beams' plane faces (D56).
enum IslandLaserOrientation: Hashable, Sendable {
    /// In the screen's own plane: the beams go down and out.
    case flat
    /// Tilted out of the screen toward whoever looks at it, by this many
    /// degrees: the beams come forward as they leave the notch.
    case towardViewer(degrees: Double)

    /// Toward the viewer by the usual angle.
    static let forward = IslandLaserOrientation.towardViewer(degrees: IslandLaserTilt.standard)

    /// The tilt in degrees: 0 when flat, and held to what the perspective
    /// can show.
    var tilt: Double {
        switch self {
        case .flat: 0
        case let .towardViewer(degrees): IslandLaserTilt.held(degrees)
        }
    }
}

/// One way the beams stand (D56): a shape, and the way its plane faces.
/// The same fan can lie flat on the screen or come out of it toward the
/// viewer. A mid hit moves to the next one in `all`.
struct IslandLaserArrangement: Hashable, Sendable {
    var shape: IslandLaserShape
    var orientation = IslandLaserOrientation.flat

    static let fan = IslandLaserArrangement(shape: .fan)
    static let wings = IslandLaserArrangement(shape: .wings)
    static let comb = IslandLaserArrangement(shape: .comb)
    static let crossed = IslandLaserArrangement(shape: .crossed)
    static let curtain = IslandLaserArrangement(shape: .curtain)
    static let wideCurtain = IslandLaserArrangement(shape: .wideCurtain)
    static let split = IslandLaserArrangement(shape: .split)

    /// The same shape coming toward the viewer.
    var forward: IslandLaserArrangement {
        IslandLaserArrangement(shape: shape, orientation: .forward)
    }

    /// The arrangements a mid hit steps through, in order: the four fan
    /// shapes, each one flat and toward the viewer. Every step is a new
    /// shape and the other orientation.
    static let all: [IslandLaserArrangement] = [
        .fan, wings.forward, .comb, crossed.forward, .wings, fan.forward, .crossed, comb.forward,
    ]

    /// The ones whose beams come straight down side by side. No hit steps
    /// to them: they are kept for a show that picks its own looks.
    static let uprights: [IslandLaserArrangement] = [.curtain, .wideCurtain, .split]

    /// The arrangement at a place in `all`, around and around. Whoever
    /// picks hands the place in: nothing here rolls a number.
    static func at(_ index: Int) -> IslandLaserArrangement {
        all[((index % all.count) + all.count) % all.count]
    }

    var name: String {
        orientation == .flat ? shape.rawValue : "\(shape.rawValue)TowardViewer"
    }

    /// True for the ones whose beams come straight down, side by side.
    var isUpright: Bool { shape.isUpright }

    /// Where `count` beams stand in this arrangement. `reach` is the
    /// lasers' own, 0 to 1: it sets how wide the wide ones are.
    func lineup(count: Int, space: IslandLaserSpace, reach: Double) -> IslandLaserLineup {
        let count = max(count, 1)
        guard isUpright else {
            // A fan that faces the viewer holds still: near its middle
            // the perspective draws a lean several times over, and the
            // slow sway would throw the fan out of true.
            return IslandLaserLineup(
                stands: leaning(count: count, halfEdge: space.halfEdge), sways: orientation.tilt == 0,
                longest: .infinity, tilt: orientation.tilt
            )
        }
        return IslandLaserLineup(
            stands: standing(count: count, space: space, reach: reach), sways: false, longest: space.longestDown,
            tilt: orientation.tilt
        )
    }

    /// The four that lean out from the notch's lower edge. A place runs
    /// from -1 at the left end to 1 at the right.
    private func leaning(count: Int, halfEdge: Double) -> [IslandLaserStand] {
        let places = Self.spread(count, from: -1, to: 1)
        let out = Self.outward(places)
        switch shape {
        case .wings:
            // From 36 degrees at the inner beam to 68 at the outer one,
            // which is the longest. `far` is 0 at the inner and 1 at the
            // outer.
            func wing(_ side: Double, _ far: Double) -> IslandLaserStand {
                IslandLaserStand(
                    start: side * (0.3 + 0.6 * far) * halfEdge, lean: side * (36 + 32 * far), share: 0.84 + 0.16 * far
                )
            }
            let leftCount = count / 2
            return Self.spread(leftCount, from: 1, to: 0).map { wing(-1, $0) }
                + Self.spread(count - leftCount, from: 0, to: 1).map { wing(1, $0) }
        case .comb:
            return places.indices.map { index in
                let fromEnd = min(index, count - 1 - index)
                return IslandLaserStand(
                    start: 0.9 * places[index] * halfEdge, lean: 50 * places[index],
                    share: fromEnd.isMultiple(of: 2) ? 1 : 0.78
                )
            }
        case .crossed:
            return places.indices.map { index in
                IslandLaserStand(
                    start: 0.9 * places[index] * halfEdge, lean: -40 * places[index], share: 1 - 0.1 * out[index]
                )
            }
        case .fan:
            // 64 degrees at its ends, and a little shorter there.
            return places.indices.map { index in
                IslandLaserStand(
                    start: 0.8 * places[index] * halfEdge, lean: 64 * places[index],
                    share: 1 - 0.18 * out[index] * out[index]
                )
            }
        case .curtain, .wideCurtain, .split:
            return []
        }
    }

    /// The three that come straight down.
    private func standing(count: Int, space: IslandLaserSpace, reach: Double) -> [IslandLaserStand] {
        switch shape {
        case .wideCurtain:
            let width = space.wide(reach: reach)
            let starts = Self.spread(count, from: -width.left, to: width.right)
            let out = Self.outward(Self.spread(count, from: -1, to: 1))
            return starts.indices.map { index in
                let dip = IslandLaserLimits.wideDip * out[index] * out[index]
                return IslandLaserStand(start: starts[index], lean: 0, share: 1 - dip)
            }
        case .split:
            let width = space.wide(reach: reach)
            let gap = IslandLaserLimits.splitGap
            let leftCount = count / 2
            let starts = Self.spread(leftCount, from: -width.left, to: -width.left * gap)
                + Self.spread(count - leftCount, from: width.right * gap, to: width.right)
            return starts.map { IslandLaserStand(start: $0, lean: 0, share: 1) }
        case .curtain:
            let width = space.curtain
            return Self.spread(count, from: -width.left, to: width.right).map {
                IslandLaserStand(start: $0, lean: 0, share: 1)
            }
        case .fan, .wings, .comb, .crossed:
            return []
        }
    }

    /// How far each place is from the middle: 0 for the innermost beams
    /// and 1 for the two at the ends. A share that falls with it leaves
    /// the innermost beams at the full length, whatever the count.
    private static func outward(_ places: [Double]) -> [Double] {
        let inner = places.map { abs($0) }.min() ?? 0
        guard inner < 1 else { return places.map { _ in 0 } }
        return places.map { (abs($0) - inner) / (1 - inner) }
    }

    /// `count` numbers from one end to the other, the same distance apart.
    /// One alone sits in the middle.
    private static func spread(_ count: Int, from first: Double, to last: Double) -> [Double] {
        guard count > 1 else { return count == 1 ? [(first + last) / 2] : [] }
        return (0..<count).map { first + (last - first) * Double($0) / Double(count - 1) }
    }
}
