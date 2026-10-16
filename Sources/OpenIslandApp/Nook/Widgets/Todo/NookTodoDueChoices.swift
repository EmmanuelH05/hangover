import Foundation

/// One line of the date menu on the add field (D69).
struct NookTodoDueChoice: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case today
        case tomorrow
        /// Any later day, which the menu names by its date.
        case day
    }

    let kind: Kind
    /// The whole day, which is what every source is given.
    let day: DateComponents
    /// The start of that day on the calendar's clock.
    let date: Date

    var id: String { NookTodoDay.isoString(day) ?? "\(kind)" }

    /// "Today", "Tomorrow", or the weekday and date: "Thu, Oct 16".
    func title(lang: LanguageManager, locale: Locale, calendar: Calendar) -> String {
        switch kind {
        case .today: lang.t("nook.todo.due.today")
        case .tomorrow: lang.t("nook.todo.due.tomorrow")
        case .day: NookTodoDueChoices.format(NookTodoDueChoices.menuTemplate, date: date, locale: locale, calendar: calendar)
        }
    }
}

/// The days the date menu offers and the words on the date button. Pure:
/// every rule takes `now` and `calendar`, and nothing reads the clock.
enum NookTodoDueChoices {
    /// Today, tomorrow, and the five days after.
    static let optionCount = 7
    /// A day this many days ahead or fewer is named by its weekday on the
    /// button. The first day after that shows its date.
    static let weekdayRange = 2...6

    static let menuTemplate = "EEEMMMd"
    private static let weekdayTemplate = "EEE"
    private static let dateTemplate = "MMMd"

    static func options(now: Date, calendar: Calendar) -> [NookTodoDueChoice] {
        let start = calendar.startOfDay(for: now)
        return (0..<optionCount).compactMap { offset in
            guard let moment = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let date = calendar.startOfDay(for: moment)
            let kind: NookTodoDueChoice.Kind = switch offset {
            case 0: .today
            case 1: .tomorrow
            default: .day
            }
            return NookTodoDueChoice(kind: kind, day: NookTodoDay.components(of: date, calendar: calendar), date: date)
        }
    }

    /// What the button shows for the picked day: "Today", "Tomorrow", the
    /// weekday for the rest of the coming week ("Fri"), and the date past it
    /// ("Oct 21"). Empty for something that is not a real day.
    static func buttonLabel(
        for day: DateComponents,
        now: Date,
        calendar: Calendar,
        lang: LanguageManager,
        locale: Locale
    ) -> String {
        guard let date = NookTodoDay.date(from: day, calendar: calendar) else { return "" }
        let ahead = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: date).day ?? 0
        switch ahead {
        case 0: return lang.t("nook.todo.due.today")
        case 1: return lang.t("nook.todo.due.tomorrow")
        case weekdayRange: return format(weekdayTemplate, date: date, locale: locale, calendar: calendar)
        default: return format(dateTemplate, date: date, locale: locale, calendar: calendar)
        }
    }

    static func format(_ template: String, date: Date, locale: Locale, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
