import Foundation

/// The sample quick notes (D51). The notes widget reads a Markdown file;
/// the sample is a file in the demo's own temporary folder, written in the
/// format the widget writes. Saving a line appends to that file and
/// nothing else.
@MainActor
enum DemoNotes {
    /// Plain lines of an ordinary day, oldest first, with how many minutes
    /// before the launch each was written.
    static let lines: [(minutesAgo: Int, text: String)] = [
        (300, "Try the new cache key"),
        (230, "Ask about the midterm room"),
        (150, "Idea: widget presets"),
        (70, "Send the slides tonight"),
        (25, "Read chapter 6"),
    ]

    /// The file's text, one line per note, stamped the way the widget does.
    static func fileText(now: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let body = lines.map { line in
            let stamp = formatter.string(from: now.addingTimeInterval(-TimeInterval(line.minutesAgo) * 60))
            return "- **\(stamp)** \(line.text)\n"
        }
        return "# Quick Notes\n\n" + body.joined()
    }

    /// Writes the sample file and returns its URL.
    static func write(in folder: URL, now: Date) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(NookNotesService.folderFileName)
        try fileText(now: now).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

/// An Apple Notes writer that writes nowhere. The demo's notes go to the
/// file, and this keeps a switch of destination from running `osascript`.
struct DemoNotesWriter: NookAppleNotesWriting {
    func append(lineHTML: String, toNoteTitled title: String) async throws {}
}
