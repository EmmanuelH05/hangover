import Foundation

/// What the closed island does on one display while music plays.
enum NookClosedMediaStyle: String, CaseIterable, Identifiable, Sendable {
    /// Album art on the left, the GIF or visualizer on the right.
    case artAndVisual
    /// Album art on the left; the right side stays with the agents.
    case artOnly
    /// Music never changes the closed island on this display.
    case off

    var id: String { rawValue }
}

/// What one side of the closed island shows when no agent is waiting and
/// no music, timer or notice has taken it. Both sides take the same set.
enum NookSideSlot: String, CaseIterable, Identifiable, Sendable {
    /// The agent activity bars.
    case agents
    /// The "×N" session count.
    case count
    /// One tile per agent session.
    case grid
    /// Today's date as a small calendar tile.
    case date
    case battery
    /// Time left until the next event.
    case countdown
    case none

    var id: String { rawValue }
}

/// How the Nook shares the island with the agents on one kind of display.
/// The Personalization tab keeps one set for the MacBook notch and one for
/// external displays, next to `IslandAppearancePreferences`.
struct NookDisplayPreferences: Equatable, Sendable {
    var mediaStyle: NookClosedMediaStyle = .artAndVisual
    /// An agent waiting on the user takes the right side back from the GIF.
    var agentsReclaimRightSide = true
    /// Small agent status dot on the album art.
    var showsAgentDotOnArt = true
    /// Timer countdown and short notices (charger, headphones, next event).
    var showsNotices = true
    /// External displays: the track title replaces the agent label.
    var centerLabelShowsTrack = false
    /// External displays: the next calendar event fills the center label
    /// while no agent has anything to say.
    var centerLabelShowsNextEvent = false
    /// Widgets left off the Nook page on this display. The Nook tab's
    /// switches stay the master list; this only hides.
    var hiddenWidgets: Set<NookWidgetKind> = []
    /// What the left of the closed island shows while nothing else claims it.
    var leftSlot: NookSideSlot = .agents
    /// Nil keeps the island's own right slot setting (count, agents, none).
    var rightSlot: NookSideSlot? = nil
    var calendarStyle: NookCalendarStyle = .strip
    /// Calendars left out of every calendar view on this display.
    var hiddenCalendarIDs: Set<String> = []
    var openedPage: NookOpenedPage = .auto
    /// Now-playing row under the agent list.
    var showsCompactBar = true
    /// Agent summary row above the Nook widgets.
    var showsAgentsBar = true
    /// Order of the widgets on the Nook page. Kinds missing from the list
    /// go after it in their default order.
    var widgetOrder: [NookWidgetKind] = NookWidgetKind.allCases
    /// Sizes the user picked. A widget not listed is medium.
    var widgetSizes: [NookWidgetKind: NookWidgetSize] = [:]
    /// Glow around the closed island for agent states, notices and music.
    var haloStyle: IslandHaloStyle = .subtle
    /// The glow takes the album art's color while music plays.
    var haloFollowsMusic = true
    /// The glow's color for each moment, and the one color that can stand
    /// in for all of them (D31). A template leaves these alone.
    var haloColors = IslandHaloColors.standard
    /// How wide the opened island is and what its corners look like (D35).
    /// A template leaves this alone.
    var openedLook = IslandOpenedLook.standard
}

extension NookDisplayPreferences {
    /// `widgetOrder` with duplicates dropped and every kind present.
    var normalizedWidgetOrder: [NookWidgetKind] {
        var seen = Set<NookWidgetKind>()
        let listed = widgetOrder.filter { seen.insert($0).inserted }
        return listed + NookWidgetKind.allCases.filter { !seen.contains($0) }
    }

    func size(of kind: NookWidgetKind) -> NookWidgetSize {
        widgetSizes[kind] ?? .medium
    }

