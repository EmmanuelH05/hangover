import CoreGraphics
import Foundation

/// Where a picture sits in its floating panel. Positions are fractions of
/// the panel's picture area, measured from its middle, which makes them
/// hold when the panel is resized.
///
/// `scale` 1 is the fit: the whole picture, as large as the area allows.
/// The picture is never drawn smaller than that, because making the panel
/// smaller does the same job.
struct NookDesignZoom: Equatable, Sendable {
    static let range: ClosedRange<CGFloat> = 1...8
    /// One press of a zoom button.
    static let step: CGFloat = 1.25

    var scale: CGFloat = 1
    /// From the area's middle to the picture's middle.
    var offset: CGSize = .zero

    static let fit = NookDesignZoom()

    var isFit: Bool { scale <= 1 && offset == .zero }

    /// "100%" at the fit, "250%" zoomed in.
    var percentText: String { "\(Int((scale * 100).rounded()))%" }

    /// How far the picture's middle may sit from the area's middle on each
    /// axis before an edge of the picture comes inside the area. `fitted`
    /// is the part of the area the picture covers at the fit, on each
    /// axis, from 0 to 1.
    static func maxOffset(scale: CGFloat, fitted: CGSize) -> CGSize {
        CGSize(
            width: max(0, (fitted.width * scale - 1) / 2),
            height: max(0, (fitted.height * scale - 1) / 2)
        )
    }

    /// The same zoom with its scale in range and the picture pulled back
    /// until it covers the area wherever it can.
    func clamped(fitted: CGSize = CGSize(width: 1, height: 1)) -> NookDesignZoom {
        let scale = min(max(scale.isFinite ? scale : 1, Self.range.lowerBound), Self.range.upperBound)
        let limit = Self.maxOffset(scale: scale, fitted: fitted)
        let x = offset.width.isFinite ? offset.width : 0
        let y = offset.height.isFinite ? offset.height : 0
        return NookDesignZoom(
            scale: scale,
            offset: CGSize(
                width: min(max(x, -limit.width), limit.width),
                height: min(max(y, -limit.height), limit.height)
            )
        )
    }

    /// Zooms to `newScale` and keeps the spot of the picture under
    /// `anchor` where it is. The anchor is a point of the area as a
    /// fraction from its middle: zero is the middle, (0.5, 0.5) a corner.
    func zoomed(
        to newScale: CGFloat,
        around anchor: CGPoint = .zero,
        fitted: CGSize = CGSize(width: 1, height: 1)
    ) -> NookDesignZoom {
        let target = min(max(newScale.isFinite ? newScale : scale, Self.range.lowerBound), Self.range.upperBound)
        guard scale > 0 else { return NookDesignZoom(scale: target).clamped(fitted: fitted) }
        let ratio = target / scale
        let moved = CGSize(
            width: anchor.x - (anchor.x - offset.width) * ratio,
            height: anchor.y - (anchor.y - offset.height) * ratio
        )
        return NookDesignZoom(scale: target, offset: moved).clamped(fitted: fitted)
    }

    func zoomed(
        by factor: CGFloat,
        around anchor: CGPoint = .zero,
        fitted: CGSize = CGSize(width: 1, height: 1)
    ) -> NookDesignZoom {
        zoomed(to: scale * factor, around: anchor, fitted: fitted)
    }

    /// Moves the picture by a fraction of the area.
    func panned(by delta: CGSize, fitted: CGSize = CGSize(width: 1, height: 1)) -> NookDesignZoom {
        NookDesignZoom(
            scale: scale,
            offset: CGSize(width: offset.width + delta.width, height: offset.height + delta.height)
        ).clamped(fitted: fitted)
    }
}

/// What a click on a reference does about its floating panel.
enum NookDesignPanelDecision: Equatable, Sendable {
    /// Its panel is already up. Bring that one forward.
    case focus
    /// Open a panel in this cascade slot.
    case open(slot: Int)
    /// As many panels as there may be are up already.
    case refuse
}

