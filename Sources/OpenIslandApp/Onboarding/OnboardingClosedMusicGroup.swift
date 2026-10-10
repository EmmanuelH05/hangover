import SwiftUI

/// The closed page's third group, "While music plays": the three media
/// styles of Settings' section 04 as cards, then each of its switches that
/// the display and the agents switch leave in (`NookClosedMusicOption`).
/// A tap writes what Settings writes.
struct OnboardingClosedMusicGroup: View {
    let context: OnboardingPageContext
    /// The width of a style card, shared with the groups above.
    let cardWidth: CGFloat

    private var state: OnboardingState { context.state }
    private var music: OnboardingClosedMusic { state.closedMusic }

    private static let optionMaxWidth: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            OnboardingClosedGroupTitle(text: context.t("onboarding.closed.music.title"))
            HStack(spacing: OnboardingClosedPage.cardGap) {
                ForEach(NookClosedMediaStyle.allCases) { style in
                    OnboardingClosedCard(
                        title: context.t(Self.titleKey(of: style)),
                        hint: context.t("onboarding.closed.music.\(style.rawValue).note"),
                        isSelected: music.style == style,
                        action: { context.actions.setClosedMusic(.style(style)) }
                    ) {
                        Self.styleArt(style)
                    }
                    .frame(width: cardWidth, height: OnboardingClosedPage.cardHeight)
                }
                ForEach(options) { option in optionCard(option) }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The switches Settings lists on this display, in its order.
    var options: [NookClosedMusicOption] {
        NookClosedMusicOption.offered(agentsEnabled: state.agentsEnabled, profile: state.displayProfile)
    }

    /// The same names Settings gives the three styles.
    static func titleKey(of style: NookClosedMediaStyle) -> String {
        "settings.appearance.nook.media.\(style.rawValue)"
    }

    private func optionCard(_ option: NookClosedMusicOption) -> some View {
        let isOn = music.onOptions.contains(option)
        let isEnabled = option.isEnabled(whenStyle: music.style)
        let title = context.t(option.titleKey)
        return OnboardingChoiceCard(
            isSelected: false,
            action: { context.actions.setClosedMusic(.option(option, isOn: !isOn)) }
        ) {
            HStack(spacing: 4) {
                OnboardingSwitchArt(isOn: isOn)
                    .scaleEffect(0.65)
                    .frame(width: 26, height: 16)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(OnboardingStyle.primaryText.opacity(0.9))
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .frame(maxWidth: Self.optionMaxWidth)
        .frame(height: OnboardingClosedPage.cardHeight)
        .accessibilityLabel(title)
        .accessibilityValue(context.t(isOn ? "onboarding.closed.music.on" : "onboarding.closed.music.off"))
    }

    /// What the style does to the pill: art on the left and a visualizer on
    /// the right, art alone, or nothing.
    @ViewBuilder
    private static func styleArt(_ style: NookClosedMediaStyle) -> some View {
        switch style {
        case .artAndVisual:
            HStack(spacing: 5) {
                OnboardingPillSideArt(side: .art, height: 40, tint: nil)
                OnboardingBarsArt(color: OnboardingStyle.album)
                    .frame(width: 12, height: 12)
            }
        case .artOnly:
            OnboardingPillSideArt(side: .art, height: 40, tint: nil)
        case .off:
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 16, height: 3)
        }
    }
}
