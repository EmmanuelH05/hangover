import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// The bar under the tray's sideways row follows the row. The live card is
/// hosted in a view that never goes on screen, scrolled the way a swipe
/// scrolls it, and drawn at two places where the row shows the same tiles:
/// every file is an mp4 and both places are whole tiles in, which leaves the
/// bar as the only thing that can differ.
@MainActor @Suite(.serialized, .noNewWindows)
struct NookTrayScrollBarTests {
    private static let fileCount = 146
    private static let cardSize = CGSize(width: 313, height: NookTrayCard.height(for: .small))
    /// One compact tile and the gap after it.
    private static let pitch = NookTrayTileMetrics.compact.width + NookTrayRowLayout.spacing

    private struct Fixture {
        let store: NookTrayStore
        let folder: URL
        let incoming: URL

        @MainActor
        init() async throws {
            let id = UUID().uuidString
            folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("NookTrayScrollBar-\(id)", isDirectory: true)
            incoming = FileManager.default.temporaryDirectory
                .appendingPathComponent("NookTrayScrollBarIncoming-\(id)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
            let defaults = MemoryDefaults()
            store = NookTrayStore(
                folder: folder,
                clipboard: NookClipboardMonitor(pasteboard: NookFakePasteboard(), defaults: defaults),
                defaults: defaults
            )
            store.overflow = .scroll
            for index in 1...NookTrayScrollBarTests.fileCount {
                let source = incoming.appendingPathComponent("take \(index).mp4")
                try Data("x".utf8).write(to: source)
                await store.add(fileAt: source)?.value
            }
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: incoming)
        }
    }

    @Test func theThumbMovesWithTheRow() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        #expect(fixture.store.items.count == Self.fileCount)

        let host = NSHostingView(
            rootView: NookTrayCard(store: fixture.store, takesDrops: false)
                .environment(\.nookWidgetSize, .small)
                .frame(width: Self.cardSize.width, height: Self.cardSize.height)
                .padding(8)
                .background(V6Palette.ink)
                .environment(\.colorScheme, .dark)
        )
        host.frame = CGRect(x: 0, y: 0, width: Self.cardSize.width + 16, height: Self.cardSize.height + 16)
        Self.settle(host)
        let row = try #require(Self.scrollView(in: host), "the row has no scroll view")

        let near = try Self.picture(of: host, scrolledTo: NSPoint(x: Self.pitch * 20, y: 0), row)
        let far = try Self.picture(of: host, scrolledTo: NSPoint(x: Self.pitch * 100, y: 0), row)
        #expect(Self.brightPixelCount(near) > 200, "the card drew no tiles")

        let changed = Self.changedRows(near, far)
        try #require(!changed.isEmpty, "the bar did not move between 20 and 100 tiles in")
        let band = changed.max()! - changed.min()! + 1
        #expect(CGFloat(band) <= 4 * Self.scale(near), "more than the bar changed: rows \(changed.min()!) to \(changed.max()!)")

