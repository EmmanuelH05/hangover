import SwiftUI

/// The color side of the card: the active palette's swatches, one click
/// each to copy, then the colors the eyedropper picked. Medium adds the
/// palette and format switches, and large adds names, every palette as a
/// chip and a field to type a color into.
struct NookDesignColorsTab: View {
    var kit: NookDesignKit
    @Environment(\.nookWidgetSize) private var size

    var body: some View {
        let palette = kit.palettes.activePalette
        let swatches = NookDesignLibrary.compactOrder(palette?.swatches ?? [])
        // Small keeps the tighter gap: the pill may have a line of its own above.
        VStack(alignment: .leading, spacing: size == .small ? 6 : 8) {
            if size == .large {
                NookDesignPaletteChips(kit: kit)
            }
            if swatches.isEmpty {
                emptyState
            } else if size == .large {
                NookDesignSwatchGrid(kit: kit, swatches: swatches)
            } else {
                NookDesignSwatchRow(kit: kit, swatches: swatches, side: NookDesignCardLayout.swatchSide(for: size))
            }
            if size == .large {
                NookDesignQuickAdd(kit: kit)
                    .frame(height: 24)
            }
            NookDesignRecentRow(kit: kit, showsSwitches: size != .small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        Text(LanguageManager.shared.t(size == .small ? "nook.design.colors.empty.short" : "nook.design.colors.empty.long"))
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.4))
            .lineLimit(size == .large ? 3 : 2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(
                maxWidth: .infinity,
                minHeight: NookDesignCardLayout.swatchSide(for: size),
                maxHeight: size == .large ? .infinity : nil,
                alignment: .leading
            )
    }
}

// MARK: - Swatches

/// One row of swatches. What does not fit hides behind a "+N" tile that
/// opens the palette editor.
private struct NookDesignSwatchRow: View {
    var kit: NookDesignKit
    let swatches: [NookDesignSwatch]
    let side: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let capacity = NookDesignCardLayout.capacity(width: proxy.size.width, side: side)
            let row = NookDesignCardLayout.visible(swatches, capacity: capacity)
            HStack(spacing: NookDesignCardLayout.spacing) {
                ForEach(row.shown) { swatch in
                    NookDesignSwatchButton(kit: kit, swatch: swatch, side: side, showsName: false)
                }
                if row.hidden > 0 {
                    NookDesignMoreButton(kit: kit, count: row.hidden, side: side)
                }
            }
        }
        .frame(height: side)
    }
}

/// Two rows of swatches with their names under them.
private struct NookDesignSwatchGrid: View {
    var kit: NookDesignKit
    let swatches: [NookDesignSwatch]

    private static let side: CGFloat = 30
    private static let tileWidth: CGFloat = 44
    private static let rowCount = 2

    var body: some View {
        GeometryReader { proxy in
            let columns = max(1, NookDesignCardLayout.capacity(width: proxy.size.width, side: Self.tileWidth))
            let grid = NookDesignCardLayout.visible(swatches, capacity: columns * Self.rowCount)
            let cells = grid.shown.map(Cell.swatch) + (grid.hidden > 0 ? [Cell.more(grid.hidden)] : [])
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<Self.rowCount, id: \.self) { row in
                    HStack(alignment: .top, spacing: NookDesignCardLayout.spacing) {
                        ForEach(cells.dropFirst(row * columns).prefix(columns)) { cell in
                            switch cell {
                            case let .swatch(swatch):
                                NookDesignSwatchButton(kit: kit, swatch: swatch, side: Self.side, showsName: true)
                                    .frame(width: Self.tileWidth)
                            case let .more(count):
                                NookDesignMoreButton(kit: kit, count: count, side: Self.side)
                                    .frame(width: Self.tileWidth, alignment: .top)
                            }
                        }
                    }
                    .frame(height: 45, alignment: .top)
                }
            }
        }
        .frame(height: 98)
    }

    private enum Cell: Identifiable {
        case swatch(NookDesignSwatch)
        case more(Int)

        var id: String {
            switch self {
            case let .swatch(swatch): swatch.id.uuidString
            case .more: "more"
            }
        }
    }
}

/// A swatch that copies its color on a click. A right click lists the
/// other formats and what else can be done with it.
private struct NookDesignSwatchButton: View {
    var kit: NookDesignKit
    let swatch: NookDesignSwatch
    let side: CGFloat
    let showsName: Bool
    @Environment(\.nookDesignIsStill) private var isStill