    /// The widgets on the page for this display, in order, with sizes:
    /// switched on in the Nook tab and not hidden here.
    func placements(enabled: [NookWidgetKind]) -> [NookWidgetPlacement] {
        let enabledSet = Set(enabled)
        return normalizedWidgetOrder
            .filter { enabledSet.contains($0) && !hiddenWidgets.contains($0) }
            .map { NookWidgetPlacement(kind: $0, size: size(of: $0)) }
    }
}

extension NookDisplayPreferences {
    private static func key(_ profile: IslandAppearanceDisplayProfile, _ name: String) -> String {
        "nook.display.\(profile.rawValue).\(name)"
    }

    /// Keys from before these choices were per display. They seed both
    /// profiles the first time, which keeps an existing setup unchanged.
    private enum LegacyKey {
        static let openedPage = "nook.openedPage"
        static let compactBar = "nook.agents.compactBar"
        static let dotOnArt = "nook.agents.dotOnArt"
        static let mediaActivityEnabled = "nook.media.closedActivityEnabled"
    }

    static func load(
        for profile: IslandAppearanceDisplayProfile,
        defaults: UserDefaults = .standard
    ) -> NookDisplayPreferences {
        var preferences = NookDisplayPreferences()

        func bool(_ name: String, legacy: String? = nil) -> Bool? {
            (defaults.object(forKey: key(profile, name)) as? Bool)
                ?? legacy.flatMap { defaults.object(forKey: $0) as? Bool }
        }

        if let raw = defaults.string(forKey: key(profile, "mediaStyle")),
           let style = NookClosedMediaStyle(rawValue: raw) {
            preferences.mediaStyle = style
        } else if defaults.object(forKey: LegacyKey.mediaActivityEnabled) as? Bool == false {
            preferences.mediaStyle = .off
        }
        if let raw = defaults.string(forKey: key(profile, "openedPage")) ?? defaults.string(forKey: LegacyKey.openedPage),
           let page = NookOpenedPage(rawValue: raw) {
            preferences.openedPage = page
        }
        preferences.agentsReclaimRightSide = bool("agentsReclaimRightSide") ?? preferences.agentsReclaimRightSide
        preferences.showsAgentDotOnArt = bool("dotOnArt", legacy: LegacyKey.dotOnArt) ?? preferences.showsAgentDotOnArt
        preferences.showsNotices = bool("notices") ?? preferences.showsNotices
        preferences.centerLabelShowsTrack = bool("centerLabelShowsTrack") ?? preferences.centerLabelShowsTrack
        preferences.centerLabelShowsNextEvent = bool("centerLabelShowsNextEvent") ?? preferences.centerLabelShowsNextEvent
        if let raw = defaults.stringArray(forKey: key(profile, "hiddenWidgets")) {
            preferences.hiddenWidgets = Set(raw.compactMap(NookWidgetKind.init(rawValue:)))
        }
        if let raw = defaults.string(forKey: key(profile, "leftSlot")), let slot = NookSideSlot(rawValue: raw) {
            preferences.leftSlot = slot
        }
        preferences.rightSlot = defaults.string(forKey: key(profile, "rightSlot")).flatMap(NookSideSlot.init(rawValue:))
        if let raw = defaults.string(forKey: key(profile, "calendarStyle")), let style = NookCalendarStyle(rawValue: raw) {
            preferences.calendarStyle = style
        }
        if let raw = defaults.stringArray(forKey: key(profile, "hiddenCalendarIDs")) {
            preferences.hiddenCalendarIDs = Set(raw)
        }
        preferences.showsCompactBar = bool("compactBar", legacy: LegacyKey.compactBar) ?? preferences.showsCompactBar
        preferences.showsAgentsBar = bool("agentsBar") ?? preferences.showsAgentsBar
        if let raw = defaults.string(forKey: key(profile, "haloStyle")), let style = IslandHaloStyle(rawValue: raw) {
            preferences.haloStyle = style
        }
        preferences.haloFollowsMusic = bool("haloFollowsMusic") ?? preferences.haloFollowsMusic
        preferences.haloColors.palette = IslandHaloPalette(storageValue: defaults.dictionary(forKey: key(profile, "haloPalette")))
        preferences.haloColors.usesSingleColor = bool("haloSingleColorOn") ?? preferences.haloColors.usesSingleColor
        if let raw = defaults.string(forKey: key(profile, "haloSingleColor")), let color = IslandHaloRGB(hex: raw) {
            preferences.haloColors.singleColor = color
        }
        if let raw = defaults.string(forKey: key(profile, "openedWidth")), let width = IslandOpenedWidth(rawValue: raw) {
            preferences.openedLook.width = width
        }
        if let raw = defaults.string(forKey: key(profile, "openedCorners")),
           let corners = IslandOpenedCorners(rawValue: raw) {
            preferences.openedLook.corners = corners
        }
        if let raw = defaults.stringArray(forKey: key(profile, "widgetOrder")) {
            preferences.widgetOrder = raw.compactMap(NookWidgetKind.init(rawValue:))
        }
        if let raw = defaults.dictionary(forKey: key(profile, "widgetSizes")) as? [String: String] {
            preferences.widgetSizes = Dictionary(uniqueKeysWithValues: raw.compactMap { name, size in
                guard let kind = NookWidgetKind(rawValue: name), let size = NookWidgetSize(rawValue: size) else { return nil }
                return (kind, size)
            })
        }
        return preferences
    }