/// Pure rules for the floating reference panels: how many, where, how
/// large, and how they resize. A panel is as large as the user drags it,
/// within the room it has, and the picture is fitted inside its area.
enum NookDesignPanelRules {
    /// Panels that can be up at once.
    static let maxOpenPanels = 6
    /// Longer side of a new panel's picture area.
    static let initialLongSide: CGFloat = 360
    /// The strip of controls needs this much.
    static let minimumWidth: CGFloat = 240
    /// Height of the strip of controls under the picture.
    static let barHeight: CGFloat = 30
    /// The least height the picture area is dragged down to.
    static let minimumAreaHeight: CGFloat = 120
    /// The panel's least height: that area and the strip of controls.
    static let minimumHeight: CGFloat = minimumAreaHeight + barHeight
    /// The picture area of a new panel, and of a panel sent back to the
    /// picture's shape, is never narrower or wider than this for its
    /// height. A picture outside it, such as a long page, is fitted inside
    /// and read by zooming. A panel the user drags is not held to it.
    static let aspectRange: ClosedRange<CGFloat> = 0.5...2.4
    /// Room kept between a new panel and the screen's edges.
    static let screenMargin: CGFloat = 24
    /// How far each new panel sits from the one before.
    static let cascadeStep: CGFloat = 28
    static let opacityRange: ClosedRange<Double> = 0.2...1

    // MARK: How many

    /// `open` maps each panel that is up to its cascade slot.
    static func decision(for id: UUID, open: [UUID: Int]) -> NookDesignPanelDecision {
        if open[id] != nil { return .focus }
        guard open.count < maxOpenPanels else { return .refuse }
        return .open(slot: lowestFreeSlot(open.values))
    }

    /// The first slot no open panel uses. A closed panel's slot is used
    /// again, which keeps the cascade from walking off the screen.
    static func lowestFreeSlot(_ used: some Collection<Int>) -> Int {
        let taken = Set(used)
        var slot = 0
        while taken.contains(slot) { slot += 1 }
        return slot
    }

    // MARK: Shape

    /// The shape of the picture area for a picture of this shape, which is
    /// the shape a new panel opens in.
    static func areaAspect(forPictureAspect aspect: CGFloat) -> CGFloat {
        guard aspect.isFinite, aspect > 0 else { return 1 }
        return min(max(aspect, aspectRange.lowerBound), aspectRange.upperBound)
    }

    /// The part of the picture area the fitted picture covers on each
    /// axis, for a panel of this size. The area is what is left of the
    /// panel above the strip of controls. A picture in the area's own shape
    /// covers all of it, and in any other shape it covers all of one axis
    /// and part of the other.
    static func fittedFraction(pictureAspect: CGFloat, panelSize: CGSize) -> CGSize {
        let whole = CGSize(width: 1, height: 1)
        let areaHeight = panelSize.height - barHeight
        guard pictureAspect.isFinite, pictureAspect > 0,
              panelSize.width.isFinite, areaHeight.isFinite,
              panelSize.width > 0, areaHeight > 0 else { return whole }
        let area = panelSize.width / areaHeight
        return pictureAspect >= area
            ? CGSize(width: 1, height: area / pictureAspect)
            : CGSize(width: pictureAspect / area, height: 1)
    }

    /// The panel's size for a width: the picture area in its shape, with
    /// the strip of controls under it.
    static func panelSize(width: CGFloat, pictureAspect: CGFloat) -> CGSize {
        let area = areaAspect(forPictureAspect: pictureAspect)
        return CGSize(width: width, height: (width / area).rounded() + barHeight)
    }

    /// The panel's width for a height.
    static func panelWidth(height: CGFloat, pictureAspect: CGFloat) -> CGFloat {
        (max(0, height - barHeight) * areaAspect(forPictureAspect: pictureAspect)).rounded()
    }

    /// A new panel's size: the picture area's longer side at
    /// `initialLongSide`, no narrower than the minimum, and no larger
    /// than the room there is.
    static func initialSize(pictureAspect: CGFloat, available: CGSize) -> CGSize {
        let area = areaAspect(forPictureAspect: pictureAspect)
        let width = area >= 1 ? initialLongSide : initialLongSide * area
        return fitted(width: width, pictureAspect: pictureAspect, available: available)
    }

    /// The size a panel opens at: the size it was left at when there is
    /// one, held to the room this screen has, and `initialSize` when there
    /// is none or it cannot be a size.
    static func openingSize(remembered: CGSize?, pictureAspect: CGFloat, available: CGSize) -> CGSize {
        guard let remembered, remembered.width.isFinite, remembered.height.isFinite,
              remembered.width > 0, remembered.height > 0 else {
            return initialSize(pictureAspect: pictureAspect, available: available)
        }
        return resizedSize(proposed: remembered, available: available)
    }

