import EventKit
import Foundation
import Observation

/// The apps the todo card can read tasks from, in the order Settings and
/// the card show them (T3). Several can be on at once (D83).
enum NookTodoSourceKind: String, CaseIterable, Identifiable, Sendable {
    case reminders
    case notion
    case tickTick = "ticktick"
    case asana
    case monday
    case canvas

    var id: String { rawValue }

    /// The name Settings gives the app.
    var nameKey: String { "nook.todo.source.\(rawValue)" }

    /// The line under the name in the To-dos list (T3).
    var subtitleKey: String { "nook.todo.source.\(rawValue).subtitle" }

    /// Reached over the network with a token the user pastes.
    var isRemote: Bool { self != .reminders }

    /// Whether the app takes a new task typed on the card. Canvas never
    /// does (T14): its assignments come from the school.
    var takesNewTasks: Bool { self != .canvas }

    /// The apps the welcome tour offers, which are the three it was drawn
    /// with (D43). The others are turned on in Settings.
    static let offeredInTour: [NookTodoSourceKind] = [.reminders, .notion, .tickTick]
}

/// Whether a source can show tasks right now.
enum NookTodoConnection: Equatable, Sendable {
    case ready
    /// Not usable yet. The message says why, in words for the user.
    case unavailable(message: String)
}

/// The surface the todo card needs from a task source.
@MainActor
protocol NookTodoSource: AnyObject {
    var items: [NookTodoItem] { get }
    /// Shown in the card header: the list or database name.
    var displayName: String { get }
    var connection: NookTodoConnection { get }
    /// A problem with the last action or refresh, shown under the rows.
    var errorMessage: String? { get }
    /// True while the last notes save is the thing that failed. The notes
    /// page keeps its draft then, because the row went back to the old
    /// notes. Any other problem in `errorMessage` says nothing about the
    /// notes, and the page goes on following the source.
    var notesSaveFailed: Bool { get }
    /// True while the rows come from the last good load, not a live one.
    var isShowingCachedItems: Bool { get }
    var canAdd: Bool { get }
    var canComplete: Bool { get }
    /// Whether a task's notes can be written back right now.
    var canEditNotes: Bool { get }
    /// Why notes are read-only, in words for the user. Nil while editable.
    var notesUnavailableReason: String? { get }
    /// Whether a due date can be saved with a new task right now.
    var canSetDue: Bool { get }
    /// Why dates cannot be set, in words for the user. Nil while they can.
    var dueUnavailableReason: String? { get }
    var addPlaceholder: String { get }
    /// How often the card should ask for a refresh while it is on screen.
    /// Nil for sources that push their own changes.
    var autoRefreshInterval: Duration? { get }

    /// Called when the card appears.
    func refresh()
    /// Called by the card's repeating timer.
    func refreshOnTimer()
    /// Adds a task. `due` is a whole day (year, month and day) or nil for no
    /// date. A source that cannot set a date ignores it.
    func add(_ title: String, due: DateComponents?)
    /// Adds a task and answers whether the source took it. The card keeps the
    /// typed title and the picked day until this says yes. A failed add
    /// loses neither (D2). Why a source said no is its `errorMessage`.
    func addConfirmed(_ title: String, due: DateComponents?) async -> Bool
    func complete(_ id: String)
    /// Saves a task's notes. Empty text clears them.
    func setNotes(_ notes: String, for id: String)
}

extension NookTodoSource {
    var notesSaveFailed: Bool { false }

    /// For a source that cannot tell: hands the task to `add` and says yes.
    func addConfirmed(_ title: String, due: DateComponents?) async -> Bool {
        add(title, due: due)
        return true
    }

    /// A task with no date. The demo's scripted adds and the small card call
    /// this; the medium and large cards pass the picked day to `add(_:due:)`.
    func add(_ title: String) {
        add(title, due: nil)
    }
}

extension NookRemindersService: NookTodoSource {
    var displayName: String { currentListName }

    var connection: NookTodoConnection {
        if hasAccess { return .ready }
        return .unavailable(
            message: authorization == .notDetermined ? "Waiting for Reminders access" : "Reminders access needed"
        )
    }

    var errorMessage: String? { lastWriteError.map { LanguageManager.shared.t($0.messageKey) } }
    var notesSaveFailed: Bool { lastWriteError == .notesFailed }
    var isShowingCachedItems: Bool { false }
    var canAdd: Bool { hasAccess }
    var canComplete: Bool { hasAccess }
    var canEditNotes: Bool { hasAccess }
    var notesUnavailableReason: String? {
        hasAccess ? nil : LanguageManager.shared.t("nook.todo.notes.remindersAccess")
    }
    var canSetDue: Bool { hasAccess }
    var dueUnavailableReason: String? {
        hasAccess ? nil : LanguageManager.shared.t("nook.todo.due.unavailable")
    }
    var addPlaceholder: String { "Add a reminder" }
    /// EventKit posts change notifications, which the service already observes.
    var autoRefreshInterval: Duration? { nil }

    func refreshOnTimer() {}
}

/// The pages a task source's token is made on. The rows in Settings and
/// the welcome tour link to the same ones.
enum NookTodoSetupLink {
    /// Where an internal integration is created in Notion.
    static let notionIntegrations = URL(string: "https://www.notion.so/my-integrations")
    /// The TickTick web app. The API token is made there, under Settings,
    /// Account.
    static let tickTickWebApp = URL(string: "https://ticktick.com/webapp/")
    /// Asana's developer apps page, where a personal access token is made.
    static let asanaDeveloperApps = URL(string: "https://app.asana.com/0/my-apps")
    /// monday's sign-in; the token is under Profile, Developer, My access
    /// tokens on the account's own address.
    static let mondayWebApp = URL(string: "https://monday.com/")

    /// Nil for Reminders, which needs no token, and for Canvas, whose
    /// page lives at the school's own address (`canvasSettings(host:)`).
    static func url(for kind: NookTodoSourceKind) -> URL? {
        switch kind {
        case .reminders, .canvas: nil
        case .notion: notionIntegrations
        case .tickTick: tickTickWebApp
        case .asana: asanaDeveloperApps
        case .monday: mondayWebApp
        }
    }

    /// The Canvas profile settings page, where "New access token" is.
    static func canvasSettings(host: String) -> URL? {
        URL(string: "https://\(host)/profile/settings")
    }
}
