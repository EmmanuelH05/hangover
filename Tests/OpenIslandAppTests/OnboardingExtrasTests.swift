import Foundation
import Testing
@testable import OpenIslandApp

// The features of this week in the welcome tour: the design kit's step in the
// widget walk, the lights that follow the beat, and what each length holds of
// them. Nothing here shows a window, starts a sound device, reads the screen
// or writes the real settings.

// MARK: - The design kit's step

struct OnboardingDesignStepTests {
    private static let t0 = Date(timeIntervalSince1970: 1_000_000)

    private static func reading(
        isOn: Bool = false, isReady: Bool = false, lastPickAt: Date? = nil
    ) -> OnboardingFeatureReading {
        OnboardingFeatureReading(design: OnboardingDesignReading(isOn: isOn, isReady: isReady, lastPickAt: lastPickAt))
    }

    // MARK: The walk

    @Test func theWalkEndsOnTheKitAndLinkToMP3WhetherTheKitIsOnThePageOrNot() {
        for kinds in [[NookWidgetKind.media, .timer], [], [.media, .design]] {
            var state = OnboardingState(enabledWidgets: Set(kinds))
            state.nookPlacements = kinds.map { NookWidgetPlacement(kind: $0, size: .medium) }
            let expected = kinds.filter { $0 != .design } + [.design, .linkAudio]
            #expect(state.featureWalk.kinds == expected, "\(kinds)")
            #expect(state.featureWalk.kinds.filter { $0 == .design }.count == 1)
        }
    }

    @Test func theWalkHoldsEveryWidgetTheTourKnowsAndThenTheTwoTools() {
        var state = OnboardingState()
        state.enabledWidgets = Set(NookWidgetKind.allCases)
        state.nookPlacements = NookWidgetKind.allCases.map { NookWidgetPlacement(kind: $0, size: .medium) }
        #expect(state.featureWalk.kinds == NookWidgetKind.allCases)
        #expect(state.featureWalk.kinds.count == OnboardingFeatureWalk.everyKind.count)
    }

    @Test func theKitHasFourToSevenLinesAndTwoButtonsInTheWalksOwnShape() {
        #expect((4...7).contains(OnboardingAbility.lines(for: .design).count))
        #expect(OnboardingTry.tries(for: .design) == [.designOn, .designPick])
        #expect(OnboardingTry.designOn.widget == .design && OnboardingTry.designPick.widget == .design)
    }

    // MARK: The buttons

    @Test func turnItOnIsEnabledOnlyWhileTheKitIsOffAndCarriesNoNote() {
        let off = OnboardingTry.designOn.button(Self.reading(), progress: OnboardingFeatureProgress())
        #expect(off.isEnabled && off.noteKey == nil)
        let on = OnboardingTry.designOn.button(Self.reading(isOn: true), progress: OnboardingFeatureProgress())
        #expect(!on.isEnabled, "a kit that is on is left on")
    }

    @Test func pickAColorNeedsTheKitOnAndReadyAndSaysWhichIsMissing() {
        let progress = OnboardingFeatureProgress()
        let off = OnboardingTry.designPick.button(Self.reading(), progress: progress)
        #expect(!off.isEnabled && off.noteKey == "onboarding.features.needsDesign")

        let loading = OnboardingTry.designPick.button(Self.reading(isOn: true, isReady: false), progress: progress)
        #expect(!loading.isEnabled)

        let ready = OnboardingTry.designPick.button(Self.reading(isOn: true, isReady: true), progress: progress)
        #expect(ready.isEnabled && ready.noteKey == "onboarding.features.try.designPick.note")
    }

    /// The eyedropper is the macOS color loupe, which asks for nothing. No
    /// button of the step names a permission or offers a settings link.
    @Test func noButtonOfTheKitAsksMacOSForAnything() {
        for step in OnboardingTry.tries(for: .design) {
            #expect(!step.asksMacOS)
            for reading in [Self.reading(), Self.reading(isOn: true), Self.reading(isOn: true, isReady: true)] {
                let button = step.button(reading, progress: OnboardingFeatureProgress())
                #expect(!button.offersCameraSettings)
                #expect(button.noteKey?.contains("refused") != true)
            }
        }
    }

