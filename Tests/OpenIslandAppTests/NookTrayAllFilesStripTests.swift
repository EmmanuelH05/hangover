import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

/// The all-files strip: the room it takes on the page and how it draws with
/// the O2 sample of 145 files. The tray folder and the files are separate
/// temp folders, the settings live in memory, and nothing leaves them.
@MainActor @Suite(.serialized, .noNewWindows) struct NookTrayAllFilesStripTests {
    /// The page's content width, which the medium card's row uses.
    private static let contentWidth: CGFloat = 612

    // MARK: Layout

    @Test func thePageHeightIsTheHeightPlusTheRowGapLikeTheOtherStrips() {
        #expect(NookTrayAllFilesLayout.pageHeight > NookTrayAllFilesLayout.height)
        #expect(NookTrayAllFilesLayout.pageHeight == NookTrayAllFilesLayout.height + NookWidgetLayout.rowSpacing)
        #expect(NookGIFStripLayout.pageHeight == NookGIFStripLayout.height + NookWidgetLayout.rowSpacing)
        #expect(NookConvertStripLayout.pageHeight == NookConvertStripLayout.height + NookWidgetLayout.rowSpacing)
    }

    @Test func theStripAddsItsHeightToThePage() {
        let closed = NookPageExtras()
        var open = NookPageExtras()
        open.showsAllFiles = true
        #expect(open.pinnedHeight - closed.pinnedHeight == NookTrayAllFilesLayout.pageHeight)
    }

    @Test func theHeightIsTheHeaderAndThreeRowsOfTilesPlusPadding() {
        let layout = NookTrayAllFilesLayout.self
        let rows = CGFloat(layout.rowsInView)
        #expect(layout.height == layout.verticalPadding * 2 + layout.headerHeight + layout.headerGap
            + rows * layout.tileHeight + (rows - 1) * layout.rowSpacing)
        #expect(layout.rowsInView == 3)
    }

    /// Eight 64 point tiles need 554 points. The default island's page is
    /// 448 wide (420 inside the strip's padding), which holds five beside
    /// the scroll bar; a fixed eight would push three columns out of reach.
    @Test func theColumnsFollowTheWidthUpToEight() {
        let layout = NookTrayAllFilesLayout.self
        #expect(layout.columns(forWidth: Self.contentWidth) == 8)
        #expect(layout.columns(forWidth: 420) == 5)
        #expect(layout.columns(forWidth: 2_000) == 8)
        #expect(layout.columns(forWidth: 10) == 1)
    }

    @Test func theScrollBarFollowsTheScrollAndHidesWhenEverythingFits() throws {
        let layout = NookTrayAllFilesLayout.self
        #expect(layout.thumb(contentHeight: layout.contentHeight(forFileCount: 24, columns: 8), viewHeight: layout.bodyHeight, offset: 0) == nil)
        let content = layout.contentHeight(forFileCount: 145, columns: 8)
        let top = try #require(layout.thumb(contentHeight: content, viewHeight: layout.bodyHeight, offset: 0))
        let end = try #require(layout.thumb(contentHeight: content, viewHeight: layout.bodyHeight, offset: content - layout.bodyHeight))
        #expect(top.top == 0)
        #expect(abs(end.top + end.height - layout.bodyHeight) < 0.001)
        #expect(top.height < layout.bodyHeight)
    }

    // MARK: Drawing

    /// The O2 sample: nine named files, then take 1.mp4 and up.
    private static func sampleNames() -> [String] {
        let first = ["clip.mp4", "demo.mp4", "intro.mp4", "notes.pdf", "mock.png", "main.swift", "data.csv", "build.zip", "demo.mp3"]
        return first + (1...136).map { "take \($0).mp4" }
    }

    @Test func theStripDrawsWith145Files() async throws {
        let stamp = UUID().uuidString
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NookTrayAllFiles-\(stamp)", isDirectory: true)
        let incoming = FileManager.default.temporaryDirectory.appendingPathComponent("NookTrayAllFilesIncoming-\(stamp)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: incoming)
        }
        let defaults = MemoryDefaults()
        let store = NookTrayStore(
            folder: folder,
            clipboard: NookClipboardMonitor(pasteboard: NookFakePasteboard(), defaults: defaults),
            defaults: defaults
        )
        // Oldest first: the first name added ends up newest.
        for name in Self.sampleNames().reversed() {
            let source = incoming.appendingPathComponent(UUID().uuidString).appendingPathComponent(name)
            try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: source)
            await store.add(fileAt: source)?.value
        }
        #expect(store.items.count == 145)

        let view = NookTrayAllFilesStrip(tray: store)
            .frame(width: Self.contentWidth + NookTrayAllFilesLayout.horizontalPadding * 2, height: NookTrayAllFilesLayout.height)
            .padding(8)
        let png = try Self.render("all-files", view)
        #expect(!png.isEmpty)

        // The default island on a notch: five columns, none cut off.
        let narrow = NookTrayAllFilesStrip(tray: store)
            .frame(width: 448, height: NookTrayAllFilesLayout.height)
            .padding(8)
        let narrowPNG = try Self.render("all-files-narrow", narrow)
        #expect(!narrowPNG.isEmpty)
    }

    /// Draws the view on the app's ink and, with OPEN_ISLAND_RENDER_SNAPSHOTS=1,
    /// writes it under output/render/tray-overflow.
    private static func render<Content: View>(_ name: String, _ view: Content, filePath: String = #filePath) throws -> Data {
        let framed = view
            .background(V6Palette.ink)
            .environment(\.colorScheme, .dark)
            .environment(\.nookDrawsStill, true)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        let image = try #require(renderer.cgImage, "ImageRenderer returned no image for \(name)")
        let png = try #require(
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
            "PNG encoding failed for \(name)"
        )
        if ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_SNAPSHOTS"] == "1" {
            let directory = URL(fileURLWithPath: filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("output/render/tray-overflow", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return png
    }
}
