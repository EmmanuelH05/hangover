import SwiftUI

// The last part of the tour: what macOS may ask for, a few tricks and the
// recap of what was chosen.

// MARK: - 10. Permissions

/// Says in plain words what asks macOS for access and when. Nothing on
/// this page asks for anything: it has no button at all.
struct OnboardingPermissionsPage: View {
    /// A row's vertical padding. Five rows are the most the page held before
    /// Record joined the list. With the agents on, the pulse on and Record
    /// listed it holds six, which need less of it to stay above the buttons.
    static func rowPadding(rowCount: Int) -> CGFloat { rowCount > 5 ? 7 : 13 }

    let context: OnboardingPageContext

    var body: some View {
        let grants = OnboardingGrant.shown(agentsEnabled: context.state.agentsEnabled, beatIsOn: context.state.beat.isOn)
        OnboardingPageScaffold(
            page: .permissions,
            context: context,
            title: context.t("onboarding.permissions.title"),
            text: context.t("onboarding.permissions.body"),
            footnote: context.t("onboarding.permissions.note"),
            gap: 20
        ) {
            VStack(spacing: 0) {
                ForEach(Array(grants.enumerated()), id: \.element) { index, grant in
                    if index > 0 { OnboardingDivider() }
                    row(grant, padding: Self.rowPadding(rowCount: grants.count))
                }
            }
            .background(OnboardingCardBackground())
            .frame(width: 680)
        }
    }