    @MainActor
    @Test func eachButtonPressesItsOwnDoorWithTheKitAsTheWidget() {
        var calls: [String] = []
        var actions = OnboardingActions()
        actions.setWidget = { kind, isOn in calls.append("setWidget \(kind.rawValue) \(isOn)") }
        actions.pickDesignColor = { calls.append("pickDesignColor") }

        OnboardingTry.designOn.press(reading: OnboardingFeatureReading(), sample: "", actions: actions)
        OnboardingTry.designPick.press(reading: OnboardingFeatureReading(), sample: "", actions: actions)

        #expect(calls == ["setWidget design true", "pickDesignColor"])
    }

    // MARK: The ticks

    @Test func turnItOnTicksFromTheKitBeingOnAndNotFromAPress() {
        var progress = OnboardingFeatureProgress()
        progress.note(Self.reading())
        #expect(!progress.done.contains(.designOn))

        progress.note(Self.reading(isOn: true))
        #expect(progress.done.contains(.designOn))
    }

    @Test func pickAColorTicksWhenAColorLandsAfterTheKitWasFirstReady() {
        var progress = OnboardingFeatureProgress()
        // Switched on, the shelves still being read: nothing to compare yet.
        progress.note(Self.reading(isOn: true, isReady: false))
        #expect(!progress.done.contains(.designPick))
        // Ready, with an old color on the shelf: that is the baseline.
        progress.note(Self.reading(isOn: true, isReady: true, lastPickAt: Self.t0))
        #expect(!progress.done.contains(.designPick), "an old color is not a pick")
        // The same color still there.
        progress.note(Self.reading(isOn: true, isReady: true, lastPickAt: Self.t0))
        #expect(!progress.done.contains(.designPick))
        // The loupe is up: not ready, and still no tick.
        progress.note(Self.reading(isOn: true, isReady: false, lastPickAt: Self.t0))
        #expect(!progress.done.contains(.designPick))
        // A color landed.
        progress.note(Self.reading(isOn: true, isReady: true, lastPickAt: Self.t0.addingTimeInterval(5)))
        #expect(progress.done.contains(.designPick))
    }

    @Test func aKitWithNoColorsTicksOnItsFirstPick() {
        var progress = OnboardingFeatureProgress()
        progress.note(Self.reading(isOn: true, isReady: true, lastPickAt: nil))
        #expect(!progress.done.contains(.designPick))
        progress.note(Self.reading(isOn: true, isReady: true, lastPickAt: Self.t0))
        #expect(progress.done.contains(.designPick))
    }

    @Test func aTickStaysAndTwoProgressesMerge() {
        var seen = OnboardingFeatureProgress()
        seen.note(Self.reading(isOn: true, isReady: true, lastPickAt: Self.t0))
        seen.note(Self.reading(isOn: true, isReady: true, lastPickAt: Self.t0.addingTimeInterval(1)))
        seen.note(Self.reading(isOn: true, isReady: true, lastPickAt: Self.t0))
        #expect(seen.done.contains(.designPick), "a tick is not taken back")

        let merged = OnboardingFeatureProgress().merged(with: seen)
        #expect(merged.done.contains(.designPick) && merged.done.contains(.designOn))
        #expect(merged.hasDesignBaseline)
    }

    // MARK: A kit the user turned on stays on

    @MainActor
    @Test func aKitTurnedOnInTheTourIsNeverSwitchedOffByTheTour() {
        var calls: [String] = []
        var actions = OnboardingActions()
        actions.setWidget = { kind, isOn in calls.append("\(kind.rawValue) \(isOn)") }
        let tour = OnboardingTour(startingAt: .features, state: { OnboardingState() }, actions: actions)

        OnboardingTry.designOn.press(reading: OnboardingFeatureReading(), sample: "", actions: tour.actions)
        tour.next()
        tour.skip()

        #expect(calls == ["design true"], "the tour switched the kit on once and nothing put it back")
    }

    @MainActor
    @Test func aKitThatWasOffAndNeverTouchedStaysOff() {
        var calls: [String] = []
        var actions = OnboardingActions()
        actions.setWidget = { kind, isOn in calls.append("\(kind.rawValue) \(isOn)") }
        let tour = OnboardingTour(startingAt: .features, state: { OnboardingState() }, actions: actions)
        tour.syncIsland()

        for _ in 0..<12 { tour.actions.nextFeature() }
        #expect(tour.state.featureKind == .linkAudio, "the walk ends on Link to MP3")
        tour.next()
        tour.back()
        tour.skip()

        #expect(calls.isEmpty, "walking past the kit's step does not switch it on")
    }

