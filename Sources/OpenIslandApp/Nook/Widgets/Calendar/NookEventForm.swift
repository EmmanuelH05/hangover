import Foundation

/// When an event reminds the user. All-day events have their own short
/// list, because "15 minutes before" means nothing for a day.
enum NookEventAlert: String, CaseIterable, Identifiable, Sendable {
    case none
    case atStart
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case oneDay

    var id: String { rawValue }

    private static let hour: TimeInterval = 3600
    /// All-day events alert at nine in the morning.
    private static let allDayAlertHour: TimeInterval = 9

    static func options(isAllDay: Bool) -> [NookEventAlert] {
        isAllDay ? [.none, .atStart, .oneDay] : allCases
    }

    func title(isAllDay: Bool) -> String {
        switch self {
        case .none: "No alert"
        case .atStart: isAllDay ? "On the day, 9 AM" : "At start"
        case .fiveMinutes: "5 min before"
        case .fifteenMinutes: "15 min before"
        case .thirtyMinutes: "30 min before"
        case .oneHour: "1 hr before"
        case .oneDay: isAllDay ? "Day before, 9 AM" : "1 day before"
        }
    }

    /// Seconds from the event's start to the alert, negative for before.
    /// Nil for no alert.
    func offset(isAllDay: Bool) -> TimeInterval? {
        switch self {
        case .none: nil
        case .atStart: isAllDay ? Self.allDayAlertHour * Self.hour : 0
        case .fiveMinutes: -5 * 60
        case .fifteenMinutes: -15 * 60
        case .thirtyMinutes: -30 * 60
        case .oneHour: -Self.hour
        case .oneDay: isAllDay ? (Self.allDayAlertHour - 24) * Self.hour : -24 * Self.hour
        }
    }

    /// The nearest choice an all-day or a timed event offers.
    func fitting(isAllDay: Bool) -> NookEventAlert {
        Self.options(isAllDay: isAllDay).contains(self) ? self : .atStart
    }
}

enum NookEventRepeat: String, CaseIterable, Identifiable, Sendable {
    case never
    case daily
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: "Does not repeat"
        case .daily: "Every day"
        case .weekly: "Every week"
        case .monthly: "Every month"
        case .yearly: "Every year"
        }
    }
}

/// The parts of the day the start-time menu is split into, which keeps each
/// list short enough to read without scrolling.
enum NookEventDayPart: String, CaseIterable, Identifiable, Sendable {
    case morning
    case afternoon
    case evening
    case night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        case .night: "Night"
        }
    }

    private var firstHour: Int {
        switch self {
        case .morning: 6
        case .afternoon: 12
        case .evening: 18
        case .night: 0
        }
    }

    /// Start times in this part of the day, as minutes after midnight.
    var minutes: [Int] {
        let first = firstHour * 60
        return stride(from: first, to: first + 6 * 60, by: NookEventForm.minuteStep).map { $0 }
    }
}

/// Everything the event editor holds, as a value. The editor's controls
/// change it through the functions below, and `draft` turns it into what
/// gets saved.
struct NookEventForm: Equatable, Sendable {
    var title = ""
    /// Start of the event's day.
    var day: Date
    /// Minutes after midnight the event starts.
    var startMinute: Int
    var durationMinutes: Int = NookEventForm.defaultDuration
    var isAllDay = false
    var location = ""
    var notes = ""
    /// Nil saves to the system's default calendar.
    var calendarID: String?
    var alert: NookEventAlert = .none
    var repeats: NookEventRepeat = .never

    static let defaultDuration = 60
    static let minuteStep = 15
    static let minutesPerDay = 24 * 60
    /// Lengths the end-time menu offers.
    static let durations = [15, 30, 45, 60, 90, 120, 180, 240, 360, 480]
    private static let defaultStartMinute = 9 * 60
    private static let halfHour = 30

