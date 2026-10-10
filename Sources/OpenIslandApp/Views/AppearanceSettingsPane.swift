import SwiftUI
import OpenIslandCore

/// v6 Personalization tab.
///
/// Two concerns, one preview:
/// - **Right slot** — what shows on the right of the closed island.
/// - **Center label** — what shows in the middle on external displays.
///
/// Everything else (idle behavior, per-tool agent colors, spinner, custom
/// avatars) was cut in the v6 redesign round.
///
/// The pane itself only lays sections out. Each section is a small child view
/// with narrow value inputs, so a click re-renders that section and not the
/// whole tab, and the closed preview owns its own auto-cycle state.
struct AppearanceSettingsPane: View {
    var model: AppModel
    /// One namespace for every row of cards, so each row's selection ring
    /// slides between that row's cards. The ring group tells the rows apart.
    @Namespace private var ringNamespace

    var lang: LanguageManager { model.lang }
    var editingProfile: IslandAppearanceDisplayProfile { model.appearanceSettingsProfile }
    private var editingPreferences: IslandAppearancePreferences {
        model.appearancePreferences(for: editingProfile)
    }
    private var languageCode: String { lang.language.resolvedCode }
    /// The agents switch. Off, the tab leaves out every choice that only
    /// makes sense with agents (D41).
    var showsAgents: Bool { model.agentsEnabled }

    var body: some View {
        ScrollView {
            contentColumn
        }
        .background(Color(red: 0.055, green: 0.055, blue: 0.06))
        .navigationTitle(lang.t("settings.tab.appearance"))
    }

