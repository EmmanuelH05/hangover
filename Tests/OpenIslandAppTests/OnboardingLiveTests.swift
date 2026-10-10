import CoreGraphics
import OpenIslandCore
import Testing
@testable import OpenIslandApp

// The tour uses the real island (D44): the hold in the pointer rules, the
// tour's own moves that turn the hold on and off, the window's frame, and
// the arrange page's walk-through. Nothing here opens a window or lights the
// screen.

// MARK: - The hold in the click rules

struct IslandTourHoldClickTests {
    private static func context(
        status: NotchStatus = .opened,
        reason: NotchOpenReason? = .click,
        inClosedSurface: Bool = false,
        inExpanded: Bool,
        onNotch: Bool = false,
        blocksDismiss: Bool = false,
        picker: Bool = false,
        holds: Bool
    ) -> IslandClickContext {
        IslandClickContext(
            status: status,
            reason: reason,
            isInClosedSurface: inClosedSurface,
            isInExpandedArea: inExpanded,
            isOnNotch: onNotch,
            blocksDismiss: blocksDismiss,
            hasOpenPicker: picker,
            holdsOpenForTour: holds
        )
    }

    @Test(arguments: [NotchOpenReason.click, .hover, .notification, .boot])
    func withTheHoldNoClickOnTheOpenIslandOrOutsideItClosesIt(reason: NotchOpenReason) {
        let places: [(inExpanded: Bool, onNotch: Bool)] = [(false, false), (true, false), (true, true)]
        for place in places {
            for blocks in [false, true] {
                let action = IslandPointerRules.clickAction(Self.context(
                    reason: reason, inExpanded: place.inExpanded, onNotch: place.onNotch,
                    blocksDismiss: blocks, holds: true
                ))
                #expect(action == .none, "\(reason) \(place) blocks \(blocks) gave \(action)")
            }
        }
    }

    @Test func withTheHoldAClickOutsideAndAClickOnTheNotchLeaveAnIslandWithNoReasonOpen() {
        #expect(IslandPointerRules.clickAction(Self.context(reason: nil, inExpanded: false, holds: true)) == .none)
        #expect(IslandPointerRules.clickAction(Self.context(reason: nil, inExpanded: true, onNotch: true, holds: true)) == .none)
    }

    @Test func withTheHoldOffTheRulesAreAsTheyWere() {
        // Outside the open island: dismiss, or hold for a decision.
        #expect(IslandPointerRules.clickAction(Self.context(inExpanded: false, holds: false)) == .dismiss)
        #expect(IslandPointerRules.clickAction(Self.context(inExpanded: false, blocksDismiss: true, holds: false)) == .holdForDecision)
        #expect(IslandPointerRules.clickAction(Self.context(inExpanded: false, picker: true, holds: false)) == .none)
        // Inside a hover-opened island: pin. On the notch of a click-opened one: close.
        #expect(IslandPointerRules.clickAction(Self.context(reason: .hover, inExpanded: true, holds: false)) == .pin)
        #expect(IslandPointerRules.clickAction(Self.context(inExpanded: true, onNotch: true, holds: false)) == .closeFromNotch)
        #expect(IslandPointerRules.clickAction(Self.context(inExpanded: true, holds: false)) == .none)
        #expect(IslandPointerRules.clickAction(Self.context(reason: .notification, inExpanded: true, holds: false)) == .none)
        // The closed island opens, and the flag is off by default.
        #expect(IslandPointerRules.clickAction(Self.context(status: .closed, reason: nil, inClosedSurface: true, inExpanded: false, holds: false)) == .open)
        #expect(IslandClickContext(
            status: .opened, reason: .click, isInClosedSurface: false,
            isInExpandedArea: false, isOnNotch: false, blocksDismiss: false
        ).holdsOpenForTour == false)
    }

    @Test func aClosedIslandStillOpensUnderTheHold() {
        let action = IslandPointerRules.clickAction(Self.context(
            status: .closed, reason: nil, inClosedSurface: true, inExpanded: false, holds: true
        ))
        #expect(action == .open)
    }

    @Test func thePointerLeavingClosesOnlyWhenTheOtherRulesSayAndTheHoldIsOff() {
        for other in [false, true] {
            #expect(IslandPointerRules.pointerLeaveCloses(otherRules: other, holdsOpenForTour: true) == false)
            #expect(IslandPointerRules.pointerLeaveCloses(otherRules: other, holdsOpenForTour: false) == other)
        }
    }
}

