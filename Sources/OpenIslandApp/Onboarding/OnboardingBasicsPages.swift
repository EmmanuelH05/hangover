import SwiftUI

// The first part of the tour: what the island is, what it is for and how
// it opens.

// MARK: - 1. Welcome

/// Says what Hangover is in three pictures. Nothing to choose here.
struct OnboardingWelcomePage: View {
    let context: OnboardingPageContext

    private static let artSize = CGSize(width: 232, height: 184)

    var body: some View {
        OnboardingPageScaffold(
            page: .welcome,
            context: context,
            title: context.t("onboarding.welcome.title"),
            text: context.t("onboarding.welcome.body"),
            footnote: context.t("onboarding.welcome.note"),
            gap: 22
        ) {
            HStack(alignment: .top, spacing: 0) {
                step(1, "lives") { closedArt(showsPointer: false) }
                arrow
                step(2, "point") { closedArt(showsPointer: true) }
                arrow
                step(3, "opens") {
                    OnboardingScreenArt(marks: 1) {
                        OnboardingOpenedArt(width: 156)
                    }
                }
            }
        }
    }

    /// The name of the first step says where the island sits on this kind
    /// of display.
    private func titleKey(_ name: String) -> String {
        name == "lives" && context.state.displayProfile == .topBar
            ? "onboarding.welcome.step.lives.title.topBar"
            : "onboarding.welcome.step.\(name).title"
    }

    private func step<Art: View>(_ number: Int, _ name: String, @ViewBuilder art: () -> Art) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            art()
                .frame(width: Self.artSize.width, height: Self.artSize.height)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(OnboardingStyle.ink)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(OnboardingStyle.paper))
                Text(context.t(titleKey(name)))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OnboardingStyle.primaryText)
            }
            .padding(.top, 14)
            Text(context.t("onboarding.welcome.step.\(name).text"))
                .font(.system(size: 12.5))
                .foregroundStyle(OnboardingStyle.secondaryText)
                .lineSpacing(1.5)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
        .padding(12)
        .frame(width: Self.artSize.width + 24, alignment: .topLeading)
        .frame(height: 334, alignment: .top)
        .background(OnboardingCardBackground())
        .accessibilityElement(children: .combine)
    }

    private var arrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(OnboardingStyle.faintText)
            .frame(width: 34)
            .padding(.top, 96)
            .accessibilityHidden(true)
    }

    private func closedArt(showsPointer: Bool) -> some View {
        OnboardingScreenArt(marks: 1) {
            OnboardingPillArt(
                width: 124,
                height: 24,
                glow: showsPointer ? OnboardingStyle.album : nil,
                glowStrength: 0.6,
                left: .art,
                right: .nothing
            )
            .padding(.top, 3)
            .overlay(alignment: .bottomTrailing) {
                if showsPointer {
                    Image(systemName: "cursorarrow.rays")
                        .font(.system(size: 22))
                        .foregroundStyle(OnboardingStyle.paper)
                        .offset(x: 4, y: 24)
                }
            }
        }
    }
}

// MARK: - 2. What it is for

/// The agents switch (D41), asked as a question with a picture for each
/// answer. It writes the same preference as the switch in Settings.
struct OnboardingPurposePage: View {
    let context: OnboardingPageContext

    var body: some View {
        OnboardingPageScaffold(
            page: .purpose,
            context: context,
            title: context.t("onboarding.purpose.title"),
            text: context.t("onboarding.purpose.body"),
            footnote: context.t("onboarding.purpose.note"),
            gap: 20
        ) {
            HStack(spacing: 16) {
                card(withAgents: false)
                card(withAgents: true)
            }
        }
    }

    private func card(withAgents: Bool) -> some View {
        let name = withAgents ? "agents" : "day"
        let title = context.t("onboarding.purpose.\(name).title")
        return OnboardingChoiceCard(isSelected: context.state.agentsEnabled == withAgents) {
            context.actions.setAgentsEnabled(withAgents)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                OnboardingScreenArt(marks: 2) {
                    OnboardingOpenedArt(width: 236, showsAgentCard: withAgents)
                }
                .frame(height: 208)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OnboardingStyle.primaryText)
                    .padding(.top, 14)
                Text(context.t("onboarding.purpose.\(name).text"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(OnboardingStyle.secondaryText)
                    .lineSpacing(1.5)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            .padding(14)
        }
        .frame(height: 350)
        .accessibilityLabel(title)
    }
}

// MARK: - 3. Opening the island

struct OnboardingOpeningPage: View {
    let context: OnboardingPageContext

    private var state: OnboardingState { context.state }

    var body: some View {
        OnboardingPageScaffold(
            page: .opening,
            context: context,
            title: context.t("onboarding.opening.title"),
            text: context.t("onboarding.opening.body"),
            footnote: context.t("onboarding.opening.note"),
            gap: 20
        ) {
            VStack(spacing: 18) {
                HStack(spacing: 16) {
                    ForEach(IslandOpenTrigger.allCases) { trigger in
                        OnboardingChoiceCard(isSelected: state.openTrigger == trigger) {
                            context.actions.setOpenTrigger(trigger)
                        } content: {
                            VStack(alignment: .leading, spacing: 10) {
                                triggerArt(trigger)
                                Text(context.t(trigger.titleKey))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(OnboardingStyle.primaryText)
                                Text(context.t(trigger.noteKey))
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(OnboardingStyle.secondaryText)
                                    .lineSpacing(1.5)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(16)
                        }
                        .frame(height: 256)
                    }
                }

                VStack(spacing: 7) {
                    tryItLine
                    OnboardingNote(text: context.t(IslandOpenTrigger.filesNoteKey))
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    /// Invites the user to open the real island, and answers when they do.
    /// The answer stays once it is given: the island closing again does not
    /// take it back.
    private var tryItLine: some View {
        let hasTried = state.hasOpenedIsland || state.isIslandOpen
        let key = hasTried
            ? "onboarding.opening.tried"
            : (state.openTrigger == .hover ? "onboarding.opening.try.hover" : "onboarding.opening.try.click")
        return HStack(spacing: 7) {
            Image(systemName: hasTried ? "checkmark.circle.fill" : "arrow.up")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hasTried ? OnboardingStyle.finished : OnboardingStyle.paper)
            Text(context.t(key))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(OnboardingStyle.primaryText)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Capsule().fill(Color.white.opacity(hasTried ? 0.06 : 0.1)))
        .accessibilityElement(children: .combine)
    }

    /// The closed island and the pointer doing what opens it.
    private func triggerArt(_ trigger: IslandOpenTrigger) -> some View {
        OnboardingScreenArt(marks: 3) {
            OnboardingPillArt(width: 150, height: 26, glow: nil, left: .nothing, right: .nothing)
                .padding(.top, 2)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: trigger == .hover ? "cursorarrow.rays" : "cursorarrow.click.2")
                        .font(.system(size: 24))
                        .foregroundStyle(OnboardingStyle.paper)
                        .offset(x: 2, y: 26)
                }
        }
        .frame(height: 120)
    }
}
