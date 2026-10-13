import AppKit
import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

// The lights on the glow page: what the notes under them say, the switch that
// turns on Glow with music, the picture that follows Reduce Motion and Dim
// flashing lights, and the keys the tour window leaves alone while the design
// kit's loupe is up. Nothing here listens to a sound device, shows a window or
// writes the real settings.

// MARK: - The reading

struct OnboardingBeatReadingTests {
    private func reading(
        _ change: (inout NookDisplayPreferences) -> Void = { _ in },
        cannotHear: Bool = false,
        policy: IslandMotionPolicy = .full,
        reduceMotion: Bool = false,
        dims: Bool = false
    ) -> OnboardingBeatReading {
        var display = NookDisplayPreferences()
        change(&display)
        return OnboardingBeatReading(
            display: display,
            cannotHear: cannotHear,
            policy: policy,
            reduceMotion: reduceMotion,
            dimsFlashingLights: dims,
            isAvailable: true
        )
    }

    @Test func aDisplayWithTheGlowAndTheMusicOnCanPulse() {
        let beat = reading()
        #expect(beat.canPulse && !beat.needsGlowWithMusic && !beat.glowIsOff)
        #expect(beat.canRunNow && !beat.cannotHear)
    }

    @Test func glowWithMusicBeingOffIsTheOnlyThingTheSwitchSetsItself() {
        let beat = reading { $0.haloFollowsMusic = false }
        #expect(beat.canPulse, "the switch can still be flipped")
        #expect(beat.needsGlowWithMusic)
    }

    @Test func theGlowBeingOffLeavesTheSwitchDeadAndSaysWhy() {
        let beat = reading { $0.haloStyle = .off; $0.haloFollowsMusic = false }
        #expect(!beat.canPulse && beat.glowIsOff)
        #expect(!beat.needsGlowWithMusic, "nothing to turn on while the glow is off")
        #expect(OnboardingLightsRow.noteKeys(for: beat) == ["onboarding.look.beat.needsGlow"])
    }

    @Test func aClosedIslandThatShowsNoMusicLeavesTheSwitchDeadAndSaysThat() {
        let beat = reading { $0.mediaStyle = .off }
        #expect(!beat.canPulse && !beat.glowIsOff)
        #expect(OnboardingLightsRow.noteKeys(for: beat) == ["onboarding.look.beat.needsMusic"])
    }

    @Test func theMotionPolicyDecidesWhetherTheLightsCanRunNow() {
        #expect(reading(policy: .full).canRunNow)
        #expect(!reading(policy: .conserving).canRunNow, "Low Power Mode")
        #expect(!reading(policy: .minimal).canRunNow, "a critical heat")
        #expect(!reading(policy: .reduced, reduceMotion: true).canRunNow)
    }

    // MARK: Notes

    @Test func macOSRefusingShowsSettingsCaptionAsTheFirstNote() {
        let refused = reading(cannotHear: true)
        #expect(OnboardingLightsRow.noteKeys(for: refused) == ["settings.appearance.nook.halo.beat.cannotHear"])
        #expect(OnboardingLightsRow.cannotHearKey == "settings.appearance.nook.halo.beat.cannotHear")
    }

