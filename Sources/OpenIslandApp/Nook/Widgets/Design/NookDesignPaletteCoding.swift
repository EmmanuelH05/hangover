import Foundation
import OpenIslandCore
import OSLog

private let paletteFileLog = Logger(subsystem: "app.openisland", category: "nook.design")

/// Counts what a lenient read had to leave out. Handed to the decoder
/// through its user info, which saves threading a number through every
/// type.
final class NookDesignSkipCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int { lock.withLock { value } }

    func add() { lock.withLock { value += 1 } }

    static let key = CodingUserInfoKey(rawValue: "nook.design.skipCounter")!
}

/// A list read one element at a time. An element that does not read is
/// skipped and counted, and the rest still load.
struct NookDesignLossyList<Element: Decodable>: Decodable {
    var elements: [Element] = []

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let counter = decoder.userInfo[NookDesignSkipCounter.key] as? NookDesignSkipCounter
        while !container.isAtEnd {
            let index = container.currentIndex
            do {
                elements.append(try container.decode(Element.self))
            } catch {
                counter?.add()
                // A failed read leaves the cursor where it was. Reading the
                // element as "anything" moves past it.
                _ = try? container.decode(NookDesignSkippedValue.self)
                if container.currentIndex == index { break }
            }
        }
    }
}

/// Stands in for one element of any shape.
private struct NookDesignSkippedValue: Decodable {
    init(from decoder: Decoder) throws {}
}

extension KeyedDecodingContainer {
    /// The list under `key`, read one element at a time. A key that is
    /// missing or null is an empty list and nothing was lost. A key that
    /// holds something other than a list is an empty list too, and it is
    /// counted as left out, which makes the loader keep a copy of the file
    /// before a save writes over it.
    func lossyElements<Element: Decodable>(
        _ type: Element.Type,
        forKey key: Key,
        counter: NookDesignSkipCounter?
    ) -> [Element] {
        guard contains(key), (try? decodeNil(forKey: key)) != true else { return [] }
        if let list = try? decode(NookDesignLossyList<Element>.self, forKey: key) { return list.elements }
        counter?.add()
        return []
    }
}

extension Decoder {
    var skipCounter: NookDesignSkipCounter? {
        userInfo[NookDesignSkipCounter.key] as? NookDesignSkipCounter
    }
}

// Each saved item reads what it can. A missing id gets a new one, a
// missing collection is Global, and a missing date is the epoch. Only a
// color that does not read makes its item fail, and the list skips it.

extension NookDesignSwatch: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, color, name, isFavorite, addedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let counter = decoder.skipCounter
        color = try container.decode(NookDesignColor.self, forKey: .color)
        id = container.lenient(UUID.self, forKey: .id, fallback: UUID(), counter: counter)
        name = container.lenient(String.self, forKey: .name, fallback: "", counter: counter)
        isFavorite = container.lenient(Bool.self, forKey: .isFavorite, fallback: false, counter: counter)
        addedAt = container.lenient(Date.self, forKey: .addedAt, fallback: Date(timeIntervalSince1970: 0), counter: counter)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(color, forKey: .color)
        try container.encode(name, forKey: .name)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(addedAt, forKey: .addedAt)
    }
}

extension NookDesignPalette: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, collectionID, name, swatches, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let counter = decoder.skipCounter
        id = container.lenient(UUID.self, forKey: .id, fallback: UUID(), counter: counter)
        collectionID = container.lenient(UUID.self, forKey: .collectionID, fallback: NookDesignCollection.globalID, counter: counter)
        name = container.lenient(String.self, forKey: .name, fallback: "", counter: counter)
        createdAt = container.lenient(Date.self, forKey: .createdAt, fallback: Date(timeIntervalSince1970: 0), counter: counter)
        swatches = container.lossyElements(NookDesignSwatch.self, forKey: .swatches, counter: counter)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(collectionID, forKey: .collectionID)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(swatches, forKey: .swatches)
    }
}

extension NookDesignRecentColor: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, collectionID, color, pickedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let counter = decoder.skipCounter
        color = try container.decode(NookDesignColor.self, forKey: .color)
        id = container.lenient(UUID.self, forKey: .id, fallback: UUID(), counter: counter)
        collectionID = container.lenient(UUID.self, forKey: .collectionID, fallback: NookDesignCollection.globalID, counter: counter)
        pickedAt = container.lenient(Date.self, forKey: .pickedAt, fallback: Date(timeIntervalSince1970: 0), counter: counter)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(collectionID, forKey: .collectionID)
        try container.encode(color, forKey: .color)
        try container.encode(pickedAt, forKey: .pickedAt)
    }
}

