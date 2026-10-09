import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// File tray card. Its header holds two tabs: the files, and the clipboard
/// history. For the files, small shows the count and up to three icons,
/// medium the original row of six tiles, large a two row grid with names.
/// The whole card is a drop target at every size, on either tab, and every
/// tile drags out.
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
    private static let maxTiles = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NookTrayHeader(store: store)
            switch store.tab {
            case .files:
                if store.items.isEmpty {
                    emptyState
                } else {
                    switch size {
                    case .small: NookTraySmallRow(store: store)
                    case .medium: mediumRow(store)
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
            if let notice = store.notice {
                NookTrayNoticeBar(notice: notice)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
        }
        .motionAnimation(Motion.hover, value: store.isFileDragOverIsland)
        .motionAnimation(Motion.hover, value: store.notice)
        .modifier(NookTrayDropTarget(store: store, isOn: takesDrops))
        // With the card gone there is nothing for a share picker to hang
        // off, and nothing to hold the island open for.
        .onDisappear { store.sharePickerDidClose() }
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

    private func mediumRow(_ store: NookTrayStore) -> some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(store.items.prefix(Self.maxTiles)) { item in
                NookTrayTile(store: store, item: item, metrics: .regular)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Header

/// The card's title row. The two tab names stand where the title was: the
/// one being shown is bright, and a click on the other switches to it.
private struct NookTrayHeader: View {
    var store: NookTrayStore

    var body: some View {
        HStack(spacing: 10) {
            ForEach(NookTrayTab.allCases) { tab in
                tabButton(tab)
            }
            Spacer(minLength: 0)
            trailing
        }
        .motionAnimation(Motion.selection, value: store.tab)
    }

    private func tabButton(_ tab: NookTrayTab) -> some View {
        let isSelected = store.tab == tab
        return Button {
            store.tab = tab
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(LanguageManager.shared.t(tab.titleKey).uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(isSelected ? 0.8 : 0.3))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var trailing: some View {
        switch store.tab {
        case .files:
            if !store.items.isEmpty {
                Text("\(store.items.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            }
        case .clipboard:
            if !store.clipboard.history.entries.isEmpty {
                Button {
                    withMotion(Motion.selection) { store.clipboard.clear() }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(LanguageManager.shared.t("nook.tray.clipboard.clear"))
                .accessibilityLabel(LanguageManager.shared.t("nook.tray.clipboard.clear"))
            }
        }
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

    private static let cornerRadius: CGFloat = 16

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    }

    var body: some View {
        shape
            .fill(Color.black.opacity(0.72))
            .overlay(shape.fill(Color.orange.opacity(0.14)))
            .overlay(shape.strokeBorder(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            .overlay {
                HStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: isCompact ? 13 : 15, weight: .semibold))
                    Text(LanguageManager.shared.t(isCompact ? "nook.tray.drop.short" : "nook.tray.drop.long"))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .foregroundStyle(Color.orange)
                .padding(.horizontal, 10)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Small

/// Up to three icons in a row, then a "+N" badge for the rest. Names are
/// dropped (they would need text under 10pt); hover shows them instead.
private struct NookTraySmallRow: View {
    var store: NookTrayStore
    private static let maxIcons = 3

    var body: some View {
        let metrics = NookTrayTileMetrics.compact
        let shown = Array(store.items.prefix(Self.maxIcons))
        let hidden = store.items.count - shown.count
        HStack(spacing: 6) {
            ForEach(shown) { item in
                NookTrayTile(store: store, item: item, metrics: metrics)
            }
            if hidden > 0 {
                NookTrayMoreTile(count: hidden, side: metrics.icon, caption: nil)
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Large

/// Up to two rows of tiles with names. The column count follows the width;
/// when the files do not fit, the last slot becomes a "+N" tile.
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

// MARK: - Shared pieces

/// Sizes for one tile. A nil `nameSize` means icon only.
private struct NookTrayTileMetrics {
    let width: CGFloat
    let icon: CGFloat
    let nameSize: CGFloat?
    let gap: CGFloat

    static let compact = NookTrayTileMetrics(width: 40, icon: 36, nameSize: nil, gap: 0)
    static let regular = NookTrayTileMetrics(width: 52, icon: 32, nameSize: 9, gap: 2)
    static let roomy = NookTrayTileMetrics(width: 64, icon: 40, nameSize: 10, gap: 3)
}

/// One file. Hovering shows a share button and a remove button on its
/// corners. A right click lists everything the tray can do with it.
private struct NookTrayTile: View {
    var store: NookTrayStore
    let item: NookTrayItem
    let metrics: NookTrayTileMetrics
    @State private var isHovering = false
    /// The view the share picker hangs off.
    @State private var anchor = NookTrayAnchorBox()

    var body: some View {
        let url = store.storedURL(for: item)
        let isWorking = store.workingIDs.contains(item.id)
        VStack(spacing: metrics.gap) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: metrics.icon, height: metrics.icon)
                .opacity(isWorking ? 0.4 : 1)
                .overlay {
                    if isWorking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            if let nameSize = metrics.nameSize {
                Text(item.originalName)
                    .font(.system(size: nameSize))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: metrics.width)
        // The anchor is only a place to hang the picker. It takes no clicks,
        // which leaves dragging the tile as it was.
        .background(NookTrayShareAnchor(box: anchor).allowsHitTesting(false).accessibilityHidden(true))
        .overlay(alignment: .topLeading) {
            if isHovering {
                Button {
                    store.share(item, from: anchor.view)
                } label: {
                    Image(systemName: "square.and.arrow.up.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85), .black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help(LanguageManager.shared.t("nook.tray.action.share"))
                .accessibilityLabel(LanguageManager.shared.t("nook.tray.action.share"))
            }
        }
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button {
                    store.remove(item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85), .black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LanguageManager.shared.t("nook.tray.action.remove"))
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .help(metrics.nameSize == nil ? item.originalName : "")
        .onDrag {
            NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
        }
        .contextMenu {
            Button(LanguageManager.shared.t("nook.tray.action.share")) { store.share(item, from: anchor.view) }
            Button(LanguageManager.shared.t("nook.tray.action.airDrop")) { store.airDrop(item) }
            Divider()
            Button(LanguageManager.shared.t("nook.tray.action.compress")) { store.compress(item) }
            if let format = NookTrayFileActions.conversionTarget(forFileNamed: item.originalName) {
                Button(LanguageManager.shared.t(format.actionTitleKey)) { store.convert(item, to: format) }
            }
            Button(LanguageManager.shared.t("nook.tray.action.copyPath")) { store.copyPath(of: item) }
            Divider()
            Button(LanguageManager.shared.t("nook.tray.action.reveal")) { store.revealInFinder(item) }
            Button(LanguageManager.shared.t("nook.tray.action.remove")) { store.remove(item) }
        }
    }
}

/// "+N" stand-in for the files that do not fit. A caption keeps it the
/// same height as a named tile.
private struct NookTrayMoreTile: View {
    let count: Int
    let side: CGFloat
    let caption: String?

    var body: some View {
        VStack(spacing: 3) {
            Text("+\(count)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: side, height: side)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
            if let caption {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }
}