    @Test func lowPowerOrHeatAddsANoteThatTheLightsAreHeldBack() {
        #expect(OnboardingLightsRow.noteKeys(for: reading(policy: .conserving))
            == ["onboarding.look.beat.note", "onboarding.look.beat.held"])
        #expect(OnboardingLightsRow.noteKeys(for: reading(cannotHear: true, policy: .minimal))
            == ["settings.appearance.nook.halo.beat.cannotHear", "onboarding.look.beat.held"])
        // Held back, the flashes are not the news: the second note is one.
        #expect(OnboardingLightsRow.noteKeys(for: reading(policy: .conserving, dims: true))
            == ["onboarding.look.beat.note", "onboarding.look.beat.held"])
    }

    @Test func reduceMotionStillStandsAloneBeforeEverythingElse() {
        let beat = reading(cannotHear: true, policy: .reduced, reduceMotion: true, dims: true)
        #expect(OnboardingLightsRow.noteKeys(for: beat) == ["onboarding.look.beat.reduceMotion"])
    }

    /// Whatever the combination, at most two notes show and each has words in
    /// every language.
    @Test func everyCombinationShowsAtMostTwoNotesAndEachHasItsWords() throws {
        let tables = try HangoverBrandTests.languages.map { try HangoverBrandTests.table($0) }
        for bits in 0..<(1 << 7) {
            func bit(_ index: Int) -> Bool { bits & (1 << index) != 0 }
            let beat = OnboardingBeatReading(
                isAvailable: bit(0), isOn: bit(1), look: .glow, canPulse: bit(2), needsGlowWithMusic: bit(3),
                glowIsOff: bit(4), cannotHear: bit(5), canRunNow: bit(6), reduceMotion: bit(0) && bit(4),
                dimsFlashingLights: bit(1) && bit(3)
            )
            let keys = OnboardingLightsRow.noteKeys(for: beat)
            #expect(keys.count <= 2, "\(bits)")
            for key in keys {
                for table in tables { #expect(!(table[key] ?? "").isEmpty, "\(key)") }
            }
        }
    }

    @Test func theSummaryLeavesTheLightsOutWhenMacOSRefused() {
        var beat = reading()
        #expect(!beat.showsInSummary, "not switched on")
        beat.isOn = true
        #expect(beat.showsInSummary)
        beat.cannotHear = true
        #expect(!beat.showsInSummary)
        beat.cannotHear = false
        beat.isAvailable = false
        #expect(!beat.showsInSummary)

        var state = OnboardingState()
        state.beat = reading { $0.haloPulsesWithBeat = true }
        #expect(OnboardingRecapRow.shown(length: .long, agentsEnabled: true, hasLights: state.beat.showsInSummary).contains(.lights))
        state.beat.cannotHear = true
        #expect(!OnboardingRecapRow.shown(length: .long, agentsEnabled: true, hasLights: state.beat.showsInSummary).contains(.lights))
    }
}

// MARK: - The words

struct OnboardingBeatWordsTests {
    /// macOS asks when the first sound is heard, not when the switch is
    /// flipped, and the three places that mention it agree.
    @Test func theThreePlacesSayMacOSAsksTheFirstTimeMusicPlays() throws {
        let english = try HangoverBrandTests.table("en")
        for key in ["onboarding.look.beat.note", "onboarding.permissions.audio.note", "onboarding.more.lights.note"] {
            let value = try #require(english[key])
            #expect(value.contains("first time music plays"), "\(key): \(value)")
            #expect(!value.contains("when you switch"), "\(key): \(value)")
        }
    }

    @Test(arguments: HangoverBrandTests.languages)
    func glowWithMusicIsNamedTheWaySettingsNamesIt(language: String) throws {
        let table = try HangoverBrandTests.table(language)
        let name = try #require(table["settings.appearance.nook.halo.music.title"])
        let line = try #require(table["onboarding.look.beat.text.withMusic"])
        #expect(line.contains("%@"), "the card's line takes the name from Settings")
        let said = line.replacingOccurrences(of: "%@", with: name)
        #expect(said.contains(name))
        for key in ["onboarding.look.beat.needsGlow", "onboarding.look.beat.needsMusic", "onboarding.look.beat.held"] {
            #expect(!(table[key] ?? "").isEmpty, "\(language) is missing \(key)")
        }
    }

    /// The old Chinese name for glow with music is nowhere in the tour.
    @Test func noChineseStringUsesTheOldNameForGlowWithMusic() throws {
        for language in ["zh-Hans", "zh-Hant"] {
            let table = try HangoverBrandTests.table(language)
            for (key, value) in table where key.hasPrefix("onboarding.") {
                #expect(!value.contains("随音乐发光") && !value.contains("隨音樂發光"), "\(language) \(key)")
            }
        }
    }

