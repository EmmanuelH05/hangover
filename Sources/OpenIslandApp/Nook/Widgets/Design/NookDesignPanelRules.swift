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
/// large, and how they resize.
enum NookDesignPanelRules {
    /// Panels that can be up at once.
    static let maxOpenPanels = 6
    /// Longer side of a new panel's picture area.
    static let initialLongSide: CGFloat = 360
    /// The strip of controls needs this much.
    static let minimumWidth: CGFloat = 240
    /// Height of the strip of controls under the picture.
    static let barHeight: CGFloat = 30
    /// A panel's picture area is never narrower or wider than this for its
    /// height. A picture outside it, such as a long page, is fitted inside
    /// and read by zooming.
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

    /// The shape of the picture area for a picture of this shape.
    static func areaAspect(forPictureAspect aspect: CGFloat) -> CGFloat {
        guard aspect.isFinite, aspect > 0 else { return 1 }
        return min(max(aspect, aspectRange.lowerBound), aspectRange.upperBound)
    }

    /// The part of the picture area the fitted picture covers on each
    /// axis. Both are 1 unless the picture's shape is outside
    /// `aspectRange`.
    static func fittedFraction(pictureAspect: CGFloat) -> CGSize {
        guard pictureAspect.isFinite, pictureAspect > 0 else { return CGSize(width: 1, height: 1) }
        let area = areaAspect(forPictureAspect: pictureAspect)
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

    /// The size a resize lands on. The edge that moved more decides, and
    /// the other follows, which keeps the picture area in its shape.
    static func resizedSize(
        proposed: CGSize,
        current: CGSize,
        pictureAspect: CGFloat,
        available: CGSize
    ) -> CGSize {
        let widthMoved = abs(proposed.width - current.width)
        let heightMoved = abs(proposed.height - current.height)
        let width = widthMoved >= heightMoved
            ? proposed.width
            : panelWidth(height: proposed.height, pictureAspect: pictureAspect)
        return fitted(width: width, pictureAspect: pictureAspect, available: available)
    }

    /// The panel size nearest `width` that is at least the minimum width
    /// and fits in `available`. The minimum wins when the two disagree.
    private static func fitted(width: CGFloat, pictureAspect: CGFloat, available: CGSize) -> CGSize {
        var width = width.isFinite ? width : initialLongSide
        width = min(width, available.width)
        width = min(width, panelWidth(height: available.height, pictureAspect: pictureAspect))
        width = max(width, minimumWidth)
        return panelSize(width: width.rounded(), pictureAspect: pictureAspect)
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
