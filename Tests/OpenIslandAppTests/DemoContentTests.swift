import AppKit
import Foundation
import Testing
@testable import OpenIslandApp

// The demo mode's sample content (D51): each source gives what it should,
// events are placed from a moment the test hands in, and the music's bar
// moves with a clock the test holds.

@MainActor
struct DemoOffTests {
    @Test func theVariableAloneSwitchesTheModeOn() {
        #expect(DemoMode.isRequested(environment: ["OPEN_ISLAND_DEMO": "1"]))
        #expect(!DemoMode.isRequested(environment: [:]))
        #expect(!DemoMode.isRequested(environment: ["OPEN_ISLAND_DEMO": "0"]))
        #expect(!DemoMode.isRequested(environment: ["OPEN_ISLAND_DEMO": "true"]))
        // The backdrop and the script do nothing by themselves.
        #expect(!DemoMode.isRequested(environment: [
            "OPEN_ISLAND_DEMO_BACKDROP": "/tmp/x.jpg", "OPEN_ISLAND_DEMO_SCRIPT": "tour",
        ]))
    }

    @Test func withoutTheVariableThereIsNoSession() {
        #expect(DemoLaunch.sessionIfRequested(environment: [:]) == nil)
        #expect(DemoLaunch.sessionIfRequested(environment: ["OPEN_ISLAND_DEMO_SCRIPT": "tour"]) == nil)
        #expect(!DemoMode.isActive)
    }

    @Test func aModelBuiltTheNormalWayHasNoDemoContent() {
        let model = AppModel(defaults: MemoryDefaults())

        #expect(model.nook.calendar.events.isEmpty)
        #expect(model.nook.media.state == nil)
        #expect(model.nook.reminders.items.isEmpty)
        #expect(model.nook.weather.place == nil)
        #expect(model.nook.tray.items.isEmpty)
        #expect(model.nook.notes.entries.isEmpty)
        // Its panel stays off screen, as it always did for a store of its own.
        #expect(!DemoMode.isActive)
    }

    @Test func windowsKeepTheirLevelOutsideTheMode() {
        let normal = NSWindow.Level.normal
        #expect(DemoWindowLevels.level(forWindowAt: normal, isDemo: false) == normal)
        #expect(DemoWindowLevels.level(forWindowAt: normal, isDemo: true) == DemoWindowLevels.raised)
        #expect(DemoWindowLevels.raised.rawValue == DemoWindowLevels.island.rawValue + 1)
        // Nothing in a test turns the mode on, which leaves the live switch off.
        #expect(DemoMode.raised(normal) == normal)
    }

    @Test func theBackdropAndTheScriptAreReadFromTheEnvironmentOnly() {
        let bare = DemoFixture()
        defer { bare.remove() }
        #expect(bare.session.backdropPath == nil)
        #expect(bare.session.script == nil)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hangover-demo-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let driven = DemoSession(
            environment: [
                "OPEN_ISLAND_DEMO": "1", "OPEN_ISLAND_DEMO_BACKDROP": "/tmp/painting.jpg",
                "OPEN_ISLAND_DEMO_SCRIPT": "looks",
            ],
            now: DemoFixture.now, temporary: root, putsPanelOnScreen: false
        )
        #expect(driven.backdropPath == "/tmp/painting.jpg")
        #expect(driven.script?.name == "looks")
        driven.model.nook.timer.reset()
    }
}

// MARK: - Music

@MainActor
struct DemoMusicTests {
    private func player(startsPlaying: Bool = true) -> (DemoPlayer, ManualClock) {
        let clock = ManualClock(DemoFixture.now)
        return (DemoPlayer(startsPlaying: startsPlaying, elapsed: 38, now: { clock.now }), clock)
    }

    @Test func thereAreFourTracksAndTheFirstPlaysWithArtwork() {
        let (player, _) = player()
        let state = player.state

        #expect(DemoTrack.all.count == 4)
        #expect(state.title == "Midnight Drive")
        #expect(state.artist == "Neon Coast")
        #expect(state.album == "Afterglow")
        #expect(state.isPlaying)
        #expect((state.artworkData?.count ?? 0) > 100)
        #expect(state.duration == 214)
    }

    @Test func theBarAdvancesWithTheClockTheTestHolds() throws {
        let (player, clock) = player()
        let start = DemoFixture.now
        #expect(player.state.position(at: start) == 38)

        clock.advance(30)
        let later = clock.now
        let progress = try #require(player.state.progress(at: later))
        #expect(player.state.position(at: later) == 68)
        #expect(abs(progress - 68.0 / 214.0) < 1e-9)

        // Paused, the bar holds where it was.
        player.handle(.pause)
        clock.advance(60)
        #expect(player.state.position(at: clock.now) == 68)
        #expect(!player.state.isPlaying)

        player.handle(.play)
        clock.advance(10)
        #expect(player.state.position(at: clock.now) == 78)
    }

    @Test func theBarStopsAtTheEndOfTheTrack() {
        let (player, clock) = player()
        clock.advance(10_000)
        #expect(player.state.position(at: clock.now) == 214)
    }

