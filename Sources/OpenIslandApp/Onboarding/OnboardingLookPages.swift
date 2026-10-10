import SwiftUI

// The two pages about how the island looks: the opened island's width and
// corners (D35), and the glow (D31).

// MARK: - 8. The opened island

/// Every card draws the island's own shape for the kind of display the
/// island is on, and a click saves the choice for that display. A live page
/// (D44): the real island shows each choice as it is made.
struct OnboardingOpenedPage: View {
    let context: OnboardingPageContext

    private var state: OnboardingState { context.state }

    private static let cardHeight: CGFloat = 96
    private static let artHeight: CGFloat = 62

    var body: some View {
        OnboardingPageScaffold(
            page: .opened,
            context: context,
            title: context.t("onboarding.opened.title"),
            text: context.t("onboarding.opened.body"),
            footnote: context.t("onboarding.opened.note"),
            gap: 12
        ) {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingLiveLine(text: context.t("onboarding.live.line"))

                row(context.t("onboarding.opened.width")) {
                    ForEach(IslandOpenedWidth.allCases) { width in
                        card(
                            title: context.t("settings.appearance.openedLook.width.\(width.rawValue)"),
                            look: IslandOpenedLook(width: width, corners: state.openedLook.corners),
                            isSelected: state.openedLook.width == width
                        ) {
                            context.actions.setOpenedWidth(width)
                        }
                    }
                }

                row(context.t("onboarding.opened.corners")) {
                    ForEach(IslandOpenedCorners.allCases) { corners in
                        card(
                            title: context.t("settings.appearance.openedLook.corners.\(corners.rawValue)"),
                            look: IslandOpenedLook(width: state.openedLook.width, corners: corners),
                            isSelected: state.openedLook.corners == corners
                        ) {
                            context.actions.setOpenedCorners(corners)
                        }
                    }
                }
            }
        }
    }

    private func row<Cards: View>(_ title: String, @ViewBuilder cards: () -> Cards) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OnboardingStyle.secondaryText)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) { cards() }
        }
    }

    private func card(
        title: String,
        look: IslandOpenedLook,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        OnboardingChoiceCard(isSelected: isSelected, showsTick: false, action: action) {
            VStack(spacing: 0) {
                OpenedLookArt(look: look, profile: state.displayProfile)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.artHeight)
                    .padding(.top, 4)
                HStack(spacing: 4) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(OnboardingStyle.paper)
                    }
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(OnboardingStyle.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .frame(height: Self.cardHeight - Self.artHeight - 4, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.cardHeight)
        .accessibilityLabel(title)
    }
}

// MARK: - 9. The glow

/// How strong the glow is, what each of its colors tells, and the themes.
struct OnboardingGlowPage: View {
    let context: OnboardingPageContext

    private var state: OnboardingState { context.state }

    var body: some View {
        OnboardingPageScaffold(
            page: .look,
            context: context,
            title: context.t("onboarding.look.title"),
            text: context.t("onboarding.look.body"),
            footnote: context.t("onboarding.look.note"),
            gap: 14
        ) {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    ForEach(IslandHaloStyle.allCases) { style in strengthCard(style) }
                }

                section(context.t("onboarding.look.legend")) {
                    legend
                }

                section(context.t("onboarding.look.themes")) {
                    OnboardingGlowThemeGrid(selectedID: state.glowThemeID, lang: context.lang) { theme in
                        context.actions.setGlowTheme(theme)
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 7) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OnboardingStyle.secondaryText)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func strengthCard(_ style: IslandHaloStyle) -> some View {
        let sides = OnboardingPillArt.sides(agentsEnabled: state.agentsEnabled)
        return OnboardingChoiceCard(isSelected: state.glowStyle == style) {
            context.actions.setGlowStyle(style)
        } content: {
            VStack(spacing: 0) {
                OnboardingPillArt(
                    width: 170,
                    height: 28,
                    glow: style == .off ? nil : sampleColor,
                    glowStrength: style == .vivid ? 1 : 0.45,
                    left: sides.left,
                    right: sides.right
                )
                .frame(maxWidth: .infinity)
                .frame(height: 66)
                Text(context.t("settings.appearance.nook.halo.\(style.rawValue)"))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(OnboardingStyle.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 11)
            }
        }
        .frame(height: 100)
    }

    /// The color the three sample pills glow in: the first color of the
    /// legend, which is the first moment the user will meet.
    private var sampleColor: Color {
        legendEntries.first?.color ?? OnboardingStyle.waiting
    }

    private var legendEntries: [OnboardingGlowLegendEntry] {
        OnboardingGlowLegendEntry.entries(palette: state.glowPalette, agentsEnabled: state.agentsEnabled)
    }

    /// One small island a moment, glowing in that moment's color, with a
    /// plain name under it. Dimmed while the glow is off.
    private var legend: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(legendEntries) { entry in
                VStack(spacing: 2) {
                    OnboardingPillArt(
                        width: 62,
                        height: 15,
                        glow: entry.color,
                        glowStrength: state.glowStyle == .vivid ? 1 : 0.6,
                        left: .nothing,
                        right: .nothing
                    )
                    .frame(height: 34)
                    Text(context.t(entry.labelKey))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(OnboardingStyle.primaryText.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 108)
                .accessibilityElement(children: .combine)
            }
        }
        .opacity(state.glowStyle == .off ? 0.35 : 1)
    }
}

