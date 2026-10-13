import SwiftUI

/// One switch of a Good to know page: the tour's own switch card, the way the
/// glow page's beat switch is. Its name is Settings' own, the line under it
/// says what it does and what macOS will ask before the flip, and the flip
/// writes through the door the switch in Settings uses. The state is read
/// from the app, never kept here.
struct OnboardingMoreSwitchRow: View {
    let context: OnboardingPageContext
    let item: OnboardingMoreSwitch

    private var reading: OnboardingMoreReading { context.state.more }

    static let cardHeight: CGFloat = 62

    var body: some View {
        let isOn = reading.isOn(item)
        let isEnabled = reading.isEnabled(item)
        let title = context.t(item.titleKey)
        VStack(spacing: 6) {
            OnboardingChoiceCard(isSelected: isOn, showsTick: false) {
                context.actions.setMore(item, !isOn)
            } content: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(OnboardingStyle.primaryText)
                        Text(context.t(item.lineKey))
                            .font(.system(size: 11.5))
                            .foregroundStyle(OnboardingStyle.secondaryText)
                            .lineSpacing(1.5)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    OnboardingSwitchArt(isOn: isOn)
                }
                .padding(.horizontal, 14)
                .frame(maxHeight: .infinity)
            }
            .frame(height: Self.cardHeight)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.45)
            .accessibilityLabel(title)
            .accessibilityValue(context.t(isOn ? "onboarding.widgets.switch.on" : "onboarding.widgets.switch.off"))

            if item == .volumeKeys { keysStatus }
        }
    }

    /// Where the keys stand, as the Settings section shows it: waiting for
    /// the grant, with the button that asks again, or refused by macOS.
    @ViewBuilder
    private var keysStatus: some View {
        switch reading.keys {
        case .off, .active:
            EmptyView()
        case .waiting:
            VStack(spacing: 4) {
                HStack(spacing: 10) {
                    Text(context.t("nook.volume.settings.keys.waiting"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(OnboardingStyle.primaryText)
                    Button(context.t("nook.volume.settings.keys.openSettings")) {
                        context.actions.requestKeysAccess()
                    }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                }
                if reading.keysAccessWasMissingAtLaunch {
                    Text(context.t("nook.volume.settings.keys.stale"))
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .unavailable:
            Text(context.t("nook.volume.settings.keys.unavailable"))
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        }
    }
}