extension NookDesignLibrary: Codable {
    private enum CodingKeys: String, CodingKey {
        case version, palettes, recents, activePaletteIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let counter = decoder.skipCounter
        // An object that holds none of what a shelf holds is not a shelf.
        if decoder.isWrongShape(contentKeys: ["palettes", "recents", "activePaletteIDs"]) { counter?.add() }
        version = (try? container.decode(Int.self, forKey: .version)) ?? Self.currentVersion
        palettes = container.lossyElements(NookDesignPalette.self, forKey: .palettes, counter: counter)
        recents = container.lossyElements(NookDesignRecentColor.self, forKey: .recents, counter: counter)
        activePaletteIDs = container.lenient(
            [String: UUID].self, forKey: .activePaletteIDs, fallback: [:], counter: counter
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(palettes, forKey: .palettes)
        try container.encode(recents, forKey: .recents)
        try container.encode(activePaletteIDs, forKey: .activePaletteIDs)
    }
}

/// Why a load did not bring everything back.
enum NookDesignLoadProblem: Equatable, Sendable {
    /// The file was not JSON this build can read at all. It was moved
    /// aside and the shelf starts empty.
    case unreadable
    /// The same, and the file could not be moved aside. It stays where it
    /// is, and nothing is written over it for the rest of the launch.
    case unreadableNotKept
    /// Something did not read or was over a limit, and was left out. A copy
    /// of the file as it was is kept beside it.
    case partlyRead(skipped: Int)
    /// The same, and the copy could not be made. Nothing is written over
    /// the file for the rest of the launch.
    case partlyReadNotKept(skipped: Int)
    /// A newer build wrote the file. Nothing in it is shown, nothing is
    /// changed, and nothing is written over it or beside it.
    case newerVersion(Int)
    /// The list of pictures was gone. It was built again from the pictures
    /// in the folder, which lost their names and their order.
    case indexMissing(recovered: Int)
    /// Pictures in the folder that the list did not have were taken back.
    case picturesTakenBack(Int)

    /// What this problem stops a store from doing for the rest of the
    /// launch, if anything.
    var lock: NookDesignStoreLock? {
        switch self {
        case let .newerVersion(version): .newerVersion(version)
        case .unreadableNotKept, .partlyReadNotKept: .copyNotKept
        case .unreadable, .partlyRead, .indexMissing, .picturesTakenBack: nil
        }
    }
}

/// Why a store takes no change. A change asked for anyway is refused with
/// a notice that says why.
enum NookDesignStoreLock: Equatable, Sendable {
    /// A newer Hangover saved the files. They are left exactly as they are.
    case newerVersion(Int)
    /// A copy of a file that could not be read in full could not be made,
    /// which makes any write a write over the only copy.
    case copyNotKept

    var noticeKey: String {
        switch self {
        case .newerVersion: "nook.design.notice.lockedNewer"
        case .copyNotKept: "nook.design.notice.lockedNoCopy"
        }
    }
}

/// What reading the palette file came to.
struct NookDesignLibraryLoad: Equatable, Sendable {
    var library: NookDesignLibrary
    var problem: NookDesignLoadProblem?
    /// The file as it stands after the read, which the store compares with
    /// the file later to find a change made by another copy of the app.
    var signature: NookDesignFileSignature?
}

/// Reads and writes `palettes.json`, the color shelf's one file:
///
/// ```json
/// {
///   "version": 1,
///   "activePaletteIDs": { "<collection id>": "<palette id>" },
///   "palettes": [
///     { "id": "…", "collectionID": "…", "name": "Brand", "createdAt": "2026-10-09T12:00:00Z",
///       "swatches": [
///         { "id": "…", "color": "#FF8800", "name": "Primary", "isFavorite": true, "addedAt": "…" }
///       ] }
///   ],
///   "recents": [ { "id": "…", "collectionID": "…", "color": "#112233", "pickedAt": "…" } ]
/// }
/// ```
///
/// Reading is lenient and never throws past this type: one bad color
/// costs that color, and a file that is not JSON costs nothing that was
/// not already lost, because it is moved aside before anything is saved
/// over it.
enum NookDesignLibraryFile {
    static let fileName = "palettes.json"

    static func decode(_ data: Data) throws -> (library: NookDesignLibrary, skipped: Int) {
        let counter = NookDesignSkipCounter()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(NookDesignDates.decoding)
        decoder.userInfo[NookDesignSkipCounter.key] = counter
        let library = try decoder.decode(NookDesignLibrary.self, from: data)
        return (library, counter.count)
    }

    static func encode(_ library: NookDesignLibrary) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var current = library
        current.version = NookDesignLibrary.currentVersion
        return try encoder.encode(current)
    }

