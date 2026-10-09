import Foundation

/// One row of the card plus what a write needs to know about its task.
struct TickTickRow: Equatable, Sendable {
    var item: NookTodoItem
    /// The list the task lives in. Completing and editing both need it.
    let projectID: String
    let notesField: TickTickNotesField
}

/// Turns TickTick tasks into the card's rows. Pure: no clock, no network.
enum TickTickTaskMapper {
    /// Open tasks, soonest due first, then in TickTick's own order.
    static func rows(
        from tasks: [TickTickTask],
        listID: String,
        listName: String,
        limit: Int,
        calendar: Calendar = .current
    ) -> [TickTickRow] {
        let parser = TickTickDateParser()
        let open = tasks.filter { $0.status == TickTickTask.statusOpen && $0.kind?.uppercased() != "NOTE" }
        let dated = open.map { task in (task: task, due: dueDate(of: task, parser: parser, calendar: calendar)) }
        let sorted = dated.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                if a.task.sortOrder != b.task.sortOrder { return a.task.sortOrder < b.task.sortOrder }
                return a.task.id < b.task.id
            }
        }
        return sorted.prefix(max(limit, 0)).map { entry in
            let field = notesField(of: entry.task)
            return TickTickRow(
                item: NookTodoItem(
                    id: entry.task.id,
                    title: entry.task.title,
                    dueDate: entry.due,
                    isCompleted: false,
                    listName: listName,
                    notes: field == .desc ? entry.task.desc : entry.task.content
                ),
                projectID: entry.task.projectID ?? listID,
                notesField: field
            )
        }
    }

    /// A task with a checklist shows `desc` as its note. Every other task
    /// shows `content`.
    static func notesField(of task: TickTickTask) -> TickTickNotesField {
        task.kind?.uppercased() == "CHECKLIST" || task.hasChecklistItems ? .desc : .content
    }

    /// When the task is due, as the card should show it.
    ///
    /// An all-day task is sent as midnight in the zone it was set in. Read
    /// in another zone that moment can fall on the day before, which is why
    /// the day is taken in the task's zone and placed on the same day here.
    ///
    /// An all-day task that runs over several days ends, as sent, on the day
    /// after its last one. That is how other TickTick clients read it, and it
    /// is not in TickTick's docs. The last day is the one shown.
    static func dueDate(of task: TickTickTask, calendar: Calendar = .current) -> Date? {
        dueDate(of: task, parser: TickTickDateParser(), calendar: calendar)
    }

    private static func dueDate(of task: TickTickTask, parser: TickTickDateParser, calendar: Calendar) -> Date? {
        guard let raw = task.dueDate, let moment = parser.date(from: raw) else { return nil }
        guard task.isAllDay else { return moment }
        var zoned = Calendar(identifier: .gregorian)
        zoned.timeZone = task.timeZone.flatMap(TimeZone.init(identifier:)) ?? calendar.timeZone
        var lastDay = moment
        if let start = task.startDate.flatMap({ parser.date(from: $0) }), start < moment,
           let before = zoned.date(byAdding: .day, value: -1, to: moment) {
            lastDay = before
        }
        let day = zoned.dateComponents([.year, .month, .day], from: lastDay)
        var local = Calendar(identifier: .gregorian)
        local.timeZone = calendar.timeZone
        return local.date(from: day) ?? moment
    }
}

/// Reads the two date shapes TickTick sends: `2019-11-13T03:00:00+0000` and
/// `2026-03-05T00:00:00.000+0000`. Made once per list, not once per task.
struct TickTickDateParser {
    private let formatters: [DateFormatter]

    init() {
        formatters = ["yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZ"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            return formatter
        }
    }

    func date(from raw: String) -> Date? {
        for formatter in formatters {
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }
}
