import CoreGraphics

/// Where the opened island sits, as the tour's window needs it (D44).
struct OnboardingIslandFootprint: Equatable, Sendable {
    /// The visible frame of the screen the island is on, in screen
    /// coordinates (the origin at the bottom left).
    var screen: CGRect
    /// The frame the opened island fills, hanging from the top of the screen.
    var island: CGRect
}

/// Where the tour's window goes. On a live page (`OnboardingPage.isLive`)
/// the real island is the preview and the window steps aside: narrow, at
/// the left edge of the screen the island is on. On the others it is the
/// full window, centered on that same screen. A pure function of two
/// rectangles, which keeps it testable without a screen.
enum OnboardingWindowFrame {
    /// Room kept between the window, the screen's edges and the island.
    static let margin: CGFloat = 24
    static let narrowWidthRange: ClosedRange<CGFloat> = 320...420
    /// The tallest the narrow window gets. Its pages scroll past it.
    static let narrowMaxHeight: CGFloat = 760

    static func frame(isLive: Bool, screen: CGRect, island: CGRect) -> CGRect {
        isLive ? narrow(screen: screen, island: island) : wide(screen: screen)
    }

    /// The full window, centered, and never larger than the screen.
    static func wide(screen: CGRect) -> CGRect {
        let size = CGSize(
            width: min(OnboardingStyle.windowSize.width, screen.width),
            height: min(OnboardingStyle.windowSize.height, screen.height)
        )
        return CGRect(
            x: screen.midX - size.width / 2,
            y: screen.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// As wide as the free space left of the island minus a margin, kept
    /// between 320 and 420 points, docked at the left edge and centered
    /// vertically. On a screen too narrow for that, the window keeps its
    /// least width at the left edge, which overlaps the island as little as
    /// it can, and is never off the screen.
    static func narrow(screen: CGRect, island: CGRect) -> CGRect {
        let free = island.minX - screen.minX
        let width = min(
            min(max(free - margin, narrowWidthRange.lowerBound), narrowWidthRange.upperBound),
            screen.width
        )
        let height = min(narrowMaxHeight, screen.height - margin)
        let left = screen.minX + margin / 2
        let x = min(max(left, screen.minX), screen.maxX - width)
        return CGRect(x: x, y: screen.midY - height / 2, width: width, height: height)
    }
}
