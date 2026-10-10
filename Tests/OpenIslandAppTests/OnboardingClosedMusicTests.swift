import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

// The closed page's third group, "While music plays" (D43): the same media
// style and switches as Settings' section 04, written the same way.

@MainActor
struct OnboardingClosedMusicTests {
    private func group(agents: Bool, profile: IslandAppearanceDisplayProfile) -> OnboardingClosedMusicGroup {
        let state = OnboardingState(agentsEnabled: agents, displayProfile: profile)
        let context = OnboardingPageContext(state: state, actions: OnboardingActions(), lang: LanguageManager.shared)
        return OnboardingClosedMusicGroup(context: context, cardWidth: 77)
    }

    /// Settings lists these switches in `nookClosedSection`, from the same
    /// list. The tour offers the list Settings draws, for each display and
    /// with the agents on and off.
    @Test(arguments: [true, false], [IslandAppearanceDisplayProfile.notch, .topBar])
    func theTourOffersTheSwitchesSettingsOffers(agents: Bool, profile: IslandAppearanceDisplayProfile) {
        let offered = group(agents: agents, profile: profile).options
        #expect(offered == NookClosedMusicOption.offered(agentsEnabled: agents, profile: profile))
    }

    @Test func theListsForEachDisplayMatchSettings() {
        typealias Option = NookClosedMusicOption
        #expect(Option.offered(agentsEnabled: true, profile: .topBar) == [.reclaim, .dot, .track, .nextEvent, .notices])
        #expect(Option.offered(agentsEnabled: true, profile: .notch) == [.reclaim, .dot, .notices])
        #expect(Option.offered(agentsEnabled: false, profile: .topBar) == [.track, .nextEvent, .notices])
        #expect(Option.offered(agentsEnabled: false, profile: .notch) == [.notices])
        #expect(NookClosedMediaStyle.allCases == [.artAndVisual, .artOnly, .off])
    }

    @Test func aSwitchGreysOutWhereSettingsGreysItOut() {
        #expect(NookClosedMusicOption.reclaim.isEnabled(whenStyle: .artAndVisual))
        #expect(!NookClosedMusicOption.reclaim.isEnabled(whenStyle: .artOnly))
        #expect(!NookClosedMusicOption.reclaim.isEnabled(whenStyle: .off))
        #expect(NookClosedMusicOption.dot.isEnabled(whenStyle: .artOnly))
        #expect(!NookClosedMusicOption.dot.isEnabled(whenStyle: .off))
        #expect(!NookClosedMusicOption.track.isEnabled(whenStyle: .off))
        #expect(NookClosedMusicOption.nextEvent.isEnabled(whenStyle: .off))
        #expect(NookClosedMusicOption.notices.isEnabled(whenStyle: .off))
    }

    @Test(arguments: NookClosedMediaStyle.allCases)
    func aStylePickWritesTheMediaStyle(style: NookClosedMediaStyle) {
        var written = NookDisplayPreferences()
        OnboardingClosedMusicPick.style(style).apply(to: &written)

        var expected = NookDisplayPreferences()
        expected.mediaStyle = style
        #expect(written == expected)
    }

    @Test(arguments: NookClosedMusicOption.allCases, [true, false])
    func aSwitchPickWritesTheFieldSettingsWrites(option: NookClosedMusicOption, isOn: Bool) {
        var written = NookDisplayPreferences()
        OnboardingClosedMusicPick.option(option, isOn: isOn).apply(to: &written)

        var expected = NookDisplayPreferences()
        switch option {
        case .reclaim: expected.agentsReclaimRightSide = isOn
        case .dot: expected.showsAgentDotOnArt = isOn
        case .track: expected.centerLabelShowsTrack = isOn
        case .nextEvent: expected.centerLabelShowsNextEvent = isOn
        case .notices: expected.showsNotices = isOn
        }
        #expect(written == expected)
    }

    @Test func thePicksPersistUnderTheKeysSettingsUses() {
        let defaults = MemoryDefaults()
        let old = NookDisplayPreferences()
        var new = old
        OnboardingClosedMusicPick.style(.artOnly).apply(to: &new)
        OnboardingClosedMusicPick.option(.notices, isOn: false).apply(to: &new)
        new.persistChanges(from: old, for: .topBar, defaults: defaults)

        let loaded = NookDisplayPreferences.load(for: .topBar, defaults: defaults)
        #expect(loaded.mediaStyle == .artOnly)
        #expect(!loaded.showsNotices)
        #expect(OnboardingClosedMusic(loaded).style == .artOnly)
        #expect(!OnboardingClosedMusic(loaded).onOptions.contains(.notices))
    }

    @Test func theStartingSetupReadsAsTheAppsDefaults() {
        let music = OnboardingClosedMusic()
        #expect(music.style == .artAndVisual)
        #expect(music.onOptions == [.reclaim, .dot, .notices])
        #expect(OnboardingState().closedMusic == music)
    }

    @Test func aMusicPickReachesTheAppOnceAndComesBackAfterATemplate() {
        var calls: [OnboardingClosedMusicPick] = []
        var actions = OnboardingActions()
        actions.setClosedMusic = { calls.append($0) }
        actions.applyTemplate = { _ in }
        let tour = OnboardingTour(state: { OnboardingState() }, actions: actions)

        tour.actions.setClosedMusic(.style(.artOnly))
        tour.actions.setClosedMusic(.option(.dot, isOn: false))
        tour.actions.setClosedMusic(.option(.dot, isOn: true))
        #expect(calls.count == 3)

        calls.removeAll()
        tour.actions.applyTemplate(.planner)
        // The style first, then the last value of each switch picked.
        #expect(calls == [.style(.artOnly), .option(.dot, isOn: true)])
    }
}
