import SwiftUI

/// A color at an opacity, kept as numbers. A view draws `color`, and a test
/// reads what the paint comes to over a surface, at the alpha really drawn.
struct IslandPaint: Equatable, Sendable {
    let rgb: IslandHaloRGB
    var opacity: Double = 1

    static let paper = IslandHaloRGB(rgb: 0xF1EAD9)
    static let black = IslandHaloRGB(rgb: 0x000000)

    var color: Color { rgb.color.opacity(opacity) }

    /// What this paint looks like laid over `surface`, mixed the way the
    /// window system mixes two layers.
    func over(_ surface: IslandHaloRGB) -> IslandHaloRGB {
        func mix(_ top: Double, _ bottom: Double) -> Double { top * opacity + bottom * (1 - opacity) }
        return IslandHaloRGB(
            red: mix(rgb.red, surface.red),
            green: mix(rgb.green, surface.green),
            blue: mix(rgb.blue, surface.blue)
        )
    }
}

extension HangoverAccent {
    /// The lightest thing a picked mark sits on: a calendar day that is
    /// both today and the picked day, whose cell is white at 0.12 over ink.
    static let lightestSurface = IslandPaint(rgb: white, opacity: 0.12).over(ink)
}

/// An answer on an agent's question card: the row and its numbered badge,
/// at rest, under the pointer and picked.
///
/// On Default a picked row is paper laid thinly over the card, as it always
/// was. With an accent set the row is filled and ringed in the accent, at
/// opacities that beat the hovered row for every fixed color, and the badge
/// is the accent itself under the tone that reads on it (D62).
enum IslandQuestionOptionLook {
    static let pickedFillOpacity = 0.22
    static let pickedStrokeOpacity = 0.9

    static func fill(isSelected: Bool, isHovered: Bool, accent: HangoverAccentTint) -> IslandPaint {
        if isSelected {
            if let rgb = accent.rgb { return IslandPaint(rgb: rgb, opacity: pickedFillOpacity) }
            return IslandPaint(rgb: IslandPaint.paper, opacity: 0.10)
        }
        return IslandPaint(rgb: HangoverAccent.white, opacity: isHovered ? 0.065 : 0.028)
    }

    static func stroke(isSelected: Bool, isHovered: Bool, accent: HangoverAccentTint) -> IslandPaint {
        if isSelected {
            if let rgb = accent.rgb { return IslandPaint(rgb: rgb, opacity: pickedStrokeOpacity) }
            return IslandPaint(rgb: IslandPaint.paper, opacity: 0.36)
        }
        return IslandPaint(rgb: HangoverAccent.white, opacity: isHovered ? 0.13 : 0.045)
    }

    static func badgeFill(isSelected: Bool, accent: HangoverAccentTint) -> IslandPaint {
        guard isSelected else { return IslandPaint(rgb: HangoverAccent.white, opacity: 0.045) }
        if let rgb = accent.rgb { return IslandPaint(rgb: rgb) }
        return IslandPaint(rgb: IslandPaint.paper, opacity: 0.88)
    }

    static func badgeText(isSelected: Bool, accent: HangoverAccentTint) -> IslandPaint {
        guard isSelected else { return IslandPaint(rgb: IslandPaint.paper, opacity: 0.42) }
        if let rgb = accent.rgb { return IslandPaint(rgb: HangoverAccent.textTone(on: rgb).rgb) }
        return IslandPaint(rgb: IslandPaint.black, opacity: 0.82)
    }
}

/// The numbered square at the front of an answer.
struct IslandQuestionOptionBadge: View {
    let number: Int
    let isSelected: Bool

    @Environment(\.hangoverAccent) private var accent

    var body: some View {
        Text("\(number)")
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(IslandQuestionOptionLook.badgeText(isSelected: isSelected, accent: accent).color)
            .frame(width: 22, height: 20)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(IslandQuestionOptionLook.badgeFill(isSelected: isSelected, accent: accent).color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(.white.opacity(isSelected ? 0 : 0.08))
            )
    }
}

/// A day's number in a calendar. On Default, today wears the Nook's orange
/// as it always did. With an accent set a picked thing is a fill (D62), and
/// today is its number on a circle of the accent.
struct NookDayNumber: View {
    let text: String
    let isToday: Bool
    let font: Font
    /// The circle behind today's number when an accent is set.
    let diameter: CGFloat
    var plain = Color.white.opacity(0.85)

    @Environment(\.hangoverAccent) private var accent

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(isToday ? accent.pickedText(.orange) : plain)
            .background {
                if isToday, let fill = accent.pickedFill {
                    Circle().fill(fill).frame(width: diameter, height: diameter)
                }
            }
    }
}

/// A sample scrub bar for the pictures Settings draws of the island: a
/// track and the part played, which takes the accent like the real one.
struct NookSampleProgress: View {
    var fraction: CGFloat = 0.4

    @Environment(\.hangoverAccent) private var accent

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.15))
            .frame(height: 3)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule()
                        .fill(accent.highlight(.white).opacity(0.8))
                        .frame(width: geometry.size.width * fraction)
                }
            }
    }
}