    @Test(arguments: HangoverBrandTests.languages)
    func theFootnoteSaysAKitOrLinkToMP3TurnedOnStaysOn(language: String) throws {
        let note = try #require(try HangoverBrandTests.table(language)["onboarding.features.note"])
        switch language {
        case "en": #expect(note.contains("The design kit and Link to MP3 stay on if you turned them on."))
        case "zh-Hans": #expect(note.contains("设计工具和链接转 MP3 会保持开启"))
        default: #expect(note.contains("設計工具和連結轉 MP3 會保持開啟"))
        }
    }

    @MainActor
    @Test func theKitsTriesAreNotTrialsThatTheCleanUpUndoes() {
        let reading = Self.reading(isOn: true, isReady: true)
        let trials = OnboardingTrials(baseline: OnboardingFeatureBaseline(reading))
        #expect(trials.releases(leaving: .design, reading: reading).isEmpty)
        #expect(trials.releases(leaving: nil, reading: reading).isEmpty)
    }
}

// MARK: - The lights

@MainActor
struct OnboardingLightsTests {
    @Test func theMadeUpBeatIsOneShortPatternPlayedAFewTimesAndThenRests() {
        #expect(OnboardingBeatLoop.pattern.count == 8)
        #expect(OnboardingBeatLoop.stepCount == OnboardingBeatLoop.pattern.count * OnboardingBeatLoop.bars)
        #expect(OnboardingBeatLoop.stepCount < 40, "it comes to rest: nothing in the tour repeats forever")
        #expect(OnboardingBeatLoop.pattern.allSatisfy { (0...1).contains($0) })
        #expect(OnboardingBeatLoop.pattern.contains(1) && OnboardingBeatLoop.pattern.contains(0))
        #expect(OnboardingBeatLoop.strength(at: -1) == 0 && OnboardingBeatLoop.strength(at: OnboardingBeatLoop.stepCount) == 0)
        #expect(OnboardingBeatLoop.strength(at: 0) == 1)
        #expect(OnboardingBeatLoop.strength(at: OnboardingBeatLoop.pattern.count) == 1, "each bar starts on a kick")
    }

    @Test func theColorStepsOnEachHitAndHoldsBetweenHits() {
        var last = OnboardingBeatLoop.hue(at: 0)
        var steps = 0
        for step in 1..<OnboardingBeatLoop.stepCount {
            let hue = OnboardingBeatLoop.hue(at: step)
            if OnboardingBeatLoop.strength(at: step) > 0 {
                #expect(hue == (last + 1) % OnboardingBeatLoop.hues.count, "step \(step)")
                steps += 1
            } else {
                #expect(hue == last, "step \(step) holds the color")
            }
            last = hue
        }
        #expect(steps > OnboardingBeatLoop.hues.count, "the four colors come round")
        #expect(OnboardingBeatLoop.hues.count == 4)
    }

    @Test func theLightsPageIsOnlyInTheLongTourAndOnlyOnAMacThatCanRunThem() {
        #expect(OnboardingPage.shown(length: .long, agentsEnabled: true).contains(.lights))
        #expect(!OnboardingPage.shown(length: .medium, agentsEnabled: true).contains(.lights))
        #expect(!OnboardingPage.shown(length: .short, agentsEnabled: true).contains(.lights))
        #expect(!OnboardingPage.shown(length: .long, agentsEnabled: true, hasLights: false).contains(.lights))
        #expect(OnboardingPage.lights.more == .lights)
        #expect(OnboardingPage.lights.chapter == .know && !OnboardingPage.lights.isLive)

        var old = OnboardingState()
        old.length = .long
        old.beat.isAvailable = false
        #expect(!OnboardingTour.pages(for: old).contains(.lights))
        old.beat.isAvailable = true
        #expect(OnboardingTour.pages(for: old).contains(.lights))
    }

