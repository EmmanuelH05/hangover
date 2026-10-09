import SwiftUI

/// What sits over the live mirror while the user places stickers: the
/// drag, resize and remove handles. Never part of a photo. It only exists
/// while the picker is up, which leaves the picture alone the rest of the
/// time.
struct NookMirrorDecorationEditor: View {
    var nook: NookModel

    fileprivate static let space = "nook.mirror.decorations.editor"

    var body: some View {
        if nook.isDecoratingMirror {
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    // A click on the bare picture lets go of the sticker.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { nook.selectedMirrorStickerID = nil }
                    ForEach(nook.mirrorDecorations.stickers) { sticker in
                        NookMirrorStickerGrip(
                            nook: nook,
                            sticker: sticker,
                            pictureSize: size,
                            isSelected: nook.selectedMirrorStickerID == sticker.id
                        )
                    }
                    if let selected = nook.mirrorDecorations.stickers.first(where: { $0.id == nook.selectedMirrorStickerID }) {
                        NookMirrorStickerHandles(nook: nook, sticker: selected, pictureSize: size)
                    }
                }
                .coordinateSpace(.named(Self.space))
            }
        }
    }
}

/// The part of a sticker that takes the pointer: a clear square over it
/// that moves it, with a dashed edge while it is the selected one.
private struct NookMirrorStickerGrip: View {
    var nook: NookModel
    var sticker: NookMirrorSticker
    var pictureSize: CGSize
    var isSelected: Bool

    /// The sticker as it was when the drag began. Moves are measured from
    /// it, which keeps a long drag from drifting.
    @State private var dragStart: NookMirrorSticker?

    var body: some View {
        let rect = NookMirrorDecorationLayout.rect(of: sticker, in: pictureSize)
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.white.opacity(0.001))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .frame(width: rect.width, height: rect.height)
            .contentShape(Rectangle())
            .rotationEffect(.degrees(sticker.rotation))
            .position(x: rect.midX, y: rect.midY)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named(NookMirrorDecorationEditor.space))
                    .onChanged { value in
                        let start = dragStart ?? sticker
                        if dragStart == nil {
                            dragStart = sticker
                            nook.selectedMirrorStickerID = sticker.id
                        }
                        nook.replaceMirrorSticker(
                            NookMirrorDecorationLayout.moved(start, by: value.translation, in: pictureSize)
                        )
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .onTapGesture { nook.selectedMirrorStickerID = sticker.id }
            .accessibilityLabel(NookMirrorDesigns.sticker(sticker.designID).map { LanguageManager.shared.t($0.nameKey) } ?? "")
    }
}

/// The three small buttons on the selected sticker's corners: remove,
/// next color, and the one that resizes and turns it.
private struct NookMirrorStickerHandles: View {
    var nook: NookModel
    var sticker: NookMirrorSticker
    var pictureSize: CGSize

    @State private var reshapeStart: NookMirrorSticker?

    private static let chip: CGFloat = 16
    private static let hitArea: CGFloat = 22

    var body: some View {
        let lang = LanguageManager.shared
        let hasColors = (NookMirrorDesigns.sticker(sticker.designID)?.variants ?? 1) > 1
        ZStack {
            Button {
                nook.removeMirrorSticker(sticker.id)
            } label: {
                chip("xmark")
            }
            .buttonStyle(.plain)
            .help(lang.t("nook.mirror.decorations.sticker.remove"))
            .accessibilityLabel(lang.t("nook.mirror.decorations.sticker.remove"))
            .position(place(CGPoint(x: -1, y: -1)))

            if hasColors {
                Button {
                    nook.cycleMirrorStickerVariant(sticker.id)
                } label: {
                    chip("paintpalette.fill")
                }
                .buttonStyle(.plain)
                .help(lang.t("nook.mirror.decorations.sticker.color"))
                .accessibilityLabel(lang.t("nook.mirror.decorations.sticker.color"))
                .position(place(CGPoint(x: 1, y: -1)))
            }

            chip("arrow.up.left.and.arrow.down.right")
                .help(lang.t("nook.mirror.decorations.sticker.resize"))
                .accessibilityLabel(lang.t("nook.mirror.decorations.sticker.resize"))
                .position(place(CGPoint(x: 1, y: 1)))
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named(NookMirrorDecorationEditor.space))
                        .onChanged { value in
                            let start = reshapeStart ?? sticker
                            if reshapeStart == nil { reshapeStart = sticker }
                            nook.replaceMirrorSticker(
                                NookMirrorDecorationLayout.reshaped(
                                    start,
                                    handleTranslation: value.translation,
                                    in: pictureSize
                                )
                            )
                        }
                        .onEnded { _ in reshapeStart = nil }
                )
        }
    }

    /// Where a corner's button goes: on the turned corner, pulled back
    /// inside the picture when the sticker hangs over its edge.
    private func place(_ corner: CGPoint) -> CGPoint {
        let rect = NookMirrorDecorationLayout.rect(of: sticker, in: pictureSize)
        let offset = NookMirrorDecorationLayout.cornerOffset(of: sticker, corner: corner, in: pictureSize)
        return NookMirrorDecorationLayout.reachable(
            CGPoint(x: rect.midX + offset.width, y: rect.midY + offset.height),
            in: pictureSize,
            inset: Self.hitArea / 2
        )
    }

    private func chip(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(Color.black.opacity(0.8))
            .frame(width: Self.chip, height: Self.chip)
            .background(Circle().fill(Color.white))
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
            .frame(width: Self.hitArea, height: Self.hitArea)
            .contentShape(Circle())
    }
}

/// The mirror's corner button that opens the decoration picker.
struct NookMirrorDecorationButton: View {
    var nook: NookModel

    /// The same round chip as the bulb and the close button beside it.
    private static let hitArea: CGFloat = 22

    var body: some View {
        // No picture, nothing to decorate: the button waits for the camera.
        if NookMirrorController.shared.authorization == .authorized, NookMirrorController.shared.hasCamera {
            button
        }
    }

    private var button: some View {
        let lang = LanguageManager.shared
        let isOn = nook.isDecoratingMirror
        let label = lang.t(isOn ? "nook.mirror.decorations.button.close" : "nook.mirror.decorations.button.open")
        return Button {
            withMotion(Motion.reflow) {
                if isOn {
                    nook.stopDecoratingMirror()
                } else {
                    nook.isDecoratingMirror = true
                }
            }
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isOn ? Color.pink : Color.white.opacity(0.9))
                .frame(width: Self.hitArea, height: Self.hitArea)
                .background(Circle().fill(Color.black.opacity(0.55)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        // The decorations stay as they are while the booth takes its
        // pictures: all four must show the same thing.
        .disabled(nook.photoBooth.isRunning)
        .opacity(nook.photoBooth.isRunning ? 0.35 : 1)
    }
}
