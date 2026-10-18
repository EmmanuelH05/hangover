import AppKit
import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

/// The month look lists the picked day under its grid: two rows, then "+N
/// more", which grows the card by N rows (`calendarExtraRows`). Nothing had
/// measured that the rows fit the look's height, or that the page grows by
/// what the card grows by. Both are measured here. Set
/// `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to write the PNGs to
/// `output/render/calendar/`.
@MainActor
@Suite struct NookCalendarMonthRowsTests {
    /// The room the look has for the day rows: its height less the card's
    /// padding, the header, the weekday line, the six-row grid and the gaps
    /// between the parts.
    @Test func twoRowsAndTheMoreLineFitUnderTheGrid() {
        let look = NookCalendarMonthView.height - 2 * 12
        let above: CGFloat = 22 + 4 + 12 + 4 + 6 * 26 + 4 + 2 + 4
        let room = look - above
        let rows: CGFloat = 2
        let rowsHeight = rows * NookCalendarExpansion.rowHeight + rows * NookCalendarExpansion.rowSpacing
        let moreLine: CGFloat = 14
        #expect(rowsHeight + moreLine <= room, "two rows and the more line need \(rowsHeight + moreLine), the look has \(room)")
    }

    /// Drawn: the look's own content, measured at its natural height, fits
    /// the room collapsed and grows by exactly the rows "+N more" adds.
    @Test func theLookDrawsWithinItsHeightCollapsedAndExpanded() throws {
        let (nook, hidden) = Self.rig(eventsToday: 6)
        let room = NookCalendarMonthView.height - 2 * 12

        let collapsed = try Self.naturalHeight(of: nook)
        #expect(collapsed <= room, "collapsed month content is \(collapsed) in a look of \(room)")

        nook.calendarExtraRows = hidden
        let expanded = try Self.naturalHeight(of: nook)
        let grown = room + NookCalendarExpansion.height(extraRows: hidden)
        #expect(expanded <= grown, "expanded month content is \(expanded) in a look of \(grown)")
    }

    /// The page grows by what the card grows by, so the widgets under the
    /// calendar move down instead of being cut.
    @Test func thePageGrowsByTheRowsTheCardAdds() {
        let placements = [
            NookWidgetPlacement(kind: .calendar, size: .medium),
            NookWidgetPlacement(kind: .todo, size: .medium),
        ]
        var extras = NookPageExtras.none
        extras.calendarExtraRows = 4
        let plain = NookPanelView.preferredHeight(for: placements, calendarStyle: .month, isEditing: false)
        let grown = NookPanelView.preferredHeight(for: placements, calendarStyle: .month, isEditing: false, extras: extras)
        #expect(grown - plain == NookCalendarExpansion.height(extraRows: 4))
        #expect(NookPanelView.cardHeight(placements[0], calendarStyle: .month, calendarExtraRows: 4)
            == NookCalendarCard.height(for: .medium, style: .month) + NookCalendarExpansion.height(extraRows: 4))
        // The small card lists no day and has nothing to grow.
        let small = NookWidgetPlacement(kind: .calendar, size: .small)
        #expect(NookPanelView.cardHeight(small, calendarStyle: .month, calendarExtraRows: 4)
            == NookCalendarCard.height(for: .small, style: .month))
    }

    /// The card at medium with six events today, short and then with every
    /// row. The picture is the card's height, and the PNGs are for a look.
    @Test func theCardDrawsShortAndThenWithEveryRow() throws {
        let (nook, hidden) = Self.rig(eventsToday: 6)
        for (name, rows) in [("month-6-events", 0), ("month-6-events-expanded", hidden)] {
            nook.calendarExtraRows = rows
            let height = NookCalendarCard.height(for: .medium, style: .month) + NookCalendarExpansion.height(extraRows: rows)
            let image = try Self.render(
                NookCalendarCard(nook: nook)
                    .environment(\.nookWidgetSize, .medium)
                    .frame(width: 484, height: height)
            )
            #expect(image.height == Int((height + 16) * 2), "\(name)")
            try Self.write(image, name: name)
        }
    }

    // MARK: Rig

    /// A model whose calendar has `eventsToday` events on today, drawn in the
    /// month look. Returns the rows "+N more" stands for.
    private static func rig(eventsToday: Int) -> (NookModel, Int) {
        let cal = Calendar.current
        let morning = cal.startOfDay(for: Date()).addingTimeInterval(8 * 3600)
        let source = DemoCalendarSource(now: morning)
        let already = source.events.filter { cal.isDate($0.start, inSameDayAs: morning) && !$0.isAllDay }.count
        for index in 0..<max(0, eventsToday - already) {
            let start = morning.addingTimeInterval(TimeInterval(7 + 2 * index) * 3600)
            source.add(NookEventDraft(title: "Extra \(index + 1)", start: start, end: start.addingTimeInterval(3600), isAllDay: false))
        }
        let defaults = MemoryDefaults()
        let nook = NookModel(
            calendar: NookCalendarService(sample: source, defaults: defaults),
            defaults: defaults, looksForImportedGIF: false, asksMacOSForAccess: false
        )
        nook.updateDisplayPreferences(for: nook.activeProfile()) { $0.calendarStyle = .month }
        let total = nook.calendarEvents(from: cal.startOfDay(for: morning), to: cal.startOfDay(for: morning).addingTimeInterval(86_400))
            .filter { !$0.isAllDay }.count
        return (nook, NookCalendarExpansion.hiddenRows(total: total, shownWhenCollapsed: 2))
    }

    /// The month content at the width it has in the card, at its own height.
    private static func naturalHeight(of nook: NookModel) throws -> CGFloat {
        let image = try render(
            NookCalendarMonthView(nook: nook)
                .frame(width: 484 - 2 * 14)
                .fixedSize(horizontal: false, vertical: true),
            margin: 0
        )
        return CGFloat(image.height) / 2
    }

    private static func render(_ view: some View, margin: CGFloat = 8) throws -> CGImage {
        let renderer = ImageRenderer(
            content: view
                .padding(margin)
                .background(Color.black)
                .environment(\.colorScheme, .dark)
                .environment(\.nookDrawsStill, true)
        )
        renderer.scale = 2
        return try #require(renderer.cgImage, "no picture")
    }

    private static func write(_ image: CGImage, name: String) throws {
        guard ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_SNAPSHOTS"] == "1" else { return }
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("output/render/calendar", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
