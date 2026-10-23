import AppKit
import SwiftUI

// MARK: - Shared pieces

/// Sizes for one tile. A nil `nameSize` means icon only.
struct NookTrayTileMetrics {
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
struct NookTrayTile: View {
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
struct NookTrayJobBar: View {
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
struct NookTrayConvertMenu: View {
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
/// same height as a named tile. A click opens every file in the strip above
/// the cards, and the square carries a paper outline while that strip is
/// open.
struct NookTrayMoreTile: View {
    var store: NookTrayStore
    let count: Int
    let side: CGFloat
    let caption: String?

    var body: some View {
        let isOpen = store.isShowingAllFiles
        let help = LanguageManager.shared.t("nook.tray.more.help")
        Button {
            store.showAllFiles()
        } label: {
            VStack(spacing: 3) {
                Text("+\(count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(.white.opacity(isOpen ? 1 : 0.6))
                    .frame(width: side, height: side)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .overlay {
                        if isOpen {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(V6Palette.paper, lineWidth: 2)
                        }
                    }
                if let caption {
                    Text(caption)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
