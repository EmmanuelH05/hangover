import Foundation
import OSLog

private let linkFileLog = Logger(subsystem: "app.openisland", category: "nook.design")

// Each saved link reads what it can. A missing id gets a new one, a missing
// name is made from the address, a missing date is the epoch. Only an
// address that is no whole, valid web link makes its item fail, and the
// list skips it: a file edited by hand must not put a `javascript:` or a
// `file:` address on the card.

extension NookDesignLink: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, url, name, collectionID, isFavorite, addedAt, lastOpenedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let url = try container.decode(String.self, forKey: .url)
        guard NookDesignLinkRules.isStorable(url) else {
            throw DecodingError.dataCorruptedError(forKey: .url, in: container, debugDescription: "Not a web link")
        }
        self.url = url
        let counter = decoder.skipCounter
        id = container.lenient(UUID.self, forKey: .id, fallback: UUID(), counter: counter)
        name = container.lenient(String.self, forKey: .name, fallback: "", counter: counter)
        collectionID = container.lenientOptional(UUID.self, forKey: .collectionID, counter: counter)
        isFavorite = container.lenient(Bool.self, forKey: .isFavorite, fallback: false, counter: counter)
        addedAt = container.lenient(Date.self, forKey: .addedAt, fallback: Date(timeIntervalSince1970: 0), counter: counter)
        lastOpenedAt = container.lenientOptional(Date.self, forKey: .lastOpenedAt, counter: counter)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(collectionID, forKey: .collectionID)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(addedAt, forKey: .addedAt)
        try container.encodeIfPresent(lastOpenedAt, forKey: .lastOpenedAt)
    }
}

extension NookDesignLinkCollection: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let counter = decoder.skipCounter
        id = container.lenient(UUID.self, forKey: .id, fallback: UUID(), counter: counter)
        name = container.lenient(String.self, forKey: .name, fallback: "", counter: counter)
        createdAt = container.lenient(Date.self, forKey: .createdAt, fallback: Date(timeIntervalSince1970: 0), counter: counter)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

extension NookDesignLinkLibrary: Codable {
    private enum CodingKeys: String, CodingKey {
        case version, links, collections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let counter = decoder.skipCounter
        if decoder.isWrongShape(contentKeys: ["links", "collections"]) { counter?.add() }
        version = (try? container.decode(Int.self, forKey: .version)) ?? Self.currentVersion
        links = container.lossyElements(NookDesignLink.self, forKey: .links, counter: counter)
        collections = container.lossyElements(NookDesignLinkCollection.self, forKey: .collections, counter: counter)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(collections, forKey: .collections)
        try container.encode(links, forKey: .links)
    }
}

/// What reading the links file came to.
struct NookDesignLinkLibraryLoad: Equatable, Sendable {
    var library: NookDesignLinkLibrary
    var problem: NookDesignLoadProblem?
    /// The file as it stands after the read (see `NookDesignLibraryLoad`).
    var signature: NookDesignFileSignature?
}

/// Reads and writes `links.json`, the Links tab's one file:
///
/// ```json
/// {
///   "version": 1,
///   "collections": [ { "id": "…", "name": "Client work", "createdAt": "2026-10-09T12:00:00Z" } ],
///   "links": [
///     { "id": "…", "url": "https://www.figma.com/design/KEY/Name?node-id=1-2", "name": "Brand kit",
///       "collectionID": "…", "isFavorite": true, "addedAt": "…", "lastOpenedAt": "…" }
///   ]
/// }
/// ```
///
/// It follows the color shelf's file in everything that can go wrong. A
/// missing file is an empty shelf. A file that is not JSON this build can
/// read is moved aside before anything is saved over it. One item that does
/// not read costs that item. A file from a newer build is read as far as it
/// can be, and a copy is kept. A failed write is reported by the store.
enum NookDesignLinkFile {
    static let fileName = "links.json"

    static func decode(_ data: Data) throws -> (library: NookDesignLinkLibrary, skipped: Int) {
        let counter = NookDesignSkipCounter()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(NookDesignDates.decoding)
        decoder.userInfo[NookDesignSkipCounter.key] = counter
        let library = try decoder.decode(NookDesignLinkLibrary.self, from: data)
        return (library, counter.count)
    }

    static func encode(_ library: NookDesignLinkLibrary) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var current = library
        current.version = NookDesignLinkLibrary.currentVersion
        return try encoder.encode(current)
    }

    /// Reads the file at `url`. This touches the disk and must run off the
    /// main actor. What it does with a file that is damaged, over a limit or
    /// from a newer build is what `NookDesignLibraryFile.load` does.
    static func load(from url: URL) -> NookDesignLinkLibraryLoad {
        let before = NookDesignFileSignature.of(url)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            if !NookDesignFiles.isMissingFile(error) {
                linkFileLog.error("The saved links could not be opened: \(error.localizedDescription, privacy: .public)")
                return unreadable(url, before: before)
            }
            return NookDesignLinkLibraryLoad(library: .empty, problem: nil, signature: before)
        }
        do {
            let read = try decode(data)
            if read.library.version > NookDesignLinkLibrary.currentVersion {
                linkFileLog.error("The saved links come from a newer build (version \(read.library.version, privacy: .public)). They are left alone.")
                return NookDesignLinkLibraryLoad(library: .empty, problem: .newerVersion(read.library.version), signature: before)
            }
            let library = read.library.sanitized()
            // What did not read, and what is over a limit. Either way something
            // is left out, and the file is kept as it was before a save changes it.
            let overLimit = (read.library.links.count - library.links.count) + (read.library.collections.count - library.collections.count)
            let leftOut = read.skipped + overLimit
            if leftOut > 0 {
                linkFileLog.error("\(leftOut, privacy: .public) saved links or collections were left out. A copy of the file is kept.")
                let kept = NookDesignFiles.keepCopy(of: url, marked: "before-repair")
                return NookDesignLinkLibraryLoad(
                    library: library,
                    problem: kept ? .partlyRead(skipped: leftOut) : .partlyReadNotKept(skipped: leftOut),
                    signature: before
                )
            }
            return NookDesignLinkLibraryLoad(library: library, problem: nil, signature: before)
        } catch {
            linkFileLog.error("The saved links could not be read: \(String(describing: error), privacy: .public)")
            return unreadable(url, before: before)
        }
    }

    private static func unreadable(_ url: URL, before: NookDesignFileSignature?) -> NookDesignLinkLibraryLoad {
        let moved = NookDesignFiles.setAside(url, marked: "unreadable")
        return NookDesignLinkLibraryLoad(
            library: .empty,
            problem: moved ? .unreadable : .unreadableNotKept,
            signature: moved ? nil : before
        )
    }

    /// Writes the library to `url`, making its folder first. False when it
    /// could not be written. This touches the disk and must run off the
    /// main actor.
    @discardableResult
    static func write(_ library: NookDesignLinkLibrary, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encode(library).write(to: url, options: .atomic)
            return true
        } catch {
            linkFileLog.error("The links could not be saved: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
