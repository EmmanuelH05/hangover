import EventKit
import Foundation

/// Why a write to Reminders did not happen, which the card shows under the
/// rows (D2). It stays until the next write or a change of list.
enum NookRemindersWriteError: String, Equatable, Sendable {
    /// There is no list to put a new reminder in.
    case noList
    case addFailed
    case completeFailed
    case notesFailed

    var messageKey: String { "nook.todo.reminders.error.\(rawValue)" }
}

/// The EventKit calls a write makes. The real ones are `eventKit`; a test
/// hands in its own and never touches a store that holds anything.
@MainActor
struct NookRemindersWrites {
    /// The list a new reminder goes in: the picked one, else the default.
    var listForNewReminder: (_ store: EKEventStore, _ selectedListID: String?) -> EKCalendar?
    /// The reminder with this ID, if the store still has it.
    var reminder: (_ store: EKEventStore, _ id: String) -> EKReminder?
    var save: (_ store: EKEventStore, _ reminder: EKReminder) throws -> Void

    static let eventKit = NookRemindersWrites(
        listForNewReminder: { store, selectedListID in
            NookRemindersWrites.resolveList(in: store, selectedListID: selectedListID)
        },
        reminder: { store, id in store.calendarItem(withIdentifier: id) as? EKReminder },
        save: { store, reminder in try store.save(reminder, commit: true) }
    )

    /// The picked list while the store still has it, else the default for
    /// new reminders.
    static func resolveList(in store: EKEventStore, selectedListID: String?) -> EKCalendar? {
        if let selectedListID,
           let match = store.calendars(for: .reminder).first(where: { $0.calendarIdentifier == selectedListID }) {
            return match
        }
        return store.defaultCalendarForNewReminders()
    }
}
