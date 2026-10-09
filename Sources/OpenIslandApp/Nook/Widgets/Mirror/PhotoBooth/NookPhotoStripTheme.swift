import AppKit
import CoreGraphics
import CoreText
import Foundation

/// A color on the printed strip, kept as plain numbers, which makes a
/// theme a value that can be sent between tasks.
struct NookStripColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    /// From `0xRRGGBB`.
    init(_ hex: UInt32, alpha: Double = 1) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    func opacity(_ alpha: Double) -> NookStripColor {
        var copy = self
        copy.alpha = alpha
        return copy
    }

    static let white = NookStripColor(0xFFFFFF)
    static let black = NookStripColor(0x000000)
}

/// What the paper under the pictures is.
enum NookStripPaper: Equatable, Sendable {
    case solid(NookStripColor)
    /// Colors from the top of the page to the bottom, each with its place
    /// between 0 and 1.
    case gradient([NookStripColor], stops: [CGFloat])
}

/// A mark printed on the paper, under the pictures.
enum NookStripPattern: Equatable, Sendable {
    /// Fine lines both ways.
    case grid(NookStripColor, spacing: CGFloat, line: CGFloat)
    /// Bands both ways that read darker where they cross.
    case gingham(NookStripColor, band: CGFloat, period: CGFloat)
    /// Thin upright lines.
    case pinstripes(NookStripColor, width: CGFloat, period: CGFloat, start: CGFloat)
    /// A page from a school notebook: blue rules and one margin line.
    case ruled(NookStripColor, period: CGFloat, margin: NookStripColor, marginX: CGFloat)
    /// Newsprint dots, every other row shifted.
    case halftone(NookStripColor, radius: CGFloat, pitch: CGFloat)
    /// Film perforations down both long edges.
    case sprockets(NookStripColor)
    /// Four-point glints in the gaps between pictures and in the footer.
    case glints(NookStripColor)
    /// Small squares, dots and dashes thrown about. The seed fixes where.
    case confetti([NookStripColor], count: Int, seed: UInt64)
    /// Four-point sparkles thrown about.
    case sparkles(NookStripColor, count: Int, seed: UInt64)
    /// Darker corners, the way an old lens leaves them.
    case vignette(NookStripColor)
}

/// A line of a given color and weight.
struct NookStripLine: Equatable, Sendable {
    var color: NookStripColor
    var width: CGFloat
}

/// How each picture is framed on the strip.
struct NookStripFrame: Equatable, Sendable {
    /// Corner radius of the slot.
    var radius: CGFloat = 0
    /// The line on the slot's edge.
    var border: NookStripLine?
    /// A second line outside the first, `gap` points clear of it.
    var outerLine: NookStripLine?
    var outerGap: CGFloat = 0
    /// Fills the slot with a card and sets the picture in from its edge,
    /// the way an instant print sits on its border.
    var mat: NookStripColor?
    var matInset: CGFloat = 0
    /// Degrees the border is turned, one way on odd pictures and the other
    /// on even ones. The picture itself stays straight.
    var tilt: CGFloat = 0
    /// A strip of tape on the top edge.
    var tape: NookStripColor?
    /// Fine dark lines across the picture, like an old screen.
    var scanlines: NookStripColor?
    /// "1/4" in the corner of each picture, in this ink on this plate.
    var counter: NookStripColor?
    var counterPlate: NookStripColor?
}

/// How the camera's picture is developed. Decorations keep their own
/// colors and go on after this.
enum NookStripTreatment: Equatable, Sendable {
    /// Color with its saturation, contrast and brightness nudged, and an
    /// optional wash of one color laid softly over it. The wash's alpha is
    /// how much.
    case adjusted(saturation: Double, contrast: Double, brightness: Double, wash: NookStripColor?)
    case sepia(intensity: Double, vignette: Double)
    /// Two inks: black prints as `dark` and white as `light`.
    case duotone(dark: NookStripColor, light: NookStripColor, contrast: Double)

