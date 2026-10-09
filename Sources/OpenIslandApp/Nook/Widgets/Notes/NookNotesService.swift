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
    /// Where notes go on an install that never picked a file: a Markdown
    /// file in the app's own folder. Not Documents or Desktop, which macOS
    /// asks about, and not a new folder in the user's home.
    static let defaultPath = "~/Library/Application Support/OpenIsland/Notes/Quick Notes.md"
    private static let maxEntries = 20

    @ObservationIgnored private(set) weak var nook: NookModel?
    private(set) var entries: [NookNoteEntry] = []
    private(set) var fileURL: URL = NookNotesService.resolveURL()

    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var started = false

    func start(nook: NookModel) {
        self.nook = nook
        guard !started else { return }
        started = true
        ensureFileExists()
        reload()
        watch()
    }

    // MARK: Public API

    func setFileURL(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: Self.pathDefaultsKey)
        fileURL = url
        ensureFileExists()
        reload()
        watch()
    }

    func append(_ text: String) {
        let flat = text
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !flat.isEmpty else { return }
        ensureFileExists()
        let line = "- **\(Self.stampFormatter.string(from: Date()))** \(flat)\n"
        // True append: the rest of the file is never rewritten, so a failed
        // read can never replace the user's notes.
        do {
            let handle = try FileHandle(forWritingTo: fileURL)
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
        }
        reload()
        watch()
    }

    func delete(_ id: String) {
        guard entries.contains(where: { $0.id == id }),
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
        if next != entries { entries = next }
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

    private static func resolveURL() -> URL {
        let path = resolvePath(stored: UserDefaults.standard.string(forKey: pathDefaultsKey))
        return URL(fileURLWithPath: expandHome(path))
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