    @Test func theGlowNoteSendsTheUserToTheStrengthCardsOnThePageNotToSettings() throws {
        for language in HangoverBrandTests.languages {
            let table = try HangoverBrandTests.table(language)
            let subtle = try #require(table["settings.appearance.nook.halo.subtle"])
            let vivid = try #require(table["settings.appearance.nook.halo.vivid"])
            let note = try #require(table["onboarding.look.beat.needsGlow"])
            #expect(note.contains(subtle) && note.contains(vivid), "\(language): \(note)")
        }
        let english = try HangoverBrandTests.table("en")
        #expect(!(english["onboarding.look.beat.needsGlow"] ?? "").contains("Settings"))
    }
}

// MARK: - The switch

@MainActor
struct OnboardingBeatSwitchTests {
    private static func model() -> AppModel {
        let nook = NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
        let model = AppModel(agentsDefaults: MemoryDefaults(), defaults: MemoryDefaults(), nookModel: nook)
        nook.activeProfile = { [weak model] in model?.activeAppearanceProfile ?? .topBar }
        return model
    }

    private func display(_ model: AppModel) -> NookDisplayPreferences {
        model.nook.displayPreferences(for: model.activeAppearanceProfile)
    }

    private func set(_ model: AppModel, _ change: (inout NookDisplayPreferences) -> Void) {
        model.nook.updateDisplayPreferences(for: model.activeAppearanceProfile, change)
    }

    @Test func withTheGlowAndGlowWithMusicOnTheSwitchTurnsOnThePulseAlone() {
        let model = Self.model()
        #expect(model.onboardingState.beat.canPulse && !model.onboardingState.beat.needsGlowWithMusic)

        model.setTourBeatPulse(true)

        #expect(display(model).haloPulsesWithBeat && display(model).haloFollowsMusic)
        #expect(model.onboardingState.beat.isOn)
    }

    /// A layout can leave Glow with music off. The switch then turns it on
    /// with the pulse, and the card's line names it.
    @Test func withGlowWithMusicOffTheSwitchTurnsItOnTogetherWithThePulse() {
        let model = Self.model()
        set(model) { $0.haloFollowsMusic = false }
        let before = model.onboardingState.beat
        #expect(before.canPulse && before.needsGlowWithMusic)

        model.setTourBeatPulse(true)

        let after = model.onboardingState.beat
        #expect(display(model).haloPulsesWithBeat)
        #expect(display(model).haloFollowsMusic)
        #expect(after.isOn && !after.needsGlowWithMusic)
    }

    @Test func withTheGlowOffTheSwitchIsDeadAndWritesNothing() {
        let model = Self.model()
        set(model) { $0.haloStyle = .off; $0.haloFollowsMusic = false }
        let before = display(model)

        model.setTourBeatPulse(true)

        #expect(display(model) == before, "nothing was written")
        let beat = model.onboardingState.beat
        #expect(!beat.canPulse && beat.glowIsOff && !beat.isOn)
        #expect(OnboardingLightsRow.noteKeys(for: beat) == ["onboarding.look.beat.needsGlow"])

        // Picking a strength on the same page brings the switch back, and
        // then it turns on Glow with music with the pulse.
        set(model) { $0.haloStyle = .subtle }
        #expect(model.onboardingState.beat.needsGlowWithMusic)
        model.setTourBeatPulse(true)
        #expect(display(model).haloPulsesWithBeat && display(model).haloFollowsMusic)
    }

    @Test func switchingOffIsAlwaysAllowedAndLeavesGlowWithMusicAlone() {
        let model = Self.model()
        model.setTourBeatPulse(true)
        set(model) { $0.haloStyle = .off }

        model.setTourBeatPulse(false)

        #expect(!display(model).haloPulsesWithBeat)
        #expect(display(model).haloFollowsMusic)
    }

