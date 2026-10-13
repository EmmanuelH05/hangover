import SwiftUI

/// "06 · Accent color" on the Personalization tab (D62): Default, System and
/// Apple's eight colors as tiles with a round swatch, and under them a small
/// sample of what the accent colors.
///
/// Its neighbors are stored per display. This one choice is for the whole
/// app, which its note says.
struct AccentColorSection: View, Equatable {
    let lang: LanguageManager
    let languageCode: String
    let choice: HangoverAccentChoice
    /// What macOS is set to, for the System tile's swatch. Nil before the
    /// first reading.
    let systemColor: IslandHaloRGB?
    let pick: (HangoverAccentChoice) -> Void

    @Namespace private var ring

    private static let columns = [GridItem(.adaptive(minimum: 84), spacing: 10)]

    /// The action is fixed, and two sections that would draw the same are
    /// equal, which keeps a tap elsewhere in the pane from touching this one.
    nonisolated static func == (lhs: AccentColorSection, rhs: AccentColorSection) -> Bool {
        lhs.languageCode == rhs.languageCode && lhs.choice == rhs.choice && lhs.systemColor == rhs.systemColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PersonalizationSectionHeader(
                title: lang.t("settings.appearance.accent.title"),
                note: lang.t("settings.appearance.accent.note")
            )

            LazyVGrid(columns: Self.columns, spacing: 10) {
                ForEach(HangoverAccentChoice.allCases) { option in
                    PersonalizationCard(
                        title: lang.t(option.titleKey),
                        selected: option == choice,
                        ringNamespace: ring,
                        ringGroup: "accent",
                        action: { pick(option) }
                    ) {
                        AccentSwatch(choice: option, systemColor: systemColor)
                    }
                }
            }

            AccentSample(
                today: lang.t("settings.appearance.accent.sample.today"),
                todo: lang.t("settings.appearance.accent.sample.todo"),
                button: lang.t("settings.appearance.accent.sample.button")
            )
        }
    }
}

extension AppearanceSettingsPane {
    /// The status glow, and after it the accent color, which is not the
    /// Nook's and is not kept per display.
    @ViewBuilder
    var glowAndAccentSections: some View {
        nookHost { nookHaloSection }
        accentSection
    }

    /// One choice for the whole app, which is why it reads the model and
    /// not the display being edited (D62).
    private var accentSection: some View {
        AccentColorSection(
            lang: lang,
            languageCode: lang.language.resolvedCode,
            choice: model.accent.choice,
            systemColor: model.accent.system.accent
        ) { [model] choice in
            withMotion(Motion.selection) { model.accent.choice = choice }
        }
        .equatable()
    }
}

/// One choice as a round swatch. Default shows the two colors today's look
/// highlights with, and System shows the color macOS is set to under a gear.
struct AccentSwatch: View {
    let choice: HangoverAccentChoice
    let systemColor: IslandHaloRGB?

    static let size: CGFloat = 22
    /// What System shows before macOS has been read: Apple's gray.
    static let unreadSystem = IslandHaloRGB(rgb: 0x98989D)

    var body: some View {
        fill
            .frame(width: Self.size, height: Self.size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.black.opacity(0.4), lineWidth: 1))
            .overlay { if choice == .system { gear } }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var fill: some View {
        switch choice {
        case .standard:
            HStack(spacing: 0) {
                V6Palette.paper
                Color.orange
            }
        case .system:
            (systemColor ?? Self.unreadSystem).color
        default:
            (choice.fixedColor ?? Self.unreadSystem).color
        }
    }

    private var gear: some View {
        let tone = HangoverAccent.textTone(on: systemColor ?? Self.unreadSystem)
        return Image(systemName: "gearshape.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tone == .ink ? V6Palette.ink : Color.white)
    }
}

/// Four of the things the accent colors, drawn the way the island draws
/// them: the scrub bar, today's date, a task just checked off and a main
/// button. It reads the accent from the environment like the real ones do,
/// which makes a pick show here at once.
struct AccentSample: View {
    let today: String
    let todo: String
    let button: String

    @Environment(\.hangoverAccent) private var accent

    private static let scrubFraction: CGFloat = 0.42
    private static let sampleDay = 12

    var body: some View {
        HStack(spacing: 18) {
            scrubBar
            labeled(today) {
                Text("\(Self.sampleDay)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent.highlight(.orange))
            }
            labeled(todo) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(accent.highlight(.white.opacity(0.6)))
            }
            Text(button)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent.textOnHighlight(.black).opacity(0.85))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 24)
                .background(Capsule().fill(accent.highlight(.orange)))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private var scrubBar: some View {
        NookSampleProgress(fraction: Self.scrubFraction)
            .frame(minWidth: 80, maxWidth: 160)
    }

    private func labeled<Mark: View>(_ title: String, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(spacing: 6) {
            mark()
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.55))
                .lineLimit(1)
        }
    }
}