    private func row(_ grant: OnboardingGrant, padding: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 13) {
            OnboardingSymbolPlate(symbol: grant.symbol, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(context.t("onboarding.permissions.\(grant.rawValue).title"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(OnboardingStyle.primaryText)
                    Text(context.t("onboarding.permissions.\(grant.rawValue).when"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(OnboardingStyle.waiting)
                }
                Text(context.t(grant.noteKey(agentsEnabled: context.state.agentsEnabled)))
                    .font(.system(size: 12))
                    .foregroundStyle(OnboardingStyle.secondaryText)
                    .lineSpacing(1.5)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, padding)
        .accessibilityElement(children: .combine)
    }
}

/// What the permissions page lists, in order. The raw value is the name in
/// the page's string keys.
enum OnboardingGrant: String, CaseIterable, Sendable {
    case camera
    case accessibility
    case calendar
    /// Asked for by Record (D67): Screen Recording the first time the screen
    /// or an area is recorded, and the microphone the first time Voice is
    /// recorded. The face cam's camera is the camera row's. Nothing is asked
    /// before the user presses Record.
    case record
    /// Asked for when "Pulse with the beat" is switched on (D56): the app
    /// listens to the Mac's sound to find the beat. Listed only while the
    /// switch is on.
    case audio
    /// Asked for by the session monitor, a terminal jump and a reply, all
    /// of which belong to the agent half.
    case automation

    var symbol: String {
        switch self {
        case .camera: "camera.fill"
        case .accessibility: "accessibility"
        case .calendar: "calendar"
        case .record: "record.circle"
        case .audio: "waveform"
        case .automation: "terminal.fill"
        }
    }

    var isAgentsOnly: Bool { self == .automation }

    /// The sentence under the name. Accessibility has a second one that
    /// also names a terminal jump, for when the agents are on.
    func noteKey(agentsEnabled: Bool) -> String {
        let base = "onboarding.permissions.\(rawValue).note"
        return self == .accessibility && agentsEnabled ? base + ".agents" : base
    }

    static func shown(agentsEnabled: Bool, beatIsOn: Bool = false) -> [OnboardingGrant] {
        allCases.filter { (agentsEnabled || !$0.isAgentsOnly) && (beatIsOn || $0 != .audio) }
    }
}

// MARK: - 11. Tips

/// A card a trick: a picture, a name and one sentence.
struct OnboardingTipsPage: View {
    let context: OnboardingPageContext

    /// Five across, in two rows: ten tips, which is every tip there is with
    /// the swipe off. Four across held eight, and the widgets' own tips were
    /// the ones that fell off the page.
    private static let columnCount = 5
    private static let spacing: CGFloat = 10
    /// The width that puts `columnCount` cards across the page's content.
    static var cardWidth: CGFloat {
        (OnboardingStyle.contentWidth - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount)
    }

    var body: some View {
        let state = context.state
        let tips = OnboardingTip.shown(
            agentsEnabled: state.agentsEnabled,
            widgets: Set(state.shownPlacements.map(\.kind)),
            swipeEnabled: state.swipeEnabled
        )
        OnboardingPageScaffold(
            page: .tips,
            context: context,
            title: context.t("onboarding.tips.title"),
            text: context.t("onboarding.tips.body"),
            footnote: context.t("onboarding.tips.note"),
            gap: 18
        ) {
            VStack(spacing: Self.spacing) {
                ForEach(Array(Self.rows(tips).enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: Self.spacing) {
                        ForEach(row) { tip in card(tip) }
                    }
                }
            }
        }
    }

    /// The tips in rows of five. A short last row sits in the middle.
    static func rows(_ tips: [OnboardingTip]) -> [[OnboardingTip]] {
        stride(from: 0, to: tips.count, by: columnCount).map {
            Array(tips[$0..<min($0 + columnCount, tips.count)])
        }
    }

    private func card(_ tip: OnboardingTip) -> some View {
        let name = tip.keyName(openTrigger: context.state.openTrigger)
        return VStack(alignment: .leading, spacing: 0) {
            OnboardingSymbolPlate(symbol: tip.symbol, size: 34)
            Text(context.t("onboarding.tips.\(name).title"))
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(OnboardingStyle.primaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            Text(tip.text(openTrigger: context.state.openTrigger, lang: context.lang))
                .font(.system(size: 11.5))
                .foregroundStyle(OnboardingStyle.secondaryText)
                .lineSpacing(1.5)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(width: Self.cardWidth, height: 190, alignment: .topLeading)
        .background(OnboardingCardBackground())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 12. Done

/// Says back what was chosen, and where to change it.
struct OnboardingDonePage: View {
    let context: OnboardingPageContext

    private var state: OnboardingState { context.state }

    var body: some View {
        let rows = OnboardingRecapRow.shown(
            length: state.length ?? .medium,
            agentsEnabled: state.agentsEnabled,
            hasTodoWidget: state.showsWidget(.todo),
            hasNotesWidget: state.showsWidget(.notes),
            hasWeatherWidget: state.showsWidget(.weather),
            hasCalendarWidget: state.showsWidget(.calendar),
            hasDesignKit: state.features.design.isOn,
            hasLights: state.beat.showsInSummary,
            hasMoreSwitches: !state.moreSwitchedOn.isEmpty
        )
        let rowHeight = Self.rowHeight(rowCount: rows.count)
        VStack(spacing: 0) {
            OnboardingPillArt(
                width: 230,
                height: 34,
                glow: OnboardingStyle.finished,
                glowStrength: 0.85,
                left: OnboardingClosedPage.leftPillSide(state.closedLeft),
                right: OnboardingClosedPage.pillSide(state.closedSide)
            )
            .frame(height: 72)

            OnboardingHeading(
                eyebrow: OnboardingPageScaffold<EmptyView>.eyebrow(.done, context),
                title: context.t("onboarding.done.title"),
                text: context.t(state.openTrigger == .hover ? "onboarding.done.body.hover" : "onboarding.done.body.click"),
                titleSize: 28
            )
            .padding(.bottom, 12)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                    if index > 0 { OnboardingDivider() }
                    recapRow("onboarding.done.recap.\(row.rawValue)", height: rowHeight) { recapContent(row) }
                }
            }
            .background(OnboardingCardBackground())
            .frame(width: 540)

            OnboardingNote(text: context.t("onboarding.done.where"))
                .multilineTextAlignment(.center)
                .frame(maxWidth: OnboardingStyle.textWidth)
                .padding(.top, 12)

            // The short tour says it can be run again, for a longer one. The
            // main tour's recap has no room for a second line.
            if state.length == .short {
                OnboardingNote(text: context.t("onboarding.done.again"))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: OnboardingStyle.textWidth)
                    .padding(.top, 6)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func recapContent(_ row: OnboardingRecapRow) -> some View {
        switch row {
        case .opens: recapValue(context.t(state.openTrigger.titleKey))
        case .closed: recapValue(closedText)
        case .agents: recapValue(connectedAgentsText)
        case .approve: recapKeys(state.approveKeys)
        case .deny: recapKeys(state.denyKeys)
        case .widgets: recapValue(widgetsText)
        case .calendar: recapValue(context.t(OnboardingCalendarLooks.nameKey(state.calendarStyle)))
        case .todos: recapValue(context.t(OnboardingTodoGuide.nameKey(for: state.todoSource)))
        case .notes: recapValue(context.t(OnboardingNotesGuide.titleKey(for: state.notesSaveTo)))
        case .weather: recapValue(weatherText)
        case .layout: recapValue(layoutText)
        case .opened: recapValue(openedLookText)
        case .glow: recapValue(glowText)
        case .design: recapValue(context.t("onboarding.done.recap.design.on"))
        case .lights: recapValue(lightsText)
        case .goodToKnow: recapValue(goodToKnowText)
        }
    }

    /// A row is 27 points while thirteen or fewer fit above the buttons. With
    /// the design kit, the lights and the Good to know row chosen there are
    /// sixteen at most, and each takes a little less, which keeps the whole
    /// list the height thirteen were.
    static func rowHeight(rowCount: Int) -> CGFloat {
        if rowCount > 15 { return 21.9 }
        return rowCount > 13 ? 23.4 : 27
    }

    /// The Good to know switches turned on in this tour, by short name.
    private var goodToKnowText: String {
        state.moreSwitchedOn.map { context.t("onboarding.done.recap.more.\($0.rawValue)") }.joined(separator: ", ")
    }

    /// The pulse and the look it is in.
    private var lightsText: String {
        context.lang.t("onboarding.done.recap.lights.value", context.t(state.beat.look.titleKey))
    }

    /// The saved place, or that none is saved yet.
    private var weatherText: String {
        state.weather.place?.label ?? context.t("onboarding.done.recap.weather.none")
    }

    /// Both sides, left first.
    private var closedText: String {
        let right = state.closedSide.map { context.t($0.titleKey) }
            ?? context.t("onboarding.done.recap.closed.own")
        return context.lang.t("onboarding.done.recap.closed.value", context.t(state.closedLeft.titleKey), right)
    }

    private var connectedAgentsText: String {
        let names = state.connectedAgents.map(\.name).joined(separator: ", ")
        switch (names.isEmpty, state.hasAgentOutsideTour) {
        case (true, false): return context.t("onboarding.done.recap.agents.none")
        case (true, true): return context.t("onboarding.done.recap.agents.otherOnly")
        case (false, false): return names
        case (false, true): return context.lang.t("onboarding.done.recap.agents.more", names)
        }
    }

    /// The widgets on the page, by name, in the page's order.
    private var widgetsText: String {
        let names = state.shownPlacements.map { context.t("onboarding.nook.widget.\($0.kind.rawValue)") }
        return names.isEmpty ? context.t("onboarding.done.recap.widgets.none") : names.joined(separator: ", ")
    }

    /// The layout picked in the tour by its name, or the one the display
    /// was on, or "your own".
    private var layoutText: String {
        guard let id = state.shownTemplate else { return context.t("onboarding.done.recap.layout.own") }
        return TemplateText(id, lang: context.lang).title
    }

    /// The glow's strength and, while it is on, the theme its colors are.
    private var glowText: String {
        let style = context.t("settings.appearance.nook.halo.\(state.glowStyle.rawValue)")
        guard state.glowStyle != .off,
              let theme = state.glowThemeID.flatMap(IslandHaloTheme.theme(id:)),
              theme.id != IslandHaloTheme.standard.id
        else { return style }
        return "\(style) · \(context.t(theme.titleKey))"
    }

    private var openedLookText: String {
        context.lang.t(
            "onboarding.done.recap.opened.value",
            context.t("settings.appearance.openedLook.width.\(state.openedLook.width.rawValue)"),
            context.t("settings.appearance.openedLook.corners.\(state.openedLook.corners.rawValue)")
        )
    }

    private func recapRow<Value: View>(_ key: String, height: CGFloat, @ViewBuilder value: () -> Value) -> some View {
        HStack(spacing: 12) {
            Text(context.t(key))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(OnboardingStyle.primaryText)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 12)
            value()
        }
        .padding(.horizontal, 14)
        // Thirteen rows have to fit the window above its buttons, and two more
        // take a little less each (`rowHeight`).
        .frame(height: height)
        .accessibilityElement(children: .combine)
    }

    private func recapValue(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(OnboardingStyle.secondaryText)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    private func recapKeys(_ caps: [String]?) -> some View {
        if let caps {
            OnboardingKeyCaps(caps: caps)
        } else {
            recapValue(context.t("onboarding.done.recap.keys.off"))
        }
    }
}

/// The rows of the last page's recap, in the order the tour asked. The raw
/// value is the name in the row's string key.
enum OnboardingRecapRow: String, CaseIterable, Sendable {
    case opens
    case closed
    case agents
    case approve
    case deny
    case widgets
    /// The calendar look, while the calendar is on the page (D50).
    case calendar
    /// Where the to-do widget gets its tasks.
    case todos
    /// Where notes are saved.
    case notes
    /// Where the user is, for the weather card.
    case weather
    case layout
    case opened
    case glow
    /// The design kit, while it is switched on.
    case design
    /// The lights that follow the beat, while the pulse is switched on.
    case lights
    /// The Good to know switches the user turned on, in one row.
    case goodToKnow

    var isAgentsOnly: Bool {
        self == .agents || self == .approve || self == .deny
    }

    /// True for a row of something the short tour asked about: how the
    /// island opens, what the closed island shows, the agents that are
    /// connected and the widgets. The rows of the pages it skips are left
    /// off its recap.
    var isInShortTour: Bool {
        switch self {
        case .opens, .closed, .agents, .widgets: true
        case .approve, .deny, .calendar, .todos, .notes, .weather, .layout, .opened, .glow, .design, .lights, .goodToKnow: false
        }
    }

    /// The rows the recap shows: nothing of agents while they are off, and
    /// no task source while the to-do widget is off the page, and no notes
    /// place while the notes widget is. The short tour recaps only what it
    /// asked.
    static func shown(
        length: OnboardingLength = .medium,
        agentsEnabled: Bool,
        hasTodoWidget: Bool = true,
        hasNotesWidget: Bool = true,
        hasWeatherWidget: Bool = true,
        hasCalendarWidget: Bool = true,
        hasDesignKit: Bool = false,
        hasLights: Bool = false,
        hasMoreSwitches: Bool = false
    ) -> [OnboardingRecapRow] {
        allCases.filter { row in
            (length > .short || row.isInShortTour)
                && (agentsEnabled || !row.isAgentsOnly)
                && (hasTodoWidget || row != .todos)
                && (hasNotesWidget || row != .notes)
                && (hasWeatherWidget || row != .weather)
                && (hasCalendarWidget || row != .calendar)
                && (hasDesignKit || row != .design)
                && (hasLights || row != .lights)
                && (hasMoreSwitches || row != .goodToKnow)
        }
    }
}
