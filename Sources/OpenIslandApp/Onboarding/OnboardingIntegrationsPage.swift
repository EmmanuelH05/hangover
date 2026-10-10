import SwiftUI

// MARK: - 11. Integrations

/// A card for each outside thing the app works with: what the connection
/// does and where it is set up. The page only tells. It has no button and
/// asks macOS for nothing. The agents and the terminals show only while
/// the agents switch is on (D41).
struct OnboardingIntegrationsPage: View {
    let context: OnboardingPageContext

    private static let columnCount = 5
    private static let spacing: CGFloat = 10

    var body: some View {
        let cards = OnboardingIntegration.shown(agentsEnabled: context.state.agentsEnabled)
        OnboardingPageScaffold(
            page: .integrations,
            context: context,
            title: context.t("onboarding.integrations.title"),
            text: context.t("onboarding.integrations.body"),
            footnote: context.t("onboarding.integrations.note"),
            gap: 18
        ) {
            VStack(spacing: Self.spacing) {
                ForEach(Array(Self.rows(cards).enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: Self.spacing) {
                        ForEach(row) { integration in card(integration) }
                    }
                }
            }
        }
    }

    /// The cards in rows of five.
    static func rows(_ cards: [OnboardingIntegration]) -> [[OnboardingIntegration]] {
        stride(from: 0, to: cards.count, by: columnCount).map {
            Array(cards[$0..<min($0 + columnCount, cards.count)])
        }
    }

    /// The line under a card's name. The agents card lists the agents the
    /// tour knows, and the Setup tab has the rest.
    private func text(_ integration: OnboardingIntegration) -> String {
        guard integration == .agents else { return context.t(integration.textKey) }
        let names = OnboardingAgent.allCases.map(\.name).joined(separator: ", ")
        return context.lang.t(integration.textKey, names)
    }

    private func card(_ integration: OnboardingIntegration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingSymbolPlate(symbol: integration.symbol, size: 30)
            Text(context.t(integration.nameKey))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OnboardingStyle.primaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)
            Text(text(integration))
                .font(.system(size: 11))
                .foregroundStyle(OnboardingStyle.secondaryText)
                .lineSpacing(1.5)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            Spacer(minLength: 4)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "gearshape")
                    .font(.system(size: 8.5, weight: .semibold))
                Text(context.t(integration.whereKey))
                    .font(.system(size: 10.5))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(OnboardingStyle.faintText)
        }
        .padding(12)
        .frame(width: 158.4, height: 186, alignment: .topLeading)
        .background(OnboardingCardBackground())
        .accessibilityElement(children: .combine)
    }
}
