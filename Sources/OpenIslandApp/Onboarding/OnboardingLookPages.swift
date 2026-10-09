import SwiftUI

/// The tour's page for how the opened island looks: its width and its
/// corners (D35). Every card draws the island's own shape for the kind of
/// display the island is on, and a click saves the choice for that display.
struct OnboardingOpenedPage: View {
    let state: OnboardingState
    let actions: OnboardingActions
    let lang: LanguageManager

    private static let cardWidth: CGFloat = 250
    private static let cardHeight: CGFloat = 104

    var body: some View {
        VStack(spacing: 14) {
            OnboardingHeading(title: lang.t("onboarding.opened.title"), text: lang.t("onboarding.opened.body"))

            row(lang.t("onboarding.opened.width")) {
                ForEach(IslandOpenedWidth.allCases) { width in
                    card(
                        title: lang.t("settings.appearance.openedLook.width.\(width.rawValue)"),
                        look: IslandOpenedLook(width: width, corners: state.openedLook.corners),
                        isSelected: state.openedLook.width == width
                    ) {
                        actions.setOpenedWidth(width)
                    }
                }
            }

            row(lang.t("onboarding.opened.corners")) {
                ForEach(IslandOpenedCorners.allCases) { corners in
                    card(
                        title: lang.t("settings.appearance.openedLook.corners.\(corners.rawValue)"),
                        look: IslandOpenedLook(width: state.openedLook.width, corners: corners),
                        isSelected: state.openedLook.corners == corners
                    ) {
                        actions.setOpenedCorners(corners)
                    }
                }
            }

            Text(lang.t("onboarding.opened.note"))
                .font(.system(size: 11.5))
                .foregroundStyle(OnboardingStyle.faintText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func row<Cards: View>(_ title: String, @ViewBuilder cards: () -> Cards) -> some View {
        VStack(spacing: 7) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OnboardingStyle.secondaryText)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 12) { cards() }
        }
    }

    private func card(
        title: String,
        look: IslandOpenedLook,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        OnboardingChoiceCard(isSelected: isSelected, action: action) {
            VStack(spacing: 0) {
                OpenedLookArt(look: look, profile: state.displayProfile)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity)
                    .frame(height: 68)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OnboardingStyle.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.cardHeight - 68, alignment: .center)
            }
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .accessibilityLabel(title)
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
            .frame(width: 118, height: Self.rowHeight)
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
