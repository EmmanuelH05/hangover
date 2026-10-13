import AppKit
import SwiftUI

/// One color the design kit keeps: sRGB, eight bits a channel, alpha
/// included. Two colors are the same color when all four numbers match,
/// which is what duplicate detection compares.
///
/// It is saved as its HEX text ("#FF8800", or "#FF880080" with alpha),
/// which keeps the files readable and lets a hand-edited file use any form
/// the parser reads.
struct NookDesignColor: Hashable, Sendable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8
    var alpha: UInt8 = 255

    var isOpaque: Bool { alpha == 255 }

    /// Alpha from 0 to 1.
    var opacity: Double { Double(alpha) / 255 }

    // MARK: Text forms

    /// "#FF8800", with two more digits when the color is see-through.
    func hex(includesHash: Bool = true) -> String {
        let digits = isOpaque
            ? String(format: "%02X%02X%02X", red, green, blue)
            : String(format: "%02X%02X%02X%02X", red, green, blue, alpha)
        return includesHash ? "#" + digits : digits
    }

    /// "rgb(255, 136, 0)", or "rgba(255, 136, 0, 0.5)" when see-through.
    var rgbText: String {
        isOpaque
            ? "rgb(\(red), \(green), \(blue))"
            : "rgba(\(red), \(green), \(blue), \(alphaText))"
    }

    /// "hsl(32, 100%, 50%)", or "hsla(32, 100%, 50%, 0.5)" when see-through.
    var hslText: String {
        let hsl = hsl
        let hue = Int(hsl.hue.rounded()) % 360
        let saturation = Int((hsl.saturation * 100).rounded())
        let lightness = Int((hsl.lightness * 100).rounded())
        return isOpaque
            ? "hsl(\(hue), \(saturation)%, \(lightness)%)"
            : "hsla(\(hue), \(saturation)%, \(lightness)%, \(alphaText))"
    }

    /// Alpha as a decimal: the shortest of one, two or three places that
    /// reads back as the same eight bit number. 128 is "0.5".
    var alphaText: String {
        for places in 1...3 {
            let text = String(format: "%.\(places)f", opacity)
            if let value = Double(text), UInt8((value * 255).rounded()) == alpha {
                return Self.trimmingZeros(text)
            }
        }
        return Self.trimmingZeros(String(format: "%.3f", opacity))
    }

    private static func trimmingZeros(_ text: String) -> String {
        guard text.contains(".") else { return text }
        var result = text
        while result.hasSuffix("0") { result.removeLast() }
        if result.hasSuffix(".") { result.removeLast() }
        return result
    }

    // MARK: HSL

    /// Hue in degrees from 0 up to 360, saturation and lightness from 0 to 1.
    var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let r = Double(red) / 255
        let g = Double(green) / 255
        let b = Double(blue) / 255
        let high = max(r, g, b)
        let low = min(r, g, b)
        let lightness = (high + low) / 2
        let spread = high - low
        guard spread > 0 else { return (0, 0, lightness) }
        let saturation = spread / (1 - abs(2 * lightness - 1))
        var hue: Double
        if high == r {
            hue = ((g - b) / spread).truncatingRemainder(dividingBy: 6)
        } else if high == g {
            hue = (b - r) / spread + 2
        } else {
            hue = (r - g) / spread + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        return (hue, min(1, saturation), lightness)
    }

    /// A color from hue in degrees (any number, it wraps), and saturation
    /// and lightness from 0 to 1.
    init(hue: Double, saturation: Double, lightness: Double, alpha: UInt8 = 255) {
        let wrapped = hue.truncatingRemainder(dividingBy: 360)
        let h = (wrapped < 0 ? wrapped + 360 : wrapped) / 60
        let s = min(1, max(0, saturation))
        let l = min(1, max(0, lightness))
        let chroma = (1 - abs(2 * l - 1)) * s
        let x = chroma * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double) = switch Int(h) {
        case 0: (chroma, x, 0)
        case 1: (x, chroma, 0)
        case 2: (0, chroma, x)
        case 3: (0, x, chroma)
        case 4: (x, 0, chroma)
        default: (chroma, 0, x)
        }
        let lift = l - chroma / 2
        self.init(
            red: Self.byte(r + lift),
            green: Self.byte(g + lift),
            blue: Self.byte(b + lift),
            alpha: alpha
        )
    }

    init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// A number from 0 to 1 as eight bits, rounded and kept in range.
    static func byte(_ unit: Double) -> UInt8 {
        UInt8(min(255, max(0, (unit * 255).rounded())))
    }

    // MARK: Drawing

    /// The color for SwiftUI.
    var color: Color {
        Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: opacity)
    }

    /// How bright the color looks, from 0 to 1, alpha left out. This is
    /// the weighted sum used to pick readable text over a swatch. It is
    /// not the WCAG number.
    var perceivedBrightness: Double {
        (0.299 * Double(red) + 0.587 * Double(green) + 0.114 * Double(blue)) / 255
    }

    /// The tint for the closed island's notice. A color too dark to see
    /// on the black pill is swapped for white.
    var noticeTint: NookDesignColor {
        perceivedBrightness < 0.28 ? NookDesignColor(red: 255, green: 255, blue: 255) : NookDesignColor(red: red, green: green, blue: blue)
    }

    /// A color the system handed over, taken to sRGB and rounded to eight
    /// bits a channel. Nil when it has no RGB form, such as a pattern.
    init?(nsColor: NSColor) {
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return nil }
        self.init(
            red: Self.byte(Double(rgb.redComponent)),
            green: Self.byte(Double(rgb.greenComponent)),
            blue: Self.byte(Double(rgb.blueComponent)),
            alpha: Self.byte(Double(rgb.alphaComponent))
        )
    }
}

extension NookDesignColor: Codable {
    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = NookDesignColorParser.parse(text) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Not a color")
            )
        }
        self = parsed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex())
    }
}

/// The text a click on a swatch puts on the clipboard.
enum NookDesignColorFormat: String, CaseIterable, Identifiable, Sendable {
    /// "#FF8800"
    case hex
    /// "FF8800"
    case hexBare
    /// "rgb(255, 136, 0)"
    case rgb
    /// "hsl(32, 100%, 50%)"
    case hsl

    var id: String { rawValue }

    var titleKey: String { "nook.design.format.\(rawValue)" }

    /// The few letters the card's format chip shows.
    var shortTitle: String {
        switch self {
        case .hex: "#HEX"
        case .hexBare: "HEX"
        case .rgb: "RGB"
        case .hsl: "HSL"
        }
    }

    func text(for color: NookDesignColor) -> String {
        switch self {
        case .hex: color.hex()
        case .hexBare: color.hex(includesHash: false)
        case .rgb: color.rgbText
        case .hsl: color.hslText
        }
    }

    /// The format after this one, for the chip that steps through them.
    var next: NookDesignColorFormat {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
}