// MARK: - The hold on the overlay

@MainActor
struct IslandTourHoldOverlayTests {
    @Test func aHoverOpenedIslandDoesNotFollowThePointerWhileHeld() {
        let model = AppModel(defaults: MemoryDefaults())
        model.notchStatus = .opened
        model.notchOpenReason = .hover
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave)

        model.setTourHoldsIslandOpen(true)
        #expect(model.tourHoldsIslandOpen)
        #expect(!model.overlay.shouldAutoCollapseOnMouseLeave)
        #expect(model.notchStatus == .opened)

        model.setTourHoldsIslandOpen(false)
        #expect(!model.tourHoldsIslandOpen)
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave, "with the hold off the island follows its own rules again")
        #expect(model.notchStatus == .opened, "an island the hold did not open is left as it was")
    }

    @Test func aCloseAskedForWhileHeldLeavesTheNookPageOpen() {
        let model = AppModel(defaults: MemoryDefaults())
        model.notchStatus = .opened
        model.notchOpenReason = .click
        model.setTourHoldsIslandOpen(true)

        model.notchClose()
        model.toggleOverlay()

        #expect(model.notchStatus == .opened)
    }

    @Test func theHoldNeverTakesTheKeyboardFromTheTour() {
        #expect(OverlayPanelController.shouldActivatePanel(for: .click))
        #expect(!OverlayPanelController.shouldActivatePanel(for: .click, holdsOpenForTour: true))
        #expect(!OverlayPanelController.shouldActivatePanel(for: .hover, holdsOpenForTour: true))
    }
}

// MARK: - The tour turns the hold on and off

@MainActor
struct OnboardingHoldTests {
    /// The calls the tour made to hold the island, in order.
    private final class Calls {
        var holds: [Bool] = []
    }

    private static func tour(
        startingAt page: OnboardingPage = .welcome,
        calls: Calls,
        onEnd: @escaping (OnboardingOutcome) -> Void = { _ in }
    ) -> OnboardingTour {
        var actions = OnboardingActions()
        actions.holdIsland = { calls.holds.append($0) }
        return OnboardingTour(startingAt: page, state: { OnboardingState() }, actions: actions, onEnd: onEnd)
    }

    @Test func theHoldFollowsThePageThatIsUp() {
        let calls = Calls()
        let tour = Self.tour(calls: calls)
        tour.go(to: .purpose)
        #expect(calls.holds.isEmpty, "a page that is not live holds nothing")

        tour.go(to: .widgets)
        tour.go(to: .layout)
        tour.next()
        #expect(tour.page == .arrange)
        #expect(calls.holds == [true], "the hold is asked for once while live pages follow each other")

        tour.go(to: .look)
        #expect(calls.holds == [true, false])
        tour.back()
        tour.back()
        #expect(tour.page == .notes)
        #expect(calls.holds == [true, false, true])
    }

    @Test func aTourStartedOnALivePageHoldsOnlyOnceTheWindowSaysSo() {
        let calls = Calls()
        let tour = Self.tour(startingAt: .widgets, calls: calls)
        #expect(calls.holds.isEmpty, "building a tour opens nothing")

        tour.syncIsland()
        tour.syncIsland()
        #expect(calls.holds == [true])
    }

    @Test func theHoldGoesOffWhenTheTourIsFinished() {
        let calls = Calls()
        let tour = Self.tour(calls: calls)
        tour.go(to: .opened)
        tour.go(to: .done)
        #expect(calls.holds == [true, false])
        tour.next()
        #expect(tour.flow.outcome == .finished)
        #expect(calls.holds == [true, false])
    }

    @Test func theHoldGoesOffWhenTheTourIsSkippedFromALivePage() {
        let calls = Calls()
        var ended: [OnboardingOutcome] = []
        let tour = Self.tour(calls: calls) { ended.append($0) }
        tour.go(to: .arrange)
        #expect(calls.holds == [true])

        tour.skip()
        #expect(ended == [.skipped])
        #expect(calls.holds == [true, false])
    }

    @Test func theHoldIsGoneBeforeTheEndIsRecordedAndTheWindowClosed() {
        let calls = Calls()
        var holdsWhenEnded: [Bool] = []
        let tour = Self.tour(calls: calls) { _ in holdsWhenEnded.append(calls.holds.last ?? false) }
        tour.go(to: .todos)
        tour.skip()
        #expect(holdsWhenEnded == [false])
    }

