import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Draws the photo booth's Settings section the way Settings shows it, with
/// the previews already in. Set `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to also
/// write the pictures to `output/render/photo-booth/` under the repo root.
/// Nothing here opens a window, starts the camera or touches the standard
/// settings. A render cannot draw the system's own controls. The countdown
/// menu, the sound switch and the caption field show as yellow stand-ins in
/// the pictures, and the tiles are drawn in full.
@Suite(.serialized, .oneStripAtATime)
struct NookPhotoBoothSettingsRenderTests {
    private static let width: CGFloat = 560

    /// The section as a picture. With `drawsPreviews` false the cache is left
    /// empty, which shows what a tile looks like before its picture arrives.
    @MainActor
    private static func png(
        layout: NookPhotoStripLayout.Kind,
        themeID: String,
        caption: String,
        drawsPreviews: Bool = true
    ) async throws -> Data {
        let nook = NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
        let booth = nook.photoBooth
        booth.layoutKind = layout
        booth.themeID = themeID
        booth.caption = caption

        // The previews are drawn first: a render does not wait for a task.
        let previews = NookPhotoBoothPreviews()
        let set = NookPhotoBoothPreviewSet(
            layout: booth.layoutKind,
            theme: booth.theme,
            typedCaption: caption,
            defaultLine: booth.defaultCaption
        )
        if drawsPreviews {
            await previews.request(set.keys)
            #expect(set.keys.allSatisfy { previews.image(for: $0) != nil }, "a preview was not drawn")
        }

        let content = VStack(alignment: .leading, spacing: 10) {
            NookPhotoBoothSettings(nook: nook, previews: previews)
        }
        .padding(20)
        .frame(width: width, alignment: .topLeading)
        .background(Color(white: 0.12))
        .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.cgImage, "no picture of the settings")
        return try #require(NookPhotoBoothImaging.pngData(image), "no PNG of the settings")
    }

    private static func write(_ name: String, _ png: Data) throws {
        guard ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_SNAPSHOTS"] == "1" else { return }
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("output/render/photo-booth", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    @MainActor
    @Test func theSectionShowsEveryLayoutAndTheme() async throws {
        let classic = try await Self.png(layout: .classic, themeID: "gingham", caption: "")
        try Self.write("settings-classic-layout", classic)
        let grid = try await Self.png(layout: .grid, themeID: "film", caption: "Friday night")
        try Self.write("settings-grid-layout", grid)
    }

    /// The pictures in the tiles are the previews. The same section drawn
    /// before they arrive is only the empty places, and is a different picture.
    @MainActor
    @Test func theTilesShowTheirPreviews() async throws {
        let drawn = try await Self.png(layout: .classic, themeID: "gingham", caption: "")
        let waiting = try await Self.png(layout: .classic, themeID: "gingham", caption: "", drawsPreviews: false)
        #expect(drawn != waiting)
        #expect(drawn.count > waiting.count, "the previews add detail the empty places do not have")
    }
}