    @Test func nextAndPreviousMoveBetweenTheTracks() {
        let (player, clock) = player()

        player.handle(.nextTrack)
        #expect(player.state.title == "Paper Lanterns")
        #expect(player.state.position(at: clock.now) == 0)
        player.handle(.nextTrack)
        player.handle(.nextTrack)
        #expect(player.state.title == "Window Seat")
        player.handle(.nextTrack)
        #expect(player.state.title == "Midnight Drive", "after the last track comes the first")

        // A few seconds in, Previous starts the track again. Near its start
        // it goes back one.
        clock.advance(20)
        player.handle(.previousTrack)
        #expect(player.state.title == "Midnight Drive")
        #expect(player.state.position(at: clock.now) == 0)
        player.handle(.previousTrack)
        #expect(player.state.title == "Window Seat")
    }

    @Test func eachTrackKeepsItsOwnIdentityAndCover() {
        let (player, _) = player()
        var identities: [String?] = []
        var covers: [Data?] = []
        for _ in DemoTrack.all {
            identities.append(player.state.itemIdentifier)
            covers.append(player.state.artworkData)
            player.handle(.nextTrack)
        }
        #expect(Set(identities.compactMap { $0 }).count == 4)
        #expect(Set(covers.compactMap { $0 }).count == 4)
    }

    @Test func theServiceSendsNothingOutsideWhenACommandIsPressed() {
        let (player, _) = player()
        var launched: [[String]] = []
        let service = MediaRemoteService(commandLauncher: { launched.append($0); return true }, sample: player)

        service.start()
        #expect(service.isAvailable)
        #expect(service.state?.title == "Midnight Drive")

        service.togglePlayPause()
        #expect(service.state?.isPlaying == false)
        service.nextTrack()
        #expect(service.state?.title == "Paper Lanterns")
        service.previousTrack()
        service.seek(to: 90)
        #expect(service.state?.elapsedTime == 90)
        #expect(launched.isEmpty, "no adapter command left the app")
    }
}

// MARK: - Calendar

@MainActor
struct DemoCalendarTests {
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func source() -> DemoCalendarSource {
        DemoCalendarSource(now: DemoFixture.now, calendar: Self.utc)
    }

    @Test func theEventsAreOffsetFromTheMomentTheTestHandsIn() throws {
        let now = DemoFixture.now
        let events = source().events

        let first = try #require(events.first)
        #expect(first.title == "Standup")
        #expect(first.start == now.addingTimeInterval(20 * 60))
        #expect(first.meetingURL != nil)
        #expect(events.filter { $0.meetingURL != nil }.count == 1)

        let startOfToday = Self.utc.startOfDay(for: now)
        let today = events.filter { Self.utc.isDate($0.start, inSameDayAs: now) }
        #expect(today.count == 3, "one in about 20 minutes and two later today")
        #expect(today.dropFirst().allSatisfy { $0.start > first.start })

        let other = events.filter { !Self.utc.isDate($0.start, inSameDayAs: now) }
        #expect(other.count >= 3)
        for event in other {
            let day = Self.utc.dateComponents([.day], from: startOfToday, to: Self.utc.startOfDay(for: event.start)).day ?? 0
            #expect((1...6).contains(day), "\(event.title) is within the week the card looks ahead")
        }
    }

    @Test func aDifferentMomentMovesEveryEvent() {
        let later = DemoFixture.now.addingTimeInterval(3 * 86_400)
        let moved = DemoCalendarSource(now: later, calendar: Self.utc).events
        #expect(moved.first?.start == later.addingTimeInterval(20 * 60))
    }

    @Test func theServiceCountsAccessAsAllowedAndReadsTheSample() async throws {
        let fixture = DemoFixture(now: Date())
        defer { fixture.remove() }
        let calendar = fixture.nook.calendar
        #expect(calendar.hasAccess)
        #expect(calendar.authorization == .fullAccess)

        fixture.startSampleServices()
        #expect(calendar.events.count == 7)
        #expect(calendar.calendars.map(\.title) == ["Work", "Personal", "School"])
        #expect(calendar.defaultCalendarID == DemoCalendarSource.personalID)

        // Asking for access asks macOS for nothing.
        #expect(await calendar.requestAccessIfUndecided() == false)
        let start = Calendar.current.startOfDay(for: Date())
        let range = calendar.events(from: start, to: start.addingTimeInterval(14 * 86_400))
        #expect(range.count == 7)
    }

    @Test func aNewEventIsKeptInMemory() throws {
        let fixture = DemoFixture(now: Date())
        defer { fixture.remove() }
        fixture.startSampleServices()
        let start = Date().addingTimeInterval(3_600)

        try fixture.nook.calendar.addEvent(NookEventDraft(title: "Study group", start: start, end: start.addingTimeInterval(3_600), isAllDay: false))

        #expect(fixture.nook.calendar.events.contains { $0.title == "Study group" })
    }

