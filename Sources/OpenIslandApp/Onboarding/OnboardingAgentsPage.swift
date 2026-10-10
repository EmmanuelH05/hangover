import SwiftUI

/// The tour's page for connecting coding agents, shown only while the
/// agents switch is on (D41): a picture of the card an agent's request
/// shows, the two shortcuts that answer it, and a Connect button for each
/// of the common agents.
struct OnboardingAgentsPage: View {
    let context: OnboardingPageContext

    private var state: OnboardingState { context.state }

    var body: some View {
        OnboardingPageScaffold(
            page: .agents,
            context: context,
            title: context.t("onboarding.agents.title"),
            text: context.t("onboarding.agents.body"),
            gap: 20
        ) {
            HStack(alignment: .top, spacing: 18) {
                approvalPicture
                    .frame(width: 360)
                connectList
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// A picture of the card an agent's request shows, with the two
    /// shortcuts under it. The buttons in it are drawn, not live.
    private var approvalPicture: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(context.t("onboarding.agents.card.title"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OnboardingStyle.primaryText)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Circle().fill(OnboardingStyle.waiting).frame(width: 8, height: 8)
                    Text("Claude Code")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(OnboardingStyle.primaryText)
                    Text(context.t("onboarding.agents.card.asks"))
                        .font(.system(size: 12))
                        .foregroundStyle(OnboardingStyle.secondaryText)
                        .lineLimit(1)
                }
                Text("npm test")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(OnboardingStyle.primaryText)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.07)))
                HStack(spacing: 8) {
                    pictureButton(context.t("approval.deny"), filled: false)
                    pictureButton(context.t("approval.allowOnce"), filled: true)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(OnboardingStyle.waiting.opacity(0.45), lineWidth: 1)
            )
            .accessibilityHidden(true)

            shortcuts
        }
    }

    private func pictureButton(_ title: String, filled: Bool) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(filled ? OnboardingStyle.ink : OnboardingStyle.primaryText)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(filled ? OnboardingStyle.paper : Color.white.opacity(0.1))
            )
    }

    @ViewBuilder
    private var shortcuts: some View {
        if state.approveKeys == nil, state.denyKeys == nil {
            OnboardingNote(text: context.t("onboarding.agents.keys.off"))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                OnboardingNote(text: context.t("onboarding.agents.keys.title"))
                if let caps = state.approveKeys {
                    shortcutRow(caps, context.t("onboarding.agents.keys.approve"))
                }
                if let caps = state.denyKeys {
                    shortcutRow(caps, context.t("onboarding.agents.keys.deny"))
                }
            }
        }
    }

    private func shortcutRow(_ caps: [String], _ text: String) -> some View {
        HStack(spacing: 8) {
            OnboardingKeyCaps(caps: caps)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(OnboardingStyle.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var connectList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(context.t("onboarding.agents.connect.title"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OnboardingStyle.primaryText)

            VStack(spacing: 0) {
                ForEach(Array(OnboardingAgent.allCases.enumerated()), id: \.element) { index, agent in
                    if index > 0 { OnboardingDivider() }
                    agentRow(agent)
                }
            }
            .background(OnboardingCardBackground())

            if let failed = failedAgentNames {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(OnboardingStyle.waiting)
                    Text(context.lang.t("onboarding.agents.failed.note", failed))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(OnboardingStyle.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            } else {
                OnboardingNote(text: context.t("onboarding.agents.connect.note"))
            }

            Button(context.t("onboarding.agents.all")) { context.actions.showAllAgents() }
                .buttonStyle(OnboardingSecondaryButtonStyle(height: 28))
        }
    }

    private func agentRow(_ agent: OnboardingAgent) -> some View {
        let status = state.status(of: agent)
        return HStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(OnboardingStyle.secondaryText)
                .frame(width: 18)
            Text(agent.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(OnboardingStyle.primaryText)
            Spacer(minLength: 8)
            if status.isConnected {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(OnboardingStyle.finished)
                    Text(context.t("onboarding.agents.connected"))
                        .foregroundStyle(OnboardingStyle.secondaryText)
                }
                .font(.system(size: 12, weight: .medium))
            } else if status.isBusy {
                Text(context.t("onboarding.agents.connecting"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OnboardingStyle.secondaryText)
            } else {
                if status.didFail {
                    Text(context.t("onboarding.agents.failed"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(OnboardingStyle.waiting)
                        .lineLimit(1)
                }
                let title = context.t(status.didFail ? "onboarding.agents.retry" : "onboarding.agents.connect")
                Button(title) { context.actions.connect(agent) }
                    .buttonStyle(OnboardingSecondaryButtonStyle(height: 26))
                    .disabled(!status.canConnect)
                    .opacity(status.canConnect ? 1 : 0.4)
                    .accessibilityLabel("\(title) \(agent.name)")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
    }

    /// The agents whose Connect did not work, by name, or nil when none
    /// failed.
    private var failedAgentNames: String? {
        let names = OnboardingAgent.allCases.filter { state.status(of: $0).didFail }.map(\.name)
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }
}
