import SwiftUI

/// The Nook's part of the Personalization tab. Like the rest of that tab,
/// every choice here is stored per display profile: one set for the MacBook
/// notch, one for external displays.
///
/// Each choice is its own small child view (`NookSliceReader`) that reads only
/// the part of the preferences it shows. The pane's own body reads none of
/// them, which means one tap re-renders the control that changed and not the
/// whole pane. Every write goes through `Motion.selection`.
extension AppearanceSettingsPane {
    private func updateNook(_ update: (inout NookDisplayPreferences) -> Void) {
        withMotion(Motion.selection) {
            model.nook.updateDisplayPreferences(for: editingProfile, update)
        }
    }

    // MARK: - 03 · Left slot (closed island)

    @ViewBuilder
    var nookLeftSlotSection: some View {
        PersonalizationSectionHeader(
            title: lang.t("settings.appearance.nook.leftSlot.title"),
            note: lang.t(
                showsAgents
                    ? "settings.appearance.nook.leftSlot.note"
                    : "settings.appearance.nook.leftSlot.note.nookOnly"
            )
        )

        if showsAgents {
            nookSideSlotRow([.agents, .count, .grid, .none], group: "nook.leftSlot.first", current: { $0.leftSlot }) { slot in
                updateNook { $0.leftSlot = slot }
            }
            nookSideSlotRow([.date, .battery, .countdown], group: "nook.leftSlot.second", current: { $0.leftSlot }) { slot in
                updateNook { $0.leftSlot = slot }
            }
            nookSideSlotRow(Self.newSideSlots, group: "nook.leftSlot.third", current: { $0.leftSlot }) { slot in
                updateNook { $0.leftSlot = slot }
            }
        } else {
            ForEach(Array(Self.sideSlotRowsWithoutAgents.enumerated()), id: \.offset) { index, row in
                nookSideSlotRow(row, group: "nook.leftSlot.nookOnly\(index)", current: { $0.leftSlot }) { slot in
                    updateNook { preferences in
                        // A saved choice that shows agents already reads as
                        // None. Picking None must not throw it away.
                        guard slot != .none || !preferences.leftSlot.needsAgents else { return }
                        preferences.leftSlot = slot
                    }
                }
            }
        }
    }

    /// The cards one side offers while the agents are switched off (D41):
    /// nothing, or one of the six items that are the Nook's.
    static let sideSlotsWithoutAgents: [NookSideSlot] = sideSlotRowsWithoutAgents.flatMap { $0 }

    /// Weather, the timer and the to-dos: the Nook's items that need no
    /// agents and no calendar, on a row of their own on both sides.
    static let newSideSlots: [NookSideSlot] = [.weather, .timer, .todos]

    /// The same cards as `sideSlotsWithoutAgents`, as the rows Settings draws.
    static let sideSlotRowsWithoutAgents: [[NookSideSlot]] = [[.none, .date, .battery, .countdown], newSideSlots]

    /// The right side while the agents are switched off, as one row. None
    /// takes a Nook item off the side and leaves the island's own saved
    /// slot alone, which brings that slot back with the switch.
    @ViewBuilder
    var nookRightSlotWithoutAgents: some View {
        PersonalizationSectionHeader(
            title: lang.t("settings.appearance.rightSlot.title"),
            note: lang.t("settings.appearance.rightSlot.note")
        )

        ForEach(Array(Self.sideSlotRowsWithoutAgents.enumerated()), id: \.offset) { index, row in
            nookSideSlotRow(
                row,
                group: "nook.rightSlot.nookOnly\(index)",
                current: { $0.rightSlot ?? NookSideSlot.none }
            ) { slot in
                if slot == .none {
                    updateNook { preferences in
                        if preferences.rightSlot?.needsAgents == false { preferences.rightSlot = nil }
                    }
                } else {
                    withMotion(Motion.selection) {
                        model.chooseRightSide(.extra(slot), for: editingProfile)
                    }
                }
            }
        }
    }

    /// The right slot's extra choices, under the island's own three. A pick
    /// in either row takes the whole right side (`IslandRightSideChoice`).
    @ViewBuilder
    var nookRightSlotExtras: some View {
        nookSideSlotRow([.agents, .date, .battery, .countdown], group: "nook.rightSlot.extras", current: { $0.rightSlot }) { slot in
            withMotion(Motion.selection) {
                model.chooseRightSide(.extra(slot), for: editingProfile)
            }
        }
        nookSideSlotRow(Self.newSideSlots, group: "nook.rightSlot.third", current: { $0.rightSlot }) { slot in
            withMotion(Motion.selection) {
                model.chooseRightSide(.extra(slot), for: editingProfile)
            }
        }
    }

