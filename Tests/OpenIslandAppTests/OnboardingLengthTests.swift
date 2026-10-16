import Foundation
import OpenIslandCore
import Testing
@testable import OpenIslandApp

// The tour's three lengths: the page list of each, the question that picks
// one, the counter, the way a last page carries on to a longer tour, and
// what a finished tour records. No window, no camera, no network, and the
// store is a throwaway.

// MARK: - The page list is a pure function of the length

struct OnboardingLengthPageListTests {
    private static let main: [OnboardingPage] = [
        .welcome, .length, .purpose, .opening, .closed, .agents, .widgets, .features, .layout, .arrange,
        .todos, .notes, .weather, .opened, .look, .permissions, .integrations, .tips, .done,
    ]
    private static let extras: [OnboardingPage] = [
        .mirror, .booth, .weatherCard, .record, .convert, .lights, .accent, .power, .volume, .usage, .quiet, .phone,
        .screens, .sounds, .links, .startup, .updates,
    ]

    @Test func theShortTourIsTheEssentialsInOrder() {
        #expect(OnboardingPage.shown(length: .short, agentsEnabled: true) == [
            .welcome, .length, .purpose, .opening, .closed, .widgets, .permissions, .done,
        ])
        #expect(OnboardingPage.shown(length: .short, agentsEnabled: false) == [
            .welcome, .length, .purpose, .opening, .closed, .widgets, .permissions, .done,
        ])
    }

    /// The permissions page is walked while a widget that makes macOS ask is
    /// on the page, and while the agents are on, for its Automation row. The
    /// other switches do not touch the short tour.
    @Test func theShortTourWalksThePermissionsPageForAWidgetThatMakesMacOSAskOrForAgents() {
        let nothingAsks = OnboardingPage.shown(length: .short, agentsEnabled: false, hasPermissionWidget: false)
        #expect(nothingAsks == [.welcome, .length, .purpose, .opening, .closed, .widgets, .done])

        let widgetOnly = OnboardingPage.shown(length: .short, agentsEnabled: false, hasPermissionWidget: true)
        #expect(widgetOnly.contains(.permissions))
        // An agents user whose widgets ask for nothing still sees what the agents ask for.
        let agentsOnly = OnboardingPage.shown(length: .short, agentsEnabled: true, hasPermissionWidget: false)
        #expect(agentsOnly == [.welcome, .length, .purpose, .opening, .closed, .widgets, .permissions, .done])
        #expect(OnboardingGrant.shown(agentsEnabled: true).contains(.automation))

        for agents in [true, false] {
            for todo in [true, false] {
                for notes in [true, false] {
                    for weather in [true, false] {
                        let pages = OnboardingPage.shown(
                            length: .short, agentsEnabled: agents, hasTodoWidget: todo,
                            hasNotesWidget: notes, hasWeatherWidget: weather
                        )
                        #expect(pages.count == 8, "agents \(agents), to-dos \(todo), notes \(notes), weather \(weather)")
                    }
                }
            }
        }
    }

    @Test func theShortTourHasEightPagesAtMost() {
        for permission in [true, false] {
            for agents in [true, false] {
                let pages = OnboardingPage.shown(length: .short, agentsEnabled: agents, hasPermissionWidget: permission)
                #expect(pages.count <= 8)
            }
        }
    }

    @Test func theMainTourIsTodaysListPlusTheQuestion() {
        #expect(OnboardingPage.shown(length: .medium, agentsEnabled: true) == Self.main)
        #expect(OnboardingPage.shown(agentsEnabled: true) == Self.main, "the main tour is the default")
        // Today's list, without the question, is what the tour was before.
        #expect(Self.main.filter { $0 != .length } == [
            .welcome, .purpose, .opening, .closed, .agents, .widgets, .features, .layout, .arrange,
            .todos, .notes, .weather, .opened, .look, .permissions, .integrations, .tips, .done,
        ])
        // The permissions rule is the short tour's alone.
        #expect(OnboardingPage.shown(length: .medium, agentsEnabled: true, hasPermissionWidget: false) == Self.main)
        #expect(OnboardingPage.shown(length: .long, agentsEnabled: true, hasPermissionWidget: false).contains(.permissions))
    }

    @Test func theLongTourIsTheMainTourAndSeventeenPagesBeforeTheClosingPages() {
        let long = OnboardingPage.shown(length: .long, agentsEnabled: true)
        let expected = Array(Self.main.prefix(15)) + Self.extras + Array(Self.main.suffix(4))
        #expect(long == expected)
        #expect(long == OnboardingPage.allCases)
        #expect(long.count == Self.main.count + 17)
        #expect(Set(Self.main).isSubset(of: long))
        // The main tour's pages keep their order inside the long one.
        #expect(long.filter { !Self.extras.contains($0) } == Self.main)
    }

    @Test func theLongPagesThatAreAboutAgentsLeaveWithTheAgents() {
        let long = OnboardingPage.shown(length: .long, agentsEnabled: false)
        #expect(long.filter(\.isLongOnly) == [
            .mirror, .booth, .weatherCard, .record, .convert, .lights, .accent, .power, .volume, .screens, .sounds, .links,
            .startup, .updates,
        ])
        #expect(!long.contains(.agents))
        #expect(OnboardingPage.usage.isAgentsOnly && OnboardingPage.quiet.isAgentsOnly && OnboardingPage.phone.isAgentsOnly)
        #expect(OnboardingPage.allCases.filter(\.isAgentsOnly) == [.agents, .usage, .quiet, .phone])
    }

    @Test func eachLengthHoldsTheOneBefore() {
        for agents in [true, false] {
            let short = Set(OnboardingPage.shown(length: .short, agentsEnabled: agents))
            let medium = Set(OnboardingPage.shown(length: .medium, agentsEnabled: agents))
            let long = Set(OnboardingPage.shown(length: .long, agentsEnabled: agents))
            #expect(short.isSubset(of: medium))
            #expect(medium.isSubset(of: long))
        }
    }

    @Test func beforeTheQuestionIsAnsweredOnlyTheCertainPagesAreKnown() {
        #expect(OnboardingPage.shown(length: nil, agentsEnabled: true) == [.welcome, .length])
        #expect(OnboardingPage.shown(length: nil, agentsEnabled: false) == [.welcome, .length])
    }

    @Test func theLongPagesSitBetweenTheChoicesAndTheClosingPagesInTheLastChapter() {
        #expect(OnboardingPage.look.next == .mirror)
        #expect(OnboardingPage.updates.next == .permissions)
        for page in Self.extras {
            #expect(page.chapter == .know)
            #expect(!page.isLive, "\(page) uses the wide window")
            #expect(page.isLongOnly && page.shortestLength == .long)
            #expect(page.more != nil)
        }
        #expect(OnboardingPage.allCases.filter(\.isLongOnly) == Self.extras)
        #expect(OnboardingPage.length.chapter == .basics)
        #expect(OnboardingPage.length.shortestLength == .short)
    }

    @Test func theLengthsAreOrderedAndEachOffersTheLongerOnes() {
        #expect(OnboardingLength.short < .medium && OnboardingLength.medium < .long)
        #expect(OnboardingLength.short.longer == [.medium, .long])
        #expect(OnboardingLength.medium.longer == [.long])
        #expect(OnboardingLength.long.longer.isEmpty)
    }

    @Test func theRecapOfTheShortTourHoldsOnlyWhatItAsked() {
        #expect(OnboardingRecapRow.shown(length: .short, agentsEnabled: true) == [.opens, .closed, .agents, .widgets])
        #expect(OnboardingRecapRow.shown(length: .short, agentsEnabled: false) == [.opens, .closed, .widgets])
        #expect(OnboardingRecapRow.shown(length: .medium, agentsEnabled: true) == OnboardingRecapRow.standard)
        #expect(OnboardingRecapRow.shown(agentsEnabled: true) == OnboardingRecapRow.standard)
    }
}

