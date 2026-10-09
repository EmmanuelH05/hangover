import Foundation

/// Due date wording shared by the task list and the notes page.
extension NookTodoCard {
    static func isOverdue(_ date: Date) -> Bool {
        date < Calendar.current.startOfDay(for: .now)
    }

    static func dueLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: date)).day ?? 0
        let format = (days > 0 && days < 7) ? "EEEE" : "MMM d"
        return formatted(date, format)
    }

    private static func formatted(_ date: Date, _ format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = format
        return f.string(from: date)
    }
}