    @Test func theWindowClosingLetsGoOfTheIslandWithoutTheTourEnding() {
        let calls = Calls()
        let tour = Self.tour(startingAt: .layout, calls: calls)
        tour.syncIsland()
        #expect(calls.holds == [true])

        tour.releaseIsland()
        tour.releaseIsland()
        #expect(calls.holds == [true, false], "letting go twice tells the app once")
        #expect(!tour.flow.hasEnded)
    }

    @Test func aTourThatIsDroppedLetsGoOfTheIsland() {
        let calls = Calls()
        do {
            let tour = Self.tour(startingAt: .opened, calls: calls)
            tour.syncIsland()
            #expect(calls.holds == [true])
        }
        #expect(calls.holds == [true, false])
    }

    @Test func theRecordedTourClosesItsWindowOnlyAfterTheIslandIsLetGo() {
        let store = AgentIntentStore(defaults: MemoryDefaults())
        let calls = Calls()
        var closedWithHold: [Bool] = []
        var actions = OnboardingActions()
        actions.holdIsland = { calls.holds.append($0) }
        let tour = OnboardingTour.recording(
            in: store, startingAt: .widgets, state: { OnboardingState() }, actions: actions
        ) { closedWithHold.append(calls.holds.last == true) }
        tour.syncIsland()

        tour.skip()

        #expect(closedWithHold == [false])
        #expect(store.welcomeTourEnded)
    }

    @Test func theLivePagesAreTheEightThatUseTheRealIsland() {
        #expect(OnboardingPage.allCases.filter(\.isLive) == [.widgets, .features, .layout, .arrange, .todos, .notes, .weather, .opened])
        #expect(!OnboardingPage.closed.isLive)
        #expect(!OnboardingPage.look.isLive)
    }
}

// MARK: - The page list

struct OnboardingArrangePageListTests {
    @Test func arrangeIsItsOwnPageRightAfterLayout() {
        let pages = OnboardingPage.allCases
        let layout = pages.firstIndex(of: .layout)
        let arrange = pages.firstIndex(of: .arrange)
        #expect(layout != nil && arrange == layout.map { $0 + 1 })
        #expect(OnboardingPage.layout.next == .arrange)
        #expect(OnboardingPage.arrange.next == .todos)
        #expect(OnboardingPage.arrange.chapter == .yours)
    }

    @Test func everyRunWalksArrangeWhateverTheSwitches() {
        for agents in [true, false] {
            for todo in [true, false] {
                #expect(OnboardingPage.shown(agentsEnabled: agents, hasTodoWidget: todo).contains(.arrange))
            }
        }
    }

    @Test func theSnapshotNamesAreStillOneToAPage() {
        let names = OnboardingPage.allCases.map(\.snapshotName)
        #expect(Set(names).count == names.count)
        #expect(OnboardingPage.arrange.snapshotName.hasSuffix("-arrange"))
    }
}

// MARK: - The window

struct OnboardingWindowFrameTests {
    private static let screen = CGRect(x: 0, y: 25, width: 1512, height: 920)

    private static func island(width: CGFloat, on screen: CGRect = Self.screen) -> CGRect {
        CGRect(x: screen.midX - width / 2, y: screen.maxY - 300, width: width, height: 300)
    }

    @Test func aPageThatIsNotLiveIsTheFullWindowCenteredOnTheScreen() {
        let frame = OnboardingWindowFrame.frame(isLive: false, screen: Self.screen, island: Self.island(width: 640))

        #expect(frame.size == OnboardingStyle.windowSize)
        #expect(frame.midX == Self.screen.midX)
        #expect(frame.midY == Self.screen.midY)
    }

    @Test func aLivePageDocksAtTheLeftEdgeAndIsCenteredUpAndDown() {
        let frame = OnboardingWindowFrame.frame(isLive: true, screen: Self.screen, island: Self.island(width: 640))

        #expect(frame.minX == Self.screen.minX + OnboardingWindowFrame.margin / 2)
        #expect(frame.midY == Self.screen.midY)
        #expect(frame.height <= Self.screen.height)
        #expect(frame.height == OnboardingWindowFrame.narrowMaxHeight)
    }

