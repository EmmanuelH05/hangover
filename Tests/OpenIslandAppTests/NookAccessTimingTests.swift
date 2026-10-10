import EventKit
import Foundation
import Testing
@testable import OpenIslandApp

/// A calendar or reminders permission that exists only in a test. It counts
/// how often macOS would have been asked. No test here calls EventKit: the
/// status is made up, and a request only changes that made-up status.
///
/// The answer is never "allowed". A service that believes it has access
/// reads the real event store, and no test may do that either.
@MainActor
final class FakeEventKitPermission {
    var status: EKAuthorizationStatus
    /// What the status turns into once macOS has been asked.
    var answer: EKAuthorizationStatus
    private(set) var requestCount = 0
    /// Runs while the made-up prompt is up, before it is answered.
    var whilePromptIsUp: (@MainActor () async -> Void)?

    init(status: EKAuthorizationStatus, answer: EKAuthorizationStatus = .denied) {
        self.status = status
        self.answer = answer
    }

    var access: NookEventKitAccess {
        NookEventKitAccess(
            status: { self.status },
            request: {
                self.requestCount += 1
                await self.whilePromptIsUp?()
                self.status = self.answer
            }
        )
    }
}

/// When macOS is asked for the calendar and for Reminders: never at launch,
/// only once a widget that needs it is shown or turned on, and never again
/// once the question has an answer.
@MainActor
struct NookAccessTimingTests {
    static let once: Int = 1
    static let never: Int = 0

    // MARK: The rule

    @Test func nothingIsAskedForAtLaunch() {
        let none: Set<NookEventKitPermission> = []
        for kind in NookWidgetKind.allCases {
            for source in NookTodoSourceKind.allCases {
                let asked = NookAccessTiming.permissions(for: kind, at: .launch, isEnabled: true, todoSource: source)
                #expect(asked == none, "\(kind) asks at launch")
            }
        }
    }

    @Test(arguments: [NookAccessMoment.shown, .turnedOn])
    func theCalendarAndTheToDoWidgetAskWhenShownOrTurnedOn(moment: NookAccessMoment) {
        let calendar: Set<NookEventKitPermission> = [.calendar]
        let reminders: Set<NookEventKitPermission> = [.reminders]
        #expect(NookAccessTiming.permissions(for: .calendar, at: moment, isEnabled: true, todoSource: .reminders) == calendar)
        #expect(NookAccessTiming.permissions(for: .todo, at: moment, isEnabled: true, todoSource: .reminders) == reminders)
    }

    @Test(arguments: [NookAccessMoment.shown, .turnedOn])
    func aToDoWidgetOnNotionNeverAsksForReminders(moment: NookAccessMoment) {
        let none: Set<NookEventKitPermission> = []
        #expect(NookAccessTiming.permissions(for: .todo, at: moment, isEnabled: true, todoSource: .notion) == none)
        #expect(NookAccessTiming.permissions(for: .todo, at: moment, isEnabled: true, todoSource: .tickTick) == none)
    }

    @Test(arguments: [NookAccessMoment.shown, .turnedOn])
    func aWidgetThatIsOffOrNeedsNeitherAsksForNothing(moment: NookAccessMoment) {
        let none: Set<NookEventKitPermission> = []
        #expect(NookAccessTiming.permissions(for: .calendar, at: moment, isEnabled: false, todoSource: .reminders) == none)
        #expect(NookAccessTiming.permissions(for: .todo, at: moment, isEnabled: false, todoSource: .reminders) == none)
        for kind in NookWidgetKind.allCases where kind != .calendar && kind != .todo {
            let asked = NookAccessTiming.permissions(for: kind, at: moment, isEnabled: true, todoSource: .reminders)
            #expect(asked == none, "\(kind) asks for a permission")
        }
    }

    @Test func macOSIsAskedOnlyForAPermissionNeverDecided() {
        #expect(NookAccessTiming.shouldRequest(status: .notDetermined, isAlreadyAsking: false))
        // One prompt at a time.
        #expect(!NookAccessTiming.shouldRequest(status: .notDetermined, isAlreadyAsking: true))
        // An install that already answered is not asked again, whatever
        // the answer was.
        for decided in [EKAuthorizationStatus.fullAccess, .denied, .restricted, .writeOnly] {
            #expect(!NookAccessTiming.shouldRequest(status: decided, isAlreadyAsking: false))
        }
    }

