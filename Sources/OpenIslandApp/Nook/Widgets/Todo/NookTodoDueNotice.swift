import Foundation

/// A time of day, on the calendar's clock.
struct NookTodoDueTime: Equatable, Sendable {
    var hour: Int
    var minute: Int = 0

    /// When the due-day reminder first speaks (D69).
    static let morning = NookTodoDueTime(hour: 9)
}

/// What the closed notch says about to-dos and their dates (D69): the ones
/// due today, and the ones past their date. Pure: every rule takes `now` and
/// `calendar`, and nothing reads the clock.
struct NookTodoDueNotice: Equatable, Sendable {
    enum Wording: Equatable, Sendable {
        /// One to-do is due today, named by its title.
        case oneDue(title: String)
        case manyDue(count: Int)
        case overdue(count: Int)
    }

    let wording: Wording
    /// The to-dos the notice is about, in list order.
    let itemIDs: [String]
    /// The day it was made for, as `2026-10-14`.
    let day: String

    /// The mark in the closed notch's left wing. The island draws a symbol
    /// from the system set there, and this is the to-do widget's own.
    static let symbol = "checklist"

    /// The closed notch has room for about 18 characters, and the words after
    /// the title are the ones that matter.
    private static let maxTitleLength = 8

    /// What the record of shown notices keeps for this notice.
    var shownKeys: [String] {
        switch wording {
        case .oneDue, .manyDue: itemIDs.map { NookTodoDueShown.taskKey($0, day: day) }
        case .overdue: [NookTodoDueShown.overdueKey(day: day)]
        }
    }

    /// Which kind of notice this is, for the log. No title: that is the user's.
    var logKind: String {
        switch wording {
        case .oneDue: "one due today"
        case .manyDue: "several due today"
        case .overdue: "overdue"
        }
    }

    func text(lang: LanguageManager) -> String {
        switch wording {
        case .oneDue(let title):
            lang.t("nook.todo.due.notice.one", title.isEmpty ? lang.t("nook.todo.notion.untitled") : title)
        case .manyDue(let count):
            lang.t("nook.todo.due.notice.many", count)
        case .overdue(let count):
            count == 1 ? lang.t("nook.todo.due.notice.overdue.one") : lang.t("nook.todo.due.notice.overdue.many", count)
        }
    }

    /// A title cut to fit the closed notch. Empty for a title with no words.
    static func shortTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxTitleLength else { return trimmed }
        return String(trimmed.prefix(maxTitleLength - 1)) + "…"
    }

    /// The notices to show now, in the order to show them: what is due today
    /// first, then what is overdue.
    ///
    /// Nothing shows before `remindAt` on the calendar's clock. A to-do that
    /// is done, or has no date, never shows. A to-do already in `shown` for
    /// today is left out, so a due-today notice names only the to-dos that
    /// are new today. The overdue notice counts every to-do past its date,
    /// and comes once a day.
    static func notices(
        items: [NookTodoItem],
        now: Date,
        calendar: Calendar,
        shown: NookTodoDueShown,
        remindAt: NookTodoDueTime = .morning
    ) -> [NookTodoDueNotice] {
        guard hasReached(remindAt, at: now, calendar: calendar) else { return [] }
        let day = NookTodoDay.key(of: now, calendar: calendar)
        let (dueToday, overdue) = sorting(items, now: now, calendar: calendar)

        var result: [NookTodoDueNotice] = []
        let fresh = dueToday.filter { !shown.hasShown(task: $0.id, on: day) }
        if let first = fresh.first {
            let wording: Wording = fresh.count == 1
                ? .oneDue(title: shortTitle(first.title))
                : .manyDue(count: fresh.count)
            result.append(NookTodoDueNotice(wording: wording, itemIDs: fresh.map(\.id), day: day))
        }
        if !overdue.isEmpty, !shown.hasShownOverdue(on: day) {
            result.append(NookTodoDueNotice(wording: .overdue(count: overdue.count), itemIDs: overdue.map(\.id), day: day))
        }
        return result
    }

    /// The open, dated to-dos that are due today and the ones past their
    /// date, in list order.
    private static func sorting(
        _ items: [NookTodoItem], now: Date, calendar: Calendar
    ) -> (dueToday: [NookTodoItem], overdue: [NookTodoItem]) {
        let today = calendar.startOfDay(for: now)
        var dueToday: [NookTodoItem] = []
        var overdue: [NookTodoItem] = []
        for item in items where !item.isCompleted {
            guard let due = item.dueDate else { continue }
            let dueDay = calendar.startOfDay(for: due)
            if dueDay == today {
                dueToday.append(item)
            } else if dueDay < today, calendar.startOfDay(for: item.overdueDate ?? due) < today {
                // A date range is overdue once its end has passed, not its
                // start. The due day stays the start (D9).
                overdue.append(item)
            }
        }
        return (dueToday, overdue)
    }

    /// Why `notices` gave nothing, for the log (D6). Nil while there is
    /// something to say.
    enum Silence: Equatable, Sendable {
        /// It is before the reminder time on the calendar's clock.
        case beforeReminderTime
        /// Nothing open is due today or past its date.
        case nothingDue
        /// What is due or late was said already today.
        case alreadyShown

        var logText: String {
            switch self {
            case .beforeReminderTime: "it is before the reminder time"
            case .nothingDue: "nothing open is due today or overdue"
            case .alreadyShown: "everything due or overdue was said already today"
            }
        }
    }

    static func silence(
        items: [NookTodoItem],
        now: Date,
        calendar: Calendar,
        shown: NookTodoDueShown,
        remindAt: NookTodoDueTime = .morning
    ) -> Silence? {
        guard hasReached(remindAt, at: now, calendar: calendar) else { return .beforeReminderTime }
        guard notices(items: items, now: now, calendar: calendar, shown: shown, remindAt: remindAt).isEmpty else {
            return nil
        }
        let (dueToday, overdue) = sorting(items, now: now, calendar: calendar)
        return dueToday.isEmpty && overdue.isEmpty ? .nothingDue : .alreadyShown
    }

    /// True once the calendar's clock has reached `time` on the day of `now`.
    static func hasReached(_ time: NookTodoDueTime, at now: Date, calendar: Calendar) -> Bool {
        let start = calendar.startOfDay(for: now)
        let moment = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: start, matchingPolicy: .nextTime)
        return now >= (moment ?? start.addingTimeInterval(TimeInterval(time.hour * 3600 + time.minute * 60)))
    }
}

