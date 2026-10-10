import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

@Suite struct NookDisplayPreferencesTests {
    private static let media = NookClosedMediaActivity(
        artwork: nil,
        gifURL: nil,
        gifScale: 1,
        gifOffset: .zero,
        isPlaying: true
    )

    private static func makeDefaults() -> UserDefaults { MemoryDefaults() }

    // MARK: Closed island

    @Test func artAndVisualFillsBothSidesAndYieldsToWaitingAgents() {
        let activity = NookClosedActivity.resolve(
            transient: nil, timerText: nil, media: Self.media, preferences: NookDisplayPreferences()
        )

        #expect(activity?.showsArtwork == true)
        #expect(activity?.trailing == .media(Self.media))
        #expect(activity?.yieldsToAgents == true)
    }

    @Test func musicKeepsTheRightSideWhenAgentsMayNotReclaimIt() {
        var preferences = NookDisplayPreferences()
        preferences.agentsReclaimRightSide = false

        let activity = NookClosedActivity.resolve(
            transient: nil, timerText: nil, media: Self.media, preferences: preferences
        )

        #expect(activity?.yieldsToAgents == false)
    }

    @Test func artOnlyLeavesTheRightSideToTheAgents() {
        var preferences = NookDisplayPreferences()
        preferences.mediaStyle = .artOnly

        let activity = NookClosedActivity.resolve(
            transient: nil, timerText: nil, media: Self.media, preferences: preferences
        )

        #expect(activity?.showsArtwork == true)
        #expect(activity?.trailing == nil)
    }

    @Test func offHidesMusicButStillShowsTheTimer() {
        var preferences = NookDisplayPreferences()
        preferences.mediaStyle = .off

        let musicOnly = NookClosedActivity.resolve(
            transient: nil, timerText: nil, media: Self.media, preferences: preferences
        )
        let withTimer = NookClosedActivity.resolve(
            transient: nil, timerText: "24:59", media: Self.media, preferences: preferences
        )

        #expect(musicOnly == nil)
        #expect(withTimer?.trailing == .text("24:59"))
        #expect(withTimer?.showsArtwork == false)
    }

    @Test func noticeBeatsTimerAndTimerBeatsMusic() {
        let notice = NookTransientActivity(symbol: "bolt.fill", text: "Charging")

        let all = NookClosedActivity.resolve(
            transient: notice, timerText: "24:59", media: Self.media, preferences: NookDisplayPreferences()
        )
        let timerAndMusic = NookClosedActivity.resolve(
            transient: nil, timerText: "24:59", media: Self.media, preferences: NookDisplayPreferences()
        )

        #expect(all?.trailing == .text("Charging"))
        #expect(timerAndMusic?.trailing == .text("24:59"))
    }

    @Test func noticeWithALevelShowsTheRingInPlaceOfItsText() {
        let charging = NookTransientActivity(symbol: "bolt.fill", text: "Charging · 78%", tint: .green, level: 78)
        let headphones = NookTransientActivity(symbol: "headphones", text: "AirPods connected")

        let ring = NookClosedActivity.resolve(
            transient: charging, timerText: nil, media: nil, preferences: NookDisplayPreferences()
        )
        let words = NookClosedActivity.resolve(
            transient: headphones, timerText: nil, media: nil, preferences: NookDisplayPreferences()
        )

        #expect(ring?.trailing == .level(percent: 78, tint: .green))
        #expect(ring?.leading == .symbol("bolt.fill", .green))
        #expect(words?.trailing == .text("AirPods connected"))
    }

    @Test func levelRingHoldsItsNumberBetweenZeroAndAHundred() {
        let low: Int = 0
        let high: Int = 100
        let middle: Int = 78
        #expect(NookLevelRingView.clamped(-5) == low)
        #expect(NookLevelRingView.clamped(140) == high)
        #expect(NookLevelRingView.clamped(78) == middle)
    }

    @Test func noticesOffFallsThroughToMusic() {
        var preferences = NookDisplayPreferences()
        preferences.showsNotices = false
        let notice = NookTransientActivity(symbol: "bolt.fill", text: "Charging")

        let withMusic = NookClosedActivity.resolve(
            transient: notice, timerText: "24:59", media: Self.media, preferences: preferences
        )
        let withoutMusic = NookClosedActivity.resolve(
            transient: notice, timerText: "24:59", media: nil, preferences: preferences
        )

        #expect(withMusic?.showsArtwork == true)
        #expect(withoutMusic == nil)
    }

    // MARK: Persistence

    @Test func loadReturnsDefaultsWhenNothingIsStored() {
        #expect(NookDisplayPreferences.load(for: .notch, defaults: Self.makeDefaults()) == NookDisplayPreferences())
    }

