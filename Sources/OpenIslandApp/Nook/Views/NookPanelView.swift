import SwiftUI

/// The Nook page of the opened island: a two column grid of widgets in the
/// order and sizes saved for this display (`AppModel.nookWidgetPlacements`).
/// Small widgets pair up side by side; medium and large span the page.
/// Heights come from each card so `OverlayPanelController` can size the
/// window before SwiftUI lays anything out. In edit mode (`NookModel.
/// isEditingLayout`) the grid takes drags and a shelf of addable widgets
/// appears under it.
struct NookPanelView: View {
    var model: AppModel

    static let verticalPadding: CGFloat = 8
    static let emptyHeight: CGFloat = 96
    /// Height edit mode adds under the grid for its shelf, counting the
    /// gap above it. With no widgets on the page the shelf keeps that gap
    /// as top padding. With widgets, the padding under the shelf comes on
    /// top of this (see `preferredHeight`).
    static let editingExtraHeight: CGFloat = NookWidgetLayout.rowSpacing + NookWidgetShelf.height

    /// Total content height for the window-sizing math. `extras` is what
    /// the page holds beyond its standard cards.
    static func preferredHeight(
        for placements: [NookWidgetPlacement],
        calendarStyle: NookCalendarStyle,
        isEditing: Bool,
        extras: NookPageExtras = .none
    ) -> CGFloat {
        let grid: CGFloat
        let shelf: CGFloat
        if placements.isEmpty {
            // The shelf stands in for the grid and sits between the two
            // `verticalPadding` terms.
            grid = isEditing ? 0 : emptyHeight
            shelf = isEditing ? editingExtraHeight : 0
        } else {
            grid = NookWidgetLayout.contentHeight(placements) {
                cardHeight($0, calendarStyle: calendarStyle, calendarExtraRows: extras.calendarExtraRows)
            }
            // The grid's own padding sits above the shelf, so the view
            // pads under the shelf by one more `verticalPadding`.
            shelf = isEditing ? editingExtraHeight + verticalPadding : 0
        }
        return verticalPadding * 2 + grid + shelf + extras.pinnedHeight
    }

    /// Each card owns its heights; this is the one place that maps kinds
    /// to cards.
    static func cardHeight(
        _ placement: NookWidgetPlacement,
        calendarStyle: NookCalendarStyle,
        calendarExtraRows: Int = 0
    ) -> CGFloat {
        let size = placement.size
        return switch placement.kind {
        case .media: NookMediaCard.height(for: size)
        case .calendar:
            NookCalendarCard.height(for: size, style: calendarStyle)
                + (size == .small ? 0 : NookCalendarExpansion.height(extraRows: calendarExtraRows))
        case .todo: NookTodoCard.height(for: size)
        case .notes: NookNotesCard.height(for: size)
        case .tray: NookTrayCard.height(for: size)
        case .timer: NookTimerCard.height(for: size)
        case .mirror: NookMirrorCard.height(for: size)
        case .weather: NookWeatherCard.height(for: size)
        }
    }

    /// Frames of the tiles in the shared edit space, for chip drops.
    @State private var tileFrames: [NookWidgetKind: CGRect] = [:]
    /// Tile a chip dragged out of the shelf is hovering over.
    @State private var insertionTarget: NookWidgetKind?
    @FocusState private var isEditFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far the scroll area reaches into the side inset, so a lifted
    /// tile's scale and shadow are not cut at the grid's edge.
    private static let liftOverhang: CGFloat = 16

