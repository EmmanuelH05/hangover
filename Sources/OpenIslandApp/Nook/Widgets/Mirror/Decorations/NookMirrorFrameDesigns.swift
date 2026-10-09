import SwiftUI

/// The frames, in picker order. Sizes are in units: one hundredth of the
/// picture's height (of its shorter side, to be exact), which keeps circles
/// round and lines the same thickness on every edge. No frame reaches more
/// than `deepestReach` units in from the edge, which leaves the middle of
/// the picture clear for a face.
///
/// A frame has no clock: nothing in it blinks or breathes. The words some
/// of them carry are part of the drawing and are not translated.
enum NookMirrorFrameDesigns {
    /// The deepest any frame may reach in from the edge, in units.
    static let deepestReach: CGFloat = 15

    static let all: [NookMirrorFrameDesign] = [
        NookMirrorFrameDesign(id: "frame.hairline", nameKey: "nook.mirror.frame.hairline", draw: hairline),
        NookMirrorFrameDesign(id: "frame.instant", nameKey: "nook.mirror.frame.instant", draw: instantPrint),
        NookMirrorFrameDesign(id: "frame.film", nameKey: "nook.mirror.frame.film", draw: filmRoll),
        NookMirrorFrameDesign(id: "frame.vanity", nameKey: "nook.mirror.frame.vanity", draw: vanityBulbs),
        NookMirrorFrameDesign(id: "frame.ribbon", nameKey: "nook.mirror.frame.ribbon", draw: ribbonBow),
        NookMirrorFrameDesign(id: "frame.arcade", nameKey: "nook.mirror.frame.arcade", draw: arcadeHUD),
        NookMirrorFrameDesign(id: "frame.doodle", nameKey: "nook.mirror.frame.doodle", draw: doodleMarker),
        NookMirrorFrameDesign(id: "frame.terminal", nameKey: "nook.mirror.frame.terminal", draw: terminalWindow),
        NookMirrorFrameDesign(id: "frame.lace", nameKey: "nook.mirror.frame.lace", draw: scallopLace),
        NookMirrorFrameDesign(id: "frame.chrome", nameKey: "nook.mirror.frame.chrome", draw: chromeSparkle),
        NookMirrorFrameDesign(id: "frame.checker", nameKey: "nook.mirror.frame.checker", draw: checkerEdge),
        NookMirrorFrameDesign(id: "frame.clouds", nameKey: "nook.mirror.frame.clouds", draw: cloudNine),
        NookMirrorFrameDesign(id: "frame.hearts", nameKey: "nook.mirror.frame.hearts", draw: heartGarland),
        NookMirrorFrameDesign(id: "frame.neon", nameKey: "nook.mirror.frame.neon", draw: neonTubes),
        NookMirrorFrameDesign(id: "frame.garden", nameKey: "nook.mirror.frame.garden", draw: daisyPatch),
        NookMirrorFrameDesign(id: "frame.rainbow", nameKey: "nook.mirror.frame.rainbow", draw: rainbowBands),
    ]

    // MARK: Places on the picture

    private typealias Shapes = NookDecorationShapes

    /// Places measured in units from the picture's edges.
    private struct Edges {
        let pen: NookDecorationPen

        var unit: CGFloat { pen.unit }
        var left: CGFloat { pen.rect.minX }
        var right: CGFloat { pen.rect.maxX }
        var top: CGFloat { pen.rect.minY }
        var bottom: CGFloat { pen.rect.maxY }
        var middleX: CGFloat { pen.rect.midX }

