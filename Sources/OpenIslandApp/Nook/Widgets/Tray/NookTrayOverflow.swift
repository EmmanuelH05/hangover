import CoreGraphics
import Foundation

/// What the small and medium tray cards do with files that do not fit in
/// one row. Scroll keeps every file in a row that swipes sideways. Count
/// fills the row and ends it with a "+N" tile that opens every file.
enum NookTrayOverflow: String, CaseIterable, Identifiable, Sendable {
    case scroll
    case count

    var id: String { rawValue }
    var titleKey: String { "nook.tray.overflow.\(rawValue)" }
}

/// The arithmetic for a row that fills by width, the large card's rule.
/// The last slot of a full row is the "+N" tile.
enum NookTrayRowLayout {
    /// The gap between tiles.
    static let spacing: CGFloat = 6

    /// How many tiles fit in a row of this width, never fewer than one.
    static func slots(width: CGFloat, tileWidth: CGFloat) -> Int {
        max(1, Int((width + spacing) / (tileWidth + spacing)))
    }

    /// How many files get a tile of their own. When every file fits that is
    /// all of them. Otherwise the last slot is the "+N" tile, and the hidden
    /// count is `count - shown`.
    static func shown(count: Int, slots: Int) -> Int {
        count <= slots ? count : max(0, slots - 1)
    }
}
