import SwiftUI

// Reusable controls for the Personalization tab. They replace the copy-pasted
// card chromes in `AppearanceSettingsPane` and add hover, press and selection
// feedback. Every animation comes from `Motion` (D16), so Reduce Motion is
// handled in one place.

// MARK: - Card

/// A selectable card in three layouts: a `tile` (icon box above a one-line
/// title), a `row` (icon, title, note and a checkmark) and a `panel` (the
/// card's chrome around content the caller draws). The fill moves between
/// rest, hover and selected levels, and the selection ring is its own
/// overlay so selecting never shifts the layout. Cards that share a
/// `ringNamespace` and `ringGroup` pass one ring between them.
struct PersonalizationCard<Icon: View>: View {
    enum Style: Equatable, Sendable {
        case tile
        case row(note: String)
        /// The icon builder draws the whole card. `title` names the card
        /// for accessibility only.
        case panel
    }

    let title: String
    let selected: Bool
    let style: Style
    let ringNamespace: Namespace.ID?
    let ringGroup: String
    let action: () -> Void
    private let icon: Icon

    @State private var isHovering = false
    @State private var checkBounce = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        selected: Bool,
        style: Style = .tile,
        ringNamespace: Namespace.ID? = nil,
        ringGroup: String = "",
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) {
        self.title = title
        self.selected = selected
        self.style = style
        self.ringNamespace = ringNamespace
        self.ringGroup = ringGroup
        self.action = action
        self.icon = icon()
    }

    var body: some View {
        Button(action: action) {
            content
                .padding(tokens.padding)
                .frame(maxWidth: .infinity, alignment: tokens.alignment)
                .background(fill)
                .overlay(hairline)
                .overlay(selectionRing)
                .contentShape(cardShape)
                .onHover { isHovering = $0 }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Tokens

    private struct Tokens {
        let padding: CGFloat
        let alignment: Alignment
        let restFill: Double
        let selectedFill: Double
    }

    private static var hoverFill: Double { 0.045 }

    private var tokens: Tokens {
        switch style {
        case .tile: Tokens(padding: 12, alignment: .center, restFill: 0.02, selectedFill: 0.07)
        case .row: Tokens(padding: 14, alignment: .leading, restFill: 0.025, selectedFill: 0.075)
        case .panel: Tokens(padding: 12, alignment: .leading, restFill: 0.025, selectedFill: 0.075)
        }
    }

    private var fillOpacity: Double {
        if selected { return tokens.selectedFill }
        return isHovering ? Self.hoverFill : tokens.restFill
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    // MARK: Chrome

    private var fill: some View {
        cardShape
            .fill(Color.white.opacity(fillOpacity))
            .motionAnimation(Motion.hover, value: isHovering)
            .motionAnimation(Motion.selection, value: selected)
    }

    private var hairline: some View {
        cardShape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
    }

    private var ring: some View {
        cardShape.strokeBorder(V6Palette.paper.opacity(0.9), lineWidth: 1.5)
    }

    @ViewBuilder
    private var selectionRing: some View {
        if let ringNamespace, !reduceMotion {
            // Only the selected card holds the ring, so it slides from the
            // card that lost it to the card that gained it.
            ZStack {
                if selected {
                    ring
                        .matchedGeometryEffect(id: ringGroup, in: ringNamespace)
                        .transition(.opacity)
                }
            }
            .motionAnimation(Motion.selection, value: selected)
        } else {
            ring
                .opacity(selected ? 1 : 0)
                .motionAnimation(Motion.selection, value: selected)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch style {
        case .tile: tileContent
        case .row(let note): rowContent(note: note)
        case .panel: icon.accessibilityElement(children: .ignore).accessibilityLabel(title)
        }
    }

    private var tileContent: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                icon
            }
            .frame(height: 56)

            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func rowContent(note: String) -> some View {
        HStack(spacing: 12) {
            icon
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(selected ? V6Palette.paper : V6Palette.paper.opacity(0.55))
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(selected ? 0.11 : 0.05))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.94))
                Text(note)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(V6Palette.paper.opacity(0.42))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.9))
                    .symbolEffect(.bounce, value: checkBounce)
                    .transition(Motion.transition(.scale.combined(with: .opacity), reduceMotion: reduceMotion))
            }
        }
        .motionAnimation(Motion.selection, value: selected)
        // The checkmark is inserted by `if selected`, so it can never see
        // `selected` change. This counter is bumped right after it appears,
        // which gives `.symbolEffect` a value change to react to.
        .onChange(of: selected) { _, isSelected in
            if isSelected && !reduceMotion { checkBounce += 1 }
        }
    }
}

// MARK: - Chip

/// A small monospaced capsule. Selected chips are solid paper; unselected
/// chips brighten under the pointer. Fill and text color cross-fade.
struct MonoChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    @State private var isHovering = false

    init(title: String, selected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.selected = selected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(selected ? V6Palette.ink : V6Palette.paper.opacity(0.7))
                .background(Capsule().fill(fillColor))
                .motionAnimation(Motion.selection, value: selected)
                .motionAnimation(Motion.hover, value: isHovering)
                .contentShape(Capsule())
                .onHover { isHovering = $0 }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var fillColor: Color {
        if selected { return V6Palette.paper }
        return Color.white.opacity(isHovering ? 0.1 : 0.06)
    }
}

// MARK: - Section header

/// The small uppercase monospaced title with an optional note underneath.
struct PersonalizationSectionHeader: View {
    let title: String
    let note: String?

    init(title: String, note: String?) {
        self.title = title
        self.note = note
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.55))
            if let note {
                Text(note)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.38))
            }
        }
    }
}

// MARK: - Toggle row

/// A switch row drawn in the Personalization card style. Dimming and
/// disabling are animated together, and the row washes lighter under the
/// pointer while it is enabled.
struct PersonalizationToggleRow: View {
    let title: String
    let note: String
    @Binding var isOn: Bool
    var isEnabled: Bool = true

    init(title: String, note: String, isOn: Binding<Bool>, isEnabled: Bool = true) {
        self.title = title
        self.note = note
        self._isOn = isOn
        self.isEnabled = isEnabled
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.88))
                Text(note)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .hoverHighlight(cornerRadius: 12)
        .allowsHitTesting(isEnabled)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .motionAnimation(Motion.toggleEnable, value: isEnabled)
    }
}