    /// Everything inside the scroll view. Internal so a render can draw it
    /// without the `ScrollView`, which `ImageRenderer` leaves blank.
    var contentColumn: some View {
        VStack(alignment: .leading, spacing: 32) {
            displayProfilePart
            TemplatesSection(model: model, profile: editingProfile, ringNamespace: ringNamespace)
            notchPersonalizationPart
            sessionListPersonalizationPart
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Display profile

    private var displayProfilePart: some View {
        DisplayProfileSection(
            header: lang.t("settings.appearance.profile.title"),
            note: lang.t("settings.appearance.profile.note"),
            items: [
                .init(
                    profile: .topBar,
                    icon: "display",
                    title: lang.t("settings.appearance.profile.external.title"),
                    note: lang.t("settings.appearance.profile.external.note")
                ),
                .init(
                    profile: .notch,
                    icon: "laptopcomputer",
                    title: lang.t("settings.appearance.profile.macbook.title"),
                    note: lang.t("settings.appearance.profile.macbook.note")
                ),
            ],
            selected: editingProfile,
            ringNamespace: ringNamespace
        ) { [model] profile in
            // The whole tab changes shape with the display, so this one morphs.
            withMotion(Motion.morph) { model.appearanceSettingsProfile = profile }
        }
        .equatable()
    }

    // MARK: - Notch part

    private var notchPersonalizationPart: some View {
        VStack(alignment: .leading, spacing: 18) {
            partHeader(title: lang.t("settings.appearance.notchPart.title"))
            ClosedPreviewSection(
                model: model,
                profile: editingProfile,
                rightSlot: editingPreferences.rightSlot,
                centerLabel: editingPreferences.centerLabel
            )
            if showsAgents {
                rightSlotSection
                nookHost { nookRightSlotExtras }
                centerLabelSection
            } else {
                // The island's own three cards and both center labels show
                // agents. What is left of the right side is one row.
                nookHost { nookRightSlotWithoutAgents }
            }
            nookHost { nookLeftSlotSection }
            nookHost { nookClosedSection }
            nookHost { nookHaloSection }
        }
    }

    // MARK: - Session list part

    private var sessionListPersonalizationPart: some View {
        VStack(alignment: .leading, spacing: 18) {
            // With the agents switched off the opened island has no
            // session list, and the part is named for what is left.
            partHeader(title: lang.t(
                showsAgents ? "settings.appearance.sessionListPart.title" : "settings.appearance.openedPart.title"
            ))
            if showsAgents { sessionListPreviewSection }
            nookHost { nookOpenedLookSection }
            if showsAgents {
                usageDisplaySection
                stateIndicatorSection
                sessionGroupSection
                sessionSortSection
                staleThresholdSection
            }
            nookHost { nookOpenedSection }
        }
    }

    /// Hosts one of the Nook extension's sections as its own view. What it
    /// reads from the model is tracked here, so the pane does not re-run for
    /// it, and an unrelated change to the pane leaves it alone.
    private func nookHost<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> some View {
        NookSectionHost(profile: editingProfile, languageCode: languageCode, content: content)
            .equatable()
    }

    // MARK: - Session list preview

    private var sessionListPreviewSection: some View {
        let preferences = editingPreferences
        return SessionListPreviewSection(
            lang: lang,
            languageCode: languageCode,
            profile: editingProfile,
            look: model.nook.displayPreferences(for: editingProfile).openedLook,
            group: preferences.sessionGroup,
            sort: preferences.sessionSort,
            staleThreshold: preferences.completedStaleThreshold,
            indicator: preferences.sessionStateIndicator
        )
        .equatable()
    }

    // MARK: - 01 · Right slot

    private var rightSlotSection: some View {
        // A Nook slot on the right takes the choice away from the island's own
        // three cards, so none of them is selected then.
        let nookSlotIsSet = model.nook.displayPreferences(for: editingProfile).rightSlot != nil
        return AppearanceOptionSection(
            header: lang.t("settings.appearance.rightSlot.title"),
            note: lang.t("settings.appearance.rightSlot.note"),
            items: [
                .init(option: IslandRightSlot.count, title: lang.t("settings.appearance.rightSlot.count")),
                .init(option: .agents, title: lang.t("settings.appearance.rightSlot.agents")),
                .init(option: .none, title: lang.t("settings.appearance.rightSlot.none")),
            ],
            selected: nookSlotIsSet ? nil : editingPreferences.rightSlot,
            ringNamespace: ringNamespace,
            ringGroup: "rightSlot",
            select: { [model] option in
                withMotion(Motion.selection) {
                    model.chooseRightSide(.own(option), for: model.appearanceSettingsProfile)
                }
            },
            icon: { option in
                switch option {
                case .count:
                    CountBadgePreview(count: 3)
                case .agents:
                    AgentsMiniGridPreview()
                case .none:
                    Text("—")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(V6Palette.paper.opacity(0.5))
                }
            }
        )
        .equatable()
    }

    // MARK: - 02 · Center label

    private var centerLabelSection: some View {
        AppearanceOptionSection(
            header: lang.t("settings.appearance.centerLabel.title"),
            note: lang.t("settings.appearance.centerLabel.note"),
            items: [
                .init(option: IslandCenterLabel.agentAction, title: lang.t("settings.appearance.centerLabel.agentAction")),
                .init(option: .sessionName, title: lang.t("settings.appearance.centerLabel.sessionName")),
                .init(option: .off, title: lang.t("settings.appearance.centerLabel.off")),
            ],
            selected: editingPreferences.centerLabel,
            ringNamespace: ringNamespace,
            ringGroup: "centerLabel",
            select: { [model] option in
                Self.applyChoice(on: model) { $0.centerLabel = option }
            },
            icon: { option in
                Text(Self.centerLabelSample(for: option))
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(V6Palette.paper.opacity(option == .off ? 0.4 : 0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 12)
            }
        )
        .equatable()
    }

    private static func centerLabelSample(for option: IslandCenterLabel) -> String {
        switch option {
        case .agentAction: "Claude · editing"
        case .sessionName: "open-island"
        case .off:         "—"
        }
    }

    // MARK: - 02 · Usage

    private var usageDisplaySection: some View {
        let lang = lang
        return AppearanceOptionSection(
            header: lang.t("settings.appearance.usageDisplay.title"),
            note: lang.t("settings.appearance.usageDisplay.note"),
            items: IslandUsageDisplay.allCases.map { .init(option: $0, title: lang.appearanceTitle(for: $0)) },
            selected: editingPreferences.usageDisplay,
            ringNamespace: ringNamespace,
            ringGroup: "usageDisplay",
            select: { [model] option in
                Self.applyChoice(on: model) { $0.usageDisplay = option }
            },
            icon: { UsageDisplayPreview(option: $0) }
        )
        .equatable()
    }

    // MARK: - 03 · Session state

    private var stateIndicatorSection: some View {
        let lang = lang
        return AppearanceOptionSection(
            header: lang.t("settings.appearance.stateIndicator.title"),
            note: lang.t("settings.appearance.stateIndicator.note"),
            items: [IslandSessionStateIndicator.animatedDot, .bar, .glyph, .tint].map {
                .init(option: $0, title: lang.appearanceTitle(for: $0))
            },
            selected: editingPreferences.sessionStateIndicator,
            ringNamespace: ringNamespace,
            ringGroup: "stateIndicator",
            select: { [model] option in
                Self.applyChoice(on: model) { $0.sessionStateIndicator = option }
            },
            icon: { StateIndicatorPreview(option: $0) }
        )
        .equatable()
    }

    // MARK: - 04 · Session grouping

    private var sessionGroupSection: some View {
        let lang = lang
        return AppearanceOptionSection(
            header: lang.t("settings.appearance.sessionGroup.title"),
            note: lang.t("settings.appearance.sessionGroup.note"),
            items: IslandSessionGroup.allCases.map { .init(option: $0, title: lang.appearanceTitle(for: $0)) },
            selected: editingPreferences.sessionGroup,
            ringNamespace: ringNamespace,
            ringGroup: "sessionGroup",
            select: { [model] option in
                Self.applyChoice(on: model) { $0.sessionGroup = option }
            },
            icon: { SessionGroupPreview(option: $0) }
        )
        .equatable()
    }

    // MARK: - 05 · Session sorting

    private var sessionSortSection: some View {
        let lang = lang
        return AppearanceOptionSection(
            header: lang.t("settings.appearance.sessionSort.title"),
            note: lang.t("settings.appearance.sessionSort.note"),
            items: IslandSessionSort.allCases.map { .init(option: $0, title: lang.appearanceTitle(for: $0)) },
            selected: editingPreferences.sessionSort,
            ringNamespace: ringNamespace,
            ringGroup: "sessionSort",
            select: { [model] option in
                Self.applyChoice(on: model) { $0.sessionSort = option }
            },
            icon: { SessionSortPreview(option: $0) }
        )
        .equatable()
    }

    // MARK: - 06 · Done timeout

    private var staleThresholdSection: some View {
        let lang = lang
        return AppearanceOptionSection(
            header: lang.t("settings.appearance.staleThreshold.title"),
            note: lang.t("settings.appearance.staleThreshold.note"),
            items: IslandCompletedStaleThreshold.allCases.map { .init(option: $0, title: lang.appearanceTitle(for: $0)) },
            selected: editingPreferences.completedStaleThreshold,
            arrangement: .grid,
            ringNamespace: ringNamespace,
            ringGroup: "staleThreshold",
            select: { [model] option in
                Self.applyChoice(on: model) { $0.completedStaleThreshold = option }
            },
            icon: { option in
                Text(lang.appearanceTitle(for: option))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(V6Palette.paper.opacity(0.9))
            }
        )
        .equatable()
    }

    // MARK: - Helpers

    /// Writes one choice for the display being edited, animated. The display
    /// is read when the click lands: a section that did not re-render after a
    /// display switch (its inputs were equal) must still write to the right one.
    private static func applyChoice(
        on model: AppModel,
        _ update: (inout IslandAppearancePreferences) -> Void
    ) {
        withMotion(Motion.selection) {
            model.updateAppearancePreferences(for: model.appearanceSettingsProfile, update)
        }
    }

    private func partHeader(title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
    }

    /// A tile card for the Nook extension's rows. Pass a `ringGroup` to let
    /// the selection ring slide between the cards that share it (the pane's
    /// own rows use "rightSlot", "centerLabel" and so on).
    func optionCard<Icon: View>(
        selected: Bool,
        title: String,
        ringGroup: String? = nil,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        PersonalizationCard(
            title: title,
            selected: selected,
            style: .tile,
            ringNamespace: ringGroup == nil ? nil : ringNamespace,
            ringGroup: ringGroup ?? "",
            action: action,
            icon: icon
        )
    }

    func sectionHeader(title: String, note: String?) -> some View {
        PersonalizationSectionHeader(title: title, note: note)
    }

    func monoChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        MonoChip(title: title, selected: selected, action: action)
    }

    /// Sample content for the preview and the option cards.
    static func sampleSideSlot(_ slot: NookSideSlot, mode: UnifiedBars.Mode = .running) -> NookSideSlotContent? {
        switch slot {
        case .agents: .bars(mode)
        case .count: .agentSlot(.count(3))
        case .grid: .agentSlot(.agents(Array(repeating: .session(color: .orange, state: .running), count: 3)))
        case .date: .date(Calendar.current.component(.day, from: Date()))
        case .battery: .battery(percent: 82, isCharging: false)
        case .countdown: .countdown("42m")
        case .weather: .weather(text: "72°", symbol: "cloud.sun.fill")
        case .timer: .timer("24m")
        case .todos: .todos(3)
        case .none: .hidden
        }
    }
}

// MARK: - Sections

/// The display profile cards. These are wide rows, so the section spaces them
/// a little tighter than the tile sections below.
private struct DisplayProfileSection: View, Equatable {
    struct Item: Hashable, Sendable {
        let profile: IslandAppearanceDisplayProfile
        let icon: String
        let title: String
        let note: String
    }

    let header: String
    let note: String
    let items: [Item]
    let selected: IslandAppearanceDisplayProfile
    let ringNamespace: Namespace.ID
    let select: (IslandAppearanceDisplayProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PersonalizationSectionHeader(title: header, note: note)

            HStack(spacing: 12) {
                ForEach(items, id: \.profile) { item in
                    PersonalizationCard(
                        title: item.title,
                        selected: item.profile == selected,
                        style: .row(note: item.note),
                        ringNamespace: ringNamespace,
                        ringGroup: "profile",
                        action: { select(item.profile) }
                    ) {
                        Image(systemName: item.icon)
                    }
                }
            }
        }
    }

    nonisolated static func == (lhs: DisplayProfileSection, rhs: DisplayProfileSection) -> Bool {
        lhs.header == rhs.header
            && lhs.note == rhs.note
            && lhs.items == rhs.items
            && lhs.selected == rhs.selected
    }
}

/// A header and one set of selectable tiles. Two sections are equal when what
/// they would draw is equal (the icon and the action are fixed per option), so
/// a click in another section never touches this one.
private struct AppearanceOptionSection<Option: Hashable & Sendable, Icon: View>: View, Equatable {
    enum Arrangement: Sendable {
        case row
        case grid
    }

