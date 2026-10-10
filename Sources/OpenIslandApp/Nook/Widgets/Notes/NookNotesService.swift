import AppKit
import Foundation
import Observation

struct NookNoteEntry: Identifiable, Equatable, Sendable {
    /// Line index plus the raw line, so duplicates stay distinct.
    let id: String
    let date: Date
    let text: String
}

@MainActor
@Observable
final class NookNotesService {
    static let pathDefaultsKey = "nook.notes.path"
    static let destinationDefaultsKey = "nook.notes.destination"
    /// The last notes sent to Apple Notes, for the card's list.
    static let recentDefaultsKey = "nook.notes.appleNotes.recent"
    /// Where notes go on an install that never picked a file: a Markdown
    /// file in the app's own folder. Not Documents or Desktop, which macOS
    /// asks about, and not a new folder in the user's home.
    static let defaultPath = "~/Library/Application Support/OpenIsland/Notes/Quick Notes.md"
    /// The file a notes folder holds, which the welcome tour's folder choice
    /// names. The same name as the default file.
    static let folderFileName = "Quick Notes.md"
    private static let maxEntries = 20

    @ObservationIgnored private(set) weak var nook: NookModel?
    /// The lines of the Markdown file, newest first.
    private(set) var fileEntries: [NookNoteEntry] = []
    /// What was sent to Apple Notes, newest first. The card cannot read the
    /// note back, and shows this list in its place.
    private(set) var appleNotesEntries: [NookNoteEntry] = []
    private(set) var fileURL: URL
    private(set) var destination: NookNotesDestination
    /// How many notes were saved since the app started, to the file or to
    /// Apple Notes. The welcome tour watches it to see a note go in.
    private(set) var savedCount = 0