// MARK: - The question and the counter

@MainActor
struct OnboardingLengthQuestionTests {
    private static func tour(
        startingAt page: OnboardingPage = .welcome,
        state: OnboardingState = OnboardingState(),
        onEnd: @escaping (OnboardingOutcome) -> Void = { _ in }
    ) -> OnboardingTour {
        OnboardingTour(startingAt: page, state: { state }, onEnd: onEnd)
    }

    @Test func nextWaitsOnTheQuestionUntilOneCardIsPicked() {
        let tour = Self.tour()
        tour.next()
        #expect(tour.page == .length)
        #expect(!tour.canGoNext)
        #expect(!tour.isLastPage, "the question is the end of the list the tour knows, not of the tour")

        tour.next()
        #expect(tour.page == .length)
        #expect(tour.flow.outcome == nil)

        tour.actions.chooseLength(.short)
        #expect(tour.canGoNext)
        tour.next()
        #expect(tour.page == .purpose)
    }

    @Test func aPageAfterTheQuestionCannotBeReachedBeforeItIsAnswered() {
        let tour = Self.tour()
        tour.go(to: .widgets)
        #expect(tour.page == .welcome)
        tour.next()
        tour.go(to: .done)
        #expect(tour.page == .length)
        #expect(tour.pages == [.welcome, .length])
    }