    @Test func profilesPersistIndependently() {
        let defaults = Self.makeDefaults()
        var notch = NookDisplayPreferences()
        notch.mediaStyle = .artOnly
        notch.openedPage = .nook
        notch.showsAgentsBar = false
        var topBar = NookDisplayPreferences()
        topBar.centerLabelShowsTrack = true
        topBar.centerLabelShowsNextEvent = true
        topBar.hiddenWidgets = [.mirror, .notes]
        topBar.leftSlot = .countdown
        topBar.rightSlot = .battery
        notch.leftSlot = .grid
        topBar.calendarStyle = .month
        topBar.hiddenCalendarIDs = ["abc", "def"]
        topBar.showsNotices = false

        notch.persist(for: .notch, defaults: defaults)
        topBar.persist(for: .topBar, defaults: defaults)

        #expect(NookDisplayPreferences.load(for: .notch, defaults: defaults) == notch)
        #expect(NookDisplayPreferences.load(for: .topBar, defaults: defaults) == topBar)
    }

    @Test func legacyGlobalSettingsSeedBothProfiles() {
        let defaults = Self.makeDefaults()
        defaults.set("agents", forKey: "nook.openedPage")
        defaults.set(false, forKey: "nook.agents.compactBar")
        defaults.set(false, forKey: "nook.agents.dotOnArt")
        defaults.set(false, forKey: "nook.media.closedActivityEnabled")

        for profile in IslandAppearanceDisplayProfile.allCases {
            let loaded = NookDisplayPreferences.load(for: profile, defaults: defaults)
            #expect(loaded.openedPage == .agents)
            #expect(loaded.showsCompactBar == false)
            #expect(loaded.showsAgentDotOnArt == false)
            #expect(loaded.mediaStyle == .off)
        }
    }

    @Test func perDisplayValueWinsOverLegacySetting() {
        let defaults = Self.makeDefaults()
        defaults.set("agents", forKey: "nook.openedPage")
        var notch = NookDisplayPreferences()
        notch.openedPage = .nook
        notch.persist(for: .notch, defaults: defaults)

        #expect(NookDisplayPreferences.load(for: .notch, defaults: defaults).openedPage == .nook)
        #expect(NookDisplayPreferences.load(for: .topBar, defaults: defaults).openedPage == .agents)
    }

    // MARK: Changed-field saves

    /// Keys whose stored value differs between two snapshots of a store.
    private static func changedKeys(_ before: [String: Any], _ after: [String: Any]) -> Set<String> {
        Set(before.keys).union(after.keys).filter { key in
            guard let old = before[key] as? NSObject, let new = after[key] as? NSObject else {
                return (before[key] == nil) != (after[key] == nil)
            }
            return !old.isEqual(new)
        }
    }

    private static func keysWritten(
        from old: NookDisplayPreferences,
        to new: NookDisplayPreferences,
        profile: IslandAppearanceDisplayProfile = .notch
    ) -> Set<String> {
        // A store of its own, in memory. A suite on disk mixes the standard
        // domain into `dictionaryRepresentation()`, which other tests write
        // while this one runs, and those writes were counted as this save's keys.
        let defaults = MemoryDefaults()
        func ownValues() -> [String: Any] { defaults.all }
        old.persist(for: profile, defaults: defaults)
        let before = ownValues()

        new.persistChanges(from: old, for: profile, defaults: defaults)

        return changedKeys(before, ownValues())
    }

    @Test func persistChangesWritesExactlyOneKeyWhenOneFieldChanges() {
        var withRightSlot = NookDisplayPreferences()
        withRightSlot.rightSlot = .battery
        let changes: [(String, NookDisplayPreferences, NookDisplayPreferences)] = [
            ("mediaStyle", NookDisplayPreferences(), { var p = NookDisplayPreferences(); p.mediaStyle = .artOnly; return p }()),
            ("notices", NookDisplayPreferences(), { var p = NookDisplayPreferences(); p.showsNotices = false; return p }()),
            ("hiddenWidgets", NookDisplayPreferences(), { var p = NookDisplayPreferences(); p.hiddenWidgets = [.mirror]; return p }()),
            ("rightSlot set", NookDisplayPreferences(), withRightSlot),
            ("rightSlot cleared", withRightSlot, NookDisplayPreferences()),
            ("calendarStyle", NookDisplayPreferences(), { var p = NookDisplayPreferences(); p.calendarStyle = .month; return p }()),
            ("haloStyle", NookDisplayPreferences(), { var p = NookDisplayPreferences(); p.haloStyle = .vivid; return p }()),
            ("haloFollowsMusic", NookDisplayPreferences(), { var p = NookDisplayPreferences(); p.haloFollowsMusic = false; return p }()),
            ("widgetOrder", NookDisplayPreferences(), { var p = NookDisplayPreferences(); p.widgetOrder = [.timer, .media]; return p }()),
            ("widgetSizes", NookDisplayPreferences(), { var p = NookDisplayPreferences(); p.widgetSizes = [.notes: .large]; return p }()),
        ]

        for (name, old, new) in changes {
            let written = Self.keysWritten(from: old, to: new)
            #expect(written.count == 1, "\(name) wrote \(written)")
        }
    }

    @Test func persistChangesWritesNothingWhenNothingChanged() {
        let preferences = NookDisplayPreferences()

        #expect(Self.keysWritten(from: preferences, to: preferences).isEmpty)
    }

