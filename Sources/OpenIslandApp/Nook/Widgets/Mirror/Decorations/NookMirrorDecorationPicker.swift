import SwiftUI

/// The picker under the mirror: a frame to put around the picture and
/// stickers to drop on it. It sits under the mirror and not over it, which
/// keeps the whole picture in view while things are placed.
struct NookMirrorDecorationPicker: View {
    var nook: NookModel

    enum Tab: String, CaseIterable {
        case stickers
        case frames

        var titleKey: String {
            switch self {
            case .stickers: "nook.mirror.decorations.tab.stickers"
            case .frames: "nook.mirror.decorations.tab.frames"
            }
        }
    }

    /// The tab to start on.
    var startingTab: Tab = .stickers
    /// False lays the tiles out with no scroll view and cuts off what does
    /// not fit. `ImageRenderer` cannot draw a scroll view, and a contact
    /// sheet of the picker turns this off.
    var isScrollable = true

    @State private var chosenTab: Tab?

    private var tab: Tab { chosenTab ?? startingTab }

    private typealias Layout = NookMirrorDecorationLayout

    var body: some View {
        let lang = LanguageManager.shared
        let decorations = nook.mirrorDecorations
        VStack(spacing: Layout.pickerSpacing) {
            header(lang, decorations)
                .frame(height: Layout.pickerHeaderHeight)
            if isScrollable {
                ScrollView(.vertical) { tiles(lang, decorations) }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: Layout.tileAreaHeight)
            } else {
                tiles(lang, decorations)
                    .frame(height: Layout.tileAreaHeight, alignment: .top)
                    .clipped()
            }
        }
        .padding(Layout.pickerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NookCardBackground())
        // The mirror going away takes the picker with it. Without this the
        // picker would come back by itself with the next mirror.
        .onDisappear { nook.stopDecoratingMirror() }
    }

    @ViewBuilder
    private func tiles(_ lang: LanguageManager, _ decorations: NookMirrorDecorationSet) -> some View {
        switch tab {
        case .stickers: stickerGrid(lang)
        case .frames: frameGrid(lang, decorations)
        }
    }

    // MARK: Header

    private func header(_ lang: LanguageManager, _ decorations: NookMirrorDecorationSet) -> some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button {
                    withMotion(Motion.selection) { chosenTab = item }
                } label: {
                    Text(lang.t(item.titleKey))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(tab == item ? 0.95 : 0.55))
                        .padding(.horizontal, 10)
                        .frame(height: Layout.pickerHeaderHeight)
                        .background(Capsule().fill(Color.white.opacity(tab == item ? 0.16 : 0.05)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
            Text(note(lang, decorations))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.leading, 4)
            Spacer(minLength: 4)
            Button(lang.t("nook.mirror.decorations.clearAll")) {
                nook.clearMirrorDecorations()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(decorations.isEmpty ? 0.25 : 0.7))
            .disabled(decorations.isEmpty)
            Button {
                withMotion(Motion.reflow) { nook.stopDecoratingMirror() }
            } label: {
                Text(lang.t("nook.mirror.decorations.done"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.horizontal, 10)
                    .frame(height: Layout.pickerHeaderHeight)
                    .background(Capsule().fill(Color.pink.opacity(0.55)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    /// The short line beside the tabs: how to start, how many are on, or
    /// that the mirror is full.
    private func note(_ lang: LanguageManager, _ decorations: NookMirrorDecorationSet) -> String {
        NookMirrorDecorationPickerNote.text(
            tab: tab,
            stickerCount: decorations.stickers.count,
            translate: { key, numbers in
                switch numbers.count {
                case 1: lang.t(key, numbers[0])
                case 2: lang.t(key, numbers[0], numbers[1])
                default: lang.t(key)
                }
            }
        )
    }

    // MARK: Tiles

    private func stickerGrid(_ lang: LanguageManager) -> some View {
        let columns = [GridItem(.adaptive(minimum: Layout.stickerTileSide, maximum: Layout.stickerTileSide), spacing: Layout.tileSpacing)]
        let isFull = nook.mirrorDecorations.stickers.count >= Layout.maxStickers
        return LazyVGrid(columns: columns, alignment: .leading, spacing: Layout.tileSpacing) {
            ForEach(NookMirrorDesigns.stickers) { design in
                Button {
                    nook.addMirrorSticker(design.id)
                } label: {
                    NookMirrorStickerThumbnail(design: design)
                        .frame(width: Layout.stickerTileSide, height: Layout.stickerTileSide)
                        .background(tileBackground(isSelected: false))
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(isFull)
                .opacity(isFull ? 0.4 : 1)
                .help(lang.t(design.nameKey))
                .accessibilityLabel(lang.t(design.nameKey))
            }
        }
    }

    private func frameGrid(_ lang: LanguageManager, _ decorations: NookMirrorDecorationSet) -> some View {
        let size = Layout.frameTileSize
        let columns = [GridItem(.adaptive(minimum: size.width, maximum: size.width), spacing: Layout.tileSpacing)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: Layout.tileSpacing) {
            Button {
                nook.setMirrorFrame(nil)
            } label: {
                Text(lang.t("nook.mirror.decorations.none"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: size.width, height: size.height)
                    .background(tileBackground(isSelected: decorations.frameID == nil))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityAddTraits(decorations.frameID == nil ? .isSelected : [])
            ForEach(NookMirrorDesigns.frames) { design in
                let isSelected = decorations.frameID == design.id
                Button {
                    nook.setMirrorFrame(isSelected ? nil : design.id)
                } label: {
                    NookMirrorFrameThumbnail(design: design)
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(tileRing(isSelected: isSelected))
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .help(lang.t(design.nameKey))
                .accessibilityLabel(lang.t(design.nameKey))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func tileBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(0.07))
            .overlay(tileRing(isSelected: isSelected))
    }

    private func tileRing(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(isSelected ? Color.pink.opacity(0.9) : Color.white.opacity(0.08), lineWidth: isSelected ? 1.5 : 0.5)
    }
}

/// Words for the line beside the picker's tabs. Pure, which lets a test
/// read them without a view.
enum NookMirrorDecorationPickerNote {
    static func text(
        tab: NookMirrorDecorationPicker.Tab,
        stickerCount: Int,
        translate: (_ key: String, _ numbers: [Int]) -> String
    ) -> String {
        let most = NookMirrorDecorationLayout.maxStickers
        switch tab {
        case .frames:
            return translate("nook.mirror.decorations.hint.frames", [])
        case .stickers where stickerCount >= most:
            return translate("nook.mirror.decorations.full", [most])
        case .stickers where stickerCount == 0:
            return translate("nook.mirror.decorations.hint.stickers", [])
        case .stickers:
            return translate("nook.mirror.decorations.count", [stickerCount, most])
        }
    }
}

/// One sticker design, small, in its first colorway.
struct NookMirrorStickerThumbnail: View {
    var design: NookMirrorStickerDesign
    var variant = 0

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height) * 0.78
            let rect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
            design.draw(NookDecorationPen(context: context, rect: rect), design.wrapped(variant))
        }
        .accessibilityHidden(true)
    }
}

/// One frame design, small, over a stand-in for the camera picture.
struct NookMirrorFrameThumbnail: View {
    var design: NookMirrorFrameDesign

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(
                Path(rect),
                with: .linearGradient(
                    Gradient(colors: [Color(white: 0.42), Color(white: 0.26)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
            design.draw(NookDecorationPen(context: context, rect: rect))
        }
        .accessibilityHidden(true)
    }
}
