import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

// The welcome tour's choices as plain values (D43): the closed island's
// picks, the widgets a page draws and the glow's legend.

// MARK: - The closed island's picks

struct OnboardingClosedSideTests {
    /// The right side's cards in Settings: the island's own three
    /// (`rightSlotSection`) and the Nook's extras (`nookRightSlotExtras`).
    private static let settingsRightWithAgents: [IslandRightSideChoice] = [
        .own(.count), .own(.agents), .own(.none),
        .extra(.agents), .extra(.date), .extra(.battery), .extra(.countdown),
        .extra(.weather), .extra(.timer), .extra(.todos),
    ]

    @Test func thePageOffersEveryCardSettingsOffersForTheRightSide() {
        let offered = OnboardingClosedSide.offered(agentsEnabled: true)
        #expect(offered == [.count, .agents, .bars, .date, .battery, .countdown, .weather, .timer, .todos, .nothing])
        let choices = offered.map(\.choice)
        #expect(Self.settingsRightWithAgents.allSatisfy { choices.contains($0) })
        #expect(offered.count == Self.settingsRightWithAgents.count, "no card twice")
    }

    /// Off, Settings keeps two rows (`nookRightSlotWithoutAgents`): none, date,
    /// battery, countdown, then weather, timer, to-dos.
    @Test func withTheAgentsOffThePageOffersSettingsOneRow() {
        let offered = OnboardingClosedSide.offered(agentsEnabled: false)
        #expect(offered == [.date, .battery, .countdown, .weather, .timer, .todos, .nothing])
        let slots = offered.map { $0.write(agentsEnabled: false) }
        let settings = AppearanceSettingsPane.sideSlotsWithoutAgents
        #expect(Set(settings) == [.none, .date, .battery, .countdown, .weather, .timer, .todos])
        #expect(slots == [
            .choice(.extra(.date)), .choice(.extra(.battery)), .choice(.extra(.countdown)),
            .choice(.extra(.weather)), .choice(.extra(.timer)), .choice(.extra(.todos)), .clearNookItem,
        ])
        #expect(OnboardingClosedSide.allCases.filter(\.needsAgents) == [.count, .agents, .bars])
    }

    @Test func onlyTheCountdownReadsTheCalendar() {
        #expect(OnboardingClosedSide.allCases.filter(\.needsCalendar) == [.countdown])
        #expect(OnboardingClosedLeft.allCases.filter(\.needsCalendar) == [.countdown])
    }

    /// Weather needs a city, the to-dos need a source, and the line under a
    /// group names each need once.
    @Test func theNewPicksSayWhatTheyNeed() {
        #expect(OnboardingClosedSide.allCases.filter { $0.need == .weatherCity } == [.weather])
        #expect(OnboardingClosedSide.allCases.filter { $0.need == .todoSource } == [.todos])
        #expect(OnboardingClosedLeft.allCases.filter { $0.need == .weatherCity } == [.weather])
        #expect(OnboardingClosedLeft.allCases.filter { $0.need == .todoSource } == [.todos])
        #expect(OnboardingClosedSide.timer.need == nil)
        #expect(Set(OnboardingClosedNeed.allCases.map(\.textKey)).count == 3)
    }

    /// Every pick is one choice for the whole right side, the value
    /// `AppModel.chooseRightSide` takes (D39).
    @Test func aPickIsWrittenAsOneChoiceForTheWholeRightSide() {
        #expect(OnboardingClosedSide.count.choice == .own(.count))
        #expect(OnboardingClosedSide.agents.choice == .own(.agents))
        #expect(OnboardingClosedSide.bars.choice == .extra(.agents))
        #expect(OnboardingClosedSide.date.choice == .extra(.date))
        #expect(OnboardingClosedSide.battery.choice == .extra(.battery))
        #expect(OnboardingClosedSide.countdown.choice == .extra(.countdown))
        #expect(OnboardingClosedSide.weather.choice == .extra(.weather))
        #expect(OnboardingClosedSide.timer.choice == .extra(.timer))
        #expect(OnboardingClosedSide.todos.choice == .extra(.todos))
        #expect(OnboardingClosedSide.nothing.choice == .own(.none))

        for side in OnboardingClosedSide.allCases {
            #expect(side.write(agentsEnabled: true) == .choice(side.choice))
        }
        #expect(OnboardingClosedSide.date.write(agentsEnabled: false) == .choice(.extra(.date)))
        #expect(OnboardingClosedSide.countdown.write(agentsEnabled: false) == .choice(.extra(.countdown)))
    }

    /// With the agents off the island's own slot is not on screen. Nothing
    /// takes a Nook item off and leaves that slot for when they come back.
    @Test func nothingLeavesTheIslandsOwnSlotAloneWhileTheAgentsAreOff() {
        let write = OnboardingClosedSide.nothing.write(agentsEnabled: false)
        #expect(write == .clearNookItem)

        let cleared = write.applied(own: .count, nook: .date)
        #expect(cleared.own == .count)
        #expect(cleared.nook == nil)

        // A saved Nook slot that shows agents already reads as nothing and
        // is kept too.
        let kept = write.applied(own: .agents, nook: .grid)
        #expect(kept.own == .agents)
        #expect(kept.nook == .grid)
        #expect(OnboardingClosedSide.reading(own: kept.own, nook: kept.nook, agentsEnabled: false) == .nothing)
    }

    @Test(arguments: OnboardingClosedSide.allCases)
    func whatIsWrittenReadsBackAsThePick(side: OnboardingClosedSide) {
        // From a display on the agent tiles, which the right side does not offer.
        let written = side.write(agentsEnabled: true).applied(own: .agents, nook: .grid)

        #expect(OnboardingClosedSide.reading(own: written.own, nook: written.nook, agentsEnabled: true) == side)
    }

    @Test(arguments: OnboardingClosedSide.offered(agentsEnabled: false))
    func whatIsWrittenReadsBackWhileTheAgentsAreOff(side: OnboardingClosedSide) {
        let written = side.write(agentsEnabled: false).applied(own: .count, nook: .battery)

        #expect(OnboardingClosedSide.reading(own: written.own, nook: written.nook, agentsEnabled: false) == side)
    }

    @Test func aPickTheTourDoesNotOfferReadsAsNone() {
        // The agent tiles and the count are the left side's and the island's own.
        #expect(OnboardingClosedSide.reading(own: .none, nook: .grid, agentsEnabled: true) == nil)
        #expect(OnboardingClosedSide.reading(own: .none, nook: .count, agentsEnabled: true) == nil)
        // A saved choice that shows agents reads as Nothing while they are off.
        #expect(OnboardingClosedSide.reading(own: .none, nook: .grid, agentsEnabled: false) == .nothing)
        #expect(OnboardingClosedSide.reading(own: .none, nook: .agents, agentsEnabled: false) == .nothing)
        // The countdown is the Nook's and is offered with the agents off too.
        #expect(OnboardingClosedSide.reading(own: .none, nook: .countdown, agentsEnabled: false) == .countdown)
    }

    @Test func theAppsStartingSetupReadsAsThePicksTheTourOffers() {
        #expect(OnboardingClosedSide.reading(
            own: IslandAppearancePreferences().rightSlot, nook: NookDisplayPreferences().rightSlot, agentsEnabled: true
        ) == .count)
        #expect(OnboardingClosedSide.reading(
            own: IslandAppearancePreferences().rightSlot, nook: NookDisplayPreferences().rightSlot, agentsEnabled: false
        ) == .nothing)
        #expect(OnboardingState().closedSide == .count)
        #expect(OnboardingState().closedLeft == .bars)
    }

    @Test func thePictureDrawsEachPickAndAnEmptySideForTheRest() {
        #expect(OnboardingClosedPage.pillSide(.count) == .count)
        #expect(OnboardingClosedPage.pillSide(.agents) == .agents)
        #expect(OnboardingClosedPage.pillSide(.bars) == .bars)
        #expect(OnboardingClosedPage.pillSide(.date) == .date)
        #expect(OnboardingClosedPage.pillSide(.battery) == .battery)
        #expect(OnboardingClosedPage.pillSide(.countdown) == .countdown)
        #expect(OnboardingClosedPage.pillSide(.weather) == .weather)
        #expect(OnboardingClosedPage.pillSide(.timer) == .timer)
        #expect(OnboardingClosedPage.pillSide(.todos) == .todos)
        #expect(OnboardingClosedPage.pillSide(.nothing) == .nothing)
        #expect(OnboardingClosedPage.pillSide(nil) == .nothing)
    }
}