    /// Reads the file at `url`. A missing file is an empty library and no
    /// problem. This touches the disk and must run off the main actor.
    ///
    /// Nothing is dropped without a copy and a report. A file that cannot be
    /// read at all is moved aside. One that is read in part, or holds more
    /// than a limit allows, is copied first. When the move or the copy
    /// cannot be done the problem is reported and the store takes no change. A
    /// file from a newer build is left exactly as it is: nothing in it is
    /// shown, and nothing is written over it or beside it.
    static func load(from url: URL) -> NookDesignLibraryLoad {
        let before = NookDesignFileSignature.of(url)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            if !NookDesignFiles.isMissingFile(error) {
                paletteFileLog.error("The saved palettes could not be opened: \(error.localizedDescription, privacy: .public)")
                return unreadable(url, before: before)
            }
            return NookDesignLibraryLoad(library: .empty, problem: nil, signature: before)
        }
        do {
            let read = try decode(data)
            if read.library.version > NookDesignLibrary.currentVersion {
                paletteFileLog.error("The saved palettes come from a newer build (version \(read.library.version, privacy: .public)). They are left alone.")
                return NookDesignLibraryLoad(library: .empty, problem: .newerVersion(read.library.version), signature: before)
            }
            let library = read.library.sanitized()
            let leftOut = read.skipped + read.library.countLeftOut(by: library)
            if leftOut > 0 {
                paletteFileLog.error("\(leftOut, privacy: .public) saved palette items could not be read or were over a limit. A copy of the file is kept.")
                let kept = NookDesignFiles.keepCopy(of: url, marked: "before-repair")
                return NookDesignLibraryLoad(
                    library: library,
                    problem: kept ? .partlyRead(skipped: leftOut) : .partlyReadNotKept(skipped: leftOut),
                    signature: before
                )
            }
            return NookDesignLibraryLoad(library: library, problem: nil, signature: before)
        } catch {
            paletteFileLog.error("The saved palettes could not be read: \(String(describing: error), privacy: .public)")
            return unreadable(url, before: before)
        }
    }

    private static func unreadable(_ url: URL, before: NookDesignFileSignature?) -> NookDesignLibraryLoad {
        let moved = NookDesignFiles.setAside(url, marked: "unreadable")
        return NookDesignLibraryLoad(
            library: .empty,
            problem: moved ? .unreadable : .unreadableNotKept,
            signature: moved ? nil : before
        )
    }

    /// Writes the library to `url`, making its folder first. False when it
    /// could not be written. This touches the disk and must run off the
    /// main actor.
    @discardableResult
    static func write(_ library: NookDesignLibrary, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encode(library).write(to: url, options: .atomic)
            return true
        } catch {
            paletteFileLog.error("The palettes could not be saved: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

/// Where the design kit keeps its files, and what it does with one it
/// cannot read.
enum NookDesignFiles {
    /// `Design` inside the folder the app keeps what it saves in (D45):
    /// `Library/Application Support/open-island/Design` in the app, and a
    /// folder of the run's own under the temporary folder in a test or a
    /// demo run. It is never spelled out as a path of its own, which is
    /// what keeps a test from reaching the user's saved colors.
    static var defaultFolder: URL {
        OpenIslandStateDirectory.url.appendingPathComponent("Design", isDirectory: true)
    }

    /// A folder no other model shares, for a model on a store of its own.
    /// It lies under the state directory and nothing is made there until
    /// something is saved.
    static func isolatedFolder() -> URL {
        OpenIslandStateDirectory.url.appendingPathComponent("Design-\(UUID().uuidString)", isDirectory: true)
    }

    /// The time to stamp a new item with: now, cut to the whole second.
    /// The files keep dates to the second, and an item must read back
    /// equal to the one that was saved.
    static func now() -> Date {
        Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    }

    static func isMissingFile(_ error: Error) -> Bool {
        let cocoa = error as NSError
        return cocoa.domain == NSCocoaErrorDomain && cocoa.code == NSFileReadNoSuchFileError
    }

    /// `palettes.json` marked "unreadable" is `palettes.unreadable.json`.
    static func markedURL(for url: URL, marked mark: String) -> URL {
        let base = url.deletingPathExtension().lastPathComponent
        let name = "\(base).\(mark).\(url.pathExtension)"
        return url.deletingLastPathComponent().appendingPathComponent(name)
    }

    /// Moves a file out of the way, over any file moved there before. The
    /// next save then cannot write over what the user had.
    @discardableResult
    static func setAside(_ url: URL, marked mark: String) -> Bool {
        let target = markedURL(for: url, marked: mark)
        let fm = FileManager.default
        try? fm.removeItem(at: target)
        do {
            try fm.moveItem(at: url, to: target)
            return true
        } catch {
            paletteFileLog.error("A file that could not be read could not be moved aside: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Copies a file beside itself, over any copy made before.
    @discardableResult
    static func keepCopy(of url: URL, marked mark: String) -> Bool {
        let target = markedURL(for: url, marked: mark)
        let fm = FileManager.default
        try? fm.removeItem(at: target)
        do {
            try fm.copyItem(at: url, to: target)
            return true
        } catch {
            paletteFileLog.error("A copy of a file could not be kept: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