    /// The size a resize lands on: the width and the height the user
    /// dragged to, each held between its minimum and the room there is.
    /// Neither follows the other, and the picture's shape is not asked.
    /// The minimum wins when the room is smaller than it.
    static func resizedSize(proposed: CGSize, available: CGSize) -> CGSize {
        CGSize(
            width: limited(proposed.width, minimum: minimumWidth, maximum: available.width),
            height: limited(proposed.height, minimum: minimumHeight, maximum: available.height)
        )
    }

    private static func limited(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        let wanted = value.isNaN ? minimum : value.rounded()
        let capped = maximum.isNaN ? wanted : min(wanted, maximum.rounded(.down))
        guard capped.isFinite else { return minimum }
        return max(capped, minimum)
    }

    /// The panel sent back to its picture's shape: the width it has now,
    /// and the height the picture area needs at that width. It is held to
    /// the same minimums and room as any other size.
    static func matchedSize(current: CGSize, pictureAspect: CGFloat, available: CGSize) -> CGSize {
        fitted(width: current.width, pictureAspect: pictureAspect, available: available)
    }

    /// The frame of a panel that a button or a double click resized, not a
    /// drag. Its top left corner stays where it is. It moves back onto the
    /// screen only by as much as the new size pushed it off, which keeps a
    /// panel the user left partly off the screen from jumping. The frame is
    /// counted from the bottom left, the way AppKit counts.
    static func frame(keepingTopLeftOf frame: CGRect, resizedTo size: CGSize, in visible: CGRect) -> CGRect {
        var origin = CGPoint(x: frame.minX, y: frame.maxY - size.height)
        let newMaxX = origin.x + size.width
        origin.x -= max(0, newMaxX - max(visible.maxX, frame.maxX))
        origin.y += max(0, min(visible.minY, frame.minY) - origin.y)
        return CGRect(origin: origin, size: size)
    }

    /// The panel size in the picture's shape nearest `width`, at least the
    /// minimum size and fitting in `available`. The minimum wins when the
    /// two disagree.
    private static func fitted(width: CGFloat, pictureAspect: CGFloat, available: CGSize) -> CGSize {
        var width = width.isFinite ? width : initialLongSide
        width = min(width, available.width)
        width = min(width, panelWidth(height: available.height, pictureAspect: pictureAspect))
        width = max(width, minimumWidth)
        let size = panelSize(width: width.rounded(), pictureAspect: pictureAspect)
        return CGSize(width: size.width, height: max(size.height, minimumHeight))
    }

    // MARK: Place

    /// Where a new panel goes: the first at the top right of the screen's
    /// usable area, each later slot one step down and to the left. A slot
    /// that would leave the area starts over from the corner. The point is
    /// the panel's bottom left corner, the way AppKit counts.
    static func frameOrigin(slot: Int, size: CGSize, in visibleFrame: CGRect) -> CGPoint {
        let roomX = max(0, visibleFrame.width - size.width - screenMargin * 2)
        let roomY = max(0, visibleFrame.height - size.height - screenMargin * 2)
        let stepsThatFit = max(1, Int(min(roomX, roomY) / cascadeStep) + 1)
        let shift = CGFloat(max(0, slot) % stepsThatFit) * cascadeStep
        let x = visibleFrame.maxX - screenMargin - size.width - shift
        let y = visibleFrame.maxY - screenMargin - size.height - shift
        return CGPoint(
            x: max(visibleFrame.minX, x).rounded(),
            y: max(visibleFrame.minY, y).rounded()
        )
    }

    /// A point of the panel, counted from its bottom left corner the way
    /// AppKit hands out a pointer's place, as an anchor for a zoom: a
    /// fraction of the picture area from its middle, with down positive.
    /// The strip of controls sits under the picture area.
    static func anchor(forPanelPoint point: CGPoint, panelSize: CGSize) -> CGPoint {
        let areaHeight = panelSize.height - barHeight
        guard panelSize.width > 0, areaHeight > 0 else { return .zero }
        let x = point.x / panelSize.width - 0.5
        let y = 0.5 - (point.y - barHeight) / areaHeight
        return CGPoint(x: min(max(x, -0.5), 0.5), y: min(max(y, -0.5), 0.5))
    }

    /// How much one notch of a scroll with Command or Option held zooms.
    static func zoomFactor(forScroll delta: CGFloat) -> CGFloat {
        guard delta.isFinite else { return 1 }
        return min(max(exp(delta * 0.01), 0.5), 2)
    }

    // MARK: Look

    static func clampedOpacity(_ opacity: Double) -> Double {
        guard opacity.isFinite else { return opacityRange.upperBound }
        return min(max(opacity, opacityRange.lowerBound), opacityRange.upperBound)
    }
}