    // MARK: What counts as shown

    @Test func aTileIsShownOnlyOnTheNookPageOfAnIslandTheUserOpened() {
        let page: [NookWidgetKind] = [.media, .calendar, .todo]
        let all: Set<NookWidgetKind> = [.media, .calendar, .todo]
        let none: Set<NookWidgetKind> = []
        func inView(_ status: NotchStatus, _ reason: NotchOpenReason?, nook: Bool = true) -> Set<NookWidgetKind> {
            NookAccessTiming.widgetsInView(status: status, reason: reason, showsNookPage: nook, pageWidgets: page)
        }

        #expect(inView(.opened, .hover) == all)
        #expect(inView(.opened, .click) == all)
        // The boot animation opens the island by itself, right after launch.
        #expect(inView(.opened, .boot) == none)
        // A card is up, not the page.
        #expect(inView(.opened, .notification) == none)
        #expect(inView(.opened, nil) == none)
        // The agents page shows no tiles.
        #expect(inView(.opened, .hover, nook: false) == none)
        #expect(inView(.closed, nil) == none)
        #expect(inView(.popping, .hover) == none)
    }

    @Test func aWidgetThatIsNotOnThePageIsNotShown() {
        let shown = NookAccessTiming.widgetsInView(
            status: .opened, reason: .click, showsNookPage: true, pageWidgets: [.media, .timer]
        )
        #expect(!shown.contains(.calendar))
        #expect(!shown.contains(.todo))
    }

    // MARK: The services

    @Test(arguments: [EKAuthorizationStatus.notDetermined, .denied, .restricted, .writeOnly])
    func startingTheCalendarServiceAsksForNothing(status: EKAuthorizationStatus) {
        let permission = FakeEventKitPermission(status: status)
        let service = NookCalendarService(access: permission.access)
        let nook = NookModel(calendar: service, defaults: MemoryDefaults(), looksForImportedGIF: false)
        let before = service.revision

        service.start(nook: nook)

        #expect(permission.requestCount == Self.never)
        #expect(service.authorization == status)
        // It still loads what it may: a granted install shows its events.
        #expect(service.revision == before + 1)
    }

    @Test(arguments: [EKAuthorizationStatus.notDetermined, .denied, .restricted, .writeOnly])
    func startingTheRemindersServiceAsksForNothing(status: EKAuthorizationStatus) {
        // The answer changes between the service being made and started,
        // as it does when the user answers in System Settings. Start must
        // read it again, which is the same call that loads a granted
        // install's tasks.
        let before: EKAuthorizationStatus = status == .denied ? .restricted : .denied
        let permission = FakeEventKitPermission(status: before)
        let service = NookRemindersService(access: permission.access)
        let nook = NookModel(reminders: service, defaults: MemoryDefaults(), looksForImportedGIF: false)
        #expect(service.authorization == before)
        permission.status = status

        service.start(nook: nook)

        #expect(permission.requestCount == Self.never)
        #expect(service.authorization == status)
    }

    @Test func aRealServiceThatWasNeverStartedCannotAskMacOS() async {
        // What `AppModel(defaults: MemoryDefaults())` and `NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)` hold in every other test:
        // services on the real EventKit, never started. Asking returns
        // before anything reaches EventKit.
        let askedCalendar = await NookCalendarService().requestAccessIfUndecided()
        let askedReminders = await NookRemindersService().requestAccessIfUndecided()

        #expect(!askedCalendar)
        #expect(!askedReminders)
    }

    @Test func anAnswerChangedInSystemSettingsIsPickedUpWithoutAsking() async {
        let permission = FakeEventKitPermission(status: .denied)
        let service = NookCalendarService(access: permission.access)
        let before = service.revision

        // Nothing changed: a tile coming into view costs no reload.
        await service.requestAccessIfUndecided()
        #expect(service.revision == before)

        permission.status = .restricted
        await service.requestAccessIfUndecided()

        #expect(service.authorization == .restricted)
        #expect(service.revision == before + 1)
        #expect(permission.requestCount == Self.never)
    }

