import Foundation

/// Reads a color someone typed or pasted. It takes:
///
/// - HEX with or without "#": three digits ("f80"), four with alpha
///   ("f80c"), six ("ff8800") or eight with alpha ("ff8800cc").
/// - `rgb(255, 136, 0)`, `rgba(255, 136, 0, 0.5)`, the space form
///   `rgb(255 136 0 / 50%)`, and channels as percentages.
/// - Three or four bare numbers, "255, 136, 0" or "255 136 0 0.5". Any
///   kind of blank, a tab or a line break included, separates numbers.
/// - `hsl(32, 100%, 50%)`, `hsla(32, 100%, 50%, 0.5)`, with or without
///   "deg" and the percent signs. Hue wraps, 380 is 20.
///
/// Anything else is nil. A channel out of range is refused and not
/// clamped, because a typo should not turn into a color nobody meant.
enum NookDesignColorParser {
    /// Longer text than this is never a color.
    static let maxLength = 64

    static func parse(_ text: String) -> NookDesignColor? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasSuffix(";") { trimmed.removeLast() }
        trimmed = trimmed.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { return nil }

        if let arguments = functionArguments(of: trimmed, named: ["rgba", "rgb"]) {
            return rgb(from: arguments)
        }
        if let arguments = functionArguments(of: trimmed, named: ["hsla", "hsl"]) {
            return hsl(from: arguments)
        }
        if trimmed.contains(where: isSeparator) {
            return rgb(from: tokens(in: trimmed))
        }
        return hex(from: trimmed)
    }

    // MARK: HEX

    private static func hex(from text: String) -> NookDesignColor? {
        var digits = Substring(text)
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        let values = digits.utf8.map(hexValue)
        guard values.allSatisfy({ $0 != nil }) else { return nil }
        let nibbles = values.compactMap { $0 }
        switch nibbles.count {
        case 3, 4:
            // Each digit stands for itself twice: "f80" is "ff8800".
            let bytes = nibbles.map { $0 * 17 }
            return NookDesignColor(red: bytes[0], green: bytes[1], blue: bytes[2], alpha: bytes.count == 4 ? bytes[3] : 255)
        case 6, 8:
            let bytes = stride(from: 0, to: nibbles.count, by: 2).map { nibbles[$0] * 16 + nibbles[$0 + 1] }
            return NookDesignColor(red: bytes[0], green: bytes[1], blue: bytes[2], alpha: bytes.count == 4 ? bytes[3] : 255)
        default:
            return nil
        }
    }

    /// The value of one ASCII HEX digit. Digits from other scripts are
    /// refused, which `Character.isHexDigit` would let through.
    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
        default: nil
        }
    }

    // MARK: Functions

    /// The text between the brackets of `name(...)`, split into tokens.
    private static func functionArguments(of text: String, named names: [String]) -> [Substring]? {
        for name in names where text.hasPrefix(name) {
            let rest = text.dropFirst(name.count).drop(while: { $0.isWhitespace })
            guard rest.hasPrefix("("), rest.hasSuffix(")") else { continue }
            let inside = rest.dropFirst().dropLast()
            guard !inside.contains("("), !inside.contains(")") else { return [] }
            return tokens(in: inside)
        }
        return nil
    }

    private static func tokens<Text: StringProtocol>(in text: Text) -> [Substring] where Text.SubSequence == Substring {
        text.split(whereSeparator: isSeparator)
    }

    /// A comma, a slash, or a blank of any kind. Text copied from a web
    /// page or a design file carries tabs, line breaks and no-break spaces
    /// where a typist would use a space.
    private static func isSeparator(_ character: Character) -> Bool {
        character == "," || character == "/" || character.isWhitespace
    }

    private static func rgb(from tokens: [Substring]) -> NookDesignColor? {
        guard tokens.count == 3 || tokens.count == 4 else { return nil }
        let channels = tokens.prefix(3).map(channel)
        guard channels.allSatisfy({ $0 != nil }) else { return nil }
        let bytes = channels.compactMap { $0 }
        guard let alpha = alpha(tokens.count == 4 ? tokens[3] : nil) else { return nil }
        return NookDesignColor(red: bytes[0], green: bytes[1], blue: bytes[2], alpha: alpha)
    }

    private static func hsl(from tokens: [Substring]) -> NookDesignColor? {
        guard tokens.count == 3 || tokens.count == 4 else { return nil }
        var hueText = tokens[0]
        if hueText.hasSuffix("deg") { hueText = hueText.dropLast(3) }
        if hueText.hasSuffix("°") { hueText = hueText.dropLast() }
        guard let hue = number(hueText),
              let saturation = percent(tokens[1]),
              let lightness = percent(tokens[2]),
              let alpha = alpha(tokens.count == 4 ? tokens[3] : nil) else {
            return nil
        }
        return NookDesignColor(hue: hue, saturation: saturation, lightness: lightness, alpha: alpha)
    }

    /// One red, green or blue value: 0 to 255, or 0% to 100%.
    private static func channel(_ token: Substring) -> UInt8? {
        if token.hasSuffix("%") {
            guard let value = number(token.dropLast()), (0...100).contains(value) else { return nil }
            return NookDesignColor.byte(value / 100)
        }
        guard let value = number(token), (0...255).contains(value) else { return nil }
        return UInt8(value.rounded())
    }

    /// Saturation or lightness: 0 to 100, with or without the percent sign.
    private static func percent(_ token: Substring) -> Double? {
        let digits = token.hasSuffix("%") ? token.dropLast() : token
        guard let value = number(digits), (0...100).contains(value) else { return nil }
        return value / 100
    }

    /// Alpha: 0 to 1, or 0% to 100%. No token means opaque.
    private static func alpha(_ token: Substring?) -> UInt8? {
        guard let token else { return 255 }
        if token.hasSuffix("%") {
            guard let value = number(token.dropLast()), (0...100).contains(value) else { return nil }
            return NookDesignColor.byte(value / 100)
        }
        guard let value = number(token), (0...1).contains(value) else { return nil }
        return NookDesignColor.byte(value)
    }

    /// A plain decimal number: an optional sign, digits, and at most one
    /// point. `Double` alone would also read "1e3", "nan" and "0x10".
    private static func number(_ text: Substring) -> Double? {
        var digits = text
        if digits.hasPrefix("-") || digits.hasPrefix("+") { digits = digits.dropFirst() }
        guard !digits.isEmpty, digits.count <= 12 else { return nil }
        var points = 0
        var hasDigit = false
        for byte in digits.utf8 {
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): hasDigit = true
            case UInt8(ascii: "."): points += 1
            default: return nil
            }
        }
        guard hasDigit, points <= 1 else { return nil }
        return Double(text)
    }
}
