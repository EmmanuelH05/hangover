import AppKit
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Which side of the design kit card shows.
enum NookDesignTab: String, CaseIterable, Identifiable, Sendable {
    case colors
    case links
    case references

    var id: String { rawValue }
    var titleKey: String { "nook.design.tab.\(rawValue)" }

    var symbol: String {
        switch self {
        case .colors: "paintpalette"
        case .links: "link"
        case .references: "photo.on.rectangle"
        }
    }
}

/// A line the card shows for a moment after an action.
struct NookDesignNotice: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case done
        /// Nothing went wrong, and nothing was done either.
        case info
        case error
    }

    let text: String
    let kind: Kind
    /// The color the line is about, drawn as a dot in front of it.
    var swatch: NookDesignColor?
}

/// What typing a color and pressing Add came to.
enum NookDesignEntryResult: Equatable, Sendable {
    case added(NookDesignSwatch)
    case duplicate(NookDesignSwatch)
    case notAColor
    case full
    /// The shelf has not been read yet.
    case unavailable
}

/// Shows the floating reference panels. The app passes the real one on a
/// real launch. Tests pass a fake, and a kit nobody handed one to opens
/// nothing.
@MainActor
protocol NookDesignReferencePresenting: AnyObject {
    /// Opens a panel for a picture in a cascade slot. `onClose` runs once
    /// when the panel goes away, whoever closed it.
    func present(_ reference: NookDesignReference, image: CGImage, slot: Int, onClose: @escaping @MainActor () -> Void)
    func focus(_ id: UUID)
    func close(_ id: UUID)
    func closeAll()
}

/// Shows the palette editor's panel.
@MainActor
protocol NookDesignEditorPresenting: AnyObject {
    func show(_ kit: NookDesignKit)
    func close()
}

/// The parts of the design kit that reach outside the app's own state:
/// the screen sampler, the windows, the clipboard, the hot key and the
/// opener of links. Only a real launch hands them over. A test, a harness run and a bare model
/// have none, which is what keeps them from opening a window, starting the
/// sampler or reading the clipboard.
@MainActor
struct NookDesignServices {
    var sampler: any NookDesignColorSampling
    var presenter: any NookDesignReferencePresenting
    var editor: any NookDesignEditorPresenting
    var pictureClipboard: any NookDesignPictureClipboard
    var hotkeyRegistrar: any NookDesignHotkeyRegistering
    var linkOpener: any NookDesignLinkOpening
}

/// The designer kit: a color shelf, a screen eyedropper, a shelf of links
/// and a shelf of reference pictures behind one Nook widget. It owns the
/// three stores, the eyedropper's shortcut and what the card shows, and it
/// is the one place that copies, picks, opens links and opens panels.
///
/// Nothing here talks to a server. Colors and pictures live in files under
/// the app's state folder (D45) and go nowhere else.
@MainActor
@Observable
final class NookDesignKit {
    nonisolated static let tabKey = "nook.design.tab"
    nonisolated static let formatKey = "nook.design.copyFormat"
    nonisolated static let savesPicksKey = "nook.design.eyedropper.savesToPalette"
    nonisolated static let keepsPickingKey = "nook.design.eyedropper.keepsPicking"
    /// The most colors one run of "Keep picking until Escape" takes. Escape
    /// is what ends a run. This is the guard for a loop Escape cannot break,
    /// such as a sampler that answers with a color every time and never
    /// shows its loupe.
    nonisolated static let maxPicksPerRun = 200

    let palettes: NookDesignPaletteStore
    let links: NookDesignLinkStore
    let references: NookDesignReferenceStore
    let hotkey: NookDesignHotkeyController

    var tab: NookDesignTab {
        didSet {
            guard tab != oldValue else { return }
            defaults.set(tab.rawValue, forKey: Self.tabKey)
            noteTabShown()
        }
    }

    /// The text a click on a swatch copies.
    var copyFormat: NookDesignColorFormat {
        didSet { if copyFormat != oldValue { defaults.set(copyFormat.rawValue, forKey: Self.formatKey) } }
    }

    /// Whether a picked color is also added to the active palette. Off to
    /// begin with: a pick always lands in the recent colors.
    var savesPicksToPalette: Bool {
        didSet { if savesPicksToPalette != oldValue { defaults.set(savesPicksToPalette, forKey: Self.savesPicksKey) } }
    }

