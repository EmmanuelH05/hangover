import SwiftUI

/// What the to-dos page says about each task source (D43, D44). The steps
/// themselves are `OnboardingTodoChecklist`, drawn by `OnboardingTodoStepRow`.
///
/// Notion, from `NookNotionTodoSettings` and the `nook.todo.notion`
/// strings: an internal integration and its token, with the three
/// capabilities the app's own errors name; the token pasted and Connect; the
/// database shared with the integration, which is what an empty database
/// list says to do; then the database, which loads its tasks.
///
/// TickTick, from `NookTickTickTodoSettings` and its strings: the API token
/// from the web app, pasted and Connect, then the list, which starts on the
/// inbox. Reminders has one step: macOS is asked.
enum OnboardingTodoGuide {
    /// The one line on a source's card.
    static func noteKey(for source: NookTodoSourceKind) -> String {
        "onboarding.todos.\(source.rawValue).text"
    }

    /// The name Settings gives the source.
    static func nameKey(for source: NookTodoSourceKind) -> String {
        "nook.todo.source.\(source.rawValue)"
    }

    /// The label of the button that opens the page a token is made on.
    /// Settings has the same link under the same words. Nil for Reminders.
    static func linkKey(for source: NookTodoSourceKind) -> String? {
        switch source {
        case .reminders: nil
        case .notion: "nook.todo.notion.openIntegrations"
        case .tickTick: "nook.todo.ticktick.openWeb"
        }
    }

    static func symbol(for source: NookTodoSourceKind) -> String {
        switch source {
        case .reminders: "list.bullet"
        case .notion: "tablecells"
        case .tickTick: "checkmark.circle"
        }
    }

    /// The string key of a step's line.
    static func stepKey(_ kind: OnboardingTodoStepKind, source: NookTodoSourceKind) -> String {
        "onboarding.todos.\(source.rawValue).\(kind.rawValue)"
    }
}

/// The tour's page for where the to-do widget gets its tasks, shown only
/// while that widget is on the page: a card for each source, and under
/// them a checklist the user completes here. Each step ticks when the
/// service says it is done (`OnboardingTodoChecklist`). The real island
/// shows the widget (D44) and fills in as the source loads: the services
/// load on their own, and the card reads them.
struct OnboardingTodosPage: View {
    let context: OnboardingPageContext

    private var state: OnboardingState { context.state }

    var body: some View {
        OnboardingPageScaffold(
            page: .todos,
            context: context,
            title: context.t("onboarding.todos.title"),
            text: context.t("onboarding.todos.body"),
            footnote: context.t("onboarding.todos.note"),
            gap: 12
        ) {
            VStack(alignment: .leading, spacing: 12) {
                OnboardingLiveLine(text: context.t("onboarding.live.line"))

                VStack(spacing: 6) {
                    ForEach(NookTodoSourceKind.allCases) { source in card(source) }
                }
                Text(context.t(OnboardingTodoGuide.noteKey(for: state.todoSource)))
                    .font(.system(size: 11.5))
                    .foregroundStyle(OnboardingStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                checklist
            }
        }
    }

    /// One line to a card, with the source's own sentence under the three.
    private func card(_ source: NookTodoSourceKind) -> some View {
        let name = context.t(OnboardingTodoGuide.nameKey(for: source))
        return OnboardingChoiceCard(isSelected: state.todoSource == source) {
            context.actions.setTodoSource(source)
        } content: {
            HStack(spacing: 11) {
                OnboardingSymbolPlate(symbol: OnboardingTodoGuide.symbol(for: source), size: 28)
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OnboardingStyle.primaryText)
                Spacer(minLength: 0)
            }
            .padding(.leading, 12)
            // Room for the tick of the picked card.
            .padding(.trailing, 30)
            .frame(maxHeight: .infinity)
        }
        .frame(height: 46)
        .accessibilityLabel(name)
    }

    // MARK: The checklist

    private var checklist: some View {
        let source = state.todoSource
        let steps = OnboardingTodoChecklist.steps(source: source, setup: state.todoSetup)
        return VStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                if index > 0 { OnboardingDivider() }
                OnboardingTodoStepRow(step: step, source: source, setup: state.todoSetup, context: context)
            }
        }
        .background(OnboardingCardBackground())
    }
}
