import CoreServices
import Foundation

/// Tells the store when something in the notes folder changed: a note
/// edited, added or deleted by Obsidian or any other program. Tests pass a
/// fake and call it by hand.
@MainActor
protocol NookNoteFolderWatching: AnyObject {
    /// Starts watching `folder`, replacing the folder watched before.
    /// `onChange` runs on the main actor, a moment after a burst of changes.
    /// False when the folder could not be watched (N9): nothing is watched
    /// then, and the store tries again at the next save and when the island
    /// opens.
    func watch(_ folder: URL, onChange: @escaping @MainActor () -> Void) -> Bool
    func stop()
}

/// The watcher the app uses: file system events, which report a file
/// that is changed in place as well as one that is added or removed.
@MainActor
final class NookNoteFolderWatcher: NookNoteFolderWatching {
    /// How long events are gathered before one report. A save is often
    /// several writes.
    private static let latency: CFTimeInterval = 0.4

    private var stream: FSEventStreamRef?
    private var onChange: (@MainActor () -> Void)?
    /// The folder as the system names it, which the paths of events use.
    private var watchedPath = ""

    isolated deinit {
        stop()
    }

    /// True for a change to the folder itself or to a file directly in it.
    /// An Obsidian vault is full of files in folders of its own, and
    /// `.obsidian` changes all the time; none of them are notes.
    nonisolated static func isRelevant(_ path: String, watched: String) -> Bool {
        path == watched || URL(fileURLWithPath: path).deletingLastPathComponent().path == watched
    }

    /// The path with every link in it followed, which is how events name a
    /// file. Foundation's own `resolvingSymlinksInPath` leaves out the `/private`
    /// the system puts in front of `/var`, and events do not.
    nonisolated static func realPath(of url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    func watch(_ folder: URL, onChange: @escaping @MainActor () -> Void) -> Bool {
        stop()
        self.onChange = onChange
        watchedPath = Self.realPath(of: folder)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let paths = (unsafeBitCast(eventPaths, to: CFArray.self) as? [String]) ?? []
            let watcher = Unmanaged<NookNoteFolderWatcher>.fromOpaque(info).takeUnretainedValue()
            // The stream is scheduled on the main queue.
            MainActor.assumeIsolated {
                guard paths.contains(where: { NookNoteFolderWatcher.isRelevant($0, watched: watcher.watchedPath) }) else { return }
                watcher.onChange?()
            }
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes
        )
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [watchedPath] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), Self.latency, flags
        ) else {
            NookNotesLog.warning("The system would not make a stream to watch the notes folder", path: folder.path)
            self.onChange = nil
            return false
        }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        guard FSEventStreamStart(stream) else {
            NookNotesLog.warning("The system would not start watching the notes folder", path: folder.path)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.onChange = nil
            return false
        }
        self.stream = stream
        return true
    }

    func stop() {
        onChange = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
