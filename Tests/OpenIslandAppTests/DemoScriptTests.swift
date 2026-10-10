import Foundation
import Testing
import OpenIslandCore
@testable import OpenIslandApp

// The demo scripts (D51) as plain values, run against recorders with a clock
// that does not wait, and against the demo model's own doors. No test here
// launches the app, shows a window or moves the pointer.

@MainActor
struct DemoScriptShapeTests {
    @Test func thereAreFourScriptsByName() {
        #expect(DemoScripts.names == ["tour", "use", "closed", "looks"])
        for name in DemoScripts.names {
            #expect(DemoScripts.named(name)?.name == name)
        }
        #expect(DemoScripts.named("nope") == nil)
        #expect(DemoScripts.named("") == nil)
    }

    @Test(arguments: ["tour", "use", "closed", "looks"])
    func everyScriptIsUnderTwoMinutesAndEveryStepNamesADoor(name: String) throws {
        let script = try #require(DemoScripts.named(name))

        #expect(script.duration < DemoScript.longestAllowed, "\(name) runs \(script.duration) seconds")
        #expect(script.duration > 20)
        #expect(!script.steps.isEmpty)
        for step in script.steps {
            #expect(!step.name.isEmpty)
            #expect(!step.action.door.isEmpty, "\(step.name) names no door")
            #expect(step.pause >= 0.8 && step.pause <= 7, "\(step.name) waits \(step.pause)")
        }
        #expect(DemoScript.endPause == 2)
    }

    @Test func theWordsOfTheScriptsHaveNoEmOrEnDashes() {
        for script in DemoScripts.all {
            for step in script.steps {
                let text = step.name + step.action.door
                #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"))
            }
        }
    }

    @Test func theTourWalksEveryPageItsOwnWayAndAsksMacOSForNothing() {
        let steps = DemoScripts.tour.steps.map(\.action)

        #expect(steps.first == .openTour)
        #expect(steps.filter { $0 == .tourNext }.count == DemoScripts.tourPages.count, "one Next for each page, the last one finishes")
        #expect(DemoScripts.tourPages.first == .welcome && DemoScripts.tourPages.last == .done)
        // The widgets page: one widget off and on.
        #expect(steps.contains(.tourSetWidget(.tray, isOn: false)))
        let off = steps.firstIndex(of: .tourSetWidget(.tray, isOn: false)) ?? 0
        let on = steps.firstIndex(of: .tourSetWidget(.tray, isOn: true)) ?? 0
        #expect(off < on)
        // The features page steps through each of the six widgets.
        #expect(steps.filter { $0 == .tourNextFeature }.count == 5)
        #expect(steps.contains(.tourTry(.musicPlay)) && steps.contains(.tourTry(.musicNext)))
        #expect(steps.contains(.tourTry(.timerStart)) && steps.contains(.tourTry(.timerStop)))
        let looks = steps.compactMap { step -> NookCalendarStyle? in
            if case .tourSetCalendarLook(let style) = step { style } else { nil }
        }
        #expect(looks.count == 3)
        #expect(Set(looks).count == 3)
        #expect(looks.last == .month)
        // The layout page: two templates.
        #expect(steps.filter { if case .tourApplyTemplate = $0 { true } else { false } }.count == 2)
        // The arrange page: pick, move one place, put back.
        let pick = steps.firstIndex(of: .tourPickWidget(.todo)) ?? -1
        let move = steps.firstIndex(of: .tourMoveWidget(.todo, to: 1)) ?? -1
        let putBack = steps.firstIndex(of: .tourPutBack) ?? -1
        #expect(pick >= 0 && pick < move && move < putBack)
        // No button that asks macOS for anything, or opens another app.
        let forbidden: [OnboardingTry] = [.mirrorOn, .ringLight, .photoBooth, .calendarShow, .notesLine, .trayCopy]
        for step in forbidden {
            #expect(!steps.contains(.tourTry(step)), "\(step) is not pressed")
        }
    }

