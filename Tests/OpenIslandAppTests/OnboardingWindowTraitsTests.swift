import AppKit
import Testing
@testable import OpenIslandApp

/// The tour's window has to be seen wherever the island is: on every Space
/// and over a full-screen app. A plain window vanished there while the island
/// it held open stayed.
struct OnboardingWindowTraitsTests {
    @Test func theWindowFollowsTheUserToTheActiveSpaceAndMayShowOverAFullScreenApp() {
        let behavior = OnboardingWindowTraits.collectionBehavior
        #expect(behavior.contains(.moveToActiveSpace))
        #expect(behavior.contains(.fullScreenAuxiliary))
        // Not pinned to every Space at once: it moves with the user instead.
        #expect(!behavior.contains(.canJoinAllSpaces))
    }

    @Test func aLivePageFloatsBesideTheIslandAndTheOthersAreOrdinaryWindows() {
        #expect(OnboardingWindowTraits.level(isLivePage: true) == .floating)
        #expect(OnboardingWindowTraits.level(isLivePage: false) == .normal)
        // Below the island's own panel, which stays on top of the tour.
        #expect(OnboardingWindowTraits.level(isLivePage: true).rawValue < IslandPanelLevel.standard.rawValue)
    }

    @Test func theDemoRaisesEitherLevelAboveTheIsland() {
        for isLive in [true, false] {
            let level = DemoWindowLevels.level(forWindowAt: OnboardingWindowTraits.level(isLivePage: isLive), isDemo: true)
            #expect(level.rawValue > DemoWindowLevels.island.rawValue)
        }
    }
}