    @Test func aPickOnAnotherPageIsLeftAlone() {
        let tour = Self.tour()
        tour.actions.chooseLength(.long)
        #expect(tour.length == nil)
        #expect(tour.stepCount == nil)
    }

    @Test func goingBackToTheQuestionLetsTheUserChangeItAndThePagesFollow() {
        let tour = Self.tour()
        tour.answerQuestion(.short)
        #expect(tour.pages == OnboardingPage.shown(length: .short, agentsEnabled: true, hasWeatherWidget: false))

        tour.next()
        tour.next()
        #expect(tour.page == .opening)
        tour.back()
        tour.back()
        #expect(tour.page == .length)
        #expect(tour.state.length == .short)

        tour.actions.chooseLength(.long)
        #expect(tour.state.length == .long)
        #expect(tour.pages == OnboardingPage.shown(length: .long, agentsEnabled: true, hasWeatherWidget: false))
        tour.go(to: .look)
        tour.next()
        #expect(tour.page == .mirror, "the pages after the question follow the new pick")
    }

    @Test func theCounterHasNoTotalBeforeTheChoiceAndCountsTheChosenListAfter() {
        let tour = Self.tour()
        #expect(tour.step == 1 && tour.stepCount == nil)
        tour.next()
        #expect(tour.step == 2 && tour.stepCount == nil, "the question has no total either")

        tour.actions.chooseLength(.short)
        #expect(tour.step == 2 && tour.stepCount == 8, "right after the choice, the position in the chosen list")
        #expect(tour.stepCount == tour.pages.count)
        tour.go(to: .welcome)
        #expect(tour.step == 1 && tour.stepCount == 8, "back at the first page the total stays known")

        tour.go(to: .done)
        #expect(tour.step == 8 && tour.stepCount == 8, "at the last page the position is the total")
        #expect(tour.isLastPage)
    }

    @Test func theCounterOfEachPathEndsOnItsTotal() {
        for (length, total) in [(OnboardingLength.short, 8), (.medium, 18), (.long, 35)] {
            let tour = Self.tour()
            tour.answerQuestion(length)
            #expect(tour.stepCount == total, "\(length)")
            while !tour.isLastPage { tour.next() }
            #expect(tour.step == total, "\(length)")
            #expect(tour.page == .done)
        }
    }

    /// The total is the list as it stands now, every time. A page that
    /// drops out of the list drops out of the total at once.
    @Test func theCounterNeverCountsAPageThatWillNotBeShown() {
        var widgets = Set(NookWidgetKind.defaultEnabled)
        var agents = true
        let tour = OnboardingTour(startingAt: .welcome, state: {
            OnboardingState(agentsEnabled: agents, enabledWidgets: widgets)
        })
        tour.answerQuestion(.medium)
        #expect(tour.stepCount == 18)

        agents = false
        #expect(tour.stepCount == 17)
        widgets.insert(.weather)
        #expect(tour.stepCount == 18)
        widgets.remove(.todo)
        #expect(tour.stepCount == 17)
        #expect(tour.stepCount == tour.pages.count)
        #expect(!tour.pages.contains(.todos) && !tour.pages.contains(.agents))
    }