    @Test func theCalendarServiceAsksOnceAndNeverAgainOnceAnswered() async {
        let permission = FakeEventKitPermission(status: .notDetermined, answer: .denied)
        let service = NookCalendarService(access: permission.access)

        let first = await service.requestAccessIfUndecided()
        let second = await service.requestAccessIfUndecided()

        #expect(first)
        #expect(!second)
        #expect(permission.requestCount == Self.once)
        #expect(service.authorization == .denied)
    }

    @Test func theRemindersServiceAsksOnceAndNeverAgainOnceAnswered() async {
        let permission = FakeEventKitPermission(status: .notDetermined, answer: .restricted)
        let service = NookRemindersService(access: permission.access)

        let first = await service.requestAccessIfUndecided()
        let second = await service.requestAccessIfUndecided()

        #expect(first)
        #expect(!second)
        #expect(permission.requestCount == Self.once)
        #expect(service.authorization == .restricted)
    }

    @Test(arguments: [EKAuthorizationStatus.denied, .restricted, .writeOnly])
    func anAnsweredPermissionIsNeverAskedForAgain(status: EKAuthorizationStatus) async {
        let calendar = FakeEventKitPermission(status: status)
        let reminders = FakeEventKitPermission(status: status)

        let askedCalendar = await NookCalendarService(access: calendar.access).requestAccessIfUndecided()
        let askedReminders = await NookRemindersService(access: reminders.access).requestAccessIfUndecided()

        #expect(!askedCalendar)
        #expect(!askedReminders)
        #expect(calendar.requestCount == Self.never)
        #expect(reminders.requestCount == Self.never)
    }

    @Test func aSecondRequestWhileThePromptIsUpDoesNotAskTwice() async {
        let permission = FakeEventKitPermission(status: .notDetermined)
        let service = NookCalendarService(access: permission.access)
        var askedAgain: Bool?
        permission.whilePromptIsUp = {
            askedAgain = await service.requestAccessIfUndecided()
        }

        let asked = await service.requestAccessIfUndecided()

        #expect(asked)
        #expect(askedAgain == false)
        #expect(permission.requestCount == Self.once)
    }

    // MARK: The model

    /// A Nook model whose calendar and Reminders permissions are made up
    /// and whose to-do source lives in memory. Never started: `start()`
    /// would run the real services.
    private func makeNook(
        calendar: FakeEventKitPermission,
        reminders: FakeEventKitPermission,
        todoSource: NookTodoSourceKind = .reminders
    ) -> NookModel {
        let hub = NookTodoHub(defaults: MemoryDefaults())
        hub.selectedKind = todoSource
        return NookModel(
            calendar: NookCalendarService(access: calendar.access),
            reminders: NookRemindersService(access: reminders.access),
            todo: hub,
            defaults: MemoryDefaults(),
            looksForImportedGIF: false
        )
    }

    /// The saved widget switches are read, never written, by these tests.
    /// The calendar and the to-do list are on unless a user turned them
    /// off, and no test does.
    private func requireBothWidgetsOn(_ nook: NookModel) throws {
        try #require(nook.isWidgetEnabled(.calendar), "the calendar widget is off in this test host's settings")
        try #require(nook.isWidgetEnabled(.todo), "the to-do widget is off in this test host's settings")
    }

    // MARK: Tiles coming into view, and widgets turned on

    @Test func tilesComingIntoViewAskOncePerPermissionAndOneAtATime() async throws {
        let calendar = FakeEventKitPermission(status: .notDetermined)
        let reminders = FakeEventKitPermission(status: .notDetermined)
        let nook = makeNook(calendar: calendar, reminders: reminders)
        nook.allowsAccessRequests = true
        nook.widgetsInUserView = { [.calendar, .todo] }
        try requireBothWidgetsOn(nook)
        // While the calendar prompt is up, Reminders must not have been
        // asked for yet, and the tiles that appear meanwhile add nothing.
        var remindersAskedDuringCalendarPrompt: Int?
        calendar.whilePromptIsUp = {
            remindersAskedDuringCalendarPrompt = reminders.requestCount
            nook.widgetsCameIntoView()
            nook.widgetsCameIntoView()
        }

        // One open calls this three times: the island's state, then each tile.
        let first = try #require(nook.widgetsCameIntoView(), "nothing was queued")
        let second = nook.widgetsCameIntoView()
        let third = nook.widgetsCameIntoView()
        #expect(second == nil)
        #expect(third == nil)
        await first.value
        // Whatever the prompt's own calls queued.
        await nook.widgetsCameIntoView()?.value

        #expect(remindersAskedDuringCalendarPrompt == Self.never)
        #expect(calendar.requestCount == Self.once)
        #expect(reminders.requestCount == Self.once)
    }