    /// A row of side-slot cards. The row reads the current slot only while it
    /// is one of this row's own, so choosing a card in one row leaves the
    /// other row alone. With the agents switched off the row leaves out the
    /// cards that show agents, and a saved one of those reads as None.
    private func nookSideSlotRow(
        _ allSlots: [NookSideSlot],
        group: String,
        current: @escaping (NookDisplayPreferences) -> NookSideSlot?,
        pick: @escaping (NookSideSlot) -> Void
    ) -> some View {
        let showsAgents = showsAgents
        let slots = AgentsSwitch.offered(allSlots, agentsEnabled: showsAgents)
        return NookSliceReader(
            nook: model.nook,
            profile: editingProfile,
            showsAgents: showsAgents,
            select: { preferences in
                current(preferences)
                    .map { AgentsSwitch.shown($0, agentsEnabled: showsAgents) }
                    .flatMap { slots.contains($0) ? $0 : nil }
            }
        ) { selected in
            NookCardRow(
                options: slots,
                selected: selected,
                ringGroup: group,
                title: { nookTitle(for: $0) },
                pick: pick
            ) { slot in
                if slot == .none {
                    Text("—")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(V6Palette.paper.opacity(0.5))
                } else if let sample = Self.sampleSideSlot(slot) {
                    NookSideSlotView(content: sample, size: 24)
                }
            }
        }
    }

    // MARK: - 04 · While music plays (closed island)

    @ViewBuilder
    var nookClosedSection: some View {
        PersonalizationSectionHeader(
            title: lang.t("settings.appearance.nook.closed.title"),
            note: lang.t("settings.appearance.nook.closed.note")
        )

        let showsAgents = showsAgents
        NookSliceReader(
            nook: model.nook,
            profile: editingProfile,
            showsAgents: showsAgents,
            select: \.mediaStyle
        ) { selected in
            NookCardRow(
                options: NookClosedMediaStyle.allCases,
                selected: selected,
                ringGroup: "nook.media",
                title: { nookTitle(for: $0) },
                pick: { style in updateNook { $0.mediaStyle = style } }
            ) { style in
                NookMediaStylePreview(style: style, showsAgents: showsAgents)
            }
        }

        // The switches are `NookClosedMusicOption`'s, which the welcome tour
        // offers too. Two say what an agent does to the music, two belong to
        // external displays.
        VStack(spacing: 8) {
            ForEach(NookClosedMusicOption.offered(agentsEnabled: showsAgents, profile: editingProfile)) { option in
                nookToggleRow(
                    titleKey: option.titleKey,
                    noteKey: option.noteKey(agentsEnabled: showsAgents),
                    option.keyPath,
                    enabledWhen: { option.isEnabled(whenStyle: $0.mediaStyle) }
                )
            }
        }
    }

    // MARK: - 05 · Status glow (closed island)

