import CoreGraphics
import Foundation
import Observation

/// Holds the reference shelf: the list of pictures, and the copies and
/// thumbnails under `Design/References` in the state folder (D45).
/// Copying, decoding and deleting all run off the main actor. A thumbnail
/// is drawn once, when its picture is added, and decoded for a tile the
/// first time the tile asks.
@MainActor
@Observable
final class NookDesignReferenceStore {
    /// How many decoded thumbnails are kept in memory at most.
    nonisolated static let thumbnailCacheLimit = 96
    /// A panel size at or past this, in points, is not kept. No screen is
    /// that large, and the number must fit the list.
    nonisolated static let panelSizeLimit: CGFloat = 100_000

    private(set) var items: [NookDesignReference] = []
    private(set) var isLoaded = false
    /// What the last read had to leave out. Settings says it.
    private(set) var loadProblem: NookDesignLoadProblem?
    /// Decoded thumbnails, by picture.
    private(set) var thumbnails: [UUID: CGImage] = [:]
    /// Pictures being copied in right now.
    private(set) var addingCount = 0

    /// Why the shelf takes no change, if it does not.
    private(set) var lock: NookDesignStoreLock?

    /// Writes the list. A test swaps it for one that fails.
    @ObservationIgnored var writeList: @Sendable ([NookDesignReference], [UUID], URL) -> Bool = {
        NookDesignReferenceFiles.write($0, pendingDeletes: $1, to: $2)
    }

    /// Runs on the main actor when a save did not reach the disk.
    @ObservationIgnored var onSaveFailed: (() -> Void)?
    /// Runs when a change was asked for and refused because of the lock.
    @ObservationIgnored var onRefused: ((NookDesignStoreLock) -> Void)?

    @ObservationIgnored private let folder: URL
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// The disk writes still waiting, one behind the other.
    @ObservationIgnored private var diskTask: Task<Void, Never>?
    /// The list as this store last read it or wrote it.
    @ObservationIgnored private var knownSignature: NookDesignFileSignature?
    @ObservationIgnored private var pendingSaves = 0
    /// True while a write is not on disk yet.
    var hasPendingWrites: Bool { pendingSaves > 0 }
    /// Pictures taken off the shelf whose files are not deleted yet. They
    /// are written into the list, which gets the delete tried again at the
    /// next read and keeps the pictures from coming back as lost ones.
    @ObservationIgnored private var pendingDeletes: Set<UUID> = []
    @ObservationIgnored private var thumbnailRequests: Set<UUID> = []

    /// The app uses the default folder. Tests pass a temporary one.
    init(folder: URL? = nil) {
        self.folder = folder ?? NookDesignFiles.defaultFolder.appendingPathComponent("References", isDirectory: true)
    }

    var folderURL: URL { folder }

    func fileURL(for item: NookDesignReference) -> URL {
        NookDesignReferenceFiles.fileURL(for: item, in: folder)
    }

    func thumbnailURL(for item: NookDesignReference) -> URL {
        NookDesignReferenceFiles.thumbnailURL(for: item.id, in: folder)
    }

    func item(_ id: UUID) -> NookDesignReference? {
        items.first { $0.id == id }
    }

    // MARK: Reading

    /// Reads the saved shelf. A second call waits for the first.
    func load() async {
        if let loadTask { return await loadTask.value }
        let folder = folder
        let task = Task { [weak self] in
            let loaded = await Task.detached(priority: .userInitiated) {
                NookDesignReferenceFiles.load(from: folder)
            }.value
            guard let self else { return }
            self.adopt(loaded)
        }
        loadTask = task
        await task.value
    }

    /// Reads the list again when another copy of the app changed it since
    /// this store read or wrote it. True when it did.
    @discardableResult
    func refreshIfChanged() -> Bool {
        guard isLoaded, pendingSaves == 0 else { return false }
        guard NookDesignFileSignature.of(NookDesignReferenceFiles.indexURL(in: folder)) != knownSignature else { return false }
        adopt(NookDesignReferenceFiles.load(from: folder))
        return true
    }