    @Test func aTourThatStartsPastTheQuestionWalksTheMainTour() {
        let tour = Self.tour(startingAt: .agents)
        #expect(tour.length == .medium)
        #expect(tour.stepCount == 18)
        #expect(tour.page == .agents)
        #expect(tour.canGoNext)
        #expect(tour.pages == OnboardingPage.shown(length: .medium, agentsEnabled: true, hasWeatherWidget: false))
    }

    @Test func aStateHandedInWithALengthIsKept() {
        var state = OnboardingState()
        state.length = .short
        let tour = Self.tour(startingAt: .opening, state: state)
        #expect(tour.length == .short)
        #expect(tour.pages.count == 8)
        #expect(tour.state.length == .short)
    }

    /// The tour turns the widgets on the page into the short tour's
    /// permissions rule. The page that is up is the display's own, which means
    /// a widget that is switched on and left off this display's page does not
    /// count.
    @Test func theShortToursPermissionsPageFollowsTheWidgetsOnThePageAndTheAgents() {
        func pages(
            widgets: Set<NookWidgetKind>, agents: Bool, onPage: [NookWidgetKind]? = nil, length: OnboardingLength = .short
        ) -> [OnboardingPage] {
            var state = OnboardingState(agentsEnabled: agents, enabledWidgets: widgets)
            state.length = length
            state.nookPlacements = onPage.map { kinds in kinds.map { NookWidgetPlacement(kind: $0, size: .medium) } }
            return OnboardingTour.pages(for: state)
        }
        let quiet: Set<NookWidgetKind> = [.media, .notes, .tray, .timer, .weather]

        #expect(!pages(widgets: quiet, agents: false).contains(.permissions))
        for kind in OnboardingGrant.widgetsAskingMacOS {
            #expect(pages(widgets: quiet.union([kind]), agents: false).contains(.permissions), "\(kind)")
        }
        #expect(OnboardingGrant.widgetsAskingMacOS == [.mirror, .calendar, .todo, .record])
        #expect(pages(widgets: quiet, agents: true).contains(.permissions), "the agents ask too")

        // On the display's page counts. Switched on and left off it does not.
        #expect(pages(widgets: [.media], agents: false, onPage: [.media, .calendar]).contains(.permissions))
        let leftOff = pages(widgets: quiet.union([.mirror, .calendar, .todo]), agents: false, onPage: [.media])
        #expect(!leftOff.contains(.permissions))

        // The longer tours always walk it.
        for length in [OnboardingLength.medium, .long] {
            #expect(pages(widgets: quiet, agents: false, length: length).contains(.permissions))
        }
    }

    @Test func theCardsCountThePagesOfTheirOwnList() {
        let state = OnboardingState()
        #expect(OnboardingLengthPage.stepCount(.short, in: state) == 8)
        #expect(OnboardingLengthPage.stepCount(.medium, in: state) == 18)
        #expect(OnboardingLengthPage.stepCount(.long, in: state) == 35)

        var nookOnly = state
        nookOnly.agentsEnabled = false
        #expect(OnboardingLengthPage.stepCount(.medium, in: nookOnly) == 17)
        #expect(OnboardingLengthPage.stepCount(.long, in: nookOnly) == 31)
        for length in OnboardingLength.allCases {
            var chosen = state
            chosen.length = length
            #expect(OnboardingLengthPage.stepCount(length, in: state) == OnboardingTour.pages(for: chosen).count)
        }
    }
}

// MARK: - A page asked for from outside the tour

@MainActor
struct OnboardingOutsideRequestTests {
    private static func tour(agents: Bool = true) -> OnboardingTour {
        OnboardingTour(state: { OnboardingState(agentsEnabled: agents) })
    }