    @Test func persistChangesUsesTheSameKeyAsPersist() {
        var changed = NookDisplayPreferences()
        changed.haloStyle = .vivid
        let viaPersist = Self.makeDefaults()
        changed.persist(for: .topBar, defaults: viaPersist)
        let viaChanges = Self.makeDefaults()
        changed.persistChanges(from: NookDisplayPreferences(), for: .topBar, defaults: viaChanges)

        #expect(viaChanges.string(forKey: "nook.display.topBar.haloStyle") == "vivid")
        #expect(viaChanges.string(forKey: "nook.display.topBar.haloStyle") == viaPersist.string(forKey: "nook.display.topBar.haloStyle"))
    }

    @Test func persistChangesRoundTripsThroughLoad() {
        let defaults = Self.makeDefaults()
        var old = NookDisplayPreferences()
        old.rightSlot = .count
        old.persist(for: .topBar, defaults: defaults)
        var new = old
        new.rightSlot = nil
        new.leftSlot = .battery
        new.mediaStyle = .off
        new.hiddenCalendarIDs = ["a", "b"]
        new.widgetSizes = [.timer: .small, .calendar: .large]
        new.widgetOrder = [.timer, .notes]

        new.persistChanges(from: old, for: .topBar, defaults: defaults)

        #expect(NookDisplayPreferences.load(for: .topBar, defaults: defaults) == new)
    }

    @Test func haloFieldsRoundTrip() {
        let defaults = Self.makeDefaults()
        var preferences = NookDisplayPreferences()
        preferences.haloStyle = .vivid
        preferences.haloFollowsMusic = false

        preferences.persist(for: .notch, defaults: defaults)
        let loaded = NookDisplayPreferences.load(for: .notch, defaults: defaults)

        #expect(loaded.haloStyle == .vivid)
        #expect(loaded.haloFollowsMusic == false)
        #expect(NookDisplayPreferences.load(for: .topBar, defaults: defaults).haloStyle == .subtle)
    }

    @Test func haloFieldsRoundTripThroughPersistChanges() {
        let defaults = Self.makeDefaults()
        let old = NookDisplayPreferences()
        old.persist(for: .notch, defaults: defaults)
        var new = old
        new.haloStyle = .off
        new.haloFollowsMusic = false

        new.persistChanges(from: old, for: .notch, defaults: defaults)
        let loaded = NookDisplayPreferences.load(for: .notch, defaults: defaults)

        #expect(loaded.haloStyle == .off)
        #expect(loaded.haloFollowsMusic == false)
    }

    @Test @MainActor func editingTheOtherProfileDoesNotRepositionTheIsland() {
        let nook = NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
        nook.activeProfile = { .notch }
        var repositionCount = 0
        nook.onDisplayPreferencesChanged = { repositionCount += 1 }

        // Toggles, so the edit is a real change however earlier runs left the stored values.
        nook.updateDisplayPreferences(for: .topBar) { $0.showsNotices.toggle() }
        let afterOtherProfile = repositionCount
        nook.updateDisplayPreferences(for: .notch) { $0.showsNotices.toggle() }
        let afterActiveProfile = repositionCount

        #expect(afterOtherProfile == 0)
        #expect(afterActiveProfile == 1)

        // Put the stored values back.
        nook.updateDisplayPreferences(for: .topBar) { $0.showsNotices.toggle() }
        nook.updateDisplayPreferences(for: .notch) { $0.showsNotices.toggle() }
    }

    // MARK: Left slot

    @Test func calendarDefaultsToTheDayStripAndLeftSlotToAgents() {
        #expect(NookDisplayPreferences().calendarStyle == .strip)
        #expect(NookDisplayPreferences().leftSlot == .agents)
    }

    @Test func countdownTextScalesFromMinutesToDays() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(NookSideSlotContent.countdownText(to: now.addingTimeInterval(41 * 60 + 5), now: now) == "42m")
        #expect(NookSideSlotContent.countdownText(to: now.addingTimeInterval(3 * 3600 + 600), now: now) == "3h")
        #expect(NookSideSlotContent.countdownText(to: now.addingTimeInterval(50 * 3600), now: now) == "2d")
        #expect(NookSideSlotContent.countdownText(to: now.addingTimeInterval(-60), now: now) == nil)
    }

    @Test func meetingLinksAreFoundInAnyField() {
        let zoom = NookMeetingLink.find(in: [nil, "Royce 190", "Join: https://ucla.zoom.us/j/123456 thanks"])
        let none = NookMeetingLink.find(in: ["https://example.com/agenda", "Room 4"])

        #expect(zoom?.host == "ucla.zoom.us")
        #expect(none == nil)
    }

    // MARK: Center label

    @Test @MainActor func longTrackTitlesAreTruncatedToTheLimit() {
        let short = AppModel.truncatedLabel("Bitch Too", limit: 26)
        let long = AppModel.truncatedLabel("A Very Long Track Title That Keeps Going", limit: 26)

        #expect(short == "Bitch Too")
        #expect(long.count <= 26)
        #expect(long.hasSuffix("…"))
    }
}
