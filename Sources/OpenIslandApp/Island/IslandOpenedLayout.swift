import CoreGraphics
import OpenIslandCore

/// Heights of the opened island, resolved by the panel controller from the
/// content and handed to `IslandPanelView`, which animates the shape to
/// them. The window may be taller for a moment while a shrink settles.
struct IslandOpenedLayout: Equatable, Sendable {
    /// The header row: the notch height on a MacBook, the menu bar height
    /// on an external display (`NSScreen.islandClosedHeight` on both).
    var headerHeight: CGFloat
    /// Space under the header, already clamped to the minimum and to the
    /// screen.
    var contentHeight: CGFloat
    var bottomPadding: CGFloat = 0

    /// Height of the black surface.
    var shapeHeight: CGFloat { headerHeight + contentHeight + bottomPadding }

    /// Height the island window needs: the shape plus the transparent inset
    /// under it that the shadow and the status halo use.
    var windowHeight: CGFloat { shapeHeight + IslandChromeMetrics.openedShadowBottomInset }

    static let placeholder = IslandOpenedLayout(headerHeight: 32, contentHeight: 108)

    // MARK: Content height rules

    /// The opened island is never shorter than this under the header, which
    /// also keeps the window from shrinking when sessions come and go.
    static let minimumContentHeight: CGFloat = 108
    /// Gap kept between a capped Nook page and the bottom of the screen.
    static let nookScreenMargin: CGFloat = 8

    /// Room a Nook page may use under the header before it would run past
    /// the visible bottom of the screen.
    static func nookContentRoom(
        screenMaxY: CGFloat,
        visibleMinY: CGFloat,
        headerHeight: CGFloat,
        bottomPadding: CGFloat,
        shadowBottomInset: CGFloat,
        margin: CGFloat = nookScreenMargin
    ) -> CGFloat {
        screenMaxY - visibleMinY - headerHeight - bottomPadding - shadowBottomInset - margin
    }

    /// Clamps the height a page asked for to the minimum and, for the Nook
    /// page, to the room the screen has. `nookRoom` is nil for every other
    /// page. A tiny screen never pushes the Nook page under the minimum.
    static func clampedContentHeight(
        requested: CGFloat,
        nookRoom: CGFloat?,
        minimum: CGFloat = minimumContentHeight
    ) -> CGFloat {
        var height = requested
        if let nookRoom {
            height = min(height, max(minimum, nookRoom))
        }
        return max(height, minimum)
    }
}

/// Window sizing rules for the opened island (approach B, D16): the window
/// grows before the shape animates and shrinks after it.
enum IslandPanelSizing {
    enum ResizeStep: Equatable, Sendable {
        /// The target is taller: resize the window now, before the shape moves.
        case grow
        /// The target is shorter: let the shape move first, resize later.
        case shrink
        /// Within the dead zone: leave the window alone.
        case none
    }

    /// Height differences up to this many points are ignored.
    static let deadZone: CGFloat = 0.5

    static func resizeStep(current: CGFloat, target: CGFloat) -> ResizeStep {
        let difference = target - current
        if difference > deadZone { return .grow }
        if difference < -deadZone { return .shrink }
        return .none
    }

    /// True when `target` differs from `current` only in height, with the
    /// same top edge. Anything else (another screen, a different width) is a
    /// screen change and is applied exactly, at once.
    static func isHeightOnlyChange(from current: CGRect, to target: CGRect) -> Bool {
        abs(current.minX - target.minX) <= deadZone
            && abs(current.width - target.width) <= deadZone
            && abs(current.maxY - target.maxY) <= deadZone
    }

    /// True when the window gets narrower in place: same middle, same top
    /// edge, less width. That is a narrower look on the same screen, and
    /// never a move to another screen.
    static func isNarrowing(from current: CGRect, to target: CGRect) -> Bool {
        target.width < current.width - deadZone
            && abs(current.midX - target.midX) <= deadZone
            && abs(current.maxY - target.maxY) <= deadZone
    }

    /// The part of the window the black shape covers while the island is
    /// open: anchored to the top, inset on both sides by the shadow inset.
    /// Everything else in the window is transparent and lets clicks through
    /// to the close-and-repost path. `bounds` uses the bottom-up coordinates
    /// of the window, so the top edge is `maxY`.
    static func visibleShapeRect(
        in bounds: CGRect,
        shapeHeight: CGFloat,
        horizontalInset: CGFloat
    ) -> CGRect {
        let height = max(0, min(shapeHeight, bounds.height))
        return CGRect(
            x: bounds.minX + horizontalInset,
            y: bounds.maxY - height,
            width: max(0, bounds.width - (horizontalInset * 2)),
            height: height
        )
    }
}

/// What the opened island is drawing. While open it is live; during the
/// close fade the coordinator keeps a snapshot, which stops a notification
/// card from turning into the session list or the Nook page mid-fade.
struct IslandOpenedPresentation: Equatable {
    var surface: IslandSurface
    var openReason: NotchOpenReason?
    var showsNookPage: Bool
    var showsNookAgentsBar: Bool
    var showsNookCompactBar: Bool
    /// The session behind the surface's card, as it was when the
    /// presentation was taken. A closing notification card draws this copy,
    /// so approving, answering or dismissing (which change or remove the
    /// session in the same turn as the close) cannot redraw the card as
    /// another row mid-fade. Nil when the surface has no session.
    var session: AgentSession? = nil

    var isNotificationMode: Bool {
        openReason == .notification && surface.sessionID != nil
    }
}