    var body: some View {
        let lang = LanguageManager.shared
        let value = kit.copyFormat.text(for: swatch.color)
        let title = swatch.name.isEmpty ? value : "\(swatch.name), \(value)"
        let button = Button {
            withMotion(Motion.selection) { _ = kit.copy(swatch.color, from: swatch.id) }
        } label: {
            VStack(spacing: 3) {
                NookDesignSwatchChip(
                    color: swatch.color,
                    side: side,
                    isFavorite: swatch.isFavorite,
                    isJustCopied: kit.justCopiedID == swatch.id
                )
                if showsName {
                    Text(swatch.name.isEmpty ? swatch.color.hex(includesHash: false) : swatch.name)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.white.opacity(swatch.name.isEmpty ? 0.35 : 0.6))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lang.t("nook.design.action.copyValue", title))

        if isStill {
            button
        } else {
            button
                .help(title)
                .contextMenu {
                    ForEach(NookDesignColorFormat.allCases) { format in
                        Button(lang.t("nook.design.action.copyValue", format.text(for: swatch.color))) {
                            kit.copy(swatch.color, as: format, from: swatch.id)
                        }
                    }
                    Divider()
                    Button(lang.t(swatch.isFavorite ? "nook.design.action.unfavorite" : "nook.design.action.favorite")) {
                        withMotion(Motion.reflow) { kit.palettes.toggleFavorite(swatch.id) }
                    }
                    Button(lang.t("nook.design.action.moveBack")) {
                        withMotion(Motion.reflow) { kit.palettes.nudgeSwatch(swatch.id, by: -1) }
                    }
                    Button(lang.t("nook.design.action.moveForward")) {
                        withMotion(Motion.reflow) { kit.palettes.nudgeSwatch(swatch.id, by: 1) }
                    }
                    Button(lang.t("nook.design.action.editPalettes")) { kit.showPaletteEditor() }
                    Divider()
                    Button(lang.t("nook.design.action.remove")) {
                        withMotion(Motion.reflow) { kit.palettes.removeSwatch(swatch.id) }
                    }
                }
        }
    }
}

/// The "+N" tile. It opens the palette editor, where every color shows.
private struct NookDesignMoreButton: View {
    var kit: NookDesignKit
    let count: Int
    let side: CGFloat

