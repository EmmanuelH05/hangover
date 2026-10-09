import Foundation

/// Turns typed text such as "lunch fri 1pm" into an event draft.
///
/// The parser is deterministic and pure: every date computation uses the passed
/// calendar and the passed `now`, never `Calendar.current` or `Date()`.
enum NookEventQuickAdd {
    /// Default length of a timed event when the text gives no end.
    static let defaultDuration: TimeInterval = 60 * 60
    /// Longest "for N hours" the parser accepts.
    static let maxDuration: TimeInterval = 24 * 60 * 60
    /// Written in capitals these are far more often an exam or a brand
    /// than a weekday, unless "on" or "next" comes first.
    private static let ambiguousCapitals: Set<String> = ["SAT", "SUN"]

    /// - Parameters:
    ///   - text: what the user typed.
    ///   - day: the day picked in the card; used when the text names no day.
    ///   - now: the current time, for words like "today" and "tomorrow".
    /// - Returns: nil when the text is empty after trimming.
    static func parse(_ text: String, on day: Date, now: Date = Date(), calendar: Calendar = .current) -> NookEventDraft? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var rest = trimmed
        let duration = extractDuration(&rest)
        let dayToken = extractDay(&rest, now: now, calendar: calendar)
        let times = extractTimes(&rest)
        let title = makeTitle(rest, matchedAny: rest != trimmed)

        let chosenDay = resolveDay(dayToken, start: times?.start, fallback: day, now: now, calendar: calendar)
        guard let times else {
            let start = calendar.startOfDay(for: chosenDay)
            return NookEventDraft(title: title, start: start, end: addDays(1, to: start, calendar: calendar), isAllDay: true)
        }

