import SwiftUI

/// The palette editor, which lives in a floating panel and never in the
/// card: the list of palettes on the left, and on the right the chosen
/// palette's colors, each with a name, a favorite mark, its place in the
/// order and a way out. Colors are added by typing HEX, RGB or HSL.
///
/// It is drawn from plain shapes, the island's dark look, which also lets
/// a still picture of it be made for review.
struct NookDesignPaletteEditor: View {
    var kit: NookDesignKit
    var onImport: () -> Void = {}
    var onExport: (_ paletteIDs: [UUID]) -> Void = { _ in }
    var isStill = false

    static let idealSize = CGSize(width: 620, height: 440)
    static let minimumSize = CGSize(width: 540, height: 360)

    @State private var colorText = ""
    @State private var colorName = ""
    @State private var lastResult: NookDesignEntryResult?
    /// The palette whose delete button was pressed once. A second press
    /// deletes it.
    @State private var confirmingDeleteID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 176)
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 0.5)
            detail
        }
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
        .background(V6Palette.ink)
        // What an import, an export or a copy came to is said here too: the
        // card is not on screen while this window is.
        .overlay(alignment: .bottom) {
            if let notice = kit.notice {
                NookDesignNoticeBar(notice: notice)
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }
        }
        .motionAnimation(Motion.hover, value: kit.notice)
        .environment(\.nookDesignIsStill, isStill)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Palettes

    private var sidebar: some View {
        let lang = LanguageManager.shared
        let palettes = kit.palettes.palettes
        let activeID = kit.palettes.activePalette?.id
        return VStack(alignment: .leading, spacing: 8) {
            NookCardHeader(title: lang.t("nook.design.editor.palettes"), systemImage: "paintpalette")
            NookDesignScroll {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(palettes) { palette in
                        paletteRow(palette, isActive: palette.id == activeID)
                    }
                    if palettes.isEmpty {
                        Text(lang.t("nook.design.palette.none"))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(.vertical, 4)
                    }
                }
            }
            Spacer(minLength: 0)
            Button {
                kit.palettes.addPalette(named: lang.t("nook.design.palette.new"))
            } label: {
                NookDesignChipLabel(text: lang.t("nook.design.editor.newPalette"))
            }
            .buttonStyle(.plain)
            HStack(spacing: 6) {
                Button(action: onImport) {
                    NookDesignChipLabel(text: lang.t("nook.design.editor.import"))
                }
                .buttonStyle(.plain)
                .help(lang.t("nook.design.editor.import.help"))
                Button {
                    onExport(palettes.map(\.id))
                } label: {
                    NookDesignChipLabel(text: lang.t("nook.design.editor.exportAll"))
                }
                .buttonStyle(.plain)
                .disabled(palettes.isEmpty)
                .help(lang.t("nook.design.editor.export.help"))
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func paletteRow(_ palette: NookDesignPalette, isActive: Bool) -> some View {
        let lang = LanguageManager.shared
        let name = palette.name.isEmpty ? lang.t("nook.design.palette.untitled") : palette.name
        let isConfirming = confirmingDeleteID == palette.id
        return HStack(spacing: 4) {
            Button {
                confirmingDeleteID = nil
                kit.palettes.setActivePalette(palette.id)
            } label: {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(.white.opacity(isActive ? 0.9 : 0.6))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(palette.swatches.count)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.horizontal, 8)
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(name)
            .accessibilityAddTraits(isActive ? .isSelected : [])
            if isActive {
                Button {
                    // An empty palette goes at once. One with colors in it
                    // asks first.
                    if palette.swatches.isEmpty || isConfirming {
                        confirmingDeleteID = nil
                        kit.palettes.removePalette(palette.id)
                    } else {
                        confirmingDeleteID = palette.id
                    }
                } label: {
                    if isConfirming {
                        NookDesignChipLabel(text: lang.t("nook.design.editor.deleteConfirm"), isOn: true)
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .help(lang.t("nook.design.editor.deletePalette"))
                .accessibilityLabel(lang.t("nook.design.editor.deletePalette"))
                .padding(.trailing, 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(isActive ? 0.1 : 0))
        )
    }

    // MARK: The chosen palette

    @ViewBuilder
    private var detail: some View {
        let lang = LanguageManager.shared
        if let palette = kit.palettes.activePalette {
            let repeats = kit.palettes.library.duplicateSwatchIDs(in: palette.id)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    NookDesignNameField(
                        name: palette.name,
                        prompt: lang.t("nook.design.editor.paletteName"),
                        size: 14,
                        weight: .semibold
                    ) { kit.palettes.renamePalette(palette.id, to: $0) }
                        .id(palette.id)
                        .frame(height: 28)
                    Button {
                        onExport([palette.id])
                    } label: {
                        NookDesignChipLabel(text: lang.t("nook.design.editor.export"))
                    }
                    .buttonStyle(.plain)
                    .disabled(palette.swatches.isEmpty)
                    .help(lang.t("nook.design.editor.export.help"))
                }
                addRow(to: palette)
                if let message = entryMessage {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if palette.swatches.isEmpty {
                    Text(lang.t("nook.design.editor.empty"))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    NookDesignScroll {
                        VStack(spacing: 2) {
                            ForEach(Array(palette.swatches.enumerated()), id: \.element.id) { index, swatch in
                                NookDesignEditorRow(
                                    kit: kit,
                                    swatch: swatch,
                                    isRepeat: repeats.contains(swatch.id),
                                    isFirst: index == 0,
                                    isLast: index == palette.swatches.count - 1
                                )
                            }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                footer(palette: palette, repeats: repeats.count)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "paintpalette")
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.3))
                Text(lang.t("nook.design.editor.noPalette"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                Button {
                    kit.palettes.addPalette(named: lang.t("nook.design.palette.default"))
                } label: {
                    NookDesignChipLabel(text: lang.t("nook.design.editor.newPalette"), isOn: true)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func addRow(to palette: NookDesignPalette) -> some View {
        let lang = LanguageManager.shared
        let parsed = NookDesignColorParser.parse(colorText)
        return HStack(spacing: 6) {
            if let parsed {
                NookDesignSwatchChip(color: parsed, side: 24)
                    .accessibilityHidden(true)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            }
            NookDesignField(text: $colorText, prompt: lang.t("nook.design.add.prompt")) { add(to: palette) }
            NookDesignField(text: $colorName, prompt: lang.t("nook.design.editor.colorName")) { add(to: palette) }
                .frame(width: 112)
            Button {
                add(to: palette)
            } label: {
                NookDesignChipLabel(text: lang.t("nook.design.add.button"), isOn: parsed != nil)
            }
            .buttonStyle(.plain)
            .disabled(parsed == nil)
            .help(lang.t("nook.design.add.help"))
        }
        .frame(height: 28)
    }

    private func add(to palette: NookDesignPalette) {
        guard !colorText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let result = kit.addColor(text: colorText, name: colorName, to: palette.id)
        lastResult = result
        if case .added = result {
            colorText = ""
            colorName = ""
        }
    }

    /// What the last Add had to say, when it did not add.
    private var entryMessage: String? {
        let lang = LanguageManager.shared
        switch lastResult {
        case .notAColor?: return lang.t("nook.design.notice.notAColor")
        case let .duplicate(existing)?:
            let name = existing.name.isEmpty ? existing.color.hex() : existing.name
            return lang.t("nook.design.editor.duplicate", name)
        case .full?: return lang.t("nook.design.notice.paletteFull")
        case .added?, .unavailable?, nil: return nil
        }
    }

    private func footer(palette: NookDesignPalette, repeats: Int) -> some View {
        let lang = LanguageManager.shared
        return VStack(alignment: .leading, spacing: 8) {
            if repeats > 0 {
                HStack(spacing: 8) {
                    Text(lang.t("nook.design.editor.repeats", repeats))
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Button {
                        kit.palettes.removeDuplicates(in: palette.id)
                    } label: {
                        NookDesignChipLabel(text: lang.t("nook.design.editor.removeRepeats"))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 5) {
                Text(lang.t("nook.design.editor.copyAs"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                ForEach(NookDesignColorFormat.allCases) { format in
                    Button {
                        kit.copyFormat = format
                    } label: {
                        NookDesignChipLabel(text: format.shortTitle, isOn: kit.copyFormat == format)
                    }
                    .buttonStyle(.plain)
                    .help(lang.t(format.titleKey))
                    .accessibilityLabel(lang.t(format.titleKey))
                    .accessibilityAddTraits(kit.copyFormat == format ? .isSelected : [])
                }
                Spacer(minLength: 8)
                Button {
                    kit.savesPicksToPalette.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: kit.savesPicksToPalette ? "checkmark.square.fill" : "square")
                            .font(.system(size: 12))
                            .foregroundStyle(kit.savesPicksToPalette ? HangoverAccentSource.tint().highlight(.orange) : Color.white.opacity(0.45))
                        Text(lang.t("nook.design.editor.savePicks"))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(lang.t("nook.design.settings.savePicks.note"))
                .accessibilityAddTraits(kit.savesPicksToPalette ? .isSelected : [])
            }
        }
    }
}

// MARK: - One color

/// One color of the palette being edited.
private struct NookDesignEditorRow: View {
    var kit: NookDesignKit
    let swatch: NookDesignSwatch
    let isRepeat: Bool
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        let lang = LanguageManager.shared
        let value = kit.copyFormat.text(for: swatch.color)
        HStack(spacing: 8) {
            NookDesignSwatchChip(color: swatch.color, side: 24, isJustCopied: kit.justCopiedID == swatch.id)
                .accessibilityHidden(true)
            NookDesignNameField(
                name: swatch.name,
                prompt: lang.t("nook.design.editor.colorName"),
                size: 12,
                weight: .regular
            ) { kit.palettes.renameSwatch(swatch.id, to: $0) }
                .frame(height: 24)
            if isRepeat {
                Text(lang.t("nook.design.editor.repeat"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 5)
                    .frame(height: 16)
                    .background(Capsule().fill(Color.orange.opacity(0.16)))
            }
            Button {
                kit.copy(swatch.color, from: swatch.id)
            } label: {
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .frame(width: 150, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(lang.t("nook.design.action.copyValue", value))
            .accessibilityLabel(lang.t("nook.design.action.copyValue", value))
            rowButton(
                swatch.isFavorite ? "star.fill" : "star",
                lang.t(swatch.isFavorite ? "nook.design.action.unfavorite" : "nook.design.action.favorite"),
                tint: swatch.isFavorite ? .yellow : .white.opacity(0.45)
            ) { kit.palettes.toggleFavorite(swatch.id) }
            rowButton("chevron.up", lang.t("nook.design.action.moveBack")) {
                kit.palettes.nudgeSwatch(swatch.id, by: -1)
            }
            .disabled(isFirst)
            rowButton("chevron.down", lang.t("nook.design.action.moveForward")) {
                kit.palettes.nudgeSwatch(swatch.id, by: 1)
            }
            .disabled(isLast)
            rowButton("trash", lang.t("nook.design.action.remove")) {
                kit.palettes.removeSwatch(swatch.id)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func rowButton(
        _ symbol: String,
        _ label: String,
        tint: Color = .white.opacity(0.45),
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Pieces

/// A name that is typed in place. It is kept on Return and when the field
/// loses the keyboard.
private struct NookDesignNameField: View {
    let name: String
    let prompt: String
    let size: CGFloat
    let weight: Font.Weight
    let onCommit: (String) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool
    @Environment(\.nookDesignIsStill) private var isStill

    var body: some View {
        Group {
            if isStill {
                Text(name.isEmpty ? prompt : name)
                    .foregroundStyle(.white.opacity(name.isEmpty ? 0.3 : 0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("", text: $text, prompt: Text(prompt))
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white.opacity(0.85))
                    .focused($isFocused)
                    .onSubmit { onCommit(text) }
            }
        }
        .font(.system(size: size, weight: weight))
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(isFocused ? 0.1 : 0.05))
        )
        .accessibilityLabel(prompt)
        .onAppear { text = name }
        .onChange(of: name) { _, renamed in
            if !isFocused { text = renamed }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused, text != name { onCommit(text) }
        }
    }
}

/// A scroll view on the screen and a plain stack in a still picture,
/// which `ImageRenderer` cannot draw a scroll view into.
struct NookDesignScroll<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.nookDesignIsStill) private var isStill

    var body: some View {
        if isStill {
            content
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                content
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
