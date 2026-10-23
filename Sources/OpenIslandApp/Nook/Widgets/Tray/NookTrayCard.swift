import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// File tray card. Its header holds two tabs (`NookTrayHeader`): the files,
/// and the clipboard history. For the files, small shows icons only and
/// medium a row with names, and both follow the tray's overflow choice: in
/// Scroll every file sits in one row that swipes sideways, in Count them the
/// row fills by width and ends in a "+N" tile. Large keeps a two row grid
/// with names and a "+N" tile in both modes. A click on any "+N" tile opens
/// every file in a strip above the cards. The whole card is a drop target at every size, on either tab,
/// and every tile drags out. A tile's right click lists what the tray can do
/// with it, Convert included. On the medium and large card the Convert chip
/// after FILES does the same: it turns on picking, and a click on a tile
/// then opens the Convert strip for that file. Command-click and Shift-click
/// choose several files, and a bar over the bottom of the card offers to
/// combine them. The GIF options and the Convert strip open above the cards
/// (`NookGIFStrip`, `NookConvertStrip`) and leave the files in view here.
struct NookTrayCard: View {
    var store: NookTrayStore
    private let takesDrops: Bool
    @Environment(\.nookWidgetSize) private var size

    init(nook: NookModel) {
        store = nook.tray
        takesDrops = true
    }

    /// A card on a store of its own, which is how the render tests draw
    /// it. They leave the drop target off: it is backed by AppKit, and
    /// `ImageRenderer` paints a placeholder over the whole card for it.
    init(store: NookTrayStore, takesDrops: Bool = true) {
        self.store = store
        self.takesDrops = takesDrops
    }

    static let height: CGFloat = 90

    /// Height at each size. Small rows always use the grid's shared height.
    static func height(for size: NookWidgetSize) -> CGFloat {
        switch size {
        case .small: NookWidgetLayout.smallHeight
        case .medium: height
        case .large: 170
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NookTrayHeader(store: store)
            switch store.tab {
            case .files:
                // The GIF options and the Convert strip open in a strip above
                // the cards, which leaves the files in view here.
                if store.items.isEmpty {
                    emptyState
                } else {
                    switch size {
                    case .small: NookTraySmallRow(store: store)
                    case .medium: NookTrayMediumRow(store: store)
                    case .large: NookTrayGrid(store: store)
                    }
                }
            case .clipboard:
                NookClipboardTab(store: store)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // Fill the cell the grid gives us; the grid owns the outer height.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(NookCardBackground())
        .overlay {
            if store.isFileDragOverIsland {
                NookTrayDropHighlight(isCompact: size == .small)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 4) {
                if store.tab == .files, store.gifSourceItem == nil, store.convertSourceItem == nil,
                   !store.combineActions.isEmpty {
                    NookTrayCombineBar(store: store)
                        .transition(.opacity)
                }
                if let notice = store.notice {
                    NookTrayNoticeBar(notice: notice)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .motionAnimation(Motion.hover, value: store.isFileDragOverIsland)
        .motionAnimation(Motion.hover, value: store.notice)
        .motionAnimation(Motion.hover, value: store.selection)
        .motionAnimation(Motion.hover, value: store.isPickingToConvert)
        .modifier(NookTrayDropTarget(store: store, isOn: takesDrops))
        // With the card gone there is nothing for a share picker to hang
        // off, and nothing to hold the island open for. Picking a file to
        // convert is over too, which would otherwise be waiting when the
        // card comes back.
        .onDisappear {
            store.sharePickerDidClose()
            store.cancelPickingToConvert()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        Spacer(minLength: 0)
        switch size {
        case .small:
            VStack(spacing: 4) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 18))
                Text(LanguageManager.shared.t("nook.tray.empty.short"))
                    .font(.system(size: 12))
            }
            .foregroundStyle(.white.opacity(0.35))
            .frame(maxWidth: .infinity, alignment: .center)
        case .medium:
            Text(LanguageManager.shared.t("nook.tray.empty.long"))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .center)
        case .large:
            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 22))
                Text(LanguageManager.shared.t("nook.tray.empty.long"))
                    .font(.system(size: 12))
            }
            .foregroundStyle(.white.opacity(0.35))
            .frame(maxWidth: .infinity, alignment: .center)
        }
        Spacer(minLength: 0)
    }
}

/// A line over the bottom of the card that says what an action did, or
/// why it could not.
private struct NookTrayNoticeBar: View {
    let notice: NookTrayNotice