    @Test func aPassReadsWhatIsInViewWhenItRuns() async throws {
        let calendar = FakeEventKitPermission(status: .notDetermined)
        let reminders = FakeEventKitPermission(status: .notDetermined)
        let nook = makeNook(calendar: calendar, reminders: reminders)
        nook.allowsAccessRequests = true
        try requireBothWidgetsOn(nook)
        var inView: Set<NookWidgetKind> = [.calendar, .todo]
        nook.widgetsInUserView = { inView }

        let pass = try #require(nook.widgetsCameIntoView(), "nothing was queued")
        // The island closes before the pass gets its turn.
        inView = []
        await pass.value

        #expect(calendar.requestCount == Self.never)
        #expect(reminders.requestCount == Self.never)
    }

    @Test func turningAWidgetOnInSettingsAsksForItsPermission() async throws {
        let calendar = FakeEventKitPermission(status: .notDetermined)
        let reminders = FakeEventKitPermission(status: .notDetermined)
        let nook = makeNook(calendar: calendar, reminders: reminders)
        nook.allowsAccessRequests = true
        try requireBothWidgetsOn(nook)

        let forToDo = try #require(nook.widgetTurnedOn(.todo), "nothing was queued")
        await forToDo.value
        #expect(reminders.requestCount == Self.once)
        #expect(calendar.requestCount == Self.never)

        let forCalendar = try #require(nook.widgetTurnedOn(.calendar), "nothing was queued")
        await forCalendar.value
        #expect(calendar.requestCount == Self.once)

        // Turned on again: both have their answer.
        await nook.widgetTurnedOn(.calendar)?.value
        await nook.widgetTurnedOn(.todo)?.value
        #expect(calendar.requestCount == Self.once)
        #expect(reminders.requestCount == Self.once)
    }

    @Test func turningAWidgetOnBeforeTheModelStartsAsksForNothing() {
        let calendar = FakeEventKitPermission(status: .notDetermined)
        let reminders = FakeEventKitPermission(status: .notDetermined)
        let nook = makeNook(calendar: calendar, reminders: reminders)

        #expect(nook.widgetTurnedOn(.calendar) == nil)
        #expect(nook.widgetTurnedOn(.todo) == nil)
        #expect(calendar.requestCount == Self.never)
        #expect(reminders.requestCount == Self.never)
    }

    @Test func aModelThatWasNeverStartedAsksForNothing() async {
        let calendar = FakeEventKitPermission(status: .notDetermined)
        let reminders = FakeEventKitPermission(status: .notDetermined)
        let nook = makeNook(calendar: calendar, reminders: reminders)
        #expect(!nook.allowsAccessRequests)

        let asked = await nook.askForAccess(for: .calendar, at: .shown)
        nook.widgetsInUserView = { [.calendar, .todo] }
        // Nothing is queued at all, which is more than "nothing was asked".
        #expect(nook.widgetsCameIntoView() == nil)

        let none: Set<NookEventKitPermission> = []
        #expect(asked == none)
        #expect(calendar.requestCount == Self.never)
        #expect(reminders.requestCount == Self.never)
    }

    @Test func launchAsksForNothingEvenWithBothWidgetsOn() async throws {
        let calendar = FakeEventKitPermission(status: .notDetermined)
        let reminders = FakeEventKitPermission(status: .notDetermined)
        let nook = makeNook(calendar: calendar, reminders: reminders)
        nook.allowsAccessRequests = true
        try requireBothWidgetsOn(nook)

        await nook.askForAccess(for: .calendar, at: .launch)
        await nook.askForAccess(for: .todo, at: .launch)

        #expect(calendar.requestCount == Self.never)
        #expect(reminders.requestCount == Self.never)
    }

