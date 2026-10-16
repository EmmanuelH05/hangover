import AppKit
import SwiftUI

@MainActor
final class OpenIslandAppDelegate: NSObject, NSApplicationDelegate {
    /// Set only when the environment asks for the demo mode (D51).
    private let demo = DemoLaunch.sessionIfRequested()
    let model: AppModel
    private let harnessLaunchConfiguration = HarnessLaunchConfiguration()
    private let launchedAt = Date()
    private lazy var harnessRuntimeMonitor = HarnessRuntimeMonitor(launchedAt: launchedAt)
    private let focusKeeper = IslandFocusKeeper()
    /// Links that arrived before the model was up, the one that launched
    /// the app among them.
    private var pendingLinks: [URL] = []
    private var isReadyForLinks = false

    override init() {
        model = demo?.model ?? AppModel()
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // `hangover://` links from other apps arrive as an Apple event.
        // Taking the event here keeps a link from summoning the Settings
        // window.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        focusKeeper.start()
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue
        guard let url = text.flatMap(URL.init(string:)) else {
            // Nothing to act on. The event still brought the app forward,
            // and the keyboard goes back as it does for any ignored link.
            model.noteUnreadableLink(text)
            focusKeeper.giveBack()
            return
        }
        receive([url])
    }

    /// The same links, should the system hand them over this way instead.
    func application(_ application: NSApplication, open urls: [URL]) {
        receive(urls)
    }