    private var symbol: String {
        switch notice.kind {
        case .done: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch notice.kind {
        case .done: .green
        case .info: .white.opacity(0.6)
        case .error: .orange
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(notice.text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.82)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        .allowsHitTesting(false)
    }
}

/// Offers to make one PDF of the chosen files, when they can be. A
/// choice that cannot be combined shows no bar, and a plain click on a
/// file clears it.
private struct NookTrayCombineBar: View {
    var store: NookTrayStore

    var body: some View {
        // A conversion still reading one of the chosen files would make
        // Combine do nothing, so the buttons go dim and say what they wait for.
        let blocker = store.combineBlocker
        let help = blocker.map { NookConvertRules.waitText(forBusyFileNamed: $0.originalName) } ?? ""
        HStack(spacing: 10) {
            ForEach(store.combineActions, id: \.self) { action in
                Button {
                    store.combine(store.selectedItems, action: action)
                } label: {
                    Text(LanguageManager.shared.t(action.titleKey))
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.95))
                }
                .buttonStyle(.plain)
                .disabled(blocker != nil)
                .opacity(blocker == nil ? 1 : 0.4)
                .help(help)
            }
            Button {
                store.clearSelection()
            } label: {
                Text(LanguageManager.shared.t("nook.tray.convert.combine.clear"))
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.82)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
    }
}

// MARK: - Drop target

/// Makes the whole card take dropped files.
private struct NookTrayDropTarget: ViewModifier {
    var store: NookTrayStore
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.onDrop(of: [.fileURL], isTargeted: nil) { providers in
                store.handleDrop(providers)
            }
        } else {
            content
        }
    }
}

// MARK: - Drop highlight

/// Covers the tray card while files are dragged over the island, which
/// marks it as the place they land. It takes no hits: the drop still goes
/// to the card under it.
private struct NookTrayDropHighlight: View {
    let isCompact: Bool
    @Environment(\.hangoverAccent) private var accent

    private static let cornerRadius: CGFloat = 16

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    }

    var body: some View {
        shape
            .fill(Color.black.opacity(0.72))
            .overlay(shape.fill(accent.highlight(.orange).opacity(0.14)))
            .overlay(shape.strokeBorder(accent.highlight(.orange), style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            .overlay {
                HStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: isCompact ? 13 : 15, weight: .semibold))
                    Text(LanguageManager.shared.t(isCompact ? "nook.tray.drop.short" : "nook.tray.drop.long"))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .foregroundStyle(accent.highlight(.orange))
                .padding(.horizontal, 10)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Small and medium rows

/// Small: icons only, at compact metrics.
private struct NookTraySmallRow: View {
    var store: NookTrayStore

    var body: some View {
        NookTrayOverflowRow(store: store, metrics: .compact, isCentered: true, moreCaption: nil)
    }
}

/// Medium: a row with names, at regular metrics. Its "+N" tile carries the
/// "more" caption, like the large card's.
private struct NookTrayMediumRow: View {
    var store: NookTrayStore

    var body: some View {
        NookTrayOverflowRow(
            store: store,
            metrics: .regular,
            isCentered: false,
            moreCaption: LanguageManager.shared.t("nook.tray.more")
        )
    }
}

/// One row of tiles that follows the tray's overflow choice.
private struct NookTrayOverflowRow: View {
    var store: NookTrayStore
    let metrics: NookTrayTileMetrics
    /// Small centers its icons in the space under the header, medium sits
    /// them at the top.
    let isCentered: Bool
    let moreCaption: String?

    var body: some View {
        switch store.overflow {
        case .scroll:
            NookTrayScrollRow(store: store, metrics: metrics, isCentered: isCentered)
        case .count:
            NookTrayFillRow(store: store, metrics: metrics, isCentered: isCentered, moreCaption: moreCaption)
        }
    }
}

/// Count them: as many tiles as the width holds, the last slot a "+N" tile
/// when the files do not all fit.
private struct NookTrayFillRow: View {
    var store: NookTrayStore
    let metrics: NookTrayTileMetrics
    let isCentered: Bool
    let moreCaption: String?

    var body: some View {
        GeometryReader { proxy in
            let items = store.items
            let slots = NookTrayRowLayout.slots(width: proxy.size.width, tileWidth: metrics.width)
            let shown = NookTrayRowLayout.shown(count: items.count, slots: slots)
            let hidden = items.count - shown
            HStack(alignment: .top, spacing: NookTrayRowLayout.spacing) {
                ForEach(items.prefix(shown)) { item in
                    NookTrayTile(store: store, item: item, metrics: metrics)
                }
                if hidden > 0 {
                    NookTrayMoreTile(store: store, count: hidden, side: metrics.icon, caption: moreCaption)
                        .frame(width: metrics.width)
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: isCentered ? .center : .top)
        }
    }
}

/// How far a scroll view has moved, for the tray's scroll bars. SwiftUI's
/// scroll view on macOS moves its content through AppKit, which never
/// measures the content again: a GeometryReader inside it stays at the start
/// however far the row goes. The scroll view reports its own offset from
/// macOS 15. macOS 14 has no way to ask, and its bars stay hidden.
enum NookScrollOffset {
    static var isTracked: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }
}

extension View {
    func nookScrollOffset(_ axis: Axis, into offset: Binding<CGFloat>) -> some View {
        modifier(NookScrollOffsetReader(axis: axis, offset: offset))
    }
}

private struct NookScrollOffsetReader: ViewModifier {
    let axis: Axis
    @Binding var offset: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                axis == .horizontal ? geometry.contentOffset.x : geometry.contentOffset.y
            } action: { _, new in
                offset = new
            }
        } else {
            content
        }
    }
}

