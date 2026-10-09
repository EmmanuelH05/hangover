import Foundation

/// A ready-made Personalization setup for one display: the closed island,
/// the opened island, the session list and the Nook page in one click. The
/// Personalization tab lists `all` above its own controls, which makes a
/// template a starting point that every control below can still change.
///
/// A template is a full definition, not a patch. Applying one sets every
/// choice on the tab except the calendars picked for the display, and a
/// display is "on" a template while it draws exactly what the template
/// describes. A template touches one display and nothing else: it never
/// changes the other display and never switches a widget on or off in the
/// Nook tab.
struct PersonalizationTemplate: Identifiable, Equatable, Sendable {
    enum ID: String, CaseIterable, Sendable {
        case cockpit
        case nowPlaying
        case planner
        case focus
        case minimal
    }

    /// One side of the closed island in a template's thumbnail.
    enum Glyph: Equatable, Sendable {
        case bars
        case count
        case agents
        case date
        case battery
        case countdown
        case artwork
        case visualizer
        case none
    }

    let id: ID
    let symbol: String
    let appearance: IslandAppearancePreferences
    /// The Nook choices. Six fields are not read from here: the page comes
    /// from `widgets` (`widgetOrder`, `widgetSizes`, `hiddenWidgets`), and the
    /// calendars, the glow colors and the opened look stay the user's
    /// (`hiddenCalendarIDs`, `haloColors`, `openedLook`).
    let nook: NookDisplayPreferences
    /// The Nook page from top to bottom. Never the mirror: a camera control
    /// is the user's to add. A widget that is switched off in the Nook tab
    /// stays off; the template keeps its place for when it comes back on.
    let widgets: [NookWidgetPlacement]
    /// The thumbnail shows the closed island while music plays.
    let previewsMusic: Bool
    /// The thumbnail's glow. Nil when the template turns the glow off.
    let previewGlow: IslandHaloRGB?
}

// MARK: - Applying

extension PersonalizationTemplate {
    var widgetKinds: [NookWidgetKind] { widgets.map(\.kind) }

    /// `current` with this template applied. The template's widgets lead the
    /// page and every other widget is hidden on this display. Widgets left
    /// off the page keep their place in the order and their size, which
    /// puts one back where the user had it when it is added again.
    func applying(to current: NookDisplayPreferences) -> NookDisplayPreferences {
        let kinds = widgetKinds
        var result = nook
        result.hiddenCalendarIDs = current.hiddenCalendarIDs
        result.haloColors = current.haloColors
        result.openedLook = current.openedLook
        result.widgetOrder = kinds + current.normalizedWidgetOrder.filter { !kinds.contains($0) }
        result.widgetSizes = current.widgetSizes.filter { !kinds.contains($0.key) }
        for placement in widgets where placement.size != .medium {
            result.widgetSizes[placement.kind] = placement.size
        }
        result.hiddenWidgets = Set(NookWidgetKind.allCases).subtracting(kinds)
        return result
    }

    /// True while a display draws exactly this template: every choice equals
    /// the template's and the page holds the template's widgets, in order,
    /// at its sizes. The calendars are the user's and are not compared, and
    /// neither are the order and sizes of widgets that are off the page.
    func matches(appearance current: IslandAppearancePreferences, nook display: NookDisplayPreferences) -> Bool {
        guard current == appearance else { return false }
        guard display.placements(enabled: NookWidgetKind.allCases) == widgets else { return false }
        var choices = display
        choices.widgetOrder = nook.widgetOrder
        choices.widgetSizes = nook.widgetSizes
        choices.hiddenWidgets = nook.hiddenWidgets
        choices.hiddenCalendarIDs = nook.hiddenCalendarIDs
        choices.haloColors = nook.haloColors
        choices.openedLook = nook.openedLook
        return choices == nook
    }

    /// The template's widgets that are switched off in the Nook tab. They
    /// are missing from the page until they are switched on there.
    func widgetsSwitchedOff(enabled: [NookWidgetKind]) -> [NookWidgetKind] {
        widgetKinds.filter { !enabled.contains($0) }
    }
}

// MARK: - Thumbnail

extension PersonalizationTemplate {
    /// Left side of the thumbnail's closed island.
    var previewLeft: Glyph {
        previewsMusic ? .artwork : Self.glyph(for: nook.leftSlot)
    }

    /// Right side of the thumbnail's closed island. A Nook slot on the right
    /// wins over the island's own, as it does on the real island.
    var previewRight: Glyph {
        if previewsMusic { return .visualizer }
        if let slot = nook.rightSlot { return Self.glyph(for: slot) }
        switch appearance.rightSlot {
        case .count: return .count
        case .agents: return .agents
        case .none: return .none
        }
    }