    static let color = NookStripTreatment.adjusted(saturation: 1, contrast: 1, brightness: 0, wash: nil)

    /// True when the picture is left as it came.
    var isUntouched: Bool { self == .color }
}

/// The type the footer is set in. Named faces ship with macOS, and a
/// missing one falls back to a system face of the same kind.
struct NookStripFont: Equatable, Sendable {
    enum Family: Sendable {
        case rounded
        case serif
        case mono
    }

    /// PostScript name, or nil for the system face.
    var name: String?
    var fallback: Family
    var isBold = true

    static func named(_ name: String, fallback: Family = .rounded) -> NookStripFont {
        NookStripFont(name: name, fallback: fallback)
    }

    static func system(_ family: Family, bold: Bool = true) -> NookStripFont {
        NookStripFont(name: nil, fallback: family, isBold: bold)
    }

    func font(size: CGFloat) -> CTFont {
        if let name, let font = NSFont(name: name, size: size) { return font }
        let base = NSFont.systemFont(ofSize: size, weight: isBold ? .bold : .regular)
        let design: NSFontDescriptor.SystemDesign = switch fallback {
        case .rounded: .rounded
        case .serif: .serif
        case .mono: .monospaced
        }
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
}

/// How a line of the footer is cased.
enum NookStripCase: Sendable {
    case asTyped
    case upper
    case lower

    func apply(_ text: String) -> String {
        switch self {
        case .asTyped: text
        case .upper: text.uppercased()
        case .lower: text.lowercased()
        }
    }
}

/// How the footer is set: the caption, the date under it, and anything
/// drawn around them.
struct NookStripFooter: Equatable, Sendable {
    enum Alignment: Sendable {
        case center
        case left
        /// One line: caption at the left, date at the right.
        case split
    }

    enum Ornament: Equatable, Sendable {
        /// A small heart either side of the caption.
        case hearts(NookStripColor)
        /// A ribbon bow above the caption.
        case bow(fill: NookStripColor, accent: NookStripColor, ink: NookStripColor)
        /// Two thin rules across the top, like a newspaper's.
        case doubleRule(NookStripColor)
    }

    var captionFont: NookStripFont
    /// Type sizes are for the classic strip. Other layouts scale them.
    var captionSize: CGFloat
    var captionInk: NookStripColor
    var captionCase: NookStripCase = .asTyped
    var captionTracking: CGFloat = 0
    var dateFont: NookStripFont
    var dateSize: CGFloat
    var dateInk: NookStripColor
    /// A Unicode date pattern, such as `MMM dd yyyy`.
    var dateFormat: String
    var dateCase: NookStripCase = .asTyped
    var dateTracking: CGFloat = 0
    var alignment: Alignment = .center
    /// A plate behind the text, for papers too busy to read on.
    var plate: NookStripColor?
    var plateRadius: CGFloat = 3
    var ornament: Ornament?

    func dateText(for date: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = dateFormat
        return dateCase.apply(formatter.string(from: date))
    }
}

/// One look for the printed strip: the paper, how each picture is framed
/// and developed, and how the footer is set. Every theme is drawn in code
/// from these parts. None uses a picture file.
struct NookPhotoStripTheme: Identifiable, Equatable, Sendable {
    let id: String
    var paper: NookStripPaper
    var patterns: [NookStripPattern] = []
    var frame: NookStripFrame
    var treatment: NookStripTreatment = .color
    var footer: NookStripFooter

    var nameKey: String { "nook.photoBooth.theme.\(id)" }
    /// What the footer says when the user has typed no caption.
    var defaultCaptionKey: String { "nook.photoBooth.theme.\(id).caption" }

    static let defaultID = "classic"

    static func theme(id: String) -> NookPhotoStripTheme {
        all.first { $0.id == id } ?? all[0]
    }

    static let all: [NookPhotoStripTheme] = NookPhotoStripThemes.catalog
}
