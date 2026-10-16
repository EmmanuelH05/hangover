import Foundation
import Testing
@testable import OpenIslandApp

// Two fixes to the Record step of the features page (R1 and R2 of the review
// fixes). Leaving the step must not stop a recording the user started, and
// "Record is on" is the widget's switch, not the page the tour draws.
// Nothing here starts a recording, opens a window or reads the real settings.

/// The app as the tour sees it, with the Record switch and the Record card on
/// the page told apart, and a recording the test starts by hand.
@MainActor
private final class LeaveWorld {
    var state = OnboardingState()
    var calls: [String] = []

    /// `recordSwitch` is the widget's switch. `recordOnPage` is whether a
    /// layout shows its card, and follows the switch unless told otherwise.
    init(recordSwitch: Bool = false, recordOnPage: Bool? = nil, kinds: [NookWidgetKind] = [.media, .notes]) {
        let onPage = recordOnPage ?? recordSwitch
        state.nookPlacements = (kinds + (onPage ? [.record] : [])).map {
            NookWidgetPlacement(kind: $0, size: .medium)
        }
        state.enabledWidgets = Set(NookWidgetKind.allCases).subtracting(recordSwitch ? [] : [.record])
    }

    var actions: OnboardingActions {
        var actions = OnboardingActions()
        actions.setWidget = { [self] kind, isOn in
            calls.append("\(kind.rawValue) \(isOn)")
            var placements = (state.nookPlacements ?? []).filter { $0.kind != kind }
            if isOn { placements.append(NookWidgetPlacement(kind: kind, size: .medium)) }
            state.nookPlacements = placements
            if isOn { state.enabledWidgets.insert(kind) } else { state.enabledWidgets.remove(kind) }
        }
        return actions
    }

    var isRecordOn: Bool { state.enabledWidgets.contains(.record) }

    /// The user starts or ends a recording of their own.
    func setRecording(_ isRecording: Bool) {
        state.features.isRecordBusy = isRecording
    }

    /// A tour on the features page, on the Record step.
    func onRecordStep() -> OnboardingTour {
        let tour = OnboardingTour(startingAt: .widgets, state: { self.state }, actions: actions)
        tour.next()
        tour.actions.nextFeature()
        tour.actions.nextFeature()
        return tour
    }
}

// MARK: - R1: a recording the user started

@MainActor
struct OnboardingRecordLeaveRecordingTests {
    @Test(arguments: OnboardingRecordExit.allCases)
    func aRecordingRunningWhenTheStepIsLeftKeepsTheWidgetOn(exit: OnboardingRecordExit) {
        let world = LeaveWorld()
        let tour = world.onRecordStep()
        tour.actions.setWidget(.record, true)
        // The user starts a recording with the shortcut while on the step.
        world.setRecording(true)

        exit.leave(tour)

        #expect(world.isRecordOn, "\(exit) switched Record off under a recording")
        #expect(!world.calls.contains("record false"), "\(exit): \(world.calls)")
    }

    @Test func aRecordingThatEndedBeforeTheStepWasLeftStaysTheUsersChoice() {
        let world = LeaveWorld()
        let tour = world.onRecordStep()
        tour.actions.setWidget(.record, true)
        world.setRecording(true)
        _ = tour.state
        world.setRecording(false)

        tour.actions.nextFeature()

        #expect(world.isRecordOn, "Record became the user's when they recorded")
        #expect(!world.calls.contains("record false"), "\(world.calls)")
    }

    @Test func withNoRecordingLeavingStillSwitchesTheToursRecordOff() {
        let world = LeaveWorld()
        let tour = world.onRecordStep()
        tour.actions.setWidget(.record, true)

        tour.actions.nextFeature()

        #expect(!world.isRecordOn)
        #expect(world.calls == ["record true", "record false"])
    }

    @Test func theTrialsDropARecordTheUserIsRecordingWith() {
        var trials = OnboardingTrials()
        trials.baseline = OnboardingFeatureBaseline()
        trials.record = true
        let busy = OnboardingFeatureReading(isRecordOn: true, isRecordBusy: true)

        #expect(trials.observing(busy).releases(leaving: .record, reading: busy).isEmpty)
        #expect(!trials.observing(busy).record)
        // The same reading without a recording would have put it back.
        let idle = OnboardingFeatureReading(isRecordOn: true)
        #expect(trials.releases(leaving: .record, reading: idle) == [.recordOff])
        #expect(trials.releases(leaving: nil, reading: busy).isEmpty, "also when the whole page closes")
    }
}

// MARK: - R2: the switch, not the page