    private func adopt(_ loaded: NookDesignReferenceLoad) {
        items = loaded.items
        pendingDeletes = Set(loaded.pendingDeletes)
        loadProblem = loaded.problem
        lock = loaded.problem?.lock
        knownSignature = loaded.signature
        isLoaded = true
        // A list that was built again, or had pictures taken back, or had a
        // delete tried again is saved, which makes the next read an ordinary
        // one. A list that takes no change is left as it is.
        if loaded.needsSave, lock == nil { save() }
    }

    /// The start of every change: the list is looked at, and a shelf that
    /// takes no change tells the user.
    private func beginChange() -> Bool {
        guard isLoaded else { return false }
        refreshIfChanged()
        if let lock {
            onRefused?(lock)
            return false
        }
        return true
    }

    /// Waits until every change made up to now is on disk.
    func flush() async {
        await diskTask?.value
    }

    // MARK: Adding

    /// Copies a picture file onto the shelf. The file it came from can be
    /// moved or deleted afterwards.
    @discardableResult
    func add(fileAt source: URL) -> Task<NookDesignReferenceAddResult, Never> {
        // A tile dragged out and dropped back must not copy itself in.
        guard !NookTrayStore.isInside(folder, source) else { return Task { .alreadyHere } }
        return add { folder, id, now in
            NookDesignReferenceFiles.importFile(
                at: source, into: folder, id: id, collectionID: NookDesignCollection.globalID, now: now
            )
        }
    }

    /// Puts picture data, such as a pasted picture, onto the shelf.
    @discardableResult
    func add(imageData data: Data, named name: String) -> Task<NookDesignReferenceAddResult, Never> {
        add { folder, id, now in
            NookDesignReferenceFiles.importData(
                data, named: name, into: folder, id: id, collectionID: NookDesignCollection.globalID, now: now
            )
        }
    }

