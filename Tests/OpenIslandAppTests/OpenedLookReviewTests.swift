import CoreGraphics
import Testing
@testable import OpenIslandApp

/// Rules added after the review of the opened island's look (D35).
struct OpenedLookReviewTests {
    @Test func aNarrowerLookOnTheSameScreenIsNarrowing() {
        let wide = CGRect(x: 100, y: 500, width: 776, height: 300)
        let standard = CGRect(x: 200, y: 560, width: 576, height: 240)

        #expect(IslandPanelSizing.isNarrowing(from: wide, to: standard))
        #expect(IslandPanelSizing.isNarrowing(from: standard, to: wide) == false)
    }

    @Test func aMoveToAnotherScreenIsNotNarrowing() {
        let notch = CGRect(x: 100, y: 500, width: 776, height: 300)
        let external = CGRect(x: 2200, y: 900, width: 556, height: 300)
        let lowerTop = CGRect(x: 200, y: 300, width: 576, height: 240)

        #expect(IslandPanelSizing.isNarrowing(from: notch, to: external) == false)
        #expect(IslandPanelSizing.isNarrowing(from: notch, to: lowerTop) == false)
    }

    @Test func aHeightChangeAloneIsNotNarrowing() {
        let tall = CGRect(x: 100, y: 400, width: 576, height: 400)
        let short = CGRect(x: 100, y: 560, width: 576, height: 240)

        #expect(IslandPanelSizing.isNarrowing(from: tall, to: short) == false)
    }

    @Test func aHarnessSwitchStopsTheTourAndAnOrdinaryNameDoesNot() {
        #expect(OnboardingGate.isHarnessLaunch(environment: ["OPEN_ISLAND_HALO": "flash"]))
        #expect(OnboardingGate.isHarnessLaunch(environment: ["OPEN_ISLAND_NOOK_PAGE": "nook"]))
        for name in OnboardingGate.ordinaryNames {
            #expect(OnboardingGate.isHarnessLaunch(environment: [name: "1"]) == false)
        }
        #expect(OnboardingGate.isHarnessLaunch(environment: ["PATH": "/usr/bin"]) == false)
    }
}
