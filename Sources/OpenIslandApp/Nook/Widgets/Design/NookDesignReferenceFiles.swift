import Foundation
import ImageIO
import OSLog

private let referenceFileLog = Logger(subsystem: "app.openisland", category: "nook.design")

/// What reading the reference shelf came to.
struct NookDesignReferenceLoad: Equatable, Sendable {
    var items: [NookDesignReference]
    /// Pictures the user took off the shelf whose files could not be
    /// deleted. They are deleted again at the next read, and they are never
    /// taken back as pictures the list lost.
    var pendingDeletes: [UUID] = []
    var problem: NookDesignLoadProblem?
    /// The list as it stands after the read.
    var signature: NookDesignFileSignature?
    /// True when the list should be written again now: it was built again,
    /// pictures were taken back, or a delete was tried again.
    var needsSave = false
}

/// The reference shelf on disk. Under its folder,
/// `Design/References` in the state folder (D45), sit:
///
/// - `index.json`: `{ "version": 1, "items": [ … ] }`, the pictures in
///   the order the shelf shows them. Each item carries its id, its
///   collection's id, a name, the file's name, the pixel size, the
///   favorite mark and the date it was added. An item the user has
///   resized the floating panel of also carries `panelWidth` and
///   `panelHeight`, in points. They are optional and the version stays 1.
///   A copy of the app that does not know them reads the list as it
///   always did and drops them the next time it writes it.
/// - one folder per picture, named by the picture's id, holding the copy
///   (`original.png`, with the ending of its real type) and
///   `thumbnail.png`.
///
/// The folders are the truth and the index is the order and the names. An
/// index that is gone or cannot be read is built again from the folders,
/// which is why a damaged index loses names and order and never a picture.
///
/// Everything here touches the disk and runs off the main actor.
enum NookDesignReferenceFiles {
    static let indexFileName = "index.json"
    static let currentVersion = 1

    private struct Index: Codable {
        var version: Int
        var items: [NookDesignReference]
        /// Pictures taken off the shelf whose files are still to be deleted.
        var pendingDelete: [UUID]

        private enum CodingKeys: String, CodingKey {
            case version, items, pendingDelete
        }

        init(items: [NookDesignReference], pendingDelete: [UUID]) {
            version = NookDesignReferenceFiles.currentVersion
            self.items = items
            self.pendingDelete = pendingDelete
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = (try? container.decode(Int.self, forKey: .version)) ?? NookDesignReferenceFiles.currentVersion
            items = try container.decode(NookDesignLossyList<NookDesignReference>.self, forKey: .items).elements
            pendingDelete = container.lenient([UUID].self, forKey: .pendingDelete, fallback: [], counter: decoder.skipCounter)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(version, forKey: .version)
            try container.encode(items, forKey: .items)
            if !pendingDelete.isEmpty { try container.encode(pendingDelete, forKey: .pendingDelete) }
        }
    }

    static func indexURL(in folder: URL) -> URL {
        folder.appendingPathComponent(indexFileName)
    }