    private func add(
        _ work: @escaping @Sendable (_ folder: URL, _ id: UUID, _ now: Date) -> NookDesignReferenceAddResult
    ) -> Task<NookDesignReferenceAddResult, Never> {
        guard isLoaded else { return Task { .failed } }
        guard beginChange() else { return Task { .locked } }
        guard items.count + addingCount < NookDesignReferenceRules.maxReferences else { return Task { .full } }
        let folder = folder
        addingCount += 1
        return Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                work(folder, UUID(), NookDesignFiles.now())
            }.value
            guard let self else { return result }
            self.addingCount -= 1
            guard case let .added(item) = result else { return result }
            // The list may have changed while the files were copied.
            self.refreshIfChanged()
            if let lock = self.lock {
                NookDesignReferenceFiles.removeFiles(of: item.id, in: folder)
                self.onRefused?(lock)
                return .locked
            }
            self.items.insert(item, at: 0)
            // "Added" is only promised once the list that names it is written.
            return await self.save().value ? .added(item) : .addedNotSaved(item)
        }
    }

    // MARK: Editing

    func rename(_ id: UUID, to name: String) {
        guard beginChange() else { return }
        update(id) { $0.name = NookDesignReferenceRules.cleanName(name) }
    }

    func toggleFavorite(_ id: UUID) {
        guard beginChange() else { return }
        update(id) { $0.isFavorite.toggle() }
    }

    func move(_ id: UUID, to index: Int) {
        guard beginChange() else { return }
        let moved = NookDesignReferenceRules.moving(id, to: index, in: items)
        guard moved != items else { return }
        items = moved
        save()
    }

    /// Moves a picture one place toward the front or the back.
    func nudge(_ id: UUID, by offset: Int) {
        guard beginChange() else { return }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        move(id, to: index + offset)
    }

    /// Remembers the size a picture's floating panel was left at, which the
    /// panel opens at next time. A shelf that takes no change keeps what it
    /// has without a word: a panel the user dragged larger is no reason to
    /// say the shelf is locked.
    func rememberPanelSize(_ id: UUID, _ size: CGSize) {
        guard isLoaded, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0, size.width < Self.panelSizeLimit, size.height < Self.panelSizeLimit else { return }
        refreshIfChanged()
        guard lock == nil else { return }
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        update(id) {
            $0.panelWidth = width
            $0.panelHeight = height
        }
    }

    /// Takes a picture off the shelf and deletes its copy and thumbnail.
    @discardableResult
    func remove(_ id: UUID) -> Task<Void, Never> {
        guard beginChange(), items.contains(where: { $0.id == id }) else { return Task {} }
        items.removeAll { $0.id == id }
        thumbnails[id] = nil
        thumbnailRequests.remove(id)
        pendingDeletes.insert(id)
        save()
        return deleteFiles(of: [id])
    }

    /// Empties the shelf and deletes every copy.
    @discardableResult
    func clear() -> Task<Void, Never> {
        guard beginChange(), !items.isEmpty else { return Task {} }
        let ids = items.map(\.id)
        items = []
        thumbnails = [:]
        thumbnailRequests = []
        pendingDeletes.formUnion(ids)
        save()
        return deleteFiles(of: ids)
    }

    // MARK: Thumbnails

    /// Decodes a picture's thumbnail for its tile, once. A thumbnail file
    /// that is gone is drawn again from the picture.
    func requestThumbnail(for item: NookDesignReference) {
        guard thumbnails[item.id] == nil, thumbnailRequests.insert(item.id).inserted else { return }
        let id = item.id
        let picture = fileURL(for: item)
        let thumbnail = thumbnailURL(for: item)
        Task { [weak self] in
            let image = await Task.detached(priority: .utility) { () -> CGImage? in
                let limit = NookDesignReferenceRules.thumbnailMaxPixel
                if let saved = NookDesignPictures.image(fileAt: thumbnail, maxPixel: limit) { return saved }
                guard NookDesignPictures.writeThumbnail(ofFileAt: picture, to: thumbnail) else { return nil }
                return NookDesignPictures.image(fileAt: thumbnail, maxPixel: limit)
            }.value
            guard let self else { return }
            self.thumbnailRequests.remove(id)
            guard let image, self.items.contains(where: { $0.id == id }) else { return }
            self.thumbnails[id] = image
            self.trimThumbnails()
        }
    }

    /// Keeps the decoded thumbnails under the limit by letting go of the
    /// ones furthest down the shelf.
    private func trimThumbnails() {
        guard thumbnails.count > Self.thumbnailCacheLimit else { return }
        let keep = Set(items.prefix(Self.thumbnailCacheLimit / 2).map(\.id))
        thumbnails = thumbnails.filter { keep.contains($0.key) }
    }

    // MARK: Private

    private func update(_ id: UUID, _ change: (inout NookDesignReference) -> Void) {
        guard isLoaded, let index = items.firstIndex(where: { $0.id == id }) else { return }
        var changed = items[index]
        change(&changed)
        guard changed != items[index] else { return }
        items[index] = changed
        save()
    }

    /// Queues a write of the list behind the disk work already waiting. The
    /// task ends with whether the list was written.
    @discardableResult
    private func save() -> Task<Bool, Never> {
        let snapshot = items
        let deletes = Array(pendingDeletes)
        let folder = folder
        let previous = diskTask
        let writeList = writeList
        pendingSaves += 1
        let task = Task.detached(priority: .utility) { [weak self] () -> Bool in
            await previous?.value
            let wrote = writeList(snapshot, deletes, folder)
            let signature = wrote ? NookDesignFileSignature.of(NookDesignReferenceFiles.indexURL(in: folder)) : nil
            await MainActor.run { self?.finishSave(wrote: wrote, signature: signature) }
            return wrote
        }
        diskTask = Task { _ = await task.value }
        return task
    }

    private func finishSave(wrote: Bool, signature: NookDesignFileSignature?) {
        pendingSaves -= 1
        if wrote {
            knownSignature = signature
        } else {
            onSaveFailed?()
        }
    }

    /// Deletes the files of pictures taken off the shelf. A picture whose
    /// files could not be deleted stays in the list's pending deletes, which
    /// the next read tries again.
    private func deleteFiles(of ids: [UUID]) -> Task<Void, Never> {
        let folder = folder
        let previous = diskTask
        let task = Task.detached(priority: .utility) { [weak self] in
            await previous?.value
            var deleted: [UUID] = []
            for id in ids where NookDesignReferenceFiles.removeFiles(of: id, in: folder) {
                deleted.append(id)
            }
            await MainActor.run { self?.finishDelete(deleted) }
        }
        diskTask = task
        return task
    }

    private func finishDelete(_ deleted: [UUID]) {
        let before = pendingDeletes
        pendingDeletes.subtract(deleted)
        if pendingDeletes != before { save() }
    }
}