    struct Item: Hashable, Sendable {
        let option: Option
        let title: String
    }

    let header: String
    let note: String?
    let items: [Item]
    /// Nil when none of the tiles is chosen.
    let selected: Option?
    var arrangement: Arrangement = .row
    let ringNamespace: Namespace.ID
    let ringGroup: String
    let select: (Option) -> Void
    @ViewBuilder let icon: (Option) -> Icon

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PersonalizationSectionHeader(title: header, note: note)

            switch arrangement {
            case .row:
                HStack(spacing: 12) { cards }
            case .grid:
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 104), spacing: 12)],
                    alignment: .leading,
                    spacing: 12
                ) { cards }
            }
        }
    }

    private var cards: some View {
        ForEach(items, id: \.option) { item in
            PersonalizationCard(
                title: item.title,
                selected: item.option == selected,
                style: .tile,
                ringNamespace: ringNamespace,
                ringGroup: ringGroup,
                action: { select(item.option) }
            ) {
                icon(item.option)
            }
        }
    }

    nonisolated static func == (lhs: AppearanceOptionSection, rhs: AppearanceOptionSection) -> Bool {
        lhs.header == rhs.header
            && lhs.note == rhs.note
            && lhs.items == rhs.items
            && lhs.selected == rhs.selected
            && lhs.arrangement == rhs.arrangement
            && lhs.ringGroup == rhs.ringGroup
    }
}

/// Hosts a section the Nook extension builds, so its reads of the model are
/// tracked on this view. Equal while the display and the language are.
///
/// The extension's sections are several views in a row (header, cards,
/// toggles). The stack gives them the same spacing they had as direct
/// children of the part, which an equatable wrapper would not do on its own.
private struct NookSectionHost<Content: View>: View, Equatable {
    let profile: IslandAppearanceDisplayProfile
    let languageCode: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            content()
        }
    }

    nonisolated static func == (lhs: NookSectionHost, rhs: NookSectionHost) -> Bool {
        lhs.profile == rhs.profile && lhs.languageCode == rhs.languageCode
    }
}

