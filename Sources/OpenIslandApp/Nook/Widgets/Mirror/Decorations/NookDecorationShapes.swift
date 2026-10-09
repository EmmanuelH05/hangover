import SwiftUI

/// The shapes the frames and stickers are built from, in points. Angles
/// are in degrees: 0 points right, 90 points down, -90 points up.
enum NookDecorationShapes {
    private static func radians(_ degrees: CGFloat) -> CGFloat { degrees * .pi / 180 }

    static func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    /// An oval, turned about its own center.
    static func ellipse(_ center: CGPoint, width: CGFloat, height: CGFloat, turned degrees: CGFloat = 0) -> Path {
        let oval = Path(ellipseIn: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        return oval.applying(
            CGAffineTransform(translationX: center.x, y: center.y).rotated(by: radians(degrees))
        )
    }

    /// A shape turned about a point.
    static func turned(_ path: Path, _ degrees: CGFloat, about center: CGPoint) -> Path {
        path.applying(
            CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: radians(degrees))
                .translatedBy(x: -center.x, y: -center.y)
        )
    }

    /// A heart `width` wide and nine tenths as tall, around its center.
    static func heart(_ center: CGPoint, width: CGFloat) -> Path {
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: center.x + x * width, y: center.y + y * width)
        }
        var path = Path()
        path.move(to: at(0, 0.45))
        path.addCurve(to: at(-0.5, -0.12), control1: at(-0.15, 0.32), control2: at(-0.5, 0.14))
        path.addCurve(to: at(-0.24, -0.45), control1: at(-0.5, -0.36), control2: at(-0.32, -0.45))
        path.addCurve(to: at(0, -0.24), control1: at(-0.12, -0.45), control2: at(-0.03, -0.36))
        path.addCurve(to: at(0.24, -0.45), control1: at(0.03, -0.36), control2: at(0.12, -0.45))
        path.addCurve(to: at(0.5, -0.12), control1: at(0.32, -0.45), control2: at(0.5, -0.36))
        path.addCurve(to: at(0, 0.45), control1: at(0.5, 0.14), control2: at(0.15, 0.32))
        path.closeSubpath()
        return path
    }

    /// A star or a burst: `points` tips at `outer` from the center with
    /// the dips between them at `inner`. The first tip points up, then is
    /// turned by `turned`. `squash` flattens it top to bottom.
    static func star(
        _ center: CGPoint,
        outer: CGFloat,
        inner: CGFloat,
        points: Int = 5,
        turned degrees: CGFloat = 0,
        squash: CGFloat = 1
    ) -> Path {
        let count = max(3, points)
        var path = Path()
        for index in 0..<(count * 2) {
            let radius = index.isMultiple(of: 2) ? outer : inner
            let angle = radians(-90 + degrees + CGFloat(index) * 180 / CGFloat(count))
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius * squash)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    /// A four point glint with sides that curve in toward the center.
    static func sparkle(_ center: CGPoint, radius: CGFloat) -> Path {
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: center.x + x * radius, y: center.y + y * radius)
        }
        var path = Path()
        path.move(to: at(0, -1))
        path.addQuadCurve(to: at(1, 0), control: at(0.14, -0.14))
        path.addQuadCurve(to: at(0, 1), control: at(0.14, 0.14))
        path.addQuadCurve(to: at(-1, 0), control: at(-0.14, 0.14))
        path.addQuadCurve(to: at(0, -1), control: at(-0.14, -0.14))
        path.closeSubpath()
        return path
    }

    /// A raindrop: a ball with a point above it.
    static func drop(_ center: CGPoint, radius: CGFloat) -> Path {
        let tip = polygon([
            CGPoint(x: center.x - 0.9 * radius, y: center.y - 0.45 * radius),
            CGPoint(x: center.x + 0.9 * radius, y: center.y - 0.45 * radius),
            CGPoint(x: center.x, y: center.y - 2.4 * radius),
        ])
        return circle(center, radius).union(tip)
    }

    /// A moon: a disc with a smaller disc bitten out of it.
    static func crescent(_ center: CGPoint, radius: CGFloat, bite offset: CGSize, biteRadius: CGFloat) -> Path {
        circle(center, radius)
            .subtracting(circle(CGPoint(x: center.x + offset.width, y: center.y + offset.height), biteRadius))
    }

    /// Part of a circle's edge, clockwise from `start` to `end`.
    static func arc(_ center: CGPoint, radius: CGFloat, from start: CGFloat, to end: CGFloat) -> Path {
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        return path
    }

    static func polygon(_ points: [CGPoint]) -> Path {
        var path = polyline(points)
        path.closeSubpath()
        return path
    }

    static func polyline(_ points: [CGPoint]) -> Path {
        var path = Path()
        for (index, point) in points.enumerated() {
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    /// Round petals around a center.
    static func flower(_ center: CGPoint, reach: CGFloat, petals: Int = 5, petalRadius: CGFloat) -> Path {
        let count = max(3, petals)
        var path = circle(center, reach * 0.3)
        for index in 0..<count {
            let angle = radians(-90 + CGFloat(index) * 360 / CGFloat(count))
            let petal = CGPoint(
                x: center.x + cos(angle) * (reach - petalRadius),
                y: center.y + sin(angle) * (reach - petalRadius)
            )
            path = path.union(circle(petal, petalRadius))
        }
        return path
    }

    /// A leaf with a point at each end, lying across the rectangle.
    static func leaf(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.3)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.3)
        )
        path.closeSubpath()
        return path
    }
}