    /// Whether the loupe comes back after every color, until Escape. Off to
    /// begin with, and off for settings saved before this one existed.
    var keepsPicking: Bool {
        didSet { if keepsPicking != oldValue { defaults.set(keepsPicking, forKey: Self.keepsPickingKey) } }
    }

    /// The last thing an action had to say, shown in the card for a moment.
    private(set) var notice: NookDesignNotice?
    /// The swatch or recent color last copied from, which shows a tick.
    private(set) var justCopiedID: UUID?
    /// The color the eyedropper picked last, this session.
    private(set) var lastPick: NookDesignColor?
    /// True while the system's loupe is up, and across the whole of a run of
    /// picks that keeps going: other parts of the app keep the island closed
    /// while this is true, and a gap between two picks would let it open.
    private(set) var isSampling = false
    /// The floating panels that are up, each with its cascade slot.
    private(set) var openPanels: [UUID: Int] = [:]
    /// The reference whose name is being typed in the card.
    var renamingReferenceID: UUID?
    /// True while pictures are dragged over the card.
    var isPictureDragOverCard = false
    /// What the Links tab is asking a name for, if anything.
    var linkNaming: NookDesignLinkNaming?
    /// The collection chip that is lit on the Links tab. Nil is All.
    var selectedLinkCollectionID: UUID?

    @ObservationIgnored private(set) weak var nook: NookModel?
    /// Puts text on the clipboard. A kit nobody wired copies nothing.
    @ObservationIgnored var copyText: ((String) -> Bool)?
    /// Runs before a pick that starts from the card. The app model closes
    /// the island there.
    @ObservationIgnored var willSampleFromIsland: () -> Void = {}
    /// Opens Settings on the Nook tab. The app model installs it. A kit
    /// nobody wired does nothing.
    @ObservationIgnored var openSettings: () -> Void = {}
    /// Runs when a name question opens. The app makes the island's panel the
    /// key window then, which a right click does not do.
    @ObservationIgnored var onNameQuestionOpened: () -> Void = {}

    @ObservationIgnored private var sampler: (any NookDesignColorSampling)?
    @ObservationIgnored private var presenter: (any NookDesignReferencePresenting)?
    @ObservationIgnored private var editor: (any NookDesignEditorPresenting)?
    @ObservationIgnored var pictureClipboard: (any NookDesignPictureClipboard)?
    @ObservationIgnored var linkOpener: (any NookDesignLinkOpening)?
    /// The clock for "last opened". A test swaps it.
    @ObservationIgnored var now: () -> Date = NookDesignFiles.now

    /// Whether the pick under way may be followed by another. Cleared when
    /// the widget is switched off, which a later switch on does not undo.
    @ObservationIgnored private var runMayContinue = false
    /// How many colors the run under way has taken.
    @ObservationIgnored private var picksInRun = 0
    /// The wait between two picks of a run, which is one turn of the main
    /// actor. Nil while the loupe is up or no run is under way.
    @ObservationIgnored private var nextPick: Task<Void, Never>?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private(set) var isLive = false
    /// The trouble already put on the card, by tab. Each is said once.
    @ObservationIgnored var reportedProblems: [NookDesignTab: NookDesignLoadProblem] = [:]
    /// How many times the island closed, for the tests of what that does.
    @ObservationIgnored var closeFlushCount = 0
    /// A line that waits for an error to go.
    @ObservationIgnored private var queuedNotice: NookDesignNotice?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var copiedTask: Task<Void, Never>?