    @Test(arguments: [NookAccessMoment.shown, .turnedOn])
    func eachWidgetAsksOnlyForItsOwnPermission(moment: NookAccessMoment) async throws {
        let calendar = FakeEventKitPermission(status: .notDetermined)
        let reminders = FakeEventKitPermission(status: .notDetermined)
        let nook = makeNook(calendar: calendar, reminders: reminders)
        nook.allowsAccessRequests = true
        try requireBothWidgetsOn(nook)

        let forCalendar = await nook.askForAccess(for: .calendar, at: moment)
        let onlyCalendar: Set<NookEventKitPermission> = [.calendar]
        #expect(forCalendar == onlyCalendar)
        #expect(calendar.requestCount == Self.once)
        #expect(reminders.requestCount == Self.never)

        let forToDo = await nook.askForAccess(for: .todo, at: moment)
        let onlyReminders: Set<NookEventKitPermission> = [.reminders]
        #expect(forToDo == onlyReminders)
        #expect(reminders.requestCount == Self.once)

        // Shown again, turned on again: both are answered now.
        let again = await nook.askForAccess(for: .calendar, at: moment)
        let none: Set<NookEventKitPermission> = []
        #expect(again == none)
        #expect(calendar.requestCount == Self.once)
    }

    @Test func aToDoWidgetOnNotionLeavesRemindersAlone() async {
        let calendar = FakeEventKitPermission(status: .notDetermined)
        let reminders = FakeEventKitPermission(status: .notDetermined)
        let nook = makeNook(calendar: calendar, reminders: reminders, todoSource: .notion)
        nook.allowsAccessRequests = true

        await nook.askForAccess(for: .todo, at: .shown)
        await nook.askForAccess(for: .todo, at: .turnedOn)

        #expect(reminders.requestCount == Self.never)
        #expect(calendar.requestCount == Self.never)
    }

    @Test func aWidgetWithNoPermissionAsksForNothing() async {
        let calendar = FakeEventKitPermission(status: .notDetermined)
        let reminders = FakeEventKitPermission(status: .notDetermined)
        let nook = makeNook(calendar: calendar, reminders: reminders)
        nook.allowsAccessRequests = true

        for kind in NookWidgetKind.allCases where kind != .calendar && kind != .todo {
            await nook.askForAccess(for: kind, at: .shown)
            await nook.askForAccess(for: kind, at: .turnedOn)
        }

        #expect(calendar.requestCount == Self.never)
        #expect(reminders.requestCount == Self.never)
    }

    @Test func nothingInViewMeansNothingAsked() async {
        let calendar = FakeEventKitPermission(status: .notDetermined)
        let reminders = FakeEventKitPermission(status: .notDetermined)
        let nook = makeNook(calendar: calendar, reminders: reminders)
        nook.allowsAccessRequests = true
        // What the app model answers while the island is closed, on the
        // agents page, or open only by the boot animation.
        nook.widgetsInUserView = { [] }

        #expect(nook.widgetsCameIntoView() == nil)

        #expect(calendar.requestCount == Self.never)
        #expect(reminders.requestCount == Self.never)
    }

    // MARK: The live island

    @Test func theAppModelShowsNoTilesToAnyoneWhileClosedOrBootOpened() {
        let model = AppModel(defaults: MemoryDefaults())
        let none: Set<NookWidgetKind> = []
        #expect(model.nookWidgetsInUserView == none)

        model.notchStatus = .opened
        model.notchOpenReason = .boot
        #expect(model.nookWidgetsInUserView == none)

        // A real model in a test was never started, which is what keeps
        // these state changes from asking macOS for anything.
        #expect(!model.nook.allowsAccessRequests)
    }

    // MARK: What the tour says

    @Test func theTourNoLongerSaysTheCalendarIsAskedForAtLaunch() throws {
        for language in HangoverBrandTests.languages {
            let table = try HangoverBrandTests.table(language)
            let note = try #require(table["onboarding.permissions.calendar.note"], "\(language) has no calendar note")
            #expect(!note.isEmpty)
        }
        let english = try HangoverBrandTests.table("en")
        let note = try #require(english["onboarding.permissions.calendar.note"])
        #expect(!note.contains("asks about these when"))
        #expect(note.contains("first time the calendar widget is shown"))
        #expect(note.contains("Neither is asked for when Hangover starts"))
    }
}
