import SwiftUI

/// One page of the welcome tour. A page is a function of the tour's state
/// and draws nothing but SwiftUI, which keeps it the same in the window
/// and in a snapshot.
struct OnboardingPageView: View {
    let page: OnboardingPage
    let state: OnboardingState
    let actions: OnboardingActions
    let lang: LanguageManager

    var body: some View {
        Group {
            switch page {
            case .welcome: welcome
            case .opening: opening
            case .agents: agents
            case .nook: nook
            case .opened: OnboardingOpenedPage(state: state, actions: actions, lang: lang)
            case .look: look
            case .permissions: permissions
            case .done: done
            }
        }
        .padding(.horizontal, OnboardingStyle.sidePadding)
        // Room for the window's own buttons at the top left.
        .padding(.top, 36)
        .padding(.bottom, 16)
    }

    // MARK: - 1. Welcome

    private var welcome: some View {
        VStack(spacing: 0) {
            OnboardingScreenArt(showsContent: state.agentsEnabled)
                .frame(width: 640, height: 170)
                .padding(.top, 14)
            Spacer(minLength: 12)
            OnboardingHeading(
                title: lang.t("onboarding.welcome.title"),
                text: lang.t(state.agentsEnabled ? "onboarding.welcome.body" : "onboarding.welcome.body.nookOnly"),
                titleSize: 30
            )
            Spacer(minLength: 12)
            agentsSwitch
            Spacer(minLength: 12)
        }
    }

    /// The agents switch (D41), the same preference as the one in Settings.
    /// It is drawn in SwiftUI alone, like every control in the tour: a
    /// system switch would come out blank in a snapshot.
    private var agentsSwitch: some View {
        let isOn = state.agentsEnabled
        let title = lang.t("onboarding.welcome.agents.title")
        return Button {
            actions.setAgentsEnabled(!isOn)
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(OnboardingStyle.primaryText)
                    Text(lang.t(isOn ? "onboarding.welcome.agents.note.on" : "onboarding.welcome.agents.note.off"))
                        .font(.system(size: 12))
                        .foregroundStyle(OnboardingStyle.secondaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                OnboardingSwitchArt(isOn: isOn)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(card)
            .contentShape(RoundedRectangle(cornerRadius: OnboardingStyle.cardCornerRadius, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .frame(width: 560)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: - 2. Opening the island

    private var opening: some View {
        VStack(spacing: 20) {
            OnboardingHeading(title: lang.t("onboarding.opening.title"), text: lang.t("onboarding.opening.body"))

            HStack(spacing: 14) {
                ForEach(IslandOpenTrigger.allCases) { trigger in
                    OnboardingChoiceCard(isSelected: state.openTrigger == trigger) {
                        actions.setOpenTrigger(trigger)
                    } content: {
                        VStack(alignment: .leading, spacing: 10) {
                            triggerArt(trigger)
                            Text(lang.t(trigger.titleKey))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(OnboardingStyle.primaryText)
                            Text(lang.t(trigger.noteKey))
                                .font(.system(size: 12))
                                .foregroundStyle(OnboardingStyle.secondaryText)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(18)
                    }
                    .frame(height: 204)
                }
            }

            VStack(spacing: 6) {
                tryItLine
                Text(lang.t(IslandOpenTrigger.filesNoteKey))
                    .font(.system(size: 11.5))
                    .foregroundStyle(OnboardingStyle.faintText)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)
        }
    }

    /// Invites the user to open the real island, and answers when they do.
    /// The answer stays once it is given: the island closing again does not
    /// take it back.
    private var tryItLine: some View {
        let hasTried = state.hasOpenedIsland || state.isIslandOpen
        let key = hasTried
            ? "onboarding.opening.tried"
            : (state.openTrigger == .hover ? "onboarding.opening.try.hover" : "onboarding.opening.try.click")
        return HStack(spacing: 6) {
            Image(systemName: hasTried ? "checkmark.circle.fill" : "arrow.up")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hasTried ? OnboardingStyle.finished : OnboardingStyle.paper)
            Text(lang.t(key))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(OnboardingStyle.primaryText)
        }
    }

    /// The closed island and the pointer doing what opens it.
    private func triggerArt(_ trigger: IslandOpenTrigger) -> some View {
        ZStack(alignment: .top) {
            OnboardingPillArt(width: 150, height: 26, glow: nil, showsContent: false)
            Image(systemName: trigger == .hover ? "cursorarrow.rays" : "cursorarrow.click.2")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(OnboardingStyle.paper)
                .offset(x: 34, y: 20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 78, alignment: .top)
        .accessibilityHidden(true)
    }

    // MARK: - 3. Agents

    private var agents: some View {
        VStack(spacing: 18) {
            OnboardingHeading(title: lang.t("onboarding.agents.title"), text: lang.t("onboarding.agents.body"))

            HStack(alignment: .top, spacing: 16) {
                approvalPicture
                    .frame(width: 340)
                connectList
                    .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 0)
        }
    }

    /// A picture of the card an agent's request shows, with the two
    /// shortcuts under it. The buttons in it are drawn, not live.
    private var approvalPicture: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Circle().fill(OnboardingStyle.waiting).frame(width: 8, height: 8)
                    Text("Claude Code")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(OnboardingStyle.primaryText)
                    Text(lang.t("onboarding.agents.card.asks"))
                        .font(.system(size: 12))
                        .foregroundStyle(OnboardingStyle.secondaryText)
                        .lineLimit(1)
                }
                Text("npm test")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(OnboardingStyle.primaryText)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.07)))
                HStack(spacing: 8) {
                    pictureButton(lang.t("approval.deny"), filled: false)
                    pictureButton(lang.t("approval.allowOnce"), filled: true)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(OnboardingStyle.waiting.opacity(0.45), lineWidth: 1)
            )
            .accessibilityHidden(true)

            shortcuts
        }
    }

