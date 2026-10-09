import CoreGraphics
import SwiftUI

/// How much room a widget takes on the Nook page. The page is a two column
/// grid: a small widget fills one column at a shared height, so two small
/// widgets sit side by side; medium and large span both columns, large
/// with more height.
enum NookWidgetSize: String, CaseIterable, Codable, Identifiable, Sendable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var spansBothColumns: Bool { self != .small }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    /// One letter for the size buttons on a card in edit mode.
    var shortTitle: String {
        switch self {
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        }
    }
}

/// One widget on the page with the size it is drawn at.
struct NookWidgetPlacement: Equatable, Hashable, Identifiable, Sendable {
    var kind: NookWidgetKind
    var size: NookWidgetSize

    var id: NookWidgetKind { kind }
}

/// One row of the grid: a single wide widget, or one or two small ones.
struct NookWidgetRow: Equatable, Identifiable, Sendable {
    var placements: [NookWidgetPlacement]

    var id: NookWidgetKind { placements[0].kind }
    var isSmallRow: Bool { placements[0].size == .small }
}

extension EnvironmentValues {
    /// The size the enclosing grid cell gives a card. Cards read it to pick
    /// their layout; the frame itself comes from the grid.
    @Entry var nookWidgetSize: NookWidgetSize = .medium
}

/// Pure layout rules for the Nook grid, shared by the page, the window
/// sizing math and the Personalization editor.
enum NookWidgetLayout {
    static let columnSpacing: CGFloat = 10
    static let rowSpacing: CGFloat = 10
    /// Every small widget is this tall, which keeps two of them level.
    static let smallHeight: CGFloat = 120
    /// Drag distance on a resize grip that moves one size step.
    static let resizeStep: CGFloat = 60

    /// Packs widgets into rows in order. Two small widgets in a row share
    /// it; a small widget followed by a wide one sits alone, left aligned.
    static func rows(_ placements: [NookWidgetPlacement]) -> [NookWidgetRow] {
        var rows: [NookWidgetRow] = []
        var pendingSmall: NookWidgetPlacement?
        for placement in placements {
            if placement.size == .small {
                if let first = pendingSmall {
                    rows.append(NookWidgetRow(placements: [first, placement]))
                    pendingSmall = nil
                } else {
                    pendingSmall = placement
                }
                continue
            }
            if let first = pendingSmall {
                rows.append(NookWidgetRow(placements: [first]))
                pendingSmall = nil
            }
            rows.append(NookWidgetRow(placements: [placement]))
        }
        if let first = pendingSmall {
            rows.append(NookWidgetRow(placements: [first]))
        }
        return rows
    }

    /// Height of one row. `height` gives a wide widget's height; small rows
    /// use `smallRowHeight`, the shared `smallHeight` except in the
    /// settings preview.
    static func rowHeight(
        _ row: NookWidgetRow,
        smallRowHeight: CGFloat = smallHeight,
        height: (NookWidgetPlacement) -> CGFloat
    ) -> CGFloat {
        row.isSmallRow ? smallRowHeight : height(row.placements[0])
    }

    /// Height of all rows with spacing between them, zero when empty.
    static func contentHeight(
        _ placements: [NookWidgetPlacement],
        smallRowHeight: CGFloat = smallHeight,
        height: (NookWidgetPlacement) -> CGFloat
    ) -> CGFloat {
        let rows = rows(placements)
        guard !rows.isEmpty else { return 0 }
        return rows.reduce(0) { $0 + rowHeight($1, smallRowHeight: smallRowHeight, height: height) }
            + rowSpacing * CGFloat(rows.count - 1)
    }

    /// Width of one column for a grid this wide.
    static func columnWidth(totalWidth: CGFloat) -> CGFloat {
        max(0, (totalWidth - columnSpacing) / 2)
    }

    /// The order with `kind` moved to `index`, clamped to the list.
    static func moving(_ kind: NookWidgetKind, to index: Int, in order: [NookWidgetKind]) -> [NookWidgetKind] {
        guard let from = order.firstIndex(of: kind) else { return order }
        var result = order
        result.remove(at: from)
        result.insert(kind, at: min(max(0, index), result.count))
        return result
    }

    /// The size a resize grip lands on after a drag. The longer axis
    /// decides: right or down grows, left or up shrinks, one step per
    /// `resizeStep` points.
    static func snappedSize(from start: NookWidgetSize, translation: CGSize) -> NookWidgetSize {
        let dominant = abs(translation.width) >= abs(translation.height) ? translation.width : translation.height
        let steps = Int((dominant / resizeStep).rounded(.towardZero))
        let all = NookWidgetSize.allCases
        let startIndex = all.firstIndex(of: start) ?? 1
        return all[min(max(0, startIndex + steps), all.count - 1)]
    }
}
