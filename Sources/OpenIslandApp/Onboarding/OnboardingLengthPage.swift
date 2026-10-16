import SwiftUI

// MARK: - 2. How much time

/// The tour's length, asked as a question with a card for each answer. Each
/// card shows how many pages the answer gives, counted from the page list of
/// that answer as the app stands now, and never a number of minutes. A pick
/// goes through `OnboardingActions.chooseLength`, which the tour answers
/// itself: it is the tour's own state and the app never sees it.
struct OnboardingLengthPage: View {
    let context: OnboardingPageContext

    private var state: OnboardingState { context.state }

    private static let cardHeight: CGFloat = 256
    private static let stripWidth: CGFloat = 214

    var body: some View {
        let counts = Dictionary(uniqueKeysWithValues: OnboardingLength.allCases.map { ($0, Self.stepCount($0, in: state)) })
        let most = counts.values.max() ?? 1
        OnboardingPageScaffold(
            page: .length,
            context: context,
            title: context.t("onboarding.length.title"),
            text: context.t("onboarding.length.body"),
            footnote: context.t("onboarding.length.note"),
            gap: 28
        ) {
            HStack(spacing: 16) {
                ForEach(OnboardingLength.allCases) { length in
                    card(length, steps: counts[length] ?? 0, most: most)
                }
            }
        }
    }

    /// How many pages a tour of `length` walks with the app as `state` has
    /// it: the same list the step counter counts once the choice is made.
    static func stepCount(_ length: OnboardingLength, in state: OnboardingState) -> Int {
        var chosen = state
        chosen.length = length
        return OnboardingTour.pages(for: chosen).count
    }

    private func card(_ length: OnboardingLength, steps: Int, most: Int) -> some View {
        let title = context.t(length.titleKey)
        return OnboardingChoiceCard(isSelected: state.length == length) {
            context.actions.chooseLength(length)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                OnboardingLengthStrip(count: steps, most: most, width: Self.stripWidth, isSelected: state.length == length)
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(OnboardingStyle.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 22)
                Text(context.t(length.textKey))
                    .font(.system(size: 13))
                    .foregroundStyle(OnboardingStyle.secondaryText)
                    .lineSpacing(1.5)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                // What the tour walks through, in three short lines.
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(length.pointKeys, id: \.self) { key in
                        Text(context.t(key))
                            .font(.system(size: 12))
                            .foregroundStyle(OnboardingStyle.secondaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 16)
                Spacer(minLength: 8)
                Text(context.lang.t("onboarding.length.steps", steps))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(OnboardingStyle.primaryText.opacity(0.8))
            }
            .padding(18)
        }
        .frame(height: Self.cardHeight)
        .accessibilityLabel(title)
        .accessibilityValue(context.lang.t("onboarding.length.steps", steps))
        .demoTarget(.tourLength(length))
    }
}

/// One small segment for each page of a tour, the way the progress dots
/// draw them. The segments of the three cards are the same width, which
/// makes a longer tour a longer strip.
struct OnboardingLengthStrip: View {
    let count: Int
    /// The most segments any of the cards has.
    let most: Int
    let width: CGFloat
    let isSelected: Bool

    private static let gap: CGFloat = 2
    private static let height: CGFloat = 6

    var body: some View {
        let segment = max(1, (width - Self.gap * CGFloat(most - 1)) / CGFloat(max(most, 1)))
        HStack(spacing: Self.gap) {
            ForEach(0..<max(count, 0), id: \.self) { _ in
                Capsule()
                    .fill(OnboardingStyle.paper.opacity(isSelected ? 0.95 : 0.5))
                    .frame(width: segment, height: Self.height)
            }
        }
        .frame(width: width, height: Self.height, alignment: .leading)
        .accessibilityHidden(true)
    }
}
