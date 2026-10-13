import Foundation
import Observation

/// Holds the color shelf and keeps it in `palettes.json` under the app's
/// state folder (D45). The library is read once, off the main actor, and
/// every change is written the same way, in the order the changes were
/// made. Nothing can be changed before the first read is done, which keeps
/// an early click from saving an empty shelf over a full one.
@MainActor
@Observable
final class NookDesignPaletteStore {
    private(set) var library = NookDesignLibrary.empty
    private(set) var isLoaded = false
    /// What the last read had to leave out. Settings says it.
    private(set) var loadProblem: NookDesignLoadProblem?

    /// Why the shelf takes no change, if it does not (a file from a newer
    /// build, or a file that could not be kept before it was repaired).
    private(set) var lock: NookDesignStoreLock?

    /// Runs on the main actor when a save did not reach the disk.
    @ObservationIgnored var onSaveFailed: (() -> Void)?
    /// Runs when a change was asked for and refused because of the lock.
    @ObservationIgnored var onRefused: ((NookDesignStoreLock) -> Void)?

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// The file as this store last read it or wrote it. A file that is not
    /// like this was changed by someone else.
    @ObservationIgnored private var knownSignature: NookDesignFileSignature?
    /// Writes queued and not yet finished. While there are any the file is
    /// this store's own, and looking at it would show an older shelf.
    @ObservationIgnored private var pendingSaves = 0
    /// True while a write is not on disk yet.
    var hasPendingWrites: Bool { pendingSaves > 0 }
    /// True when the last write that finished did not reach the disk.
    private(set) var lastSaveFailed = false

    /// The app uses the default folder. Tests pass a temporary one.
    init(folder: URL? = nil) {
        fileURL = (folder ?? NookDesignFiles.defaultFolder).appendingPathComponent(NookDesignLibraryFile.fileName)
    }

    var folderURL: URL { fileURL.deletingLastPathComponent() }

    // MARK: Reading

    /// Reads the saved library. A second call waits for the first.
    func load() async {
        if let loadTask { return await loadTask.value }
        let url = fileURL
        let task = Task { [weak self] in
            let loaded = await Task.detached(priority: .userInitiated) {
                NookDesignLibraryFile.load(from: url)
            }.value
            guard let self else { return }
            self.adopt(loaded)
        }
        loadTask = task
        await task.value
    }

    /// Looks at the file, and when another copy of the app changed it since
    /// this store read or wrote it, reads it again. Every change calls this
    /// first, which makes the change land on what the file holds now. The
    /// island opening calls it too, which keeps what is shown current.
    /// True when the shelf was read again.
    @discardableResult
    func refreshIfChanged() -> Bool {
        guard isLoaded, pendingSaves == 0 else { return false }
        guard NookDesignFileSignature.of(fileURL) != knownSignature else { return false }
        adopt(NookDesignLibraryFile.load(from: fileURL))
        return true
    }

    private func adopt(_ loaded: NookDesignLibraryLoad) {
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

    var palettes: [NookDesignPalette] { library.palettes() }
    var activePalette: NookDesignPalette? { library.activePalette() }
    var recents: [NookDesignRecentColor] { library.recents() }

    var colorCount: Int { library.palettes.reduce(0) { $0 + $1.swatches.count } }

    // MARK: Palettes

    @discardableResult
    func addPalette(named name: String) -> NookDesignPalette? {
        guard beginChange(), let added = library.addingPalette(named: name) else { return nil }
        apply(added.library)
        return added.palette
    }

    func renamePalette(_ id: UUID, to name: String) {
        guard beginChange() else { return }
        apply(library.renamingPalette(id, to: name))
    }

    func removePalette(_ id: UUID) {
        guard beginChange() else { return }
        apply(library.removingPalette(id))
    }

    func setActivePalette(_ id: UUID) {
        guard beginChange() else { return }
        apply(library.settingActivePalette(id))
    }

    /// Makes the palette after the active one active, wrapping at the end.
    func selectNextPalette() {
        let all = palettes
        guard all.count > 1, let active = activePalette,
              let index = all.firstIndex(where: { $0.id == active.id }) else { return }
        setActivePalette(all[(index + 1) % all.count].id)
    }

    // MARK: Colors

    /// Adds a color to a palette, or to the active one when none is named.
    /// With no palette at all, one called `defaultPaletteName` is made
    /// first.
    @discardableResult
    func addColor(
        _ color: NookDesignColor,
        named name: String = "",
        to paletteID: UUID? = nil,
        defaultPaletteName: String
    ) -> NookDesignAddOutcome {
        guard beginChange() else { return .noPalette }
        var working = library
        var target = paletteID ?? working.activePalette()?.id
        if target == nil {
            guard let made = working.addingPalette(named: defaultPaletteName) else { return .noPalette }
            working = made.library
            target = made.palette.id
        }
        guard let target else { return .noPalette }
        let outcome = working.addingColor(color, named: name, to: target)
        if case let .added(changed, _) = outcome { apply(changed) }
        return outcome
    }

    func renameSwatch(_ id: UUID, to name: String) {
        guard beginChange() else { return }
        apply(library.renamingSwatch(id, to: name))
    }

    func toggleFavorite(_ id: UUID) {
        guard beginChange() else { return }
        apply(library.togglingFavorite(id))
    }

    func removeSwatch(_ id: UUID) {
        guard beginChange() else { return }
        apply(library.removingSwatch(id))
    }

    func moveSwatch(_ id: UUID, to index: Int) {
        guard beginChange() else { return }
        apply(library.movingSwatch(id, to: index))
    }

    func nudgeSwatch(_ id: UUID, by offset: Int) {
        guard beginChange() else { return }
        apply(library.nudgingSwatch(id, by: offset))
    }

    func removeDuplicates(in paletteID: UUID) {
        guard beginChange() else { return }
        apply(library.removingDuplicates(in: paletteID))
    }

    // MARK: Recent picks

    func recordRecent(_ color: NookDesignColor) {
        guard beginChange() else { return }
        apply(library.recordingRecent(color))
    }

    func removeRecent(_ id: UUID) {
        guard beginChange() else { return }
        apply(library.removingRecent(id))
    }

    func clearRecents() {
        guard beginChange() else { return }
        apply(library.clearingRecents())
    }

    // MARK: Import

    /// Adds imported palettes. Returns how many were added.
    @discardableResult
    func importPalettes(_ imported: NookDesignImport, untitled: String) -> Int {
        guard beginChange() else { return 0 }
        let result = library.importing(imported, untitled: untitled)
        apply(result.library)
        return result.added
    }

    // MARK: Private

    private func apply(_ changed: NookDesignLibrary) {
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
            let wrote = NookDesignLibraryFile.write(snapshot, to: url)
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
