import AppKit
import Testing
@testable import OpenIslandApp
import OpenIslandCore

// The camera clean-up of the features page on a real `AppModel`, with the
// real mirror door (`AppModel.setMirror`, the one a link uses) and the real
// reading of the mirror. `OnboardingFeaturesTourTests` proves the tour's
// rules against a stand-in whose door writes the variable the tour reads
// back. Here a wrong door or a wrong reading fails.
//
// The model is on a store held in memory, which keeps its panel off screen
// (`putsPanelOnScreen`). No camera is attached: the camera starts only when
// a mirror view is on screen, and none is built. The suite's trait fails a
// test that puts a window on screen.

@MainActor
@Suite(.noNewWindows)
struct OnboardingRealMirrorTests {
    /// A model with the Mirror widget on the Nook page, as the features page
    /// needs it, and the mirror as the user left it. A mirror that is on
    /// means the island is open on the Nook page, which is the only place it
    /// can be on: closing the island turns it off.
    private static func model(mirrorWasOn: Bool = false) -> AppModel {
        let model = AppModel(defaults: MemoryDefaults())
        model.nook.presentRingLight = { _ in }
        model.nook.setWidget(.mirror, enabled: true)
        if mirrorWasOn {
            model.notchOpen(reason: .click, page: .nook)
            model.nook.isMirrorOn = true
        }
        return model
    }

    /// A welcome tour on the features page with the island held, which is
    /// what takes the baseline.
    private static func featuresTour(_ model: AppModel) -> OnboardingTour {
        let tour = model.makeWelcomeTour(startingAt: .features)
        tour.setPresence(appIsActive: true, windowIsVisible: true)
        return tour
    }

    @Test func theMirrorButtonTurnsTheRealMirrorOn() {
        let model = Self.model()
        let tour = Self.featuresTour(model)
        #expect(tour.page == .features)
        #expect(!model.nook.isMirrorOn)

        tour.actions.setMirror(true)

        #expect(model.nook.isMirrorOn)
        #expect(tour.state.features.isMirrorOn, "the tour reads the real mirror back")
    }

    @Test func releasingTheIslandSwitchesARealMirrorTheTourTurnedOnBackOff() {
        let model = Self.model()
        let tour = Self.featuresTour(model)
        tour.actions.setMirror(true)
        #expect(model.nook.isMirrorOn)

        tour.releaseIsland()

        #expect(!model.nook.isMirrorOn)
        #expect(!tour.state.features.isMirrorOn)
    }

    @Test func droppingTheTourSwitchesARealMirrorItTurnedOnBackOff() {
        let model = Self.model()
        var tour: OnboardingTour? = Self.featuresTour(model)
        tour?.actions.setMirror(true)
        #expect(model.nook.isMirrorOn)

        tour = nil

        #expect(tour == nil)
        #expect(!model.nook.isMirrorOn)
    }

    @Test func aMirrorTheUserHadOnStaysOnWhenTheIslandIsReleased() {
        let model = Self.model(mirrorWasOn: true)
        let tour = Self.featuresTour(model)
        tour.actions.setMirror(true)

        tour.releaseIsland()

        #expect(model.nook.isMirrorOn)
    }

    @Test func aMirrorTheUserHadOnStaysOnWhenTheTourIsDropped() {
        let model = Self.model(mirrorWasOn: true)
        var tour: OnboardingTour? = Self.featuresTour(model)
        tour?.actions.setMirror(true)

        tour = nil

        #expect(tour == nil)
        #expect(model.nook.isMirrorOn)
    }

    @Test func leavingThePageByTheToursOwnNextSwitchesARealMirrorOff() {
        let model = Self.model()
        let tour = Self.featuresTour(model)
        tour.actions.setMirror(true)

        tour.next()

        #expect(!model.nook.isMirrorOn)
    }

    @Test func theUserLeavingTheAppSwitchesARealMirrorOff() {
        let model = Self.model()
        let tour = Self.featuresTour(model)
        tour.actions.setMirror(true)

        tour.setPresence(appIsActive: false, windowIsVisible: true)

        #expect(!model.nook.isMirrorOn)
    }

    @Test func aRingLightTheTourTurnedOnIsPutBackOnceEvenWhenFocusWasLostBeforeThePageWasLeft() {
        let model = Self.model()
        let tour = Self.featuresTour(model)
        tour.actions.setMirror(true)
        tour.actions.setRingLight(true)
        #expect(model.nook.isRingLightOn)

        // Focus goes first: everything the buttons switched on goes off.
        tour.setPresence(appIsActive: false, windowIsVisible: true)
        #expect(!model.nook.isMirrorOn)
        #expect(!model.nook.isRingLightOn)

        // Leaving the page later finds nothing left to put back, and does
        // not touch what is off.
        tour.next()
        tour.releaseIsland()
        #expect(!model.nook.isMirrorOn)
        #expect(!model.nook.isRingLightOn)
    }

    /// A button pressed after the page was let go records nothing and
    /// switches nothing on: nothing would be left to put it back, and the
    /// next visit would take a mirror left on as the user's.
    @Test func aPressAfterThePageWasLetGoSwitchesNothingOn() {
        let model = Self.model()
        let tour = Self.featuresTour(model)
        tour.releaseIsland()
        #expect(model.notchStatus == .closed)

        tour.actions.setMirror(true)
        tour.actions.setRingLight(true)

        #expect(!model.nook.isMirrorOn)
        #expect(!model.nook.isRingLightOn)
        #expect(model.notchStatus == .closed)
    }
}
