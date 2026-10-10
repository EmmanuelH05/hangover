import SwiftUI

/// The card under the island on the widgets page: the selected widget's
/// picture and name, and a few lines on what it can do beyond the obvious.
/// A widget that is off gets its card too, with a note that says it is off.
/// Every line is an `OnboardingAbility`, tied to its code.
struct OnboardingSpotlightCard: View {
    let kind: NookWidgetKind
    let isOn: Bool
    let context: OnboardingPageContext

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                OnboardingSymbolPlate(symbol: kind.systemImage, size: 28)
                Text(context.t("onboarding.nook.widget.\(kind.rawValue)"))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(OnboardingStyle.primaryText)
                Spacer(minLength: 6)
                if !isOn {
                    Text(context.t("onboarding.widgets.spotlight.off"))
                        .font(.system(size: 11))
                        .foregroundStyle(OnboardingStyle.faintText)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(OnboardingAbility.lines(for: kind)) { ability in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Circle()
                            .fill(OnboardingStyle.paper.opacity(0.7))
                            .frame(width: 4, height: 4)
                            .offset(y: -2.5)
                        Text(context.t(ability.textKey))
                            .font(.system(size: 11.5))
                            .foregroundStyle(OnboardingStyle.primaryText.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .background(OnboardingCardBackground())
        .accessibilityElement(children: .combine)
    }
}