// MARK: - The left of the closed island

struct OnboardingClosedLeftTests {
    /// The left side's cards in Settings (`nookLeftSlotSection`): the two
    /// rows together, every `NookSideSlot`.
    private static let settingsLeftWithAgents: [NookSideSlot] = [
        .agents, .count, .grid, .none, .date, .battery, .countdown, .weather, .timer, .todos,
    ]

    @Test func thePageOffersEveryCardSettingsOffersForTheLeftSide() {
        let offered = OnboardingClosedLeft.offered(agentsEnabled: true)
        #expect(Set(offered.map(\.slot)) == Set(Self.settingsLeftWithAgents))
        #expect(Set(offered.map(\.slot)) == Set(NookSideSlot.allCases), "Settings offers every slot on the left")
        #expect(offered.count == Self.settingsLeftWithAgents.count, "no card twice")
    }

    @Test func withTheAgentsOffThePageOffersSettingsOneRow() {
        let offered = OnboardingClosedLeft.offered(agentsEnabled: false)
        #expect(Set(offered.map(\.slot)) == Set(AppearanceSettingsPane.sideSlotsWithoutAgents))
        #expect(offered.count == AppearanceSettingsPane.sideSlotsWithoutAgents.count)
        #expect(offered.allSatisfy { !$0.needsAgents })
        #expect(OnboardingClosedLeft.allCases.filter(\.needsAgents) == [.bars, .count, .grid])
    }

