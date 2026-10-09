import SwiftUI

/// The Personalization tab's editor for one display's Nook page. It is the
/// island's own edit mode (the same grid, drags, size buttons, resize grip
/// and shelf) drawn with placeholder tiles at the island's width and a
/// shorter height, so the whole page fits in the settings window.
struct NookLayoutEditor: View {
    var nook: NookModel
    var profile: IslandAppearanceDisplayProfile
    /// The opened look of the display being edited, which sets the page's
    /// width.
    var look: IslandOpenedLook = .standard
    var calendarStyle: NookCalendarStyle
    var addTitle: String
    var allShownTitle: String
    var emptyTitle: String
    var resetTitle: String

    /// Heights are drawn at this fraction of the island's; widths match it.
    static let heightScale: CGFloat = 0.6
    private static let padding: CGFloat = 12
    private static let emptyHeight: CGFloat = 56

    /// The island's content width on this kind of display under `look`:
    /// the opened panel minus its side insets (448 on the notch and 488 on
    /// a top bar under the standard look).
    nonisolated static func pageWidth(
        for profile: IslandAppearanceDisplayProfile,
        look: IslandOpenedLook = .standard
    ) -> CGFloat {
        IslandOpenedMetrics.resolve(look: look, profile: profile).pageWidth
    }

    @State private var tileFrames: [NookWidgetKind: CGRect] = [:]
    @State private var insertionTarget: NookWidgetKind?

    var body: some View {
        let placements = nook.widgetPlacements(for: profile)
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: NookWidgetLayout.rowSpacing) {
                if placements.isEmpty {
                    Text(emptyTitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.white.opacity(0.38))
                        .frame(maxWidth: .infinity, minHeight: Self.emptyHeight)
                        .transition(.opacity)
                } else {
                    grid(placements)
                        .transition(.opacity)
                }
                NookWidgetShelf(
                    addable: nook.addableWidgets(for: profile),
                    order: placements.map(\.kind),
                    tileFrames: tileFrames,
                    insertionTarget: $insertionTarget,
                    onAdd: { kind in
                        reflow { nook.addWidget(kind, for: profile) }
                        nook.widgetTurnedOn(kind)
                    },
                    onAddAt: { kind, index in
                        reflow { nook.addWidget(kind, at: index, for: profile) }
                        nook.widgetTurnedOn(kind)
                    },
                    onDone: nil,
                    addTitle: addTitle,
                    allShownTitle: allShownTitle
                )
            }
            .coordinateSpace(.nookWidgetEditing)
            .padding(Self.padding)
            .frame(maxWidth: Self.pageWidth(for: profile, look: look) + Self.padding * 2)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black)
            )

            Button(resetTitle) {
                reflow { nook.resetWidgetLayout(for: profile) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.55))
        }
    }

    /// Every layout change reflows the grid on the shared spring.
    private func reflow(_ change: () -> Void) {
        withMotion(Motion.reflow, change)
    }

    private func grid(_ placements: [NookWidgetPlacement]) -> some View {
        NookWidgetGrid(
            placements: placements,
            isEditing: true,
            cellHeight: { NookPanelView.cardHeight($0, calendarStyle: calendarStyle) * Self.heightScale },
            smallRowHeight: NookWidgetLayout.smallHeight * Self.heightScale,
            allowsContextMenu: false,
            entersEditingOnLongPress: false,
            highlightedKind: insertionTarget,
            onFramesChange: { tileFrames = $0 },
            onMove: { kind, index in reflow { nook.moveWidget(kind, to: index, for: profile) } },
            onResize: { kind, size in reflow { nook.setWidgetSize(kind, size, for: profile) } },
            onRemove: { kind in reflow { nook.hideWidget(kind, for: profile) } },
            onBeginEditing: {}
        ) { placement in
            NookLayoutPlaceholderTile(kind: placement.kind)
        }
    }
}

/// Stand-in for a card in the settings editor: the widget's symbol and name
/// on the card background. Full-strength colors because the grid dims
/// tiles while editing.
private struct NookLayoutPlaceholderTile: View {
    let kind: NookWidgetKind

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
            Text(kind.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NookCardBackground())
    }
}