/// One line of the glow page's legend: a moment and the color the glow
/// takes for it on the display in use.
struct OnboardingGlowLegendEntry: Identifiable, Equatable {
    /// The moment's name in its string key.
    let id: String
    let color: Color

    var labelKey: String { "onboarding.look.legend.\(id)" }

    /// The moments the glow has on this display, in the order they matter.
    /// The four that are an agent's show only with the agents on. A notice
    /// keeps the color it comes with unless the palette gives it one, and
    /// music takes the album's color unless the palette says otherwise.
    static func entries(palette: IslandHaloPalette, agentsEnabled: Bool) -> [OnboardingGlowLegendEntry] {
        var entries: [OnboardingGlowLegendEntry] = []
        if agentsEnabled {
            entries += [
                OnboardingGlowLegendEntry(id: "approval", color: palette.approval.color),
                OnboardingGlowLegendEntry(id: "question", color: palette.question.color),
                OnboardingGlowLegendEntry(id: "completed", color: palette.completed.color),
                OnboardingGlowLegendEntry(id: "running", color: palette.running.color),
            ]
        }
        if let music = palette.music, !palette.musicUsesArtwork {
            entries.append(OnboardingGlowLegendEntry(id: "music", color: music.color))
        } else {
            entries.append(OnboardingGlowLegendEntry(id: "album", color: OnboardingStyle.album))
        }
        if let notice = palette.notice {
            entries.append(OnboardingGlowLegendEntry(id: "notice", color: notice.color))
        } else {
            // The colors a timer that ends and the charger come with.
            entries.append(OnboardingGlowLegendEntry(id: "timer", color: .orange))
            entries.append(OnboardingGlowLegendEntry(id: "charger", color: .green))
        }
        return entries
    }
}

/// The glow themes as a grid of small cards on the tour's glow page: each
/// theme's colors as dots over its name (D31). A click copies the theme's
/// colors to the display the island is on, the same write Settings makes.
struct OnboardingGlowThemeGrid: View {
    let selectedID: String?
    let lang: LanguageManager
    let pick: (IslandHaloTheme) -> Void

    static let columnCount = 6
    static let rowHeight: CGFloat = 46
    private static let spacing: CGFloat = 8

    /// Rows the grid takes for this many themes.
    static func rowCount(themes: Int) -> Int {
        guard themes > 0 else { return 0 }
        return (themes + columnCount - 1) / columnCount
    }

    var body: some View {
        let themes = IslandHaloTheme.all
        VStack(spacing: Self.spacing) {
            ForEach(0..<Self.rowCount(themes: themes.count), id: \.self) { row in
                HStack(spacing: Self.spacing) {
                    ForEach(themes.dropFirst(row * Self.columnCount).prefix(Self.columnCount)) { theme in
                        card(theme)
                    }
                }
            }
        }
    }

    private func card(_ theme: IslandHaloTheme) -> some View {
        let name = lang.t(theme.titleKey)
        let isSelected = selectedID == theme.id
        return Button {
            pick(theme)
        } label: {
            VStack(spacing: 5) {
                GlowThemeSwatches(colors: theme.swatches)
                Text(name)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(isSelected ? OnboardingStyle.primaryText : OnboardingStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 6)
            .frame(width: 124, height: Self.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? OnboardingStyle.selectedFill : OnboardingStyle.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? OnboardingStyle.paper.opacity(0.9) : OnboardingStyle.cardStroke,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
