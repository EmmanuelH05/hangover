import Foundation

/// A file in the folder the MP3s go to, as far as the clean-up needs to know it.
struct NookLinkAudioFileEntry: Equatable, Sendable {
    var name: String
    var modified: Date
}

/// What the widget does to the disk: makes its folder, lists it and removes
/// the leftovers of a cancelled job. The app uses the file manager. A test
/// hands in a fake that holds the folder in memory.
@MainActor
protocol NookLinkAudioFiles: AnyObject {
    func makeFolder(_ folder: URL) throws
    func listing(of folder: URL) -> [NookLinkAudioFileEntry]
    func remove(_ file: URL)
    func exists(_ file: URL) -> Bool
    /// Moves a file. Throws when something is already at `destination`: it
    /// never replaces a file.
    func move(_ file: URL, to destination: URL) throws
    /// Puts a file in the Trash, where the user can still find it.
    func trash(_ file: URL) throws
}

@MainActor
final class NookLinkAudioSystemFiles: NookLinkAudioFiles {
    func makeFolder(_ folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func listing(of folder: URL) -> [NookLinkAudioFileEntry] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else {
            return []
        }
        return urls.compactMap { url in
            guard let date = (try? url.resourceValues(forKeys: Set(keys)))?.contentModificationDate else { return nil }
            return NookLinkAudioFileEntry(name: url.lastPathComponent, modified: date)
        }
    }

    func remove(_ file: URL) {
        try? FileManager.default.removeItem(at: file)
    }

    func exists(_ file: URL) -> Bool {
        FileManager.default.fileExists(atPath: file.path)
    }

    func move(_ file: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: file, to: destination)
    }

    func trash(_ file: URL) throws {
        try FileManager.default.trashItem(at: file, resultingItemURL: nil)
    }
}

/// Why a folder was not taken.
enum NookLinkAudioFolderRefusal: Error, Equatable, Sendable {
    /// A dollar sign stands in the path. `yt-dlp` reads `$NAME` in the output
    /// name as an environment variable and has no way to write a plain `$`.
    case hasDollar

    /// The line Settings shows.
    var messageKey: String {
        switch self {
        case .hasDollar: "nook.linkAudio.settings.folderDollar"
        }
    }
}

/// Where the MP3s go.
enum NookLinkAudioFolderRule {
    static let defaultsKey = "nook.linkAudio.folder"

    /// Why a folder cannot be used, or nil when it can.
    static func refusal(for folder: URL) -> NookLinkAudioFolderRefusal? {
        folder.path.contains("$") ? .hasDollar : nil
    }

    /// `Music/Hangover` in the home folder. Made when the first job starts.
    static func defaultFolder(home: URL) -> URL {
        home.appendingPathComponent("Music", isDirectory: true).appendingPathComponent("Hangover", isDirectory: true)
    }

    /// The folder the user chose, or the default. A saved path that is not
    /// absolute is not a folder anyone chose, and nor is one the rule refuses.
    /// The default stands in for both.
    static func resolve(saved: String?, home: URL) -> URL {
        guard let saved, saved.hasPrefix("/"), saved.count > 1 else { return defaultFolder(home: home) }
        let folder = URL(fileURLWithPath: saved, isDirectory: true)
        return refusal(for: folder) == nil ? folder : defaultFolder(home: home)
    }

    /// `path` as a file that sits directly in `folder`, or nil. What `yt-dlp`
    /// prints as a path comes through here before the app believes it: a path
    /// in another folder, in a folder below this one, one that climbs out with
    /// `..`, a relative one and the folder itself are all nil.
    static func directChild(_ path: String, of folder: URL) -> URL? {
        guard path.hasPrefix("/"), !path.unicodeScalars.contains(where: isControl) else { return nil }
        let file = URL(fileURLWithPath: path).standardizedFileURL
        let name = file.lastPathComponent
        guard !name.isEmpty, name != "/", name != ".", name != ".." else { return nil }
        let parent = file.deletingLastPathComponent().standardizedFileURL.path
        return parent == folder.standardizedFileURL.path ? file : nil
    }

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.generalCategory == .control
    }

    /// A folder no other model shares, for a model on a store of its own.
    /// Nothing is made there unless a job runs.
    static func isolatedFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("HangoverLinkAudio-\(UUID().uuidString)", isDirectory: true)
    }
}

/// What a cancelled job leaves behind and may be removed.
enum NookLinkAudioLeftovers {
    /// The names, among `entries`, of the files the job left. `writing` is
    /// the file `yt-dlp` said it was writing, such as `Song.webm`, with its
    /// folder or without. These go: that file, anything that starts with its
    /// name and a dot (`.part`, `.ytdl`), `Song.mp3` and `Song.temp.*`, which
    /// `ffmpeg` was writing. Only files changed since the job started count.
    /// A file the user already had under the same name stays. With no
    /// file named nothing was written yet, and nothing goes.
    static func names(
        in entries: [NookLinkAudioFileEntry],
        writing path: String?,
        since start: Date
    ) -> [String] {
        guard let path else { return [] }
        let fileName = (path as NSString).lastPathComponent
        guard isPlainName(fileName) else { return [] }
        let stem = (fileName as NSString).deletingPathExtension
        var candidates = [fileName]
        if !stem.isEmpty { candidates.append(stem + ".mp3") }
        return entries.filter { entry in
            guard entry.modified >= start else { return false }
            return candidates.contains(entry.name)
                || entry.name.hasPrefix(fileName + ".")
                || (!stem.isEmpty && entry.name.hasPrefix(stem + ".temp."))
        }.map(\.name)
    }

    /// A name with no folder in it and no way up out of one.
    private static func isPlainName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/")
    }
}
