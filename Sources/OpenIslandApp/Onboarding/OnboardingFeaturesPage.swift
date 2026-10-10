import SwiftUI

/// "See what each one does": the widgets on the user's page, one at a time
/// (D47). The widget shown is ringed on the real island. The page names it,
/// says what it is for, has "Try it" buttons that make the real widget do the
/// thing, and lists what it can do. Next is never held up by any of it.
struct OnboardingFeaturesPage: View {
    let context: OnboardingPageContext

    private var state: OnboardingState { context.state }

    var body: some View {
        let walk = state.featureWalk
        OnboardingPageScaffold(
            page: .features,
            context: context,
            title: context.t("onboarding.features.title"),
            text: context.t(walk.current == nil ? "onboarding.features.none" : "onboarding.features.body"),
            footnote: context.t("onboarding.features.note"),
            gap: 12
        ) {
            VStack(alignment: .leading, spacing: 12) {
                OnboardingLiveLine(text: context.t("onboarding.live.line"))
                if let kind = walk.current {
                    header(kind, walk)
                    // The buttons come first: in a window this narrow the list
                    // would push them below the fold.
                    tries(kind)
                    lines(kind)
                    if walk.isAtEnd, walk.kinds.count < NookWidgetKind.allCases.count {
                        OnboardingNote(text: context.t("onboarding.features.others"))
                    }
                }
            }
        }
    }

    private func name(_ kind: NookWidgetKind) -> String {
        context.t("onboarding.nook.widget.\(kind.rawValue)")
    }

    // MARK: The widget and where it is in the list

    private func header(_ kind: NookWidgetKind, _ walk: OnboardingFeatureWalk) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                OnboardingSymbolPlate(symbol: kind.systemImage, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name(kind))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(OnboardingStyle.primaryText)
                    Text(context.lang.t("onboarding.features.count", walk.position, walk.count))
                        .font(.system(size: 11))
                        .foregroundStyle(OnboardingStyle.faintText)
                }
                Spacer(minLength: 6)
                HStack(spacing: 6) {
                    stepButton("onboarding.features.previous", symbol: "chevron.left", enabled: walk.previous != nil) {
                        context.actions.previousFeature()
                    }
                    stepButton("onboarding.features.next", symbol: "chevron.right", enabled: walk.next != nil) {
                        context.actions.nextFeature()
                    }
                }
            }
            Text(context.t("onboarding.widgets.\(kind.rawValue)"))
                .font(.system(size: 12.5))
                .foregroundStyle(OnboardingStyle.primaryText.opacity(0.9))
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private func stepButton(_ key: String, symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .foregroundStyle(OnboardingStyle.primaryText)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(context.t(key))
    }

    // MARK: What it can do

    private func lines(_ kind: NookWidgetKind) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(context.t("onboarding.features.can").uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(OnboardingStyle.faintText)
            ForEach(OnboardingAbility.lines(for: kind)) { ability in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(OnboardingStyle.paper.opacity(0.7))
                        .frame(width: 4, height: 4)
                        .offset(y: -2.5)
                    Text(context.t(ability.textKey))
                        .font(.system(size: 12))
                        .foregroundStyle(OnboardingStyle.primaryText.opacity(0.88))
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OnboardingCardBackground())
        .accessibilityElement(children: .combine)
    }

    // MARK: Try it

    /// The buttons of the widget, or the line that says the next pages
    /// connect it.
    @ViewBuilder
    private func tries(_ kind: NookWidgetKind) -> some View {
        let steps = OnboardingTry.tries(for: kind)
        if steps.isEmpty {
            OnboardingNote(text: context.t("onboarding.features.connected.\(kind.rawValue)"))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(context.t("onboarding.features.try").uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(OnboardingStyle.faintText)
                ForEach(steps) { step in
                    if step == .notesLine {
                        OnboardingNotesTryStep(context: context)
                    } else {
                        tryRow(step)
                    }
                }
            }
        }
    }

    private func tryRow(_ step: OnboardingTry) -> some View {
        let button = step.button(state.features, progress: state.featureProgress)
        let isDone = state.isDone(step)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isDone ? OnboardingStyle.finished : OnboardingStyle.faintText)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Button(context.t(button.titleKey)) {
                    step.press(
                        reading: state.features,
                        sample: context.t(OnboardingFeatureSample.clipboardKey),
                        actions: context.actions
                    )
                }
                .buttonStyle(OnboardingSecondaryButtonStyle(height: 30))
                .disabled(!button.isEnabled)
                .opacity(button.isEnabled ? 1 : 0.45)
                .accessibilityValue(context.t(isDone ? "onboarding.arrange.done" : "onboarding.arrange.todo"))
                Spacer(minLength: 0)
            }
            if let note = button.noteKey {
                Text(context.t(note))
                    .font(.system(size: 11.5))
                    .foregroundStyle(OnboardingStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 27)
            }
        }
    }
}
