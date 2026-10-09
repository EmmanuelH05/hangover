import AppKit
import EventKit
import Foundation
import Observation
import SwiftUI

struct NookTodoItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let dueDate: Date?
    let isCompleted: Bool
    let listName: String
    /// Free text attached to the task. Nil when there is none.
    var notes: String? = nil
}

struct NookReminderList: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let color: Color
}

@MainActor
@Observable
final class NookRemindersService {
    private static let listKey = "nook.todo.listID"

    private(set) var items: [NookTodoItem] = []
    private(set) var lists: [NookReminderList] = []
    private(set) var authorization: EKAuthorizationStatus = .notDetermined

    var selectedListID: String? = UserDefaults.standard.string(forKey: "nook.todo.listID") {
        didSet {
            guard selectedListID != oldValue else { return }
            if let selectedListID {
                UserDefaults.standard.set(selectedListID, forKey: Self.listKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.listKey)
            }
            refresh()
        }
    }

    @ObservationIgnored private(set) weak var nook: NookModel?
    @ObservationIgnored private let store: EKEventStore
    /// The reminders permission: its status and the one way to ask for it.
    @ObservationIgnored private let access: NookEventKitAccess
    /// True while a request is up, which keeps a second one from going out.
    @ObservationIgnored private var isAskingForAccess = false
    /// True when the permission is EventKit's own and not one a test made up.
    @ObservationIgnored private let asksRealEventKit: Bool
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var generation = 0

    var hasAccess: Bool { authorization == .fullAccess }

    /// `access` is EventKit itself unless a test hands in its own.
    init(access: NookEventKitAccess? = nil) {
        let store = EKEventStore()
        self.store = store
        self.access = access ?? .reminders(in: store)
        asksRealEventKit = access == nil
        authorization = self.access.status()
    }

    /// Name of the list the card shows.
    var currentListName: String {
        if let selectedListID, let match = lists.first(where: { $0.id == selectedListID }) {
            return match.title
        }
        return store.defaultCalendarForNewReminders()?.title ?? "Reminders"
    }

    /// Starts the change observer and loads tasks when access was granted
    /// on an earlier run. Asks macOS for nothing: a permission that was
    /// never decided waits for `requestAccess()`.
    func start(nook: NookModel) {
        self.nook = nook
        hasStarted = true
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    /// Asks macOS for full access if that was never decided, then loads
    /// tasks. Called when the to-do tile first comes into view with
    /// Reminders as its source, and when the widget or that source is
    /// turned on in Settings. Never at launch.
    func requestAccess() {
        Task { @MainActor in await requestAccessIfUndecided() }
    }

    /// The same, awaited. True when macOS was asked.
    ///
    /// The real EventKit request goes out only from a service that was
    /// started, which the app does at launch and no test does. A service a
    /// test built with a permission of its own may be asked at any time.
    @discardableResult
    func requestAccessIfUndecided() async -> Bool {
        guard hasStarted || !asksRealEventKit else { return false }
        let status = access.status()
        guard NookAccessTiming.shouldRequest(status: status, isAlreadyAsking: isAskingForAccess) else {
            // Answered already, or a request is up. Tasks are loaded again
            // only when the answer changed behind the app's back, in System
            // Settings: a tile coming into view must not cost a fetch.
            if status != authorization { refresh() }
            return false
        }
        authorization = status
        isAskingForAccess = true
        await access.request()
        isAskingForAccess = false
        refresh()
        return true
    }

    func refresh() {
        authorization = access.status()
        guard hasAccess else {
            items = []
            lists = []
            return
        }
        lists = store.calendars(for: .reminder).map {
            NookReminderList(id: $0.calendarIdentifier, title: $0.title, color: Color(nsColor: $0.color ?? .systemBlue))
        }
        guard let calendar = resolveCalendar() else {
            items = []
            return
        }
        generation += 1
        let token = generation
        let listName = calendar.title
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: [calendar]
        )
        store.fetchReminders(matching: predicate) { @Sendable reminders in
            // Convert to value types before leaving the callback.
            let sorted = (reminders ?? []).sorted { a, b in
                let da = a.dueDateComponents?.date
                let db = b.dueDateComponents?.date
                switch (da, db) {
                case let (x?, y?) where x != y: return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return (a.creationDate ?? .distantPast) < (b.creationDate ?? .distantPast)
                }
            }
            let mapped = sorted.map {
                NookTodoItem(
                    id: $0.calendarItemIdentifier,
                    title: $0.title ?? "",
                    dueDate: $0.dueDateComponents?.date,
                    isCompleted: $0.isCompleted,
                    listName: listName,
                    notes: $0.notes.flatMap { $0.isEmpty ? nil : $0 }
                )
            }
            Task { @MainActor [weak self] in
                guard let self, token == self.generation else { return }
                self.items = mapped
            }
        }
    }

    func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasAccess, !trimmed.isEmpty, let calendar = resolveCalendar() else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = trimmed
        reminder.calendar = calendar
        do {
            try store.save(reminder, commit: true)
        } catch {
            return
        }
        refresh()
    }

    func complete(_ id: String) {
        guard hasAccess, let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
        } catch {
            return
        }
        items.removeAll { $0.id == id }
        refresh()
    }

    /// Writes the reminder's notes. Empty text clears them.
    func setNotes(_ notes: String, for id: String) {
        guard hasAccess, let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.notes = notes.isEmpty ? nil : notes
        do {
            try store.save(reminder, commit: true)
        } catch {
            // The row keeps its old notes, and the editor keeps the draft.
            return
        }
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].notes = notes.isEmpty ? nil : notes
        }
        refresh()
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }

    private func resolveCalendar() -> EKCalendar? {
        if let selectedListID,
           let match = store.calendars(for: .reminder).first(where: { $0.calendarIdentifier == selectedListID }) {
            return match
        }
        return store.defaultCalendarForNewReminders()
    }
}
