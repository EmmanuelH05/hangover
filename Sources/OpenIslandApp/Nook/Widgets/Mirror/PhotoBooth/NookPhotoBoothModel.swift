import AppKit
import Foundation
import Observation
import OSLog

/// A finished strip.
struct NookPhotoBoothResult: @unchecked Sendable {
    let fileURL: URL
    /// The strip drawn as a picture, for the screen.
    let preview: CGImage
    let pageSize: CGSize
    var isInTray = false
}

/// Why a session ended without a strip.
enum NookPhotoBoothFailure: Equatable, Sendable {
    /// The camera gave no picture.
    case camera
    /// The strip could not be drawn or written.
    case save

    var messageKey: String {
        switch self {
        case .camera: "nook.photoBooth.error.camera"
        case .save: "nook.photoBooth.error.save"
        }
    }
}

/// The sounds a session makes.
enum NookPhotoBoothSound: Sendable {
    case tick
    case lastTick
    case shutter
}

/// The photo booth in the mirror: its settings, the session that is
/// running, and the strip it made.
///
/// A picture is only ever taken by a session, a session only starts from
/// `start()`, and `start()` is only called by a press on the mirror: its
/// shutter button, Retake, or Try again. Nothing outside the app can reach
/// it: there is no link for it.
@MainActor
@Observable
final class NookPhotoBoothModel {
    nonisolated static let layoutKey = "nook.photoBooth.layout"
    nonisolated static let themeKey = "nook.photoBooth.theme"
    nonisolated static let captionKey = "nook.photoBooth.caption"
    nonisolated static let countdownKey = "nook.photoBooth.countdown"
    nonisolated static let soundKey = "nook.photoBooth.sound"
    nonisolated static let folderKey = "nook.photoBooth.folder"

    /// Pixels to the point for the strip shown on screen.
    private static let previewScale: CGFloat = 3
    private nonisolated static let log = Logger(subsystem: "app.openisland", category: "nook.photobooth")

    // MARK: Settings

    var layoutKind: NookPhotoStripLayout.Kind {
        didSet { if layoutKind != oldValue { defaults.set(layoutKind.rawValue, forKey: Self.layoutKey) } }
    }

    var themeID: String {
        didSet { if themeID != oldValue { defaults.set(themeID, forKey: Self.themeKey) } }
    }

    /// What the user wants printed under the pictures. Empty prints the
    /// theme's own line.
    var caption: String {
        didSet { if caption != oldValue { defaults.set(caption, forKey: Self.captionKey) } }
    }

    /// Seconds counted down before the first picture.
    var countdown: Int {
        didSet { if countdown != oldValue { defaults.set(countdown, forKey: Self.countdownKey) } }
    }

    var playsSound: Bool {
        didSet { if playsSound != oldValue { defaults.set(playsSound, forKey: Self.soundKey) } }
    }

    /// The folder strips are saved to, or nil for the default one.
    var folderPath: String? {
        didSet {
            guard folderPath != oldValue else { return }
            if let folderPath {
                defaults.set(folderPath, forKey: Self.folderKey)
            } else {
                defaults.removeObject(forKey: Self.folderKey)
            }
        }
    }

    var folderURL: URL {
        folderPath.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? defaultFolder
    }

    var theme: NookPhotoStripTheme { NookPhotoStripTheme.theme(id: themeID) }

    // MARK: What the mirror shows

    /// The session that is running or has just finished.
    private(set) var session: NookPhotoBoothSession?
    /// The pictures taken in this session, in order.
    private(set) var pictures: [NookPhotoBoothPicture] = []
    private(set) var result: NookPhotoBoothResult?
    private(set) var failure: NookPhotoBoothFailure?
    /// Goes up by one with every picture. The view flashes when it moves.
    private(set) var flashes = 0
    /// The layout the running session shoots for. Settings changed in the
    /// middle of a session wait for the next one.
    private(set) var sessionLayout: NookPhotoStripLayout?

    /// True while pictures are being counted down to, taken or printed.
    var isRunning: Bool { session != nil && result == nil }

