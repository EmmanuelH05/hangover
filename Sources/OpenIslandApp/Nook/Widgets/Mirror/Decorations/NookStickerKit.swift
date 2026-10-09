import SwiftUI

/// A sticker's unit square. Every number a sticker is drawn from is a
/// fraction of its side: places run from 0 to 1 from the top left, and
/// sizes, radii and line widths are fractions too.
struct NookStickerKit {
    let pen: NookDecorationPen

    private typealias Shapes = NookDecorationShapes

    /// The ink line around a shape, unless a sticker asks for another.
    static let inkWidth: CGFloat = 0.045

    func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { pen.point(x, y) }
    func length(_ value: CGFloat) -> CGFloat { value * pen.width }

    // MARK: Shapes

    func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) -> Path {
        Shapes.circle(at(x, y), length(radius))
    }

    func ellipse(_ x: CGFloat, _ y: CGFloat, width: CGFloat, height: CGFloat, turned degrees: CGFloat = 0) -> Path {
        Shapes.ellipse(at(x, y), width: length(width), height: length(height), turned: degrees)
    }

    func heart(_ x: CGFloat, _ y: CGFloat, width: CGFloat, turned degrees: CGFloat = 0) -> Path {
        let heart = Shapes.heart(at(x, y), width: length(width))
        return degrees == 0 ? heart : Shapes.turned(heart, degrees, about: at(x, y))
    }

    func star(
        _ x: CGFloat,
        _ y: CGFloat,
        outer: CGFloat,
        inner: CGFloat,
        points: Int = 5,
        turned degrees: CGFloat = 0,
        squash: CGFloat = 1
    ) -> Path {
        Shapes.star(at(x, y), outer: length(outer), inner: length(inner), points: points, turned: degrees, squash: squash)
    }

    func sparkle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) -> Path {
        Shapes.sparkle(at(x, y), radius: length(radius))
    }

    func drop(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) -> Path {
        Shapes.drop(at(x, y), radius: length(radius))
    }

    func arc(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, from start: CGFloat, to end: CGFloat) -> Path {
        Shapes.arc(at(x, y), radius: length(radius), from: start, to: end)
    }

    func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
        Shapes.polygon(points.map { at($0.0, $0.1) })
    }

    func polyline(_ points: [(CGFloat, CGFloat)]) -> Path {
        Shapes.polyline(points.map { at($0.0, $0.1) })
    }

    /// A rectangle between two corners, with rounded corners if asked.
    func box(_ left: CGFloat, _ top: CGFloat, _ right: CGFloat, _ bottom: CGFloat, radius: CGFloat = 0) -> Path {
        let origin = at(left, top)
        let rect = CGRect(x: origin.x, y: origin.y, width: length(right - left), height: length(bottom - top))
        return Path(roundedRect: rect, cornerRadius: length(radius))
    }

    /// A curved shape written the way vector drawings write them. Places
    /// are offsets from `origin`. `mirrored` flips it left to right about
    /// the origin, for the other half of a bow.
    func curve(
        from origin: (CGFloat, CGFloat) = (0, 0),
        mirrored: Bool = false,
        _ build: (inout NookStickerCurve) -> Void
    ) -> Path {
        var curve = NookStickerCurve { x, y in
            at(origin.0 + (mirrored ? -x : x), origin.1 + y)
        }
        build(&curve)
        return curve.path
    }

    /// A line turned into the shape it covers when drawn this wide, for
    /// giving stems and trails a rim of their own.
    func body(of line: Path, width: CGFloat) -> Path {
        line.strokedPath(StrokeStyle(lineWidth: length(width), lineCap: .round, lineJoin: .round))
    }

    // MARK: Drawing

    /// The white rim and shadow under the whole sticker.
    func rim(_ silhouette: Path) {
        pen.backing(silhouette)
    }

    func fill(_ path: Path, _ color: Color) {
        pen.fill(path, color)
    }

    /// A line `width` of the sticker's side wide.
    func ink(_ path: Path, _ color: Color, width: CGFloat = NookStickerKit.inkWidth) {
        pen.stroke(path, color, width: width * 100)
    }

    /// A filled shape with its ink line.
    func shape(_ path: Path, fill color: Color, ink line: Color, width: CGFloat = NookStickerKit.inkWidth) {
        fill(path, color)
        ink(path, line, width: width)
    }

    func word(
        _ string: String,
        _ x: CGFloat,
        _ y: CGFloat,
        size: CGFloat,
        font: NookDecorationFont,
        color: Color,
        turned degrees: CGFloat = 0
    ) {
        let place = at(x, y)
        let writer = degrees == 0 ? pen : pen.turned(degrees, about: place)
        writer.text(string, at: place, size: size * 100, font: font, color: color)
    }
}

/// The pen strokes of one curved shape.
struct NookStickerCurve {
    fileprivate(set) var path = Path()
    fileprivate let place: (CGFloat, CGFloat) -> CGPoint

    fileprivate init(place: @escaping (CGFloat, CGFloat) -> CGPoint) {
        self.place = place
    }

    mutating func move(_ x: CGFloat, _ y: CGFloat) {
        path.move(to: place(x, y))
    }

    mutating func line(_ x: CGFloat, _ y: CGFloat) {
        path.addLine(to: place(x, y))
    }

    /// Two control points, then the end.
    mutating func cubic(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ x: CGFloat, _ y: CGFloat) {
        path.addCurve(to: place(x, y), control1: place(x1, y1), control2: place(x2, y2))
    }

    /// One control point, then the end.
    mutating func quad(_ x1: CGFloat, _ y1: CGFloat, _ x: CGFloat, _ y: CGFloat) {
        path.addQuadCurve(to: place(x, y), control: place(x1, y1))
    }

    mutating func close() {
        path.closeSubpath()
    }
}

/// One colorway of a sticker: its main fill, up to two accents, the ink
/// its outline is drawn in, and the color of any word on it.
struct NookStickerTones: Sendable {
    var fill: Color
    var accent: Color = .clear
    var second: Color = .clear
    var ink: Color
    var text: Color = .clear
    /// How solid the main fill is, for a sticker meant to be seen through.
    var fillOpacity: Double = 1

    init(
        _ fill: UInt32,
        accent: UInt32? = nil,
        second: UInt32? = nil,
        ink: UInt32,
        text: UInt32? = nil,
        fillOpacity: Double = 1
    ) {
        self.fillOpacity = fillOpacity
        self.fill = .decoration(fill)
        self.accent = accent.map(Color.decoration) ?? .clear
        self.second = second.map(Color.decoration) ?? .clear
        self.ink = .decoration(ink)
        self.text = text.map(Color.decoration) ?? .clear
    }
}