    @Test func theUseScriptDoesWhatEverydayUseDoesInOrder() {
        let steps = DemoScripts.use.steps.map(\.action)
        let expected: [DemoAction] = [
            .openIsland, .playOrPause, .playOrPause, .playOrPause, .nextTrack,
            .checkOffTodo(position: 0), .addTodo("Call home"), .startTimer(minutes: 25),
            .closeIsland, .openIsland, .saveNote("Pick up groceries on the way back"),
            .applyTemplate(.focus), .undoTemplate,
            .beginEditing, .moveWidget(.timer, to: 1), .resizeWidget(.todo, .large), .endEditing, .closeIsland,
        ]
        #expect(steps == expected)
        #expect(!DemoScripts.use.startsPlaying, "the first press plays")
    }

    @Test func theClosedScriptShowsEachClosedLookInTurn() {
        let steps = DemoScripts.closed.steps.map(\.action)
        let order: [DemoAction] = [
            .closeIsland, .playOrPause, .startTimer(minutes: 25), .stopTimer, .playOrPause,
            .showChargingNotice, .showCalendarNotice,
        ]
        #expect(Array(steps.prefix(order.count)) == order)
        for side in [OnboardingClosedSide.date, .battery, .weather, .todos] {
            #expect(steps.contains(.chooseRightSide(side)))
        }
        for side in [OnboardingClosedLeft.date, .battery, .weather, .todos] {
            #expect(steps.contains(.chooseLeftSide(side)))
        }
        #expect(Array(steps.suffix(3)) == [.playOrPause, .setGlow(.vivid), .nextTrack])
        #expect(steps.allSatisfy { if case .openIsland = $0 { false } else { true } }, "only the closed island")
        #expect(!DemoScripts.closed.startsPlaying, "idle first")
    }

    @Test func theLooksScriptGoesThroughFiveLooksThenTheWeatherThenThreeLayouts() {
        let steps = DemoScripts.looks.steps.map(\.action)
        let looks = steps.compactMap { step -> NookCalendarStyle? in
            if case .setCalendarLook(let style) = step { style } else { nil }
        }
        #expect(looks == NookCalendarStyle.allCases)
        #expect(steps.contains(.resizeWidget(.calendar, .large)))
        let hours = steps.firstIndex(of: .setWeatherMode(.hours)) ?? -1
        let week = steps.firstIndex(of: .setWeatherMode(.week)) ?? -1
        #expect(hours >= 0 && hours < week)
        let templates = steps.compactMap { step -> PersonalizationTemplate.ID? in
            if case .applyTemplate(let id) = step { id } else { nil }
        }
        #expect(templates.count == 3 && Set(templates).count == 3)
        // The looks come before the weather, and the weather before the layouts.
        let lastLook = steps.lastIndex(of: .setCalendarLook(.month)) ?? -1
        let firstTemplate = steps.firstIndex { if case .applyTemplate = $0 { true } else { false } } ?? -1
        #expect(lastLook < week && week < firstTemplate)
    }

    @Test func aLogLineIsTheSecondsSinceLaunchThenTheStepsName() {
        let line = DemoRunner.line(
            since: DemoFixture.now, now: DemoFixture.now.addingTimeInterval(12.4), name: DemoAction.openIsland.name
        )
        #expect(line == "DEMO 12.40 open-island")
    }
}

// MARK: - Run against recorders

@MainActor
struct DemoRunnerTests {
    @Test(arguments: ["tour", "use", "closed", "looks"])
    func aRunCallsTheDoorsInOrderThenQuitsAfterTwoSeconds(name: String) async throws {
        let script = try #require(DemoScripts.named(name))
        let doors = RecordingDoors()
        let clock = InstantClock()

        await clock.runner.run(script, doors: doors, launchedAt: DemoFixture.now)

        #expect(doors.actions == script.steps.map(\.action))
        #expect(clock.sleeps == script.steps.map(\.pause) + [2])
        #expect(clock.sleeps.reduce(0, +) == script.duration)
        #expect(clock.quitCount == 1)
        #expect(clock.lines.count == script.steps.count, "one line for each step")
    }