    /// The app uses the defaults. Tests pass a temporary folder, settings
    /// held in memory and a `copyText` that records.
    init(folder: URL? = nil, defaults: UserDefaults = .standard, copyText: ((String) -> Bool)? = nil) {
        let base = folder ?? NookDesignFiles.defaultFolder
        palettes = NookDesignPaletteStore(folder: base)
        links = NookDesignLinkStore(folder: base)
        references = NookDesignReferenceStore(folder: base.appendingPathComponent("References", isDirectory: true))
        hotkey = NookDesignHotkeyController(defaults: defaults)
        self.defaults = defaults
        self.copyText = copyText
        tab = defaults.string(forKey: Self.tabKey).flatMap(NookDesignTab.init(rawValue:)) ?? .colors
        copyFormat = defaults.string(forKey: Self.formatKey).flatMap(NookDesignColorFormat.init(rawValue:)) ?? .hex
        savesPicksToPalette = defaults.bool(forKey: Self.savesPicksKey)
        keepsPicking = defaults.bool(forKey: Self.keepsPickingKey)
        palettes.onSaveFailed = { [weak self] in self?.post("nook.design.notice.saveFailed", .error) }
        links.onSaveFailed = { [weak self] in self?.post("nook.design.notice.saveFailed", .error) }
        palettes.onRefused = { [weak self] lock in self?.post(lock.noticeKey, .error) }
        links.onRefused = { [weak self] lock in self?.post(lock.noticeKey, .error) }
        references.onRefused = { [weak self] lock in self?.post(lock.noticeKey, .error) }
        references.onSaveFailed = { [weak self] in self?.post("nook.design.notice.saveFailed", .error) }
        hotkey.onPress = { [weak self] in self?.pickColor(from: .shortcut) }
    }

    /// A run that waits for its next pick asks the sampler for nothing more.
    isolated deinit {
        nextPick?.cancel()
    }

    // MARK: - Lifecycle

    func start(nook: NookModel) {
        self.nook = nook
        // Copies go through the tray's clipboard, which records its own
        // writes in the clipboard history without reading them back.
        if copyText == nil {
            copyText = { [weak nook] text in nook?.tray.clipboard.copy(text: text) ?? false }
        }
        setLive(nook.isWidgetEnabled(.design))
    }

    /// Hands over the services that reach outside the app. Called once,
    /// on a real launch.
    func activate(_ services: NookDesignServices) {
        sampler = services.sampler
        presenter = services.presenter
        editor = services.editor
        pictureClipboard = services.pictureClipboard
        linkOpener = services.linkOpener
        hotkey.activate(registrar: services.hotkeyRegistrar)
    }

    /// The widget's switch in the Nook tab moved. A model that was never
    /// started ignores it, which keeps a bare model in a test from reading
    /// the user's own files.
    func widgetSwitched(_ isOn: Bool) {
        guard nook != nil else { return }
        setLive(isOn)
    }

    /// Follows the widget's switch. While the widget is off nothing is
    /// read from disk, the shortcut is not held, and no panel stays up.
    func setLive(_ live: Bool) {
        guard live != isLive else { return }
        isLive = live
        hotkey.setLive(live)
        if live {
            Task { [weak self] in await self?.load() }
            // Switched on with keys that do not work: said at once, in the
            // card and on the closed island, and it stands in the card after.
            if let standing = standingNotice { postText(standing.text, .error) }
        } else {
            stopPicking()
            closeAllReferencePanels()
            editor?.close()
            renamingReferenceID = nil
            linkNaming = nil
        }
    }

    /// Reads every shelf. Safe to call more than once.
    func load() async {
        await palettes.load()
        await links.load()
        await references.load()
    }

    /// Waits until every change made up to now is on disk.
    func flush() async {
        await palettes.flush()
        await links.flush()
        await references.flush()
    }

    // MARK: - Copying

    /// Copies a color as text, in the chosen format unless one is named.
    /// `id` is the swatch or recent color that shows the tick.
    @discardableResult
    func copy(_ color: NookDesignColor, as format: NookDesignColorFormat? = nil, from id: UUID? = nil) -> Bool {
        let text = (format ?? copyFormat).text(for: color)
        guard copyText?(text) == true else {
            post("nook.design.notice.copyFailed", .error)
            return false
        }
        post("nook.design.notice.copied", .done, swatch: color, text)
        flash(id)
        return true
    }

    // MARK: - Colors

    /// Adds a typed color to a palette, or to the active one.
    @discardableResult
    func addColor(text: String, name: String = "", to paletteID: UUID? = nil) -> NookDesignEntryResult {
        guard let color = NookDesignColorParser.parse(text) else {
            post("nook.design.notice.notAColor", .info)
            return .notAColor
        }
        return addColor(color, name: name, to: paletteID)
    }