        let start = date(at: times.start, on: chosenDay, calendar: calendar)
        let end: Date
        if let endTime = times.end {
            let sameDay = date(at: endTime, on: chosenDay, calendar: calendar)
            end = sameDay > start ? sameDay : addDays(1, to: sameDay, calendar: calendar)
        } else {
            end = start.addingTimeInterval(duration ?? defaultDuration)
        }
        return NookEventDraft(title: title, start: start, end: end, isAllDay: false)
    }

    /// True when the text itself names a day ("fri", "5/12", "tomorrow").
    /// That day then wins over the one picked in the form.
    static func namesDay(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = extractDuration(&rest)
        return extractDay(&rest, now: now, calendar: calendar) != nil
    }

    // MARK: - Constants

    private static let secondsPerMinute: TimeInterval = 60
    private static let secondsPerHour: TimeInterval = 3600
    private static let minutesPerHour = 60
    private static let noonHour = 12
    /// Bare hours 1 to 7 read as afternoon; 8 to 11 read as morning.
    private static let bareAfternoonHours = 1...7
    private static let monthPrefixes = [
        "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec",
    ]
    private static let weekdayPrefixes = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    private static let trailingConnectives: Set<String> = ["at", "on", "from"]
    private static let fallbackTitle = "New event"
    private static let daysPerWeek = 7

    // MARK: - Patterns

    private static let notAfterWord = #"(?<![\w:/.\-])"#
    private static let notBeforeWord = #"(?![\w:/])"#
    private static let timePrefix = #"(?:(at\s+|@\s*))?"#

    private static let durationPattern =
        #"(?<![\w])for\s+(\d+(?:\.\d+)?)\s*(hours?|hrs?|h|minutes?|mins?|m)(?![\w])"#
    private static let numericDatePattern =
        #"(?<![\w/.])(?:on\s+)?(\d{1,2})/(\d{1,2})(?![\w/])"#
    private static let namedDatePattern =
        #"(?<![\w/])(?:on\s+)?(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?![\w:/])(?!\s*(?:am|pm)\b)"#
    private static let relativeDayPattern = #"(?<![\w])(today|tomorrow|tmrw)(?![\w])"#
    private static let weekdayPattern =
        #"(?<![\w])(?:on\s+)?(next\s+)?(mon(?:day)?|tue(?:s(?:day)?)?|wed(?:nesday)?|thu(?:r(?:s(?:day)?)?)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)(?![\w])"#
    private static let rangePattern =
        notAfterWord + #"(?:(at\s+|from\s+|@\s*))?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(?:-|to|until|\u2013|\u2014)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        + notBeforeWord
    private static let singleTimePattern =
        notAfterWord + timePrefix + #"(\d{1,2})(?::(\d{2}))?(?:\s*(am|pm))?"# + notBeforeWord
    private static let wordTimePattern = #"(?<![\w])(?:(at\s+))?(noon|midnight)(?![\w])"#

    // MARK: - Types

    private struct Hit {
        let range: NSRange
        let groups: [String?]
    }

    private struct ClockTime {
        let hour: Int
        let minute: Int
        var minuteOfDay: Int { hour * 60 + minute }
    }

    private struct TimeSpan {
        let start: ClockTime
        let end: ClockTime?
    }

    private enum DayToken {
        case fixed(Date)
        case weekday(Int, isNext: Bool)
    }

    // MARK: - Regex helpers

    private static func hits(_ pattern: String, in text: String) -> [Hit] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return matches.map { match in
            let groups = (0..<match.numberOfRanges).map { index -> String? in
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : ns.substring(with: range)
            }
            return Hit(range: match.range, groups: groups)
        }
    }

    private static func remove(_ hit: Hit, from text: String) -> String {
        (text as NSString).replacingCharacters(in: hit.range, with: " ")
    }

    // MARK: - Duration

    private static func extractDuration(_ rest: inout String) -> TimeInterval? {
        for hit in hits(durationPattern, in: rest) {
            guard let valueText = hit.groups[1], let value = Double(valueText), let unit = hit.groups[2] else { continue }
            let isHours = unit.lowercased().hasPrefix("h")
            let seconds = value * (isHours ? secondsPerHour : secondsPerMinute)
            // An absurd length stays in the title and the default applies.
            guard seconds.isFinite, seconds > 0, seconds <= maxDuration else { continue }
            rest = remove(hit, from: rest)
            return seconds
        }
        return nil
    }

    // MARK: - Day

    private static func extractDay(_ rest: inout String, now: Date, calendar: Calendar) -> DayToken? {
        let today = calendar.startOfDay(for: now)
        for hit in hits(numericDatePattern, in: rest) {
            guard let month = hit.groups[1].flatMap({ Int($0) }), let dayNumber = hit.groups[2].flatMap({ Int($0) }),
                  let date = nextDate(month: month, day: dayNumber, today: today, calendar: calendar) else { continue }
            rest = remove(hit, from: rest)
            return .fixed(date)
        }
        for hit in hits(namedDatePattern, in: rest) {
            guard let name = hit.groups[1]?.lowercased(),
                  let monthIndex = monthPrefixes.firstIndex(of: String(name.prefix(3))),
                  let dayNumber = hit.groups[2].flatMap({ Int($0) }),
                  let date = nextDate(month: monthIndex + 1, day: dayNumber, today: today, calendar: calendar) else { continue }
            rest = remove(hit, from: rest)
            return .fixed(date)
        }
        if let hit = hits(relativeDayPattern, in: rest).first, let word = hit.groups[1]?.lowercased() {
            rest = remove(hit, from: rest)
            return .fixed(word == "today" ? today : addDays(1, to: today, calendar: calendar))
        }
        let weekdayHit = hits(weekdayPattern, in: rest).first { hit in
            guard let raw = hit.groups[2] else { return false }
            let bare = hit.groups[0]?.trimmingCharacters(in: .whitespaces) == raw
            return !(bare && ambiguousCapitals.contains(raw))
        }
        if let hit = weekdayHit, let name = hit.groups[2]?.lowercased(),
           let index = weekdayPrefixes.firstIndex(of: String(name.prefix(3))) {
            rest = remove(hit, from: rest)
            return .weekday(index + 1, isNext: hit.groups[1] != nil)
        }
        return nil
    }

    /// The next month/day on or after `today`, or nil when the date does not exist.
    private static func nextDate(month: Int, day: Int, today: Date, calendar: Calendar) -> Date? {
        let year = calendar.component(.year, from: today)
        guard let thisYear = validDate(year: year, month: month, day: day, calendar: calendar) else { return nil }
        if thisYear >= today { return thisYear }
        return validDate(year: year + 1, month: month, day: day, calendar: calendar)
    }

    private static func validDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let parts = calendar.dateComponents([.month, .day], from: date)
        return parts.month == month && parts.day == day ? date : nil
    }

    private static func resolveDay(_ token: DayToken?, start: ClockTime?, fallback: Date, now: Date, calendar: Calendar) -> Date {
        switch token {
        case nil:
            return calendar.startOfDay(for: fallback)
        case .fixed(let date):
            return date
        case .weekday(let target, let isNext):
            let today = calendar.startOfDay(for: now)
            let current = calendar.component(.weekday, from: today)
            if current == target, !isNext, let start, date(at: start, on: today, calendar: calendar) > now {
                return today
            }
            var ahead = (target - current + daysPerWeek) % daysPerWeek
            if ahead == 0 { ahead = daysPerWeek }
            return addDays(ahead, to: today, calendar: calendar)
        }
    }

    // MARK: - Time

    private static func extractTimes(_ rest: inout String) -> TimeSpan? {
        for hit in hits(rangePattern, in: rest) {
            guard let span = rangeSpan(hit) else { continue }
            rest = remove(hit, from: rest)
            return span
        }
        for hit in hits(singleTimePattern, in: rest) {
            let hasMarker = hit.groups[1] != nil || hit.groups[3] != nil || hit.groups[4] != nil
            guard hasMarker, let hour = hour24(hit.groups[2], meridiem: hit.groups[4]),
                  let minute = minutes(hit.groups[3]) else { continue }
            rest = remove(hit, from: rest)
            return TimeSpan(start: ClockTime(hour: hour, minute: minute), end: nil)
        }
        if let hit = hits(wordTimePattern, in: rest).first, let word = hit.groups[2]?.lowercased() {
            rest = remove(hit, from: rest)
            return TimeSpan(start: ClockTime(hour: word == "noon" ? noonHour : 0, minute: 0), end: nil)
        }
        return nil
    }

    private static func rangeSpan(_ hit: Hit) -> TimeSpan? {
        let startMeridiem = hit.groups[4]?.lowercased()
        let endMeridiem = hit.groups[7]?.lowercased()
        let hasMarker = hit.groups[1] != nil || startMeridiem != nil || endMeridiem != nil
            || (hit.groups[3] != nil && hit.groups[6] != nil)
        guard hasMarker, let startMinute = minutes(hit.groups[3]), let endMinute = minutes(hit.groups[6]) else { return nil }
        guard let (startHour, endHour) = rangeHours(
            startText: hit.groups[2], startMinute: startMinute, startMeridiem: startMeridiem,
            endText: hit.groups[5], endMinute: endMinute, endMeridiem: endMeridiem
        ) else { return nil }
        return TimeSpan(
            start: ClockTime(hour: startHour, minute: startMinute),
            end: ClockTime(hour: endHour, minute: endMinute)
        )
    }

    private static func rangeHours(
        startText: String?, startMinute: Int, startMeridiem: String?,
        endText: String?, endMinute: Int, endMeridiem: String?
    ) -> (Int, Int)? {
        func total(_ hour: Int, _ minute: Int) -> Int { hour * minutesPerHour + minute }
        switch (startMeridiem, endMeridiem) {
        case (nil, let end?):
            guard let endHour = hour24(endText, meridiem: end), let inherited = hour24(startText, meridiem: end) else { return nil }
            if total(inherited, startMinute) <= total(endHour, endMinute) { return (inherited, endHour) }
            guard let morning = hour24(startText, meridiem: "am") else { return nil }
            return (morning, endHour)
        case (let start?, nil):
            guard let startHour = hour24(startText, meridiem: start), let inherited = hour24(endText, meridiem: start) else { return nil }
            if total(inherited, endMinute) > total(startHour, startMinute) { return (startHour, inherited) }
            let flipped = hour24(endText, meridiem: start == "am" ? "pm" : "am")
            return (startHour, flipped ?? inherited)
        default:
            guard let startHour = hour24(startText, meridiem: startMeridiem),
                  let endHour = hour24(endText, meridiem: endMeridiem) else { return nil }
            return (startHour, endHour)
        }
    }

    private static func minutes(_ text: String?) -> Int? {
        guard let text else { return 0 }
        guard let value = Int(text), (0..<minutesPerHour).contains(value) else { return nil }
        return value
    }

    /// Converts an hour string to 0...23. Bare hours follow the "at 3" rule.
    private static func hour24(_ text: String?, meridiem: String?) -> Int? {
        guard let text, let hour = Int(text) else { return nil }
        if let meridiem = meridiem?.lowercased() {
            guard (1...noonHour).contains(hour) else { return nil }
            return hour % noonHour + (meridiem == "pm" ? noonHour : 0)
        }
        guard (0...23).contains(hour) else { return nil }
        if text.hasPrefix("0") || hour == 0 || hour > noonHour || hour == noonHour { return hour }
        return bareAfternoonHours.contains(hour) ? hour + noonHour : hour
    }

    // MARK: - Dates and title

    private static func date(at time: ClockTime, on day: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) ?? day
    }

    private static func addDays(_ count: Int, to date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: count, to: date) ?? date
    }

    private static func makeTitle(_ rest: String, matchedAny: Bool) -> String {
        var words = rest.split(whereSeparator: \.isWhitespace).map(String.init)
        if matchedAny {
            let edge = CharacterSet(charactersIn: ",;:-")
            words = words.map { $0.trimmingCharacters(in: edge) }.filter { !$0.isEmpty }
            while let last = words.last, trailingConnectives.contains(last.lowercased()) {
                words.removeLast()
            }
        }
        let joined = words.joined(separator: " ")
        guard let first = joined.first else { return fallbackTitle }
        return first.uppercased() + joined.dropFirst()
    }
}
