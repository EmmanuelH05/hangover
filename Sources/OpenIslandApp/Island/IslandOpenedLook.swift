import CoreGraphics

/// How wide the opened island is.
enum IslandOpenedWidth: String, CaseIterable, Identifiable, Sendable {
    /// The width the island has always had.
    case standard
    case wide
    case widest

    var id: String { rawValue }
}

/// The corners of the opened island.
enum IslandOpenedCorners: String, CaseIterable, Identifiable, Sendable {
    /// Round corners, and on a notch a curved flare where the island meets
    /// the top edge. The shape the island has always had.
    case soft
    /// Small corners and almost no flare, which reads as a rectangle
    /// hanging from the top edge.
    case square

    var id: String { rawValue }
}

/// How the opened island looks on one kind of display (D35). The default is
/// the island as it was before the look could be chosen.
struct IslandOpenedLook: Equatable, Hashable, Sendable {
    var width: IslandOpenedWidth = .standard
    var corners: IslandOpenedCorners = .soft

    static let standard = IslandOpenedLook()

    /// Every look, widths first.
    static let all: [IslandOpenedLook] = IslandOpenedCorners.allCases.flatMap { corners in
        IslandOpenedWidth.allCases.map { IslandOpenedLook(width: $0, corners: corners) }
    }
}

/// Every size that follows from an opened look on one kind of display. The
/// window, the black shape, the click area, the pages and the Settings
/// previews all read these and nothing else, which keeps them from
/// drifting apart.
struct IslandOpenedMetrics: Equatable, Sendable {
    /// Width of the black shape's frame, its flares included.
    var panelWidth: CGFloat
    /// Radius of the concave flares at the top of a notch display's shape.
    /// A top bar's shape has a flat top and does not use it.
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    /// From the frame's edge to a page's content, on each side.
    var sideInset: CGFloat
    /// From the frame's edge to the header's content, on each side.
    var headerInset: CGFloat

    /// Width of the Nook page and of the rows in the agents list.
    var pageWidth: CGFloat { max(0, panelWidth - sideInset * 2) }

    // MARK: Numbers

    /// The frame is never narrower than this, whatever the screen.
    static let minimumPanelWidth: CGFloat = 360
    /// Room kept between the frame and the screen's edges, both sides
    /// together.
    static let screenMargin: CGFloat = 32
    /// What each step up in width adds to the frame.
    static let widthStep: CGFloat = 100
    /// From the body's edge to the content on a notch display. The body
    /// starts where the flare ends, one top radius in.
    static let notchBodyPadding: CGFloat = 24
    static let topBarSideInset: CGFloat = 16
    static let topBarHeaderInset: CGFloat = 18

    /// Width of the frame for a choice, before the screen clamps it. The
    /// standard width is 540 on a notch and 520 on a top bar.
    static func preferredWidth(_ width: IslandOpenedWidth, profile: IslandAppearanceDisplayProfile) -> CGFloat {
        let standard: CGFloat = profile == .notch ? 540 : 520
        switch width {
        case .standard: return standard
        case .wide: return standard + widthStep
        case .widest: return standard + widthStep * 2
        }
    }

    static func radii(for corners: IslandOpenedCorners) -> (top: CGFloat, bottom: CGFloat) {
        switch corners {
        case .soft: (NotchShape.openedTopRadius, NotchShape.openedBottomRadius)
        case .square: (6, 10)
        }
    }

    /// The sizes for `look` on a display of this kind. `screenWidth` is the
    /// screen's visible width; nil leaves the width unclamped, for a
    /// preview that has no screen.
    static func resolve(
        look: IslandOpenedLook,
        profile: IslandAppearanceDisplayProfile,
        screenWidth: CGFloat? = nil
    ) -> IslandOpenedMetrics {
        let preferred = preferredWidth(look.width, profile: profile)
        let panelWidth = screenWidth.map { max(minimumPanelWidth, min(preferred, $0 - screenMargin)) } ?? preferred
        let radii = radii(for: look.corners)
        switch profile {
        case .notch:
            let inset = radii.top + notchBodyPadding
            return IslandOpenedMetrics(
                panelWidth: panelWidth,
                topRadius: radii.top,
                bottomRadius: radii.bottom,
                sideInset: inset,
                headerInset: inset
            )
        case .topBar:
            return IslandOpenedMetrics(
                panelWidth: panelWidth,
                topRadius: radii.top,
                bottomRadius: radii.bottom,
                sideInset: topBarSideInset,
                headerInset: topBarHeaderInset
            )
        }
    }

    /// How much wider a page is under `look` than under the standard look
    /// on the same screen. Text that was measured for the standard width
    /// has this much more room.
    static func pageWidthGain(
        look: IslandOpenedLook,
        profile: IslandAppearanceDisplayProfile,
        screenWidth: CGFloat? = nil
    ) -> CGFloat {
        let chosen = resolve(look: look, profile: profile, screenWidth: screenWidth)
        let standard = resolve(look: .standard, profile: profile, screenWidth: screenWidth)
        return max(0, chosen.pageWidth - standard.pageWidth)
    }
}

extension IslandPanelSizing {
    /// The island's window on a screen: centered, top-anchored, as wide as
    /// the black shape plus the shadow inset on both sides.
    static func windowFrame(
        panelWidth: CGFloat,
        windowHeight: CGFloat,
        screenFrame: CGRect,
        horizontalInset: CGFloat
    ) -> CGRect {
        let width = panelWidth + horizontalInset * 2
        return CGRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - windowHeight,
            width: width,
            height: windowHeight
        )
    }
}

/// The mirror's size above the Nook grid. It shows the whole camera picture
/// at the page's width. A wider island makes a taller mirror, and on a
/// short screen that could push the picker under it off the island: the
/// mirror is then drawn smaller, at the picture's own shape, and centered.
enum NookMirrorFit {
    /// The mirror is never cut shorter than this.
    static let minimumHeight: CGFloat = 140

    /// `room` is the height the mirror may take; nil means any.
    static func size(pageWidth: CGFloat, aspectRatio: CGFloat, room: CGFloat?) -> CGSize {
        let natural = NookMirrorLayout.height(pageWidth: pageWidth, aspectRatio: aspectRatio)
        guard let room else { return CGSize(width: pageWidth, height: natural) }
        let limit = max(room, minimumHeight)
        guard natural > limit else { return CGSize(width: pageWidth, height: natural) }
        let pictureHeight = max(0, limit - NookMirrorLayout.padding * 2)
        let width = (pictureHeight * max(aspectRatio, 0.1)).rounded() + NookMirrorLayout.padding * 2
        return CGSize(width: min(pageWidth, width), height: limit)
    }

    /// Height the mirror may take on a page whose content has
    /// `contentRoom` on the screen: what is left once the bars around the
    /// page, the gap under the mirror, the decoration picker and the
    /// page's own padding have their room.
    static func room(contentRoom: CGFloat, barsHeight: CGFloat) -> CGFloat {
        contentRoom
            - barsHeight
            - NookMirrorLayout.pageHeight(0)
            - NookMirrorDecorationLayout.pickerPageHeight
            - NookPanelView.verticalPadding * 2
    }
}