/// Scroll: every file in one row that swipes sideways. The row runs past
/// the card's right padding to the card's edge under a fade, and a thin bar
/// shows the position. Small puts the bar under the icons; medium puts it
/// 5 points above the card's bottom.
private struct NookTrayScrollRow: View {
    var store: NookTrayStore
    let metrics: NookTrayTileMetrics
    let isCentered: Bool

    @State private var offset: CGFloat = 0
    /// A still picture (the render tests) cannot draw a `ScrollView`, which
    /// is AppKit-backed. It gets the row at its start, clipped the same way.
    @Environment(\.nookDrawsStill) private var drawsStill

    /// The card's right padding, which the row runs through.
    private static let overrun: CGFloat = 14
    private static let fadeWidth: CGFloat = 44
    private static let barHeight: CGFloat = 3

    /// The content's width, which the tile metrics fix: every tile, the gaps
    /// and the room kept at the end. Only the scroll position is measured.
    private var contentWidth: CGFloat {
        let count = CGFloat(store.items.count)
        guard count > 0 else { return 0 }
        return count * metrics.width + (count - 1) * NookTrayRowLayout.spacing + Self.fadeWidth
    }

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.size.width
            let viewport = frame + Self.overrun
            let showsBar = contentWidth > viewport + 0.5 && NookScrollOffset.isTracked
            VStack(spacing: 6) {
                scrolled(width: viewport)
                .frame(width: viewport)
                .frame(maxHeight: .infinity)
                .mask(alignment: .leading) { fadeMask(width: viewport) }
                .frame(width: frame, alignment: .leading)
                .overlay(alignment: .bottomLeading) {
                    if showsBar, !isCentered {
                        bar(frame: frame, viewport: viewport)
                            .offset(y: 7)
                    }
                }
                if showsBar, isCentered {
                    bar(frame: frame, viewport: viewport)
                }
            }
            .frame(width: frame, height: proxy.size.height, alignment: .top)
        }
    }

    @ViewBuilder
    private func scrolled(width: CGFloat) -> some View {
        if drawsStill {
            tiles.fixedSize().frame(width: width, alignment: .leading).clipped()
        } else {
            ScrollView(.horizontal, showsIndicators: false) { tiles }
                .nookScrollOffset(.horizontal, into: $offset)
        }
    }

    /// Lazy: a tray of a hundred files builds only the tiles in view, and a
    /// conversion's progress redraws only those.
    private var tiles: some View {
        LazyHStack(alignment: .top, spacing: NookTrayRowLayout.spacing) {
            ForEach(store.items) { item in
                NookTrayTile(store: store, item: item, metrics: metrics)
            }
        }
        // Room at the end, which lets the last file scroll out from under
        // the fade.
        .padding(.trailing, Self.fadeWidth)
        .frame(maxHeight: .infinity, alignment: isCentered ? .center : .top)
    }

    /// Opaque everywhere but the last 44 points, which fall to clear.
    private func fadeMask(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(Color.black)
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.fadeWidth)
        }
        .frame(width: width)
    }

    /// The thumb's width is the share of the content in view, and its
    /// offset follows how far the content has moved.
    private func bar(frame: CGFloat, viewport: CGFloat) -> some View {
        let total = max(contentWidth, 1)
        let fraction = min(1, viewport / total)
        let thumb = max(12, frame * fraction)
        let travel = max(1, total - viewport)
        let progress = min(1, max(0, offset / travel))
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.08))
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.35))
                .frame(width: thumb)
                .offset(x: (frame - thumb) * progress)
        }
        .frame(width: frame, height: Self.barHeight)
        .accessibilityHidden(true)
    }
}

// MARK: - Large

/// Up to two rows of tiles with names, in both overflow modes. The column
/// count follows the width; when the files do not fit, the last slot becomes
/// a "+N" tile that opens every file.
private struct NookTrayGrid: View {
    var store: NookTrayStore

    private static let metrics = NookTrayTileMetrics.roomy
    private static let rowCount = 2
    private static let columnSpacing: CGFloat = 6
    private static let rowSpacing: CGFloat = 8

    private static func columnCount(for width: CGFloat) -> Int {
        let slot = metrics.width + columnSpacing
        return max(1, Int((width + columnSpacing) / slot))
    }

    var body: some View {
        GeometryReader { proxy in
            let columns = Self.columnCount(for: proxy.size.width)
            let capacity = columns * Self.rowCount
            let items = store.items
            let shown = items.count > capacity ? Array(items.prefix(capacity - 1)) : items
            let hidden = items.count - shown.count
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(minimum: Self.metrics.width), spacing: Self.columnSpacing),
                    count: columns
                ),
                alignment: .leading,
                spacing: Self.rowSpacing
            ) {
                ForEach(shown) { item in
                    NookTrayTile(store: store, item: item, metrics: Self.metrics)
                        .frame(maxWidth: .infinity)
                }
                if hidden > 0 {
                    NookTrayMoreTile(
                        store: store,
                        count: hidden,
                        side: Self.metrics.icon,
                        caption: LanguageManager.shared.t("nook.tray.more")
                    )
                    .frame(width: Self.metrics.width)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
