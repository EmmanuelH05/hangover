import CoreGraphics
import Foundation

/// The marks a theme prints on the paper, and the small shapes the footer
/// borrows. Everything is drawn in a space measured from the page's top
/// left, which the composer sets up before calling in.
enum NookPhotoStripPatterns {
    static func draw(_ pattern: NookStripPattern, layout: NookPhotoStripLayout, context: CGContext) {
        let page = CGRect(origin: .zero, size: layout.pageSize)
        switch pattern {
        case let .grid(color, spacing, line):
            guard spacing > 0 else { return }
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(line)
            for x in stride(from: spacing, to: page.width, by: spacing) {
                context.move(to: CGPoint(x: x, y: 0))
                context.addLine(to: CGPoint(x: x, y: page.height))
            }
            for y in stride(from: spacing, to: page.height, by: spacing) {
                context.move(to: CGPoint(x: 0, y: y))
                context.addLine(to: CGPoint(x: page.width, y: y))
            }
            context.strokePath()

        case let .gingham(color, band, period):
            guard period > 0 else { return }
            context.setFillColor(color.cgColor)
            // Two fills, which lets the crossings read darker.
            for y in stride(from: CGFloat(0), to: page.height, by: period) {
                context.addRect(CGRect(x: 0, y: y, width: page.width, height: band))
            }
            context.fillPath()
            for x in stride(from: CGFloat(0), to: page.width, by: period) {
                context.addRect(CGRect(x: x, y: 0, width: band, height: page.height))
            }
            context.fillPath()

        case let .pinstripes(color, width, period, start):
            guard period > 0 else { return }
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(width)
            for x in stride(from: start, to: page.width, by: period) {
                context.move(to: CGPoint(x: x, y: 0))
                context.addLine(to: CGPoint(x: x, y: page.height))
            }
            context.strokePath()

        case let .ruled(color, period, margin, marginX):
            guard period > 0 else { return }
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(0.5)
            for y in stride(from: period, to: page.height, by: period) {
                context.move(to: CGPoint(x: 0, y: y))
                context.addLine(to: CGPoint(x: page.width, y: y))
            }
            context.strokePath()
            context.setStrokeColor(margin.cgColor)
            context.setLineWidth(0.75)
            context.move(to: CGPoint(x: marginX, y: 0))
            context.addLine(to: CGPoint(x: marginX, y: page.height))
            context.strokePath()

        case let .halftone(color, radius, pitch):
            guard pitch > 0 else { return }
            context.setFillColor(color.cgColor)
            var row = 0
            for y in stride(from: pitch / 2, to: page.height, by: pitch) {
                let shift = row % 2 == 0 ? 0 : pitch / 2
                for x in stride(from: pitch / 2 + shift, to: page.width, by: pitch) {
                    context.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius))
                }
                row += 1
            }
            context.fillPath()

        case let .sprockets(color):
            drawSprockets(color, page: page, context: context)

        case let .glints(color):
            context.setFillColor(color.cgColor)
            for glint in glintSpots(layout) {
                context.addPath(sparkle(center: glint.center, radius: glint.radius))
            }
            context.fillPath()

        case let .confetti(colors, count, seed):
            guard !colors.isEmpty else { return }
            var random = NookStripRandom(seed: seed)
            for _ in 0..<count {
                let point = CGPoint(x: random.unit() * page.width, y: random.unit() * page.height)
                let color = colors[Int(random.unit() * CGFloat(colors.count)) % colors.count]
                let turn = random.unit() * .pi
                context.saveGState()
                context.translateBy(x: point.x, y: point.y)
                context.rotate(by: turn)
                context.setFillColor(color.cgColor)
                switch Int(random.unit() * 3) {
                case 0: context.fill(CGRect(x: -1.6, y: -0.8, width: 3.2, height: 1.6))
                case 1: context.fillEllipse(in: CGRect(x: -1.1, y: -1.1, width: 2.2, height: 2.2))
                default: context.fill(CGRect(x: -1.2, y: -1.2, width: 2.4, height: 2.4))
                }
                context.restoreGState()
            }