    private static func glyph(for slot: NookSideSlot) -> Glyph {
        switch slot {
        case .agents: .bars
        case .count: .count
        case .grid: .agents
        case .date: .date
        case .battery: .battery
        case .countdown: .countdown
        case .none: .none
        }
    }
}

// MARK: - The five templates

extension PersonalizationTemplate {
    /// In the order the Personalization tab lists them.
    static let all: [PersonalizationTemplate] = [cockpit, nowPlaying, planner, focus, minimal]

    /// Several agents at once. The agents own both sides of the closed
    /// island, the glow is loud, and the island opens on the agent list.
    static let cockpit = PersonalizationTemplate(
        id: .cockpit,
        symbol: "terminal.fill",
        appearance: IslandAppearancePreferences(
            rightSlot: .agents,
            centerLabel: .agentAction,
            usageDisplay: .compact,
            sessionStateIndicator: .animatedDot,
            sessionGroup: .state,
            sessionSort: .attention,
            completedStaleThreshold: .fiveMinutes
        ),
        nook: NookDisplayPreferences(
            mediaStyle: .artOnly,
            agentsReclaimRightSide: true,
            showsAgentDotOnArt: true,
            showsNotices: true,
            centerLabelShowsTrack: false,
            centerLabelShowsNextEvent: false,
            leftSlot: .agents,
            rightSlot: nil,
            calendarStyle: .agenda,
            openedPage: .agents,
            showsCompactBar: true,
            showsAgentsBar: true,
            haloStyle: .vivid,
            haloFollowsMusic: false
        ),
        widgets: [
            NookWidgetPlacement(kind: .timer, size: .small),
            NookWidgetPlacement(kind: .tray, size: .small),
            NookWidgetPlacement(kind: .todo, size: .medium),
        ],
        previewsMusic: false,
        previewGlow: .approval
    )

    /// Music all day. Album art and the visualizer hold the closed island
    /// even while an agent waits; the glow carries that signal instead.
    static let nowPlaying = PersonalizationTemplate(
        id: .nowPlaying,
        symbol: "music.note",
        appearance: IslandAppearancePreferences(
            rightSlot: .count,
            centerLabel: .agentAction,
            usageDisplay: .compact,
            sessionStateIndicator: .animatedDot,
            sessionGroup: .none,
            sessionSort: .attention,
            completedStaleThreshold: .fiveMinutes
        ),
        nook: NookDisplayPreferences(
            mediaStyle: .artAndVisual,
            agentsReclaimRightSide: false,
            showsAgentDotOnArt: true,
            showsNotices: true,
            centerLabelShowsTrack: true,
            centerLabelShowsNextEvent: false,
            leftSlot: .agents,
            rightSlot: nil,
            calendarStyle: .strip,
            openedPage: .nook,
            showsCompactBar: true,
            showsAgentsBar: true,
            haloStyle: .vivid,
            haloFollowsMusic: true
        ),
        widgets: [
            NookWidgetPlacement(kind: .media, size: .large),
            NookWidgetPlacement(kind: .timer, size: .small),
            NookWidgetPlacement(kind: .notes, size: .small),
        ],
        previewsMusic: true,
        previewGlow: .rgb255(255, 55, 95)
    )

    /// A day run by the calendar. The date and the time until the next
    /// event sit in the closed island, over a month view and the task list.
    static let planner = PersonalizationTemplate(
        id: .planner,
        symbol: "calendar",
        appearance: IslandAppearancePreferences(
            rightSlot: .count,
            centerLabel: .agentAction,
            usageDisplay: .compact,
            sessionStateIndicator: .animatedDot,
            sessionGroup: .none,
            sessionSort: .attention,
            completedStaleThreshold: .fiveMinutes
        ),
        nook: NookDisplayPreferences(
            mediaStyle: .artOnly,
            agentsReclaimRightSide: true,
            showsAgentDotOnArt: true,
            showsNotices: true,
            centerLabelShowsTrack: false,
            centerLabelShowsNextEvent: true,
            leftSlot: .date,
            rightSlot: .countdown,
            calendarStyle: .month,
            openedPage: .nook,
            showsCompactBar: true,
            showsAgentsBar: true,
            haloStyle: .subtle,
            haloFollowsMusic: false
        ),
        widgets: [
            NookWidgetPlacement(kind: .calendar, size: .medium),
            NookWidgetPlacement(kind: .todo, size: .medium),
        ],
        previewsMusic: false,
        previewGlow: .running
    )

