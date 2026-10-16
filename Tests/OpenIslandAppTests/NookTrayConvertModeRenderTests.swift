import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Draws a view the way the tray's render tests do: dark, with the motion
/// stopped, at twice the size. Set `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to also
/// write the PNGs to `output/render/` under the repo root for a visual check.
enum NookConvertModeSnapshot {
    @MainActor
    /// `cropTop` drops that many points off the top first, which lets a test
    /// compare the tiles without the header above them.
    static func render<Content: View>(_ name: String, _ view: Content, cropTop: CGFloat = 0, filePath: String = #filePath) throws -> Data {
        let framed = view
            .background(V6Palette.ink)
            .environment(\.colorScheme, .dark)
            .environment(\.nookDrawsStill, true)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        let whole = try #require(renderer.cgImage, "ImageRenderer returned no image for \(name)")
        let top = Int(cropTop * renderer.scale)
        let image = try #require(
            whole.cropping(to: CGRect(x: 0, y: top, width: whole.width, height: whole.height - top)),
            "could not crop \(name)"
        )
        let png = try #require(
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
            "PNG encoding failed for \(name)"
        )
        if ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_SNAPSHOTS"] == "1" {
            let directory = URL(fileURLWithPath: filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("output/render", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return png
    }

    /// The height a view takes at `width` when it is free to choose, in
    /// points. The strip's fit test reads this to see that its rows fit.
    @MainActor
    static func naturalHeight<Content: View>(of view: Content, width: CGFloat) throws -> CGFloat {
        let sized = view
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.nookDrawsStill, true)
        let renderer = ImageRenderer(content: sized)
        renderer.scale = 1
        let image = try #require(renderer.cgImage, "ImageRenderer returned no image")
        return CGFloat(image.height)
    }
}

// MARK: - Rules

@Suite struct NookTrayHeaderRulesTests {
    @Test func theConvertChipShowsOnTheFilesTabOfACardWithFiles() {
        #expect(NookTrayHeaderRules.showsConvertChip(tab: .files, hasFiles: true))
    }

    @Test func theChipHasNothingToConvertInAnEmptyTray() {
        #expect(!NookTrayHeaderRules.showsConvertChip(tab: .files, hasFiles: false))
    }

    @Test func theChipBelongsToFilesAndNotToTheClipboard() {
        #expect(!NookTrayHeaderRules.showsConvertChip(tab: .clipboard, hasFiles: true))
    }
}

// MARK: - The header and the card

@MainActor @Suite(.serialized, .noNewWindows) struct NookTrayConvertModeRenderTests {
    private func header(_ store: NookTrayStore, size: NookWidgetSize = .medium, width: CGFloat? = nil) -> some View {
        NookTrayHeader(store: store)
            .environment(\.nookWidgetSize, size)
            .frame(width: width ?? (size == .small ? 176 : 388))
            .padding(14)
    }

    /// Where the tiles start in `card`: the 8 point margin, the card's 12
    /// point padding and the header row. Cropping there leaves only the tiles.
    private static let belowHeader: CGFloat = 8 + 12 + NookTrayHeaderLayout.height + 2

    private func card(_ store: NookTrayStore, size: NookWidgetSize) -> some View {
        NookTrayCard(store: store, takesDrops: false)
            .environment(\.nookWidgetSize, size)
            .frame(width: size == .small ? 204 : 416, height: NookTrayCard.height(for: size))
            .padding(8)
    }

    @Test func theHeaderShowsTheChipOffAndThenWhilePicking() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        try await fixture.add(try fixture.files.png(width: 16, height: 16), named: "photo.png")
        try await fixture.add(try fixture.files.pdf(pages: 1), named: "notes.pdf")

        let off = try NookConvertModeSnapshot.render("tray-convert-mode-header-off", header(fixture.store))
        fixture.store.beginPickingToConvert()
        let picking = try NookConvertModeSnapshot.render("tray-convert-mode-header-picking", header(fixture.store))
        fixture.store.cancelPickingToConvert()
        let offAgain = try NookConvertModeSnapshot.render("tray-convert-mode-header-off-again", header(fixture.store))

