import SwiftUI

/// One card of the closed page: what it is called, what it says and the
/// picture it draws in the pill. The left and the right side share the card.
struct OnboardingClosedChoice: Identifiable, Equatable {
    let id: String
    let titleKey: String
    let noteKey: String
    let art: OnboardingPillSide
    let isSelected: Bool
    let need: OnboardingClosedNeed?
}

/// The tour's page for the closed island (D43): a row of cards for each
/// side and for the music, every choice Settings offers for it, a line under
/// each side that says what a choice needs, and a line that points at the
/// real notch (D44). A click writes what the cards in Personalization write
/// (D39 for the right, the left slot for the left, section 04 for the music).
struct OnboardingClosedPage: View {
    let context: OnboardingPageContext

    private var state: OnboardingState { context.state }

    /// Ten cards to a row is the most either side has (agents on). The
    /// width is shared by every group, which lines the rows up.
    static let maxCardWidth: CGFloat = 112
    static let cardHeight: CGFloat = 74
    static let cardGap: CGFloat = 6

    var body: some View {
        OnboardingPageScaffold(
            page: .closed,
            context: context,
            title: context.t("onboarding.closed.title"),
            text: context.t("onboarding.closed.body"),
            footnote: context.t("onboarding.closed.note"),
            gap: 10
        ) {
            VStack(spacing: 12) {
                // The closed island is at the top of the screen, outside this
                // window. Its picture is the real one.
                OnboardingLiveLine(text: context.t("onboarding.closed.line"))
                    .frame(maxWidth: 560)

                group(titleKey: "onboarding.closed.left.title", choices: leftChoices) { id in
                    OnboardingClosedLeft(rawValue: id).map(context.actions.setClosedLeft)
                }
                group(titleKey: "onboarding.closed.right.title", choices: rightChoices) { id in
                    OnboardingClosedSide(rawValue: id).map(context.actions.setClosedSide)
                }
                OnboardingClosedMusicGroup(context: context, cardWidth: cardWidth)

                if state.closedSide == nil {
                    OnboardingNote(text: context.t("onboarding.closed.own"))
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    // MARK: Choices

    /// The left side's cards, the ones Settings offers for it.
    var leftChoices: [OnboardingClosedChoice] {
        OnboardingClosedLeft.offered(agentsEnabled: state.agentsEnabled).map { left in
            OnboardingClosedChoice(
                id: left.rawValue,
                titleKey: left.titleKey,
                noteKey: left.noteKey,
                art: Self.leftPillSide(left),
                isSelected: state.closedLeft == left,
                need: left.need
            )
        }
    }

    /// The right side's cards, the ones Settings offers for it.
    var rightChoices: [OnboardingClosedChoice] {
        OnboardingClosedSide.offered(agentsEnabled: state.agentsEnabled).map { side in
            OnboardingClosedChoice(
                id: side.rawValue,
                titleKey: side.titleKey,
                noteKey: side.noteKey,
                art: Self.pillSide(side),
                isSelected: state.closedSide == side,
                need: side.need
            )
        }
    }

    /// The width of every card: as wide as the most crowded row allows.
    var cardWidth: CGFloat {
        let count = CGFloat(max(leftChoices.count, rightChoices.count))
        let room = OnboardingStyle.contentWidth - Self.cardGap * (count - 1)
        return min(Self.maxCardWidth, (room / count).rounded(.down))
    }

    /// The drawing for a right-side pick. A pick made in Settings that the
    /// tour does not offer draws as an empty side.
    static func pillSide(_ side: OnboardingClosedSide?) -> OnboardingPillSide {
        switch side {
        case .count: .count
        case .agents: .agents
        case .bars: .bars
        case .date: .date
        case .battery: .battery
        case .countdown: .countdown
        case .weather: .weather
        case .timer: .timer
        case .todos: .todos
        case .nothing, nil: .nothing
        }
    }

    /// The drawing for a left-side pick.
    static func leftPillSide(_ left: OnboardingClosedLeft) -> OnboardingPillSide {
        switch left {
        case .bars: .bars
        case .count: .count
        case .grid: .grid
        case .date: .date
        case .battery: .battery
        case .countdown: .countdown
        case .weather: .weather
        case .timer: .timer
        case .todos: .todos
        case .nothing: .nothing
        }
    }

    // MARK: Drawing

    private func group(
        titleKey: String,
        choices: [OnboardingClosedChoice],
        pick: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            OnboardingClosedGroupTitle(text: context.t(titleKey))
            HStack(spacing: Self.cardGap) {
                ForEach(choices) { choice in card(choice) { pick(choice.id) } }
            }
            needsLine(for: choices)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card(_ choice: OnboardingClosedChoice, pick: @escaping () -> Void) -> some View {
        OnboardingClosedCard(
            title: context.t(choice.titleKey),
            hint: context.t(choice.noteKey),
            isSelected: choice.isSelected,
            action: pick
        ) {
            glyph(choice.art)
        }
        .frame(width: cardWidth, height: Self.cardHeight)
    }

    /// What the choices in a group need, in a few words, once each.
    @ViewBuilder
    private func needsLine(for choices: [OnboardingClosedChoice]) -> some View {
        let needs = OnboardingClosedNeed.allCases.filter { need in choices.contains { $0.need == need } }
        if !needs.isEmpty {
            Text(needs.map { context.t($0.textKey) }.joined(separator: " "))
                .font(.system(size: 10.5))
                .foregroundStyle(OnboardingStyle.faintText)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The pick by itself, as large as it is on the picture above.
    @ViewBuilder
    private func glyph(_ art: OnboardingPillSide) -> some View {
        if art == .nothing {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 16, height: 3)
        } else {
            OnboardingPillSideArt(side: art, height: 40, tint: nil)
        }
    }
}

/// The small caps title above a group of cards.
struct OnboardingClosedGroupTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(1)
            .foregroundStyle(OnboardingStyle.faintText)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One card of a group: a picture over a name. What the choice does is its
/// accessibility hint, and what it needs is said under the group.
struct OnboardingClosedCard<Art: View>: View {
    let title: String
    let hint: String
    let isSelected: Bool
    var isEnabled = true
    let action: () -> Void
    @ViewBuilder var art: () -> Art

    var body: some View {
        OnboardingChoiceCard(isSelected: isSelected, action: action) {
            VStack(spacing: 6) {
                art()
                    .frame(height: 30, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(OnboardingStyle.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 6)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }
}
