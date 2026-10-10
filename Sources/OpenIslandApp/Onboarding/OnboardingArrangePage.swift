import SwiftUI

/// "Move them where you want": pick one widget, then one instruction at a
/// time about it, each ticked as the real island shows it done (D44). Next
/// is never held up by any of it.
struct OnboardingArrangePage: View {
    let context: OnboardingPageContext

    private var state: OnboardingState { context.state }

    var body: some View {
        let progress = state.arrangeProgress
        OnboardingPageScaffold(
            page: .arrange,
            context: context,
            title: context.t("onboarding.arrange.title"),
            text: text(for: progress),
            footnote: progress == nil ? context.t("onboarding.arrange.note") : nil,
            gap: 14
        ) {
            if let progress {
                walk(progress)
            } else {
                pick
            }
        }
    }

    private func name(_ kind: NookWidgetKind) -> String {
        context.t("onboarding.nook.widget.\(kind.rawValue)")
    }

    /// The sentence under the title: what is about to happen, then where
    /// the widget is, then how it ended.
    private func text(for progress: OnboardingArrangeProgress?) -> String {
        guard let progress else { return context.t("onboarding.arrange.body") }
        if !progress.isOnPage { return context.lang.t("onboarding.arrange.gone", name(progress.kind)) }
        if progress.isAllDone { return context.t("onboarding.arrange.end.body") }
        return context.lang.t("onboarding.arrange.outlined", name(progress.kind))
    }

    // MARK: Pick

    /// The widgets on the user's page, two to a row.
    private var pick: some View {
        let kinds = state.shownPlacements.map(\.kind)
        let rows = stride(from: 0, to: kinds.count, by: 2).map { Array(kinds[$0..<min($0 + 2, kinds.count)]) }
        return VStack(alignment: .leading, spacing: 10) {
            Text(context.t("onboarding.arrange.pick"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(OnboardingStyle.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(row) { kind in choice(kind) }
                        if row.count == 1 { Color.clear.frame(maxWidth: .infinity) }
                    }
                }
            }
        }
    }

    private func choice(_ kind: NookWidgetKind) -> some View {
        Button {
            context.actions.pickArrangeWidget(kind)
        } label: {
            HStack(spacing: 8) {
                OnboardingSymbolPlate(symbol: kind.systemImage, size: 26)
                Text(name(kind))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OnboardingStyle.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(OnboardingCardBackground())
            .contentShape(RoundedRectangle(cornerRadius: OnboardingStyle.cardCornerRadius, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(name(kind))
    }

    // MARK: Walk

    @ViewBuilder
    private func walk(_ progress: OnboardingArrangeProgress) -> some View {
        if !progress.isOnPage {
            tryAnother
        } else if progress.isAllDone {
            end
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(progress.doneSteps) { step in doneLine(step, progress) }
                if let step = progress.current {
                    stepCard(step, progress)
                    if progress.needsEditing {
                        Text(context.lang.t("onboarding.arrange.stopped", name(progress.kind)))
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(OnboardingStyle.waiting)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// A step that is done, folded to one ticked line.
    private func doneLine(_ step: OnboardingRearrangeStep, _ progress: OnboardingArrangeProgress) -> some View {
        let who = name(progress.kind)
        let line = switch step {
        case .move: context.lang.t(step.doneKey, who)
        case .resize: context.lang.t(step.doneKey, who, size(progress.size))
        case .finish: context.t(step.doneKey)
        }
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(OnboardingStyle.finished)
            Text(line)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(OnboardingStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(context.t("onboarding.arrange.done"))
    }

    private func size(_ size: NookWidgetSize?) -> String {
        context.t("onboarding.arrange.size.\((size ?? .medium).rawValue)")
    }

    /// The step to do now, in full: a small picture, the instruction, how.
    private func stepCard(_ step: OnboardingRearrangeStep, _ progress: OnboardingArrangeProgress) -> some View {
        let number = (OnboardingRearrangeStep.allCases.firstIndex(of: step) ?? 0) + 1
        return HStack(alignment: .top, spacing: 12) {
            OnboardingArrangeArt(step: step)
            VStack(alignment: .leading, spacing: 5) {
                Text(context.lang.t("onboarding.arrange.stepOf", number, OnboardingRearrangeStep.allCases.count).uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(OnboardingStyle.faintText)
                Text(title(step, progress))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(OnboardingStyle.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let how = step.howKey {
                    Text(context.t(how))
                        .font(.system(size: 12.5))
                        .foregroundStyle(OnboardingStyle.secondaryText)
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OnboardingCardBackground())
        .accessibilityElement(children: .combine)
    }

    private func title(_ step: OnboardingRearrangeStep, _ progress: OnboardingArrangeProgress) -> String {
        step == .move
            ? context.lang.t(step.titleKey, name(progress.kind))
            : context.t(step.titleKey)
    }

    // MARK: End

    private var end: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OnboardingStyle.paper)
                    .frame(width: 18)
                Text(context.t("onboarding.arrange.end.remember"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(OnboardingStyle.primaryText.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OnboardingCardBackground())
            .accessibilityElement(children: .combine)

            tryAnother
            Button(context.t("onboarding.arrange.reset")) { context.actions.resetArrangement() }
                .buttonStyle(OnboardingSecondaryButtonStyle(height: 30))
                .disabled(!hasChanged)
                .opacity(hasChanged ? 1 : 0.4)
        }
    }

    private var tryAnother: some View {
        Button(context.t("onboarding.arrange.another")) { context.actions.tryAnotherWidget() }
            .buttonStyle(OnboardingSecondaryButtonStyle(height: 30))
    }

    /// The page is not as it was when the walk-through came up: what the
    /// reset button puts back.
    private var hasChanged: Bool {
        state.arrangeStart.map { $0 != state.shownPlacements } ?? false
    }
}

/// The small picture beside a step: still shapes, no motion.
struct OnboardingArrangeArt: View {
    let step: OnboardingRearrangeStep

    private static let size = CGSize(width: 58, height: 52)

    var body: some View {
        Group {
            switch step {
            case .move: move
            case .resize: resize
            case .finish: finish
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityHidden(true)
    }

    private func tile(width: CGFloat, height: CGFloat, fill: Double = 0.14, ring: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.white.opacity(fill))
            .overlay {
                if ring { RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.cyan, lineWidth: 1.5) }
            }
            .frame(width: width, height: height)
    }

    /// One tile lifted over its neighbor, with an arrow for the way it goes.
    private var move: some View {
        ZStack {
            tile(width: 22, height: 18, fill: 0.08).offset(x: 12, y: 12)
            tile(width: 22, height: 18, ring: true).offset(x: -12, y: -10)
            Image(systemName: "arrow.down.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(OnboardingStyle.paper)
                .offset(x: 6, y: 2)
        }
    }

    /// A tile with a handle at its corner and an arrow pulling it outward.
    private var resize: some View {
        ZStack {
            tile(width: 30, height: 24, ring: true).offset(x: -6, y: -5)
            Circle()
                .fill(OnboardingStyle.paper)
                .frame(width: 9, height: 9)
                .offset(x: 9, y: 7)
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(OnboardingStyle.paper)
                .offset(x: 19, y: 16)
        }
    }

    /// The island's Done button.
    private var finish: some View {
        Text("Done")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(Color.orange))
    }
}