    /// A fresh form for `day`. Today starts at the next half hour, any
    /// other day at nine in the morning.
    static func new(on day: Date, now: Date, calendar: Calendar) -> NookEventForm {
        let start = calendar.startOfDay(for: day)
        guard calendar.isDate(day, inSameDayAs: now) else {
            return NookEventForm(day: start, startMinute: defaultStartMinute)
        }
        let minutesNow = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let next = (minutesNow / halfHour + 1) * halfHour
        // Too late for another slot today: keep it on today's last one.
        return NookEventForm(day: start, startMinute: min(next, minutesPerDay - halfHour))
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var canSave: Bool { !trimmedTitle.isEmpty }

    /// True once the user has typed anything worth keeping.
    var hasContent: Bool {
        !trimmedTitle.isEmpty
            || !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func start(calendar: Calendar) -> Date {
        calendar.date(byAdding: .minute, value: startMinute, to: day) ?? day
    }

    func end(calendar: Calendar) -> Date {
        calendar.date(byAdding: .minute, value: startMinute + durationMinutes, to: day) ?? day
    }

    /// What saving the form writes.
    func draft(calendar: Calendar) -> NookEventDraft {
        let dayStart = calendar.startOfDay(for: day)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return NookEventDraft(
            title: trimmedTitle,
            start: isAllDay ? dayStart : start(calendar: calendar),
            end: isAllDay ? nextDay : end(calendar: calendar),
            isAllDay: isAllDay,
            location: location.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            calendarID: calendarID,
            alert: alert.fitting(isAllDay: isAllDay),
            repeats: repeats
        )
    }

    // MARK: Changes

    func settingAllDay(_ isOn: Bool) -> NookEventForm {
        var next = self
        next.isAllDay = isOn
        next.alert = alert.fitting(isAllDay: isOn)
        return next
    }

    /// Picking a start time makes the event a timed one and keeps its length.
    func settingStart(minute: Int) -> NookEventForm {
        var next = settingAllDay(false)
        next.startMinute = min(max(0, minute), Self.minutesPerDay - Self.minuteStep)
        return next
    }

    func settingDuration(minutes: Int) -> NookEventForm {
        var next = settingAllDay(false)
        next.durationMinutes = min(max(Self.minuteStep, minutes), Self.minutesPerDay)
        return next
    }

    // MARK: A time or a day typed into the title

    /// What the title asks for when it names a time or a day ("dinner fri
    /// 7pm"). Nil when it names neither, or when the form already says the
    /// same. The editor offers it; nothing changes until the user takes it.
    func suggestion(now: Date, calendar: Calendar) -> NookEventDraft? {
        guard let parsed = NookEventQuickAdd.parse(title, on: day, now: now, calendar: calendar) else { return nil }
        let namesDay = NookEventQuickAdd.namesDay(title, now: now, calendar: calendar)
        guard namesDay || !parsed.isAllDay else { return nil }
        return applying(parsed, calendar: calendar) == self ? nil : parsed
    }

    /// The form with a suggestion taken: its day, its times when it has
    /// any, and the title with those words removed.
    func applying(_ suggestion: NookEventDraft, calendar: Calendar) -> NookEventForm {
        var next = self
        next.title = suggestion.title
        next.day = calendar.startOfDay(for: suggestion.start)
        // A title that names only a day leaves the times and All day alone.
        guard !suggestion.isAllDay else { return next }
        next = next.settingAllDay(false)
        next.startMinute = calendar.component(.hour, from: suggestion.start) * 60
            + calendar.component(.minute, from: suggestion.start)
        let length = Int((suggestion.end.timeIntervalSince(suggestion.start) / 60).rounded())
        next.durationMinutes = min(max(1, length), Self.minutesPerDay)
        return next
    }
}

extension NookEventDraft {
    /// What the draft will save, in one line: "Fri, Oct 9, 7:00 PM to
    /// 8:00 PM" or "Fri, Oct 9, all day". Pure: it formats with the passed
    /// calendar and locale only.
    func summary(now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let day = NookEventText.day(start, now: now, calendar: calendar, locale: locale)
        guard !isAllDay else { return "\(day), all day" }
        let from = NookEventText.time(start, calendar: calendar, locale: locale)
        let to = NookEventText.time(end, calendar: calendar, locale: locale)
        return "\(day), \(from) to \(to)"
    }
}

/// Dates, times and lengths as the editor writes them.
enum NookEventText {
    /// "Fri, Oct 9", with the year added when it is not this year. "5/12"
    /// typed in October means next May, and the line has to say that.
    static func day(_ date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let style = Date.FormatStyle(
            date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone
        ).weekday(.abbreviated).month(.abbreviated).day()
        let isThisYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return date.formatted(isThisYear ? style : style.year())
    }

    static func time(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        date.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        )
    }

    /// "45 min", "1 hr", "1.5 hr".
    static func duration(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = Double(minutes) / 60
        return hours == hours.rounded() ? "\(Int(hours)) hr" : String(format: "%.1f hr", hours)
    }
}

/// Size of the event editor at the top of the Nook page.
enum NookEventEditorLayout {
    static let height: CGFloat = 222
    /// Width of the month on the editor's left.
    static let monthWidth: CGFloat = 154

    /// Height the editor adds above the grid: itself and one row gap.
    static var pageHeight: CGFloat { height + NookWidgetLayout.rowSpacing }
}