    @Test func eachLineHasTheSecondsSinceLaunchAndTheStepsName() async {
        let script = DemoScript(
            name: "tiny", startsPlaying: true,
            steps: [DemoStep(1.5, .openIsland), DemoStep(2.25, .playOrPause)]
        )
        let doors = RecordingDoors()
        let clock = InstantClock(start: DemoFixture.now.addingTimeInterval(3))

        await clock.runner.run(script, doors: doors, launchedAt: DemoFixture.now)

        #expect(clock.lines == ["DEMO 4.50 open-island", "DEMO 6.75 play-pause"])
    }
}

// MARK: - The doors on the demo model

@MainActor
struct DemoDoorsOnTheModelTests {
    private static func run(_ name: String, on fixture: DemoFixture, tour: OnboardingTour? = nil) async throws {
        let script = try #require(DemoScripts.named(name))
        let doors = AppDemoDoors(model: fixture.model, openTour: {}, currentTour: { tour })
        await InstantClock().runner.run(script, doors: doors, launchedAt: DemoFixture.now)
    }

    @Test func useEndsWithTheListNoteLayoutAndIslandWhereTheStepsLeftThem() async throws {
        let fixture = DemoFixture(script: "use", now: Date())
        defer { fixture.remove() }
        fixture.startSampleServices()

        try await Self.run("use", on: fixture)

        let nook = fixture.nook
        let todos = nook.reminders.items.map(\.title)
        #expect(todos.count == 6)
        #expect(!todos.contains("Finish problem set 3"), "the first task was checked off")
        #expect(todos.last == "Call home")
        #expect(nook.notes.entries.first?.text == "Pick up groceries on the way back")
        #expect(nook.notes.savedCount == 1)
        #expect(nook.media.state?.isPlaying == true)
        #expect(nook.media.state?.title == "Paper Lanterns")
        #expect(nook.timer.isActive, "the 25 minute timer is still running")
        #expect(nook.timer.remaining > 24 * 60)
        #expect(!nook.isEditingLayout)
        #expect(fixture.model.notchStatus == .closed)
        // The template went on and came off again.
        #expect(fixture.model.appliedTemplateID(for: fixture.model.activeAppearanceProfile) == nil)
        let order = nook.widgetPlacements(for: fixture.model.activeAppearanceProfile)
        #expect(order.map(\.kind).firstIndex(of: .timer) == 1)
        #expect(order.first { $0.kind == .todo }?.size == .large)
    }

    @Test func closedEndsOnVividGlowWithMusicPlayingAndTheSidesCleared() async throws {
        let fixture = DemoFixture(script: "closed", now: Date())
        defer { fixture.remove() }
        fixture.startSampleServices()

        try await Self.run("closed", on: fixture)

        let display = fixture.nook.displayPreferences(for: fixture.model.activeAppearanceProfile)
        #expect(display.haloStyle == .vivid)
        #expect(display.rightSlot == nil, "with the agents off, Nothing clears the Nook item")
        #expect(display.leftSlot == .none)
        #expect(fixture.nook.media.state?.isPlaying == true)
        #expect(fixture.nook.timer.isActive == false)
    }

    @Test func theCalendarNoticeShowsOnTheClosedIsland() {
        let fixture = DemoFixture(now: Date())
        defer { fixture.remove() }
        fixture.startSampleServices()
        let doors = AppDemoDoors(model: fixture.model, openTour: {}, currentTour: { nil })

        doors.perform(.showCalendarNotice)
        #expect(fixture.nook.transient?.text.hasSuffix("in 10 min") == true)
    }

