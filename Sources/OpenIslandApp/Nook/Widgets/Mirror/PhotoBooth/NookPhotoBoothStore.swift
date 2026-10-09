import Foundation

/// Where strips are kept and what they are called. Plain file work, with
/// the folder always handed in, which lets a test use one of its own.
struct NookPhotoBoothStore: Sendable {
    static let folderName = "Hangover Photo Booth"
    /// Names tried for one strip before giving up.
    private static let maxAttempts = 500

    /// Puts a file in the Trash. A test swaps this, which keeps its strips
    /// out of the real Trash.
    var trash: @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }

    /// `Pictures/Hangover Photo Booth` in the user's home. Apple's Mac
    /// Help ("Control access to files and folders on Mac") names Desktop,
    /// Documents and Downloads as the folders macOS asks about. Pictures
    /// is not one of them, which is why strips go there by default.
    static func defaultFolder() -> URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures", isDirectory: true)
        return pictures.appendingPathComponent(folderName, isDirectory: true)
    }

    /// `Photo Strip 2026-10-09 at 21.47.05.pdf`, with a number after it
    /// from the second try on.
    static func fileName(for date: Date, calendar: Calendar, attempt: Int) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "Photo Strip \(formatter.string(from: date))"
        return attempt <= 1 ? "\(base).pdf" : "\(base) \(attempt).pdf"
    }

    /// Writes a strip into a folder under a name no file there has yet.
    /// Never replaces a file: a taken name moves on to the next number.
    func save(_ data: Data, into folder: URL, at date: Date, calendar: Calendar = .current) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for attempt in 1...Self.maxAttempts {
            let url = folder.appendingPathComponent(Self.fileName(for: date, calendar: calendar, attempt: attempt))
            do {
                try data.write(to: url, options: .withoutOverwriting)
                return url
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            } catch {
                // A write cut short leaves part of a file. A taken name
                // was handled above, which makes this file ours to remove.
                try? FileManager.default.removeItem(at: url)
                throw error
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    /// Puts a strip in the Trash, where it can still be taken back.
    func moveToTrash(_ url: URL) throws {
        try trash(url)
    }

    /// Removes a strip that was saved for a session the user had already
    /// thrown away.
    func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