    @Test func theWidthIsTheFreeSpaceLeftOfTheIslandLessAMarginKeptBetween320And420() {
        // Island 640 wide on 1512: 436 free at the left, less the margin.
        let roomy = OnboardingWindowFrame.narrow(screen: Self.screen, island: Self.island(width: 640))
        #expect(roomy.width == 412)
        #expect(roomy.maxX <= Self.island(width: 640).minX - OnboardingWindowFrame.margin / 2)

        // A very wide room is held to 420.
        let wide = OnboardingWindowFrame.narrow(screen: Self.screen, island: Self.island(width: 300))
        #expect(wide.width == 420)

        // A narrow room is held to 320.
        let tight = OnboardingWindowFrame.narrow(screen: Self.screen, island: Self.island(width: 1100))
        #expect(tight.width == 320)
    }

    @Test func aScreenTooNarrowToFitBesideTheIslandOverlapsAsLittleAsItCanAndStaysOnScreen() {
        let small = CGRect(x: 100, y: 0, width: 800, height: 600)
        let island = Self.island(width: 700, on: small)
        let frame = OnboardingWindowFrame.narrow(screen: small, island: island)

        #expect(frame.width == 320)
        #expect(frame.minX == small.minX + OnboardingWindowFrame.margin / 2, "as far left as the screen lets it go")
        #expect(small.contains(frame))
        #expect(frame.intersects(island), "there is no room: it overlaps")
    }

    @Test func aScreenNarrowerThanTheLeastWidthStillHoldsTheWindow() {
        let tiny = CGRect(x: -300, y: 40, width: 300, height: 400)
        for live in [true, false] {
            let frame = OnboardingWindowFrame.frame(isLive: live, screen: tiny, island: Self.island(width: 200, on: tiny))
            #expect(tiny.contains(frame), "live \(live): \(frame)")
        }
    }

    @Test func aShortScreenLimitsTheHeight() {
        let short = CGRect(x: 0, y: 0, width: 1440, height: 500)
        let frame = OnboardingWindowFrame.frame(isLive: true, screen: short, island: Self.island(width: 640, on: short))

        #expect(frame.height == short.height - OnboardingWindowFrame.margin)
        #expect(short.contains(frame))
        #expect(OnboardingWindowFrame.wide(screen: short).height == short.height)
    }

    @Test func theFrameFollowsTheScreenTheIslandIsOn() {
        let other = CGRect(x: 1512, y: 0, width: 2560, height: 1415)
        let frame = OnboardingWindowFrame.frame(isLive: true, screen: other, island: Self.island(width: 760, on: other))

        #expect(other.contains(frame))
        #expect(frame.minX == other.minX + OnboardingWindowFrame.margin / 2)
        #expect(OnboardingWindowFrame.wide(screen: other).midX == other.midX)
    }
}

// MARK: - The arrange walk-through

struct OnboardingArrangeProgressTests {
    private static let start = [
        NookWidgetPlacement(kind: .media, size: .large),
        NookWidgetPlacement(kind: .todo, size: .small),
        NookWidgetPlacement(kind: .notes, size: .small),
    ]

    private static func progress(
        _ now: [NookWidgetPlacement],
        picked: NookWidgetKind = .todo,
        editing: Bool = true,
        ended: Bool = false
    ) -> OnboardingArrangeProgress {
        .reading(picked: picked, atPick: start, now: now, isEditing: editing, editingEnded: ended)
    }

    @Test func rightAfterThePickTheFirstStepIsAskedAndNothingIsDone() {
        let progress = Self.progress(Self.start)

        #expect(progress.kind == .todo && progress.isOnPage)
        #expect(OnboardingRearrangeStep.allCases.allSatisfy { !progress.isDone($0) })
        #expect(progress.current == .move)
        #expect(progress.doneSteps.isEmpty)
        #expect(!progress.needsEditing)
        #expect(progress.size == .small)
    }

    @Test func movingThePickedWidgetDoneAsksForTheResize() {
        let progress = Self.progress([Self.start[1], Self.start[0], Self.start[2]])

        #expect(progress.moved && !progress.resized && !progress.finished)
        #expect(progress.doneSteps == [.move])
        #expect(progress.current == .resize)
    }

    @Test func aWidgetThatKeepsItsPlaceDidNotMove() {
        // The other two trade places; the picked one stays first.
        let swapped = [Self.start[0], Self.start[2], Self.start[1]]
        #expect(!Self.progress(swapped, picked: .media).moved)
        #expect(Self.progress(swapped, picked: .todo).moved)
    }

