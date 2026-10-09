import CoreGraphics

/// What the Nook page holds beyond its grid of standard cards: the Join
/// bar, the event editor and the mirror above the grid, and a calendar card
/// grown to list a whole day. One value feeds both the view and the window-sizing math, which
/// keeps the two adding up to the same height.
struct NookPageExtras: Equatable, Sendable {
    /// Height of the mirror above the grid, nil while it is off.
    var mirrorHeight: CGFloat? = nil
    /// Width of the mirror when the screen is too short for it at the
    /// page's full width (`NookMirrorFit`). Nil fills the page.
    var mirrorWidth: CGFloat? = nil
    var showsEventEditor = false
    /// Rows the calendar card adds under its look after "+N more".
    var calendarExtraRows = 0
    /// True while a meeting is about to start or has just started.
    var showsJoinBar = false
    /// True while the decoration picker is up under the mirror.
    var showsMirrorDecorationPicker = false

    static let none = NookPageExtras()

    /// Height of everything pinned above the grid, each with one row gap
    /// under it.
    var pinnedHeight: CGFloat {
        NookMirrorLayout.pageHeight(mirrorHeight)
            + (showsEventEditor ? NookEventEditorLayout.pageHeight : 0)
            + (showsJoinBar ? NookJoinBarLayout.pageHeight : 0)
            + (showsMirrorDecorationPicker ? NookMirrorDecorationLayout.pickerPageHeight : 0)
    }
}

/// The calendar card growing to show every event of a day. The looks that
/// list a day (the week strip and the month) cut the list short with a
/// "+N more" line; clicking it adds N rows of this height to the card.
enum NookCalendarExpansion {
    static let rowHeight: CGFloat = 15
    static let rowSpacing: CGFloat = 3

    /// Height `extraRows` more rows add to the card.
    static func height(extraRows: Int) -> CGFloat {
        CGFloat(max(0, extraRows)) * (rowHeight + rowSpacing)
    }

    /// How many rows "+N more" stands for: everything past what the short
    /// list shows.
    static func hiddenRows(total: Int, shownWhenCollapsed: Int) -> Int {
        max(0, total - shownWhenCollapsed)
    }
}