/// The notices already shown, by day. Saved in settings so a notice is not
/// repeated the same day, even across relaunches, and kept for seven days.
///
/// A key is `2026-10-14|task|<id>` for one to-do and `2026-10-14|overdue`
/// for the overdue notice. The day leads, so a key's age can be read without
/// knowing what follows it.
struct NookTodoDueShown: Equatable, Sendable {
    /// Today and the six days before it.
    static let daysKept = 7
    private static let separator: Character = "|"

    private(set) var keys: Set<String>

    init() {
        keys = []
    }

    init<S: Sequence>(keys: S) where S.Element == String {
        self.keys = Set(keys)
    }

    static func taskKey(_ id: String, day: String) -> String {
        "\(day)\(separator)task\(separator)\(id)"
    }

    static func overdueKey(day: String) -> String {
        "\(day)\(separator)overdue"
    }

    func hasShown(task id: String, on day: String) -> Bool {
        keys.contains(Self.taskKey(id, day: day))
    }

    func hasShownOverdue(on day: String) -> Bool {
        keys.contains(Self.overdueKey(day: day))
    }

    /// A copy that also holds everything these notices said.
    func recording(_ notices: [NookTodoDueNotice]) -> NookTodoDueShown {
        NookTodoDueShown(keys: keys.union(notices.flatMap(\.shownKeys)))
    }

    /// A copy without anything older than the last seven days, and without
    /// anything that is not a key this type wrote.
    func trimmed(now: Date, calendar: Calendar) -> NookTodoDueShown {
        let start = calendar.startOfDay(for: now)
        guard let oldest = calendar.date(byAdding: .day, value: -(Self.daysKept - 1), to: start) else { return self }
        let oldestDay = NookTodoDay.key(of: oldest, calendar: calendar)
        return NookTodoDueShown(keys: keys.filter { key in
            guard let day = Self.day(of: key) else { return false }
            return day >= oldestDay
        })
    }

    /// The keys as saved: sorted, so the same record always saves the same.
    var saved: [String] { keys.sorted() }

    /// The day a key leads with, when it is one.
    private static func day(of key: String) -> String? {
        guard let day = key.split(separator: separator, maxSplits: 1, omittingEmptySubsequences: false).first,
              day.count == 10 else { return nil }
        let characters = Array(day)
        for (index, character) in characters.enumerated() {
            let isDash = index == 4 || index == 7
            if isDash ? character != "-" : !character.isASCII || !character.isNumber { return nil }
        }
        return String(day)
    }
}
