import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// The event editor on the Nook page, and the calendar card growing for
/// "+N more".
@MainActor
@Suite struct NookEventEditorTests {
    private static func place(_ kind: NookWidgetKind, _ size: NookWidgetSize) -> NookWidgetPlacement {
        NookWidgetPlacement(kind: kind, size: size)
    }

    // MARK: Opening and closing

    @Test func thePlusOpensTheEditorOnThatDay() {
        let nook = NookModel()
        let day = Date(timeIntervalSince1970: 1_800_000_000)

        nook.beginAddingEvent(on: day)

        #expect(nook.isEventEditorOpen)
        #expect(nook.eventForm?.day == Calendar.current.startOfDay(for: day))
    }

    @Test func cancelDropsWhatWasTyped() {
        let nook = NookModel()
        nook.beginAddingEvent(on: Date())
        nook.eventForm?.title = "Dinner"

        nook.closeEventEditor(keepingDraft: false)
        nook.beginAddingEvent(on: Date())

        #expect(nook.eventForm?.title == "")
    }

    @Test func theIslandClosingKeepsWhatWasTypedForTheNextPlus() {
        let nook = NookModel()
        nook.beginAddingEvent(on: Date())
        nook.eventForm?.title = "Dinner"
        nook.eventForm?.notes = "at eight"

        nook.closeEventEditor(keepingDraft: true)
        #expect(!nook.isEventEditorOpen)
        #expect(nook.eventForm == nil)

        nook.beginAddingEvent(on: Date())
        #expect(nook.eventForm?.title == "Dinner")
        #expect(nook.eventForm?.notes == "at eight")

        // It comes back once. A cancel after that starts clean.
        nook.closeEventEditor(keepingDraft: false)
        nook.beginAddingEvent(on: Date())
        #expect(nook.eventForm?.title == "")
    }

    @Test func anEmptyFormIsNotKept() {
        let nook = NookModel()
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        let second = first.addingTimeInterval(5 * 86_400)
        nook.beginAddingEvent(on: first)
        nook.closeEventEditor(keepingDraft: true)

        nook.beginAddingEvent(on: second)

        #expect(nook.eventForm?.day == Calendar.current.startOfDay(for: second))
    }

    @Test func theEditorHoldsTheIslandOpenAndClosingTheIslandFoldsItAway() {
        let model = AppModel()
        model.nook.presentRingLight = { _ in }
        model.nook.pageOverride = .nook
        model.notchStatus = .opened
        model.notchOpenReason = .hover

        #expect(model.overlay.shouldAutoCollapseOnMouseLeave)

        model.nook.beginAddingEvent(on: Date())
        model.nook.eventForm?.title = "Dinner"
        #expect(!model.overlay.shouldAutoCollapseOnMouseLeave)

        model.notchClose()
        #expect(!model.nook.isEventEditorOpen)
        #expect(model.nook.calendarExtraRows == 0)

        // What was typed is waiting for the next "+".
        model.nook.beginAddingEvent(on: Date())
        #expect(model.nook.eventForm?.title == "Dinner")
        model.nook.closeEventEditor(keepingDraft: false)
    }

    @Test func leavingTheNookPageFoldsTheEditorAway() {
        let model = AppModel()
        model.nook.presentRingLight = { _ in }
        model.nook.pageOverride = .nook
        model.nook.beginAddingEvent(on: Date())

        model.showAgentsPage()

        #expect(!model.nook.isEventEditorOpen)
    }

    @Test func openingAndClosingTheEditorResizesTheIsland() {
        let nook = NookModel()
        var resizeCount = 0
        nook.onDisplayPreferencesChanged = { resizeCount += 1 }

        nook.beginAddingEvent(on: Date())
        nook.eventForm?.title = "typing does not resize"
        nook.closeEventEditor(keepingDraft: false)

        #expect(resizeCount == 2)
    }

    // MARK: Page height

    @Test func theEditorAddsItsHeightAndOneRowGapToThePage() {
        let placements = [Self.place(.calendar, .medium), Self.place(.todo, .medium)]
        let plain = NookPanelView.preferredHeight(for: placements, calendarStyle: .month, isEditing: false)
        let withEditor = NookPanelView.preferredHeight(
            for: placements, calendarStyle: .month, isEditing: false,
            extras: NookPageExtras(showsEventEditor: true)
        )
        let withBoth = NookPanelView.preferredHeight(
            for: placements, calendarStyle: .month, isEditing: false,
            extras: NookPageExtras(mirrorHeight: 259, showsEventEditor: true)
        )

        #expect(withEditor - plain == NookEventEditorLayout.height + NookWidgetLayout.rowSpacing)
        #expect(withBoth - withEditor == 259 + NookWidgetLayout.rowSpacing)
    }