    @Test(arguments: OnboardingClosedLeft.allCases)
    func aPickWritesTheSlotSettingsWrites(left: OnboardingClosedLeft) {
        #expect(left.written(over: .date, agentsEnabled: true) == left.slot)
        #expect(OnboardingClosedLeft.reading(left.slot, agentsEnabled: true) == left)
    }

    /// Settings' guard (`slot != .none || !preferences.leftSlot.needsAgents`):
    /// None must not throw away a saved choice that shows agents.
    @Test func nothingKeepsASavedAgentChoiceWhileTheAgentsAreOff() {
        #expect(OnboardingClosedLeft.nothing.written(over: .grid, agentsEnabled: false) == .grid)
        #expect(OnboardingClosedLeft.nothing.written(over: .agents, agentsEnabled: false) == .agents)
        #expect(OnboardingClosedLeft.nothing.written(over: .date, agentsEnabled: false) == .none)
        #expect(OnboardingClosedLeft.nothing.written(over: .grid, agentsEnabled: true) == .none)
        #expect(OnboardingClosedLeft.countdown.written(over: .grid, agentsEnabled: false) == .countdown)
    }

    @Test func aSavedChoiceThatShowsAgentsReadsAsNothingWhileTheyAreOff() {
        for slot in [NookSideSlot.agents, .count, .grid] {
            #expect(OnboardingClosedLeft.reading(slot, agentsEnabled: false) == .nothing)
        }
        #expect(OnboardingClosedLeft.reading(.countdown, agentsEnabled: false) == .countdown)
    }

    @Test func theAppsStartingSetupReadsAsTheBars() {
        #expect(OnboardingClosedLeft.reading(NookDisplayPreferences().leftSlot, agentsEnabled: true) == .bars)
        #expect(OnboardingClosedLeft.reading(NookDisplayPreferences().leftSlot, agentsEnabled: false) == .nothing)
    }

    @Test func eachCardDrawsItsOwnPicture() {
        let pictures = OnboardingClosedLeft.allCases.map { OnboardingClosedPage.leftPillSide($0) }
        #expect(Set(pictures).count == OnboardingClosedLeft.allCases.count)
    }
}

// MARK: - The widgets the tour draws

struct OnboardingWidgetPageTests {
    @Test func theDisplaysOwnPageWinsWhenTheAppHandsOneIn() {
        var state = OnboardingState(appliedTemplate: .planner)
        state.nookPlacements = [NookWidgetPlacement(kind: .timer, size: .small)]

        #expect(state.shownPlacements == [NookWidgetPlacement(kind: .timer, size: .small)])
        #expect(state.showsWidget(.timer))
        #expect(!state.showsWidget(.calendar))
    }

