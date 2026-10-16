import Foundation

/// Where recordings go and what they are called.
enum NookRecordFiles {
    static func folder(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Movies", isDirectory: true)
            .appendingPathComponent("Hangover", isDirectory: true)
    }

    /// "Recording 2026-10-14 at 3.42.10 PM.mp4", like a Mac screenshot.
    static func fileName(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let hour = c.hour ?? 0
        let hour12 = (hour + 11) % 12 + 1
        let meridiem = hour < 12 ? "AM" : "PM"
        return String(
            format: "Recording %04d-%02d-%02d at %d.%02d.%02d %@.mp4",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, hour12, c.minute ?? 0, c.second ?? 0, meridiem
        )
    }

    /// `name`, or "name 2", "name 3" when it is taken.
    static func uniqueURL(in folder: URL, name: String, exists: (URL) -> Bool) -> URL {
        let first = folder.appendingPathComponent(name)
        guard exists(first) else { return first }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var number = 2
        while true {
            let url = folder.appendingPathComponent("\(base) \(number).\(ext)")
            if !exists(url) { return url }
            number += 1
        }
    }
}