    @Test func theTourReadsWhetherMacOSRefusedFromTheBeatController() {
        let model = Self.model()
        #expect(!model.onboardingState.beat.cannotHear, "nothing was heard or refused in a fresh app")
    }
}

// MARK: - The picture

struct OnboardingBeatPictureTests {
    @Test func theBarHasHitsCloserThanTheDimmedGap() {
        // The test below means something only because the plain bar does.
        let hits = OnboardingBeatLoop.steps(dimmed: false).enumerated().filter { $0.element > 0 }.map(\.offset)
        let gaps = zip(hits, hits.dropFirst()).map { Double($1 - $0) * OnboardingBeatLoop.stepDuration }
        #expect(gaps.contains { $0 < IslandBeatLimits.dimmedFlashGap })
    }

    /// With Dim flashing lights on, no two hits are closer than the constant
    /// the real lights use, inside a bar and between bars, and no second
    /// holds more flashes than the setting allows.
    @Test func theDimmedPatternKeepsEveryHitTheDimmedGapApart() {
        let steps = OnboardingBeatLoop.steps(dimmed: true)
        #expect(steps.count == OnboardingBeatLoop.stepCount)
        let hits = steps.enumerated().filter { $0.element > 0 }.map(\.offset)
        #expect(hits.count > 3, "it still plays a beat")
        for (before, after) in zip(hits, hits.dropFirst()) {
            let gap = Double(after - before) * OnboardingBeatLoop.stepDuration
            #expect(gap >= IslandBeatLimits.dimmedFlashGap, "hits at steps \(before) and \(after) are \(gap) s apart")
        }
        for start in hits {
            let inASecond = hits.filter {
                Double($0 - start) * OnboardingBeatLoop.stepDuration >= 0
                    && Double($0 - start) * OnboardingBeatLoop.stepDuration < 1
            }
            #expect(inASecond.count <= IslandBeatLimits.dimmedFlashesPerSecond)
        }
    }

    @Test func theDimmedPatternOnlyLeavesHitsOutAndKeepsTheFirst() {
        let plain = OnboardingBeatLoop.steps(dimmed: false)
        let dimmed = OnboardingBeatLoop.steps(dimmed: true)
        #expect(dimmed.first == plain.first)
        for (a, b) in zip(plain, dimmed) { #expect(b == a || b == 0) }
        #expect(OnboardingBeatLoop.strength(at: 0, dimmed: true) == 1)
        #expect(OnboardingBeatLoop.strength(at: 5, dimmed: false) == 0.3)
        #expect(OnboardingBeatLoop.strength(at: 5, dimmed: true) == 0)
        #expect(OnboardingBeatLoop.strength(at: -1, dimmed: true) == 0)
        for step in 0..<OnboardingBeatLoop.stepCount {
            #expect((0..<OnboardingBeatLoop.hues.count).contains(OnboardingBeatLoop.hue(at: step, dimmed: true)))
        }
    }

    @Test func theCallersHandThePictureWhatMacOSSays() throws {
        for file in ["OnboardingLightsRow.swift", "OnboardingMorePage.swift"] {
            let source = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Onboarding/\(file)")
            #expect(source.contains("reduceMotion:") && source.contains("dimsFlashingLights:"), "\(file)")
        }
    }

    @MainActor
    @Test func withReduceMotionThePictureDrawsTheSameAsTheStillPeakFrame() throws {
        func png(reduceMotion: Bool, still: Bool) throws -> Data {
            let view = OnboardingBeatPicture(look: .glow, reduceMotion: reduceMotion)
                .padding(8)
                .background(Color.black)
                .environment(\.nookDrawsStill, still)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            return try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        }
        let peak = try png(reduceMotion: false, still: true)
        let reduced = try png(reduceMotion: true, still: false)
        #expect(reduced == peak, "Reduce Motion draws the peak frame")
    }

    @Test func reduceMotionDrawsThePeakFrameWhateverStepIsPlayingAndPlaysNothing() {
        for step in [nil, 0, 2, 5, 17] as [Int?] {
            #expect(OnboardingBeatPicture.shownStep(playing: step, drawsStill: false, reduceMotion: true) == 0)
            #expect(OnboardingBeatPicture.shownStep(playing: step, drawsStill: true, reduceMotion: false) == 0)
            #expect(OnboardingBeatPicture.shownStep(playing: step, drawsStill: false, reduceMotion: false) == step)
        }
        #expect(!OnboardingBeatPicture.plays(reduceMotion: true))
        #expect(OnboardingBeatPicture.plays(reduceMotion: false))
    }
}

// MARK: - The keys

struct OnboardingKeyRuleTests {
    @Test func theWindowTakesKeysUnlessTheLoupeIsUpOrJustWent() {
        #expect(OnboardingKeyRule.takesKeys(isSampling: false, isSettling: false))
        #expect(!OnboardingKeyRule.takesKeys(isSampling: true, isSettling: false))
        #expect(!OnboardingKeyRule.takesKeys(isSampling: false, isSettling: true))
        #expect(!OnboardingKeyRule.takesKeys(isSampling: true, isSettling: true))
        #expect(OnboardingKeyRule.settle > .zero)
    }