    /// Timed work blocks. A large timer over the next event and the task
    /// list, with battery and time left in the closed island.
    static let focus = PersonalizationTemplate(
        id: .focus,
        symbol: "timer",
        appearance: IslandAppearancePreferences(
            rightSlot: .count,
            centerLabel: .off,
            usageDisplay: .hidden,
            sessionStateIndicator: .animatedDot,
            sessionGroup: .none,
            sessionSort: .attention,
            completedStaleThreshold: .twoMinutes
        ),
        nook: NookDisplayPreferences(
            mediaStyle: .artOnly,
            agentsReclaimRightSide: true,
            showsAgentDotOnArt: true,
            showsNotices: true,
            centerLabelShowsTrack: false,
            centerLabelShowsNextEvent: true,
            leftSlot: .battery,
            rightSlot: .countdown,
            calendarStyle: .hero,
            openedPage: .nook,
            showsCompactBar: false,
            showsAgentsBar: true,
            haloStyle: .subtle,
            haloFollowsMusic: false
        ),
        widgets: [
            NookWidgetPlacement(kind: .timer, size: .large),
            NookWidgetPlacement(kind: .calendar, size: .medium),
            NookWidgetPlacement(kind: .todo, size: .small),
            NookWidgetPlacement(kind: .notes, size: .small),
        ],
        previewsMusic: false,
        previewGlow: .running
    )

    /// Out of the way. Only the activity bars: no glow, no music, no
    /// notices, and one row of widgets.
    static let minimal = PersonalizationTemplate(
        id: .minimal,
        symbol: "moon.fill",
        appearance: IslandAppearancePreferences(
            rightSlot: .none,
            centerLabel: .off,
            usageDisplay: .hidden,
            sessionStateIndicator: .glyph,
            sessionGroup: .none,
            sessionSort: .attention,
            completedStaleThreshold: .twoMinutes
        ),
        nook: NookDisplayPreferences(
            mediaStyle: .off,
            agentsReclaimRightSide: true,
            showsAgentDotOnArt: false,
            showsNotices: false,
            centerLabelShowsTrack: false,
            centerLabelShowsNextEvent: false,
            leftSlot: .agents,
            rightSlot: nil,
            calendarStyle: .agenda,
            openedPage: .auto,
            showsCompactBar: false,
            showsAgentsBar: false,
            haloStyle: .off,
            haloFollowsMusic: false
        ),
        widgets: [
            NookWidgetPlacement(kind: .todo, size: .small),
            NookWidgetPlacement(kind: .timer, size: .small),
        ],
        previewsMusic: false,
        previewGlow: nil
    )
}

// MARK: - Setup

/// What a template reads and writes, as a value: one display's island
/// choices and its Nook choices. Applying and undoing are pure functions of
/// it; `AppModel` only copies it in and out. It is also what undo holds:
/// the display's setup from before a template replaced it.
struct PersonalizationSetup: Equatable, Sendable {
    var appearance: IslandAppearancePreferences
    var nook: NookDisplayPreferences
}

extension PersonalizationSetup {
    /// The template this setup equals. Nil once anything on the
    /// Personalization tab differs from every template.
    var appliedTemplateID: PersonalizationTemplate.ID? {
        PersonalizationTemplate.all.first { $0.matches(appearance: appearance, nook: nook) }?.id
    }

    /// This setup with `template` applied, and the setup undo should hold.
    ///
    /// Going from one template straight to another keeps the `earlier`
    /// setup, which lets a few tries in a row still lead back to the user's
    /// own. Clicking the template the display is already on changes nothing
    /// and leaves undo as it was.
    func applying(
        _ template: PersonalizationTemplate,
        keeping earlier: PersonalizationSetup?
    ) -> (setup: PersonalizationSetup, undo: PersonalizationSetup?) {
        let current = appliedTemplateID
        guard current != template.id else { return (self, earlier) }
        let undo = (current == nil ? nil : earlier) ?? self
        let applied = PersonalizationSetup(appearance: template.appearance, nook: template.applying(to: nook))
        return (applied, undo)
    }

    /// The setup `undo` holds, put back. A template never touches the
    /// calendars, which makes a calendar picked while on one the user's own
    /// change, and it stays.
    func undoing(_ undo: PersonalizationSetup) -> PersonalizationSetup {
        var result = undo
        result.nook.hiddenCalendarIDs = nook.hiddenCalendarIDs
        result.nook.haloColors = nook.haloColors
        result.nook.openedLook = nook.openedLook
        return result
    }
}
