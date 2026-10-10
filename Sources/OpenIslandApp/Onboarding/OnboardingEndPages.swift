import SwiftUI

// The last part of the tour: what macOS may ask for, a few tricks and the
// recap of what was chosen.

// MARK: - 10. Permissions

/// Says in plain words what asks macOS for access and when. Nothing on
/// this page asks for anything: it has no button at all.
struct OnboardingPermissionsPage: View {
    let context: OnboardingPageContext

    var body: some View {
        let grants = OnboardingGrant.shown(agentsEnabled: context.state.agentsEnabled)
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
                    row(grant)
                }
            }
            .background(OnboardingCardBackground())
            .frame(width: 680)
        }
    }

    private func row(_ grant: OnboardingGrant) -> some View {
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
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }
}

/// What the permissions page lists, in order. The raw value is the name in
/// the page's string keys.
enum OnboardingGrant: String, CaseIterable, Sendable {
    case camera
    case accessibility
    case calendar
    /// Asked for by the session monitor, a terminal jump and a reply, all
    /// of which belong to the agent half.
    case automation

    var symbol: String {
        switch self {
        case .camera: "camera.fill"
        case .accessibility: "accessibility"
        case .calendar: "calendar"
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

    static func shown(agentsEnabled: Bool) -> [OnboardingGrant] {
        agentsEnabled ? allCases : allCases.filter { !$0.isAgentsOnly }
    }
}

// MARK: - 11. Tips

/// A card a trick: a picture, a name and one sentence.
struct OnboardingTipsPage: View {
    let context: OnboardingPageContext

    private static let columnCount = 4
    private static let spacing: CGFloat = 10

    var body: some View {
        let state = context.state
        let tips = OnboardingTip.shown(
            agentsEnabled: state.agentsEnabled,
            widgets: Set(state.shownPlacements.map(\.kind))
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

    /// The tips in rows of four. A short last row sits in the middle.
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
            Text(context.t("onboarding.tips.\(name).text"))
                .font(.system(size: 11.5))
                .foregroundStyle(OnboardingStyle.secondaryText)
                .lineSpacing(1.5)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(width: 201.5, height: 178, alignment: .topLeading)
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
            agentsEnabled: state.agentsEnabled,
            hasTodoWidget: state.showsWidget(.todo),
            hasNotesWidget: state.showsWidget(.notes),
            hasWeatherWidget: state.showsWidget(.weather)
        )
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
                    recapRow("onboarding.done.recap.\(row.rawValue)") { recapContent(row) }
                }
            }
            .background(OnboardingCardBackground())
            .frame(width: 540)

            OnboardingNote(text: context.t("onboarding.done.where"))
                .multilineTextAlignment(.center)
                .frame(maxWidth: OnboardingStyle.textWidth)
                .padding(.top, 12)

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
        case .todos: recapValue(context.t(OnboardingTodoGuide.nameKey(for: state.todoSource)))
        case .notes: recapValue(context.t(OnboardingNotesGuide.titleKey(for: state.notesDestination)))
        case .weather: recapValue(weatherText)
        case .layout: recapValue(layoutText)
        case .opened: recapValue(openedLookText)
        case .glow: recapValue(glowText)
        }
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

    private func recapRow<Value: View>(_ key: String, @ViewBuilder value: () -> Value) -> some View {
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
        // Twelve rows have to fit the window above its buttons.
        .frame(height: 27)
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
    /// Where the to-do widget gets its tasks.
    case todos
    /// Where quick notes go.
    case notes
    /// Where the user is, for the weather card.
    case weather
    case layout
    case opened
    case glow

    var isAgentsOnly: Bool {
        self == .agents || self == .approve || self == .deny
    }

    /// The rows the recap shows: nothing of agents while they are off, and
    /// no task source while the to-do widget is off the page, and no notes
    /// place while the notes widget is.
    static func shown(
        agentsEnabled: Bool,
        hasTodoWidget: Bool = true,
        hasNotesWidget: Bool = true,
        hasWeatherWidget: Bool = true
    ) -> [OnboardingRecapRow] {
        allCases.filter { row in
            (agentsEnabled || !row.isAgentsOnly)
                && (hasTodoWidget || row != .todos)
                && (hasNotesWidget || row != .notes)
                && (hasWeatherWidget || row != .weather)
        }
    }
}