    @discardableResult
    func addColor(_ color: NookDesignColor, name: String = "", to paletteID: UUID? = nil) -> NookDesignEntryResult {
        guard palettes.isLoaded else { return .unavailable }
        let outcome = palettes.addColor(
            color,
            named: name,
            to: paletteID,
            defaultPaletteName: LanguageManager.shared.t("nook.design.palette.default")
        )
        switch outcome {
        case let .added(_, swatch):
            sayAfterWrite { $0.post("nook.design.notice.added", .done, swatch: color, color.hex()) }
            return .added(swatch)
        case let .duplicate(existing):
            post("nook.design.notice.duplicate", .info, swatch: color)
            return .duplicate(existing)
        case .full:
            post("nook.design.notice.paletteFull", .error)
            return .full
        case .noPalette:
            return .unavailable
        }
    }

    // MARK: - Eyedropper

    /// Starts a pick with the system's loupe. A pick already under way is
    /// left alone, and a kit with no sampler does nothing. With
    /// `keepsPicking` on this starts a run: the loupe comes back after each
    /// color until Escape, and `isSampling` stays true all the while.
    @discardableResult
    func pickColor(from source: NookDesignPickSource) -> Bool {
        guard isLive, let sampler, !isSampling else { return false }
        isSampling = true
        runMayContinue = true
        picksInRun = 0
        // Once, at the start. The island is not reopened between picks.
        if source == .island { willSampleFromIsland() }
        ask(sampler)
        return true
    }

    private func ask(_ sampler: any NookDesignColorSampling) {
        sampler.sample { [weak self] result in self?.finishPick(result) }
    }

    /// What a pick came to. A cancel changes nothing: not the clipboard, not
    /// the recent colors, not the palette. It is also how a run ends.
    func finishPick(_ result: NookDesignPickResult) {
        let wasAnswered = result != .cancelled
        if wasAnswered { picksInRun += 1 }
        let goesOn = wasAnswered && runMayContinue && keepsPicking && isLive
            && picksInRun < Self.maxPicksPerRun
        if goesOn {
            // No gap: `isSampling` is never false between two picks.
            resumeAfterTurn()
        } else {
            runMayContinue = false
            isSampling = false
        }
        record(result)
    }

