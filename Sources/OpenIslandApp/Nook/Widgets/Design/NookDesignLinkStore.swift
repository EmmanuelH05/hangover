import Foundation
import Observation

/// Holds the Links tab's shelf and keeps it in `links.json` in the kit's
/// own folder. It follows the color shelf's store: the library is read once,
/// off the main actor, every change is written the same way in the order it
/// was made, and nothing can change before the first read is done, which
/// keeps an early click from saving an empty shelf over a full one.
@MainActor
@Observable
final class NookDesignLinkStore {
    private(set) var library = NookDesignLinkLibrary.empty
    private(set) var isLoaded = false
    /// What the last read had to leave out. Settings says it.
    private(set) var loadProblem: NookDesignLoadProblem?

    /// Why the shelf takes no change, if it does not.
    private(set) var lock: NookDesignStoreLock?

    /// Runs on the main actor when a save did not reach the disk.
    @ObservationIgnored var onSaveFailed: (() -> Void)?
    /// Runs when a change was asked for and refused because of the lock.
    @ObservationIgnored var onRefused: ((NookDesignStoreLock) -> Void)?

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// The file as this store last read it or wrote it (see the color shelf's store).
    @ObservationIgnored private var knownSignature: NookDesignFileSignature?
    @ObservationIgnored private var pendingSaves = 0
    /// True while a write is not on disk yet.
    var hasPendingWrites: Bool { pendingSaves > 0 }
    /// True when the last write that finished did not reach the disk.
    private(set) var lastSaveFailed = false

    /// The app uses the default folder. Tests pass a temporary one.
    init(folder: URL? = nil) {
        fileURL = (folder ?? NookDesignFiles.defaultFolder).appendingPathComponent(NookDesignLinkFile.fileName)
    }

    var folderURL: URL { fileURL.deletingLastPathComponent() }

    // MARK: Reading

    /// Reads the saved shelf. A second call waits for the first.
    func load() async {
        if let loadTask { return await loadTask.value }
        let url = fileURL
        let task = Task { [weak self] in
            let loaded = await Task.detached(priority: .userInitiated) {
                NookDesignLinkFile.load(from: url)
            }.value
            guard let self else { return }
            self.adopt(loaded)
        }
        loadTask = task
        await task.value
    }

    /// Reads the file again when another copy of the app changed it since
    /// this store read or wrote it. True when it did.
    @discardableResult
    func refreshIfChanged() -> Bool {
        guard isLoaded, pendingSaves == 0 else { return false }
        guard NookDesignFileSignature.of(fileURL) != knownSignature else { return false }
        adopt(NookDesignLinkFile.load(from: fileURL))
        return true
    }

    private func adopt(_ loaded: NookDesignLinkLibraryLoad) {
        library = loaded.library
        loadProblem = loaded.problem
        lock = loaded.problem?.lock
        knownSignature = loaded.signature
        isLoaded = true
    }

    /// The start of every change: the file is looked at, and a shelf that
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
        await saveTask?.value
    }

    var links: [NookDesignLink] { library.links }
    var collections: [NookDesignLinkCollection] { library.collections }

    func link(_ id: UUID) -> NookDesignLink? { library.link(id) }

    // MARK: Links

    /// Adds a link for an address the rules took. `name` is the one the
    /// user gave, and the default name is made from the address without it.
    @discardableResult
    func addLink(
        _ address: NookDesignLinkAddress,
        name: String? = nil,
        to collectionID: UUID? = nil,
        now: Date = NookDesignFiles.now()
    ) -> NookDesignLinkAddOutcome {
        guard isLoaded else { return .notLoaded }
        guard beginChange() else { return .notLoaded }
        let outcome = library.addingLink(
            url: address.url,
            name: name ?? NookDesignLinkRules.defaultName(for: address),
            to: collectionID,
            now: now
        )
        if case let .added(changed, _) = outcome { apply(changed) }
        return outcome
    }

    func renameLink(_ id: UUID, to name: String) {
        guard beginChange() else { return }
        apply(library.renamingLink(id, to: name))
    }

    func removeLink(_ id: UUID) {
        guard beginChange() else { return }
        apply(library.removingLink(id))
    }

    func toggleFavorite(_ id: UUID) {
        guard beginChange() else { return }
        apply(library.togglingFavorite(id))
    }

    func markOpened(_ id: UUID, now: Date = NookDesignFiles.now()) {
        guard beginChange() else { return }
        apply(library.markingOpened(id, now: now))
    }

    @discardableResult
    func moveLink(_ id: UUID, to collectionID: UUID?) -> NookDesignLinkMoveOutcome {
        guard beginChange() else { return .unknownLink }
        let outcome = library.movingLink(id, to: collectionID)
        if case let .moved(changed) = outcome { apply(changed) }
        return outcome
    }

    /// Files a link under the collection of this name, making it first
    /// when there is none.
    @discardableResult
    func moveLink(_ id: UUID, toCollectionNamed name: String) -> NookDesignLinkMoveOutcome {
        guard beginChange() else { return .unknownLink }
        let outcome = library.movingLink(id, toCollectionNamed: name)
        if case let .moved(changed) = outcome { apply(changed) }
        return outcome
    }

    // MARK: Collections

    @discardableResult
    func addCollection(named name: String) -> NookDesignCollectionOutcome {
        guard beginChange() else { return .unknown }
        let outcome = library.addingCollection(named: name)
        if case let .done(changed, _) = outcome { apply(changed) }
        return outcome
    }

    @discardableResult
    func renameCollection(_ id: UUID, to name: String) -> NookDesignCollectionOutcome {
        guard beginChange() else { return .unknown }
        let outcome = library.renamingCollection(id, to: name)
        if case let .done(changed, _) = outcome { apply(changed) }
        return outcome
    }

    func removeCollection(_ id: UUID) {
        guard beginChange() else { return }
        apply(library.removingCollection(id))
    }

    // MARK: Private

    private func apply(_ changed: NookDesignLinkLibrary) {
        guard isLoaded, changed != library else { return }
        library = changed
        save()
    }

    /// Queues a write behind the ones already waiting, which keeps the
    /// file ending up as the newest library.
    private func save() {
        let snapshot = library
        let url = fileURL
        let previous = saveTask
        pendingSaves += 1
        saveTask = Task.detached(priority: .utility) { [weak self] in
            await previous?.value
            let wrote = NookDesignLinkFile.write(snapshot, to: url)
            let signature = wrote ? NookDesignFileSignature.of(url) : nil
            await MainActor.run { self?.finishSave(wrote: wrote, signature: signature) }
        }
    }

    private func finishSave(wrote: Bool, signature: NookDesignFileSignature?) {
        pendingSaves -= 1
        lastSaveFailed = !wrote
        if wrote {
            knownSignature = signature
        } else {
            onSaveFailed?()
        }
    }
}
