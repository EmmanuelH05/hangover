import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Draws the tray card in its states with `ImageRenderer`, on a store, a
/// pasteboard and settings of its own, held in memory. Set
/// `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to also write the PNGs to
/// `output/render/` under the repo root for a visual check.
///
/// `ImageRenderer` cannot draw AppKit-backed views, which is why the card
/// is drawn with its drop target off, and why a list too long for the card
/// (it scrolls) shows as a placeholder in these pictures and nowhere else.
@MainActor
struct NookTrayRenderTests {
    private static let scale: CGFloat = 2
    private static let snapshotEnvKey = "OPEN_ISLAND_RENDER_SNAPSHOTS"

    private static func cardSize(_ size: NookWidgetSize) -> CGSize {
        switch size {
        case .small: CGSize(width: 204, height: NookTrayCard.height(for: .small))
        case .medium: CGSize(width: 416, height: NookTrayCard.height(for: .medium))
        case .large: CGSize(width: 416, height: NookTrayCard.height(for: .large))
        }
    }

    private struct Fixture {
        let store: NookTrayStore
        let folder: URL
        let pasteboard: NookFakePasteboard
        let defaults: UserDefaults
        let suiteName: String

        @MainActor
        init() throws {
            folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("NookTrayRenderTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            suiteName = "NookTrayRenderTests"
            defaults = MemoryDefaults()
            pasteboard = NookFakePasteboard()
            store = NookTrayStore(
                folder: folder,
                clipboard: NookClipboardMonitor(pasteboard: pasteboard, defaults: defaults),
                defaults: defaults
            )
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: folder)
            defaults.removePersistentDomain(forName: suiteName)
        }

        @MainActor
        func copy(_ texts: [String]) {
            for text in texts {
                pasteboard.simulateCopy(.text(text))
                store.clipboard.poll()
            }
        }
    }

    @Test(arguments: NookWidgetSize.allCases)
    func theTwoTabsLookDifferent(size: NookWidgetSize) throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let files = try render("tray-\(size.rawValue)-files-empty", fixture.store, size)
        fixture.store.tab = .clipboard
        let offer = try render("tray-\(size.rawValue)-clipboard-offer", fixture.store, size)

        #expect(files != offer, "the clipboard tab should not look like the empty file list")
    }

    @Test(arguments: NookWidgetSize.allCases)
    func turningTheHistoryOnReplacesTheOfferWithTheCopies(size: NookWidgetSize) throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.store.tab = .clipboard
        let offer = try render("tray-\(size.rawValue)-clipboard-offer", fixture.store, size)

        fixture.store.clipboard.setEnabled(true)
        let empty = try render("tray-\(size.rawValue)-clipboard-empty", fixture.store, size)
        // Two rows fit every size without scrolling, which keeps them in
        // the picture.
        fixture.copy(["meeting at 3", "https://example.com/a/long/link/that/runs/off/the/edge/of/the/row"])
        let list = try render("tray-\(size.rawValue)-clipboard-list", fixture.store, size)
        let top = try #require(fixture.store.clipboard.history.entries.first)
        fixture.store.copyAgain(top)
        let copied = try render("tray-\(size.rawValue)-clipboard-copied", fixture.store, size)

        #expect(offer != empty)
        #expect(empty != list)
        #expect(list != copied, "the row just copied from should show a tick")
    }

    @Test(arguments: NookWidgetSize.allCases)
    func aHeldBackReadIsExplained(size: NookWidgetSize) throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.store.tab = .clipboard
        fixture.store.clipboard.setEnabled(true)
        let allowed = try render("tray-\(size.rawValue)-clipboard-empty", fixture.store, size)

        fixture.pasteboard.accessValue = .asks
        fixture.store.clipboard.poll()
        let asks = try render("tray-\(size.rawValue)-clipboard-asks", fixture.store, size)
        fixture.pasteboard.accessValue = .denied
        fixture.store.clipboard.poll()
        let denied = try render("tray-\(size.rawValue)-clipboard-denied", fixture.store, size)

        #expect(allowed != asks)
        #expect(asks != denied)
    }

    @Test func anActionsNoticeShowsOverTheCard() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.store.tab = .clipboard
        fixture.store.clipboard.setEnabled(true)
        let before = try render("tray-medium-notice-none", fixture.store, .medium)

        fixture.store.captureClipboardNow()
        let after = try render("tray-medium-notice", fixture.store, .medium)

        #expect(fixture.store.notice != nil)
        #expect(before != after)
    }

    // MARK: - Rendering

    private func render(_ name: String, _ store: NookTrayStore, _ size: NookWidgetSize) throws -> Data {
        let cardSize = Self.cardSize(size)
        let framed = NookTrayCard(store: store, takesDrops: false)
            .environment(\.nookWidgetSize, size)
            .frame(width: cardSize.width, height: cardSize.height)
            .padding(8)
            .background(V6Palette.ink)
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: framed)
        renderer.scale = Self.scale
        let rendered = renderer.cgImage
        let image = try #require(rendered, "ImageRenderer returned no image for \(name)")

        let representation = NSBitmapImageRep(cgImage: image)
        let encoded = representation.representation(using: .png, properties: [:])
        let png = try #require(encoded, "PNG encoding failed for \(name)")

        if ProcessInfo.processInfo.environment[Self.snapshotEnvKey] == "1" {
            let directory = Self.repoRoot.appendingPathComponent("output/render", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return png
    }

    /// `Tests/OpenIslandAppTests/<this file>` sits three levels below the root.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