/// The session list preview and what it draws from. It takes the four
/// preferences that shape the list, so it ignores every other click.
private struct SessionListPreviewSection: View, Equatable {
    let lang: LanguageManager
    let languageCode: String
    let profile: IslandAppearanceDisplayProfile
    let look: IslandOpenedLook
    let group: IslandSessionGroup
    let sort: IslandSessionSort
    let staleThreshold: IslandCompletedStaleThreshold
    let indicator: IslandSessionStateIndicator

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PersonalizationSectionHeader(title: lang.t("settings.appearance.sessionPreview"), note: nil)

            SettingsPreviewStage(contentTopPadding: 20, contentBottomPadding: 28) {
                SessionListPanelPreview(
                    sections: sections,
                    showsSections: group != .none,
                    indicator: indicator,
                    profile: profile,
                    look: look,
                    lang: lang
                )
                .equatable()
                .padding(.horizontal, 18)
            }
            .padding(.top, 8)
        }
    }

    nonisolated static func == (lhs: SessionListPreviewSection, rhs: SessionListPreviewSection) -> Bool {
        lhs.languageCode == rhs.languageCode
            && lhs.profile == rhs.profile
            && lhs.look == rhs.look
            && lhs.group == rhs.group
            && lhs.sort == rhs.sort
            && lhs.staleThreshold == rhs.staleThreshold
            && lhs.indicator == rhs.indicator
    }

    private var sections: [AppearanceSessionPreviewSection] {
        SessionListPreviewSamples.sections(lang: lang, group: group, sort: sort, staleThreshold: staleThreshold)
    }
}

/// The sample sessions the previews list, grouped and sorted the way a setup
/// asks. Shared by the session list preview and the preview stage.
@MainActor
struct SessionListPreviewSamples {
    let lang: LanguageManager
    let group: IslandSessionGroup
    let sort: IslandSessionSort
    let staleThreshold: IslandCompletedStaleThreshold
    /// Keeps only the first sessions in list order. Nil keeps all five.
    var limit: Int? = nil

    static func sections(
        lang: LanguageManager,
        group: IslandSessionGroup,
        sort: IslandSessionSort,
        staleThreshold: IslandCompletedStaleThreshold,
        limit: Int? = nil
    ) -> [AppearanceSessionPreviewSection] {
        SessionListPreviewSamples(
            lang: lang, group: group, sort: sort, staleThreshold: staleThreshold, limit: limit
        ).sections
    }

    var sections: [AppearanceSessionPreviewSection] {
        var items = sortedItems
        if let limit { items = Array(items.prefix(limit)) }

        switch group {
        case .none:
            return [
                AppearanceSessionPreviewSection(
                    id: "all",
                    title: lang.t("settings.appearance.sessionGroup.none"),
                    items: items
                )
            ]
        case .state:
            let groups: [(String, String, (AppearanceSessionPreviewItem) -> Bool)] = [
                ("approval", lang.t("island.section.needsApproval"), { $0.phase == .approval }),
                ("answer", lang.t("island.section.needsAnswer"), { $0.phase == .answer }),
                ("running", lang.t("island.section.inProgress"), { $0.phase == .running }),
                ("done", lang.t("island.section.justDone"), { $0.phase == .done }),
                ("idle", lang.t("island.section.idle"), { $0.phase == .idle }),
            ]
            return groups.compactMap { id, title, include in
                let groupItems = items.filter(include)
                guard !groupItems.isEmpty else { return nil }
                return AppearanceSessionPreviewSection(id: id, title: title, items: groupItems)
            }
        case .agent:
            let groups = ["Codex", "Claude", "Cursor", "Gemini"]
            return groups.compactMap { agent in
                let groupItems = items.filter { $0.agent == agent }
                guard !groupItems.isEmpty else { return nil }
                return AppearanceSessionPreviewSection(id: agent, title: agent, items: groupItems)
            }
        case .project:
            let groups = ["open-island", "website", "docs"]
            return groups.compactMap { project in
                let groupItems = items.filter { $0.project == project }
                guard !groupItems.isEmpty else { return nil }
                return AppearanceSessionPreviewSection(id: project, title: project, items: groupItems)
            }
        }
    }

    private var sortedItems: [AppearanceSessionPreviewItem] {
        switch sort {
        case .attention:
            return items.sorted { lhs, rhs in
                if lhs.attentionRank == rhs.attentionRank {
                    return lhs.updatedRank < rhs.updatedRank
                }
                return lhs.attentionRank < rhs.attentionRank
            }
        case .lastUpdate:
            return items.sorted { $0.updatedRank < $1.updatedRank }
        }
    }