    @Test func theIslandsHintOpensTheAgentsPageOnTheShortTour() {
        let tour = Self.tour()
        tour.answerQuestion(.short)
        #expect(!tour.pages.contains(.agents))

        tour.show(.agents)

        #expect(tour.page == .agents)
        #expect(tour.length == .medium, "the shortest length that has the page")
        #expect(tour.pages.contains(.agents))
        tour.next()
        #expect(tour.page == .widgets)
    }

    @Test func theHintWorksBeforeTheQuestionIsAnswered() {
        let tour = Self.tour()
        #expect(tour.length == nil)

        tour.show(.agents)

        #expect(tour.page == .agents)
        #expect(tour.length == .medium)
        #expect(tour.stepCount == 18)
    }

    @Test func theHintBringsBackAPageACarryOnLeftOut() {
        let tour = Self.tour()
        tour.answerQuestion(.medium)
        while !tour.isLastPage { tour.next() }
        tour.carryOn(to: .long)
        #expect(!tour.pages.contains(.agents), "the agents page was seen")

        tour.show(.agents)

        #expect(tour.page == .agents)
        #expect(tour.length == .long, "a longer tour is not shortened")
        tour.next()
        #expect(tour.page == .mirror)
    }

    @Test func aPageTheTourHasIsJustGoneTo() {
        let tour = Self.tour()
        tour.answerQuestion(.long)
        tour.show(.widgets)
        #expect(tour.page == .widgets)
        #expect(tour.length == .long)

        let short = Self.tour()
        short.answerQuestion(.short)
        short.show(.widgets)
        #expect(short.page == .widgets)
        #expect(short.length == .short, "the page is in the short tour already")
    }

    @Test func aPageTheAppTakesOutStaysOutAndNothingIsAnswered() {
        let tour = Self.tour(agents: false)
        tour.show(.agents)
        #expect(tour.page == .welcome)
        #expect(tour.length == nil)

        tour.answerQuestion(.short)
        tour.show(.agents)
        #expect(tour.page == .length)
        #expect(tour.length == .short)
    }

    @Test func theWindowAsksThroughThisDoor() throws {
        let source = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Onboarding/OnboardingWindowController.swift")
        #expect(source.contains("if page != .welcome { tour.show(page) }"))
        #expect(!source.contains("tour.go(to: page)"))
    }
}

// MARK: - Carrying on to a longer tour

@MainActor
struct OnboardingCarryOnTests {
    private static func tour(
        store: AgentIntentStore? = nil,
        startingAt page: OnboardingPage = .welcome
    ) -> OnboardingTour {
        if let store {
            return OnboardingTour.recording(in: store, startingAt: page, state: { OnboardingState() })
        }
        return OnboardingTour(startingAt: page, state: { OnboardingState() })
    }

    private static func store() -> AgentIntentStore {
        AgentIntentStore(defaults: MemoryDefaults())
    }

    /// Presses Next until the tour has ended, writing down each page.
    private static func walkToTheEnd(_ tour: OnboardingTour) -> [OnboardingPage] {
        var seen = [tour.page]
        while !tour.flow.hasEnded {
            let before = tour.page
            tour.next()
            if tour.flow.hasEnded { break }
            guard tour.page != before else { break }
            seen.append(tour.page)
        }
        return seen
    }

    private static func atTheLastPage(of length: OnboardingLength, store: AgentIntentStore? = nil) -> OnboardingTour {
        let tour = Self.tour(store: store)
        tour.answerQuestion(length)
        while !tour.isLastPage { tour.next() }
        return tour
    }

    @Test func onlyALastPageOffersALongerTour() {
        let tour = Self.tour()
        #expect(tour.carryOnLengths.isEmpty)
        tour.answerQuestion(.short)
        #expect(tour.carryOnLengths.isEmpty)

        #expect(Self.atTheLastPage(of: .short).carryOnLengths == [.medium, .long])
        #expect(Self.atTheLastPage(of: .medium).carryOnLengths == [.long])
        #expect(Self.atTheLastPage(of: .long).carryOnLengths.isEmpty)
    }