        let line = Self.busiestRow(changed, near, far)
        let nearCenter = try #require(Self.thumbCenter(near, row: line))
        let farCenter = try #require(Self.thumbCenter(far, row: line))
        #expect(farCenter > nearCenter + 20, "the thumb should sit further right 100 tiles in (\(nearCenter) then \(farCenter))")
    }

    /// The strip's bar has a column of its own beside the grid, which is
    /// the only part of the picture read here.
    @Test func theAllFilesThumbMovesWithTheGrid() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        let layout = NookTrayAllFilesLayout.self
        let width: CGFloat = 640

        let host = NSHostingView(
            rootView: NookTrayAllFilesStrip(tray: fixture.store)
                .frame(width: width, height: layout.height)
                .background(V6Palette.ink)
                .environment(\.colorScheme, .dark)
        )
        host.frame = CGRect(x: 0, y: 0, width: width, height: layout.height)
        Self.settle(host)
        let grid = try #require(Self.scrollView(in: host), "the strip has no scroll view")

        let top = try Self.picture(of: host, scrolledTo: .zero, grid)
        let lower = try Self.picture(of: host, scrolledTo: NSPoint(x: 0, y: 800), grid)

        let barTop = layout.verticalPadding + layout.headerHeight + layout.headerGap
        let column = width - layout.horizontalPadding - layout.scrollBarWidth / 2
        let topCenter = try #require(Self.thumbMiddle(top, column: column, from: barTop, height: layout.bodyHeight))
        let lowerCenter = try #require(Self.thumbMiddle(lower, column: column, from: barTop, height: layout.bodyHeight))
        #expect(lowerCenter > topCenter + 20, "the thumb should sit lower 800 points down (\(topCenter) then \(lowerCenter))")
    }

    // MARK: - Helpers

    private static func settle(_ host: NSView) {
        for _ in 0..<6 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    /// SwiftUI's scroll view on macOS is an `NSScrollView`.
    private static func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for subview in view.subviews {
            if let found = scrollView(in: subview) { return found }
        }
        return nil
    }

    /// Scrolls the clip view the way a swipe does, then draws the host.
    private static func picture(of host: NSView, scrolledTo point: NSPoint, _ scroll: NSScrollView) throws -> NSBitmapImageRep {
        scroll.contentView.scroll(to: point)
        scroll.reflectScrolledClipView(scroll.contentView)
        settle(host)
        let picture = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: picture)
        return picture
    }

    private static func scale(_ picture: NSBitmapImageRep) -> CGFloat {
        CGFloat(picture.pixelsWide) / picture.size.width
    }

    private static func brightness(_ picture: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat {
        guard let color = picture.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return 0 }
        return (color.redComponent + color.greenComponent + color.blueComponent) / 3
    }

    private static func brightPixelCount(_ picture: NSBitmapImageRep) -> Int {
        var count = 0
        for y in 0..<picture.pixelsHigh {
            for x in 0..<picture.pixelsWide where brightness(picture, x, y) > 0.7 {
                count += 1
            }
        }
        return count
    }

    private static func changedRows(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> [Int] {
        (0..<a.pixelsHigh).filter { y in
            (0..<a.pixelsWide).contains { x in abs(brightness(a, x, y) - brightness(b, x, y)) > 0.02 }
        }
    }

    private static func busiestRow(_ rows: [Int], _ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Int {
        rows.max { first, second in
            changedCount(a, b, first) < changedCount(a, b, second)
        }!
    }

    private static func changedCount(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, _ y: Int) -> Int {
        (0..<a.pixelsWide).filter { x in abs(brightness(a, x, y) - brightness(b, x, y)) > 0.02 }.count
    }

    /// The middle of the brightest run down one column, in points from the
    /// top of the run's range.
    private static func thumbMiddle(_ picture: NSBitmapImageRep, column: CGFloat, from top: CGFloat, height: CGFloat) -> CGFloat? {
        let s = scale(picture)
        let x = Int(column * s)
        let rows = Int(top * s)..<Int((top + height) * s)
        let levels = rows.map { brightness(picture, x, $0) }
        guard let low = levels.min(), let high = levels.max(), high - low > 0.05 else { return nil }
        let cut = (low + high) / 2
        let thumb = levels.indices.filter { levels[$0] > cut }
        guard !thumb.isEmpty else { return nil }
        return CGFloat(thumb.reduce(0, +)) / CGFloat(thumb.count) / s
    }

    /// The middle of the brightest run on the bar's row, in pixels.
    private static func thumbCenter(_ picture: NSBitmapImageRep, row y: Int) -> CGFloat? {
        let levels = (0..<picture.pixelsWide).map { brightness(picture, $0, y) }
        guard let low = levels.min(), let high = levels.max(), high - low > 0.05 else { return nil }
        let cut = (low + high) / 2
        let thumb = levels.indices.filter { levels[$0] > cut }
        guard !thumb.isEmpty else { return nil }
        return CGFloat(thumb.reduce(0, +)) / CGFloat(thumb.count)
    }
}