        case let .sparkles(color, count, seed):
            var random = NookStripRandom(seed: seed)
            for _ in 0..<count {
                let center = CGPoint(x: random.unit() * page.width, y: random.unit() * page.height)
                let radius = 1.2 + random.unit() * 2.6
                context.setFillColor(color.opacity(color.alpha * Double(0.45 + random.unit() * 0.55)).cgColor)
                context.addPath(sparkle(center: center, radius: radius))
                context.fillPath()
            }

        case let .vignette(color):
            let clear = color.opacity(0)
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let gradient = CGGradient(
                      colorsSpace: space,
                      colors: [clear.cgColor, color.cgColor] as CFArray,
                      locations: [0, 1]
                  ) else { return }
            let center = CGPoint(x: page.midX, y: page.midY)
            let reach = (page.width * page.width + page.height * page.height).squareRoot() / 2
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: reach, options: [])
        }
    }

    /// Where the glints go: two in the footer when it has room, and a
    /// small one in every gap between two pictures, swapping sides as it
    /// goes down the page.
    static func glintSpots(_ layout: NookPhotoStripLayout) -> [(center: CGPoint, radius: CGFloat)] {
        var spots: [(center: CGPoint, radius: CGFloat)] = []
        // A one-line footer has no corner to spare.
        if layout.footer.height >= 30 {
            spots.append((CGPoint(x: layout.footer.minX + 8, y: layout.footer.minY + 9), 5))
            spots.append((CGPoint(x: layout.footer.maxX - 8, y: layout.footer.maxY - 8), 3))
        }
        var flips = false
        for (index, slot) in layout.slots.enumerated() {
            for other in layout.slots.dropFirst(index + 1) {
                let stacked = abs(slot.minX - other.minX) < 0.5 && other.minY > slot.maxY && other.minY - slot.maxY < 20
                let beside = abs(slot.minY - other.minY) < 0.5 && other.minX > slot.maxX && other.minX - slot.maxX < 20
                if stacked {
                    let x = flips ? slot.maxX - 10 : slot.minX + 10
                    spots.append((CGPoint(x: x, y: (slot.maxY + other.minY) / 2), 2.5))
                    flips.toggle()
                } else if beside {
                    let y = flips ? slot.maxY - 10 : slot.minY + 10
                    spots.append((CGPoint(x: (slot.maxX + other.minX) / 2, y: y), 2.5))
                    flips.toggle()
                }
            }
        }
        return spots
    }

    /// Film holes run down the two long edges of the page, whichever way
    /// it is turned.
    private static func drawSprockets(_ color: NookStripColor, page: CGRect, context: CGContext) {
        let long: CGFloat = 5.5
        let short: CGFloat = 4
        let inset: CGFloat = 4.5
        let pitch: CGFloat = 12
        context.setFillColor(color.cgColor)
        if page.height >= page.width {
            for y in stride(from: CGFloat(10), to: page.height - long, by: pitch) {
                for x in [inset, page.width - inset] {
                    let hole = CGRect(x: x - short / 2, y: y, width: short, height: long)
                    context.addPath(CGPath(roundedRect: hole, cornerWidth: 1, cornerHeight: 1, transform: nil))
                }
            }
        } else {
            for x in stride(from: CGFloat(10), to: page.width - long, by: pitch) {
                for y in [inset, page.height - inset] {
                    let hole = CGRect(x: x, y: y - short / 2, width: long, height: short)
                    context.addPath(CGPath(roundedRect: hole, cornerWidth: 1, cornerHeight: 1, transform: nil))
                }
            }
        }
        context.fillPath()
    }

    // MARK: - Small shapes

    /// A four-point glint.
    static func sparkle(center: CGPoint, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: center.x + x * radius, y: center.y + y * radius)
        }
        path.move(to: point(0, -1))
        path.addQuadCurve(to: point(1, 0), control: point(0.14, -0.14))
        path.addQuadCurve(to: point(0, 1), control: point(0.14, 0.14))
        path.addQuadCurve(to: point(-1, 0), control: point(-0.14, 0.14))
        path.addQuadCurve(to: point(0, -1), control: point(-0.14, -0.14))
        path.closeSubpath()
        return path
    }

    /// A heart `width` points across, centered where asked.
    static func heart(center: CGPoint, width: CGFloat) -> CGPath {
        let path = CGMutablePath()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: center.x + x * width, y: center.y + y * width)
        }
        path.move(to: point(0, 0.45))
        path.addCurve(to: point(-0.50, -0.12), control1: point(-0.15, 0.32), control2: point(-0.50, 0.14))
        path.addCurve(to: point(-0.24, -0.45), control1: point(-0.50, -0.36), control2: point(-0.32, -0.45))
        path.addCurve(to: point(0, -0.24), control1: point(-0.12, -0.45), control2: point(-0.03, -0.36))
        path.addCurve(to: point(0.24, -0.45), control1: point(0.03, -0.36), control2: point(0.12, -0.45))
        path.addCurve(to: point(0.50, -0.12), control1: point(0.32, -0.45), control2: point(0.50, -0.36))
        path.addCurve(to: point(0, 0.45), control1: point(0.50, 0.14), control2: point(0.15, 0.32))
        path.closeSubpath()
        return path
    }

    /// A ribbon bow `width` points across with its knot at `knot`: two
    /// tails, two loops and the knot over them.
    static func drawBow(
        knot: CGPoint,
        width: CGFloat,
        fill: NookStripColor,
        accent: NookStripColor,
        ink: NookStripColor,
        context: CGContext
    ) {
        func point(_ x: CGFloat, _ y: CGFloat, mirrored: Bool) -> CGPoint {
            CGPoint(x: knot.x + (mirrored ? -x : x) * width, y: knot.y + y * width)
        }
        context.setStrokeColor(ink.cgColor)
        context.setLineWidth(max(0.3, width * 0.035))
        context.setLineJoin(.round)
        for mirrored in [false, true] {
            // Tail.
            context.setFillColor(accent.cgColor)
            context.move(to: point(-0.05, 0.04, mirrored: mirrored))
            context.addLine(to: point(-0.26, 0.38, mirrored: mirrored))
            context.addLine(to: point(-0.15, 0.36, mirrored: mirrored))
            context.addLine(to: point(-0.10, 0.46, mirrored: mirrored))
            context.addLine(to: point(0.03, 0.10, mirrored: mirrored))
            context.closePath()
            context.drawPath(using: .fillStroke)
        }
        for mirrored in [false, true] {
            // Loop.
            context.setFillColor(fill.cgColor)
            context.move(to: point(0, 0, mirrored: mirrored))
            context.addCurve(
                to: point(-0.36, -0.15, mirrored: mirrored),
                control1: point(-0.09, -0.13, mirrored: mirrored),
                control2: point(-0.27, -0.22, mirrored: mirrored)
            )
            context.addCurve(
                to: point(-0.36, 0.15, mirrored: mirrored),
                control1: point(-0.42, -0.09, mirrored: mirrored),
                control2: point(-0.42, 0.09, mirrored: mirrored)
            )
            context.addCurve(
                to: point(0, 0, mirrored: mirrored),
                control1: point(-0.27, 0.22, mirrored: mirrored),
                control2: point(-0.09, 0.13, mirrored: mirrored)
            )
            context.closePath()
            context.drawPath(using: .fillStroke)
        }
        let knotBox = CGRect(x: knot.x - 0.07 * width, y: knot.y - 0.09 * width, width: 0.14 * width, height: 0.18 * width)
        context.setFillColor(accent.cgColor)
        context.addPath(CGPath(roundedRect: knotBox, cornerWidth: 0.05 * width, cornerHeight: 0.05 * width, transform: nil))
        context.drawPath(using: .fillStroke)
    }
}

/// A small repeatable source of numbers, which makes a scattered pattern
/// print the same way every time.
struct NookStripRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    private mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    /// From 0 up to, never reaching, 1.
    mutating func unit() -> CGFloat {
        CGFloat(next() >> 11) / CGFloat(1 << 53)
    }
}