    private func receive(_ links: [URL]) {
        guard isReadyForLinks else {
            pendingLinks += links
            return
        }
        for link in links {
            // An action that shows the island keeps the keyboard. Anything
            // else, an ignored link included, gives it back.
            if model.handleIncomingURL(link)?.opensIsland != true {
                focusKeeper.giveBack()
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination(
            "\(AppBrand.name) should remain active while monitoring local agent sessions."
        )
        ProcessInfo.processInfo.disableSuddenTermination()
        NSApp.setActivationPolicy(model.showDockIcon ? .regular : .accessory)
        harnessRuntimeMonitor.recordMilestone("applicationDidFinishLaunching")

        DispatchQueue.main.async { [self] in
            harnessRuntimeMonitor.recordMilestone("bootstrapStarted")
            model.harnessRuntimeMonitor = harnessRuntimeMonitor
            harnessRuntimeMonitor.recordLog(model.lastActionMessage)

            model.ignoresPointerExitDuringHarness = harnessLaunchConfiguration.scenario != nil
            model.disablesOverlayEventMonitoringDuringHarness =
                harnessLaunchConfiguration.disablesOverlayEventMonitoring
            // The demo mode starts no bridge, discovers no sessions and
            // checks for no update (D51).
            model.startIfNeeded(
                startBridge: demo == nil && harnessLaunchConfiguration.shouldStartBridge,
                shouldPerformBootAnimation: harnessLaunchConfiguration.shouldPerformBootAnimation,
                loadRuntimeState: demo == nil && harnessLaunchConfiguration.scenario == nil
            )
            harnessRuntimeMonitor.recordMilestone("modelStarted")

            // Global shortcuts belong to a real launch, not a harness run.
            // The model holds them back while the agents are switched off.
            if demo == nil, harnessLaunchConfiguration.scenario == nil {
                model.activateAgentHotkeys(registrar: CarbonHotkeyRegistrar())
                // Listening to the Mac's sound belongs to a real launch too
                // (D56). Nothing listens until the user switches it on.
                model.beat.activate(makeListener: IslandBeatSupport.makeListener)
                // The same goes for the design kit's sampler, panels,
                // clipboard reads and shortcut.
                model.nook.design.activate(.system())
                // Record's shortcut, its face cam bubble and its area overlay
                // are a real launch's too. The shortcut is held only while the
                // widget is on.
                model.nook.record.activate(.system(screen: { [model] in model.islandScreen }))
                // The new note shortcut works from any app, with or without
                // the Notes widget on the page.
                model.nook.notes.hotkey.activate(registrar: NookNoteCarbonHotkey())
            }

            if let scenario = harnessLaunchConfiguration.scenario {
                model.loadDebugSnapshot(
                    scenario.snapshot(),
                    presentOverlay: harnessLaunchConfiguration.presentOverlay
                )
            }

            // Hide all windows on launch — settings opens on demand only.
            OpenIslandAppDelegate.hideAllAppWindows()
            demo?.begin(launchedAt: launchedAt)

            harnessRuntimeMonitor.recordMilestone("bootstrapCompleted")

            isReadyForLinks = true
            let waiting = pendingLinks
            pendingLinks = []
            receive(waiting)

            if let captureDelay = harnessLaunchConfiguration.captureDelay,
               harnessLaunchConfiguration.artifactDirectoryURL != nil {
                harnessRuntimeMonitor.recordMilestone(
                    "captureScheduled",
                    message: String(format: "%.3fs", captureDelay)
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + captureDelay) { [self] in
                    harnessRuntimeMonitor.recordMilestone("captureStarted")
                    try? HarnessArtifactRecorder.record(
                        configuration: harnessLaunchConfiguration,
                        model: model,
                        launchedAt: launchedAt,
                        runtimeMonitor: harnessRuntimeMonitor
                    )
                }
            }

            if let autoExitAfter = harnessLaunchConfiguration.autoExitAfter {
                harnessRuntimeMonitor.recordMilestone(
                    "autoExitScheduled",
                    message: String(format: "%.3fs", autoExitAfter)
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + autoExitAfter) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    /// A change to the designer kit's colors, links or pictures made just
    /// before a quit is still being written, and a recording that is under
    /// way is still an open file (D67). The quit waits for both, each with a
    /// limit that really holds (`NookQuitWait`), which keeps a stuck disk or a
    /// stalled capture from stopping a quit or an update. A recording gets
    /// longer than the writes: its file has to be closed. A note typed a moment
    /// ago is saved first, which queues its send to Apple Notes, and the sends
    /// in line get the same short limit as the writes. One given up on is in the
    /// backlog, and the next launch makes it.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let needsDesignWrites = model.designKitQuitDecision == .afterWrites
        let isRecording = model.nook.record.phase.isBusy
        let needsNotesSends = model.prepareNotesForQuit()
        guard needsDesignWrites || isRecording || needsNotesSends else { return .terminateNow }
        Task { @MainActor [model] in
            var jobs: [NookQuitJob] = []
            if needsNotesSends {
                jobs.append(NookQuitJob(name: "Apple Notes sends", limit: NookQuitWait.writesLimit) {
                    await model.flushNotesBeforeQuit()
                })
            }
            if needsDesignWrites {
                jobs.append(NookQuitJob(name: "design kit writes", limit: NookQuitWait.writesLimit) {
                    await model.flushDesignKitBeforeQuit()
                })
            }
            if isRecording {
                jobs.append(NookQuitJob(name: "recording", limit: NookQuitWait.recordingLimit) {
                    await model.nook.record.prepareForQuit()
                })
            }
            _ = await NookQuitWait.run(jobs)
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private static func hideAllAppWindows() {
        for window in NSApp.windows {
            window.orderOut(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.showSettings()
        return false
    }
}

@main
struct OpenIslandApp: App {
    @NSApplicationDelegateAdaptor(OpenIslandAppDelegate.self)
    private var appDelegate

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window(AppBrand.settingsWindowTitle, id: "settings") {
            SettingsWindowContent(model: appDelegate.model)
        }
        .windowResizability(.contentMinSize)
        // A link from another app is an action for the island, never a
        // reason to bring up Settings.
        .handlesExternalEvents(matching: [])
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    openWindow(id: "settings")
                    appDelegate.model.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

/// Refreshes the `openWindow` registration each time the settings
/// window opens, keeping the closure current after window recreation.
private struct SettingsWindowContent: View {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SettingsView(model: model)
            .onAppear {
                model.openSettingsWindow = { [openWindow] in
                    openWindow(id: "settings")
                }
            }
    }
}