    @Test func aNewSizeForThePickedWidgetAloneIsTheResizeAndNamesTheSize() {
        var resized = Self.start
        resized[1].size = .large
        var other = Self.start
        other[0].size = .small

        let progress = Self.progress(resized)
        #expect(progress.resized && !progress.moved)
        #expect(progress.size == .large)
        #expect(progress.current == .move, "a step done out of order still counts, and the first one left is asked")
        #expect(!Self.progress(other).resized, "another widget's size is not the picked one's")
    }

    @Test func puttingASizeOrAPlaceBackUnticksIt() {
        var resized = Self.start
        resized[1].size = .large
        #expect(Self.progress(resized).resized)
        #expect(!Self.progress(Self.start).resized)
    }

    @Test func addingOrTakingOffAnotherWidgetIsNotAMove() {
        let removed = [Self.start[0], Self.start[1]]
        let added = [NookWidgetPlacement(kind: .timer, size: .small)] + Self.start

        #expect(!Self.progress(removed).moved)
        #expect(!Self.progress(added).moved)
    }

    @Test func finishingNeedsEditingToHaveEndedAfterTheTourStartedIt() {
        #expect(!Self.progress(Self.start, editing: false, ended: false).finished, "never started is not finished")
        #expect(Self.progress(Self.start, editing: false, ended: true).finished)
        #expect(!Self.progress(Self.start, editing: true, ended: true).finished, "editing again is not finished")
    }

    @Test func stepsDoneOutOfOrderAllCountAndTheLeftOverOneIsAsked() {
        var resized = Self.start
        resized[1].size = .large
        let early = Self.progress(resized, editing: false, ended: true)

        #expect(early.doneSteps == [.resize, .finish])
        #expect(early.current == .move)
        #expect(early.needsEditing, "editing stopped with a step left, so the page says how to start again")
        #expect(!early.isAllDone)
    }

    @Test func allThreeDoneIsTheEnd() {
        var now = [Self.start[1], Self.start[0], Self.start[2]]
        now[0].size = .large
        let end = Self.progress(now, editing: false, ended: true)

        #expect(end.isAllDone && end.current == nil)
        #expect(end.doneSteps == OnboardingRearrangeStep.allCases)
        #expect(!end.needsEditing)
    }

    @Test func aPickedWidgetThatLeftThePageIsOffThePageWithNothingDone() {
        let gone = Self.progress([Self.start[0], Self.start[2]])

        #expect(!gone.isOnPage)
        #expect(!gone.moved && !gone.resized)
        #expect(gone.size == nil)
        #expect(!gone.needsEditing, "the page tells the user to pick another, not to start editing")
    }

    @Test func notEditingWithStepsLeftAsksToStartAgain() {
        #expect(Self.progress(Self.start, editing: false).needsEditing)
        #expect(!Self.progress(Self.start, editing: true).needsEditing)
    }
}

// MARK: - The arrange page in a tour

@MainActor
struct OnboardingArrangeTourTests {
    /// The app as the tour sees it: the state it reads, and the doors it
    /// pulled. The editing door does what the real one does to the state.
    private final class World {
        var state = OnboardingState()
        var restored: [[NookWidgetPlacement]] = []
        var editing: [Bool] = []
        var outlines: [NookWidgetKind?] = []
        var holds: [Bool] = []
    }

    private static let start = [
        NookWidgetPlacement(kind: .media, size: .large),
        NookWidgetPlacement(kind: .todo, size: .small),
        NookWidgetPlacement(kind: .notes, size: .small),
    ]

    private static func world() -> World {
        let world = World()
        world.state.nookPlacements = start
        return world
    }

    private static func tour(_ world: World, onEnd: @escaping (OnboardingOutcome) -> Void = { _ in }) -> OnboardingTour {
        var actions = OnboardingActions()
        actions.restorePlacements = { world.restored.append($0) }
        actions.setEditingWidgets = {
            world.editing.append($0)
            world.state.isEditingWidgets = $0
        }
        actions.outlineWidget = { world.outlines.append($0) }
        actions.holdIsland = { world.holds.append($0) }
        return OnboardingTour(startingAt: .layout, state: { world.state }, actions: actions, onEnd: onEnd)
    }