    /// Asks for the next pick on the next turn of the main actor, not from
    /// inside the completion of the one before, which the system's sampler
    /// may not like. `isSampling` is true across that turn.
    private func resumeAfterTurn() {
        nextPick = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            nextPick = nil
            guard runMayContinue, isLive, let sampler else {
                runMayContinue = false
                isSampling = false
                return
            }
            ask(sampler)
        }
    }

    /// Ends the run under way, because the widget was switched off. A loupe
    /// that is up stays up, because the system owns it: its answer is kept
    /// as any pick is, and no new loupe follows. Between two picks there is
    /// no loupe, and `isSampling` goes false at once.
    private func stopPicking() {
        runMayContinue = false
        guard let waiting = nextPick else { return }
        waiting.cancel()
        nextPick = nil
        isSampling = false
    }

    /// Keeps what a pick came to: the recent colors, the palette when
    /// that switch is on, the copy and the notice.
    private func record(_ result: NookDesignPickResult) {
        let picked: NookDesignColor
        switch result {
        case .cancelled:
            return
        case .unreadable:
            // A color with no RGB form is not a cancel, and the island tells the user.
            post("nook.design.notice.pickUnreadable", .error)
            return
        case let .picked(color):
            picked = color
        }
        // The screen has no see-through pixels.
        let color = NookDesignColor(red: picked.red, green: picked.green, blue: picked.blue)
        lastPick = color
        palettes.recordRecent(color)

        var saved: NookDesignAddOutcome?
        if savesPicksToPalette {
            saved = palettes.addColor(
                color,
                defaultPaletteName: LanguageManager.shared.t("nook.design.palette.default")
            )
        }

        let text = copyFormat.text(for: color)
        let copied = copyText?(text) == true
        let key: String
        if !copied {
            key = "nook.design.notice.picked.notCopied"
        } else if case .added = saved {
            key = "nook.design.notice.picked.saved"
        } else if case .duplicate = saved {
            key = "nook.design.notice.picked.known"
        } else if case .full = saved {
            // The pick was copied, and the palette had no room for it. Without
            // this line the card would read as if it had been saved.
            key = "nook.design.notice.picked.full"
        } else {
            key = "nook.design.notice.picked"
        }
        post(key, copied ? .done : .error, swatch: color, quietly: true, text)
        if copied, let recent = palettes.recents.first { flash(recent.id) }

        // The island is closed while the loupe is up. The closed pill is
        // where the pick shows. A pick that was not copied, or that the full
        // palette could not keep, shows a warning in words and not the color
        // of a good pick.
        if !copied {
            showPillWarning("nook.design.pill.notCopied")
        } else if case .full = saved {
            showPillWarning("nook.design.pill.paletteFull")
        } else {
            nook?.showTransient(
                symbol: "eyedropper.halffull",
                text: Self.noticeText(for: color, copied: text),
                tint: color.noticeTint.color,
                duration: .seconds(4)
            )
        }
    }

    private func showPillWarning(_ key: String) {
        nook?.showTransient(
            symbol: "exclamationmark.triangle",
            text: LanguageManager.shared.t(key),
            tint: .orange,
            duration: .seconds(4)
        )
    }

    /// The value the closed island shows after a pick: what was copied
    /// when that fits its narrow wing, and the HEX form when it does not.
    nonisolated static func noticeText(for color: NookDesignColor, copied: String) -> String {
        copied.count <= 18 ? copied : color.hex()
    }

    // MARK: - References

    // Adding pictures is in `NookDesignKit+References.swift`.

    /// Takes a picture off the shelf, closes its panel and deletes its
    /// files.
    @discardableResult
    func removeReference(_ id: UUID) -> Task<Void, Never> {
        closeReferencePanel(id)
        if renamingReferenceID == id { renamingReferenceID = nil }
        return references.remove(id)
    }

    @discardableResult
    func clearReferences() -> Task<Void, Never> {
        closeAllReferencePanels()
        renamingReferenceID = nil
        return references.clear()
    }

    // MARK: - Floating panels

    /// A click on a reference: brings its panel forward when it has one,
    /// opens one when there is room, and says why when there is not.
    @discardableResult
    func openReference(_ id: UUID) -> Task<Void, Never>? {
        guard isLive, let item = references.item(id), let presenter else { return nil }
        switch NookDesignPanelRules.decision(for: id, open: openPanels) {
        case .focus:
            presenter.focus(id)
            return nil
        case .refuse:
            post("nook.design.notice.panelCap", .info, NookDesignPanelRules.maxOpenPanels)
            return nil
        case let .open(slot):
            // The slot is taken now, which keeps a second click from
            // opening the same picture twice while it is being read.
            openPanels[id] = slot
            let url = references.fileURL(for: item)
            return Task { [weak self] in
                let image = await Task.detached(priority: .userInitiated) {
                    NookDesignPictures.image(fileAt: url, maxPixel: NookDesignReferenceRules.displayMaxPixel)
                }.value
                guard let self, self.openPanels[id] == slot else { return }
                guard let image, let current = self.references.item(id), let presenter = self.presenter else {
                    self.openPanels[id] = nil
                    self.post("nook.design.notice.pictureMissing", .error)
                    return
                }
                presenter.present(current, image: image, slot: slot) { [weak self] in
                    self?.openPanels[id] = nil
                }
            }
        }
    }

    func closeReferencePanel(_ id: UUID) {
        guard openPanels[id] != nil else { return }
        openPanels[id] = nil
        presenter?.close(id)
    }

    func closeAllReferencePanels() {
        guard !openPanels.isEmpty else { return }
        openPanels = [:]
        presenter?.closeAll()
    }

    // MARK: - Palette editor

    func showPaletteEditor() {
        guard isLive else { return }
        editor?.show(self)
    }

    /// Reads a palette file and adds what it holds. The file is read and
    /// parsed off the main actor.
    @discardableResult
    func importPalettes(fromFileAt url: URL) -> Task<Void, Never> {
        Task { [weak self] in
            let read = await Task.detached(priority: .userInitiated) { () -> Result<NookDesignImport, NookDesignImportError> in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                guard size <= NookDesignPaletteExchange.maxFileBytes else { return .failure(.tooLarge) }
                guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable) }
                do throws(NookDesignImportError) {
                    return .success(try NookDesignPaletteExchange.read(data))
                } catch {
                    return .failure(error)
                }
            }.value
            self?.finishImport(read)
        }
    }

    func finishImport(_ read: Result<NookDesignImport, NookDesignImportError>) {
        switch read {
        case let .success(imported):
            let before = palettes.colorCount
            let added = palettes.importPalettes(
                imported,
                untitled: LanguageManager.shared.t("nook.design.palette.untitled")
            )
            guard added > 0 else { return post("nook.design.notice.importFull", .error) }
            let colors = palettes.colorCount - before
            // Everything that did not go in is counted, the palettes the
            // library had no room for included.
            let leftOut = imported.skippedColors + imported.duplicateColors + imported.skippedPalettes
                + (imported.palettes.count - added)
            if leftOut > 0 {
                // Something was left out, which is news for the closed island too.
                sayAfterWrite { $0.post("nook.design.notice.imported.leftOut", .error, added, colors, leftOut) }
            } else {
                sayAfterWrite { $0.post("nook.design.notice.imported", .done, added, colors) }
            }
        case .failure(.tooLarge): post("nook.design.notice.importTooLarge", .error)
        case .failure(.unreadable): post("nook.design.notice.importUnreadable", .error)
        case .failure(.notJSON): post("nook.design.notice.importNotJSON", .error)
        case .failure(.noColors): post("nook.design.notice.importNoColors", .error)
        }
    }

    /// Writes palettes to a file in the exchange format, off the main
    /// actor.
    @discardableResult
    func exportPalettes(_ ids: [UUID], to url: URL) -> Task<Void, Never> {
        let chosen = palettes.library.palettes.filter { ids.contains($0.id) }
        // Nothing to write is a failure, not an export of an empty file.
        guard !chosen.isEmpty else {
            post("nook.design.notice.exportNothing", .error)
            return Task {}
        }
        return Task { [weak self] in
            // The reason, as the system words it, comes back with the failure.
            let failure = await Task.detached(priority: .userInitiated) { () -> String? in
                do {
                    let data = try NookDesignPaletteExchange.export(chosen)
                    try data.write(to: url, options: .atomic)
                    return nil
                } catch {
                    return (error as NSError).localizedFailureReason ?? error.localizedDescription
                }
            }.value
            if let failure {
                self?.post("nook.design.notice.exportWriteFailed", .error, failure)
            } else {
                self?.post("nook.design.notice.exported", .done)
            }
        }
    }

    // MARK: - Notices

    /// Says a success once everything written until now is on disk. A write
    /// that failed has reported itself, and nothing is said in its place.
    func sayAfterWrite(_ say: @escaping @MainActor (NookDesignKit) -> Void) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.flush()
            guard !self.palettes.lastSaveFailed, !self.links.lastSaveFailed else { return }
            say(self)
        }
    }

    /// Shows a line in the card for a moment. An error also goes to the
    /// closed island, because the island may be closed when the work is
    /// done. `quietly` keeps it in the card alone.
    func post(
        _ key: String,
        _ kind: NookDesignNotice.Kind,
        swatch: NookDesignColor? = nil,
        quietly: Bool = false,
        _ arguments: any CVarArg...
    ) {
        let format = LanguageManager.shared.t(key)
        let text = arguments.isEmpty ? format : String(format: format, arguments: arguments)
        postText(text, kind, swatch: swatch, quietly: quietly)
    }

    /// Shows a line in the card for a moment. Bad news is not hidden by
    /// good: while an error shows, a line that is not an error waits for it
    /// to go, and only the newest waits. An error replaces another error.
    func postText(_ text: String, _ kind: NookDesignNotice.Kind, swatch: NookDesignColor? = nil, quietly: Bool = false) {
        let new = NookDesignNotice(text: text, kind: kind, swatch: swatch)
        if notice?.kind == .error, kind != .error {
            queuedNotice = new
        } else {
            queuedNotice = nil
            show(new)
        }
        if kind == .error, !quietly {
            nook?.showTransient(symbol: "exclamationmark.triangle", text: text, tint: .orange)
        }
    }

    private func show(_ new: NookDesignNotice) {
        notice = new
        noticeTask?.cancel()
        noticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self else { return }
            if let next = self.queuedNotice {
                self.queuedNotice = nil
                self.show(next)
            } else {
                self.notice = nil
            }
        }
    }

    func flash(_ id: UUID?) {
        justCopiedID = id
        copiedTask?.cancel()
        guard id != nil else { return }
        copiedTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.justCopiedID = nil
        }
    }
}
