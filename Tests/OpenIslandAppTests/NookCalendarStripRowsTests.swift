import AppKit
import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

/// The week look of the calendar lists the picked day under the week. It
/// said "+2 more" under one event with room for two more rows below it: the
/// cap was 2 where the look's height holds 3.
@MainActor
@Suite struct NookCalendarStripRowsTests {
    @Test func aDayThatFitsIsShownWholeAndALongerOneGivesItsLastRowToTheMoreLine() {
        #expect(NookCalendarStripView.maxRows == 3)
        #expect(NookCalendarStripView.shownWhenShort(total: 0) == 0)
        #expect(NookCalendarStripView.shownWhenShort(total: 1) == 1)
        #expect(NookCalendarStripView.shownWhenShort(total: 3) == 3, "three events show as three rows, with no more line")
        #expect(NookCalendarStripView.shownWhenShort(total: 4) == 2)
        #expect(NookCalendarStripView.shownWhenShort(total: 9) == 2)
        // What the more line stands for is everything past the short list.
        #expect(NookCalendarExpansion.hiddenRows(total: 3, shownWhenCollapsed: NookCalendarStripView.shownWhenShort(total: 3)) == 0)
        #expect(NookCalendarExpansion.hiddenRows(total: 5, shownWhenCollapsed: NookCalendarStripView.shownWhenShort(total: 5)) == 3)
    }

    /// The rows the short list can hold fit the room the look has for them.
    /// The header is 22, the week is about 54, and there are 6 points between
    /// each of the three parts.
    @Test func theRowsFitTheLooksOwnHeight() {
        let room = NookCalendarStripView.height - 2 * 12 - 22 - 6 - 54 - 6
        let rows = CGFloat(NookCalendarStripView.maxRows)
        let needed = rows * NookCalendarExpansion.rowHeight + (rows - 1) * NookCalendarExpansion.rowSpacing
        #expect(needed <= room)
        // One more row would not.
        #expect(needed + NookCalendarExpansion.rowHeight + NookCalendarExpansion.rowSpacing > room)
    }

    /// The card at medium with three events today and with five. Set
    /// `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to write the PNGs to
    /// `output/render/calendar/`. Nothing here shows a window or asks
    /// EventKit for anything: the sample calendar stands in.
    @Test func theCardDrawsThreeRowsAndThenTwoWithTheMoreLine() throws {
        let cal = Calendar.current
        let morning = cal.startOfDay(for: Date()).addingTimeInterval(8 * 3600)
        for extra in [0, 2] {
            let source = DemoCalendarSource(now: morning)
            for index in 0..<extra {
                let start = morning.addingTimeInterval(TimeInterval(7 + 2 * index) * 3600)
                source.add(NookEventDraft(title: "Extra \(index + 1)", start: start, end: start.addingTimeInterval(3600), isAllDay: false))
            }
            let defaults = MemoryDefaults()
            let nook = NookModel(
                calendar: NookCalendarService(sample: source, defaults: defaults),
                defaults: defaults, looksForImportedGIF: false, asksMacOSForAccess: false
            )
            let height = NookCalendarCard.height(for: .medium, style: .strip)
            let renderer = ImageRenderer(
                content: NookCalendarCard(nook: nook)
                    .environment(\.nookWidgetSize, .medium)
                    .frame(width: 484, height: height)
                    .padding(8)
                    .background(Color.black)
                    .environment(\.colorScheme, .dark)
                    .environment(\.nookDrawsStill, true)
            )
            renderer.scale = 2
            let image = try #require(renderer.cgImage, "no picture of the card")
            #expect(image.height == Int((height + 16) * 2))
            guard ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_SNAPSHOTS"] == "1" else { continue }
            let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            let directory = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("output/render/calendar", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("strip-\(3 + extra)-events.png"))
        }
    }
}