    /// A tour on the arrange page with `.todo` picked.
    private static func picked(_ world: World) -> OnboardingTour {
        let tour = Self.tour(world)
        tour.next()
        tour.actions.pickArrangeWidget(.todo)
        return tour
    }

    private func expectLetGo(_ world: World, _ comment: Comment) {
        #expect(world.editing == [true, false], comment)
        #expect(world.outlines == [.todo, nil], comment)
        #expect(!world.state.isEditingWidgets, comment)
    }

    @Test func theFreshPageHasNoPickAndStartsNothing() {
        let world = Self.world()
        let tour = Self.tour(world)
        tour.next()

        #expect(tour.page == .arrange)
        #expect(tour.state.arrangeProgress == nil)
        #expect(world.editing.isEmpty && world.outlines.isEmpty)
        #expect(tour.state.arrangeStart == Self.start)
    }

    @Test func pickingAWidgetStartsEditingByItselfAndNamesTheOutline() {
        let world = Self.world()
        let tour = Self.picked(world)

        #expect(world.editing == [true])
        #expect(world.outlines == [.todo])
        let progress = tour.state.arrangeProgress
        #expect(progress?.kind == .todo)
        #expect(progress?.current == .move)
        #expect(progress?.isEditing == true)
    }

    @Test func aPickWorksWhenTheIslandWasAlreadyEditing() {
        let world = Self.world()
        world.state.isEditingWidgets = true
        let tour = Self.tour(world)
        tour.next()

        tour.actions.pickArrangeWidget(.media)

        #expect(tour.state.arrangeProgress?.kind == .media)
        #expect(world.outlines == [.media])
    }

    @Test func aPickOffThePageOrOffThisPageDoesNothing() {
        let world = Self.world()
        let tour = Self.tour(world)
        tour.actions.pickArrangeWidget(.todo)
        #expect(tour.page == .layout && world.editing.isEmpty, "not on the arrange page")

        tour.next()
        tour.actions.pickArrangeWidget(.weather)
        #expect(tour.state.arrangeProgress == nil && world.editing.isEmpty && world.outlines.isEmpty)
    }

    @Test func theStepsFollowWhatTheUserDoesOnTheIslandAndDoneEndsTheWalk() {
        let world = Self.world()
        let tour = Self.picked(world)
        #expect(tour.state.arrangeProgress?.current == .move)

        world.state.nookPlacements = [Self.start[1], Self.start[0], Self.start[2]]
        #expect(tour.state.arrangeProgress?.current == .resize)

        world.state.nookPlacements?[0].size = .large
        #expect(tour.state.arrangeProgress?.current == .finish)
        #expect(tour.state.arrangeProgress?.size == .large)

        // The user clicks Done: the island ends editing by itself.
        world.state.isEditingWidgets = false
        #expect(tour.state.arrangeProgress?.isAllDone == true)

        // Pressing and holding again is editing again, not finished.
        world.state.isEditingWidgets = true
        #expect(tour.state.arrangeProgress?.finished == false)
    }

    @Test func endingEditingEarlyLeavesTheStepsAndAsksToStartAgain() {
        let world = Self.world()
        let tour = Self.picked(world)
        _ = tour.state
        world.state.isEditingWidgets = false

        let progress = tour.state.arrangeProgress
        #expect(progress?.finished == true)
        #expect(progress?.needsEditing == true)
        #expect(progress?.current == .move)
    }

    @Test func aWidgetThatLeavesThePageIsReportedGone() {
        let world = Self.world()
        let tour = Self.picked(world)

        world.state.nookPlacements = [Self.start[0], Self.start[2]]

        #expect(tour.state.arrangeProgress?.isOnPage == false)
    }

    @Test func theNextButtonEndsTheEditingAndTheOutline() {
        let world = Self.world()
        let tour = Self.picked(world)
        tour.next()

        expectLetGo(world, "leaving by Next")
        #expect(tour.state.arrangeProgress == nil)
    }

    @Test func goingBackAndJumpingToAnotherPageEndTheEditingAndTheOutline() {
        let back = Self.world()
        let backTour = Self.picked(back)
        backTour.back()
        expectLetGo(back, "leaving by Back")

        let jump = Self.world()
        let jumpTour = Self.picked(jump)
        jumpTour.go(to: .look)
        expectLetGo(jump, "leaving by a dot")
    }