    /// Writes every field.
    func persist(
        for profile: IslandAppearanceDisplayProfile,
        defaults: UserDefaults = .standard
    ) {
        write(for: profile, defaults: defaults, changedFrom: nil)
    }

    /// Writes only the fields that differ from `old`, with the same keys and
    /// encodings as `persist(for:defaults:)`. One Personalization tap changes
    /// one field, so this keeps a save to one key instead of about 18.
    func persistChanges(
        from old: NookDisplayPreferences,
        for profile: IslandAppearanceDisplayProfile,
        defaults: UserDefaults = .standard
    ) {
        write(for: profile, defaults: defaults, changedFrom: old)
    }

    /// `old` nil writes everything.
    private func write(
        for profile: IslandAppearanceDisplayProfile,
        defaults: UserDefaults,
        changedFrom old: NookDisplayPreferences?
    ) {
        func changed<Value: Equatable>(_ field: KeyPath<NookDisplayPreferences, Value>) -> Bool {
            guard let old else { return true }
            return old[keyPath: field] != self[keyPath: field]
        }

        if changed(\.mediaStyle) {
            defaults.set(mediaStyle.rawValue, forKey: Self.key(profile, "mediaStyle"))
        }
        if changed(\.agentsReclaimRightSide) {
            defaults.set(agentsReclaimRightSide, forKey: Self.key(profile, "agentsReclaimRightSide"))
        }
        if changed(\.showsAgentDotOnArt) {
            defaults.set(showsAgentDotOnArt, forKey: Self.key(profile, "dotOnArt"))
        }
        if changed(\.showsNotices) {
            defaults.set(showsNotices, forKey: Self.key(profile, "notices"))
        }
        if changed(\.centerLabelShowsTrack) {
            defaults.set(centerLabelShowsTrack, forKey: Self.key(profile, "centerLabelShowsTrack"))
        }
        if changed(\.centerLabelShowsNextEvent) {
            defaults.set(centerLabelShowsNextEvent, forKey: Self.key(profile, "centerLabelShowsNextEvent"))
        }
        if changed(\.hiddenWidgets) {
            defaults.set(hiddenWidgets.map(\.rawValue).sorted(), forKey: Self.key(profile, "hiddenWidgets"))
        }
        if changed(\.leftSlot) {
            defaults.set(leftSlot.rawValue, forKey: Self.key(profile, "leftSlot"))
        }
        if changed(\.rightSlot) {
            if let rightSlot {
                defaults.set(rightSlot.rawValue, forKey: Self.key(profile, "rightSlot"))
            } else {
                defaults.removeObject(forKey: Self.key(profile, "rightSlot"))
            }
        }
        if changed(\.calendarStyle) {
            defaults.set(calendarStyle.rawValue, forKey: Self.key(profile, "calendarStyle"))
        }
        if changed(\.hiddenCalendarIDs) {
            defaults.set(hiddenCalendarIDs.sorted(), forKey: Self.key(profile, "hiddenCalendarIDs"))
        }
        if changed(\.openedPage) {
            defaults.set(openedPage.rawValue, forKey: Self.key(profile, "openedPage"))
        }
        if changed(\.showsCompactBar) {
            defaults.set(showsCompactBar, forKey: Self.key(profile, "compactBar"))
        }
        if changed(\.showsAgentsBar) {
            defaults.set(showsAgentsBar, forKey: Self.key(profile, "agentsBar"))
        }
        if changed(\.haloStyle) {
            defaults.set(haloStyle.rawValue, forKey: Self.key(profile, "haloStyle"))
        }
        if changed(\.haloFollowsMusic) {
            defaults.set(haloFollowsMusic, forKey: Self.key(profile, "haloFollowsMusic"))
        }
        if changed(\.haloColors.palette) {
            defaults.set(haloColors.palette.storageValue, forKey: Self.key(profile, "haloPalette"))
        }
        if changed(\.haloColors.usesSingleColor) {
            defaults.set(haloColors.usesSingleColor, forKey: Self.key(profile, "haloSingleColorOn"))
        }
        if changed(\.haloColors.singleColor) {
            defaults.set(haloColors.singleColor.hex, forKey: Self.key(profile, "haloSingleColor"))
        }
        if changed(\.openedLook.width) {
            defaults.set(openedLook.width.rawValue, forKey: Self.key(profile, "openedWidth"))
        }
        if changed(\.openedLook.corners) {
            defaults.set(openedLook.corners.rawValue, forKey: Self.key(profile, "openedCorners"))
        }
        if changed(\.widgetOrder) {
            defaults.set(widgetOrder.map(\.rawValue), forKey: Self.key(profile, "widgetOrder"))
        }
        if changed(\.widgetSizes) {
            defaults.set(
                Dictionary(uniqueKeysWithValues: widgetSizes.map { ($0.key.rawValue, $0.value.rawValue) }),
                forKey: Self.key(profile, "widgetSizes")
            )
        }
    }
}