    @Test func theShortTourCarriesOnToTheMainTourWithExactlyThePagesItSkipped() {
        let tour = Self.atTheLastPage(of: .short)
        #expect(tour.page == .done)

        tour.carryOn(to: .medium)
        #expect(tour.length == .medium)
        #expect(tour.page == .agents, "the first page the short tour skipped")

        let followed = Self.walkToTheEnd(tour)
        let skipped = OnboardingPage.shown(length: .medium, agentsEnabled: true, hasWeatherWidget: false)
            .filter { !OnboardingPage.shown(length: .short, agentsEnabled: true).contains($0) }
        #expect(followed == skipped)
        #expect(followed == [.agents, .features, .layout, .arrange, .todos, .notes, .opened, .look, .integrations, .tips])
        #expect(tour.flow.outcome == .finished)
    }

    @Test func theShortTourCarriesOnToEverythingWithoutShowingAPageTwice() {
        let tour = Self.atTheLastPage(of: .short)
        let seenBefore = Set(tour.pages)

        tour.carryOn(to: .long)
        let followed = Self.walkToTheEnd(tour)

        #expect(tour.length == .long)
        #expect(followed == [
            .agents, .features, .layout, .arrange, .todos, .notes, .opened, .look,
            .mirror, .booth, .weatherCard, .record, .convert, .lights, .accent, .power, .volume, .usage, .quiet, .phone,
            .screens, .sounds, .links, .startup, .updates,
            .integrations, .tips,
        ])
        #expect(seenBefore.isDisjoint(with: followed))
        #expect(Set(followed).count == followed.count)
    }

    @Test func theMainTourCarriesOnToEverythingWithOnlyTheLongPages() {
        let tour = Self.atTheLastPage(of: .medium)
        #expect(tour.page == .done)

        tour.carryOn(to: .long)
        #expect(tour.page == .mirror)
        let followed = Self.walkToTheEnd(tour)
        #expect(followed == [
            .mirror, .booth, .weatherCard, .record, .convert, .lights, .accent, .power, .volume, .usage, .quiet, .phone,
            .screens, .sounds, .links, .startup, .updates,
        ])
        #expect(tour.flow.outcome == .finished)
    }

    @Test func theCounterAfterCarryingOnCountsTheRestOfTheTour() {
        let tour = Self.atTheLastPage(of: .short)
        tour.carryOn(to: .medium)
        #expect(tour.step == 1)
        #expect(tour.stepCount == 10, "only the pages still to show")
        #expect(tour.isFirstPage)
        #expect(tour.pages.count == tour.stepCount)
        while !tour.isLastPage { tour.next() }
        #expect(tour.step == 10)
    }

    @Test func carryingOnWorksOnlyFromALastPageAndToALongerTour() {
        let early = Self.tour()
        early.answerQuestion(.short)
        early.carryOn(to: .long)
        #expect(early.length == .short)
        #expect(early.page == .length)

        let medium = Self.atTheLastPage(of: .medium)
        medium.carryOn(to: .short)
        medium.carryOn(to: .medium)
        #expect(medium.length == .medium)
        #expect(medium.page == .done)

        let long = Self.atTheLastPage(of: .long)
        long.carryOn(to: .long)
        #expect(long.page == .done && long.length == .long)
    }

    /// A tour whose pages were all seen is not offered, which would end the
    /// tour on a list with nothing in it.
    @Test func carryingOnIsNotOfferedToATourWithNothingLeftToShow() {
        let tour = Self.atTheLastPage(of: .medium)
        tour.back()
        tour.go(to: .length)
        tour.chooseLength(.short)
        tour.go(to: .done)
        #expect(tour.isLastPage)
        #expect(tour.length == .short)
        #expect(tour.carryOnLengths == [.long], "every page of the main tour was seen")

        tour.carryOn(to: .medium)
        #expect(tour.length == .short)
        #expect(tour.page == .done)
        #expect(tour.stepCount == 8)

        let everything = Self.atTheLastPage(of: .long)
        everything.go(to: .length)
        everything.chooseLength(.short)
        everything.go(to: .done)
        #expect(everything.isLastPage)
        #expect(everything.carryOnLengths.isEmpty)
        #expect(everything.pages.count == 8, "the list was left whole")
    }

    @Test func theLastPagesButtonsGoThroughTheToursOwnDoor() {
        let tour = Self.atTheLastPage(of: .short)
        tour.actions.carryOn(.long)
        #expect(tour.length == .long)
        #expect(tour.page == .agents)
    }

    /// A dot can jump over pages. The pages it jumped over were not seen,
    /// which is why carrying on shows them.
    @Test func carryingOnShowsAPageADotJumpedOver() {
        let tour = Self.tour()
        tour.answerQuestion(.short)
        tour.go(to: .done)
        #expect(tour.isLastPage)

        tour.carryOn(to: .medium)
        let followed = Self.walkToTheEnd(tour)
        #expect(followed.starts(with: [.purpose, .opening, .closed, .agents, .widgets]))
        #expect(!followed.contains(.welcome) && !followed.contains(.length) && !followed.contains(.done))
    }

    // MARK: What the tour remembers

    @Test(arguments: OnboardingLength.allCases)
    func finishingEachPathCountsAsTheTourAndRecordsWhichPath(length: OnboardingLength) {
        let store = Self.store()
        let tour = Self.atTheLastPage(of: length, store: store)
        #expect(store.welcomeTourLength == nil, "nothing is recorded before the end")
        #expect(!store.welcomeTourEnded)

        tour.next()

        #expect(tour.flow.outcome == .finished)
        #expect(store.welcomeTourEnded)
        #expect(store.firstLaunchCompleted)
        #expect(store.welcomeTourLength == length.rawValue)
        #expect(!OnboardingGate.showsByItself(.init(isCompleted: store.welcomeTourEnded, isHarness: false)))
    }

    @Test func aTourFinishedAfterCarryingOnRecordsTheLengthItEndedOn() {
        let store = Self.store()
        let tour = Self.atTheLastPage(of: .short, store: store)
        tour.carryOn(to: .medium)
        #expect(store.welcomeTourLength == nil)

        _ = Self.walkToTheEnd(tour)

        #expect(store.welcomeTourLength == "medium")
        #expect(store.welcomeTourEnded)
    }

    @Test func aSkippedTourCountsAsSeenAndRecordsTheLongestLengthItFinished() {
        let early = Self.store()
        let skippedEarly = Self.tour(store: early)
        skippedEarly.answerQuestion(.long)
        skippedEarly.skip()
        #expect(early.welcomeTourEnded && early.firstLaunchCompleted)
        #expect(early.welcomeTourLength == nil, "nothing was finished")

        let late = Self.store()
        let carried = Self.atTheLastPage(of: .short, store: late)
        carried.carryOn(to: .long)
        carried.next()
        carried.skip()
        #expect(late.welcomeTourEnded)
        #expect(late.welcomeTourLength == "short", "the short tour was finished before it carried on")
    }

    @Test func aTourSkippedBeforeTheQuestionRecordsNoLength() {
        let store = Self.store()
        let tour = Self.tour(store: store)
        tour.skip()
        #expect(store.welcomeTourEnded)
        #expect(store.welcomeTourLength == nil)
    }

    @Test func aTourThatStartedPastTheQuestionRecordsTheMainTourWhenFinished() {
        let store = Self.store()
        let tour = Self.tour(store: store, startingAt: .tips)
        tour.next()
        tour.next()
        #expect(tour.flow.outcome == .finished)
        #expect(store.welcomeTourLength == "medium")
    }

    @Test func aLaterTourThatIsSkippedLeavesTheEarlierRecordAlone() {
        let store = Self.store()
        store.welcomeTourLength = "short"
        let tour = Self.tour(store: store)
        tour.skip()
        #expect(store.welcomeTourLength == "short")
    }
}
