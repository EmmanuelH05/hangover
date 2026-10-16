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
    /// The last day of a date range, when the task has one that runs past
    /// its first day (a Notion date range). `dueDate` stays the first day.
    var endDate: Date? = nil

    /// The day after which the task is overdue: the end of its range, else
    /// its due date (D9).
    var overdueDate: Date? { endDate ?? dueDate }
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
    /// Why the last write did not happen. Cleared by the next write and by a
    /// change of list. It feeds `errorMessage`, which the card shows (D2).
    private(set) var lastWriteError: NookRemindersWriteError?

    var selectedListID: String? {
        didSet {
            guard selectedListID != oldValue else { return }
            lastWriteError = nil
            if let selectedListID {
                defaults.set(selectedListID, forKey: Self.listKey)
            } else {
                defaults.removeObject(forKey: Self.listKey)
            }
            refresh()
        }
    }

    @ObservationIgnored private(set) weak var nook: NookModel?
    /// Made on first use. The demo mode (D51) never makes one.
    @ObservationIgnored private var madeStore: EKEventStore?
    private var store: EKEventStore {
        if let madeStore { return madeStore }
        let made = EKEventStore()
        madeStore = made
        return made
    }
    @ObservationIgnored private let defaults: UserDefaults
    /// The EventKit calls a write makes; a test hands in its own.
    @ObservationIgnored private let writes: NookRemindersWrites
    /// True in the demo mode (D51): the tasks are samples held in memory,
    /// and EventKit is never touched.
    @ObservationIgnored private let holdsSampleTasks: Bool
    @ObservationIgnored private var sampleAdds = 0
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

    /// `access` is EventKit itself unless a test hands in its own. The demo
    /// mode hands in `sample` tasks and no store is ever made (D51).
    init(
        access: NookEventKitAccess? = nil,
        defaults: UserDefaults = .standard,
        sample: [NookTodoItem]? = nil,
        writes: NookRemindersWrites = .eventKit
    ) {
        self.defaults = defaults
        self.writes = writes
        selectedListID = defaults.string(forKey: Self.listKey)
        holdsSampleTasks = sample != nil
        if let sample {
            self.access = NookEventKitAccess(status: { .fullAccess }, request: {})
            asksRealEventKit = false
            items = sample
        } else {
            let store = EKEventStore()
            madeStore = store
            self.access = access ?? .reminders(in: store)
            asksRealEventKit = access == nil
        }
        authorization = self.access.status()
    }

    /// Name of the list the card shows.
    var currentListName: String {
        if holdsSampleTasks { return DemoTodo.listName }
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
        guard !holdsSampleTasks else {
            refresh()
            return
        }
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
        // The prompt comes up under an open island unless it steps aside.
        nook?.systemPromptBegan()
        await access.request()
        nook?.systemPromptEnded()
        isAskingForAccess = false
        refresh()
        return true
    }

    func refresh() {
        authorization = access.status()
        if holdsSampleTasks {
            lists = [NookReminderList(id: "demo-list", title: DemoTodo.listName, color: .blue)]
            return
        }
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

    /// Adds a reminder. `due` is a whole day; the reminder gets that day and
    /// no time (D69).
    func add(_ title: String, due: DateComponents?) {
        addReminder(title, due: due)
    }

    /// The same, answering whether the reminder was saved. A refusal sets
    /// `lastWriteError`, which the card shows, and is logged (D2).
    func addConfirmed(_ title: String, due: DateComponents?) async -> Bool {
        addReminder(title, due: due)
    }

    @discardableResult
    private func addReminder(_ title: String, due: DateComponents?) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let day = NookTodoDay.normalized(due)
        if holdsSampleTasks {
            guard !trimmed.isEmpty else { return false }
            sampleAdds += 1
            items.append(NookTodoItem(
                id: "demo-added-task-\(sampleAdds)", title: trimmed,
                dueDate: day.flatMap { NookTodoDay.date(from: $0, calendar: .current) },
                isCompleted: false, listName: DemoTodo.listName
            ))
            return true
        }
        // No access and a blank title are the card's to prevent: the field is
        // off without access, and a blank line adds nothing.
        guard hasAccess, !trimmed.isEmpty else { return false }
        lastWriteError = nil
        guard let calendar = writes.listForNewReminder(store, selectedListID) else {
            reportWriteFailure(.noList, error: nil)
            return false
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = trimmed
        reminder.calendar = calendar
        reminder.dueDateComponents = Self.dueComponents(for: day)
        do {
            try writes.save(store, reminder)
        } catch {
            reportWriteFailure(.addFailed, error: error)
            return false
        }
        refresh()
        return true
    }

    /// Keeps the reason for the card and writes it to the log.
    private func reportWriteFailure(_ failure: NookRemindersWriteError, error: (any Error)?) {
        lastWriteError = failure
        let reason = error.map { String(describing: $0) } ?? "no list to write to"
        nookTodoDueLog.error(
            "Reminders write failed (\(failure.rawValue, privacy: .public)): \(reason, privacy: .private)"
        )
    }

    /// How EventKit is given a whole day: year, month and day on the
    /// Gregorian calendar, with no time and no time zone, so the day does not
    /// move when the Mac does. Nil for no date.
    static func dueComponents(for day: DateComponents?) -> DateComponents? {
        guard let day = NookTodoDay.normalized(day) else { return nil }
        return DateComponents(calendar: Calendar(identifier: .gregorian), year: day.year, month: day.month, day: day.day)
    }

    func complete(_ id: String) {
        if holdsSampleTasks {
            items.removeAll { $0.id == id }
            return
        }
        guard hasAccess, let reminder = writes.reminder(store, id) else { return }
        lastWriteError = nil
        reminder.isCompleted = true
        do {
            try writes.save(store, reminder)
        } catch {
            reportWriteFailure(.completeFailed, error: error)
            return
        }
        items.removeAll { $0.id == id }
        refresh()
    }

    /// Writes the reminder's notes. Empty text clears them.
    func setNotes(_ notes: String, for id: String) {
        if holdsSampleTasks {
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            items[index].notes = notes.isEmpty ? nil : notes
            return
        }
        guard hasAccess, let reminder = writes.reminder(store, id) else { return }
        lastWriteError = nil
        reminder.notes = notes.isEmpty ? nil : notes
        do {
            try writes.save(store, reminder)
        } catch {
            // The row keeps its old notes, and the editor keeps the draft.
            reportWriteFailure(.notesFailed, error: error)
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
        NookRemindersWrites.resolveList(in: store, selectedListID: selectedListID)
    }
}
