import SwiftUI

extension EnvironmentValues {
    /// True when a design kit view is drawn into a picture and not onto
    /// the screen. `ImageRenderer` cannot draw AppKit-backed views, which
    /// is why a still view swaps its text fields, sliders, scroll views
    /// and drop targets for plain look-alikes.
    @Entry var nookDesignIsStill: Bool = false
}

/// Pure layout rules for the design kit card. A plain enum on purpose:
/// the window-sizing math and the tests call it off the main actor.
enum NookDesignCardLayout {
    /// Tall enough for the Links tab's field, collection chips and two
    /// rows of links. The other tabs have room to spare.
    static let mediumHeight: CGFloat = 128
    static let largeHeight: CGFloat = 240
    static let spacing: CGFloat = 6

    /// Height at each size. Small rows always use the grid's shared height.
    static func height(for size: NookWidgetSize) -> CGFloat {
        switch size {
        case .small: NookWidgetLayout.smallHeight
        case .medium: mediumHeight
        case .large: largeHeight
        }
    }

    /// Side of a swatch in the card's main row.
    static func swatchSide(for size: NookWidgetSize) -> CGFloat {
        switch size {
        case .small: 26
        case .medium: 28
        case .large: 30
        }
    }

    /// Side of a reference tile.
    static func tileSide(for size: NookWidgetSize) -> CGFloat {
        switch size {
        case .small: 52
        case .medium: 56
        case .large: 60
        }
    }

    /// How many link rows of `rowHeight` fit in `height` with `spacing`
    /// between them.
    static func rowCapacity(height: CGFloat, rowHeight: CGFloat, spacing: CGFloat) -> Int {
        guard height > 0, rowHeight > 0 else { return 0 }
        return max(0, Int((height + spacing) / (rowHeight + spacing)))
    }

    /// How many squares of `side` fit in `width` with `spacing` between.
    static func capacity(width: CGFloat, side: CGFloat, spacing: CGFloat = spacing) -> Int {
        guard width > 0, side > 0 else { return 0 }
        return max(0, Int((width + spacing) / (side + spacing)))
    }

    /// A palette's name cut to what a chip in a row has room for.
    static func chipText(_ name: String, limit: Int = 14) -> String {
        name.count > limit ? String(name.prefix(max(1, limit - 1))) + "…" : name
    }

    /// What a row with room for `capacity` squares shows. When everything
    /// fits it shows everything. When it does not, the last square is the
    /// "+N" tile, and N counts what is left out.
    static func visible<Item>(_ items: [Item], capacity: Int) -> (shown: [Item], hidden: Int) {
        guard items.count > capacity else { return (items, 0) }
        let shown = Array(items.prefix(max(0, capacity - 1)))
        return (shown, items.count - shown.count)
    }
}

/// The gray squares a see-through color or picture is drawn over.
struct NookDesignCheckerboard: View {
    var square: CGFloat = 5

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.92)))
            let step = max(1, square)
            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : step
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: y, width: step, height: step)), with: .color(Color(white: 0.62)))
                    x += step * 2
                }
                y += step
                row += 1
            }
        }
        .accessibilityHidden(true)
    }
}

/// One color as a square or a circle. A see-through color shows the
/// checkerboard under it, a favorite carries a star, and a color that was
/// just copied shows a tick.
struct NookDesignSwatchChip: View {
    let color: NookDesignColor
    var side: CGFloat
    var isRound = false
    var isFavorite = false
    var isJustCopied = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: isRound ? side / 2 : min(8, side * 0.27), style: .continuous)
    }

    /// A mark that reads on the color under it.
    private var inkColor: Color {
        color.opacity < 0.5 || color.perceivedBrightness > 0.6 ? .black : .white
    }

    var body: some View {
        ZStack {
            if !color.isOpaque {
                NookDesignCheckerboard(square: max(3, side / 5))
            }
            color.color
            if isJustCopied {
                Image(systemName: "checkmark")
                    .font(.system(size: side * 0.42, weight: .bold))
                    .foregroundStyle(inkColor)
                    .transition(.opacity)
            }
        }
        .frame(width: side, height: side)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
        .overlay(alignment: .topTrailing) {
            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: max(6, side * 0.26)))
                    .foregroundStyle(.yellow, .black.opacity(0.5))
                    .padding(1.5)
                    .background(Circle().fill(Color.black.opacity(0.55)))
                    .offset(x: 3, y: -3)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// "+N" stand-in for the swatches or pictures that do not fit.
struct NookDesignMoreTile: View {
    let count: Int
    let side: CGFloat

    var body: some View {
        Text("+\(count)")
            .font(.system(size: min(12, side * 0.4), weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(.white.opacity(0.6))
            .frame(width: side, height: side)
            .background(
                RoundedRectangle(cornerRadius: min(8, side * 0.27), style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
    }
}

/// A line over the bottom of the card that says what an action did, or
/// why it could not.
struct NookDesignNoticeBar: View {
    let notice: NookDesignNotice

    private var symbol: String {
        switch notice.kind {
        case .done: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch notice.kind {
        case .done: .green
        case .info: .white.opacity(0.6)
        case .error: .orange
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            if let swatch = notice.swatch {
                NookDesignSwatchChip(color: swatch, side: 11, isRound: true)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(notice.text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.86)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

/// The line that stays in the card while the eyedropper's shortcut does not
/// work. A press opens Settings, where it can be set again.
struct NookDesignStandingBar: View {
    let notice: NookDesignStandingNotice
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(notice.text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.black.opacity(0.86)))
            .overlay(Capsule().strokeBorder(Color.orange.opacity(0.5), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(notice.text)
    }
}

/// The small round buttons in the card's header and rows.
struct NookDesignIconButton: View {
    @Environment(\.hangoverAccent) private var accent
    let symbol: String
    let label: String
    var tint: Color = .white.opacity(0.6)
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(isOn ? accent.textOnHighlight(.black) : tint)
                .frame(width: 20, height: 20)
                .background(Circle().fill(isOn ? accent.highlight(.orange) : Color.white.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// A small capsule holding a word or two, such as the copy format.
struct NookDesignChipLabel: View {
    @Environment(\.hangoverAccent) private var accent
    let text: String
    var isOn = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .foregroundStyle(isOn ? accent.textOnHighlight(.black) : Color.white.opacity(0.7))
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(isOn ? accent.highlight(.orange) : Color.white.opacity(0.1)))
            .contentShape(Capsule())
    }
}

/// A text field that draws as a plain look-alike in a still picture.
struct NookDesignField: View {
    @Binding var text: String
    let prompt: String
    var onSubmit: () -> Void = {}
    @Environment(\.nookDesignIsStill) private var isStill

    var body: some View {
        Group {
            if isStill {
                Text(text.isEmpty ? prompt : text)
                    .foregroundStyle(.white.opacity(text.isEmpty ? 0.3 : 0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("", text: $text, prompt: Text(prompt))
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white.opacity(0.85))
                    .onSubmit(onSubmit)
            }
        }
        .font(.system(size: 11.5))
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .accessibilityLabel(prompt)
    }
}