    @Test func aSnapshotDrawsTheTemplatesWidgetsThatAreSwitchedOn() {
        var state = OnboardingState(appliedTemplate: .planner)
        #expect(state.shownPlacements == PersonalizationTemplate.planner.widgets)

        state.enabledWidgets.remove(.calendar)
        #expect(state.shownPlacements == PersonalizationTemplate.planner.widgets.filter { $0.kind != .calendar })
        #expect(!state.showsWidget(.calendar))
    }

    @Test func withNoTemplateThePageIsTheAppsStartingOne() {
        let state = OnboardingState()
        let expected = NookDisplayPreferences().placements(enabled: NookWidgetKind.defaultEnabled)

        #expect(state.shownPlacements == expected)
        #expect(NookWidgetKind.defaultEnabled.allSatisfy(state.showsWidget))
        #expect(!state.showsWidget(.mirror))
    }

    @Test func aPreviewIsNeverDrawnLargerThanLife() {
        let natural = CGSize(width: 700, height: 500)
        #expect(OnboardingScaledPreview<EmptyView>.scale(natural: natural, box: CGSize(width: 350, height: 500)) == 0.5)
        #expect(OnboardingScaledPreview<EmptyView>.scale(natural: natural, box: CGSize(width: 700, height: 125)) == 0.25)
        #expect(OnboardingScaledPreview<EmptyView>.scale(natural: natural, box: CGSize(width: 2000, height: 2000)) == 1)
        #expect(OnboardingScaledPreview<EmptyView>.scale(natural: .zero, box: natural) == 1)
    }

    @MainActor
    @Test func theIslandInAPreviewIsLaidOutAtItsRealSize() {
        let placements = NookDisplayPreferences().placements(enabled: NookWidgetKind.defaultEnabled)
        let size = OnboardingNookPreview.naturalSize(
            placements: placements, calendarStyle: .strip, profile: .notch, look: .standard
        )
        let page = NookPanelView.preferredHeight(for: placements, calendarStyle: .strip, isEditing: false)

        #expect(size.height == PreviewNookPanel.headHeight + page + PreviewNookPanel.footHeight)
        #expect(size.width <= PreviewNookPanel.maxWidth)
        #expect(size.width >= IslandOpenedMetrics.minimumPanelWidth)
    }
}

// MARK: - The glow's legend

struct OnboardingGlowLegendTests {
    @Test func theStandardColorsListEveryMomentWithTheAgentsOn() {
        let entries = OnboardingGlowLegendEntry.entries(palette: .standard, agentsEnabled: true)

        #expect(entries.map(\.id) == ["approval", "question", "completed", "running", "album", "timer", "charger"])
        #expect(entries.first?.color == IslandHaloPalette.standard.approval.color)
        #expect(Set(entries.map(\.labelKey)).count == entries.count)
    }

    @Test func withTheAgentsOffTheLegendNamesNoAgentMoment() {
        let entries = OnboardingGlowLegendEntry.entries(palette: .standard, agentsEnabled: false)

        #expect(entries.map(\.id) == ["album", "timer", "charger"])
    }

    /// A theme gives notices one color. Music still takes the album's.
    @Test func aThemeShowsItsOwnNoticeColor() {
        let palette = IslandHaloTheme.lagoon.palette
        let entries = OnboardingGlowLegendEntry.entries(palette: palette, agentsEnabled: false)

        #expect(entries.map(\.id) == ["album", "notice"])
        #expect(entries.last?.color == palette.notice?.color)
    }

    /// One color for everything does not read the album art.
    @Test func oneColorForEverythingColorsMusicToo() {
        let color = IslandHaloRGB.rgb255(10, 200, 120)
        let entries = OnboardingGlowLegendEntry.entries(palette: .single(color), agentsEnabled: true)

        #expect(entries.map(\.id) == ["approval", "question", "completed", "running", "music", "notice"])
        #expect(entries.allSatisfy { $0.color == color.color })
    }
}