    /// True while the booth has anything on the mirror.
    var isShowing: Bool { session != nil || result != nil || failure != nil }

    // MARK: Parts handed in

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let store: NookPhotoBoothStore
    @ObservationIgnored private let now: () -> Date
    /// Where pictures come from, where strips go when no folder is chosen,
    /// and whether the booth keeps its own time. Set at init. A test may
    /// swap them on a booth that a `NookModel` made.
    @ObservationIgnored var camera: any NookPhotoBoothCamera
    @ObservationIgnored var defaultFolder: URL
    @ObservationIgnored var advancesItself: Bool

    /// True while the mirror is on. The app's model answers this.
    @ObservationIgnored var isMirrorOn: () -> Bool = { false }
    /// What is on the mirror right now.
    @ObservationIgnored var decorations: () -> NookMirrorDecorationSet = { .none }
    @ObservationIgnored var play: (NookPhotoBoothSound) -> Void = { _ in }
    @ObservationIgnored var reveal: (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    @ObservationIgnored var captionLocale: () -> Locale = { .current }
    /// The line a theme prints when the user typed none.
    @ObservationIgnored var defaultCaption: (NookPhotoStripTheme) -> String = { LanguageManager.shared.t($0.defaultCaptionKey) }
    @ObservationIgnored private(set) weak var nook: NookModel?

    @ObservationIgnored private var sessionTheme: NookPhotoStripTheme?
    @ObservationIgnored private var sessionCaption = ""
    /// Goes up whenever a session starts or is thrown away. Work that
    /// comes back for an older number is dropped.
    @ObservationIgnored private var run = 0
    @ObservationIgnored private var driver: Task<Void, Never>?

    /// The app uses the defaults. A test hands in settings held in memory,
    /// a camera that takes no pictures, a folder of its own and a clock,
    /// and moves the session by calling `tick(at:)` itself.
    init(
        defaults: UserDefaults = .standard,
        camera: (any NookPhotoBoothCamera)? = nil,
        store: NookPhotoBoothStore = NookPhotoBoothStore(),
        defaultFolder: URL = NookPhotoBoothStore.defaultFolder(),
        now: @escaping () -> Date = Date.init,
        advancesItself: Bool = true
    ) {
        self.defaults = defaults
        self.camera = camera ?? NookMirrorStillCamera(controller: .shared)
        self.store = store
        self.defaultFolder = defaultFolder
        self.now = now
        self.advancesItself = advancesItself
        layoutKind = defaults.string(forKey: Self.layoutKey).flatMap(NookPhotoStripLayout.Kind.init(rawValue:))
            ?? NookPhotoStripLayout.defaultKind
        let savedTheme = defaults.string(forKey: Self.themeKey) ?? NookPhotoStripTheme.defaultID
        themeID = NookPhotoStripTheme.all.contains { $0.id == savedTheme } ? savedTheme : NookPhotoStripTheme.defaultID
        caption = defaults.string(forKey: Self.captionKey) ?? ""
        let savedCountdown = defaults.object(forKey: Self.countdownKey) as? Int ?? NookPhotoBoothPlan.defaultCountdown
        countdown = NookPhotoBoothPlan.countdownChoices.contains(savedCountdown) ? savedCountdown : NookPhotoBoothPlan.defaultCountdown
        playsSound = defaults.object(forKey: Self.soundKey) as? Bool ?? true
        folderPath = defaults.string(forKey: Self.folderKey)
    }

    /// Ties the booth to the app: the mirror's switch, its decorations and
    /// the island's sounds.
    func attach(nook: NookModel) {
        self.nook = nook
        isMirrorOn = { [weak nook] in nook?.isMirrorOn ?? false }
        decorations = { [weak nook] in nook?.mirrorDecorations ?? .none }
        play = { [weak nook] sound in
            guard let nook, !nook.isSoundMuted() else { return }
            NookPhotoBoothSounds.play(sound)
        }
        // Month and day names on the strip follow the app's language.
        captionLocale = { Locale(identifier: LanguageManager.shared.language.resolvedCode) }
    }

    // MARK: - A session

    /// True when the button may start a session: the mirror is showing the
    /// camera and the booth is idle.
    var canStart: Bool { !isShowing && isMirrorOn() && camera.isReady }

    /// Starts a session: the one way into the booth.
    func start() {
        guard canStart else { return }
        // The sticker picker and its handles go away for the session: a
        // drag must not move a sticker between two pictures of one strip.
        nook?.stopDecoratingMirror()
        run += 1
        let layout = NookPhotoStripLayout.layout(layoutKind)
        let theme = theme
        sessionLayout = layout
        sessionTheme = theme
        let typed = NookPhotoStripComposer.printedCaption(caption, theme: theme)
        sessionCaption = typed.isEmpty ? defaultCaption(theme) : caption
        pictures = []
        camera.prepare()
        session = NookPhotoBoothSession(
            plan: NookPhotoBoothPlan(shots: layout.shots, firstCountdown: countdown),
            at: now()
        )
        if advancesItself { startDriver() }
    }

    /// Throws away whatever the booth is doing or showing. A strip that
    /// was already saved stays saved.
    func cancel() {
        run += 1
        driver?.cancel()
        driver = nil
        session = nil
        sessionLayout = nil
        sessionTheme = nil
        pictures = []
        result = nil
        failure = nil
        unsavedStrip = nil
    }

    /// The strip that was drawn and could not be written. Kept until it is
    /// saved or put away, which lets "Save again" skip the posing.
    private(set) var unsavedStrip: NookPhotoStripInput?

    /// Draws and writes a strip off the main actor. Nil when it could not
    /// be drawn or written.
    private func write(_ input: NookPhotoStripInput) async -> NookPhotoBoothResult? {
        let store = store
        let folder = folderURL
        let scale = Self.previewScale
        return await Task.detached(priority: .userInitiated) { () -> NookPhotoBoothResult? in
            guard let pdf = NookPhotoStripComposer.pdf(input),
                  let preview = NookPhotoStripComposer.bitmap(input, scale: scale) else {
                return nil
            }
            do {
                let url = try store.save(pdf, into: folder, at: input.date)
                return NookPhotoBoothResult(fileURL: url, preview: preview, pageSize: input.layout.pageSize)
            } catch {
                Self.log.error("Could not save the strip: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }.value
    }

    /// Writes the strip that could not be saved once more, from the
    /// pictures already taken. A second failure leaves things as they are.
    func saveAgain() async {
        guard let input = unsavedStrip else { return }
        let token = run
        let outcome = await write(input)
        guard run == token else {
            if let outcome { store.discard(outcome.fileURL) }
            return
        }
        guard let outcome else { return }
        unsavedStrip = nil
        failure = nil
        result = outcome
    }

    /// Puts the strip on screen away.
    func finish() {
        cancel()
    }

    /// Bins the strip on screen and shoots again.
    func retake() {
        if let url = result?.fileURL {
            do {
                try store.moveToTrash(url)
            } catch {
                Self.log.error("Could not move the last strip to the Trash: \(error.localizedDescription, privacy: .public)")
            }
        }
        cancel()
        start()
    }

    /// Moves the session to where the clock says it is.
    func tick() async {
        await tick(at: now())
    }

    func tick(at time: Date) async {
        guard var current = session else { return }
        let effects = current.advance(to: time)
        session = current
        for effect in effects {
            await perform(effect)
        }
    }

    private func startDriver() {
        driver?.cancel()
        let token = run
        driver = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(40))
                guard let self, self.run == token, self.isRunning else { return }
                await self.tick()
            }
        }
    }

    private func perform(_ effect: NookPhotoBoothEffect) async {
        switch effect {
        case let .showNumber(number):
            sound(number == 1 ? .lastTick : .tick)
        case let .capture(shot):
            await capture(shot)
        case .compose:
            await compose()
        }
    }

    private func capture(_ shot: Int) async {
        let token = run
        flashes += 1
        sound(.shutter)
        do {
            let still = try await camera.captureStill()
            // The session may have been thrown away while the camera worked.
            guard run == token, session != nil, let layout = sessionLayout else { return }
            guard let picture = picture(from: still.image, aspect: layout.aspect(ofSlot: shot - 1)) else {
                return fail(.camera)
            }
            pictures.append(picture)
            session?.pictureArrived(at: now())
        } catch {
            guard run == token else { return }
            Self.log.error("No picture from the camera: \(String(describing: error), privacy: .public)")
            fail(.camera)
        }
    }

    /// A still made ready for its slot, with the mirror's decorations as
    /// they fall on that part of the picture.
    private func picture(from still: CGImage, aspect: CGFloat) -> NookPhotoBoothPicture? {
        guard let camera = NookPhotoBoothImaging.prepared(still, aspect: aspect) else { return nil }
        let kept = NookPhotoBoothImaging.keptFractions(imageWidth: still.width, imageHeight: still.height, aspect: aspect)
        let onPicture = NookPhotoBoothImaging.decorations(decorations(), keptX: kept.x, keptY: kept.y)
        let overlay = NookPhotoBoothImaging.decorationImage(onPicture, pixelWidth: camera.width, pixelHeight: camera.height)
        return NookPhotoBoothPicture(camera: camera, decorations: overlay)
    }

    private func compose() async {
        guard let layout = sessionLayout, let theme = sessionTheme else { return }
        let token = run
        let date = now()
        let input = NookPhotoStripInput(
            pictures: pictures,
            layout: layout,
            theme: theme,
            caption: sessionCaption,
            date: date,
            locale: captionLocale()
        )
        let outcome = await write(input)

        guard run == token, session != nil else {
            // Thrown away while it was printing. Nothing of it is kept.
            if let outcome { store.discard(outcome.fileURL) }
            return
        }
        guard let outcome else {
            // The pictures are kept: "Save again" writes the same strip,
            // and nobody has to pose a second time.
            fail(.save)
            unsavedStrip = input
            return
        }
        result = outcome
        session?.stripReady(at: now())
    }

    private func fail(_ reason: NookPhotoBoothFailure) {
        cancel()
        failure = reason
    }

    private func sound(_ sound: NookPhotoBoothSound) {
        guard playsSound else { return }
        play(sound)
    }

    // MARK: - The finished strip

    func revealInFinder() {
        guard let url = result?.fileURL else { return }
        reveal(url)
    }

    /// Opens the system share picker for the strip, hung off a view. False
    /// when it could not open.
    @discardableResult
    func share(from anchor: NSView?) -> Bool {
        guard let url = result?.fileURL, let tray = nook?.tray else { return false }
        return tray.share(fileAt: url, from: anchor)
    }

    /// Puts a copy of the strip in the file tray.
    func addToTray() {
        guard let url = result?.fileURL, result?.isInTray == false, let tray = nook?.tray else { return }
        if tray.add(fileAt: url) != nil {
            result?.isInTray = true
        }
    }

    // MARK: - Settings actions

    /// Asks for the folder strips are saved to.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = folderURL
        panel.message = LanguageManager.shared.t("nook.photoBooth.settings.folder.choose.message")
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            folderPath = url.path
        }
    }

    func useDefaultFolder() {
        folderPath = nil
    }

    func revealFolder() {
        let folder = folderURL
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        reveal(folder)
    }
}

/// Plays the booth's sounds from ones that ship with macOS. A sound that
/// is not on this Mac is skipped.
@MainActor
enum NookPhotoBoothSounds {
    /// The system's own camera shutter.
    static let shutterPath = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Shutter.aif"

    private static var shutter: NSSound? = FileManager.default.fileExists(atPath: shutterPath)
        ? NSSound(contentsOfFile: shutterPath, byReference: true)
        : nil

    static func play(_ sound: NookPhotoBoothSound) {
        switch sound {
        case .tick:
            NotificationSoundService.play("Tink")
        case .lastTick:
            NotificationSoundService.play("Pop")
        case .shutter:
            guard let shutter else { return }
            shutter.stop()
            shutter.play()
        }
    }
}