    @Test func looksEndsWithTheWeatherOnThePageInWeekModeAndTheLastLayoutOn() async throws {
        let fixture = DemoFixture(script: "looks", now: Date())
        defer { fixture.remove() }
        fixture.startSampleServices()

        try await Self.run("looks", on: fixture)

        let profile = fixture.model.activeAppearanceProfile
        #expect(fixture.nook.weather.forecastMode == .week)
        #expect(fixture.nook.isWidgetEnabled(.weather))
        #expect(fixture.model.appliedTemplateID(for: profile) == .nowPlaying)
        #expect(fixture.model.notchStatus == .closed)
    }

    @Test func aDoorForAMissingTourOrWidgetDoesNothing() {
        let fixture = DemoFixture(now: Date())
        defer { fixture.remove() }
        fixture.startSampleServices()
        let doors = AppDemoDoors(model: fixture.model, openTour: {}, currentTour: { nil })

        for action in [DemoAction.tourNext, .tourNextFeature, .tourTry(.musicPlay), .tourPutBack, .checkOffTodo(position: 40)] {
            doors.perform(action)
        }
        #expect(fixture.nook.reminders.items.count == 6)
    }
}

// MARK: - The tour script against a tour

/// The app as a tour sees it, with each door doing to a plain state what the
/// real one does to the app. Nothing here shows a window.
@MainActor
private final class TourWorld {
    var state = OnboardingState()
    var calendarWrites: [NookCalendarStyle] = []
    var tracks = 0

    init() {
        state.agentsEnabled = false
        state.enabledWidgets = Set(NookWidgetKind.defaultEnabled)
        state.nookPlacements = NookDisplayPreferences().placements(enabled: NookWidgetKind.defaultEnabled)
        state.features.music = OnboardingMusicReading(isPlaying: true, track: "track-0")
    }

    var actions: OnboardingActions {
        var actions = OnboardingActions()
        actions.setWidget = { [self] kind, isOn in
            if isOn { state.enabledWidgets.insert(kind) } else { state.enabledWidgets.remove(kind) }
            state.nookPlacements = NookDisplayPreferences().placements(enabled: NookWidgetKind.allCases.filter(state.enabledWidgets.contains))
        }
        actions.setCalendarStyle = { [self] in
            state.calendarStyle = $0
            calendarWrites.append($0)
        }
        actions.applyTemplate = { [self] template in
            // A template carries a look of its own.
            state.calendarStyle = template.nook.calendarStyle
            state.appliedTemplate = template.id
            state.nookPlacements = template.widgets.filter { state.enabledWidgets.contains($0.kind) }
        }
        actions.restorePlacements = { [self] in state.nookPlacements = $0 }
        actions.playOrPause = { [self] in
            state.features.music?.isPlaying.toggle()
        }
        actions.nextTrack = { [self] in
            tracks += 1
            state.features.music?.track = "track-\(tracks)"
        }
        actions.startTimer = { [self] length in
            state.features.isTimerActive = true
            state.features.timerOneOff = length
        }
        actions.stopTimer = { [self] in
            state.features.isTimerActive = false
            state.features.timerOneOff = nil
        }
        return actions
    }
}

/// Forwards to the real doors and writes down where the tour stood after
/// each step.
@MainActor
private final class ProbingDoors: DemoDoors {
    struct Moment {
        let action: DemoAction
        let page: OnboardingPage
        let look: NookCalendarStyle
    }

    private let inner: AppDemoDoors
    private let tour: OnboardingTour
    private let world: TourWorld
    private(set) var moments: [Moment] = []

    init(inner: AppDemoDoors, tour: OnboardingTour, world: TourWorld) {
        self.inner = inner
        self.tour = tour
        self.world = world
    }

    func perform(_ action: DemoAction) {
        inner.perform(action)
        moments.append(Moment(action: action, page: tour.page, look: world.state.calendarStyle))
    }
}