    @Test func theNextUpNoticeFiresFromTheSampleAtTenMinutes() throws {
        let fixture = DemoFixture(now: Date())
        defer { fixture.remove() }
        fixture.startSampleServices()
        let event = try #require(fixture.nook.calendar.events.first { !$0.isAllDay })

        fixture.nook.calendar.checkNextUp(now: event.start.addingTimeInterval(-9.5 * 60))

        #expect(fixture.nook.transient?.text.hasSuffix("in 10 min") == true)
        #expect(fixture.nook.transient?.symbol == "video.fill", "the event has a join link")
    }
}

// MARK: - To-dos, notes, tray, weather

@MainActor
struct DemoSampleListsTests {
    @Test func theTodoListHasSixTasksOneDueAndOneWithNotes() {
        let items = DemoTodo.items(now: DemoFixture.now)

        #expect(items.count == 6)
        #expect(items.filter { $0.dueDate != nil }.count == 1)
        #expect(items.filter { $0.notes != nil }.count == 1)
        #expect(Set(items.map(\.id)).count == 6)
        #expect(items.allSatisfy { !$0.isCompleted })
    }

    @Test func checkingOneOffAndAddingOneWorkInMemory() {
        let fixture = DemoFixture()
        defer { fixture.remove() }
        fixture.startSampleServices()
        let source = fixture.nook.todo.source(reminders: fixture.nook.reminders)
        #expect(source.connection == .ready)
        #expect(source.canAdd && source.canComplete)
        #expect(source.items.count == 6)

        let first = source.items[0].id
        source.complete(first)
        #expect(source.items.count == 5)
        #expect(!source.items.contains { $0.id == first })

        source.add("Call home")
        #expect(source.items.last?.title == "Call home")
        source.add("   ")
        #expect(source.items.count == 6, "an empty title adds nothing")
        #expect(fixture.nook.reminders.hasAccess)
    }

    @Test func theDueDateIsTomorrowAtFive() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let due = try #require(DemoTodo.items(now: DemoFixture.now, calendar: calendar).compactMap(\.dueDate).first)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        #expect(parts.year == 2027 && parts.month == 1 && parts.day == 16)
        #expect(parts.hour == 17 && parts.minute == 0)
    }

    @Test func theNotesFileHoldsFiveLinesAndSavingALineWorks() {
        let fixture = DemoFixture()
        defer { fixture.remove() }
        fixture.startSampleServices()
        let notes = fixture.nook.notes

        #expect(notes.entries.count == 5)
        #expect(notes.entries.first?.text == "Read chapter 6", "newest first")
        #expect(notes.fileURL.path.hasPrefix(fixture.session.folder.path), "the file is in the demo's own folder")

        notes.append("Pick up groceries")
        #expect(notes.entries.count == 6)
        #expect(notes.entries.first?.text == "Pick up groceries")
        #expect(notes.savedCount == 1)
    }

    @Test func theNotesWriterForAppleNotesWritesNowhere() async throws {
        try await DemoNotesWriter().append(lineHTML: "<div>x</div>", toNoteTitled: "Quick Notes")
    }

    @Test func theWeatherIsLosAngelesFromACannedReport() throws {
        let fixture = DemoFixture()
        defer { fixture.remove() }
        let weather = fixture.nook.weather

        #expect(weather.place?.name == "Los Angeles")
        let report = try #require(weather.report)
        #expect(report.fetchedAt == DemoFixture.now)
        #expect(report.hours.count == 24)
        #expect(report.days.count == 7)
        #expect(report.week(from: DemoFixture.now).count == 7, "every day carries its sky")
        #expect(report.upcomingHours(after: DemoFixture.now, count: 12).count == 12)
        #expect(report.current.code == 1)
        // Fahrenheit by default: 22.2 C reads as 72 degrees.
        #expect(weather.unit.text(celsius: report.current.temperature) == "72°")
    }

    @Test func noRequestLeavesTheMacForTheWeather() async throws {
        let fixture = DemoFixture(weatherTransport: DemoWeatherTransport())
        defer { fixture.remove() }
        fixture.startSampleServices()
        fixture.nook.setWidget(.weather, enabled: true)

        // The saved report is fresh, which means nothing is asked for.
        fixture.nook.weather.refreshIfDue()
        await fixture.nook.weather.waitForRefresh()
        #expect(fixture.nook.weather.status == .idle)

        // Even asked for a new city, the only answer is "offline".
        fixture.nook.weather.search("Paris", language: "en")
        await fixture.nook.weather.waitForSearch()
        #expect(fixture.nook.weather.searchStatus == .failed(.offline))
        #expect(fixture.nook.weather.searchResults.isEmpty)
    }

    @Test func theTrayHoldsFourFilesAndItsClipboardTabIsOff() throws {
        let fixture = DemoFixture()
        defer { fixture.remove() }
        fixture.startSampleServices()
        let tray = fixture.nook.tray

        #expect(tray.items.count == 4)
        #expect(tray.tab == .files)
        #expect(!tray.clipboard.isEnabled)
        for item in tray.items {
            #expect(FileManager.default.fileExists(atPath: tray.storedURL(for: item).path))
            #expect(tray.storedURL(for: item).path.hasPrefix(fixture.session.folder.path))
        }
    }
}