    private func pictureButton(_ title: String, filled: Bool) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(filled ? OnboardingStyle.ink : OnboardingStyle.primaryText)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(filled ? OnboardingStyle.paper : Color.white.opacity(0.1))
            )
    }

    @ViewBuilder
    private var shortcuts: some View {
        if state.approveKeys == nil, state.denyKeys == nil {
            note(lang.t("onboarding.agents.keys.off"))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                note(lang.t("onboarding.agents.keys.title"))
                if let caps = state.approveKeys {
                    shortcutRow(caps, lang.t("onboarding.agents.keys.approve"))
                }
                if let caps = state.denyKeys {
                    shortcutRow(caps, lang.t("onboarding.agents.keys.deny"))
                }
            }
        }
    }

    private func shortcutRow(_ caps: [String], _ text: String) -> some View {
        HStack(spacing: 8) {
            OnboardingKeyCaps(caps: caps)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(OnboardingStyle.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var connectList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lang.t("onboarding.agents.connect.title"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OnboardingStyle.primaryText)

            VStack(spacing: 0) {
                ForEach(Array(OnboardingAgent.allCases.enumerated()), id: \.element) { index, agent in
                    if index > 0 { divider }
                    agentRow(agent)
                }
            }
            .background(card)

            if let failed = failedAgentNames {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(OnboardingStyle.waiting)
                    Text(lang.t("onboarding.agents.failed.note", failed))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(OnboardingStyle.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            } else {
                note(lang.t("onboarding.agents.connect.note"))
            }

            Button(lang.t("onboarding.agents.all")) { actions.showAllAgents() }
                .buttonStyle(OnboardingSecondaryButtonStyle(height: 28))
        }
    }

    private func agentRow(_ agent: OnboardingAgent) -> some View {
        let status = state.status(of: agent)
        return HStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(OnboardingStyle.secondaryText)
                .frame(width: 18)
            Text(agent.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(OnboardingStyle.primaryText)
            Spacer(minLength: 8)
            if status.isConnected {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(OnboardingStyle.finished)
                    Text(lang.t("onboarding.agents.connected"))
                        .foregroundStyle(OnboardingStyle.secondaryText)
                }
                .font(.system(size: 12, weight: .medium))
            } else if status.isBusy {
                Text(lang.t("onboarding.agents.connecting"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OnboardingStyle.secondaryText)
            } else {
                if status.didFail {
                    Text(lang.t("onboarding.agents.failed"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(OnboardingStyle.waiting)
                        .lineLimit(1)
                }
                let title = lang.t(status.didFail ? "onboarding.agents.retry" : "onboarding.agents.connect")
                Button(title) { actions.connect(agent) }
                    .buttonStyle(OnboardingSecondaryButtonStyle(height: 26))
                    .disabled(!status.canConnect)
                    .opacity(status.canConnect ? 1 : 0.4)
                    .accessibilityLabel("\(title) \(agent.name)")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }

    /// The agents whose Connect did not work, by name, or nil when none
    /// failed.
    private var failedAgentNames: String? {
        let names = OnboardingAgent.allCases.filter { state.status(of: $0).didFail }.map(\.name)
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    // MARK: - 4. The Nook

    private var nook: some View {
        VStack(spacing: 12) {
            OnboardingHeading(
                title: lang.t("onboarding.nook.title"),
                text: lang.t(state.agentsEnabled ? "onboarding.nook.body" : "onboarding.nook.body.nookOnly")
            )

            HStack(spacing: 6) {
                ForEach(NookWidgetKind.allCases) { kind in
                    widgetChip(kind)
                }
            }

            note(lang.t("onboarding.nook.widgets.note"))
                .multilineTextAlignment(.center)

            HStack(spacing: 5) {
                ForEach(PersonalizationTemplate.offered(agentsEnabled: state.agentsEnabled)) { template in
                    templateCard(template)
                }
            }

            note(lang.t("onboarding.nook.templates.note"))
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)
        }
    }

    /// A widget's switch: bright while the widget is on.
    private func widgetChip(_ kind: NookWidgetKind) -> some View {
        let isOn = state.enabledWidgets.contains(kind)
        let name = lang.t("onboarding.nook.widget.\(kind.rawValue)")
        return Button {
            actions.setWidget(kind, !isOn)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isOn ? "checkmark" : "plus")
                    .font(.system(size: 9, weight: .bold))
                Image(systemName: kind.systemImage)
                    .font(.system(size: 10.5, weight: .medium))
                Text(name)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isOn ? OnboardingStyle.ink : OnboardingStyle.secondaryText)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(Capsule().fill(isOn ? OnboardingStyle.paper : Color.white.opacity(0.08)))
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func templateCard(_ template: PersonalizationTemplate) -> some View {
        let text = TemplateText(template.id, lang: lang, showsAgents: state.agentsEnabled)
        return OnboardingChoiceCard(isSelected: state.shownTemplate == template.id) {
            actions.applyTemplate(template)
        } content: {
            VStack(alignment: .leading, spacing: 7) {
                TemplateThumbnail(template: template, showsAgents: state.agentsEnabled)
                Text(text.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OnboardingStyle.primaryText)
                    .lineLimit(1)
                Text(text.bestFor)
                    .font(.system(size: 10.5))
                    .foregroundStyle(OnboardingStyle.secondaryText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(4)
        }
        .frame(width: 156, height: 178)
        .accessibilityLabel(text.spokenSummary)
    }

    // MARK: - 5. The glow

    private var look: some View {
        VStack(spacing: 12) {
            OnboardingHeading(
                title: lang.t("onboarding.look.title"),
                text: lang.t(state.agentsEnabled ? "onboarding.look.body" : "onboarding.look.body.nookOnly")
            )

            HStack(spacing: 14) {
                ForEach(IslandHaloStyle.allCases) { style in
                    OnboardingChoiceCard(isSelected: state.glowStyle == style) {
                        actions.setGlowStyle(style)
                    } content: {
                        VStack(spacing: 0) {
                            OnboardingPillArt(
                                width: 170,
                                height: 28,
                                glow: style == .off ? nil : glowSampleColor,
                                glowStrength: style == .vivid ? 1 : 0.45,
                                showsContent: state.agentsEnabled
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 76)
                            Text(lang.t("settings.appearance.nook.halo.\(style.rawValue)"))
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(OnboardingStyle.primaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, 12)
                        }
                    }
                    .frame(height: 116)
                }
            }

            Text(lang.t("onboarding.look.themes"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OnboardingStyle.secondaryText)
                .accessibilityAddTraits(.isHeader)

            OnboardingGlowThemeGrid(selectedID: state.glowThemeID, lang: lang) { theme in
                actions.setGlowTheme(theme)
            }

            note(lang.t("onboarding.look.note"))
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)
        }
    }

    /// The color the three sample pills glow in: the chosen theme's color
    /// for an agent that waits for approval, or its color for a notice
    /// while the agents are switched off.
    private var glowSampleColor: Color {
        let palette = state.glowThemeID.flatMap(IslandHaloTheme.theme(id:))?.palette
        let color = state.agentsEnabled ? palette?.approval : palette?.notice
        return color?.color ?? OnboardingStyle.waiting
    }

    // MARK: - 6. Permissions

    /// Says in plain words what asks macOS for access and when. Nothing on
    /// this page asks for anything: it has no button at all.
    private var permissions: some View {
        VStack(spacing: 18) {
            OnboardingHeading(title: lang.t("onboarding.permissions.title"), text: lang.t("onboarding.permissions.body"))

            VStack(spacing: 0) {
                let grants = OnboardingGrant.shown(agentsEnabled: state.agentsEnabled)
                ForEach(Array(grants.enumerated()), id: \.element) { index, grant in
                    if index > 0 { divider }
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: grant.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(OnboardingStyle.paper)
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.09))
                            )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(lang.t("onboarding.permissions.\(grant.rawValue).title"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(OnboardingStyle.primaryText)
                            Text(lang.t("onboarding.permissions.\(grant.rawValue).note"))
                                .font(.system(size: 12))
                                .foregroundStyle(OnboardingStyle.secondaryText)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .accessibilityElement(children: .combine)
                }
            }
            .background(card)
            .frame(width: 620)

            Spacer(minLength: 0)
        }
    }

    // MARK: - 7. Done

    private var done: some View {
        VStack(spacing: 0) {
            OnboardingPillArt(
                width: 230,
                height: 34,
                glow: OnboardingStyle.finished,
                glowStrength: 0.85,
                showsContent: state.agentsEnabled
            )
            .frame(height: 74)
                .padding(.top, 2)

            OnboardingHeading(
                title: lang.t("onboarding.done.title"),
                text: lang.t(state.openTrigger == .hover ? "onboarding.done.body.hover" : "onboarding.done.body.click"),
                titleSize: 30
            )
            .padding(.bottom, 12)

            VStack(spacing: 0) {
                let rows = OnboardingRecapRow.shown(agentsEnabled: state.agentsEnabled)
                ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                    if index > 0 { divider }
                    recapRow("onboarding.done.recap.\(row.rawValue)") { recapContent(row) }
                }
            }
            .background(card)
            .frame(width: 520)

            note(lang.t("onboarding.done.where"))
                .multilineTextAlignment(.center)
                .frame(maxWidth: OnboardingStyle.textWidth)
                .padding(.top, 10)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func recapContent(_ row: OnboardingRecapRow) -> some View {
        switch row {
        case .opens: recapValue(lang.t(state.openTrigger.titleKey))
        case .agents: recapValue(connectedAgentsText)
        case .approve: recapKeys(state.approveKeys)
        case .deny: recapKeys(state.denyKeys)
        case .glow: recapValue(glowText)
        case .layout: recapValue(layoutText)
        case .opened: recapValue(openedLookText)
        }
    }

    private var connectedAgentsText: String {
        let names = state.connectedAgents.map(\.name).joined(separator: ", ")
        switch (names.isEmpty, state.hasAgentOutsideTour) {
        case (true, false): return lang.t("onboarding.done.recap.agents.none")
        case (true, true): return lang.t("onboarding.done.recap.agents.otherOnly")
        case (false, false): return names
        case (false, true): return lang.t("onboarding.done.recap.agents.more", names)
        }
    }

    /// The layout picked in the tour by its name, or the one the display
    /// was on, or "your own".
    private var layoutText: String {
        guard let id = state.shownTemplate else { return lang.t("onboarding.done.recap.layout.own") }
        return TemplateText(id, lang: lang).title
    }

    /// The glow's strength and, while it is on, the theme its colors are.
    private var glowText: String {
        let style = lang.t("settings.appearance.nook.halo.\(state.glowStyle.rawValue)")
        guard state.glowStyle != .off,
              let theme = state.glowThemeID.flatMap(IslandHaloTheme.theme(id:)),
              theme.id != IslandHaloTheme.standard.id
        else { return style }
        return "\(style) · \(lang.t(theme.titleKey))"
    }

    private var openedLookText: String {
        lang.t(
            "onboarding.done.recap.opened.value",
            lang.t("settings.appearance.openedLook.width.\(state.openedLook.width.rawValue)"),
            lang.t("settings.appearance.openedLook.corners.\(state.openedLook.corners.rawValue)")
        )
    }

    private func recapRow<Value: View>(_ key: String, @ViewBuilder value: () -> Value) -> some View {
        HStack(spacing: 12) {
            Text(lang.t(key))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(OnboardingStyle.primaryText)
            Spacer(minLength: 12)
            value()
        }
        .padding(.horizontal, 14)
        // Seven rows have to fit the window above its buttons.
        .frame(height: 33)
        .accessibilityElement(children: .combine)
    }

    private func recapValue(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(OnboardingStyle.secondaryText)
            .lineLimit(1)
    }

    @ViewBuilder
    private func recapKeys(_ caps: [String]?) -> some View {
        if let caps {
            OnboardingKeyCaps(caps: caps)
        } else {
            recapValue(lang.t("onboarding.done.recap.keys.off"))
        }
    }

    // MARK: - Shared pieces

    private var card: some View {
        RoundedRectangle(cornerRadius: OnboardingStyle.cardCornerRadius, style: .continuous)
            .fill(OnboardingStyle.cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: OnboardingStyle.cardCornerRadius, style: .continuous)
                    .strokeBorder(OnboardingStyle.cardStroke, lineWidth: 1)
            )
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(OnboardingStyle.faintText)
            .fixedSize(horizontal: false, vertical: true)
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

    static func shown(agentsEnabled: Bool) -> [OnboardingGrant] {
        agentsEnabled ? allCases : allCases.filter { !$0.isAgentsOnly }
    }
}

/// The rows of the last page's recap, in order. The raw value is the name
/// in the row's string key.
enum OnboardingRecapRow: String, CaseIterable, Sendable {
    case opens
    case agents
    case approve
    case deny
    case glow
    case layout
    case opened

    var isAgentsOnly: Bool {
        self == .agents || self == .approve || self == .deny
    }

    static func shown(agentsEnabled: Bool) -> [OnboardingRecapRow] {
        agentsEnabled ? allCases : allCases.filter { !$0.isAgentsOnly }
    }
}

/// A switch drawn in SwiftUI: a track and a knob that slides.
struct OnboardingSwitchArt: View {
    let isOn: Bool

    private static let size = CGSize(width: 42, height: 24)
    private static let knobInset: CGFloat = 3

    var body: some View {
        Capsule()
            .fill(isOn ? OnboardingStyle.finished : Color.white.opacity(0.16))
            .frame(width: Self.size.width, height: Self.size.height)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .padding(Self.knobInset)
            }
            .accessibilityHidden(true)
    }
}

/// A page's headline and the sentence or two under it.
struct OnboardingHeading: View {
    let title: String
    let text: String
    var titleSize: CGFloat = 26

    var body: some View {
        VStack(spacing: 9) {
            Text(title)
                .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                .foregroundStyle(OnboardingStyle.primaryText)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(OnboardingStyle.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: OnboardingStyle.textWidth)
        }
    }
}
