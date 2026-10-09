import SwiftUI

/// A frame around the mirror's picture. Every design is drawn in code from
/// plain shapes, which is why there are no picture files to ship.
struct NookMirrorFrameDesign: Identifiable, Sendable {
    let id: String
    /// Key of the design's name in `Localizable.strings`.
    let nameKey: String
    /// Draws the frame over the whole picture and leaves its middle clear.
    let draw: @Sendable (NookDecorationPen) -> Void
}

/// A sticker for the mirror, drawn in a square.
struct NookMirrorStickerDesign: Identifiable, Sendable {
    let id: String
    let nameKey: String
    /// How many colorways the design has.
    let variants: Int
    let draw: @Sendable (NookDecorationPen, _ variant: Int) -> Void

    /// A saved colorway brought into the ones this design has.
    func wrapped(_ variant: Int) -> Int {
        guard variants > 0 else { return 0 }
        return ((variant % variants) + variants) % variants
    }
}

/// Every frame and sticker the mirror offers, in picker order.
enum NookMirrorDesigns {
    static let frames: [NookMirrorFrameDesign] = NookMirrorFrameDesigns.all
    static let stickers: [NookMirrorStickerDesign] = NookMirrorStickerDesigns.all

    static let frameIDs = Set(frames.map(\.id))
    static let stickerIDs = Set(stickers.map(\.id))

    // First one wins if two designs ever share an id. A test keeps ids apart.
    private static let framesByID = Dictionary(frames.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    private static let stickersByID = Dictionary(stickers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    static func frame(_ id: String?) -> NookMirrorFrameDesign? {
        id.flatMap { framesByID[$0] }
    }

    static func sticker(_ id: String) -> NookMirrorStickerDesign? {
        stickersByID[id]
    }
}

/// The typefaces a design may write in. All three ship with macOS.
enum NookDecorationFont {
    /// The rounded system face.
    case rounded(Font.Weight, italic: Bool = false)
    /// Menlo, for film edge print, score lines and prompts.
    case mono(bold: Bool)
    /// Bradley Hand, for a handwritten note.
    case hand

    func font(size: CGFloat) -> Font {
        switch self {
        case let .rounded(weight, _): .system(size: size, weight: weight, design: .rounded)
        case let .mono(bold): .custom(bold ? "Menlo-Bold" : "Menlo-Regular", fixedSize: size)
        case .hand: .custom("BradleyHandITCTT-Bold", fixedSize: size)
        }
    }

    var isItalic: Bool {
        if case let .rounded(_, italic) = self { return italic }
        return false
    }
}

/// What a design draws with: the canvas and the rectangle the design fills.
/// Places are given as fractions of that rectangle. Line widths and small
/// ornaments use `unit`, which keeps them the same shape on a wide picture
/// and on a square sticker.
struct NookDecorationPen {
    /// Thinner lines and smaller words than these are lost in a small
    /// drawing, such as a picker tile or one slot of a photo strip.
    static let thinnestLine: CGFloat = 0.35
    static let smallestText: CGFloat = 3.5

    let context: GraphicsContext
    let rect: CGRect
    /// The line a frame with a note writes: today's date.
    var note = ""

    var width: CGFloat { rect.width }
    var height: CGFloat { rect.height }

    /// One hundredth of the rectangle's shorter side.
    var unit: CGFloat { min(rect.width, rect.height) / 100 }

    /// A point at these fractions of the rectangle.
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }

    func fill(_ path: Path, _ color: Color) {
        context.fill(path, with: .color(color))
    }

    private func style(width: CGFloat, dash: [CGFloat], cap: CGLineCap) -> StrokeStyle {
        StrokeStyle(
            lineWidth: max(Self.thinnestLine, width * unit),
            lineCap: cap,
            lineJoin: .round,
            dash: dash.map { $0 * unit }
        )
    }

    /// `width` and `dash` are in units.
    func stroke(_ path: Path, _ color: Color, width: CGFloat, dash: [CGFloat] = [], cap: CGLineCap = .round) {
        context.stroke(path, with: .color(color), style: style(width: width, dash: dash, cap: cap))
    }

    func stroke(_ path: Path, gradient: Gradient, from start: CGPoint, to end: CGPoint, width: CGFloat) {
        context.stroke(
            path,
            with: .linearGradient(gradient, startPoint: start, endPoint: end),
            style: style(width: width, dash: [], cap: .round)
        )
    }

    /// Writes a word and hands back how much room it took, which is zero
    /// when the word would be too small to read and is left out. `size`
    /// is in units.
    @discardableResult
    func text(
        _ string: String,
        at place: CGPoint,
        size: CGFloat,
        font: NookDecorationFont = .rounded(.heavy),
        color: Color,
        anchor: UnitPoint = .center
    ) -> CGSize {
        let points = size * unit
        guard points >= Self.smallestText, !string.isEmpty else { return .zero }
        var label = Text(string).font(font.font(size: points)).foregroundStyle(color)
        if font.isItalic { label = label.italic() }
        let resolved = context.resolve(label)
        context.draw(resolved, at: place, anchor: anchor)
        return resolved.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
    }

    /// The white rim and soft shadow a sticker sits on, like one peeled
    /// off a sheet. Draw the colors on top of it.
    func backing(_ outline: Path, rim: CGFloat = 10) {
        let unit = unit
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.3), radius: 3 * unit, x: 0, y: 2 * unit))
            if rim > 0 {
                layer.stroke(
                    outline,
                    with: .color(.white),
                    style: StrokeStyle(lineWidth: rim * unit, lineCap: .round, lineJoin: .round)
                )
            }
            layer.fill(outline, with: .color(.white))
        }
    }

    /// The same pen turned about a point, in degrees clockwise.
    func turned(_ degrees: CGFloat, about center: CGPoint) -> NookDecorationPen {
        var turned = context
        turned.translateBy(x: center.x, y: center.y)
        turned.rotate(by: .degrees(degrees))
        turned.translateBy(x: -center.x, y: -center.y)
        return NookDecorationPen(context: turned, rect: rect, note: note)
    }

    /// The same pen drawing only inside a shape.
    func clipped(to shape: Path) -> NookDecorationPen {
        var clipped = context
        clipped.clip(to: shape)
        return NookDecorationPen(context: clipped, rect: rect, note: note)
    }
}

extension Color {
    /// A color from six hex digits, as the design notes write them.
    static func decoration(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