    @ViewBuilder
    var nookHaloSection: some View {
        let showsAgents = showsAgents
        PersonalizationSectionHeader(
            title: lang.t("settings.appearance.nook.halo.title"),
            note: lang.t(
                showsAgents
                    ? "settings.appearance.nook.halo.note"
                    : "settings.appearance.nook.halo.note.nookOnly"
            )
        )

        NookSliceReader(
            nook: model.nook,
            profile: editingProfile,
            showsAgents: showsAgents,
            select: {
                // The sample glows as a waiting agent does, or as a notice
                // does while the agents are switched off.
                let palette = $0.haloColors.effectivePalette
                return NookHaloStyleChoice(
                    style: $0.haloStyle,
                    color: showsAgents ? palette.approval : palette.noticeColor(own: IslandHaloPalette.suggestedNotice)
                )
            }
        ) { choice in
            NookCardRow(
                options: IslandHaloStyle.allCases,
                selected: choice.style,
                ringGroup: "nook.halo",
                title: { nookTitle(for: $0) },
                pick: { style in updateNook { $0.haloStyle = style } }
            ) { style in
                NookHaloStylePreview(style: style, color: choice.color)
            }
        }

        GlowColorsSection(nook: model.nook, profile: editingProfile, showsAgents: showsAgents)

        VStack(alignment: .leading, spacing: 8) {
            nookToggleRow(
                titleKey: "settings.appearance.nook.halo.music.title",
                noteKey: "settings.appearance.nook.halo.music.note",
                \.haloFollowsMusic,
                enabledWhen: { $0.haloStyle != .off && $0.mediaStyle != .off }
            )
            if SystemMotionMonitor.shared.reduceMotion {
                Text(lang.t("settings.appearance.nook.halo.reducedMotion"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Opened island look

    /// How wide the opened island is and what its corners look like (D35).
    /// Each card draws the island's own shape with the numbers the choice
    /// would give this display.
    @ViewBuilder
    var nookOpenedLookSection: some View {
        PersonalizationSectionHeader(
            title: lang.t("settings.appearance.openedLook.title"),
            note: lang.t("settings.appearance.openedLook.note")
        )

        NookSliceReader(nook: model.nook, profile: editingProfile, select: \.openedLook) { look in
            VStack(alignment: .leading, spacing: 12) {
                NookCardRow(
                    options: IslandOpenedWidth.allCases,
                    selected: look.width,
                    ringGroup: "nook.openedLook.width",
                    title: { lang.t("settings.appearance.openedLook.width.\($0.rawValue)") },
                    pick: { width in updateNook { $0.openedLook.width = width } }
                ) { width in
                    OpenedLookArt(
                        look: IslandOpenedLook(width: width, corners: look.corners),
                        profile: editingProfile
                    )
                }
                NookCardRow(
                    options: IslandOpenedCorners.allCases,
                    selected: look.corners,
                    ringGroup: "nook.openedLook.corners",
                    title: { lang.t("settings.appearance.openedLook.corners.\($0.rawValue)") },
                    pick: { corners in updateNook { $0.openedLook.corners = corners } }
                ) { corners in
                    OpenedLookArt(
                        look: IslandOpenedLook(width: look.width, corners: corners),
                        profile: editingProfile
                    )
                }
            }
        }
    }

    // MARK: - 07 · Nook and agents (opened island)

    @ViewBuilder
    var nookOpenedSection: some View {
        // Which page opens first and the rows that link the two pages.
        // With the agents switched off the Nook is the only page.
        if showsAgents {
            PersonalizationSectionHeader(
                title: lang.t("settings.appearance.nook.opened.title"),
                note: lang.t("settings.appearance.nook.opened.note")
            )

            NookSliceReader(nook: model.nook, profile: editingProfile, select: \.openedPage) { selected in
                NookCardRow(
                    options: NookOpenedPage.allCases,
                    selected: selected,
                    ringGroup: "nook.openedPage",
                    title: { nookTitle(for: $0) },
                    pick: { page in updateNook { $0.openedPage = page } }
                ) { page in
                    Image(systemName: Self.nookSymbol(for: page))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(V6Palette.paper.opacity(0.85))
                }
            }

            VStack(spacing: 8) {
                nookToggleRow(
                    titleKey: "settings.appearance.nook.compactBar.title",
                    noteKey: "settings.appearance.nook.compactBar.note",
                    \.showsCompactBar
                )
                nookToggleRow(
                    titleKey: "settings.appearance.nook.agentsBar.title",
                    noteKey: "settings.appearance.nook.agentsBar.note",
                    \.showsAgentsBar
                )
            }
        }

        nookWidgetsSection
        nookCalendarStyleSection
        nookCalendarsSection
    }

    // MARK: - 09 · Calendar look

    @ViewBuilder
    private var nookCalendarStyleSection: some View {
        PersonalizationSectionHeader(
            title: lang.t("settings.appearance.nook.calendarStyle.title"),
            note: lang.t("settings.appearance.nook.calendarStyle.note")
        )

        NookSliceReader(nook: model.nook, profile: editingProfile, select: \.calendarStyle) { selected in
            NookCardRow(
                options: NookCalendarStyle.allCases,
                selected: selected,
                ringGroup: "nook.calendarStyle",
                title: { nookTitle(for: $0) },
                pick: { style in updateNook { $0.calendarStyle = style } }
            ) { style in
                Image(systemName: Self.nookSymbol(for: style))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(V6Palette.paper.opacity(0.85))
            }
        }
    }

    // MARK: - 10 · Calendars on this display

    @ViewBuilder
    private var nookCalendarsSection: some View {
        let nook = model.nook
        let profile = editingProfile
        let hasCalendars = !nook.calendar.calendars.isEmpty

        PersonalizationSectionHeader(
            title: lang.t("settings.appearance.nook.calendars.title"),
            note: hasCalendars
                ? lang.t("settings.appearance.nook.calendars.note")
                : lang.t("settings.appearance.nook.calendars.empty")
        )

        if hasCalendars {
            NookSliceReader(
                nook: nook,
                profile: profile,
                read: {
                    NookCalendarChoices(
                        calendars: nook.calendar.calendars,
                        hiddenIDs: nook.displayPreferences(for: profile).hiddenCalendarIDs
                    )
                }
            ) { choices in
                NookChipFlow(spacing: 8) {
                    ForEach(choices.calendars) { calendar in
                        MonoChip(
                            title: calendar.title,
                            selected: !choices.hiddenIDs.contains(calendar.id)
                        ) {
                            updateNook { preferences in
                                if preferences.hiddenCalendarIDs.contains(calendar.id) {
                                    preferences.hiddenCalendarIDs.remove(calendar.id)
                                } else {
                                    preferences.hiddenCalendarIDs.insert(calendar.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 08 · Widgets on this display

    @ViewBuilder
    private var nookWidgetsSection: some View {
        let nook = model.nook
        let profile = editingProfile

        PersonalizationSectionHeader(
            title: lang.t("settings.appearance.nook.widgets.title"),
            note: lang.t("settings.appearance.nook.widgets.note")
        )

        NookSliceReader(
            nook: nook,
            profile: profile,
            select: { NookEditorChoices(calendarStyle: $0.calendarStyle, look: $0.openedLook) }
        ) { choices in
            NookLayoutEditor(
                nook: nook,
                profile: profile,
                look: choices.look,
                calendarStyle: choices.calendarStyle,
                addTitle: lang.t("settings.appearance.nook.widgets.add"),
                allShownTitle: lang.t("settings.appearance.nook.widgets.allShown"),
                emptyTitle: lang.t("settings.appearance.nook.widgets.empty"),
                resetTitle: lang.t("settings.appearance.nook.widgets.reset")
            )
        }
    }

    // MARK: - Switch rows

    /// A switch for one Boolean preference. `enabledWhen` dims and disables it
    /// from other preferences; the row re-renders only when its own value or
    /// that state changes. Titles come from the keys inside the row, which is
    /// what lets a language change reach it.
    private func nookToggleRow(
        titleKey: String,
        noteKey: String,
        _ keyPath: WritableKeyPath<NookDisplayPreferences, Bool>,
        enabledWhen isEnabled: @escaping (NookDisplayPreferences) -> Bool = { _ in true }
    ) -> some View {
        NookSliceReader(
            nook: model.nook,
            profile: editingProfile,
            showsAgents: showsAgents,
            select: { NookSwitchState(isOn: $0[keyPath: keyPath], isEnabled: isEnabled($0)) }
        ) { state in
            PersonalizationToggleRow(
                title: lang.t(titleKey),
                note: lang.t(noteKey),
                isOn: Binding(
                    get: { state.isOn },
                    set: { value in updateNook { $0[keyPath: keyPath] = value } }
                ),
                isEnabled: state.isEnabled
            )
        }
    }

    // MARK: - Titles

    private func nookTitle(for style: NookClosedMediaStyle) -> String {
        switch style {
        case .artAndVisual: lang.t("settings.appearance.nook.media.artAndVisual")
        case .artOnly:      lang.t("settings.appearance.nook.media.artOnly")
        case .off:          lang.t("settings.appearance.nook.media.off")
        }
    }

    private func nookTitle(for style: IslandHaloStyle) -> String {
        switch style {
        case .off:    lang.t("settings.appearance.nook.halo.off")
        case .subtle: lang.t("settings.appearance.nook.halo.subtle")
        case .vivid:  lang.t("settings.appearance.nook.halo.vivid")
        }
    }

    private func nookTitle(for slot: NookSideSlot) -> String {
        switch slot {
        case .agents:    lang.t("settings.appearance.nook.leftSlot.agents")
        case .count:     lang.t("settings.appearance.nook.leftSlot.count")
        case .grid:      lang.t("settings.appearance.nook.leftSlot.grid")
        case .date:      lang.t("settings.appearance.nook.leftSlot.date")
        case .battery:   lang.t("settings.appearance.nook.leftSlot.battery")
        case .countdown: lang.t("settings.appearance.nook.leftSlot.countdown")
        case .weather:   lang.t("settings.appearance.nook.leftSlot.weather")
        case .timer:     lang.t("settings.appearance.nook.leftSlot.timer")
        case .todos:     lang.t("settings.appearance.nook.leftSlot.todos")
        case .none:      lang.t("settings.appearance.nook.leftSlot.none")
        }
    }

    private func nookTitle(for style: NookCalendarStyle) -> String {
        switch style {
        case .strip:    lang.t("settings.appearance.nook.calendarStyle.strip")
        case .agenda:   lang.t("settings.appearance.nook.calendarStyle.agenda")
        case .timeline: lang.t("settings.appearance.nook.calendarStyle.timeline")
        case .hero:     lang.t("settings.appearance.nook.calendarStyle.hero")
        case .month:    lang.t("settings.appearance.nook.calendarStyle.month")
        }
    }

    private static func nookSymbol(for style: NookCalendarStyle) -> String {
        switch style {
        case .strip:    "calendar.day.timeline.left"
        case .agenda:   "list.bullet"
        case .timeline: "chart.bar.xaxis"
        case .hero:     "clock.badge"
        case .month:    "calendar"
        }
    }

    private func nookTitle(for page: NookOpenedPage) -> String {
        switch page {
        case .auto:   lang.t("settings.appearance.nook.page.auto")
        case .agents: lang.t("settings.appearance.nook.page.agents")
        case .nook:   lang.t("settings.appearance.nook.page.nook")
        }
    }

    private static func nookSymbol(for page: NookOpenedPage) -> String {
        switch page {
        case .auto:   "arrow.triangle.branch"
        case .agents: "terminal.fill"
        case .nook:   "music.note.house.fill"
        }
    }
}

// MARK: - Pieces

/// The glow style and the color its cards draw their sample in.
private struct NookHaloStyleChoice: Equatable, Sendable {
    var style: IslandHaloStyle
    var color: IslandHaloRGB
}

/// A switch's value and whether other preferences leave it usable.
private struct NookSwitchState: Equatable, Sendable {
    var isOn: Bool
    var isEnabled: Bool
}

/// What sets the layout editor's page: the calendar look and the opened
/// island's width.
private struct NookEditorChoices: Equatable, Sendable {
    var calendarStyle: NookCalendarStyle
    var look: IslandOpenedLook
}

/// The calendars on offer and the ones this display hides.
private struct NookCalendarChoices: Equatable, Sendable {
    var calendars: [NookCalendarInfo]
    var hiddenIDs: Set<String>
}

/// Reads one slice of the edited display's Nook preferences and hands it to
/// `content`. The read happens here, in a body of its own, and the content
/// sits behind `NookSliceHost`, which skips its body while the slice is
/// unchanged. A tap on one card therefore re-renders that card row and
/// nothing else.
///
/// `content` must compute everything from the slice and from state it reads
/// itself (such as `lang`). Anything else it captures is frozen while the
/// slice stays equal.
private struct NookSliceReader<Slice: Equatable & Sendable, Content: View>: View {
    let nook: NookModel
    let profile: IslandAppearanceDisplayProfile
    /// The agents switch, for content that draws differently with it off.
    /// It is part of what makes two hosts equal, which is what lets such
    /// content redraw when only the switch changed.
    let showsAgents: Bool
    private let read: () -> Slice
    private let content: (Slice) -> Content

    init(
        nook: NookModel,
        profile: IslandAppearanceDisplayProfile,
        showsAgents: Bool = true,
        select: @escaping (NookDisplayPreferences) -> Slice,
        @ViewBuilder content: @escaping (Slice) -> Content
    ) {
        self.nook = nook
        self.profile = profile
        self.showsAgents = showsAgents
        self.read = { select(nook.displayPreferences(for: profile)) }
        self.content = content
    }

    init(
        nook: NookModel,
        profile: IslandAppearanceDisplayProfile,
        read: @escaping () -> Slice,
        @ViewBuilder content: @escaping (Slice) -> Content
    ) {
        self.nook = nook
        self.profile = profile
        self.showsAgents = true
        self.read = read
        self.content = content
    }

    var body: some View {
        NookSliceHost(nook: nook, profile: profile, showsAgents: showsAgents, slice: read(), content: content)
            .equatable()
    }
}

private struct NookSliceHost<Slice: Equatable & Sendable, Content: View>: View, Equatable {
    let nook: NookModel
    let profile: IslandAppearanceDisplayProfile
    let showsAgents: Bool
    let slice: Slice
    let content: (Slice) -> Content

    nonisolated static func == (lhs: NookSliceHost, rhs: NookSliceHost) -> Bool {
        lhs.nook === rhs.nook && lhs.profile == rhs.profile
            && lhs.showsAgents == rhs.showsAgents && lhs.slice == rhs.slice
    }

    var body: some View {
        content(slice)
    }
}

/// A row of selectable cards that shares one selection ring. Each row owns
/// its namespace and ring group, so the ring slides between the cards of this
/// row and never jumps to another row.
private struct NookCardRow<Value: Hashable, Icon: View>: View {
    let options: [Value]
    let selected: Value?
    let ringGroup: String
    let title: (Value) -> String
    let pick: (Value) -> Void
    private let icon: (Value) -> Icon

    @Namespace private var ring

    init(
        options: [Value],
        selected: Value?,
        ringGroup: String,
        title: @escaping (Value) -> String,
        pick: @escaping (Value) -> Void,
        @ViewBuilder icon: @escaping (Value) -> Icon
    ) {
        self.options = options
        self.selected = selected
        self.ringGroup = ringGroup
        self.title = title
        self.pick = pick
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(options, id: \.self) { option in
                PersonalizationCard(
                    title: title(option),
                    selected: selected == option,
                    ringNamespace: ring,
                    ringGroup: ringGroup,
                    action: { pick(option) }
                ) {
                    icon(option)
                }
            }
        }
    }
}

/// A closed-island pill with the glow one style gives an agent that waits for
/// approval, held still. Off shows the pill alone. The halo insets its glow by
/// `pillInset`, so the pill sits in a clear margin of that size: the glow then
/// follows the pill's own outline, which a pill this small would otherwise
/// shrink to a hairline. The tile clips the glow to its own box.
private struct NookHaloStylePreview: View {
    let style: IslandHaloStyle
    /// The display's approval color, which the sample glows in.
    let color: IslandHaloRGB

    private static let pillSize = CGSize(width: 64, height: 14)

    var body: some View {
        Capsule()
            .fill(Color.black)
            .frame(width: Self.pillSize.width, height: Self.pillSize.height)
            .padding(IslandHaloLayerView.pillInset)
            .islandHaloPreview(Self.state(for: style, color: color), cornerRadius: Self.pillSize.height / 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private static func state(for style: IslandHaloStyle, color: IslandHaloRGB) -> IslandHaloState {
        guard style != .off else { return .off }
        let metrics = IslandHaloMetrics.metrics(for: style)
        // The source only labels the sample. Its color is the one handed in.
        return IslandHaloState(
            source: .approval,
            color: color,
            motion: .steady,
            restOpacity: metrics.breathingHigh,
            radius: metrics.radius,
            drop: metrics.drop
        )
    }
}

/// Lays chips out left to right and wraps to a new line when a row fills.
private struct NookChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: .unspecified
                )
            }
        }
    }

    private struct Row {
        var y: CGFloat
        var height: CGFloat = 0
        var width: CGFloat = 0
        var items: [(index: Int, x: CGFloat)] = []
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row(y: 0)]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            let x = row.items.isEmpty ? 0 : row.width + spacing
            if !row.items.isEmpty, x + size.width > width {
                rows.append(Row(y: row.y + row.height + spacing))
                row = rows[rows.count - 1]
                row.items.append((index, 0))
                row.width = size.width
            } else {
                row.items.append((index, x))
                row.width = x + size.width
            }
            row.height = max(row.height, size.height)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// Miniature of the closed island's two sides for each music style.
private struct NookMediaStylePreview: View {
    let style: NookClosedMediaStyle
    /// False leaves the agent bars and the session count out of the sample.
    var showsAgents = true

    var body: some View {
        HStack(spacing: 22) {
            switch style {
            case .artAndVisual:
                artTile
                NookBarVisualizer(isPlaying: true, barCount: 4, height: 14, color: V6Palette.paper.opacity(0.85))
            case .artOnly:
                artTile
                if showsAgents { sessionCount }
            case .off:
                if showsAgents {
                    UnifiedBars(mode: .running, size: 20)
                    sessionCount
                } else {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(V6Palette.paper.opacity(0.5))
                }
            }
        }
    }

    private var sessionCount: some View {
        Text("×3")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(V6Palette.paper.opacity(0.72))
    }

    private var artTile: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.pink.opacity(0.85), Color.purple.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 20, height: 20)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
            )
    }
}