    var body: some View {
        let label = LanguageManager.shared.t("nook.design.action.showAll", count)
        Button {
            kit.showPaletteEditor()
        } label: {
            NookDesignMoreTile(count: count, side: side)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Palettes

/// Every palette as a chip, the active one lit. In a still picture, and
/// while they all fit, the chips sit in a plain row.
private struct NookDesignPaletteChips: View {
    var kit: NookDesignKit
    @Environment(\.nookDesignIsStill) private var isStill

    var body: some View {
        let palettes = kit.palettes.palettes
        let activeID = kit.palettes.activePalette?.id
        Group {
            if palettes.isEmpty {
                Text(LanguageManager.shared.t("nook.design.palette.none"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if isStill {
                chips(Array(palettes.prefix(4)), activeID: activeID)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ViewThatFits(in: .horizontal) {
                    chips(palettes, activeID: activeID)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ScrollView(.horizontal, showsIndicators: false) {
                        chips(palettes, activeID: activeID)
                    }
                }
            }
        }
        .frame(height: 22)
    }

    private func chips(_ palettes: [NookDesignPalette], activeID: UUID?) -> some View {
        HStack(spacing: 5) {
            ForEach(palettes) { palette in
                let name = palette.name.isEmpty ? LanguageManager.shared.t("nook.design.palette.untitled") : palette.name
                Button {
                    withMotion(Motion.selection) { kit.palettes.setActivePalette(palette.id) }
                } label: {
                    NookDesignChipLabel(text: name, isOn: palette.id == activeID)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
                .accessibilityAddTraits(palette.id == activeID ? .isSelected : [])
            }
        }
    }
}

// MARK: - Typing a color

/// A field that takes HEX, RGB or HSL and adds the color on Return. The
/// dot beside it shows the color as soon as the text reads as one.
private struct NookDesignQuickAdd: View {
    var kit: NookDesignKit
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        let lang = LanguageManager.shared
        let parsed = NookDesignColorParser.parse(text)
        HStack(spacing: 6) {
            NookDesignField(text: $text, prompt: lang.t("nook.design.add.prompt"), onSubmit: add)
                .focused($isFocused)
            if let parsed {
                NookDesignSwatchChip(color: parsed, side: 18, isRound: true)
                    .accessibilityHidden(true)
            }
            Button(action: add) {
                NookDesignChipLabel(text: lang.t("nook.design.add.button"), isOn: parsed != nil)
            }
            .buttonStyle(.plain)
            .disabled(parsed == nil)
            .help(lang.t("nook.design.add.help"))
        }
        // The island stays open while a color is typed and not added (D20).
        // A focused field with nothing in it holds nothing.
        .onChange(of: text) { _, typed in kit.nook?.setDraft(.designColor, isUnsaved: NookDraft.isUnsaved(typed)) }
        .onDisappear { kit.nook?.setDraft(.designColor, isUnsaved: false) }
    }

    private func add() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        switch kit.addColor(text: text) {
        case .added, .duplicate: text = ""
        case .notAColor, .full, .unavailable: break
        }
    }
}

// MARK: - Recent picks

/// The colors the eyedropper picked, newest first, and at medium and
/// large the palette and format switches at the far end.
private struct NookDesignRecentRow: View {
    var kit: NookDesignKit
    let showsSwitches: Bool
    @Environment(\.nookDesignIsStill) private var isStill

    private static let side: CGFloat = 16

    var body: some View {
        let lang = LanguageManager.shared
        let recents = kit.palettes.recents
        HStack(spacing: 5) {
            if recents.isEmpty {
                Text(lang.t("nook.design.recents.empty"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
                    .help(lang.t("nook.design.recents.title"))
                    .accessibilityLabel(lang.t("nook.design.recents.title"))
                ForEach(recents.prefix(showsSwitches ? 10 : 7)) { recent in
                    recentButton(recent)
                }
            }
            Spacer(minLength: 4)
            if showsSwitches {
                switches
            }
        }
        // A line shorter at small, which keeps room for the pill's line above.
        .frame(height: showsSwitches ? 20 : 18)
    }

    private func recentButton(_ recent: NookDesignRecentColor) -> some View {
        let lang = LanguageManager.shared
        let value = kit.copyFormat.text(for: recent.color)
        let button = Button {
            withMotion(Motion.selection) { _ = kit.copy(recent.color, from: recent.id) }
        } label: {
            NookDesignSwatchChip(
                color: recent.color,
                side: Self.side,
                isRound: true,
                isJustCopied: kit.justCopiedID == recent.id
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lang.t("nook.design.action.copyValue", value))

        return Group {
            if isStill {
                button
            } else {
                button
                    .help(value)
                    .contextMenu {
                        ForEach(NookDesignColorFormat.allCases) { format in
                            Button(lang.t("nook.design.action.copyValue", format.text(for: recent.color))) {
                                kit.copy(recent.color, as: format, from: recent.id)
                            }
                        }
                        Divider()
                        Button(lang.t("nook.design.action.saveToPalette")) { kit.addColor(recent.color) }
                        Button(lang.t("nook.design.action.remove")) {
                            withMotion(Motion.reflow) { kit.palettes.removeRecent(recent.id) }
                        }
                        Button(lang.t("nook.design.action.clearRecents")) {
                            withMotion(Motion.reflow) { kit.palettes.clearRecents() }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var switches: some View {
        let lang = LanguageManager.shared
        let palettes = kit.palettes.palettes
        if palettes.count > 1, let active = kit.palettes.activePalette {
            let name = active.name.isEmpty ? lang.t("nook.design.palette.untitled") : active.name
            Button {
                withMotion(Motion.selection) { kit.palettes.selectNextPalette() }
            } label: {
                NookDesignChipLabel(text: NookDesignCardLayout.chipText(name))
            }
            .buttonStyle(.plain)
            .help(lang.t("nook.design.action.nextPalette"))
            .accessibilityLabel(lang.t("nook.design.action.nextPalette"))
            .accessibilityValue(name)
        }
        Button {
            kit.copyFormat = kit.copyFormat.next
        } label: {
            NookDesignChipLabel(text: kit.copyFormat.shortTitle)
        }
        .buttonStyle(.plain)
        .help(lang.t("nook.design.action.nextFormat"))
        .accessibilityLabel(lang.t("nook.design.action.nextFormat"))
        .accessibilityValue(lang.t(kit.copyFormat.titleKey))
    }
}