    var body: some View {
        let nook = model.nook
        let placements = model.nookWidgetPlacements
        let isEditing = nook.isEditingLayout
        let style = model.nookDisplay.calendarStyle
        let extras = model.nookPageExtras
        VStack(spacing: 0) {
            if extras.showsJoinBar, let meeting = nook.meetingPrompt {
                // A meeting about to start goes above everything else.
                NookJoinBar(nook: nook, event: meeting)
                    .frame(height: NookJoinBarLayout.height)
                    .padding(.top, Self.verticalPadding)
                    .padding(.bottom, NookWidgetLayout.rowSpacing - Self.verticalPadding)
                    .transition(Motion.transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity), reduceMotion: reduceMotion))
            }
            if extras.showsEventEditor {
                // The editor sits above everything, the way the mirror does.
                NookEventEditor(nook: nook)
                    .frame(height: NookEventEditorLayout.height)
                    .padding(.top, Self.verticalPadding)
                    .padding(.bottom, NookWidgetLayout.rowSpacing - Self.verticalPadding)
                    .transition(Motion.transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity), reduceMotion: reduceMotion))
            }
            if let mirrorHeight = extras.mirrorHeight {
                // Above the scroll area, which keeps the mirror in view while
                // the widgets scroll. The grid pads its own top, and the gap
                // under the mirror plus that padding makes one row gap.
                NookMirrorView(nook: nook)
                    .frame(width: extras.mirrorWidth, height: mirrorHeight)
                    .padding(.top, Self.verticalPadding)
                    .padding(.bottom, NookWidgetLayout.rowSpacing - Self.verticalPadding)
                    .transition(Motion.transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity), reduceMotion: reduceMotion))
            }
            if extras.showsMirrorDecorationPicker {
                // Under the mirror and not over it, which keeps the whole
                // picture in view while stickers are placed.
                NookMirrorDecorationPicker(nook: nook)
                    .frame(height: NookMirrorDecorationLayout.pickerHeight)
                    .padding(.top, Self.verticalPadding)
                    .padding(.bottom, NookWidgetLayout.rowSpacing - Self.verticalPadding)
                    .transition(Motion.transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity), reduceMotion: reduceMotion))
            }
            if !placements.isEmpty {
                // The window stops at the bottom of the screen
                // (OverlayPanelController caps it); past that the grid
                // scrolls and the shelf stays pinned under it. The vertical
                // padding sits inside so the totals match preferredHeight.
                let scrollHeight = Self.verticalPadding * 2
                    + NookWidgetLayout.contentHeight(placements) {
                        Self.cardHeight($0, calendarStyle: style, calendarExtraRows: extras.calendarExtraRows)
                    }
                ScrollView(.vertical) {
                    grid(placements, isEditing: isEditing)
                        .padding(.vertical, Self.verticalPadding)
                        .padding(.horizontal, Self.liftOverhang)
                }
                .scrollBounceBehavior(.basedOnSize)
                .padding(.horizontal, -Self.liftOverhang)
                .frame(minHeight: 0, idealHeight: scrollHeight, maxHeight: scrollHeight)
                .transition(.opacity)
            } else if !isEditing {
                emptyState
                    .frame(height: Self.emptyHeight)
                    .padding(.vertical, Self.verticalPadding)
                    .transition(.opacity)
            }
            if isEditing {
                // One shelf for both cases, so it stays put when the page
                // gains its first widget or loses its last. With no grid
                // above it, it carries the grid's vertical padding itself.
                shelf(placements)
                    .padding(.top, NookWidgetLayout.rowSpacing + (placements.isEmpty ? Self.verticalPadding : 0))
                    .padding(.bottom, Self.verticalPadding)
                    .transition(Motion.transition(.move(edge: .bottom).combined(with: .opacity), reduceMotion: reduceMotion))
            }
        }
        .coordinateSpace(.nookWidgetEditing)
        .frame(maxWidth: .infinity, alignment: .top)
        // The page going away (agents page, a notification card) ends edit
        // mode, which would otherwise keep the island from collapsing.
        .onDisappear {
            nook.isEditingLayout = false
            // The mirror and its ring light must not stay on with no page
            // to show them or turn them off. A half-typed event is kept.
            nook.isMirrorOn = false
            nook.closeEventEditor(keepingDraft: true)
            nook.calendarExtraRows = 0
        }
        .focusable(isEditing)
        .focused($isEditFocused)
        .focusEffectDisabled()
        .onKeyPress(.escape) {
            guard nook.isEditingLayout else { return .ignored }
            setEditing(false)
            return .handled
        }
        .onChange(of: isEditing, initial: true) { _, editing in
            isEditFocused = editing
            if !editing { insertionTarget = nil }
        }
    }

    /// Layout changes reflow the page on the shared spring.
    private func reflow(_ change: () -> Void) {
        withMotion(Motion.reflow, change)
    }

    /// Entering or leaving edit mode fades the controls and slides the shelf.
    private func setEditing(_ editing: Bool) {
        withMotion(Motion.editToggle) { model.nook.isEditingLayout = editing }
    }

    private func grid(_ placements: [NookWidgetPlacement], isEditing: Bool) -> some View {
        let nook = model.nook
        let profile = nook.activeProfile()
        let style = model.nookDisplay.calendarStyle
        let extraRows = model.nookPageExtras.calendarExtraRows
        return NookWidgetGrid(
            placements: placements,
            isEditing: isEditing,
            cellHeight: { Self.cardHeight($0, calendarStyle: style, calendarExtraRows: extraRows) },
            highlightedKind: insertionTarget,
            outlinedKind: nook.tourOutlinedWidget,
            onFramesChange: { tileFrames = $0 },
            onMove: { kind, index in reflow { nook.moveWidget(kind, to: index, for: profile) } },
            onResize: { kind, size in reflow { nook.setWidgetSize(kind, size, for: profile) } },
            onRemove: { kind in reflow { nook.hideWidget(kind, for: profile) } },
            onBeginEditing: { setEditing(true) }
        ) { placement in
            card(for: placement.kind)
        }
    }

    private func shelf(_ placements: [NookWidgetPlacement]) -> some View {
        let nook = model.nook
        let profile = nook.activeProfile()
        return NookWidgetShelf(
            addable: nook.addableWidgets(for: profile),
            order: placements.map(\.kind),
            tileFrames: tileFrames,
            insertionTarget: $insertionTarget,
            onAdd: { kind in reflow { nook.addWidget(kind, for: profile) } },
            onAddAt: { kind, index in reflow { nook.addWidget(kind, at: index, for: profile) } },
            onDone: { setEditing(false) }
        )
    }

    @ViewBuilder
    private func card(for kind: NookWidgetKind) -> some View {
        switch kind {
        case .media: NookMediaCard(nook: model.nook)
        case .calendar: NookCalendarCard(nook: model.nook)
        case .todo: NookTodoCard(nook: model.nook)
        case .notes: NookNotesCard(nook: model.nook)
        case .tray: NookTrayCard(nook: model.nook)
        case .timer: NookTimerCard(nook: model.nook)
        case .mirror: NookMirrorCard(nook: model.nook)
        case .weather: NookWeatherCard(nook: model.nook)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No widgets on this display")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Button {
                setEditing(true)
            } label: {
                Label("Add widgets", systemImage: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Shared chrome for every Nook card so the page reads as one surface.
struct NookCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
    }
}

/// Small title row used at the top of cards that list things.
struct NookCardHeader: View {
    let title: String
    let systemImage: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.5))
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }
}