        #expect(off != picking, "the chip should fill and say what to do while picking")
        #expect(off == offAgain, "cancelling should bring the chip back to how it was")
    }

    /// Every card size has the chip, the small one too: small is short, not
    /// narrow (the owner looked for it on a small card). Picking changes how
    /// the chip looks, which a header without the chip could not show. The
    /// narrow width checks the chip that keeps only its icon.
    @Test(arguments: zip([NookWidgetSize.small, .small, .medium, .large], [CGFloat(388), 176, 388, 388]))
    func theChipIsDrawnAtEverySize(size: NookWidgetSize, width: CGFloat) async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        try await fixture.add(try fixture.files.png(width: 16, height: 16), named: "photo.png")
        let name = "tray-convert-mode-header-\(size.rawValue)-\(Int(width))"
        let off = try NookConvertModeSnapshot.render(name, header(fixture.store, size: size, width: width))
        fixture.store.beginPickingToConvert()
        let picking = try NookConvertModeSnapshot.render("\(name)-picking", header(fixture.store, size: size, width: width))

        #expect(off != picking, "the \(size.rawValue) header at \(Int(width)) points should draw the chip")
    }

    @Test func theClipboardTabHasNoChip() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let empty = try NookConvertModeSnapshot.render("tray-convert-mode-header-empty", header(fixture.store))
        try await fixture.add(try fixture.files.png(width: 16, height: 16), named: "photo.png")
        let withFiles = try NookConvertModeSnapshot.render("tray-convert-mode-header-with-files", header(fixture.store))
        fixture.store.tab = .clipboard
        let clipboard = try NookConvertModeSnapshot.render("tray-convert-mode-header-clipboard", header(fixture.store))
        // Picking is set by hand here: choosing the clipboard ends it.
        fixture.store.isPickingToConvert = true
        let clipboardPicking = try NookConvertModeSnapshot.render("tray-convert-mode-header-clipboard-picking", header(fixture.store))

        #expect(empty != withFiles, "a tray with a file shows its count and the chip")
        #expect(withFiles != clipboard, "the clipboard tab shows no chip and no count")
        #expect(clipboard == clipboardPicking, "no chip on the clipboard tab, picking or not")
    }

    @Test(arguments: [NookWidgetSize.medium, .large])
    func pickingLightsUpTheFilesThatCanBeConvertedAndDimsTheRest(size: NookWidgetSize) async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let notes = fixture.files.url("notes.txt")
        try Data("plain text".utf8).write(to: notes)
        try await fixture.add(notes, named: "notes.txt")
        try await fixture.add(try fixture.files.png(width: 16, height: 16), named: "photo.png")
        try await fixture.add(try fixture.files.pdf(pages: 1), named: "report.pdf")

        // Only the tiles are compared: the chip changes too, and would pass
        // this on its own.
        let plain = try NookConvertModeSnapshot.render("tray-convert-mode-\(size.rawValue)-plain", card(fixture.store, size: size), cropTop: Self.belowHeader)
        fixture.store.beginPickingToConvert()
        let picking = try NookConvertModeSnapshot.render("tray-convert-mode-\(size.rawValue)-picking", card(fixture.store, size: size), cropTop: Self.belowHeader)
        fixture.store.cancelPickingToConvert()
        let after = try NookConvertModeSnapshot.render("tray-convert-mode-\(size.rawValue)-plain-again", card(fixture.store, size: size), cropTop: Self.belowHeader)

        #expect(plain != picking, "the \(size.rawValue) card's tiles should look different while picking")
        #expect(plain == after)
    }

    @Test func aTrayOfFilesThatCannotBeConvertedStillDimsWhilePicking() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let notes = fixture.files.url("notes.txt")
        try Data("plain text".utf8).write(to: notes)
        try await fixture.add(notes, named: "notes.txt")

        let plain = try NookConvertModeSnapshot.render("tray-convert-mode-nothing-to-pick-plain", card(fixture.store, size: .medium), cropTop: Self.belowHeader)
        fixture.store.beginPickingToConvert()
        let picking = try NookConvertModeSnapshot.render("tray-convert-mode-nothing-to-pick", card(fixture.store, size: .medium), cropTop: Self.belowHeader)

        #expect(plain != picking, "the dimmed tile says there is nothing to pick")
    }

    @Test func theSmallCardTakesPartInPicking() async throws {
        let fixture = try NookTrayFixesFixture()
        defer { fixture.cleanUp() }
        let notes = fixture.files.url("notes.txt")
        try Data("plain text".utf8).write(to: notes)
        try await fixture.add(notes, named: "notes.txt")
        try await fixture.add(try fixture.files.png(width: 16, height: 16), named: "photo.png")
        let plain = try NookConvertModeSnapshot.render("tray-convert-mode-small-plain", card(fixture.store, size: .small), cropTop: Self.belowHeader)

        fixture.store.beginPickingToConvert()
        let picking = try NookConvertModeSnapshot.render("tray-convert-mode-small-picking", card(fixture.store, size: .small), cropTop: Self.belowHeader)

        #expect(plain != picking, "the small card's tiles light up and dim like the others")
    }
}
