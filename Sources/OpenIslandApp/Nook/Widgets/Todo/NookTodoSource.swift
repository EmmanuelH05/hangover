import EventKit
import Foundation
import Observation

/// Where the todo card gets its tasks.
enum NookTodoSourceKind: String, CaseIterable, Identifiable, Sendable {
    case reminders
    case notion

    var id: String { rawValue }
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
    /// True while the rows come from the last good load, not a live one.
    var isShowingCachedItems: Bool { get }
    var canAdd: Bool { get }
    var canComplete: Bool { get }
    /// Whether a task's notes can be written back right now.
    var canEditNotes: Bool { get }
    /// Why notes are read-only, in words for the user. Nil while editable.
    var notesUnavailableReason: String? { get }
    var addPlaceholder: String { get }
    /// How often the card should ask for a refresh while it is on screen.
    /// Nil for sources that push their own changes.
    var autoRefreshInterval: Duration? { get }

    /// Called when the card appears.
    func refresh()
    /// Called by the card's repeating timer.
    func refreshOnTimer()
    func add(_ title: String)
    func complete(_ id: String)
    /// Saves a task's notes. Empty text clears them.
    func setNotes(_ notes: String, for id: String)
}

extension NookRemindersService: NookTodoSource {
    var displayName: String { currentListName }

    var connection: NookTodoConnection {
        if hasAccess { return .ready }
        return .unavailable(
            message: authorization == .notDetermined ? "Waiting for Reminders access" : "Reminders access needed"
        )
    }

    var errorMessage: String? { nil }
    var isShowingCachedItems: Bool { false }
    var canAdd: Bool { hasAccess }
    var canComplete: Bool { hasAccess }
    var canEditNotes: Bool { hasAccess }
    var notesUnavailableReason: String? {
        hasAccess ? nil : LanguageManager.shared.t("nook.todo.notes.remindersAccess")
    }
    var addPlaceholder: String { "Add a reminder" }
    /// EventKit posts change notifications, which the service already observes.
    var autoRefreshInterval: Duration? { nil }

    func refreshOnTimer() {}
}

/// Owns the choice of task source and the Notion service. `NookModel` holds
/// one; the Reminders service stays where it always was, on `nook.reminders`.
@MainActor
@Observable
final class NookTodoHub {
    static let sourceKey = "nook.todo.source"

    let notion: NookNotionTodoService

    /// Notes text that has not reached its source, by task ID: a save that
    /// failed, or a draft left when its task went away. The notes page
    /// opens with it, and the list marks the task. Lives as long as the app.
    var noteDrafts: [String: String] = [:]

    var selectedKind: NookTodoSourceKind {
        didSet {
            guard selectedKind != oldValue else { return }
            defaults.set(selectedKind.rawValue, forKey: Self.sourceKey)
            applySelection()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private(set) weak var nook: NookModel?
    @ObservationIgnored private var hasStarted = false

    init(defaults: UserDefaults = .standard, notion: NookNotionTodoService? = nil) {
        self.defaults = defaults
        self.notion = notion ?? NookNotionTodoService(defaults: defaults)
        selectedKind = defaults.string(forKey: Self.sourceKey).flatMap(NookTodoSourceKind.init(rawValue:)) ?? .reminders
        self.notion.onNotesWriteFinished = { [weak self] id, text, saved in
            self?.notesWriteFinished(id: id, text: text, saved: saved)
        }
    }

    /// Keeps text that failed to save. Drops a kept draft once that same
    /// text is saved.
    func notesWriteFinished(id: String, text: String, saved: Bool) {
        if !saved {
            noteDrafts[id] = text
        } else if noteDrafts[id] == text {
            noteDrafts[id] = nil
        }
    }

    func start(nook: NookModel) {
        self.nook = nook
        hasStarted = true
        applySelection()
    }

    /// The source the card and settings should read.
    func source(reminders: NookRemindersService) -> any NookTodoSource {
        switch selectedKind {
        case .reminders: reminders
        case .notion: notion
        }
    }

    /// Notion does no Keychain, disk or network work unless it is selected.
    private func applySelection() {
        guard hasStarted else { return }
        notion.setActive(selectedKind == .notion)
    }
}