extension NookDisplayPreferences {
    /// False when only the glow colors differ: they change nothing on the
    /// Nook page, and a color drag writes many of them a second.
    func changesThePage(from old: NookDisplayPreferences) -> Bool {
        var oldWithNewGlow = old
        oldWithNewGlow.haloColors = haloColors
        return oldWithNewGlow != self
    }
}

extension NookClosedActivity {
    /// Picks what the closed island shows from what is live right now and
    /// what this display allows. Priority: a notice, a running timer, music.
    /// `timerLeading` is the symbol beside the countdown: the timer by
    /// default, a round number or a cup during a pomodoro.
    static func resolve(
        transient: NookTransientActivity?,
        timerText: String?,
        timerLeading: NookClosedActivity.Leading = .symbol("timer", .orange),
        media: NookClosedMediaActivity?,
        preferences: NookDisplayPreferences
    ) -> NookClosedActivity? {
        if preferences.showsNotices {
            if let transient {
                return NookClosedActivity(
                    leading: .symbol(transient.symbol, transient.tint),
                    trailing: transient.level.map { .level(percent: $0, tint: transient.tint) }
                        ?? .text(transient.text),
                    yieldsToAgents: false
                )
            }
            if let timerText {
                return NookClosedActivity(
                    leading: timerLeading,
                    trailing: .text(timerText),
                    yieldsToAgents: false
                )
            }
        }
        guard let media else { return nil }
        switch preferences.mediaStyle {
        case .off:
            return nil
        case .artOnly:
            return NookClosedActivity(leading: .artwork(media.artwork), trailing: nil, yieldsToAgents: true)
        case .artAndVisual:
            return NookClosedActivity(
                leading: .artwork(media.artwork),
                trailing: .media(media),
                yieldsToAgents: preferences.agentsReclaimRightSide
            )
        }
    }
}
