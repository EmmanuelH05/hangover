import EventKit
import Foundation

/// The to-dos page's door to the real task services (D43, D44). It reads
/// their state into an `OnboardingTodoSetup` and runs the page's buttons
/// through the same calls Settings makes: `connect(token:)`,
/// `loadDatabases()`, `selectDatabase(_:)` and the TickTick pair, and the
/// Reminders access request. It holds no state of its own. In particular
/// it never keeps a token: the secret is passed on to the service and the
/// service writes it to the Keychain.
///
/// The services take their transport, token store and defaults as init
/// arguments, which is how a test drives this without a network, a
/// Keychain or the real settings.
@MainActor
struct OnboardingTodoConnector {
    let hub: NookTodoHub
    let reminders: NookRemindersService
    let lang: LanguageManager

    // MARK: Reading

    /// What the page shows for the source the hub has picked.
    func setup() -> OnboardingTodoSetup {
        switch hub.selectedKind {
        case .reminders: remindersSetup()
        case .notion: notionSetup()
        case .tickTick: tickTickSetup()
        }
    }

    private func notionSetup() -> OnboardingTodoSetup {
        let service = hub.notion
        let choices = service.databases.map { OnboardingTodoChoice(id: $0.id, title: $0.title) }
        let isConnected = service.hasToken && !service.tokenRejected
        var message = OnboardingTodoMessage.notion(service.state, lang: lang)
        if message == nil, isConnected, service.hasLoadedDatabases, choices.isEmpty, service.selectedDatabaseID == nil {
            message = OnboardingTodoMessage(text: lang.t("onboarding.todos.notion.noneShared"), isProblem: false)
        }
        var needsColumns = false
        if case .needsAttention = service.state { needsColumns = true }
        return OnboardingTodoSetup(
            isConnected: isConnected,
            isBusy: service.state == .connecting || service.isLoadingDatabases,
            accountName: isConnected ? service.accountName : nil,
            choices: choices,
            hasLoadedChoices: service.hasLoadedDatabases,
            chosenID: service.selectedDatabaseID,
            taskCount: service.state == .ready ? service.items.count : nil,
            message: message,
            needsColumns: needsColumns
        )
    }

    private func tickTickSetup() -> OnboardingTodoSetup {
        let service = hub.tickTick
        let inbox = OnboardingTodoChoice(id: TickTickClient.inboxID, title: lang.t("nook.todo.ticktick.inbox"))
        let choices = [inbox] + service.lists.map { OnboardingTodoChoice(id: $0.id, title: $0.name) }
        let isConnected = service.hasToken && !service.tokenRejected
        return OnboardingTodoSetup(
            isConnected: isConnected,
            isBusy: service.state == .connecting || service.isLoadingLists,
            choices: choices,
            hasLoadedChoices: service.hasLoadedLists,
            chosenID: service.selectedListID,
            taskCount: service.state == .ready ? service.items.count : nil,
            message: OnboardingTodoMessage.tickTick(service.state, lang: lang)
        )
    }

    private func remindersSetup() -> OnboardingTodoSetup {
        let access = Self.access(for: reminders.authorization)
        return OnboardingTodoSetup(
            isConnected: access == .granted,
            taskCount: access == .granted ? reminders.items.count : nil,
            message: access == .refused
                ? OnboardingTodoMessage(text: lang.t("onboarding.todos.reminders.refused"), isProblem: true)
                : nil,
            remindersAccess: access
        )
    }

    /// Only full access shows reminders. The other answers cannot be asked
    /// for again from the app.
    static func access(for status: EKAuthorizationStatus) -> OnboardingRemindersAccess {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: .notAsked
        default: .refused
        }
    }

    // MARK: Buttons

    /// Connect, with the secret the field held. Settings' Connect button
    /// makes the same call.
    func connect(token: String) async {
        switch hub.selectedKind {
        case .reminders: break
        case .notion: await hub.notion.connect(token: token)
        case .tickTick: await hub.tickTick.connect(token: token)
        }
    }

    /// Loads the databases or the lists again.
    func checkAgain() async {
        switch hub.selectedKind {
        case .reminders: break
        case .notion: await hub.notion.loadDatabases()
        case .tickTick: await hub.tickTick.loadLists()
        }
    }

    /// Picks the database or the list, which loads its tasks.
    func choose(_ id: String) async {
        switch hub.selectedKind {
        case .reminders: break
        case .notion: await hub.notion.selectDatabase(id)
        case .tickTick: await hub.tickTick.selectList(id)
        }
    }

    /// The button the user pressed asks macOS. The same call as Settings'
    /// "Allow Access".
    func allowReminders() async {
        await reminders.requestAccessIfUndecided()
    }
}
