import Foundation

// The to-dos page connects a task source for real (D43, D44). What it
// draws is a function of plain values: the setup below, read from the
// services by `OnboardingTodoConnector`, and the checklist this file turns
// it into. A snapshot and a test hand in a fixed setup.

/// One database or list the user can pick.
struct OnboardingTodoChoice: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
}

/// Where the Reminders permission stands.
enum OnboardingRemindersAccess: Equatable, Sendable {
    /// macOS has not been asked yet.
    case notAsked
    case granted
    /// Refused, restricted or write only. macOS asks no second time: the
    /// answer is changed in System Settings.
    case refused
}

/// A sentence the page shows in plain sight, in the user's language.
struct OnboardingTodoMessage: Equatable, Sendable {
    var text: String
    /// True when a step failed. A message that is not a problem is a
    /// status, such as "Connecting to Notion…".
    var isProblem: Bool
}

/// What the to-dos page needs to know about the picked source. The source
/// itself is `OnboardingState.todoSource`. No field holds a token: the
/// secret goes from the page's field straight to the service.
struct OnboardingTodoSetup: Equatable, Sendable {
    /// The service holds a token that worked.
    var isConnected = false
    /// A connect or a load is running.
    var isBusy = false
    /// The name Notion gave the connection. Nil for TickTick, which has no
    /// request that names the account, and before a connect.
    var accountName: String?
    /// The databases shared with the integration, or the lists in the
    /// account (the inbox first).
    var choices: [OnboardingTodoChoice] = []
    /// The list of choices was loaded at least once.
    var hasLoadedChoices = false
    var chosenID: String?
    /// How many open tasks the card now holds. Nil until the source loaded
    /// them.
    var taskCount: Int?
    /// The sentence for the state the service is in, when it has one worth
    /// showing.
    var message: OnboardingTodoMessage?
    /// The database's columns need the user's attention, which only
    /// Settings can fix.
    var needsColumns = false
    var remindersAccess: OnboardingRemindersAccess = .notAsked
}

/// One thing a source asks the user to do. The string key of a step's line
/// is `onboarding.todos.<source>.<kind>`.
enum OnboardingTodoStepKind: String, Sendable {
    /// Create the integration (Notion) or the API token (TickTick), in a
    /// page the button opens.
    case open
    /// Paste the secret and press Connect.
    case connect
    /// Share the database with the integration. Notion only.
    case share
    /// Pick the database or the list.
    case pick
    /// Let macOS give access. Reminders only.
    case allow

    var symbol: String {
        switch self {
        case .open: "arrow.up.forward.app"
        case .connect: "key"
        case .share: "person.badge.plus"
        case .pick: "list.bullet"
        case .allow: "hand.raised"
        }
    }
}

/// One row of the checklist.
struct OnboardingTodoStep: Identifiable, Equatable, Sendable {
    let kind: OnboardingTodoStepKind
    var isDone: Bool
    /// The step's controls are on screen: it is not done and what it needs
    /// from the steps before it is there. The "open" step is the one the
    /// connect step does not wait for, because the page it opens and the
    /// field below it are used together.
    var isActive: Bool
    /// The setup's message is drawn under this step.
    var showsMessage: Bool

    var id: String { kind.rawValue }
}

/// The checklist for a source, a pure function of its setup.
enum OnboardingTodoChecklist {
    static func kinds(for source: NookTodoSourceKind) -> [OnboardingTodoStepKind] {
        switch source {
        case .reminders: [.allow]
        case .notion: [.open, .connect, .share, .pick]
        case .tickTick: [.open, .connect, .pick]
        }
    }

    static func steps(source: NookTodoSourceKind, setup: OnboardingTodoSetup) -> [OnboardingTodoStep] {
        let kinds = kinds(for: source)
        let done = kinds.map { isDone($0, source: source, setup: setup) }
        let active = kinds.indices.map { index in
            !done[index] && kinds[..<index].enumerated().allSatisfy { done[$0.offset] || $0.element == .open }
        }
        // Once everything is done nothing is active, and a status that is
        // left (the island is offline, say) goes under the last step.
        let messageIndex = active.lastIndex(of: true) ?? kinds.indices.last
        return kinds.indices.map { index in
            OnboardingTodoStep(
                kind: kinds[index],
                isDone: done[index],
                isActive: active[index],
                showsMessage: setup.message != nil && index == messageIndex
            )
        }
    }

    /// What ticks a step, and nothing else: the services' own words for
    /// being connected, having databases listed and having tasks loaded.
    static func isDone(_ kind: OnboardingTodoStepKind, source: NookTodoSourceKind, setup: OnboardingTodoSetup) -> Bool {
        switch kind {
        case .open, .connect: setup.isConnected
        case .share: setup.isConnected && !setup.choices.isEmpty
        case .pick: setup.isConnected && setup.chosenID != nil && setup.taskCount != nil
        case .allow: setup.remindersAccess == .granted
        }
    }

    /// The string key for the line that says how many tasks loaded.
    static func loadedKey(count: Int) -> String {
        switch count {
        case 0: "onboarding.todos.loaded.zero"
        case 1: "onboarding.todos.loaded.one"
        default: "onboarding.todos.loaded.other"
        }
    }
}

// MARK: - The services' own sentences

extension OnboardingTodoMessage {
    /// The sentence for a Notion state, or nil when the state needs none:
    /// idle, ready, no token yet and no database yet are the checklist
    /// itself.
    static func notion(_ state: NotionTodoState, lang: LanguageManager) -> OnboardingTodoMessage? {
        switch state {
        case .inactive, .noToken, .noDatabase, .ready: nil
        case .connecting: OnboardingTodoMessage(text: lang.t(state.messageKey), isProblem: false)
        case .keychainUnavailable, .invalidToken, .needsAttention, .databaseUnavailable,
             .missingReadCapability, .rateLimited, .offline, .serverError:
            OnboardingTodoMessage(text: lang.t(state.messageKey), isProblem: true)
        }
    }

    static func tickTick(_ state: TickTickTodoState, lang: LanguageManager) -> OnboardingTodoMessage? {
        switch state {
        case .inactive, .noToken, .ready: nil
        case .connecting: OnboardingTodoMessage(text: lang.t(state.messageKey), isProblem: false)
        case .keychainUnavailable, .invalidToken, .connectFailed, .listUnavailable, .rejected,
             .forbidden, .rateLimited, .offline, .serverError:
            OnboardingTodoMessage(text: lang.t(state.messageKey), isProblem: true)
        }
    }
}
