import CoreGraphics
import Foundation

/// The motion of the drawn pointer (D65), as plain math. A glide follows a
/// gentle curve, the way a wrist moves a mouse, and keeps a person's pace:
/// quick off the mark, slowing as it lands. Its length in time grows with
/// the distance, from 0.35 seconds for a short hop to 0.9 for the width of
/// a screen.
enum DemoGlide {
    static let shortest: TimeInterval = 0.35
    static let longest: TimeInterval = 0.9
    /// The distance, in points, at which a glide takes its longest.
    static let farDistance: CGFloat = 1400
    /// How far the curve leans off the straight line, as a share of the
    /// distance. It always leans to the same side.
    static let bend: CGFloat = 0.1
    /// How many points a drawn glide is cut into.
    static let frameCount = 40

    // MARK: Time

    static func duration(from start: CGPoint, to end: CGPoint) -> TimeInterval {
        duration(distance: distance(start, end))
    }

    static func duration(distance: CGFloat) -> TimeInterval {
        let share = min(1, (max(0, distance) / farDistance).squareRoot())
        return shortest + (longest - shortest) * Double(share)
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }

    /// How far along the path the pointer is at `time`, both from 0 to 1.
    /// The minimum jerk curve, which is how a hand reaches for something.
    static func progress(at time: Double) -> Double {
        let t = min(1, max(0, time))
        return t * t * t * (10 - 15 * t + 6 * t * t)
    }

    // MARK: Path

    /// The control point of the curve: off the middle of the straight line,
    /// square to it, by `bend` of the distance.
    static func control(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return CGPoint(x: (start.x + end.x) / 2 - dy * bend, y: (start.y + end.y) / 2 + dx * bend)
    }

    /// The point on the curve at `share` of the way, from 0 to 1.
    static func point(along share: Double, from start: CGPoint, to end: CGPoint) -> CGPoint {
        let s = CGFloat(min(1, max(0, share)))
        let c = control(from: start, to: end)
        let a = (1 - s) * (1 - s)
        let b = 2 * (1 - s) * s
        let d = s * s
        return CGPoint(x: a * start.x + b * c.x + d * end.x, y: a * start.y + b * c.y + d * end.y)
    }

    /// Where the pointer is at `time` of the glide, from 0 to 1.
    static func position(at time: Double, from start: CGPoint, to end: CGPoint) -> CGPoint {
        point(along: progress(at: time), from: start, to: end)
    }

    /// The glide cut into evenly timed points, first and last included,
    /// which is what the drawing plays.
    static func frames(from start: CGPoint, to end: CGPoint, count: Int = frameCount) -> [CGPoint] {
        let steps = max(1, count)
        return (0...steps).map { position(at: Double($0) / Double(steps), from: start, to: end) }
    }

    // MARK: Leaving the island

    /// How far below the open island, and to its side, the pointer goes
    /// when the island closes.
    static let leaveDrop: CGFloat = 90
    static let leaveSide: CGFloat = 140
    /// The pointer stays this far inside the screen's edges.
    static let screenMargin: CGFloat = 40

    /// Where the pointer goes to let the island close: down past the
    /// island's bottom edge and a little to the side, inside the screen.
    static func leavePoint(from start: CGPoint, island: CGRect, screen: CGRect) -> CGPoint {
        let inside = screen.insetBy(dx: screenMargin, dy: screenMargin)
        let point = CGPoint(x: start.x + leaveSide, y: island.minY - leaveDrop)
        return CGPoint(x: min(max(point.x, inside.minX), inside.maxX), y: min(max(point.y, inside.minY), inside.maxY))
    }

    // MARK: A click

    /// The rest on the control before the button goes down.
    static let settle: TimeInterval = 0.08
    /// The button down, then up.
    static let pressDown: TimeInterval = 0.07
    static let pressUp: TimeInterval = 0.09
    /// The long press that begins edit mode, which asks for 0.4 seconds.
    static let hold: TimeInterval = 0.5
    /// The rest on the closed island before it opens.
    static let hover: TimeInterval = 0.15
    /// How long the ring of a click takes to fade.
    static let ringFade: TimeInterval = 0.4

    /// The time from the pointer leaving to the door, for each gesture,
    /// on a glide of `glide` seconds.
    static func lead(for gesture: DemoGesture, glide: TimeInterval) -> TimeInterval {
        switch gesture {
        case .none: 0
        case .click: glide + settle + pressDown + pressUp
        case .hold: glide + settle + hold
        case .enter: glide + hover
        case .leave: glide
        }
    }
}
