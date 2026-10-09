import CoreGraphics
import Foundation

/// Rules for placing stickers and sizing the picker. A plain enum and not
/// part of a view, which keeps them callable from the window-sizing math
/// and from tests without the main actor.
enum NookMirrorDecorationLayout {
    /// The most stickers one mirror holds.
    static let maxStickers = 12
    /// Width of a sticker fresh from the picker, as a fraction of the
    /// picture's width.
    static let defaultStickerWidth = 0.125
    /// From a sticker that still reads to one that covers most of the
    /// picture's height.
    static let stickerWidthRange: ClosedRange<Double> = 0.07...0.34

    // MARK: The picker under the mirror

    static let pickerPadding: CGFloat = 8
    static let pickerHeaderHeight: CGFloat = 22
    static let pickerSpacing: CGFloat = 6
    static let tileSpacing: CGFloat = 6
    static let stickerTileSide: CGFloat = 40
    static let frameTileSize = CGSize(width: 64, height: 40)
    /// Rows of tiles in view. More rows scroll.
    static let visibleRows = 2

    static var tileAreaHeight: CGFloat {
        CGFloat(visibleRows) * stickerTileSide + CGFloat(visibleRows - 1) * tileSpacing
    }

    static var pickerHeight: CGFloat {
        pickerPadding * 2 + pickerHeaderHeight + pickerSpacing + tileAreaHeight
    }

    /// Height the picker adds to the Nook page: itself and one row gap.
    static var pickerPageHeight: CGFloat { pickerHeight + NookWidgetLayout.rowSpacing }

    /// The picker only exists under a mirror that is showing.
    static func isPickerShown(isDecorating: Bool, mirrorHeight: CGFloat?) -> Bool {
        isDecorating && mirrorHeight != nil
    }

    /// How many tiles of this width fit side by side in the picker.
    static func columns(tileWidth: CGFloat, pickerWidth: CGFloat) -> Int {
        let inner = pickerWidth - pickerPadding * 2
        guard tileWidth > 0 else { return 1 }
        return max(1, Int((inner + tileSpacing) / (tileWidth + tileSpacing)))
    }

    // MARK: Stickers on the picture

    /// The sticker kept on the picture and inside the size limits. Numbers
    /// that are not finite fall back to the middle at the default size.
    static func clamped(_ sticker: NookMirrorSticker) -> NookMirrorSticker {
        var fitted = sticker
        fitted.x = unit(sticker.x, fallback: 0.5)
        fitted.y = unit(sticker.y, fallback: 0.5)
        fitted.width = sticker.width.isFinite
            ? min(max(sticker.width, stickerWidthRange.lowerBound), stickerWidthRange.upperBound)
            : defaultStickerWidth
        fitted.rotation = normalizedRotation(sticker.rotation)
        fitted.variant = max(0, sticker.variant)
        return fitted
    }

    private static func unit(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : fallback
    }

    /// Degrees brought into -180 up to and including 180.
    static func normalizedRotation(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let turned = degrees.truncatingRemainder(dividingBy: 360)
        if turned > 180 { return turned - 360 }
        if turned <= -180 { return turned + 360 }
        return turned
    }

    /// The square a sticker is drawn in, before it is turned. A sticker is
    /// as tall as it is wide, and its width follows the picture's width.
    static func rect(of sticker: NookMirrorSticker, in size: CGSize) -> CGRect {
        let side = CGFloat(sticker.width) * size.width
        let center = CGPoint(x: CGFloat(sticker.x) * size.width, y: CGFloat(sticker.y) * size.height)
        return CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    }

    /// Where the next sticker lands. Each one steps a little down and to
    /// the right of the last, which keeps a new sticker from hiding the
    /// one under it, and the walk starts over before it leaves the picture.
    static func dropPoint(count: Int) -> (x: Double, y: Double) {
        let step = Double(max(0, count) % 6)
        return (x: 0.3 + step * 0.08, y: 0.3 + step * 0.08)
    }

    /// The sticker moved by a drag across a picture of this size.
    static func moved(_ start: NookMirrorSticker, by translation: CGSize, in size: CGSize) -> NookMirrorSticker {
        guard size.width > 0, size.height > 0 else { return start }
        var moved = start
        moved.x = start.x + Double(translation.width / size.width)
        moved.y = start.y + Double(translation.height / size.height)
        return clamped(moved)
    }

    /// From the sticker's center to one of its corners, after it is turned.
    /// `corner` is -1 or 1 on each axis.
    static func cornerOffset(of sticker: NookMirrorSticker, corner: CGPoint, in size: CGSize) -> CGSize {
        let half = CGFloat(sticker.width) * size.width / 2
        let angle = CGFloat(sticker.rotation) * .pi / 180
        let x = corner.x * half
        let y = corner.y * half
        return CGSize(
            width: x * cos(angle) - y * sin(angle),
            height: x * sin(angle) + y * cos(angle)
        )
    }

    /// The sticker resized and turned by a drag on its bottom right corner:
    /// the corner follows the pointer, and the center stays put.
    static func reshaped(
        _ start: NookMirrorSticker,
        handleTranslation: CGSize,
        in size: CGSize
    ) -> NookMirrorSticker {
        let from = cornerOffset(of: start, corner: CGPoint(x: 1, y: 1), in: size)
        let to = CGSize(width: from.width + handleTranslation.width, height: from.height + handleTranslation.height)
        let fromLength = hypot(from.width, from.height)
        let toLength = hypot(to.width, to.height)
        guard fromLength > 0, toLength > 0 else { return start }
        var reshaped = start
        reshaped.width = start.width * Double(toLength / fromLength)
        let turn = atan2(to.height, to.width) - atan2(from.height, from.width)
        reshaped.rotation = start.rotation + Double(turn) * 180 / .pi
        return clamped(reshaped)
    }

    /// A handle's place kept inside the picture, where it can be reached.
    static func reachable(_ point: CGPoint, in size: CGSize, inset: CGFloat) -> CGPoint {
        CGPoint(
            x: min(max(point.x, inset), max(inset, size.width - inset)),
            y: min(max(point.y, inset), max(inset, size.height - inset))
        )
    }
}