    private var items: [AppearanceSessionPreviewItem] {
        [
            .init(
                id: "approval",
                title: "Codex · open-island",
                detail: lang.t("settings.appearance.preview.approveShellCommand"),
                agent: "Codex",
                agentShort: "codex",
                agentColor: Color(hex: AgentTool.codex.brandColorHex) ?? Color(red: 0.55, green: 0.72, blue: 1.0),
                project: "open-island",
                branch: "v8-design",
                prompt: lang.t("settings.appearance.preview.promptImplementPlan"),
                terminal: "Ghostty",
                age: "now",
                phase: .approval,
                attentionRank: 0,
                updatedRank: 2
            ),
            .init(
                id: "answer",
                title: "Claude · open-island",
                detail: lang.t("settings.appearance.preview.waitingForAnswer"),
                agent: "Claude",
                agentShort: "claude",
                agentColor: Color(hex: AgentTool.claudeCode.brandColorHex) ?? Color(red: 0.9, green: 0.55, blue: 0.34),
                project: "open-island",
                branch: "main",
                prompt: lang.t("settings.appearance.preview.promptChooseNotificationCopy"),
                terminal: "Ghostty",
                age: "1m",
                phase: .answer,
                attentionRank: 1,
                updatedRank: 3
            ),
            .init(
                id: "running",
                title: "Cursor · website",
                detail: lang.t("settings.appearance.preview.editingSessionListPreview"),
                agent: "Cursor",
                agentShort: "cursor",
                agentColor: Color(hex: AgentTool.cursor.brandColorHex) ?? Color(red: 0.62, green: 0.66, blue: 1.0),
                project: "website",
                branch: "main",
                prompt: lang.t("settings.appearance.preview.promptTightenSettingsUI"),
                terminal: "Cursor",
                age: "2m",
                phase: .running,
                attentionRank: 2,
                updatedRank: 0
            ),
            .init(
                id: "done",
                title: "Gemini · docs",
                detail: lang.t("settings.appearance.preview.replyAvailable"),
                agent: "Gemini",
                agentShort: "gemini",
                agentColor: Color(hex: AgentTool.geminiCLI.brandColorHex) ?? Color(red: 0.45, green: 0.78, blue: 1.0),
                project: "docs",
                branch: "main",
                prompt: lang.t("settings.appearance.preview.promptSummarizeDesignBundle"),
                terminal: "WezTerm",
                age: lang.appearanceTitle(for: staleThreshold),
                phase: .done,
                attentionRank: 3,
                updatedRank: 1
            ),
            .init(
                id: "idle",
                title: "Codex · open-island",
                detail: lang.t("settings.appearance.preview.completedEarlier"),
                agent: "Codex",
                agentShort: "codex",
                agentColor: Color(hex: AgentTool.codex.brandColorHex) ?? Color(red: 0.55, green: 0.72, blue: 1.0),
                project: "open-island",
                branch: nil,
                prompt: nil,
                terminal: "Ghostty",
                age: lang.t("island.sessionOverview.idle"),
                phase: .idle,
                attentionRank: 4,
                updatedRank: 4
            ),
        ]
    }
}

// MARK: - Titles

private extension LanguageManager {
    func appearanceTitle(for option: IslandSessionStateIndicator) -> String {
        switch option {
        case .animatedDot: t("settings.appearance.stateIndicator.animatedDot")
        case .bar:         t("settings.appearance.stateIndicator.bar")
        case .glyph:       t("settings.appearance.stateIndicator.glyph")
        case .tint:        t("settings.appearance.stateIndicator.tint")
        }
    }

    func appearanceTitle(for option: IslandUsageDisplay) -> String {
        switch option {
        case .hidden:  t("settings.appearance.usageDisplay.hidden")
        case .compact: t("settings.appearance.usageDisplay.compact")
        }
    }

    func appearanceTitle(for option: IslandSessionGroup) -> String {
        switch option {
        case .none:    t("settings.appearance.sessionGroup.none")
        case .state:   t("settings.appearance.sessionGroup.state")
        case .agent:   t("settings.appearance.sessionGroup.agent")
        case .project: t("settings.appearance.sessionGroup.project")
        }
    }

    func appearanceTitle(for option: IslandSessionSort) -> String {
        switch option {
        case .attention:  t("settings.appearance.sessionSort.attention")
        case .lastUpdate: t("settings.appearance.sessionSort.lastUpdate")
        }
    }

    func appearanceTitle(for option: IslandCompletedStaleThreshold) -> String {
        switch option {
        case .twoMinutes:    t("settings.appearance.staleThreshold.twoMinutes")
        case .fiveMinutes:   t("settings.appearance.staleThreshold.fiveMinutes")
        case .tenMinutes:    t("settings.appearance.staleThreshold.tenMinutes")
        case .twentyMinutes: t("settings.appearance.staleThreshold.twentyMinutes")
        case .never:         t("settings.appearance.staleThreshold.never")
        }
    }
}

// MARK: - Small preview ornaments

struct AppearanceSessionPreviewSection: Identifiable, Equatable {
    let id: String
    let title: String
    let items: [AppearanceSessionPreviewItem]
}

struct AppearanceSessionPreviewItem: Identifiable, Equatable {
    enum Phase {
        case approval
        case answer
        case running
        case done
        case idle
    }

    let id: String
    let title: String
    let detail: String
    let agent: String
    let agentShort: String
    let agentColor: Color
    let project: String
    let branch: String?
    let prompt: String?
    let terminal: String
    let age: String
    let phase: Phase
    let attentionRank: Int
    let updatedRank: Int
}

/// The dark wallpaper frame the Personalization previews sit on.
struct SettingsPreviewStage<Content: View>: View {
    var contentTopPadding: CGFloat = 20
    var contentBottomPadding: CGFloat = 24
    let content: Content

