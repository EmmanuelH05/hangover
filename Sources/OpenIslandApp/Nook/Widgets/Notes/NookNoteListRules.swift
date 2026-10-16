import Foundation

/// The rules for the notes list on the card (D70): how old a note is, said
/// in a few characters, and how many rows each size shows. Dates come from
/// the `now` and `calendar` passed in.
enum NookNoteListRules {
    /// Rows the list shows at each size. The list scrolls past them.
    static func rowCount(for size: NookWidgetSize) -> Int {
        switch size {
        case .small: 3
        case .medium: 4
        case .large: 7
        }
    }

    /// Whether the list says "No notes yet". Not when the folder could not
    /// be read: that is not a folder with no notes, and the card says so.
    static func showsEmptyState(notes: [NookNote], problem: NookNotesNotice?) -> Bool {
        notes.isEmpty && problem?.isAboutFolder != true
    }

    /// The line the empty list says (N11).
    enum EmptyLine: Equatable, Sendable {
        /// "Press New note, or <shortcut> in any app."
        case shortcut
        /// "Press New note, or set a shortcut in Settings."
        case settings

        var key: String {
            switch self {
            case .shortcut: "nook.notes.empty"
            case .settings: "nook.notes.empty.settings"
            }
        }
    }

    /// The shortcut is named only when macOS has it. Told of a shortcut
    /// that does not work, a person would press the keys and nothing would
    /// happen; the line points to Settings instead.
    static func emptyLine(hotkey status: NookNoteHotkeyStatus) -> EmptyLine {
        status == .ready ? .shortcut : .settings
    }

    /// What a row says for a note: its title, or for a file with no words in
    /// it the file's name, or "Untitled" for a note that has neither.
    static func rowTitle(for note: NookNote, untitled: String) -> String {
        // A file that cannot be read has no words, and is known by its name.
        if !note.title.isEmpty, note.state == .readable { return note.title }
        let isFile = URL(fileURLWithPath: note.id).pathExtension.lowercased() == NookNoteFiles.fileExtension
        return isFile ? NookNoteFiles.stem(of: note.id) : untitled
    }

    /// How long ago a note was edited.
    enum Age: Equatable, Sendable {
        /// Less than a minute, or a date ahead of the clock.
        case now
        case minutes(Int)
        case hours(Int)
        /// A day or more: the date is shown.
        case date
    }

    static func age(of date: Date, now: Date) -> Age {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return .now }
        if seconds < 3_600 { return .minutes(Int(seconds / 60)) }
        if seconds < 86_400 { return .hours(Int(seconds / 3_600)) }
        return .date
    }

    /// "now", "2m ago", "3h ago" or "Oct 12". A date in another year
    /// carries the year: "Oct 12, 2025". `string` looks a key up (the app
    /// passes its language), which keeps the rules free of the language in
    /// use.
    static func ageText(
        of date: Date,
        now: Date,
        calendar: Calendar,
        locale: Locale,
        string: (String) -> String
    ) -> String {
        switch age(of: date, now: now) {
        case .now: return string("nook.notes.age.now")
        case .minutes(let minutes): return String(format: string("nook.notes.age.minutes"), minutes)
        case .hours(let hours): return String(format: string("nook.notes.age.hours"), hours)
        case .date: return dayText(date, now: now, calendar: calendar, locale: locale)
        }
    }

    static func dayText(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "MMMdy")
        return formatter.string(from: date)
    }
}
