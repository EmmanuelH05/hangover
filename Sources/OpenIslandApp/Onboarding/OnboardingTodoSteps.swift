import SwiftUI

/// The secret field of the to-dos page: the one text field in the tour. The
/// typed text lives in this view's own `@State` and nowhere else. It is
/// handed to `onConnect` when the user presses Connect or Return, and it is
/// never logged. The view leaves the page once the service is connected,
/// which ends its state, and it clears itself on the way out as well.
struct OnboardingTokenField: View {
    let placeholder: String
    let buttonTitle: String
    let isBusy: Bool
    let onConnect: (String) -> Void

    @State private var draft = ""

    private var isBlank: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SecureField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(OnboardingStyle.primaryText)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(OnboardingStyle.cardStroke, lineWidth: 1)
                )
                .onSubmit(submit)
            Button(buttonTitle, action: submit)
                .buttonStyle(OnboardingSecondaryButtonStyle(height: 28))
                .disabled(isBlank || isBusy)
                .opacity(isBlank || isBusy ? 0.5 : 1)
        }
        .onDisappear { draft = "" }
    }

    private func submit() {
        guard !isBlank, !isBusy else { return }
        onConnect(draft)
    }
}

/// A database or a list as a plain button. The picked one carries a tick.
struct OnboardingPickButtonStyle: ButtonStyle {
    let isChosen: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.label
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if isChosen {
                Image(systemName: "checkmark")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(OnboardingStyle.paper)
            }
        }
        .font(.system(size: 12.5, weight: isChosen ? .semibold : .medium))
        .foregroundStyle(OnboardingStyle.primaryText)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(isChosen ? 0.16 : (configuration.isPressed ? 0.14 : 0.08)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isChosen ? OnboardingStyle.paper.opacity(0.8) : Color.clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// One row of the to-dos checklist: a small symbol, a short line, its
/// control while it is the step to do, and a tick when it is done.
struct OnboardingTodoStepRow: View {
    let step: OnboardingTodoStep
    let source: NookTodoSourceKind
    let setup: OnboardingTodoSetup
    let context: OnboardingPageContext

    /// Most databases or lists drawn as buttons. The picked one is always
    /// among them, and Settings holds the rest.
    static let choiceLimit = 6

    private var key: String { OnboardingTodoGuide.stepKey(step.kind, source: source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                OnboardingSymbolPlate(symbol: step.kind.symbol, size: 26)
                Text(context.t(key))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(OnboardingStyle.primaryText.opacity(step.isActive || step.isDone ? 0.95 : 0.55))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                Spacer(minLength: 0)
                Image(systemName: step.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(step.isDone ? OnboardingStyle.finished : OnboardingStyle.faintText)
                    .frame(width: 18)
                    .accessibilityHidden(true)
            }
            // The controls take the row's whole width, which keeps a button's
            // words on one line in the narrow window.
            VStack(alignment: .leading, spacing: 8) {
                controls
                if step.showsMessage, let message = setup.message { messageView(message) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityValue(context.t(step.isDone ? "onboarding.arrange.done" : "onboarding.arrange.todo"))
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        switch step.kind {
        case .open: openControl
        case .connect: connectControl
        case .share: shareControl
        case .pick: pickControl
        case .allow: allowControl
        }
    }

    @ViewBuilder
    private var openControl: some View {
        if step.isActive, let linkKey = OnboardingTodoGuide.linkKey(for: source) {
            Button(context.t(linkKey)) { context.actions.openTodoSetupPage(source) }
                .buttonStyle(OnboardingSecondaryButtonStyle(height: 28))
        }
    }

    @ViewBuilder
    private var connectControl: some View {
        if step.isDone {
            note(connectedText)
        } else if step.isActive {
            OnboardingTokenField(
                placeholder: context.t("nook.todo.\(source.rawValue).token.placeholder"),
                buttonTitle: context.t("nook.todo.\(source.rawValue).connect"),
                isBusy: setup.isBusy
            ) { token in context.actions.connectTodo(token) }
            note(context.t("onboarding.todos.keychain"))
        }
    }

    /// Notion names the connection. TickTick has no request that does.
    private var connectedText: String {
        if let name = setup.accountName {
            return context.lang.t("onboarding.todos.account", name)
        }
        return context.t("nook.todo.ticktick.token.saved")
    }

    @ViewBuilder
    private var shareControl: some View {
        if step.isActive {
            HStack(spacing: 8) {
                Button(context.t("onboarding.todos.checkAgain")) { context.actions.checkTodoAgain() }
                    .buttonStyle(OnboardingSecondaryButtonStyle(height: 28))
                    .disabled(setup.isBusy)
                    .opacity(setup.isBusy ? 0.5 : 1)
            }
        }
    }

    @ViewBuilder
    private var pickControl: some View {
        if step.isActive || step.isDone {
            let shown = Self.visibleChoices(of: setup, limit: Self.choiceLimit)
            VStack(spacing: 5) {
                ForEach(shown) { choice in
                    Button(choice.title) { context.actions.chooseTodo(choice.id) }
                        .buttonStyle(OnboardingPickButtonStyle(isChosen: choice.id == setup.chosenID))
                }
                if shown.count < setup.choices.count {
                    Button(context.t("onboarding.todos.settings")) { context.actions.showTodoSettings() }
                        .buttonStyle(OnboardingSecondaryButtonStyle(height: 28))
                }
            }
            if step.isDone, let count = setup.taskCount {
                note(context.lang.t(OnboardingTodoChecklist.loadedKey(count: count), count))
            }
        }
    }

    @ViewBuilder
    private var allowControl: some View {
        if step.isDone {
            if let count = setup.taskCount {
                note(context.lang.t(OnboardingTodoChecklist.loadedKey(count: count), count))
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if setup.remindersAccess == .refused {
                    Button(context.t("onboarding.todos.reminders.openSystem")) {
                        context.actions.openRemindersSettings()
                    }
                    .buttonStyle(OnboardingSecondaryButtonStyle(height: 28))
                } else {
                    Button(context.t("onboarding.todos.reminders.allowButton")) { context.actions.allowReminders() }
                        .buttonStyle(OnboardingSecondaryButtonStyle(height: 28))
                }
            }
        }
    }

    // MARK: Pieces

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(OnboardingStyle.secondaryText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The service's own sentence, in plain sight. A problem is orange, as
    /// Settings draws it.
    private func messageView(_ message: OnboardingTodoMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: message.isProblem ? "exclamationmark.triangle.fill" : "ellipsis.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(message.isProblem ? OnboardingStyle.waiting : OnboardingStyle.faintText)
                Text(message.text)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(message.isProblem ? OnboardingStyle.waiting : OnboardingStyle.secondaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if setup.needsColumns {
                Button(context.t("onboarding.todos.settings")) { context.actions.showTodoSettings() }
                    .buttonStyle(OnboardingSecondaryButtonStyle(height: 28))
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The first `limit` choices, with the picked one moved in when it is
    /// further down the list.
    static func visibleChoices(of setup: OnboardingTodoSetup, limit: Int) -> [OnboardingTodoChoice] {
        let first = Array(setup.choices.prefix(limit))
        guard let chosen = setup.choices.first(where: { $0.id == setup.chosenID }),
              !first.contains(chosen), limit > 0
        else { return first }
        return Array(first.dropLast()) + [chosen]
    }
}