@MainActor
struct DemoTourScriptTests {
    @Test func theTourScriptWalksEveryPageInOrderAndFinishesTheTour() async throws {
        let fixture = DemoFixture(script: "tour", now: Date())
        defer { fixture.remove() }
        let world = TourWorld()
        var ended: OnboardingOutcome?
        let tour = OnboardingTour(state: { world.state }, actions: world.actions, onEnd: { ended = $0 })
        var opened = 0
        let inner = AppDemoDoors(model: fixture.model, openTour: { opened += 1 }, currentTour: { tour })
        let doors = ProbingDoors(inner: inner, tour: tour, world: world)

        await InstantClock().runner.run(DemoScripts.tour, doors: doors, launchedAt: DemoFixture.now)

        #expect(opened == 1)
        #expect(ended == .finished)
        // The page after each Next is the next page of the walk.
        let pages = doors.moments.filter { $0.action == .tourNext }.map(\.page)
        #expect(Array(pages.dropLast()) == Array(DemoScripts.tourPages.dropFirst()))
        #expect(pages.count == DemoScripts.tourPages.count)
    }

    @Test func eachTourStepLandsOnThePageItIsMeantFor() async throws {
        let fixture = DemoFixture(script: "tour", now: Date())
        defer { fixture.remove() }
        let world = TourWorld()
        let tour = OnboardingTour(state: { world.state }, actions: world.actions)
        let inner = AppDemoDoors(model: fixture.model, openTour: {}, currentTour: { tour })
        let doors = ProbingDoors(inner: inner, tour: tour, world: world)

        await InstantClock().runner.run(DemoScripts.tour, doors: doors, launchedAt: DemoFixture.now)

        func page(of action: DemoAction) -> OnboardingPage? {
            doors.moments.first { $0.action == action }?.page
        }
        #expect(page(of: .tourSetWidget(.tray, isOn: false)) == .widgets)
        #expect(page(of: .tourSetWidget(.tray, isOn: true)) == .widgets)
        #expect(page(of: .tourTry(.musicPlay)) == .features)
        #expect(page(of: .tourTry(.musicNext)) == .features)
        #expect(page(of: .tourSetCalendarLook(.month)) == .features)
        #expect(page(of: .tourTry(.timerStart)) == .features)
        #expect(page(of: .tourTry(.timerStop)) == .features)
        #expect(page(of: .tourApplyTemplate(.planner)) == .layout)
        #expect(page(of: .tourApplyTemplate(.focus)) == .layout)
        #expect(page(of: .tourPickWidget(.todo)) == .arrange)
        #expect(page(of: .tourMoveWidget(.todo, to: 1)) == .arrange)
        #expect(page(of: .tourPutBack) == .arrange)
    }

    @Test func theButtonsDidTheirWorkAndTheCalendarLookSurvivedBothTemplates() async throws {
        let fixture = DemoFixture(script: "tour", now: Date())
        defer { fixture.remove() }
        let world = TourWorld()
        let tour = OnboardingTour(state: { world.state }, actions: world.actions)
        let inner = AppDemoDoors(model: fixture.model, openTour: {}, currentTour: { tour })
        let doors = ProbingDoors(inner: inner, tour: tour, world: world)

        await InstantClock().runner.run(DemoScripts.tour, doors: doors, launchedAt: DemoFixture.now)

        // The look picked on the features page was Month, and it was still
        // Month right after each template, whatever the template carried.
        for id in [PersonalizationTemplate.ID.planner, .focus] {
            let moment = try #require(doors.moments.first { $0.action == .tourApplyTemplate(id) })
            #expect(moment.look == .month, "\(id) left the look at \(moment.look)")
        }
        #expect(world.state.calendarStyle == .month)
        #expect(Array(world.calendarWrites.prefix(3)) == [.agenda, .timeline, .month])
        // Music paused and moved on; the minute ran and was stopped.
        #expect(world.state.features.music?.isPlaying == false)
        #expect(world.tracks == 1)
        #expect(!world.state.features.isTimerActive)
        // The tray widget was switched off and on, which leaves it on.
        #expect(world.state.enabledWidgets.contains(.tray))
        // The drag's door moved the to-do widget one place on the demo model.
        let order = fixture.nook.widgetPlacements(for: fixture.model.activeAppearanceProfile).map(\.kind)
        #expect(order.firstIndex(of: .todo) == 1)
    }
}
