import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Draws the tray card with 145 files in both overflow modes, the O2 sample
/// of the design: newest first, clip.mp4 to demo.mp3, then take 1.mp4 up to
/// take 136.mp4. Set `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to also write the PNGs
/// to `output/render/tray-overflow/` under the repo root for a visual check.
///
/// `ImageRenderer` cannot draw AppKit-backed views, which is why the card is
/// drawn with its drop target off.
@MainActor @Suite(.serialized, .noNewWindows)
struct NookTrayOverflowRenderTests {
    private static let scale: CGFloat = 2
    private static let snapshotEnvKey = "OPEN_ISLAND_RENDER_SNAPSHOTS"

    private static func cardSize(_ size: NookWidgetSize) -> CGSize {
        switch size {
        case .small: CGSize(width: 313, height: NookTrayCard.height(for: .small))
        case .medium: CGSize(width: 640, height: NookTrayCard.height(for: .medium))
        case .large: CGSize(width: 416, height: NookTrayCard.height(for: .large))
        }
    }

    /// The names of the O2 sample, newest first.
    private static var sampleNames: [String] {
        ["clip.mp4", "demo.mp4", "intro.mp4", "notes.pdf", "mock.png", "main.swift", "data.csv", "build.zip", "demo.mp3"]
            + (1...136).map { "take \($0).mp4" }
    }

    private struct Fixture {
        let store: NookTrayStore
        let folder: URL
        let incoming: URL
        let defaults: UserDefaults

        @MainActor
        init() async throws {
            let id = UUID().uuidString
            folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("NookTrayOverflowRender-\(id)", isDirectory: true)
            incoming = FileManager.default.temporaryDirectory
                .appendingPathComponent("NookTrayOverflowRenderIncoming-\(id)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
            defaults = MemoryDefaults()
            store = NookTrayStore(
                folder: folder,
                clipboard: NookClipboardMonitor(pasteboard: NookFakePasteboard(), defaults: defaults),
                defaults: defaults
            )
            // The newest file goes in last, which puts clip.mp4 first.
            for name in NookTrayOverflowRenderTests.sampleNames.reversed() {
                let source = incoming.appendingPathComponent(name)
                try Data("x".utf8).write(to: source)
                await store.add(fileAt: source)?.value
            }
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: incoming)
        }
    }

    @Test func theSampleHasTheDesignsOrder() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        #expect(fixture.store.items.count == 145)
        #expect(fixture.store.items.first?.originalName == "clip.mp4")
        #expect(fixture.store.items.last?.originalName == "take 136.mp4")
    }

    @Test(arguments: [NookWidgetSize.small, .medium])
    func scrollAndCountLookDifferent(size: NookWidgetSize) async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }

        fixture.store.overflow = .scroll
        let scroll = try render("scroll-\(size.rawValue)", fixture.store, size)
        fixture.store.overflow = .count
        let count = try render("fill-\(size.rawValue)", fixture.store, size)

        #expect(!scroll.isEmpty)
        #expect(!count.isEmpty)
        #expect(scroll != count, "Scroll and Count them should not draw the same row at \(size.rawValue)")
    }

    @Test func theLargeCardShowsItsOutlineWhileEveryFileIsOpen() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }

        let closed = try render("large-more", fixture.store, .large)
        fixture.store.showAllFiles()
        #expect(fixture.store.isShowingAllFiles)
        let open = try render("large-more-open", fixture.store, .large)

        #expect(!open.isEmpty)
        #expect(closed != open, "the +N tile should be outlined while every file is open")
    }

    @Test func theLargeGridIsTheSameInBothModes() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }

        fixture.store.overflow = .scroll
        let scroll = try render("large-scroll-mode", fixture.store, .large)
        fixture.store.overflow = .count
        let count = try render("large-count-mode", fixture.store, .large)

        #expect(scroll == count)
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

        let renderer = ImageRenderer(content: framed.environment(\.nookDrawsStill, true))
        renderer.scale = Self.scale
        let rendered = renderer.cgImage
        let image = try #require(rendered, "ImageRenderer returned no image for \(name)")

        let representation = NSBitmapImageRep(cgImage: image)
        let encoded = representation.representation(using: .png, properties: [:])
        let png = try #require(encoded, "PNG encoding failed for \(name)")

        let wanted = ["scroll-small", "scroll-medium", "fill-small", "fill-medium", "large-more-open"]
        if ProcessInfo.processInfo.environment[Self.snapshotEnvKey] == "1", wanted.contains(name) {
            let directory = Self.repoRoot.appendingPathComponent("output/render/tray-overflow", isDirectory: true)
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