    /// Escape, Return and both arrows: none has a shortcut while the window
    /// takes no key. None can skip, turn or end the tour.
    @Test(arguments: OnboardingKey.allCases)
    func noKeyReachesAButtonWhileTheWindowTakesNone(key: OnboardingKey) {
        #expect(OnboardingKeyRule.shortcut(for: key, takesKeys: false) == nil)
        #expect(OnboardingKeyRule.shortcut(for: key, takesKeys: true) == key.shortcut)
    }

    @Test func theKeysAreTheOnesTheNavigationBarHadBefore() {
        #expect(OnboardingKey.escape.shortcut == .cancelAction)
        #expect(OnboardingKey.returnKey.shortcut == .defaultAction)
        #expect(OnboardingKey.leftArrow.shortcut == KeyboardShortcut(.leftArrow, modifiers: []))
        #expect(OnboardingKey.rightArrow.shortcut == KeyboardShortcut(.rightArrow, modifiers: []))
        #expect(OnboardingKey.allCases.count == 4)
    }

    @Test func theNavigationBarTakesItsShortcutsFromTheRuleAndNowhereElse() throws {
        let source = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Onboarding/OnboardingView.swift")
        #expect(source.components(separatedBy: ".keyboardShortcut(").count - 1 == 4)
        #expect(source.components(separatedBy: ".keyboardShortcut(OnboardingKeyRule.shortcut(for:").count - 1 == 4)
    }
}

// MARK: - The loupe and the tour

@MainActor
struct OnboardingLoupeReadingTests {
    /// The tour reads that the kit's loupe is up, and that it is gone after a
    /// cancel, which changes nothing else about the tour.
    @Test func theTourReadsTheLoupeUpAndGoneAndACancelMovesNothing() async throws {
        let fixture = try await NookDesignFixture("tour-loupe")
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let nook = NookModel(design: fixture.kit, defaults: MemoryDefaults(), looksForImportedGIF: false)
        let model = AppModel(agentsDefaults: MemoryDefaults(), defaults: MemoryDefaults(), nookModel: nook)
        nook.activeProfile = { [weak model] in model?.activeAppearanceProfile ?? .topBar }
        final class Closed { var count = 0 }
        let closed = Closed()
        let tour = model.makeWelcomeTour(startingAt: .features, close: { closed.count += 1 })
        #expect(!tour.state.features.design.isSampling)
        let page = tour.page

        #expect(fixture.kit.pickColor(from: .shortcut))
        #expect(tour.state.features.design.isSampling)
        #expect(!tour.state.features.design.isReady, "a pick cannot start while one is under way")

        fixture.sampler.finish(nil)

        #expect(!tour.state.features.design.isSampling)
        #expect(tour.page == page, "a cancelled pick never turns or ends the tour")
        #expect(closed.count == 0)
    }
}