@MainActor
struct OnboardingRecordSwitchTests {
    @Test func aRecordSwitchedOnButLeftOffThisDisplaysPageIsReadAsOn() {
        let world = LeaveWorld(recordSwitch: true, recordOnPage: false)
        let tour = world.onRecordStep()

        #expect(!tour.state.showsWidget(.record), "a layout left the card off")
        #expect(tour.state.features.isRecordOn)
        #expect(!OnboardingTry.recordOn.button(tour.state.features, progress: tour.state.featureProgress).isEnabled)
    }

    @Test(arguments: OnboardingRecordExit.allCases)
    func aRecordTheUserHadOnWithoutItsCardIsLeftOnByEveryWayOut(exit: OnboardingRecordExit) {
        let world = LeaveWorld(recordSwitch: true, recordOnPage: false)
        let tour = world.onRecordStep()

        // The switch was on. Pressing it puts the card back and is not the tour's.
        tour.actions.setWidget(.record, true)
        exit.leave(tour)

        #expect(world.isRecordOn, "\(exit) switched off a Record that was the user's")
        #expect(!world.calls.contains("record false"), "\(exit): \(world.calls)")
    }

    @Test func aRecordSwitchedOffIsOffEvenWhenAStalePageStillDrawsItsCard() {
        let world = LeaveWorld(recordSwitch: false, recordOnPage: true)
        let tour = world.onRecordStep()

        #expect(tour.state.showsWidget(.record))
        #expect(!tour.state.features.isRecordOn)
        #expect(OnboardingTry.recordOn.button(tour.state.features, progress: tour.state.featureProgress).isEnabled)
    }

    @Test func aReadingHandedInWithRecordOnIsKept() {
        let world = LeaveWorld()
        world.state.features.isRecordOn = true
        let tour = world.onRecordStep()

        #expect(tour.state.features.isRecordOn)
    }
}

// MARK: - Through the real models

@MainActor
struct OnboardingRecordLeaveInTheAppTests {
    private static func model() -> AppModel {
        let nook = NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
        let model = AppModel(agentsDefaults: MemoryDefaults(), defaults: MemoryDefaults(), nookModel: nook)
        nook.activeProfile = { [weak model] in model?.activeAppearanceProfile ?? .topBar }
        return model
    }

    private static func tour(over model: AppModel) -> OnboardingTour {
        var actions = OnboardingActions()
        actions.setWidget = { [model] kind, isOn in model.setTourWidget(kind, enabled: isOn) }
        return OnboardingTour(startingAt: .widgets, state: { model.onboardingState }, actions: actions)
    }

    @Test func theReadingCarriesTheRecordersBusyStateFromEveryPhaseThatIsBusy() {
        let model = Self.model()
        #expect(!model.onboardingState.features.isRecordBusy)

        let busy: [NookRecordPhase] = [
            .countdown(secondsLeft: 3),
            .recording(startedAt: Date(), pausedTotal: 0),
            .paused(startedAt: Date(), pausedAt: Date(), pausedTotal: 0),
            .saving,
        ]
        for phase in busy {
            model.nook.record.phase = phase
            #expect(model.onboardingState.features.isRecordBusy, "\(phase)")
        }
        model.nook.record.phase = .idle
        #expect(!model.onboardingState.features.isRecordBusy)
    }

    @Test func aRecordSwitchedOnInSettingsButHiddenOnThisDisplayIsReadAsOn() {
        let model = Self.model()
        model.nook.setWidgetFromSettings(.record, enabled: true)
        model.nook.hideWidget(.record, for: model.activeAppearanceProfile)
        #expect(!model.onboardingState.showsWidget(.record), "the card is off this display's page")

        let tour = Self.tour(over: model)
        tour.next()

        #expect(model.nook.isWidgetEnabled(.record))
        #expect(tour.state.features.isRecordOn)
    }

    @Test func leavingTheStepWithARecordingRunningLeavesTheRealWidgetOn() {
        let model = Self.model()
        let tour = Self.tour(over: model)
        tour.next()
        for _ in 0..<12 where tour.state.featureKind != .record { tour.actions.nextFeature() }
        #expect(tour.state.featureKind == .record)
        OnboardingTry.recordOn.press(reading: tour.state.features, sample: "", actions: tour.actions)
        #expect(model.nook.isWidgetEnabled(.record))

        // The user records with the shortcut, then moves on.
        model.nook.record.phase = .recording(startedAt: Date(), pausedTotal: 0)
        tour.actions.nextFeature()
        tour.releaseIsland()

        #expect(model.nook.isWidgetEnabled(.record), "the tour switched Record off under a recording")
    }
}