    @Test func eachLengthHoldsWhatTheBriefSaysOfTheNewFeatures() {
        // The kit's step and the beat switch live on pages the main tour has.
        for page in [OnboardingPage.features, .look] {
            #expect(page.shortestLength == .medium)
            #expect(!OnboardingPage.shown(length: .short, agentsEnabled: true).contains(page))
            #expect(OnboardingPage.shown(length: .medium, agentsEnabled: true).contains(page))
            #expect(OnboardingPage.shown(length: .long, agentsEnabled: true).contains(page))
        }
        // The short tour has none of it, in any page or any row.
        let short = OnboardingPage.shown(length: .short, agentsEnabled: true)
        #expect(!short.contains(.lights) && !short.contains(.features) && !short.contains(.look))
        #expect(OnboardingRecapRow.shown(length: .short, agentsEnabled: true, hasDesignKit: true, hasLights: true)
            == [.opens, .closed, .agents, .widgets])
        #expect(OnboardingPage.lights.shortestLength == .long)
    }

    @Test func theCountsOfTheThreeListsFollowTheNewPage() {
        let state = OnboardingState()
        #expect(OnboardingLengthPage.stepCount(.short, in: state) == 8)
        #expect(OnboardingLengthPage.stepCount(.medium, in: state) == 18)
        #expect(OnboardingLengthPage.stepCount(.long, in: state) == 33)
    }

    @Test func theNotesUnderTheRowAreAtMostTwoAndTheMostImportantComesFirst() {
        func keys(_ change: (inout OnboardingBeatReading) -> Void) -> [String] {
            var beat = OnboardingBeatReading()
            change(&beat)
            return OnboardingLightsRow.noteKeys(for: beat)
        }
        #expect(keys { _ in } == ["onboarding.look.beat.note"], "what macOS asks, with nothing in the way")
        #expect(keys { $0.dimsFlashingLights = true } == ["onboarding.look.beat.note", "onboarding.look.beat.dimFlashing"])
        #expect(keys { $0.reduceMotion = true } == ["onboarding.look.beat.reduceMotion"])
        #expect(keys { $0.reduceMotion = true; $0.dimsFlashingLights = true } == ["onboarding.look.beat.reduceMotion"],
                "the lights stay still, which leaves nothing to dim")
        #expect(keys { $0.canPulse = false; $0.glowIsOff = true } == ["onboarding.look.beat.needsGlow"])
        #expect(keys { $0.canPulse = false } == ["onboarding.look.beat.needsMusic"], "the glow is on, the closed island shows no music")
        #expect(keys { $0.isAvailable = false }.isEmpty)
        for change in [{ (_: inout OnboardingBeatReading) in }, { $0.dimsFlashingLights = true }, { $0.canPulse = false; $0.dimsFlashingLights = true }, { $0.cannotHear = true; $0.canRunNow = false }] {
            #expect(keys(change).count <= 2)
        }
    }

    // MARK: The permission

    @Test func thePermissionsPageListsTheSoundOnlyWhileThePulseIsOn() {
        #expect(!OnboardingGrant.shown(agentsEnabled: false).contains(.audio))
        #expect(!OnboardingGrant.shown(agentsEnabled: true).contains(.audio))
        #expect(OnboardingGrant.shown(agentsEnabled: false, beatIsOn: true) == [.camera, .accessibility, .calendar, .audio])
        #expect(OnboardingGrant.shown(agentsEnabled: true, beatIsOn: true).contains(.audio))
        #expect(OnboardingGrant.shown(agentsEnabled: true, beatIsOn: true).last == .automation)
        #expect(!OnboardingGrant.audio.isAgentsOnly)
    }

    // MARK: The summary

    @Test func theSummaryListsTheKitAndTheLightsOnlyWhenTheUserChoseThem() {
        let none = OnboardingRecapRow.shown(agentsEnabled: true)
        #expect(!none.contains(.design) && !none.contains(.lights))
        #expect(none == OnboardingRecapRow.standard)

        let kit = OnboardingRecapRow.shown(agentsEnabled: true, hasDesignKit: true)
        #expect(kit.contains(.design) && !kit.contains(.lights))
        let lights = OnboardingRecapRow.shown(agentsEnabled: true, hasLights: true)
        #expect(lights.contains(.lights) && !lights.contains(.design))

        let both = OnboardingRecapRow.shown(agentsEnabled: true, hasDesignKit: true, hasLights: true)
        #expect(both.suffix(2) == [.design, .lights])
        #expect(both.count == OnboardingRecapRow.allCases.count - 1, "all but the Good to know row")
        let everything = OnboardingRecapRow.shown(agentsEnabled: true, hasDesignKit: true, hasLights: true, hasMoreSwitches: true)
        #expect(everything.count == OnboardingRecapRow.allCases.count)
        #expect(everything.suffix(3) == [.design, .lights, .goodToKnow])
    }

    @Test func fifteenRowsTakeNoMoreRoomThanThirteenDid() {
        #expect(OnboardingDonePage.rowHeight(rowCount: 13) == 27)
        #expect(OnboardingDonePage.rowHeight(rowCount: 15) < 27)
        #expect(15 * OnboardingDonePage.rowHeight(rowCount: 15) <= 13 * 27 + 0.001)
        #expect(16 * OnboardingDonePage.rowHeight(rowCount: 16) <= 13 * 27 + 0.001, "the Good to know row fits too")
    }

    // MARK: The strings

    private static var keys: [String] {
        var keys = [
            "onboarding.look.beat.text", "onboarding.look.beat.note", "onboarding.look.beat.needsGlow",
            "onboarding.look.beat.reduceMotion", "onboarding.look.beat.dimFlashing",
            "onboarding.done.recap.design", "onboarding.done.recap.design.on",
            "onboarding.done.recap.lights", "onboarding.done.recap.lights.value",
        ]
        keys += ["title", "when", "note"].map { "onboarding.permissions.audio.\($0)" }
        keys += OnboardingAbility.lines(for: .design).map(\.textKey)
        keys += OnboardingTry.tries(for: .design).map(\.titleKey)
        return keys
    }

    @Test(arguments: HangoverBrandTests.languages)
    func everyNewKeyIsInEveryLanguage(language: String) throws {
        let table = try HangoverBrandTests.table(language)
        for key in Self.keys {
            #expect(!(table[key] ?? "").isEmpty, "\(language) is missing \(key)")
        }
    }

    @Test func theNewWordsAreWrittenPlainlyAndSayWhatMacOSAsks() throws {
        let english = try HangoverBrandTests.table("en")
        for key in Self.keys {
            let value = try #require(english[key])
            #expect(value.range(of: "\\bso\\b", options: [.regularExpression, .caseInsensitive]) == nil, "\(key)")
            #expect(!value.contains("\u{2014}") && !value.contains("\u{2013}"), "\(key) has a dash")
        }
        #expect(try #require(english["onboarding.look.beat.note"]).contains("macOS asks once"))
        #expect(try #require(english["onboarding.permissions.audio.when"]).contains("Pulse with the beat"))
        #expect(try #require(english["onboarding.features.try.designPick.note"]).contains("asks for nothing"))
    }

    @Test func theLightsPageNamesARealTabAndSection() throws {
        let english = try HangoverBrandTests.table("en")
        #expect(english[OnboardingMore.lights.whereKey] == "Settings, Personalization tab, Status glow")
        #expect(english["settings.appearance.nook.halo.title"]?.hasSuffix("Status glow") == true)
        #expect(english["settings.tab.appearance"] == "Personalization")
    }
}

