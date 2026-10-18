import AppKit
import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

/// The edit-mode chrome over a card, drawn the way the grid draws it: the
/// card dimmed, the outline, the remove button, the size chips and the grip.
/// The chips sat over the card's header controls (the add button, a time);
/// they are at the bottom left now, across from the grip. Set
/// `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to write the PNGs to
/// `output/render/edit-chrome/`.
@MainActor
@Suite struct NookWidgetEditChromeRenderTests {
    @Test func theChromeDrawsOverTheCalendarAndRecordCards() throws {
        let cal = Calendar.current
        let morning = cal.startOfDay(for: Date()).addingTimeInterval(8 * 3600)
        let defaults = MemoryDefaults()
        let nook = NookModel(
            calendar: NookCalendarService(sample: DemoCalendarSource(now: morning), defaults: defaults),
            defaults: defaults, looksForImportedGIF: false, asksMacOSForAccess: false
        )
        let calendar = NookWidgetPlacement(kind: .calendar, size: .medium)
        let calendarHeight = NookCalendarCard.height(for: .medium, style: .strip)
        let calendarImage = try Self.render(
            NookCalendarCard(nook: nook)
                .environment(\.nookWidgetSize, .medium)
                .frame(width: 484, height: calendarHeight),
            placement: calendar
        )
        #expect(calendarImage.height == Int((calendarHeight + 16) * 2))
        try Self.write(calendarImage, name: "calendar-medium-editing")

        let record = NookWidgetPlacement(kind: .record, size: .medium)
        let recordImage = try Self.render(
            NookRecordCardSnapshot.card(.medium).frame(width: 416, height: NookRecordCard.height(for: .medium)),
            placement: record
        )
        try Self.write(recordImage, name: "record-medium-editing")
    }

    /// `card` under the chrome, dimmed as the grid dims it.
    private static func render(_ card: some View, placement: NookWidgetPlacement) throws -> CGImage {
        let framed = card
            .opacity(0.55)
            .overlay {
                NookWidgetEditOverlay(
                    placement: placement,
                    isHighlighted: false,
                    reorder: DragGesture(),
                    onResize: { _ in },
                    onRemove: {}
                )
            }
            .padding(8)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
            .environment(\.nookDrawsStill, true)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        return try #require(renderer.cgImage, "no picture of the card")
    }

    private static func write(_ image: CGImage, name: String) throws {
        guard ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_SNAPSHOTS"] == "1" else { return }
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("output/render/edit-chrome", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
