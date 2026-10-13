import SwiftUI

/// The picture side of the card: the shelf's thumbnails. A click floats a
/// picture in a panel of its own, a tile drags out as a file, and a right
/// click lists the rest. Small and medium show one row, large shows two
/// with names and a line of help or the field a name is typed into.
struct NookDesignReferencesTab: View {
    var kit: NookDesignKit
    @Environment(\.nookWidgetSize) private var size

    var body: some View {
        let items = kit.references.items
        VStack(alignment: .leading, spacing: 8) {
            if items.isEmpty {
                emptyState
            } else if size != .large, let renaming = renamingItem {
                // One row has no room for a name under each picture. The
                // field takes the row while a name is typed.
                NookDesignRenameRow(kit: kit, item: renaming)
                    .frame(height: 24)
                    .frame(maxHeight: .infinity, alignment: .center)
            } else {
                NookDesignTileGrid(
                    kit: kit,
                    items: NookDesignReferenceRules.compactOrder(items),
                    rowCount: size == .large ? 2 : 1
                )
            }
            if size == .large {
                footer(items)
                    .frame(height: 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var renamingItem: NookDesignReference? {
        kit.renamingReferenceID.flatMap { kit.references.item($0) }
    }

    @ViewBuilder
    private func footer(_ items: [NookDesignReference]) -> some View {
        if let renaming = renamingItem {
            NookDesignRenameRow(kit: kit, item: renaming)
        } else {
            let lang = LanguageManager.shared
            HStack(spacing: 6) {
                Text(lang.t(items.isEmpty ? "nook.design.references.hint.empty" : "nook.design.references.hint"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if !kit.openPanels.isEmpty {
                    Text(lang.t("nook.design.references.open", kit.openPanels.count, NookDesignPanelRules.maxOpenPanels))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let lang = LanguageManager.shared
        switch size {
        case .small:
            VStack(spacing: 4) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 18))
                Text(lang.t("nook.design.references.empty.short"))
                    .font(.system(size: 11))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white.opacity(0.35))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case .medium, .large:
            HStack(spacing: 10) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: size == .large ? 24 : 18))
                    .foregroundStyle(.white.opacity(0.35))
                Text(lang.t("nook.design.references.empty.long"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - Tiles

/// One or two rows of square tiles. What does not fit hides behind a "+N"
/// tile, which only counts: the shelf has no larger view yet.
private struct NookDesignTileGrid: View {
    var kit: NookDesignKit
    let items: [NookDesignReference]
    let rowCount: Int
    @Environment(\.nookWidgetSize) private var size

    var body: some View {
        let side = NookDesignCardLayout.tileSide(for: size)
        let showsNames = rowCount > 1
        let rowHeight = side + (showsNames ? 15 : 0)
        let rowGap: CGFloat = 8
        let fullHeight = rowHeight * CGFloat(rowCount) + rowGap * CGFloat(rowCount - 1)
        GeometryReader { proxy in
            // With less height than every row needs, which is what a pill on a
            // line of its own leaves, the second row goes and the "+N" tile
            // counts what is left out. Nothing is drawn past the card.
            let rows = proxy.size.height < fullHeight ? 1 : rowCount
            let columns = max(1, NookDesignCardLayout.capacity(width: proxy.size.width, side: side))
            let grid = NookDesignCardLayout.visible(items, capacity: columns * rows)
            let cells = grid.shown.map(Cell.item) + (grid.hidden > 0 ? [Cell.more(grid.hidden)] : [])
            VStack(alignment: .leading, spacing: rowGap) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(alignment: .top, spacing: NookDesignCardLayout.spacing) {
                        ForEach(cells.dropFirst(row * columns).prefix(columns)) { cell in
                            switch cell {
                            case let .item(item):
                                NookDesignReferenceTile(kit: kit, item: item, side: side, showsName: showsNames)
                            case let .more(count):
                                NookDesignMoreTile(count: count, side: side)
                                    .accessibilityLabel(LanguageManager.shared.t("nook.design.references.more", count))
                            }
                        }
                    }
                    .frame(height: rowHeight, alignment: .top)
                }
            }
        }
        .frame(minHeight: rowHeight, maxHeight: fullHeight)
    }

    private enum Cell: Identifiable {
        case item(NookDesignReference)
        case more(Int)

        var id: String {
            switch self {
            case let .item(item): item.id.uuidString
            case .more: "more"
            }
        }
    }
}

/// One picture. It is drawn whole, in its own shape, inside a square. A
/// click floats it, and it drags out as the copy the shelf keeps.
private struct NookDesignReferenceTile: View {
    @Environment(\.hangoverAccent) private var accent
    var kit: NookDesignKit
    let item: NookDesignReference
    let side: CGFloat
    let showsName: Bool
    @State private var isHovering = false
    @Environment(\.nookDesignIsStill) private var isStill

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    var body: some View {
        let lang = LanguageManager.shared
        let name = item.name.isEmpty ? lang.t("nook.design.reference.untitled") : item.name
        let isOpen = kit.openPanels[item.id] != nil
        let tile = VStack(spacing: 3) {
            Button {
                kit.openReference(item.id)
            } label: {
                picture
                    .frame(width: side, height: side)
                    .background(shape.fill(Color.white.opacity(0.06)))
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(isOpen ? accent.highlight(.orange) : Color.white.opacity(0.12), lineWidth: isOpen ? 1.5 : 0.5))
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lang.t("nook.design.action.float", name))
            if showsName {
                Text(name)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.white.opacity(item.name.isEmpty ? 0.35 : 0.6))
                    .frame(width: side)
            }
        }
        .overlay(alignment: .topLeading) {
            if item.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow)
                    .padding(2.5)
                    .background(Circle().fill(Color.black.opacity(0.6)))
                    .padding(2)
                    .accessibilityHidden(true)
            }
        }
        .task(id: item.id) { kit.references.requestThumbnail(for: item) }

        if isStill {
            tile
        } else {
            tile
                .overlay(alignment: .topTrailing) {
                    if isHovering {
                        Button {
                            withMotion(Motion.reflow) { _ = kit.removeReference(item.id) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.9), .black.opacity(0.65))
                        }
                        .buttonStyle(.plain)
                        .help(lang.t("nook.design.action.remove"))
                        .accessibilityLabel(lang.t("nook.design.action.removeNamed", name))
                    }
                }
                .onHover { isHovering = $0 }
                .help(name)
                .onDrag {
                    let url = kit.references.fileURL(for: item)
                    return NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
                }
                .contextMenu { menu(name: name, isOpen: isOpen) }
        }
    }

    @ViewBuilder
    private var picture: some View {
        if let thumbnail = kit.references.thumbnails[item.id] {
            let fitted = NookDesignReferenceRules.fittedSize(aspectRatio: item.aspectRatio, in: side)
            Image(decorative: thumbnail, scale: 1)
                .resizable()
                .interpolation(.medium)
                .frame(width: fitted.width, height: fitted.height)
                .background {
                    if NookDesignPictures.carriesAlpha(thumbnail.alphaInfo) {
                        // Pulled in from the edge: a scaled picture's edge
                        // is soft, and the squares would show along it.
                        NookDesignCheckerboard(square: 4)
                            .padding(2)
                    }
                }
        } else {
            Image(systemName: "photo")
                .font(.system(size: side * 0.3))
                .foregroundStyle(.white.opacity(0.25))
        }
    }

    @ViewBuilder
    private func menu(name: String, isOpen: Bool) -> some View {
        let lang = LanguageManager.shared
        if isOpen {
            Button(lang.t("nook.design.action.closePanel")) { kit.closeReferencePanel(item.id) }
        } else {
            Button(lang.t("nook.design.action.float", name)) { kit.openReference(item.id) }
        }
        Button(lang.t("nook.design.action.rename")) { kit.beginRenamingReference(item.id) }
        Button(lang.t(item.isFavorite ? "nook.design.action.unfavorite" : "nook.design.action.favorite")) {
            kit.references.toggleFavorite(item.id)
        }
        Divider()
        Button(lang.t("nook.design.action.moveFirst")) {
            withMotion(Motion.reflow) { kit.references.move(item.id, to: 0) }
        }
        Button(lang.t("nook.design.action.moveBack")) {
            withMotion(Motion.reflow) { kit.references.nudge(item.id, by: -1) }
        }
        Button(lang.t("nook.design.action.moveForward")) {
            withMotion(Motion.reflow) { kit.references.nudge(item.id, by: 1) }
        }
        Divider()
        Button(lang.t("nook.design.action.reveal")) {
            NSWorkspace.shared.activateFileViewerSelecting([kit.references.fileURL(for: item)])
        }
        Button(lang.t("nook.design.action.remove")) {
            withMotion(Motion.reflow) { _ = kit.removeReference(item.id) }
        }
    }
}

// MARK: - Renaming

/// The field a picture's name is typed into. Return keeps the name, and
/// Escape leaves it as it was.
private struct NookDesignRenameRow: View {
    var kit: NookDesignKit
    let item: NookDesignReference
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        let lang = LanguageManager.shared
        HStack(spacing: 6) {
            NookDesignField(text: $text, prompt: lang.t("nook.design.reference.namePrompt"), onSubmit: commit)
                .focused($isFocused)
                .onKeyPress(.escape) {
                    finish()
                    return .handled
                }
            Button(action: commit) {
                NookDesignChipLabel(text: lang.t("nook.design.action.done"), isOn: true)
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            text = item.name
            isFocused = true
        }
        // The island stays open while a new name is typed and not kept
        // (D20). The field starts with the saved name, which holds nothing.
        .onChange(of: text) { _, typed in
            kit.nook?.setDraft(.designName, isUnsaved: NookDesignReferenceRules.isUnsavedName(typed, saved: item.name))
        }
        .onDisappear { kit.nook?.setDraft(.designName, isUnsaved: false) }
    }

    private func commit() {
        kit.references.rename(item.id, to: text)
        finish()
    }

    private func finish() {
        kit.nook?.setDraft(.designName, isUnsaved: false)
        kit.renamingReferenceID = nil
    }
}