// MARK: - The look page's doors

@MainActor
struct OnboardingLightsDoorsTests {
    private final class Calls {
        var names: [String] = []
    }

    private static func actions(_ calls: Calls) -> OnboardingActions {
        var actions = OnboardingActions()
        actions.setBeatPulse = { calls.names.append("pulse \($0)") }
        actions.setBeatLook = { calls.names.append("look \($0.rawValue)") }
        return actions
    }

    /// The tour's own wrapping leaves the two doors as the app wired them, and
    /// building a tour on the glow page calls neither: nothing listens to the
    /// Mac's sound until the user flips the switch.
    @Test func theTourPassesTheLightsDoorsThroughAndCallsNoneByItself() {
        let calls = Calls()
        let tour = OnboardingTour(startingAt: .look, state: { OnboardingState() }, actions: Self.actions(calls))
        _ = tour.state
        _ = tour.pages
        tour.next()
        tour.back()
        #expect(calls.names.isEmpty)

        tour.actions.setBeatPulse(true)
        tour.actions.setBeatLook(.lasers)
        #expect(calls.names == ["pulse true", "look lasers"])
    }

    @Test func aStateHandedInKeepsTheBeatReading() {
        var state = OnboardingState()
        state.beat = OnboardingBeatReading(isAvailable: true, isOn: true, look: .lasers, canPulse: true)
        let tour = OnboardingTour(startingAt: .look, state: { state })
        #expect(tour.state.beat.isOn && tour.state.beat.look == .lasers)
        #expect(OnboardingBeatReading().isOn == false && OnboardingBeatReading().look == .glow)
    }
}
