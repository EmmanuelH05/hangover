import Darwin
import Foundation
import OSLog

private let markerLog = NookTrayLog.logger

/// A small file the tray keeps in a file's own folder while that file is still
/// being made. A quit in the middle of a copy or a conversion leaves the folder
/// with half a result in it, and the marker is the only thing that says so.
///
/// The tray used to take every folder the index did not list for leftover work.
/// That was wrong whenever the index was not the whole truth: an index that
/// failed to read and was moved aside, or one that Hangover and a dev build,
/// which share the tray folder, each rewrote. A folder with no marker is never
/// removed, however much it looks like an orphan.
enum NookTrayPartialMarker {
    static let fileName = ".partial"

    static func url(in subfolder: URL) -> URL {
        subfolder.appendingPathComponent(fileName)
    }

    /// Marks the folder as holding unfinished work, and says which app copy is
    /// doing it. False when the marker could not be written: the folder is then
    /// left unmarked, which costs a leftover folder after a quit and nothing else.
    @discardableResult
    static func write(in subfolder: URL, processID: Int32 = getpid()) -> Bool {
        do {
            try Data("\(processID)".utf8).write(to: url(in: subfolder), options: .atomic)
            return true
        } catch {
            markerLog.error("Tray: a folder could not be marked as unfinished (\(NookTrayLog.cause(error), privacy: .public))")
            return false
        }
    }

    /// The file is in the index now, so nothing is unfinished any more.
    static func clear(in subfolder: URL) {
        let marker = url(in: subfolder)
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        do {
            try FileManager.default.removeItem(at: marker)
        } catch {
            markerLog.error("Tray: an unfinished-work marker could not be removed (\(NookTrayLog.cause(error), privacy: .public))")
        }
    }

    static func isMarked(_ subfolder: URL) -> Bool {
        FileManager.default.fileExists(atPath: url(in: subfolder).path)
    }

    /// True when the folder is leftover work the sweep may remove. The marker is
    /// read once and the answer rests on that one read: a second read could
    /// find the marker gone because another copy of the app, sharing the tray,
    /// just finished and listed the file. A marker that cannot be read means
    /// exactly that, and the folder stays. A marker with no number, or the
    /// number of a process that is gone, belongs to nobody. One naming a
    /// different copy that is still running is work not over yet.
    static func mayRemove(
        _ subfolder: URL,
        ownProcessID: Int32 = getpid(),
        isRunning: (Int32) -> Bool = isProcessRunning
    ) -> Bool {
        guard let data = try? Data(contentsOf: url(in: subfolder)) else { return false }
        guard let text = String(data: data, encoding: .utf8),
              let owner = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              owner != ownProcessID else { return true }
        return !isRunning(owner)
    }

    /// Signal 0 sends nothing; it only asks whether the process exists. A
    /// process that exists but belongs to someone else answers with EPERM.
    static func isProcessRunning(_ processID: Int32) -> Bool {
        guard processID > 0 else { return false }
        return kill(processID, 0) == 0 || errno == EPERM
    }
}
