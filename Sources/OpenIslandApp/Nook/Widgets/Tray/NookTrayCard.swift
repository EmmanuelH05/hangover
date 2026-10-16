import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// File tray card. Its header holds two tabs (`NookTrayHeader`): the files,
/// and the clipboard history. For the files, small shows the count and up to
/// three icons, medium the original row of six tiles, large a two row grid
/// with names. The whole card is a drop target at every size, on either tab,
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
    private static let maxTiles = 6

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

    private func mediumRow(_ store: NookTrayStore) -> some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(store.items.prefix(Self.maxTiles)) { item in
                NookTrayTile(store: store, item: item, metrics: .regular)
            }
            Spacer(minLength: 0)
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
    @Environment(\.hangoverAccent) private var accent
    @Environment(\.nookWidgetSize) private var size

    /// True while the Convert chip waits for a file, on every card size.
    private var takesPicks: Bool {
        store.isPickingToConvert
    }

    /// While picking, a click chooses this file to convert, or does nothing
    /// when it has no conversions. Otherwise Command-click chooses or drops
    /// this file, Shift-click chooses a range, and a plain click lets go of
    /// a choice already made.
    private func handleTap() {
        if takesPicks {
            store.pickToConvert(item)
            return
        }
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            store.toggleSelection(of: item)
        } else if flags.contains(.shift) {
            store.extendSelection(to: item)
        } else if !store.selection.isEmpty {
            store.clearSelection()
        }
    }

    var body: some View {
        let url = store.storedURL(for: item)
        let isWorking = store.workingIDs.contains(item.id)
        let job = store.jobs[item.id]
        let isSelected = store.selection.contains(item.id)
        let isPicking = takesPicks
        let isPickable = isPicking && store.canPickToConvert(item)
        VStack(spacing: metrics.gap) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: metrics.icon, height: metrics.icon)
                .opacity(isWorking || job != nil ? 0.4 : 1)
                .overlay {
                    if isWorking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let job {
                        NookTrayJobBar(fraction: job.fraction)
                            .frame(width: max(12, metrics.icon - 8))
                            .padding(.bottom, 2)
                    }
                }
                .overlay(alignment: .bottom) {
                    let actions = NookTrayRecordingAction.offered(for: item, size: size)
                    if isHovering, !isPicking, job == nil, !isWorking, !actions.isEmpty {
                        NookTrayRecordingButtons(store: store, item: item, actions: actions)
                            .padding(.bottom, 1)
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
        // A file with nothing to convert steps back while picking.
        .opacity(isPicking && !isPickable ? 0.3 : 1)
        .background {
            // The files that can be picked are outlined in the accent.
            if isPickable {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(accent.highlight(.orange), lineWidth: 1.5)
                    .padding(-3)
            }
        }
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.highlight(.orange).opacity(0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(accent.highlight(.orange).opacity(0.8), lineWidth: 1)
                    )
                    .padding(-3)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAddTraits(isPickable ? .isButton : [])
        // The anchor is only a place to hang the picker. It takes no clicks,
        // which leaves dragging the tile as it was.
        .background(NookTrayShareAnchor(box: anchor).allowsHitTesting(false).accessibilityHidden(true))
        .overlay(alignment: .topLeading) {
            if isHovering, !isPicking {
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
            if job != nil {
                // A running conversion shows its stop button without a
                // hover, because it is what the tile is doing right now.
                Button {
                    store.cancelJob(for: item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85), .black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help(LanguageManager.shared.t("nook.tray.convert.cancel"))
                .accessibilityLabel(LanguageManager.shared.t("nook.tray.convert.cancel"))
            } else if isHovering, !isPicking {
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
        .onTapGesture { handleTap() }
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
            if !NookConvertRules.actions(forFileNamed: item.originalName).isEmpty {
                NookTrayConvertMenu(store: store, item: item, url: url)
            }
            Button(LanguageManager.shared.t("nook.tray.action.copyPath")) { store.copyPath(of: item) }
            // A picture can go to the design kit's references while that
            // widget is on. The tray keeps its own copy.
            if let design = store.nook?.design, store.nook?.isWidgetEnabled(.design) == true,
               NookDesignReferenceRules.isPictureFileName(item.originalName) {
                Button(LanguageManager.shared.t("nook.design.action.addFromTray")) {
                    design.addReference(fileAt: url)
                }
            }
            Divider()
            Button(LanguageManager.shared.t("nook.tray.action.reveal")) { store.revealInFinder(item) }
            Button(LanguageManager.shared.t("nook.tray.action.remove")) { store.remove(item) }
        }
    }
}

/// A thin bar on a tile whose file is being converted. A conversion that
/// cannot say how far it has got shows a bar that keeps moving.
private struct NookTrayJobBar: View {
    let fraction: Double?

    var body: some View {
        Group {
            if let fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView()
            }
        }
        .progressViewStyle(.linear)
        .controlSize(.mini)
        .tint(.white)
    }
}

/// The Convert submenu of a file's right click: only what fits the file,
/// in groups. A GIF with several pictures says that only the first one is
/// converted.
private struct NookTrayConvertMenu: View {
    var store: NookTrayStore
    let item: NookTrayItem
    let url: URL

    var body: some View {
        let actions = NookConvertRules.actions(forFileNamed: item.originalName, at: url)
        Menu(LanguageManager.shared.t("nook.tray.convert.menu")) {
            if NookConvertRules.isAnimatedGIF(at: url) {
                Button(LanguageManager.shared.t("nook.tray.convert.firstFrameOnly")) {}
                    .disabled(true)
            }
            ForEach(NookConvertGroup.allCases, id: \.self) { group in
                let inGroup = actions.filter { $0.group == group }
                if !inGroup.isEmpty {
                    Section {
                        ForEach(inGroup, id: \.self) { action in
                            Button(action.menuTitle) { store.convert(item, action: action) }
                        }
                    } header: {
                        Text(LanguageManager.shared.t(group.titleKey))
                    }
                }
            }
        }
        .disabled(store.jobs[item.id] != nil)
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