        /// `x` units from the left, `y` units from the top.
        func topLeft(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: left + x * unit, y: top + y * unit) }
        func topRight(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: right - x * unit, y: top + y * unit) }
        func bottomLeft(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: left + x * unit, y: bottom - y * unit) }
        func bottomRight(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: right - x * unit, y: bottom - y * unit) }
        func topMiddle(_ y: CGFloat) -> CGPoint { CGPoint(x: middleX, y: top + y * unit) }
        func bottomMiddle(_ y: CGFloat) -> CGPoint { CGPoint(x: middleX, y: bottom - y * unit) }

        /// The same spot in each corner, `x` and `y` units in, with the way
        /// the corner faces on each axis.
        func corners(_ x: CGFloat, _ y: CGFloat) -> [(point: CGPoint, x: CGFloat, y: CGFloat)] {
            [(topLeft(x, y), 1, 1), (topRight(x, y), -1, 1), (bottomRight(x, y), -1, -1), (bottomLeft(x, y), 1, -1)]
        }

        /// The picture's rectangle pulled in by `inset` units on every side.
        func inset(_ inset: CGFloat) -> CGRect {
            pen.rect.insetBy(dx: inset * unit, dy: inset * unit)
        }

        func outline(inset amount: CGFloat, radius: CGFloat) -> Path {
            Path(roundedRect: inset(amount), cornerRadius: radius * unit)
        }

        /// Everything between the picture's edge and a window in it.
        func border(around window: Path) -> Path {
            Path(pen.rect).subtracting(window)
        }

        /// Points about `spacing` units apart on a line `inset` units in
        /// from the edge, all the way around, starting at the top left.
        func ring(inset amount: CGFloat, spacing: CGFloat) -> [CGPoint] {
            let line = inset(amount)
            guard line.width > 0, line.height > 0, spacing > 0 else { return [] }
            let across = max(1, Int((line.width / (spacing * unit)).rounded()))
            let down = max(1, Int((line.height / (spacing * unit)).rounded()))
            var points: [CGPoint] = []
            for index in 0..<across {
                points.append(CGPoint(x: line.minX + line.width * CGFloat(index) / CGFloat(across), y: line.minY))
            }
            for index in 0..<down {
                points.append(CGPoint(x: line.maxX, y: line.minY + line.height * CGFloat(index) / CGFloat(down)))
            }
            for index in 0..<across {
                points.append(CGPoint(x: line.maxX - line.width * CGFloat(index) / CGFloat(across), y: line.maxY))
            }
            for index in 0..<down {
                points.append(CGPoint(x: line.minX, y: line.maxY - line.height * CGFloat(index) / CGFloat(down)))
            }
            return points
        }
    }

    // MARK: Frames from the design catalog

    /// Quiet and gallery clean: two thin lines and a plus mark in each corner.
    private static func hairline(_ pen: NookDecorationPen) {
        let edges = Edges(pen: pen)
        pen.stroke(edges.outline(inset: 3, radius: 3), .white.opacity(0.85), width: 0.5)
        pen.stroke(edges.outline(inset: 5, radius: 2), .white.opacity(0.35), width: 0.25)
        let half = 1.5 * pen.unit
        for corner in edges.corners(9, 9) {
            var mark = Path()
            mark.move(to: CGPoint(x: corner.point.x - half, y: corner.point.y))
            mark.addLine(to: CGPoint(x: corner.point.x + half, y: corner.point.y))
            mark.move(to: CGPoint(x: corner.point.x, y: corner.point.y - half))
            mark.addLine(to: CGPoint(x: corner.point.x, y: corner.point.y + half))
            pen.stroke(mark, .white.opacity(0.7), width: 0.4, cap: .butt)
        }
    }

    /// A snapshot with a fat white border and today's date written under it.
    private static func instantPrint(_ pen: NookDecorationPen) {
        let unit = pen.unit
        let window = Path(
            roundedRect: CGRect(
                x: pen.rect.minX + 5 * unit,
                y: pen.rect.minY + 5 * unit,
                width: pen.width - 10 * unit,
                height: pen.height - 19 * unit
            ),
            cornerRadius: unit
        )
        let edges = Edges(pen: pen)
        pen.fill(edges.border(around: window), .decoration(0xF7F4EC))
        pen.stroke(window, .black.opacity(0.15), width: 0.25)
        pen.text(pen.note, at: edges.bottomMiddle(7), size: 6, font: .hand, color: .decoration(0x2B2B2B).opacity(0.85))
    }

    /// A strip of camera film: black bars with holes and edge print.
    private static func filmRoll(_ pen: NookDecorationPen) {
        let unit = pen.unit
        let edges = Edges(pen: pen)
        let bar = 11 * unit
        pen.fill(Path(CGRect(x: edges.left, y: edges.top, width: pen.width, height: bar)), .decoration(0x0A0A0A))
        pen.fill(Path(CGRect(x: edges.left, y: edges.bottom - bar, width: pen.width, height: bar)), .decoration(0x0A0A0A))
        let holes = 20
        for index in 0..<holes {
            let x = edges.left + (CGFloat(index) + 0.5) * pen.width / CGFloat(holes)
            for y in [edges.top + 3.5 * unit, edges.bottom - 3.5 * unit] {
                let hole = CGRect(x: x - 2.5 * unit, y: y - 1.75 * unit, width: 5 * unit, height: 3.5 * unit)
                pen.fill(Path(roundedRect: hole, cornerRadius: 0.8 * unit), .decoration(0xEDEAE0).opacity(0.92))
            }
        }
        let print = Color.decoration(0xFFB020)
        let lines: [(y: CGFloat, left: String, middle: String, right: String, fromTop: Bool)] = [
            (8.4, "MIRROR 400", "12", "12A", true),
            (8.4, "NOTCH PAN 16:9", "13", "13A", false),
        ]
        for line in lines {
            let y = line.fromTop ? edges.top + line.y * unit : edges.bottom - line.y * unit
            pen.text(line.left, at: CGPoint(x: edges.left + 4 * unit, y: y), size: 2.6, font: .mono(bold: true), color: print, anchor: .leading)
            pen.text(line.middle, at: CGPoint(x: edges.middleX, y: y), size: 2.6, font: .mono(bold: true), color: print)
            pen.text(line.right, at: CGPoint(x: edges.right - 4 * unit, y: y), size: 2.6, font: .mono(bold: true), color: print, anchor: .trailing)
        }
    }

    /// A dressing room mirror ringed with warm bulbs.
    private static func vanityBulbs(_ pen: NookDecorationPen) {
        let unit = pen.unit
        let edges = Edges(pen: pen)
        let window = edges.outline(inset: 9, radius: 2.5)
        pen.fill(edges.border(around: window), .decoration(0x141416).opacity(0.88))
        pen.stroke(window, .decoration(0xFFE9B8).opacity(0.6), width: 0.4)
        var bulbs: [CGPoint] = []
        for index in 0..<14 {
            let x = edges.left + (CGFloat(index) + 0.5) * pen.width / 14
            bulbs.append(CGPoint(x: x, y: edges.top + 4.5 * unit))
            bulbs.append(CGPoint(x: x, y: edges.bottom - 4.5 * unit))
        }
        for index in 0..<6 {
            let y = edges.top + pen.height * CGFloat(index + 1) / 7
            bulbs.append(CGPoint(x: edges.left + 4.5 * unit, y: y))
            bulbs.append(CGPoint(x: edges.right - 4.5 * unit, y: y))
        }
        for bulb in bulbs {
            pen.fill(Shapes.circle(bulb, 4.2 * unit), .decoration(0xFFD27A).opacity(0.28))
            let glass = Shapes.circle(bulb, 2.6 * unit)
            pen.context.fill(
                glass,
                with: .radialGradient(
                    Gradient(colors: [.white, .decoration(0xFFE9B8)]),
                    center: bulb,
                    startRadius: 0,
                    endRadius: 2.6 * unit
                )
            )
            pen.stroke(glass, .decoration(0xC9A45C).opacity(0.8), width: 0.25)
        }
    }

    /// Soft pink ribbon and pearls, tied in a bow at the top.
    private static func ribbonBow(_ pen: NookDecorationPen) {
        let unit = pen.unit
        let edges = Edges(pen: pen)
        let ink = Color.decoration(0xE0608F)
        pen.stroke(edges.outline(inset: 2.5, radius: 4), .decoration(0xFFC2D9), width: 1.2)
        pen.stroke(edges.outline(inset: 5.5, radius: 3), .white.opacity(0.92), width: 0.9, dash: [0.01, 2.4])
        // The knot sits a little higher than a bow would hang, which keeps
        // the tail tips out of the picture's middle.
        let knot = edges.topMiddle(7)
        for side in [CGFloat(1), -1] {
            func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: knot.x + side * x * unit, y: knot.y + y * unit)
            }
            let tail = Shapes.polygon([at(-0.8, 0.2), at(-7.8, 4.7), at(-5.7, 5.2), at(-6.2, 7.3), at(0.8, 2.8)])
            pen.fill(tail, .decoration(0xFF6FA3))
            pen.stroke(tail, ink, width: 0.5)
        }
        for side in [CGFloat(1), -1] {
            func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: knot.x + side * x * unit, y: knot.y + y * unit)
            }
            var loop = Path()
            loop.move(to: at(0, 0))
            loop.addCurve(to: at(-13, -5), control1: at(-4, -6), control2: at(-10, -8))
            loop.addCurve(to: at(-13, 5), control1: at(-15.5, -2), control2: at(-15.5, 2))
            loop.addCurve(to: at(0, 0), control1: at(-10, 8), control2: at(-4, 6))
            loop.closeSubpath()
            pen.fill(loop, .decoration(0xFF8FB8))
            pen.stroke(loop, ink, width: 0.5)
        }
        let tie = Path(
            roundedRect: CGRect(x: knot.x - 2 * unit, y: knot.y - 2.5 * unit, width: 4 * unit, height: 5 * unit),
            cornerRadius: 1.5 * unit
        )
        pen.fill(tie, .decoration(0xFF6FA3))
        pen.stroke(tie, ink, width: 0.5)
        pen.fill(Shapes.heart(edges.bottomLeft(9, 9), width: 5 * unit), .decoration(0xFF8FB8))
        pen.fill(Shapes.heart(edges.bottomRight(9, 9), width: 5 * unit), .decoration(0xFF8FB8))
    }

    /// An old arcade screen with a score line and a prompt.
    private static func arcadeHUD(_ pen: NookDecorationPen) {
        let unit = pen.unit
        let edges = Edges(pen: pen)
        let cyan = Color.decoration(0x19E3FF)
        let pink = Color.decoration(0xFF4FA3)
        let yellow = Color.decoration(0xFFE600)
        pen.stroke(Path(edges.inset(1.5)), cyan, width: 1, cap: .square)
        pen.stroke(Path(edges.inset(4)), pink, width: 0.5, cap: .square)
        let side = 2.5 * unit
        for corner in edges.corners(6, 6) {
            for step in [(CGFloat(0), CGFloat(0)), (1, 0), (0, 1)] {
                // Each square grows away from its corner.
                let x = corner.point.x + corner.x * step.0 * side - (corner.x < 0 ? side : 0)
                let y = corner.point.y + corner.y * step.1 * side - (corner.y < 0 ? side : 0)
                pen.fill(Path(CGRect(x: x, y: y, width: side, height: side)), yellow)
            }
        }
        let score = edges.top + 9 * unit
        let player = pen.text(
            "P1 ", at: CGPoint(x: edges.left + 14 * unit, y: score), size: 4, font: .mono(bold: true), color: cyan, anchor: .leading
        )
        pen.text(
            "004200", at: CGPoint(x: edges.left + 14 * unit + player.width, y: score),
            size: 4, font: .mono(bold: true), color: .white, anchor: .leading
        )
        pen.text("HI 999990", at: CGPoint(x: edges.middleX, y: score), size: 4, font: .mono(bold: true), color: .white)
        pen.text(
            "LV 04", at: CGPoint(x: edges.right - 14 * unit, y: score), size: 4, font: .mono(bold: true), color: pink, anchor: .trailing
        )
        pen.text("PRESS START", at: edges.bottomMiddle(9), size: 4, font: .mono(bold: true), color: yellow)
    }

    /// Drawn on the screen with paint markers, a little wobbly on purpose.
    private static func doodleMarker(_ pen: NookDecorationPen) {
        let unit = pen.unit
        let edges = Edges(pen: pen)
        let yellow = Color.decoration(0xFFE94A)
        let pink = Color.decoration(0xFF7AC6)
        let center = CGPoint(x: pen.rect.midX, y: pen.rect.midY)
        pen.stroke(edges.outline(inset: 3, radius: 5), .white, width: 1)
        pen.stroke(Shapes.turned(edges.outline(inset: 4.4, radius: 5.5), 0.5, about: center), yellow, width: 0.6)
        pen.stroke(
            Shapes.star(edges.topLeft(11, 10.5), outer: 4 * unit, inner: 1.7 * unit, turned: -12), yellow, width: 0.8
        )
        var squiggle = Path()
        squiggle.move(to: edges.topRight(25, 10))
        for segment in 0..<8 {
            let end = edges.topRight(25 - CGFloat(segment + 1) * 2, 10)
            let control = edges.topRight(25 - CGFloat(segment) * 2 - 1, segment.isMultiple(of: 2) ? 7 : 13)
            squiggle.addQuadCurve(to: end, control: control)
        }
        pen.stroke(squiggle, .decoration(0x5CC8FF), width: 0.8)
        let spark = edges.bottomLeft(10, 10)
        var burst = Path()
        for degrees in [CGFloat(-90), -18, 54, 126, 198] {
            let angle = degrees * .pi / 180
            burst.move(to: CGPoint(x: spark.x + cos(angle) * 2 * unit, y: spark.y + sin(angle) * 2 * unit))
            burst.addLine(to: CGPoint(x: spark.x + cos(angle) * 4.5 * unit, y: spark.y + sin(angle) * 4.5 * unit))
        }
        pen.stroke(burst, pink, width: 0.8)
        let heartCenter = edges.bottomRight(11, 10)
        pen.stroke(Shapes.turned(Shapes.heart(heartCenter, width: 7 * unit), 10, about: heartCenter), pink, width: 0.8)
    }

    /// Your face in a terminal window.
    private static func terminalWindow(_ pen: NookDecorationPen) {
        let unit = pen.unit
        let edges = Edges(pen: pen)
        let chrome = Color.decoration(0x1B1B1F).opacity(0.92)
        let green = Color.decoration(0x4DFF7A)
        pen.fill(Path(CGRect(x: edges.left, y: edges.top, width: pen.width, height: 9 * unit)), chrome)
        var rule = Path()
        rule.move(to: CGPoint(x: edges.left, y: edges.top + 9 * unit))
        rule.addLine(to: CGPoint(x: edges.right, y: edges.top + 9 * unit))
        pen.stroke(rule, .white.opacity(0.1), width: 0.25, cap: .butt)
        for x in [CGFloat(6), 11, 16] {
            pen.stroke(Shapes.circle(edges.topLeft(x, 4.5), 1.4 * unit), .white.opacity(0.55), width: 0.4)
        }
        pen.text("~/mirror", at: edges.topMiddle(4.5), size: 3.2, font: .mono(bold: false), color: .white.opacity(0.7))
        pen.fill(Path(CGRect(x: edges.left, y: edges.bottom - 8 * unit, width: pen.width, height: 8 * unit)), chrome)
        let prompt = edges.bottomLeft(5, 4)
        let typed = pen.text("$ say cheese", at: prompt, size: 3.2, font: .mono(bold: true), color: green, anchor: .leading)
        if typed.width > 0 {
            let cursor = CGRect(x: prompt.x + typed.width + unit, y: prompt.y - 1.8 * unit, width: 1.8 * unit, height: 3.6 * unit)
            pen.fill(Path(cursor), green)
        }
        pen.text(
            "cam 0  16:9  ready", at: edges.bottomRight(5, 4), size: 2.8, font: .mono(bold: false),
            color: .white.opacity(0.45), anchor: .trailing
        )
        pen.stroke(edges.outline(inset: 0.25, radius: 4), .decoration(0x3A3A40), width: 0.5)
    }

    /// A lace doily edge: half circles with an eyelet in each and a stitch line.
    private static func scallopLace(_ pen: NookDecorationPen) {
        let unit = pen.unit
        let edges = Edges(pen: pen)
        let inside = pen.clipped(to: Path(pen.rect))
        let lace = Color.decoration(0xFFF5FA)
        let pink = Color.decoration(0xFF9CC8)
        let across = 22
        let down = 12
        for index in 0..<across {
            let x = edges.left + (CGFloat(index) + 0.5) * pen.width / CGFloat(across)
            for (y, inward) in [(edges.top, CGFloat(1)), (edges.bottom, -1)] {
                inside.fill(Shapes.circle(CGPoint(x: x, y: y), pen.width / CGFloat(across * 2)), lace)
                inside.fill(Shapes.circle(CGPoint(x: x, y: y + inward * 1.9 * unit), 0.7 * unit), pink)
            }
        }
        for index in 0..<down {
            let y = edges.top + (CGFloat(index) + 0.5) * pen.height / CGFloat(down)
            for (x, inward) in [(edges.left, CGFloat(1)), (edges.right, -1)] {
                inside.fill(Shapes.circle(CGPoint(x: x, y: y), pen.height / CGFloat(down * 2)), lace)
                inside.fill(Shapes.circle(CGPoint(x: x + inward * 1.9 * unit, y: y), 0.7 * unit), pink)
            }
        }
        pen.stroke(edges.outline(inset: 6.2, radius: 3), pink.opacity(0.85), width: 0.4, dash: [1.2, 1.2], cap: .butt)
    }

    /// Turn of the millennium shine: a pastel chrome band with glints.
    private static func chromeSparkle(_ pen: NookDecorationPen) {
        let unit = pen.unit
        let edges = Edges(pen: pen)
        let lilac = Color.decoration(0xC9B8FF)
        let chrome = Gradient(stops: [
            .init(color: .decoration(0xB8F1FF), location: 0),
            .init(color: lilac, location: 0.35),
            .init(color: .decoration(0xFFB8E6), location: 0.7),
            .init(color: .decoration(0xFFF3B8), location: 1),
        ])
        pen.stroke(
            edges.outline(inset: 2.5, radius: 4),
            gradient: chrome,
            from: CGPoint(x: edges.left, y: edges.top),
            to: CGPoint(x: edges.right, y: edges.bottom),
            width: 3
        )
        pen.stroke(edges.outline(inset: 1.4, radius: 4.6), .white.opacity(0.85), width: 0.4)
        let glints: [(CGPoint, CGFloat)] = [
            (edges.topLeft(10, 9.5), 5), (edges.topLeft(19, 5.5), 2.2), (edges.topRight(8, 8), 3),
            (edges.bottomRight(10, 9.5), 5), (edges.bottomRight(19, 5.5), 2.2), (edges.bottomLeft(8, 8), 3),
        ]
        for glint in glints {
            let shape = Shapes.sparkle(glint.0, radius: glint.1 * unit)
            pen.fill(shape, .white)
            pen.stroke(shape, lilac, width: 0.3)
        }
        let bubbles: [(CGPoint, CGFloat)] = [
            (edges.topLeft(25, 9), 1.3), (edges.topLeft(28.5, 6.5), 0.8),
            (edges.bottomRight(25, 9), 1.3), (edges.bottomRight(28.5, 6.5), 0.8),
        ]
        for bubble in bubbles {
            pen.stroke(Shapes.circle(bubble.0, bubble.1 * unit), .white.opacity(0.7), width: 0.4)
        }
    }

    /// Racing flag checks along the top and bottom.
    private static func checkerEdge(_ pen: NookDecorationPen) {
        let unit = pen.unit
        let edges = Edges(pen: pen)
        let columns = 40
        let side = pen.width / CGFloat(columns)
        let light = Color.white.opacity(0.95)
        let dark = Color.decoration(0x111111).opacity(0.95)
        for column in 0..<columns {
            for row in 0..<2 {
                let isLight = (column + row).isMultiple(of: 2)
                let x = edges.left + CGFloat(column) * side
                // The squares overlap by a hair, which keeps a seam of the
                // camera picture from showing between them.
                let size = CGSize(width: side + 0.5, height: side + 0.5)
                pen.fill(Path(CGRect(origin: CGPoint(x: x, y: edges.top + CGFloat(row) * side), size: size)), isLight ? light : dark)
                pen.fill(
                    Path(CGRect(origin: CGPoint(x: x, y: edges.bottom - CGFloat(2 - row) * side), size: size)),
                    isLight ? dark : light
                )
            }
        }
        let pink = Color.decoration(0xFF4FA3)
        pen.fill(Path(CGRect(x: edges.left, y: edges.top + 2 * side, width: pen.width, height: 0.6 * unit)), pink)
        pen.fill(Path(CGRect(x: edges.left, y: edges.bottom - 2 * side - 0.6 * unit, width: pen.width, height: 0.6 * unit)), pink)
    }

    /// Dreamy clouds in the corners with a moon.
    private static func cloudNine(_ pen: NookDecorationPen) {
        let unit = pen.unit
        let edges = Edges(pen: pen)
        let inside = pen.clipped(to: Path(pen.rect))
        for side in [true, false] {
            func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { side ? edges.bottomLeft(x, y) : edges.bottomRight(x, y) }
            let floor = CGRect(
                x: side ? edges.left : edges.right - 36 * unit,
                y: edges.bottom - 3 * unit,
                width: 36 * unit,
                height: 3 * unit
            )
            let cloud = Shapes.circle(at(6, 3), 7 * unit)
                .union(Shapes.circle(at(15, 5), 8.5 * unit))
                .union(Shapes.circle(at(25, 3), 6.5 * unit))
                .union(Shapes.circle(at(33, 1.5), 4.5 * unit))
                .union(Path(floor))
            inside.fill(cloud, .white.opacity(0.96))
        }
        let high = Shapes.circle(edges.topRight(8, 3), 5.5 * unit)
            .union(Shapes.circle(edges.topRight(16, 2), 4.5 * unit))
            .union(Shapes.circle(edges.topRight(2, 2), 4 * unit))
        inside.fill(high, .white.opacity(0.9))
        let moonlight = Color.decoration(0xFFE9A8)
        pen.fill(
            Shapes.crescent(
                edges.topLeft(11, 9), radius: 5 * unit,
                bite: CGSize(width: 2.2 * unit, height: -1.4 * unit), biteRadius: 4.2 * unit
            ),
            moonlight
        )
        pen.fill(Shapes.sparkle(edges.topLeft(21, 5), radius: 1.8 * unit), moonlight)
        pen.fill(Shapes.sparkle(edges.topLeft(26, 11), radius: 1.2 * unit), moonlight)
        pen.fill(Shapes.sparkle(edges.topRight(30, 6), radius: 1.5 * unit), moonlight)
    }

    // MARK: More frames

    /// Hearts in three sizes and three pinks all the way around.
    private static func heartGarland(_ pen: NookDecorationPen) {
        let edges = Edges(pen: pen)
        let colors: [Color] = [.decoration(0xFF6FA5), .decoration(0xFF4D6D), .decoration(0xFFD1E1)]
        let sizes: [CGFloat] = [9, 6, 7.5]
        let tilts: [CGFloat] = [-14, 10, 0]
        for (index, point) in edges.ring(inset: 7, spacing: 13).enumerated() {
            let heart = Shapes.turned(Shapes.heart(point, width: sizes[index % 3] * pen.unit), tilts[index % 3], about: point)
            pen.stroke(heart, .white, width: 1.6)
            pen.fill(heart, colors[index % 3])
        }
    }

    /// Two glowing tubes, pink outside and cyan inside.
    private static func neonTubes(_ pen: NookDecorationPen) {
        let unit = pen.unit
        let edges = Edges(pen: pen)
        let tubes: [(CGFloat, Color)] = [(2.5, .decoration(0xFF4FD8)), (6, .decoration(0x43E8FF))]
        for tube in tubes {
            let path = edges.outline(inset: tube.0, radius: 6)
            pen.context.drawLayer { layer in
                layer.addFilter(.shadow(color: tube.1.opacity(0.9), radius: 2 * unit))
                layer.stroke(path, with: .color(tube.1), style: StrokeStyle(lineWidth: 1.5 * unit, lineJoin: .round))
            }
            pen.stroke(path, .white.opacity(0.85), width: 0.45)
        }
    }

    /// Daisies growing up from the bottom edge, with a blossom in each
    /// top corner.
    private static func daisyPatch(_ pen: NookDecorationPen) {
        let unit = pen.unit
        let edges = Edges(pen: pen)
        let stem = Color.decoration(0x6FCF97)
        let petals: [Color] = [.white, .decoration(0xFFC2D9), .decoration(0xFFE08A)]
        let count = max(6, Int(pen.width / (13 * unit)))
        for index in 0..<count {
            let x = edges.left + (CGFloat(index) + 0.5) * pen.width / CGFloat(count)
            let tall: CGFloat = index.isMultiple(of: 2) ? 8.5 : 6
            let top = CGPoint(x: x, y: edges.bottom - tall * unit)
            pen.stroke(Shapes.polyline([top, CGPoint(x: x, y: edges.bottom)]), stem, width: 1)
            let blade = CGRect(x: x, y: edges.bottom - 3.6 * unit, width: 5 * unit, height: 2.4 * unit)
            pen.fill(Shapes.leaf(in: blade), stem)
            pen.fill(Shapes.leaf(in: blade.offsetBy(dx: -5 * unit, dy: 0.8 * unit)), .decoration(0x4FB57D))
            let reach = (index.isMultiple(of: 2) ? 3.75 : 3) * unit
            pen.fill(Shapes.flower(top, reach: reach, petals: 6, petalRadius: reach * 0.36), petals[index % 3])
            pen.fill(Shapes.circle(top, 1.2 * unit), .decoration(0xFFB13D))
        }
        for corner in [edges.topLeft(6, 6), edges.topRight(6, 6)] {
            pen.fill(Shapes.flower(corner, reach: 4.5 * unit, petals: 5, petalRadius: 1.9 * unit), .decoration(0xFFC2D9))
            pen.fill(Shapes.circle(corner, 1.5 * unit), .decoration(0xFFE08A))
        }
    }

    /// Five bands of color, one inside the other.
    private static func rainbowBands(_ pen: NookDecorationPen) {
        let edges = Edges(pen: pen)
        let colors: [Color] = [
            .decoration(0xFF6B6B), .decoration(0xFFB34D), .decoration(0xFFE066), .decoration(0x6FDB8F), .decoration(0x6FB7FF),
        ]
        for (index, color) in colors.enumerated() {
            pen.stroke(
                edges.outline(inset: 1 + CGFloat(index) * 2, radius: 5 - CGFloat(index) * 0.6), color, width: 2.05
            )
        }
    }
}
