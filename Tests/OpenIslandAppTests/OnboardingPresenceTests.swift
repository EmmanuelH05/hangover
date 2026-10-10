import CoreGraphics
import Testing
@testable import OpenIslandApp

// The tour holds the real island open only while the user is in Hangover
// (D44): the rule as a pure function, the tour following it, and the window
// docking again when the island's footprint changes. Nothing here opens a
// window or lights the screen.

// MARK: - The rule

struct OnboardingIslandHoldRuleTests {
    @Test func theHoldIsOnOnlyWhenAllThreeAreTrue() {
        for isLive in [false, true] {
            for isActive in [false, true] {
                for isVisible in [false, true] {
                    let holds = OnboardingIslandHold.holds(
                        isLivePage: isLive, appIsActive: isActive, windowIsVisible: isVisible
                    )
                    #expect(holds == (isLive && isActive && isVisible), "live \(isLive) active \(isActive) visible \(isVisible)")
                }
            }
        }
    }
}

// MARK: - The tour follows it

@MainActor
struct OnboardingPresenceTests {
    private final class Calls {
        var holds: [Bool] = []
    }

    private static func tour(startingAt page: OnboardingPage, calls: Calls) -> OnboardingTour {
        var actions = OnboardingActions()
        actions.holdIsland = { calls.holds.append($0) }
        return OnboardingTour(startingAt: page, state: { OnboardingState() }, actions: actions)
    }

    @Test func clickingAnotherAppLetsTheIslandGoAndComingBackHoldsItAgain() {
        let calls = Calls()
        let tour = Self.tour(startingAt: .widgets, calls: calls)
        tour.syncIsland()
        #expect(calls.holds == [true])

        tour.setPresence(appIsActive: false, windowIsVisible: true)
        #expect(calls.holds == [true, false])

        tour.setPresence(appIsActive: true, windowIsVisible: true)
        #expect(calls.holds == [true, false, true])
    }

    @Test func aWindowThatIsMiniaturizedOrHiddenLetsTheIslandGo() {
        let calls = Calls()
        let tour = Self.tour(startingAt: .layout, calls: calls)
        tour.syncIsland()

        tour.setPresence(appIsActive: true, windowIsVisible: false)
        #expect(calls.holds == [true, false])

        tour.setPresence(appIsActive: true, windowIsVisible: true)
        #expect(calls.holds == [true, false, true])
    }

    @Test func aPageThatIsNotLiveHoldsNothingWhateverThePresence() {
        let calls = Calls()
        let tour = Self.tour(startingAt: .purpose, calls: calls)

        tour.setPresence(appIsActive: false, windowIsVisible: true)
        tour.setPresence(appIsActive: true, windowIsVisible: true)

        #expect(calls.holds.isEmpty)
    }

    @Test func movingToALivePageWhileAwayHoldsNothingUntilTheUserIsBack() {
        let calls = Calls()
        let tour = Self.tour(startingAt: .purpose, calls: calls)
        tour.setPresence(appIsActive: false, windowIsVisible: true)

        tour.go(to: .widgets)
        #expect(calls.holds.isEmpty)

        tour.setPresence(appIsActive: true, windowIsVisible: true)
        #expect(calls.holds == [true])
    }

    @Test func repeatedPresenceTellsTheAppOnce() {
        let calls = Calls()
        let tour = Self.tour(startingAt: .arrange, calls: calls)
        tour.syncIsland()

        tour.setPresence(appIsActive: true, windowIsVisible: true)
        tour.setPresence(appIsActive: false, windowIsVisible: true)
        tour.setPresence(appIsActive: false, windowIsVisible: false)

        #expect(calls.holds == [true, false])
    }

    @Test func aTourThatEndedWhileAwayHoldsNothingWhenTheUserIsBack() {
        let calls = Calls()
        let tour = Self.tour(startingAt: .opened, calls: calls)
        tour.syncIsland()
        tour.setPresence(appIsActive: false, windowIsVisible: true)
        tour.skip()

        tour.setPresence(appIsActive: true, windowIsVisible: true)

        #expect(calls.holds == [true, false])
    }
}

// MARK: - The window docks again

struct OnboardingRedockTests {
    private static let screen = CGRect(x: 0, y: 25, width: 1512, height: 920)

    private static func footprint(islandWidth: CGFloat) -> OnboardingIslandFootprint {
        OnboardingIslandFootprint(
            screen: screen,
            island: CGRect(x: screen.midX - islandWidth / 2, y: screen.maxY - 300, width: islandWidth, height: 300)
        )
    }

    @Test func aWiderIslandMovesTheWindowOutFromUnderIt() throws {
        let before = Self.footprint(islandWidth: 640)
        let docked = OnboardingWindowFrame.narrow(screen: before.screen, island: before.island)

        let wider = Self.footprint(islandWidth: 1000)
        let moved = OnboardingIslandHold.redock(current: docked, isLivePage: true, footprint: wider)

        let frame = try #require(moved)
        #expect(frame.width < docked.width, "less room left of the island")
        #expect(frame.maxX <= wider.island.minX || frame.width == OnboardingWindowFrame.narrowWidthRange.lowerBound)
    }

    @Test func aNarrowerIslandGivesTheWindowItsRoomBack() {
        let wide = Self.footprint(islandWidth: 1000)
        let docked = OnboardingWindowFrame.narrow(screen: wide.screen, island: wide.island)

        let moved = OnboardingIslandHold.redock(current: docked, isLivePage: true, footprint: Self.footprint(islandWidth: 640))

        #expect(moved.map { $0.width > docked.width } == true)
    }

    @Test func aFootprintThatDidNotChangeLeavesTheWindowAlone() {
        let footprint = Self.footprint(islandWidth: 640)
        let docked = OnboardingWindowFrame.narrow(screen: footprint.screen, island: footprint.island)

        #expect(OnboardingIslandHold.redock(current: docked, isLivePage: true, footprint: footprint) == nil)
    }

    @Test func aPageThatIsNotLiveIsNeverDockedAgain() {
        let wide = OnboardingWindowFrame.wide(screen: Self.screen)

        #expect(OnboardingIslandHold.redock(current: wide, isLivePage: false, footprint: Self.footprint(islandWidth: 1000)) == nil)
    }
}