    init(
        contentTopPadding: CGFloat = 20,
        contentBottomPadding: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) {
        self.contentTopPadding = contentTopPadding
        self.contentBottomPadding = contentBottomPadding
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.top, contentTopPadding)
                .padding(.bottom, contentBottomPadding)
        }
        .frame(maxWidth: .infinity)
        .background(SettingsPreviewWallpaper())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct SettingsPreviewWallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 60.0 / 255.0, green: 35.0 / 255.0, blue: 68.0 / 255.0),
                    Color(red: 95.0 / 255.0, green: 46.0 / 255.0, blue: 88.0 / 255.0),
                    Color(red: 168.0 / 255.0, green: 81.0 / 255.0, blue: 122.0 / 255.0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    Color.black.opacity(0.10),
                    Color.black.opacity(0.26),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

/// Equal when the value inputs are, so an unrelated change on the tab does not
/// re-diff the panel. `lang` is for translating; the language itself is what
/// takes part in equality (the section titles already carry the strings).
struct SessionListPanelPreview: View, Equatable {
    let sections: [AppearanceSessionPreviewSection]
    let showsSections: Bool
    let indicator: IslandSessionStateIndicator
    let profile: IslandAppearanceDisplayProfile
    /// The display's opened look: how wide the panel is drawn and what its
    /// corners look like.
    let look: IslandOpenedLook
    let lang: LanguageManager
    /// The now-playing row under the list, with a sample track.
    let showsNowPlayingRow: Bool
    private let languageCode: String

    init(
        sections: [AppearanceSessionPreviewSection],
        showsSections: Bool,
        indicator: IslandSessionStateIndicator,
        profile: IslandAppearanceDisplayProfile,
        look: IslandOpenedLook = .standard,
        lang: LanguageManager,
        showsNowPlayingRow: Bool = false
    ) {
        self.sections = sections
        self.showsSections = showsSections
        self.indicator = indicator
        self.profile = profile
        self.look = look
        self.lang = lang
        self.showsNowPlayingRow = showsNowPlayingRow
        self.languageCode = lang.language.resolvedCode
    }

    nonisolated static func == (lhs: SessionListPanelPreview, rhs: SessionListPanelPreview) -> Bool {
        lhs.sections == rhs.sections
            && lhs.showsSections == rhs.showsSections
            && lhs.indicator == rhs.indicator
            && lhs.profile == rhs.profile
            && lhs.look == rhs.look
            && lhs.showsNowPlayingRow == rhs.showsNowPlayingRow
            && lhs.languageCode == rhs.languageCode
    }

    private var items: [AppearanceSessionPreviewItem] {
        sections.flatMap(\.items)
    }

    private var waitingCount: Int {
        items.filter { $0.phase == .approval || $0.phase == .answer }.count
    }

    private var runningCount: Int {
        items.filter { $0.phase == .running }.count
    }

    private var doneCount: Int {
        items.filter { $0.phase == .done }.count
    }

    private var idleCount: Int {
        items.filter { $0.phase == .idle }.count
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Self.panelWidths(for: metrics.panelWidth), id: \.self) { width in
                panel(width: width)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var metrics: IslandOpenedMetrics {
        IslandOpenedMetrics.resolve(look: look, profile: profile)
    }

    /// The widths the preview tries, widest first: the look's own, then
    /// narrower ones for a settings window that has no room for it. The
    /// standard look tries what it always has.
    nonisolated static func panelWidths(for preferred: CGFloat) -> [CGFloat] {
        let narrower: [CGFloat] = preferred > 540 ? [700, 640, 600, 540, 500, 460] : [500, 460]
        return [preferred] + narrower.filter { $0 < preferred }
    }

    private func panel(width: CGFloat) -> some View {
        ZStack(alignment: .top) {
            surfaceShape
                .fill(V6Palette.ink)
                .shadow(color: .black.opacity(0.36), radius: 22, y: 12)

            VStack(spacing: 0) {
                panelHead
                listBody
                if showsNowPlayingRow {
                    NookSampleCompactBar()
                        .padding(.horizontal, sideInset)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
                panelFoot
            }
            .clipShape(surfaceShape)
        }
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var surfaceShape: OpenedIslandSurfaceShape {
        OpenedIslandSurfaceShape(
            topProfile: profile == .notch ? .notch : .topBar,
            topCornerRadius: metrics.topRadius,
            bottomCornerRadius: metrics.bottomRadius
        )
    }

    private var sideInset: CGFloat {
        metrics.sideInset
    }

    private var panelHead: some View {
        HStack(spacing: 8) {
            UnifiedBars(mode: .waiting, size: 22)
                .frame(width: 24, height: 24)

            Text(lang.t("island.sessionList.title").uppercased())
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(V6Palette.paper.opacity(0.55))

            ViewThatFits(in: .horizontal) {
                previewSessionOverview(compact: false)
                previewSessionOverview(compact: true)
            }

            Spacer(minLength: 0)

            previewHeaderButton(systemName: "gearshape.fill")
        }
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .frame(height: 42)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.05))
                .frame(height: 1)
        }
    }

    private func previewHeaderButton(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.62))
            .frame(width: 22, height: 22)
            .background(.white.opacity(0.08), in: Circle())
    }

    private func previewSessionOverview(compact: Bool) -> some View {
        HStack(spacing: compact ? 7 : 9) {
            previewSessionOverviewMetric(
                count: items.count,
                title: lang.t("island.sessionOverview.total"),
                compactTitle: "",
                tint: nil,
                compact: compact
            )
            if waitingCount > 0 {
                previewSessionOverviewMetric(
                    count: waitingCount,
                    title: lang.t("island.sessionOverview.waiting"),
                    compactTitle: lang.t("island.sessionOverview.waitingCompact"),
                    tint: IslandDesignPalette.Status.waitingAggregate,
                    compact: compact
                )
            }
            if runningCount > 0 {
                previewSessionOverviewMetric(
                    count: runningCount,
                    title: lang.t("island.sessionOverview.running"),
                    compactTitle: lang.t("island.sessionOverview.runningCompact"),
                    tint: IslandDesignPalette.Status.running,
                    compact: compact
                )
            }
            if doneCount > 0 {
                previewSessionOverviewMetric(
                    count: doneCount,
                    title: lang.t("island.sessionOverview.done"),
                    compactTitle: lang.t("island.sessionOverview.done"),
                    tint: IslandDesignPalette.Status.completed,
                    compact: compact
                )
            }
            if idleCount > 0 {
                previewSessionOverviewMetric(
                    count: idleCount,
                    title: lang.t("island.sessionOverview.idle"),
                    compactTitle: lang.t("island.sessionOverview.idle"),
                    tint: IslandDesignPalette.Status.idle,
                    compact: compact
                )
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func previewSessionOverviewMetric(
        count: Int,
        title: String,
        compactTitle: String,
        tint: Color?,
        compact: Bool
    ) -> some View {
        HStack(spacing: 4) {
            if let tint {
                Circle()
                    .fill(tint)
                    .frame(width: 5.5, height: 5.5)
            }

            let label = title == "total"
                ? (compact ? "\(count)" : "\(count) \(title)")
                : "\(count) \(compact ? compactTitle : title)"

            Text(label)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint == nil ? V6Palette.paper.opacity(0.34) : V6Palette.paper.opacity(0.48))
        }
    }

    private var listBody: some View {
        VStack(spacing: 0) {
            ForEach(sections) { section in
                if showsSections {
                    sectionHeader(section)
                }

                ForEach(section.items) { item in
                    SessionListLivePreviewRow(
                        item: item,
                        indicator: indicator,
                        sideInset: sideInset,
                        lang: lang
                    )
                }
            }
        }
    }

    private func sectionHeader(_ section: AppearanceSessionPreviewSection) -> some View {
        HStack(spacing: 8) {
            sectionDot(for: section)
            Text(section.title.uppercased())
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(V6Palette.paper.opacity(0.7))
            Text("\(section.items.count)")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(V6Palette.paper.opacity(0.4))
            Spacer(minLength: 0)
        }
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .padding(.top, 9)
        .padding(.bottom, 6)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.05))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func sectionDot(for section: AppearanceSessionPreviewSection) -> some View {
        Circle()
            .fill(section.items.first?.phase.tint ?? V6Palette.paper.opacity(0.35))
            .frame(width: 7, height: 7)
    }

    private var panelFoot: some View {
        Color.clear
            .frame(height: 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.05))
                .frame(height: 1)
        }
    }
}

