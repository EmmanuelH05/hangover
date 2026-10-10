import Foundation

/// The sample to-do list (D51): six plain tasks, one with a due date and one
/// with notes. The Reminders service holds them in memory in place of the
/// user's lists. The card, the closed island's count and the tour's
/// to-dos page then read them the way they read real reminders.
enum DemoTodo {
    static let listName = "Reminders"

    /// Tomorrow at 5 PM is the due date, relative to `now`.
    static func items(now: Date, calendar: Calendar = .current) -> [NookTodoItem] {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let due = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: tomorrow)
        func task(_ index: Int, _ title: String, due: Date? = nil, notes: String? = nil) -> NookTodoItem {
            NookTodoItem(
                id: "demo-task-\(index)", title: title, dueDate: due,
                isCompleted: false, listName: listName, notes: notes
            )
        }
        return [
            task(0, "Finish problem set 3", due: due),
            task(1, "Email the TA", notes: "Ask about the midterm room and the practice exam."),
            task(2, "Review the pull request"),
            task(3, "Book flights"),
            task(4, "Renew library books"),
            task(5, "Plan the weekend"),
        ]
    }
}