    @Test func theEditorFitsItsHeightAtBothIslandWidths() throws {
        let nook = NookModel()
        nook.beginAddingEvent(on: Date())
        nook.eventForm?.title = "Dinner with Sam"

        // The page is 448pt wide on the MacBook notch and 488pt on a top bar.
        for width in [448.0, 488.0] {
            let height = try fittedHeight(width: width) { NookEventEditor(nook: nook) }
            #expect(
                height <= NookEventEditorLayout.height,
                "the editor needs \(height)pt at \(width)pt wide and has \(NookEventEditorLayout.height)pt"
            )
        }
    }

    @Test func theEditorRenders() throws {
        let nook = NookModel()
        nook.beginAddingEvent(on: Date(timeIntervalSince1970: 1_791_500_000))
        nook.eventForm?.title = "Dinner with Sam"
        nook.eventForm?.location = "Westwood"

        let size = CGSize(width: 448, height: NookEventEditorLayout.height)
        let renderer = ImageRenderer(
            content: NookEventEditor(nook: nook)
                .frame(width: size.width, height: size.height)
                .background(Color.black)
                .environment(\.colorScheme, .dark)
                .environment(\.nookDrawsStill, true)
        )
        renderer.scale = Self.scale
        let image = try #require(renderer.cgImage, "ImageRenderer returned no image")
        #expect(image.width == Int(size.width * Self.scale))
        #expect(image.height == Int(size.height * Self.scale))

        if ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_SNAPSHOTS"] == "1" {
            let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            let directory = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("output/render", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("event-editor.png"))
        }
    }

    // MARK: "+N more"

    @Test func moreRowsGrowTheCalendarCardAndThePage() {
        let medium = Self.place(.calendar, .medium)
        let normal = NookPanelView.cardHeight(medium, calendarStyle: .month)
        let grown = NookPanelView.cardHeight(medium, calendarStyle: .month, calendarExtraRows: 3)

        #expect(grown - normal == 3 * (NookCalendarExpansion.rowHeight + NookCalendarExpansion.rowSpacing))

        let placements = [medium, Self.place(.todo, .medium)]
        let page = NookPanelView.preferredHeight(for: placements, calendarStyle: .month, isEditing: false)
        let grownPage = NookPanelView.preferredHeight(
            for: placements, calendarStyle: .month, isEditing: false,
            extras: NookPageExtras(calendarExtraRows: 3)
        )
        #expect(grownPage - page == grown - normal)
    }

    @Test func theSmallCalendarAndOtherCardsDoNotGrow() {
        let small = Self.place(.calendar, .small)
        let todo = Self.place(.todo, .medium)

        #expect(NookPanelView.cardHeight(small, calendarStyle: .month, calendarExtraRows: 3) == NookWidgetLayout.smallHeight)
        #expect(
            NookPanelView.cardHeight(todo, calendarStyle: .month, calendarExtraRows: 3)
                == NookPanelView.cardHeight(todo, calendarStyle: .month)
        )
    }

    @Test func moreStandsForEverythingTheShortListLeavesOut() {
        #expect(NookCalendarExpansion.hiddenRows(total: 5, shownWhenCollapsed: 2) == 3)
        #expect(NookCalendarExpansion.hiddenRows(total: 2, shownWhenCollapsed: 2) == 0)
        #expect(NookCalendarExpansion.hiddenRows(total: 0, shownWhenCollapsed: 2) == 0)
        #expect(NookCalendarExpansion.height(extraRows: -4) == 0)
    }

    @Test func growingTheCalendarResizesTheIslandAndAnyPageChangePutsItBack() {
        let nook = NookModel()
        var resizeCount = 0
        nook.onDisplayPreferencesChanged = { resizeCount += 1 }

        nook.calendarExtraRows = 3
        nook.calendarExtraRows = 3
        #expect(resizeCount == 1)

        // A saved change to the page (here a toggle, put back after) folds it.
        nook.updateDisplayPreferences(for: .topBar) { $0.showsCompactBar.toggle() }
        #expect(nook.calendarExtraRows == 0)
        nook.updateDisplayPreferences(for: .topBar) { $0.showsCompactBar.toggle() }
    }

    // MARK: The add button

    @Test func theAddButtonKeepsItsHitAreaInAShortHeader() throws {
        let inline = try fittedSize { NookCalendarAddButton(isInline: true) {} }
        let regular = try fittedSize { NookCalendarAddButton {} }

        #expect(regular == CGSize(width: 22, height: 22))
        // Inline keeps the 22pt hit area and takes only 12pt of row height.
        #expect(inline == CGSize(width: 22, height: 12))
    }

    // MARK: Rendering

    private static let scale: CGFloat = 2

    private func fittedHeight<Content: View>(width: CGFloat, @ViewBuilder _ content: () -> Content) throws -> CGFloat {
        let renderer = ImageRenderer(
            content: content().fixedSize(horizontal: false, vertical: true).frame(width: width)
        )
        renderer.scale = Self.scale
        let image = try #require(renderer.cgImage, "ImageRenderer returned no image")
        return CGFloat(image.height) / Self.scale
    }

    private func fittedSize<Content: View>(@ViewBuilder _ content: () -> Content) throws -> CGSize {
        let renderer = ImageRenderer(content: content().fixedSize())
        renderer.scale = Self.scale
        let image = try #require(renderer.cgImage, "ImageRenderer returned no image")
        return CGSize(width: CGFloat(image.width) / Self.scale, height: CGFloat(image.height) / Self.scale)
    }
}