private struct SessionListLivePreviewRow: View {
    let item: AppearanceSessionPreviewItem
    let indicator: IslandSessionStateIndicator
    let sideInset: CGFloat
    let lang: LanguageManager

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                if indicator != .tint {
                    indicatorView
                }

                VStack(alignment: .leading, spacing: 3) {
                    titleLine

                    if let prompt = item.prompt {
                        Text(prompt)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(V6Palette.paper.opacity(item.phase == .idle ? 0.34 : 0.52))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 10)

                HStack(spacing: 6) {
                    agentChip
                    sideBadge(item.terminal)
                    Text(item.age)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(V6Palette.paper.opacity(item.phase == .idle ? 0.32 : 0.45))
                        .frame(minWidth: 30, alignment: .trailing)

                    Image(systemName: item.phase == .idle ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(V6Palette.paper.opacity(item.phase == .idle ? 0.42 : 0.68))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(.white.opacity(item.phase == .idle ? 0.02 : 0.045))
                        )
                }
            }
            .padding(.horizontal, rowLeadingPadding)
            .padding(.vertical, 11)
            .background(rowFill)

            if item.phase != .idle {
                detailPreview
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.04))
                .frame(height: 1)
        }
        .overlay(alignment: .leading) {
            if indicator == .bar {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(tint)
                    .frame(width: 3)
                    .padding(.vertical, 8)
                    .padding(.leading, 14)
            }
        }
        .opacity(item.phase == .idle ? 0.74 : 1)
    }

    private var titleLine: some View {
        HStack(spacing: 0) {
            Text(item.project)
                .fontWeight(.semibold)
                .foregroundStyle(projectColor)
            if let branch = item.branch {
                Text(" (\(branch))")
                    .foregroundStyle(V6Palette.paper.opacity(0.55))
            }
            Text(" · ")
                .foregroundStyle(V6Palette.paper.opacity(0.22))
            Text(item.detail)
                .foregroundStyle(V6Palette.paper.opacity(0.7))
        }
        .font(.system(size: 13, weight: .medium))
        .lineLimit(1)
    }

    private var agentChip: some View {
        Text(item.agentShort)
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(item.agentColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(item.agentColor.opacity(0.13), in: Capsule())
            .overlay(Capsule().stroke(item.agentColor.opacity(0.35), lineWidth: 1))
    }

    private func sideBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundStyle(V6Palette.paper.opacity(0.7))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.white.opacity(0.06), in: Capsule())
    }

    private var detailPreview: some View {
        VStack(alignment: .leading, spacing: 7) {
            switch item.phase {
            case .approval:
                Text(lang.t("approval.toolPermissionRequested"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.86))
                Text(lang.t("settings.appearance.preview.permissionBody"))
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(V6Palette.paper.opacity(0.78))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            case .answer:
                Text(lang.t("settings.appearance.preview.pickOrTypeAnswer"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.82))
            case .running:
                Text(item.detail)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(V6Palette.paper.opacity(0.78))
            case .done:
                Text(lang.t("settings.appearance.preview.replyAvailable"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.82))
            case .idle:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, detailLeadingPadding)
        .padding(.trailing, sideInset)
        .padding(.bottom, 12)
        .background(.white.opacity(0.015))
    }

    @ViewBuilder
    private var indicatorView: some View {
        switch indicator {
        case .animatedDot:
            Circle()
                .fill(tint)
                .frame(width: 9, height: 9)
                .shadow(color: tint.opacity(item.phase == .idle ? 0 : 0.44), radius: 5)
                .frame(width: 20, height: 20)
        case .bar:
            EmptyView()
        case .glyph:
            glyphView
                .frame(width: 20, height: 20)
        case .tint:
            EmptyView()
        }
    }

    private var rowFill: Color {
        guard indicator == .tint else { return Color.clear }
        return tint.opacity(item.phase == .idle ? 0.015 : 0.045)
    }

    @ViewBuilder
    private var glyphView: some View {
        switch item.phase {
        case .idle:
            Circle()
                .fill(V6Palette.paper.opacity(0.3))
                .frame(width: 4, height: 4)
        case .running:
            UnifiedBars(mode: .running, size: 16, tint: tint)
        case .approval, .answer:
            UnifiedBars(mode: .waiting, size: 16, tint: tint)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    private var projectColor: Color {
        indicator == .tint && item.phase != .idle ? tint : V6Palette.paper.opacity(item.phase == .idle ? 0.72 : 0.92)
    }

    private var tint: Color {
        item.phase.tint
    }

    private var rowLeadingPadding: CGFloat {
        switch indicator {
        case .bar: max(28, sideInset)
        case .tint: sideInset
        case .animatedDot, .glyph: sideInset
        }
    }

    private var detailLeadingPadding: CGFloat {
        switch indicator {
        case .bar: max(28, sideInset)
        case .tint: sideInset
        case .animatedDot, .glyph: sideInset + 30
        }
    }
}

private extension AppearanceSessionPreviewItem.Phase {
    var tint: Color {
        switch self {
        case .approval:
            IslandDesignPalette.Status.waitingForApproval
        case .answer:
            IslandDesignPalette.Status.waitingForAnswer
        case .running:
            IslandDesignPalette.Status.running
        case .done:
            IslandDesignPalette.Status.completed
        case .idle:
            IslandDesignPalette.Status.idle
        }
    }
}

private struct CountBadgePreview: View {
    let count: Int
    var body: some View {
        Text("×\(count)")
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(V6Palette.paper.opacity(0.72))
    }
}

private struct AgentsMiniGridPreview: View {
    var body: some View {
        let claude = Color(hex: AgentTool.claudeCode.brandColorHex) ?? .white
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(claude)
                    .frame(width: 8, height: 8)
            }
        }
    }
}