    @Test func skippingEndsTheEditingAndTheOutline() {
        let world = Self.world()
        var ended: [OnboardingOutcome] = []
        let tour = Self.tour(world) { ended.append($0) }
        tour.next()
        tour.actions.pickArrangeWidget(.todo)

        tour.skip()

        #expect(ended == [.skipped])
        expectLetGo(world, "skipping")
    }

    @Test func finishingTheTourLetsGoOnceAndOnlyOnce() {
        let world = Self.world()
        var ended: [OnboardingOutcome] = []
        let tour = Self.tour(world) { ended.append($0) }
        tour.next()
        tour.actions.pickArrangeWidget(.todo)
        tour.go(to: .done)
        tour.next()

        #expect(ended == [.finished])
        expectLetGo(world, "finishing the tour")
    }

    @Test func closingTheWindowEndsTheEditingAndTheOutlineBeforeTheSkip() {
        let world = Self.world()
        let tour = Self.picked(world)

        // What the window does when it goes: let go, then skip.
        tour.releaseIsland()
        expectLetGo(world, "the window closing")
        tour.skip()
        expectLetGo(world, "and the skip after it changes nothing")
    }

    @Test func theUserLeavingTheAppLetsTheIslandAndTheOutlineGo() {
        let world = Self.world()
        let tour = Self.picked(world)

        tour.setPresence(appIsActive: false, windowIsVisible: true)

        expectLetGo(world, "the hold going off")
        #expect(world.holds.last == false)
    }

    @Test func puttingItBackHandsTheAppTheStartAndReturnsToThePick() {
        let world = Self.world()
        let tour = Self.picked(world)
        world.state.nookPlacements = Self.start.reversed()
        _ = tour.state

        tour.actions.resetArrangement()

        #expect(world.restored == [Self.start])
        expectLetGo(world, "putting it back")
        #expect(tour.state.arrangeProgress == nil)
    }

    @Test func tryingAnotherStartsCleanFromThePageAsItIsNow() {
        let world = Self.world()
        let tour = Self.picked(world)
        world.state.nookPlacements = [Self.start[1], Self.start[0], Self.start[2]]
        #expect(tour.state.arrangeProgress?.moved == true)

        tour.actions.tryAnotherWidget()
        expectLetGo(world, "Try another widget")
        #expect(tour.state.arrangeProgress == nil)
        #expect(world.restored.isEmpty, "trying another does not undo what was done")

        tour.actions.pickArrangeWidget(.media)
        let progress = tour.state.arrangeProgress
        #expect(progress?.kind == .media)
        #expect(progress?.moved == false && progress?.resized == false && progress?.finished == false)
        #expect(world.editing == [true, false, true])
        #expect(world.outlines == [.todo, nil, .media])
        #expect(tour.state.arrangeStart == Self.start, "the page found at the start is still what Put it back restores")
    }

    @Test func comingBackToThePageTakesANewStartWithNoPick() {
        let world = Self.world()
        let tour = Self.picked(world)
        world.state.nookPlacements = Self.start.reversed()
        tour.next()
        tour.back()

        #expect(tour.page == .arrange)
        #expect(tour.state.arrangeProgress == nil)
        #expect(tour.state.arrangeStart == Self.start.reversed())
    }

    @Test func nextIsNeverHeldUpByThePage() {
        let world = Self.world()
        let tour = Self.tour(world)
        tour.go(to: .arrange)

        tour.next()

        #expect(tour.page == .todos)
    }
}

// MARK: - The hold asks macOS for nothing

struct IslandTourHoldAccessTests {
    private static let page: [NookWidgetKind] = [.calendar, .todo, .media]

    @Test func anIslandTheTourHoldsOpenPutsNoWidgetInTheUsersView() {
        for reason in [NotchOpenReason.click, .hover] {
            let held = NookAccessTiming.widgetsInView(
                status: .opened, reason: reason, showsNookPage: true, pageWidgets: Self.page, isHeldByTour: true
            )
            #expect(held.isEmpty, "\(reason)")
        }
    }

    @Test func withTheHoldOffAnIslandTheUserOpenedStillShowsItsWidgets() {
        for reason in [NotchOpenReason.click, .hover] {
            let shown = NookAccessTiming.widgetsInView(
                status: .opened, reason: reason, showsNookPage: true, pageWidgets: Self.page
            )
            #expect(shown == Set(Self.page), "\(reason)")
        }
    }
}
