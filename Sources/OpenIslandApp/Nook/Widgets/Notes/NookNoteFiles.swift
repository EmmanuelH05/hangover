import Foundation

/// The rules for notes as Markdown files (D70), all pure: a title from the
/// text, a file name from a title, the front matter a file carries, and the
/// order of the list. Nothing here reads a file or the clock.
enum NookNoteFiles {
    static let fileExtension = "md"
    /// The most characters in a file's name before the extension.
    static let maxNameLength = 60
    /// The name of a note whose title has nothing a file name can hold.
    static let untitledName = "Untitled"

    // MARK: Title

    /// True for text with something in it besides blanks. A note without
    /// it is never saved.
    static func hasContent(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The first line that has any text, with a Markdown heading mark taken
    /// off its front. Blank lines above it do not count as a line.
    static func title(from text: String) -> String {
        var found = ""
        // One line at a time, and no more than it takes: a long note is not
        // read to its end for a title that is on its first line.
        text.enumerateLines { line, stop in
            // A line of marks alone ("##") has no title in it: the next
            // line with words is the first line that counts.
            let title = stripHeadingMark(line.trimmingCharacters(in: .whitespaces))
            if !title.isEmpty {
                found = title
                stop = true
            }
        }
        return found
    }

    private static func stripHeadingMark(_ line: String) -> String {
        var rest = Substring(line)
        var marks = 0
        while rest.first == "#", marks < 6 {
            rest = rest.dropFirst()
            marks += 1
        }
        // "#hashtag" is a tag and not a heading: a heading has a space.
        guard marks > 0, rest.isEmpty || rest.first == " " else { return line }
        return rest.trimmingCharacters(in: .whitespaces)
    }

    // MARK: File names

    /// Characters a file name cannot hold on a Mac or in Obsidian, and the
    /// ones that would break a link to the note.
    private static let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|#^[]")
        .union(.controlCharacters)
        .union(.newlines)

    /// The title cleaned for a file name: no forbidden characters, one space
    /// between words, no dots or spaces at the ends, and at most
    /// `maxLength` characters. A title with nothing left is `untitledName`.
    static func cleanName(from title: String, maxLength: Int = maxNameLength) -> String {
        let spaced = String(title.unicodeScalars.map { forbidden.contains($0) ? " " : Character($0) })
        let words = spaced.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let cut = String(words.prefix(max(1, maxLength)))
        let trimmed = trimEnds(cut)
        return trimmed.isEmpty ? untitledName : trimmed
    }

    private static func trimEnds(_ name: String) -> String {
        let edge = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "."))
        return name.trimmingCharacters(in: edge)
    }

    /// The file name for a note with this title: the clean title and `.md`,
    /// or " 2", " 3" and on when a file of that name is already there.
    /// `taken` holds the names in the folder, compared without regard to
    /// case, because a Mac's disk does the same. The name with its number
    /// stays within `maxNameLength` too.
    static func fileName(forTitle title: String, taken: Set<String>) -> String {
        let used = Set(taken.map(comparable))
        let base = cleanName(from: title)
        var number = 1
        while true {
            let suffix = number == 1 ? "" : " \(number)"
            let stem = trimEnds(String(base.prefix(max(1, maxNameLength - suffix.count)))) + suffix
            let name = "\(stem).\(fileExtension)"
            if !used.contains(comparable(name)) { return name }
            number += 1
        }
    }

    private static func comparable(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// The title a copy is saved under, when the note's file was changed by
    /// another program (N13): the title and " (Hangover)", cut to fit.
    static func copyTitle(for title: String) -> String {
        cleanName(from: title, maxLength: maxNameLength - copySuffix.count) + copySuffix
    }

    static let copySuffix = " (Hangover)"

    /// True when a file already has the name its note's title would give it,
    /// with or without a clash number, or the name of its copy (N13). A file
    /// is renamed only when this is false, which is when the title changed.
    static func fileName(_ fileName: String, stillFits title: String) -> Bool {
        let current = comparable(stem(of: fileName))
        return fits(current, base: comparable(cleanName(from: title)))
            || fits(current, base: comparable(copyTitle(for: title)))
    }

    private static func fits(_ current: String, base: String) -> Bool {
        if current == base { return true }
        // "Plan 2" fits the title "Plan". The number may have made the base
        // shorter, so the head is compared with the base cut the same way.
        guard let space = current.lastIndex(of: " "),
              let number = Int(current[current.index(after: space)...]), number >= 2 else { return false }
        let suffix = " \(number)"
        let head = String(current[..<space])
        let expected = trimEnds(String(base.prefix(max(1, maxNameLength - suffix.count))))
        return head == expected
    }

    /// The name without its extension, for the title of a note that has no
    /// words in it.
    static func stem(of fileName: String) -> String {
        let url = URL(fileURLWithPath: fileName)
        return url.pathExtension.lowercased() == fileExtension
            ? url.deletingPathExtension().lastPathComponent
            : fileName
    }

    // MARK: Front matter

    /// A file read apart: the dates in its front matter, the front matter
    /// lines as the file has them, and the text below it.
    struct Parsed: Equatable, Sendable {
        var created: Date?
        /// What the `created` line says, as the file has it, whether or not it
        /// reads as a date (N14). It is the same text at every read, which the
        /// seconds it reads as are not: a zone the clock moved to or a line
        /// Hangover cannot read changes them. Nil for a file with no such
        /// line, or one with nothing after the colon.
        var createdText: String?
        var updated: Date?
        /// Every line between the fences, exactly as the file has them, in
        /// order, blank lines included (N18). Other programs keep tags and
        /// aliases there; a rewrite hands them back untouched. Empty for a
        /// file with no front matter.
        var frontMatter: [String] = []
        var body: String

        /// The lines that are not Hangover's: everything but `created` and
        /// `updated`.
        var otherFrontMatter: [String] {
            frontMatter.filter { NookNoteFiles.value(of: "created", in: $0) == nil && NookNoteFiles.value(of: "updated", in: $0) == nil }
        }
    }

    private static let fence = "---"

    static func parse(_ fileText: String, calendar: Calendar) -> Parsed {
        let lines = fileText.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == fence,
              let close = lines.indices.dropFirst().first(where: {
                  lines[$0].trimmingCharacters(in: .whitespaces) == fence
              }) else {
            return Parsed(body: fileText)
        }
        var parsed = Parsed(frontMatter: Array(lines[1..<close]), body: lines[(close + 1)...].joined(separator: "\n"))
        for line in parsed.frontMatter {
            if let value = value(of: "created", in: line) {
                parsed.created = date(from: value, calendar: calendar)
                let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
                parsed.createdText = text.isEmpty ? nil : text
            } else if let value = value(of: "updated", in: line) {
                parsed.updated = date(from: value, calendar: calendar)
            }
        }
        return parsed
    }

    /// The file's text: front matter with the two dates, then the note.
    ///
    /// `keeping` is the front matter a file already has. Its lines stay where
    /// they are, as they are, blank lines too, and a `created` line stays
    /// whatever it says, even when Hangover cannot read it as a date (N18).
    /// Only the `updated` line is Hangover's to change. A line that is
    /// missing is added after the others.
    static func render(
        body: String,
        created: Date,
        updated: Date,
        keeping frontMatter: [String] = [],
        calendar: Calendar
    ) -> String {
        var lines = frontMatter.map { line in
            value(of: "updated", in: line) == nil ? line : "updated: \(dateText(updated, calendar: calendar))"
        }
        if !frontMatter.contains(where: { value(of: "created", in: $0) != nil }) {
            lines.append("created: \(dateText(created, calendar: calendar))")
        }
        if !frontMatter.contains(where: { value(of: "updated", in: $0) != nil }) {
            lines.append("updated: \(dateText(updated, calendar: calendar))")
        }
        return ([fence] + lines + [fence]).joined(separator: "\n") + "\n" + body
    }

    fileprivate static func value(of key: String, in line: String) -> String? {
        let prefix = "\(key):"
        guard line.hasPrefix(prefix) else { return nil }
        return line.dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    // MARK: Dates

    /// "2026-10-15T09:41:00", in the calendar's time zone: the form
    /// Obsidian reads as a date with a time.
    static func dateText(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        )
    }

    /// Reads "2026-10-15", "2026-10-15 09:41", "2026-10-15T09:41" and
    /// "2026-10-15T09:41:00". Anything else is nil.
    static func date(from text: String, calendar: Calendar) -> Date? {
        let parts = text.split(whereSeparator: { $0 == "T" || $0 == " " })
        guard (1...2).contains(parts.count), let day = numbers(parts[0], separator: "-", counts: 3...3) else { return nil }
        var components = DateComponents(year: day[0], month: day[1], day: day[2])
        if parts.count == 2 {
            guard let time = numbers(parts[1], separator: ":", counts: 2...3) else { return nil }
            components.hour = time[0]
            components.minute = time[1]
            components.second = time.count == 3 ? time[2] : 0
        }
        // A date the calendar had to bend ("2026-02-31") is not a date.
        guard let date = calendar.date(from: components) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == day[0], back.month == day[1], back.day == day[2] else { return nil }
        return date
    }

    /// The whole numbers `text` is made of, when it is exactly that many
    /// of them between `separator`s.
    private static func numbers(_ text: Substring, separator: Character, counts: ClosedRange<Int>) -> [Int]? {
        let parts = text.split(separator: separator, omittingEmptySubsequences: false)
        let values = parts.compactMap { Int($0) }
        guard counts.contains(parts.count), values.count == parts.count else { return nil }
        return values
    }

    /// The date with its fraction left off, which is as exact as a file's
    /// front matter keeps it. A note written with a date that has a fraction
    /// would read back as a different note.
    static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    /// The date as whole seconds, to compare two dates the way a file's front
    /// matter keeps them.
    static func seconds(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970.rounded(.down))
    }

    /// "2026-10-15T16:41:00Z": the same moment in every zone, to tell a note
    /// kept in Hangover's own record from an earlier one (N14). That record
    /// holds absolute dates, and nothing about them drifts.
    static func absoluteText(_ date: Date) -> String {
        wholeSeconds(date).formatted(.iso8601)
    }

    // MARK: Order

    /// When a note was last edited: the later of the date in its front
    /// matter and the file's own, so a note edited in another program rises
    /// to the top even though that program left the front matter alone.
    static func lastEdit(frontMatterUpdated: Date?, fileModified: Date?, created: Date?) -> Date {
        [frontMatterUpdated, fileModified].compactMap { $0 }.max() ?? created ?? .distantPast
    }

    /// Newest edit first. Notes edited at the same moment keep a steady
    /// order, by title and then by id.
    static func ordered(_ notes: [NookNote]) -> [NookNote] {
        notes.sorted { lhs, rhs in
            if lhs.updated != rhs.updated { return lhs.updated > rhs.updated }
            let byTitle = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if byTitle != .orderedSame { return byTitle == .orderedAscending }
            return lhs.id < rhs.id
        }
    }

    // MARK: The old file

    /// The first line the old Quick Notes file carries.
    static let oldFileHeading = "# Quick Notes"
    /// The title the imported note gets.
    static let importedTitle = "Quick Notes"

    /// The old file's text as the one imported note: a "Quick Notes" title
    /// first, then what the file held. Nil when the file held nothing but
    /// its heading.
    static func importedText(fromOldFile contents: String) -> String? {
        var lines = contents.components(separatedBy: "\n")
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        if let first = lines.first, title(from: first) == importedTitle, first.hasPrefix("#") { lines.removeFirst() }
        let rest = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty else { return nil }
        return "\(oldFileHeading)\n\n\(rest)\n"
    }
}
