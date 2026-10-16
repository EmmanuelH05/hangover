import Foundation

/// The places notes live by default (D70): pure choices from a home folder
/// and a file manager, so a test points them at a temporary folder.
enum NookNoteLocations {
    static let folderName = "Hangover Notes"

    /// Where Obsidian keeps vaults it syncs through iCloud.
    static func obsidianDocuments(home: URL) -> URL {
        home.appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents", isDirectory: true)
    }

    /// Where a new install keeps notes: "Hangover Notes" inside the first
    /// Obsidian vault in iCloud, by name, or in the visible Documents
    /// folder when there is no such vault.
    static func defaultFolder(home: URL, fileManager: FileManager = .default) -> URL {
        defaultChoice(home: home, fileManager: fileManager).folder
    }

    /// The default folder, and whether the look for a vault went through
    /// (N12). When the iCloud Obsidian folder is there and cannot be listed,
    /// the Documents folder is a stand-in for this launch only: the choice is
    /// not kept, and the next launch looks again.
    struct DefaultChoice: Equatable, Sendable {
        var folder: URL
        /// False when the look for a vault failed.
        var isSettled: Bool
    }

    static func defaultChoice(home: URL, fileManager: FileManager = .default) -> DefaultChoice {
        let documents = home.appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        switch searchVaults(in: obsidianDocuments(home: home), fileManager: fileManager) {
        case let .found(vault): return DefaultChoice(folder: vault.appendingPathComponent(folderName, isDirectory: true), isSettled: true)
        case .none: return DefaultChoice(folder: documents, isSettled: true)
        case .failed: return DefaultChoice(folder: documents, isSettled: false)
        }
    }

    enum VaultSearch: Equatable, Sendable {
        case found(URL)
        /// The folder was looked through, or is not there, and holds no vault.
        case none
        /// The folder is there and could not be listed.
        case failed
    }

    /// The first folder, by name, that holds a `.obsidian` folder: what
    /// makes a folder a vault.
    static func searchVaults(in documents: URL, fileManager: FileManager = .default) -> VaultSearch {
        let names: [String]
        do {
            names = try fileManager.contentsOfDirectory(atPath: documents.path)
        } catch let error as CocoaError where [.fileReadNoSuchFile, .fileNoSuchFile].contains(error.code) {
            // No Obsidian in iCloud on this Mac.
            return .none
        } catch {
            NookNotesLog.failure("look for an Obsidian vault", path: documents.path, error: error)
            return .failed
        }
        let vault = names
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { documents.appendingPathComponent($0, isDirectory: true) }
            .first { fileManager.fileExists(atPath: $0.appendingPathComponent(".obsidian").path) }
        return vault.map(VaultSearch.found) ?? .none
    }

    static func firstVault(in documents: URL, fileManager: FileManager = .default) -> URL? {
        if case let .found(vault) = searchVaults(in: documents, fileManager: fileManager) { return vault }
        return nil
    }

    /// The folder the picker opens in: the Obsidian iCloud folder when it
    /// exists, otherwise the folder the notes are in now.
    static func pickerStart(home: URL, current: URL, fileManager: FileManager = .default) -> URL {
        let obsidian = obsidianDocuments(home: home)
        var isFolder: ObjCBool = false
        if fileManager.fileExists(atPath: obsidian.path, isDirectory: &isFolder), isFolder.boolValue {
            return obsidian
        }
        return current
    }

    /// The file the old Quick Notes were kept in: the one picked in
    /// Settings, else the default one in the app's own folder.
    static func oldNotesFile(storedPath: String?, home: URL) -> URL {
        let path = storedPath ?? "~/Library/Application Support/OpenIsland/Notes/Quick Notes.md"
        return URL(fileURLWithPath: expandingHome(path, home: home))
    }

    /// A path that starts with a tilde, with the home folder put in its place.
    static func expandingHome(_ path: String, home: URL) -> String {
        guard path.hasPrefix("~") else { return path }
        return home.path + path.dropFirst()
    }

    /// Where Hangover keeps its record of the notes it made in Apple Notes.
    static func appleNotesRecord(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/OpenIsland/Notes/apple-notes.json")
    }

    /// Where the text of a note that could not be saved waits (N1): one
    /// file for each note, put back as a note at the next launch.
    static func unsavedFolder(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/OpenIsland/Notes/unsaved", isDirectory: true)
    }
}
