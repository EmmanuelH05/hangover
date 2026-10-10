import AppKit
import Foundation

/// The demo mode for one launch (D51): a model on an in-memory store whose
/// services hold sample content, the script to run and the backdrop picture.
/// Building it reads nothing of the user's and writes only into a temporary
/// folder.
@MainActor
final class DemoSession {
    /// A moment after launch before the first step is timed, which lets the
    /// island finish appearing.
    static let settle: TimeInterval = 1.5

    let model: AppModel
    /// The in-memory settings the whole model runs on.
    let defaults: DemoMemoryDefaults
    let player: DemoPlayer
    let calendarSource: DemoCalendarSource
    let pasteboard: DemoPasteboard
    /// Nil when the environment names no script, or one that does not exist.
    let script: DemoScript?
    let backdropPath: String?
    /// The demo's own folder under the temporary directory.
    let folder: URL

    private var backdrop: DemoBackdrop?

    /// Builds a session from the environment. The panel is put on screen
    /// unless `putsPanelOnScreen` is false, which only a test passes.
    init(
        environment: [String: String],
        now: Date = Date(),
        temporary: URL = FileManager.default.temporaryDirectory,
        putsPanelOnScreen: Bool = true,
        weatherTransport: any NookWeatherTransport = DemoWeatherTransport()
    ) {
        let script = environment[DemoMode.scriptKey].flatMap(DemoScripts.named)
        self.script = script
        backdropPath = environment[DemoMode.backdropKey]
        folder = temporary.appendingPathComponent("open-island-demo-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)

        // The store starts from the app's defaults and goes nowhere. The
        // agents are off and the weather city is the sample's.
        let defaults = DemoMemoryDefaults()
        AgentsSwitch.save(false, to: defaults)
        defaults.set(false, forKey: AppModel.showCodexUsageDefaultsKey)
        // A charger or a pair of headphones the Mac meets during a recording
        // brings no notice with a device name in it. The script shows the
        // charging notice itself.
        defaults.set(false, forKey: NookPowerMonitor.enabledKey)
        DemoWeather.seed(defaults, now: now)
        self.defaults = defaults

        let player = DemoPlayer(startsPlaying: script?.startsPlaying ?? true)
        self.player = player
        let calendarSource = DemoCalendarSource(now: now)
        self.calendarSource = calendarSource
        let pasteboard = DemoPasteboard()
        self.pasteboard = pasteboard

        let trayFolder = folder.appendingPathComponent("Tray", isDirectory: true)
        try? FileManager.default.createDirectory(at: trayFolder, withIntermediateDirectories: true)
        try? DemoTray.populate(folder: trayFolder, now: now)
        let notesURL = (try? DemoNotes.write(in: folder.appendingPathComponent("Notes", isDirectory: true), now: now))
            ?? folder.appendingPathComponent("Notes/\(NookNotesService.folderFileName)")

        let nook = NookModel(
            calendar: NookCalendarService(sample: calendarSource, defaults: defaults),
            reminders: NookRemindersService(defaults: defaults, sample: DemoTodo.items(now: now)),
            todo: NookTodoHub(
                defaults: defaults,
                notion: NookNotionTodoService(
                    defaults: defaults, tokenStore: DemoTokenStore(),
                    cache: NotionTodoCache(directory: folder.appendingPathComponent("NotionCache", isDirectory: true))
                ),
                tickTick: NookTickTickTodoService(
                    defaults: defaults, tokenStore: DemoTokenStore(),
                    cache: TickTickTodoCache(directory: folder.appendingPathComponent("TickTickCache", isDirectory: true))
                )
            ),
            media: MediaRemoteService(sample: player),
            notes: NookNotesService(defaults: defaults, appleNotes: DemoNotesWriter(), fileURL: notesURL),
            tray: NookTrayStore(
                folder: trayFolder,
                clipboard: NookClipboardMonitor(pasteboard: pasteboard, defaults: defaults),
                defaults: defaults
            ),
            weather: NookWeatherService(transport: weatherTransport, defaults: defaults),
            defaults: defaults,
            looksForImportedGIF: false,
            asksMacOSForAccess: false
        )
        // A meeting link opens nothing in the demo.
        nook.openURL = { _ in }

        model = AppModel(defaults: defaults, nookModel: nook)
        // A model on a store of its own keeps its panel off screen, which is
        // right for a test and wrong here.
        model.overlay.overlayPanelController.putsPanelOnScreen = putsPanelOnScreen
    }

    /// Puts the backdrop up, parks the pointer and runs the script. Called
    /// once, after the model has started.
    func begin(launchedAt: Date) {
        if let backdropPath, let screen = model.islandScreen ?? NSScreen.main {
            if let backdrop = DemoBackdrop(imagePath: backdropPath, screen: screen) {
                backdrop.show(below: model.overlay.overlayPanelController.windowNumber)
                self.backdrop = backdrop
            } else {
                print("DEMO the backdrop picture could not be read")
            }
        }
        if let screen = model.islandScreen ?? NSScreen.main {
            DemoPointer.park(on: screen)
        }
        guard let script else {
            print("DEMO no script to run")
            return
        }
        let doors = AppDemoDoors(model: model)
        var runner = DemoRunner()
        runner.quit = { [weak self] in
            self?.removeFiles()
            NSApp.terminate(nil)
        }
        Task { @MainActor [settle = Self.settle, runner] in
            try? await Task.sleep(for: .seconds(settle))
            await runner.run(script, doors: doors, launchedAt: launchedAt)
        }
    }

    /// Takes the sample files out of the temporary folder when the run ends.
    func removeFiles() {
        try? FileManager.default.removeItem(at: folder)
    }
}

enum DemoLaunch {
    /// A session when the environment asks for the demo mode, and nil
    /// otherwise. This is the one place the mode is switched on.
    @MainActor
    static func sessionIfRequested(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> DemoSession? {
        guard DemoMode.isRequested(environment: environment) else { return nil }
        DemoMode.activate()
        return DemoSession(environment: environment)
    }
}