    /// What the card lists: the file's lines, or what went to Apple Notes.
    var entries: [NookNoteEntry] { destination == .appleNotes ? appleNotesEntries : fileEntries }
    /// A line can be taken out of the file. Not out of an Apple note, which
    /// the app only ever adds to.
    var canDelete: Bool { destination == .file }

    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var started = false
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let appleNotes: any NookAppleNotesWriting
    @ObservationIgnored private let now: () -> Date
    /// The newest send to Apple Notes. Each send waits for the one before
    /// it: the script reads the note and then writes it, and two running at
    /// once would lose a line or make the note twice.
    @ObservationIgnored private(set) var lastSend: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        appleNotes: any NookAppleNotesWriting = NookAppleNotesScriptWriter(),
        fileURL: URL? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.appleNotes = appleNotes
        self.now = now
        self.fileURL = fileURL ?? Self.resolveURL(defaults: defaults)
        destination = defaults.string(forKey: Self.destinationDefaultsKey)
            .flatMap(NookNotesDestination.init(rawValue:)) ?? .file
        appleNotesEntries = Self.loadRecent(from: defaults)
    }

    func start(nook: NookModel) {
        self.nook = nook
        guard !started else { return }
        started = true
        ensureFileExists()
        reload()
        watch()
    }

    // MARK: Public API

    func setDestination(_ next: NookNotesDestination) {
        guard next != destination else { return }
        destination = next
        defaults.set(next.rawValue, forKey: Self.destinationDefaultsKey)
    }

    func setFileURL(_ url: URL) {
        defaults.set(url.path, forKey: Self.pathDefaultsKey)
        fileURL = url
        ensureFileExists()
        reload()
        watch()
    }

    /// Keeps the notes file in a folder the user chose, under the default
    /// file's name. The same stored path Settings' "Choose file…" writes, so
    /// a file chosen there and a folder chosen here are one setting.
    func setFolder(_ folder: URL) {
        setFileURL(folder.appendingPathComponent(Self.folderFileName))
    }

    func append(_ text: String) {
        let flat = text
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !flat.isEmpty else { return }
        let date = now()
        switch destination {
        case .file: appendToFile(flat, date: date)
        case .appleNotes: sendToAppleNotes(flat, date: date)
        }
    }

    /// Shows the note in the card at once, then hands it to Notes. When
    /// Notes does not take it the text goes to the Markdown file, which
    /// keeps a typed note from being lost, and a notice says where it went.
    private func sendToAppleNotes(_ text: String, date: Date) {
        let entry = NookNoteEntry(id: UUID().uuidString, date: date, text: text)
        appleNotesEntries = Array(([entry] + appleNotesEntries).prefix(Self.maxEntries))
        saveRecent()
        let line = NookAppleNotesLine.html(text: text, stamp: Self.stampFormatter.string(from: date))
        let writer = appleNotes
        let previous = lastSend
        lastSend = Task { [weak self] in
            await previous?.value
            do {
                try await writer.append(lineHTML: line, toNoteTitled: NookAppleNotesLine.noteTitle)
                self?.savedCount += 1
            } catch {
                self?.appleNotesRefused(entry, error: error as? NookAppleNotesError ?? .failed)
            }
        }
    }

    private func appleNotesRefused(_ entry: NookNoteEntry, error: NookAppleNotesError) {
        // The file could not take it either: the note stays in the card's
        // list, which is the one place that still holds it, and the notice
        // from the failed write stands.
        guard appendToFile(entry.text, date: entry.date) else { return }
        appleNotesEntries.removeAll { $0.id == entry.id }
        saveRecent()
        let reason = error == .notPermitted ? "Notes access is off" : "Notes did not take it"
        nook?.showTransient(
            symbol: "exclamationmark.triangle", text: "\(reason). Saved to the file", tint: .orange,
            duration: .seconds(5)
        )
    }

    /// False when the line could not be written. A notice has said so.
    @discardableResult
    private func appendToFile(_ flat: String, date: Date) -> Bool {
        ensureFileExists()
        let line = "- **\(Self.stampFormatter.string(from: date))** \(flat)\n"
        // True append: the rest of the file is never rewritten, so a failed
        // read can never replace the user's notes. The handle is opened for
        // reading too: the last byte is read to see whether the file ends in
        // a newline, and a handle opened only for writing refused that read,
        // which failed every note added to a file that was not empty.
        do {
            let handle = try FileHandle(forUpdating: fileURL)
            defer { try? handle.close() }
            var payload = Data()
            let end = try handle.seekToEnd()
            if end > 0 {
                try handle.seek(toOffset: end - 1)
                if let last = try handle.read(upToCount: 1), last != Data([0x0A]) {
                    payload.append(0x0A)
                }
                _ = try handle.seekToEnd()
            }
            payload.append(Data(line.utf8))
            try handle.write(contentsOf: payload)
        } catch {
            nook?.showTransient(symbol: "exclamationmark.triangle", text: "Note not saved", tint: .orange, duration: .seconds(4))
            return false
        }
        savedCount += 1
        reload()
        watch()
        return true
    }

    func delete(_ id: String) {
        guard canDelete, fileEntries.contains(where: { $0.id == id }),
              let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        var lines = text.components(separatedBy: "\n")
        let separator = id.firstIndex(of: "|")
        guard let separator,
              let index = Int(id[id.startIndex..<separator]),
              lines.indices.contains(index) else { return }
        let raw = String(id[id.index(after: separator)...])
        if lines[index] == raw {
            lines.remove(at: index)
        } else if let fallback = lines.firstIndex(of: raw) {
            // File shifted since the last read.
            lines.remove(at: fallback)
        } else {
            reload()
            return
        }
        writeFile(lines.joined(separator: "\n"))
        reload()
    }

    func reload() {
        // Keep the last good entries if the file is mid-replace or unreadable.
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let lines = text.components(separatedBy: "\n")
        var found: [NookNoteEntry] = []
        for (index, line) in lines.enumerated() {
            guard let parsed = Self.parse(line) else { continue }
            found.append(NookNoteEntry(id: "\(index)|\(line)", date: parsed.date, text: parsed.text))
        }
        let next = Array(found.suffix(Self.maxEntries).reversed())
        if next != fileEntries { fileEntries = next }
    }

    // MARK: File access

    private func ensureFileExists() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: fileURL.path) else { return }
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "# Quick Notes\n\n".write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func writeFile(_ content: String) {
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            nook?.showTransient(symbol: "exclamationmark.triangle", text: "Note not saved", tint: .orange, duration: .seconds(4))
        }
        // Atomic write replaces the inode, so re-arm the watcher.
        watch()
    }

    // MARK: Watching

    private func watch(attempt: Int = 0) {
        source?.cancel()
        source = nil
        let fd = open(fileURL.path, O_EVTONLY)
        guard fd >= 0 else {
            // Editors that replace the file may not have the new one in place yet.
            guard attempt < 5 else { return }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                self?.watch(attempt: attempt + 1)
            }
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: .main
        )
        let notify = Self.makeHandler(for: self)
        src.setEventHandler(handler: notify)
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    /// Built outside actor isolation so the closure is safe on any queue.
    private nonisolated static func makeHandler(for service: NookNotesService) -> @Sendable () -> Void {
        { [weak service] in
            Task { @MainActor in
                guard let service else { return }
                service.reload()
                // Obsidian replaces files on save; re-arm on the new inode.
                service.watch()
            }
        }
    }

    // MARK: Parsing

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private static func parse(_ line: String) -> (date: Date, text: String)? {
        // "- **YYYY-MM-DD HH:mm** text"
        guard line.hasPrefix("- **"), line.count >= 4 + 16 + 2 else { return nil }
        let stampStart = line.index(line.startIndex, offsetBy: 4)
        let stampEnd = line.index(stampStart, offsetBy: 16)
        let stamp = String(line[stampStart..<stampEnd])
        let rest = line[stampEnd...]
        guard rest.hasPrefix("**"), let date = stampFormatter.date(from: stamp) else { return nil }
        let text = rest.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return (date, text)
    }

    private static func resolveURL(defaults: UserDefaults) -> URL {
        let path = resolvePath(stored: defaults.string(forKey: pathDefaultsKey))
        return URL(fileURLWithPath: expandHome(path))
    }

    // MARK: Apple Notes list

    private struct Recent: Codable {
        let id: String
        let date: Date
        let text: String
    }

    private static func loadRecent(from defaults: UserDefaults) -> [NookNoteEntry] {
        guard let data = defaults.data(forKey: recentDefaultsKey),
              let stored = try? JSONDecoder().decode([Recent].self, from: data) else { return [] }
        return stored.prefix(maxEntries).map { NookNoteEntry(id: $0.id, date: $0.date, text: $0.text) }
    }

    private func saveRecent() {
        let stored = appleNotesEntries.map { Recent(id: $0.id, date: $0.date, text: $0.text) }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: Self.recentDefaultsKey)
    }

    /// The notes file: the one picked in Settings, else the default.
    static func resolvePath(stored: String?) -> String {
        stored ?? defaultPath
    }

    private static func expandHome(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return home + path.dropFirst()
    }
}