    static func folderURL(for id: UUID, in folder: URL) -> URL {
        folder.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func fileURL(for item: NookDesignReference, in folder: URL) -> URL {
        folderURL(for: item.id, in: folder).appendingPathComponent(item.fileName)
    }

    static func thumbnailURL(for id: UUID, in folder: URL) -> URL {
        folderURL(for: id, in: folder).appendingPathComponent(NookDesignReferenceRules.thumbnailFileName)
    }

    // MARK: Reading

    /// Reads the shelf. Nothing is dropped without a copy and a report, and
    /// nothing is rewritten here: a newer build's list is left exactly as it
    /// is, and what has to be written is said in `needsSave`, which the store
    /// acts on once it knows the list takes changes.
    static func load(from folder: URL) -> NookDesignReferenceLoad {
        let url = indexURL(in: folder)
        let before = NookDesignFileSignature.of(url)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            if NookDesignFiles.isMissingFile(error) {
                // A list that is gone is built again from the folders. Nothing
                // is "moved aside": there was nothing to move.
                let found = recover(from: folder, excluding: [])
                return NookDesignReferenceLoad(
                    items: found,
                    problem: found.isEmpty ? nil : .indexMissing(recovered: found.count),
                    signature: before,
                    needsSave: !found.isEmpty
                )
            }
            referenceFileLog.error("The reference list could not be opened: \(error.localizedDescription, privacy: .public)")
            return unreadable(folder, url, before: before)
        }

        let counter = NookDesignSkipCounter()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(NookDesignDates.decoding)
        decoder.userInfo[NookDesignSkipCounter.key] = counter
        guard let index = try? decoder.decode(Index.self, from: data) else {
            referenceFileLog.error("The reference list could not be read. It is built again from the pictures.")
            return unreadable(folder, url, before: before)
        }
        if index.version > currentVersion {
            // Nothing is shown, nothing is written, and no picture is touched.
            return NookDesignReferenceLoad(items: [], problem: .newerVersion(index.version), signature: before)
        }

        // The deletes that failed last time are tried again.
        var stillPending: [UUID] = []
        for id in index.pendingDelete where !removeFiles(of: id, in: folder) {
            stillPending.append(id)
        }
        let neverShown = Set(index.pendingDelete)

        var leftOut = counter.count
        let cleaned = sanitizedCounting(index.items.filter { !neverShown.contains($0.id) })
        leftOut += cleaned.dropped
        let present = cleaned.items.filter { item in
            let exists = isSafeFileName(item.fileName)
                && FileManager.default.fileExists(atPath: fileURL(for: item, in: folder).path)
            if !exists {
                referenceFileLog.error("A reference whose picture is missing or whose file name is unsafe was left out: \(item.id.uuidString, privacy: .public)")
                leftOut += 1
            }
            return exists
        }

        // Pictures in the folder that the list does not have are taken back.
        let taken = recover(from: folder, excluding: Set(index.items.map(\.id)).union(neverShown))
        let items = taken + present
        let pendingChanged = stillPending.count != index.pendingDelete.count
        let needsSave = leftOut > 0 || !taken.isEmpty || pendingChanged

        var problem: NookDesignLoadProblem?
        if leftOut > 0 {
            let kept = NookDesignFiles.keepCopy(of: url, marked: "before-repair")
            problem = kept ? .partlyRead(skipped: leftOut) : .partlyReadNotKept(skipped: leftOut)
        } else if !taken.isEmpty {
            problem = .picturesTakenBack(taken.count)
        }
        return NookDesignReferenceLoad(
            items: items, pendingDeletes: stillPending, problem: problem, signature: before, needsSave: needsSave
        )
    }

    /// A list that cannot be read. It is moved aside, and the shelf is built
    /// again from the folders. When it cannot be moved it stays where it is,
    /// the pictures are shown, and nothing is written over it.
    private static func unreadable(_ folder: URL, _ url: URL, before: NookDesignFileSignature?) -> NookDesignReferenceLoad {
        let moved = NookDesignFiles.setAside(url, marked: "unreadable")
        return NookDesignReferenceLoad(
            items: recover(from: folder, excluding: []),
            problem: moved ? .unreadable : .unreadableNotKept,
            signature: moved ? nil : before,
            needsSave: moved
        )
    }

    /// Unique ids, clean names, and no more than the shelf may hold, with a
    /// count of what that took away: a repeated id, an entry past the limit
    /// and a name that was cut.
    static func sanitizedCounting(_ items: [NookDesignReference]) -> (items: [NookDesignReference], dropped: Int) {
        var seen = Set<UUID>()
        var dropped = 0
        var unique: [NookDesignReference] = []
        for item in items {
            if seen.insert(item.id).inserted { unique.append(item) } else { dropped += 1 }
        }
        if unique.count > NookDesignReferenceRules.maxReferences {
            dropped += unique.count - NookDesignReferenceRules.maxReferences
            unique = Array(unique.prefix(NookDesignReferenceRules.maxReferences))
        }
        let cleaned = unique.map { item -> NookDesignReference in
            var clean = item
            if item.name.count > NookDesignReferenceRules.maxNameLength { dropped += 1 }
            clean.name = NookDesignReferenceRules.cleanName(item.name)
            return clean
        }
        return (cleaned, dropped)
    }

    /// Unique ids, clean names, and no more than the shelf may hold.
    static func sanitized(_ items: [NookDesignReference]) -> [NookDesignReference] {
        sanitizedCounting(items).items
    }