private struct StateIndicatorPreview: View {
    let option: IslandSessionStateIndicator

    var body: some View {
        HStack(spacing: 8) {
            indicator
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(V6Palette.paper.opacity(option == .tint ? 0.55 : 0.22))
                .frame(width: 58, height: 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(option == .tint ? Color(hex: AgentTool.codex.brandColorHex)?.opacity(0.22) ?? Color.white.opacity(0.08) : Color.clear)
        )
    }

    @ViewBuilder
    private var indicator: some View {
        let color = Color(hex: AgentTool.codex.brandColorHex) ?? V6Palette.paper
        switch option {
        case .animatedDot:
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .shadow(color: color.opacity(0.55), radius: 5)
        case .bar:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 4, height: 28)
        case .glyph:
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
        case .tint:
            Circle()
                .fill(V6Palette.paper.opacity(0.72))
                .frame(width: 10, height: 10)
        }
    }
}

private struct UsageDisplayPreview: View {
    let option: IslandUsageDisplay

    var body: some View {
        HStack(spacing: 6) {
            if option == .compact {
                usageChip("Cl", window: "5h", value: 42, color: Color(hex: AgentTool.claudeCode.brandColorHex) ?? .orange)
                usageChip("Cx", window: "7d", value: 13, color: Color(hex: AgentTool.codex.brandColorHex) ?? .blue)
            } else {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(V6Palette.paper.opacity(0.18))
                    .frame(width: 72, height: 5)
            }
        }
        .frame(width: 104, alignment: .center)
    }

    private func usageChip(_ title: String, window: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(V6Palette.paper.opacity(0.66))
            Text(window)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(V6Palette.paper.opacity(0.42))
            Text("\(value)%")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.white.opacity(0.055), in: Capsule())
    }
}

private struct SessionGroupPreview: View {
    let option: IslandSessionGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch option {
            case .none:
                previewLine(width: 72, color: V6Palette.paper.opacity(0.42))
                previewLine(width: 54, color: V6Palette.paper.opacity(0.28))
                previewLine(width: 64, color: V6Palette.paper.opacity(0.22))
            case .state:
                groupBlock(width: 52)
                groupBlock(width: 70)
            case .agent:
                agentBlock(color: Color(hex: AgentTool.claudeCode.brandColorHex) ?? .white)
                agentBlock(color: Color(hex: AgentTool.codex.brandColorHex) ?? .white)
            case .project:
                groupBlock(width: 76)
                groupBlock(width: 46)
            }
        }
        .frame(width: 84, alignment: .leading)
    }

    private func previewLine(width: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: width, height: 5)
    }

    private func groupBlock(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            previewLine(width: width * 0.48, color: V6Palette.paper.opacity(0.48))
            previewLine(width: width, color: V6Palette.paper.opacity(0.22))
        }
    }

    private func agentBlock(color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            previewLine(width: 54, color: V6Palette.paper.opacity(0.25))
        }
    }
}

private struct SessionSortPreview: View {
    let option: IslandSessionSort

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    Text(rows[index].rank)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(V6Palette.paper.opacity(0.55))
                        .frame(width: 12, alignment: .leading)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(rows[index].color)
                        .frame(width: rows[index].width, height: 5)
                }
            }
        }
        .frame(width: 82, alignment: .leading)
    }

    private var rows: [(rank: String, width: CGFloat, color: Color)] {
        switch option {
        case .attention:
            return [
                ("!", 62, Color(hex: AgentTool.claudeCode.brandColorHex) ?? .white),
                ("2", 48, V6Palette.paper.opacity(0.28)),
                ("3", 58, V6Palette.paper.opacity(0.2)),
            ]
        case .lastUpdate:
            return [
                ("1", 64, V6Palette.paper.opacity(0.38)),
                ("2", 56, V6Palette.paper.opacity(0.3)),
                ("3", 42, V6Palette.paper.opacity(0.22)),
            ]
        }
    }
}
