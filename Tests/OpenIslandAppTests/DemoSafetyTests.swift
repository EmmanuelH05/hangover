import Foundation
import Testing
@testable import OpenIslandApp

// Demo mode touches nothing real (D51): the settings are in memory, nothing
// can raise a macOS prompt, the pasteboard and the Keychain are stand-ins,
// and the weather goes nowhere. The doors that could reach the outside are
// the sample's own; no test here asks EventKit, the network or the real
// clipboard for anything.

@MainActor
struct DemoSafetyTests {
    @Test func theSettingsStoreIsTheOneInMemoryAndTakesTheWrites() {
        let fixture = DemoFixture()
        defer { fixture.remove() }
        let defaults = fixture.session.defaults

        // The app's own defaults are in it, and the agents are off.
        #expect(defaults.object(forKey: AgentsSwitch.defaultsKey) as? Bool == false)
        #expect(!fixture.model.agentsEnabled)
        #expect(defaults.object(forKey: "app.showDockIcon") as? Bool == true)
        #expect(defaults.object(forKey: NookPowerMonitor.enabledKey) as? Bool == false, "no device name from a real headphone notice")

        fixture.nook.setWidget(.tray, enabled: false)
        fixture.nook.isRingLightOn = true
        #expect(defaults.all["nook.enabledWidgets"] != nil, "the write landed in the demo's store")
        #expect(defaults.object(forKey: "nook.mirror.ringLight") as? Bool == true)

        // Nothing it holds is saved anywhere: it has no domain of its own.
        defaults.removePersistentDomain(forName: "anything")
        #expect(defaults.all.isEmpty)
    }

    @Test func noPromptCanBeRaisedBecauseNothingMayAskMacOS() async {
        let fixture = DemoFixture(now: Date())
        defer { fixture.remove() }
        fixture.startSampleServices()
        let nook = fixture.nook

        #expect(nook.allowsAccessRequests == false)
        #expect(await nook.askForAccess(for: .calendar, at: .requested).isEmpty)
        #expect(await nook.askForAccess(for: .todo, at: .shown).isEmpty)
        #expect(nook.widgetTurnedOn(.calendar) == nil)
        #expect(nook.widgetsCameIntoView() == nil)
        // The two services believe they have access and ask for none.
        #expect(await nook.calendar.requestAccessIfUndecided() == false)
        #expect(await nook.reminders.requestAccessIfUndecided() == false)
        nook.calendar.requestAccess()
        nook.reminders.requestAccess()
        #expect(nook.calendar.authorization == .fullAccess)
        #expect(nook.reminders.authorization == .fullAccess)
    }

    @Test func theClipboardIsAStandInAndTheRealOneIsNeverWritten() {
        let fixture = DemoFixture()
        defer { fixture.remove() }
        fixture.startSampleServices()
        #expect(fixture.session.pasteboard.changeCount == 0)

        // The tour's copy button and the tray's "copy path" both end here.
        let copied = fixture.nook.tray.clipboard.copy(text: "a sentence")

        #expect(copied)
        #expect(fixture.session.pasteboard.changeCount == 1, "the write went to the stand-in")
        #expect(fixture.session.pasteboard.read() == nil)
        #expect(fixture.nook.tray.clipboard.history.entries.isEmpty, "the list is off")
    }

    @Test func noTokenIsReadFromOrWrittenToTheKeychain() throws {
        let fixture = DemoFixture()
        defer { fixture.remove() }
        fixture.startSampleServices()
        let store = DemoTokenStore()

        #expect(try store.read() == nil)
        try store.save("secret")
        #expect(try store.read() == nil, "it holds nothing")
        try store.delete()
        #expect(!fixture.nook.todo.notion.hasToken)
        #expect(!fixture.nook.todo.tickTick.hasToken)
        #expect(fixture.nook.todo.selectedKind == .reminders)
    }

    @Test func theMusicWidgetSendsNothingToThePlayerOnTheMac() {
        let fixture = DemoFixture()
        defer { fixture.remove() }
        fixture.startSampleServices()
        let media = fixture.nook.media

        media.togglePlayPause()
        media.nextTrack()
        media.previousTrack()
        media.seek(to: 12)

        #expect(media.state?.bundleIdentifier == DemoPlayer.bundleIdentifier)
        #expect(media.lastError == nil, "no adapter was looked for")
    }

    @Test func theLinkOfTheJoinEventIsOneNoMeetingServiceOwnsAndOpensNothing() throws {
        let link = try #require(DemoCalendarSource.meetingURL)
        #expect(NookMeetingLink.safeURL(from: link) == nil, "the Join button refuses it")
        #expect(link.host == "meet.example.com")
    }

    @Test func theWeatherServiceCannotReachTheNetwork() async {
        let transport = DemoWeatherTransport()
        do {
            _ = try await transport.get(URL(string: "https://example.invalid/forecast")!)
            Issue.record("the transport answered")
        } catch {
            #expect(error as? NookWeatherError == .offline)
        }
    }

    @Test func theSessionKeepsItsFilesInATemporaryFolderOfItsOwn() throws {
        let fixture = DemoFixture()
        defer { fixture.remove() }
        fixture.startSampleServices()

        #expect(fixture.session.folder.path.hasPrefix(fixture.root.path))
        #expect(fixture.nook.notes.fileURL.path.hasPrefix(fixture.root.path))
        #expect(fixture.nook.tray.folderURL.path.hasPrefix(fixture.root.path))
        #expect(!fixture.root.path.contains("Application Support"))
        #expect(!fixture.root.path.contains("/Library/"))
    }

    @Test func thePanelIsOnScreenInTheModeWhateverStoreItRunsOn() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hangover-demo-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        // A model on a store of its own keeps the panel off screen. The
        // session turns it back on, and no panel is made until the app starts.
        let plain = AppModel(defaults: MemoryDefaults())
        #expect(plain.overlay.overlayPanelController.putsPanelOnScreen == false)

        let session = DemoSession(environment: DemoFixture.environment, temporary: root)
        defer { session.model.nook.timer.reset() }

        #expect(session.model.overlay.overlayPanelController.putsPanelOnScreen == true)
        #expect(session.model.overlay.overlayPanelController.windowFrame == nil)
        session.model.overlay.overlayPanelController.putsPanelOnScreen = false
    }

    @Test func theTourDoesNotOpenByItselfInTheMode() {
        let fixture = DemoFixture()
        defer { fixture.remove() }
        // The gate keeps any launch with an OPEN_ISLAND_ switch away from
        // the tour, and the demo's launch starts none of the runtime that
        // offers it.
        let facts = fixture.model.welcomeTourFacts(environment: DemoFixture.environment)
        #expect(facts.isHarness)
        #expect(!OnboardingGate.showsByItself(facts))
    }

    @Test func theBackdropCornerAndLevelsArePlainValues() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        #expect(DemoPointer.parkPoint(screenFrame: screen, mainDisplayHeight: 982) == CGPoint(x: 1506, y: 976))
        // A screen to the right of the main display, lower than it.
        let side = CGRect(x: 1512, y: -400, width: 1920, height: 1080)
        #expect(DemoPointer.parkPoint(screenFrame: side, mainDisplayHeight: 982) == CGPoint(x: 3426, y: 1376))
        #expect(DemoWindowLevels.island == .statusBar)
    }
}