    /// A stored file name is one name with no folder in it. A list edited
    /// by hand must not point the shelf at a file outside its folder.
    static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\")
    }

    /// The pictures found in the folders, newest first, apart from the ones
    /// in `excluding`. With none found nothing was wrong.
    static func recover(from folder: URL, excluding: Set<UUID>) -> [NookDesignReference] {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        var items: [NookDesignReference] = []
        for candidate in folders {
            guard let id = UUID(uuidString: candidate.lastPathComponent), !excluding.contains(id),
                  let files = try? fm.contentsOfDirectory(at: candidate, includingPropertiesForKeys: [.creationDateKey]),
                  let picture = files.first(where: {
                      $0.deletingPathExtension().lastPathComponent == NookDesignReferenceRules.originalBaseName
                  }),
                  let info = NookDesignPictures.inspect(fileAt: picture) else { continue }
            let created = (try? picture.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date(timeIntervalSince1970: 0)
            items.append(NookDesignReference(
                id: id,
                collectionID: NookDesignCollection.globalID,
                name: "",
                fileName: picture.lastPathComponent,
                pixelWidth: info.pixelWidth,
                pixelHeight: info.pixelHeight,
                isFavorite: false,
                addedAt: created
            ))
        }
        let newestFirst = items.sorted { $0.addedAt > $1.addedAt }
        return Array(newestFirst.prefix(NookDesignReferenceRules.maxReferences))
    }

    // MARK: Writing

    @discardableResult
    static func write(_ items: [NookDesignReference], pendingDeletes: [UUID] = [], to folder: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try encoder.encode(Index(items: items, pendingDelete: pendingDeletes)).write(to: indexURL(in: folder), options: .atomic)
            return true
        } catch {
            referenceFileLog.error("The reference list could not be saved: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Removes a picture's folder: the copy and its thumbnail. True when it
    /// is gone, which includes a folder that was never there.
    @discardableResult
    static func removeFiles(of id: UUID, in folder: URL) -> Bool {
        let target = folderURL(for: id, in: folder)
        do {
            try FileManager.default.removeItem(at: target)
            return true
        } catch {
            if NookDesignFiles.isMissingFile(error) { return true }
            referenceFileLog.error("A removed reference's files could not be deleted: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: Adding

    /// Copies a picture file into the shelf and draws its thumbnail.
    static func importFile(
        at source: URL,
        into folder: URL,
        id: UUID,
        collectionID: UUID,
        now: Date
    ) -> NookDesignReferenceAddResult {
        // A file that cannot be opened to be read says nothing about what is in it.
        guard FileManager.default.isReadableFile(atPath: source.path) else { return .unreadable }
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= NookDesignReferenceRules.maxFileBytes else { return .tooLarge }
        guard let info = NookDesignPictures.inspect(fileAt: source) else { return .notAPicture }
        guard info.pixelCount <= NookDesignReferenceRules.maxPixels else { return .tooLarge }
        return store(info, named: NookDesignReferenceRules.displayName(forFileNamed: source.lastPathComponent),
                     into: folder, id: id, collectionID: collectionID, now: now) { destination in
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    /// Writes picture data, such as a pasted picture, into the shelf.
    static func importData(
        _ data: Data,
        named name: String,
        into folder: URL,
        id: UUID,
        collectionID: UUID,
        now: Date
    ) -> NookDesignReferenceAddResult {
        guard data.count <= NookDesignReferenceRules.maxFileBytes else { return .tooLarge }
        guard let info = NookDesignPictures.inspect(data) else { return .notAPicture }
        guard info.pixelCount <= NookDesignReferenceRules.maxPixels else { return .tooLarge }
        return store(info, named: NookDesignReferenceRules.cleanName(name),
                     into: folder, id: id, collectionID: collectionID, now: now) { destination in
            try data.write(to: destination, options: .atomic)
        }
    }

    /// Makes the picture's folder, lets `place` put the copy in it, and
    /// draws the thumbnail. A failure removes whatever was written.
    private static func store(
        _ info: NookDesignPictureInfo,
        named name: String,
        into folder: URL,
        id: UUID,
        collectionID: UUID,
        now: Date,
        place: (URL) throws -> Void
    ) -> NookDesignReferenceAddResult {
        let item = NookDesignReference(
            id: id,
            collectionID: collectionID,
            name: name,
            fileName: NookDesignReferenceRules.storedFileName(typeIdentifier: info.typeIdentifier),
            pixelWidth: info.pixelWidth,
            pixelHeight: info.pixelHeight,
            isFavorite: false,
            addedAt: now
        )
        let subfolder = folderURL(for: id, in: folder)
        let copy = fileURL(for: item, in: folder)
        do {
            try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
            try place(copy)
        } catch {
            referenceFileLog.error("A picture could not be copied to the references: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: subfolder)
            return .failed
        }
        // A picture whose header read and whose pixels do not is no use on
        // the shelf: it could never be shown. It is a picture all the same,
        // and the line says that its preview could not be written.
        guard NookDesignPictures.writeThumbnail(ofFileAt: copy, to: thumbnailURL(for: id, in: folder)) else {
            try? FileManager.default.removeItem(at: subfolder)
            return .previewFailed
        }
        return .added(item)
    }
}
