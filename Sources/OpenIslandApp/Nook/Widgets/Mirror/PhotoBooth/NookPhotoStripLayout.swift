import CoreGraphics
import Foundation

/// A printed strip's page and where everything sits on it. Every number is
/// a PDF point, 72 to the inch, measured from the page's top left corner
/// the way a person reads the strip.
///
/// The page sizes are the ones real booths print. The margins and the
/// places of the pictures are this app's own.
struct NookPhotoStripLayout: Identifiable, Equatable, Sendable {
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        /// The strip everyone knows: 2 by 6 inches, four pictures stacked,
        /// a short footer.
        case classic
        /// A 6 by 4 inch card with four pictures two by two, none of them
        /// cropped.
        case grid
        /// A 2 by 6 inch strip with four wide pictures and a caption big
        /// enough to read from across a room.
        case caption

        var id: String { rawValue }

        var nameKey: String { "nook.photoBooth.layout.\(rawValue)" }
    }

    /// How the caption and the date share the footer.
    enum FooterStyle: Sendable {
        /// Caption on the first line, date under it.
        case stacked
        /// One line: caption at the left, date at the right.
        case inline
    }

    static let pointsPerInch: CGFloat = 72
    static let defaultKind: Kind = .classic

    let kind: Kind
    let pageSize: CGSize
    /// One rectangle per picture, in the order the pictures are taken.
    let slots: [CGRect]
    /// The whole footer.
    let footer: CGRect
    /// Where the caption goes inside the footer.
    let captionBox: CGRect
    /// Where the date goes inside the footer.
    let dateBox: CGRect
    /// The band under the footer where the app's name is printed. It lies
    /// on the page and clear of every picture and of the footer.
    let wordmarkBox: CGRect
    let footerStyle: FooterStyle
    /// A theme's type sizes are given for the classic strip. Other
    /// layouts scale them by these.
    let captionScale: CGFloat
    let dateScale: CGFloat

    var id: String { kind.rawValue }

    /// Pictures one session takes for this layout.
    var shots: Int { slots.count }

    /// Width over height of a slot, the shape its picture is cut to.
    func aspect(ofSlot index: Int) -> CGFloat {
        let slot = slots[index]
        return slot.width / max(slot.height, 1)
    }

    static func layout(_ kind: Kind) -> NookPhotoStripLayout {
        switch kind {
        case .classic: classic
        case .grid: grid
        case .caption: caption
        }
    }

    /// 2 by 6 inches. Four pictures at three to two, 126 points wide, six
    /// points apart, and a footer with two lines.
    private static let classic: NookPhotoStripLayout = {
        let slots = (0..<4).map { CGRect(x: 9, y: 10 + CGFloat($0) * 90, width: 126, height: 84) }
        let footer = CGRect(x: 9, y: 372, width: 126, height: 50)
        return NookPhotoStripLayout(
            kind: .classic,
            pageSize: CGSize(width: 2 * pointsPerInch, height: 6 * pointsPerInch),
            slots: slots,
            footer: footer,
            captionBox: CGRect(x: footer.minX, y: footer.minY, width: footer.width, height: 32),
            dateBox: CGRect(x: footer.minX, y: footer.minY + 32, width: footer.width, height: 18),
            wordmarkBox: CGRect(x: footer.minX, y: footer.maxY, width: footer.width, height: 10),
            footerStyle: .stacked,
            captionScale: 1,
            dateScale: 1
        )
    }()

    /// 6 by 4 inches on its side. Four pictures at sixteen to nine, the
    /// camera's own shape, left to right and then down, with one line
    /// under them.
    private static let grid: NookPhotoStripLayout = {
        let slots = (0..<4).map { index in
            CGRect(
                x: index % 2 == 0 ? 12 : 220,
                y: index < 2 ? 12 : 132.5,
                width: 200,
                height: 112.5
            )
        }
        // The footer is short to leave the band under it clear of the film
        // theme's holes along the bottom edge.
        let footer = CGRect(x: 12, y: 253, width: 408, height: 17)
        return NookPhotoStripLayout(
            kind: .grid,
            pageSize: CGSize(width: 6 * pointsPerInch, height: 4 * pointsPerInch),
            slots: slots,
            footer: footer,
            captionBox: footer,
            dateBox: footer,
            wordmarkBox: CGRect(x: footer.minX, y: footer.maxY, width: footer.width, height: 11),
            footerStyle: .inline,
            captionScale: 0.9,
            dateScale: 1
        )
    }()

    /// 2 by 6 inches. Four pictures at sixteen to nine and a caption block
    /// that takes the bottom quarter.
    private static let caption: NookPhotoStripLayout = {
        let slots = (0..<4).map { CGRect(x: 8, y: 10 + CGFloat($0) * 78, width: 128, height: 72) }
        let footer = CGRect(x: 8, y: 326, width: 128, height: 96)
        return NookPhotoStripLayout(
            kind: .caption,
            pageSize: CGSize(width: 2 * pointsPerInch, height: 6 * pointsPerInch),
            slots: slots,
            footer: footer,
            captionBox: CGRect(x: 8, y: 330, width: 128, height: 60),
            dateBox: CGRect(x: 8, y: 396, width: 128, height: 20),
            wordmarkBox: CGRect(x: footer.minX, y: footer.maxY, width: footer.width, height: 10),
            footerStyle: .stacked,
            captionScale: 1.6,
            dateScale: 1.2
        )
    }()
}
