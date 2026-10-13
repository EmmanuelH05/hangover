import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Draws the design kit's card, a floating reference panel and the
/// palette editor with `ImageRenderer`, on a kit of their own with files
/// in a temporary folder. Set `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to also
/// write the PNGs to `output/render/design/` under the repo root for a
/// visual check.
///
/// `ImageRenderer` cannot draw AppKit-backed views, which is why every
/// view here is drawn still: text fields, the opacity slider, scroll
/// views and drop targets are swapped for plain look-alikes. No window is
/// opened and the system's color sampler is never called.
@MainActor
struct NookDesignRenderTests {
    private typealias Samples = NookDesignSamples

    private static let scale: CGFloat = 2
    private static let snapshotEnvKey = "OPEN_ISLAND_RENDER_SNAPSHOTS"

    private static func cardSize(_ size: NookWidgetSize) -> CGSize {
        CGSize(width: size == .small ? 204 : 416, height: NookDesignCard.height(for: size))
    }

    private static let brand: [(String, String, Bool)] = [
        ("Ember", "#FF6B35", true), ("Sun", "#F7C548", false), ("Lagoon", "#2EC4B6", false),
        ("Sky", "#3A86FF", true), ("Iris", "#8338EC", false), ("Paper", "#F4F1EA", false),
        ("Ink", "#1B1B1F", false), ("Scrim", "#00000080", false), ("", "#FF006E", false),
    ]

    /// A palette called Brand with nine colors, two of them favorites and
    /// one see-through, and a second palette beside it.
    private func fillColors(_ kit: NookDesignKit) throws {
        let grays = try #require(kit.palettes.addPalette(named: "Grays"))
        kit.palettes.addColor(Samples.ink, named: "Ink", to: grays.id, defaultPaletteName: "")
        let brand = try #require(kit.palettes.addPalette(named: "Brand"))
        for (name, hex, isFavorite) in Self.brand {
            let color = try #require(NookDesignColorParser.parse(hex))
            guard case let .added(_, swatch) = kit.palettes.addColor(color, named: name, to: brand.id, defaultPaletteName: "") else {
                continue
            }
            if isFavorite { kit.palettes.toggleFavorite(swatch.id) }
        }
        for hex in ["#0B132B", "#5BC0BE", "#FFD166", "#EF476F"] {
            kit.palettes.recordRecent(try #require(NookDesignColorParser.parse(hex)))
        }
    }

    /// Five pictures of different shapes, one of them a favorite, with
    /// their thumbnails decoded.
    private func fillReferences(_ fixture: NookDesignFixture) async throws -> [NookDesignReference] {
        let shapes: [(String, Int, Int)] = [
            ("Landing hero", 320, 180), ("Phone flow", 180, 390), ("Icon set", 240, 240),
            ("Wide banner", 600, 150), ("Type sample", 260, 200),
        ]
        var items: [NookDesignReference] = []
        for (name, width, height) in shapes {
            items.append(try await fixture.addPicture(named: "\(name).png", width: width, height: height))
        }
        fixture.kit.references.toggleFavorite(items[1].id)
        for item in fixture.kit.references.items {
            fixture.kit.references.requestThumbnail(for: item)
        }
        let decoded = await Samples.wait { fixture.kit.references.thumbnails.count == items.count }
        #expect(decoded, "the thumbnails were not decoded in time")
        return items
    }

    // MARK: Colors

    @Test(arguments: NookWidgetSize.allCases)
    func theColorsTabShowsSwatchesOnceThereAreSome(size: NookWidgetSize) async throws {
        let fixture = try await NookDesignFixture("render")
        defer { fixture.cleanUp() }

        let empty = try card("design-\(size.rawValue)-colors-empty", fixture.kit, size)
        try fillColors(fixture.kit)
        let filled = try card("design-\(size.rawValue)-colors", fixture.kit, size)

        #expect(empty != filled)
    }

    @Test(arguments: NookWidgetSize.allCases)
    func aCopiedSwatchShowsATickAndALine(size: NookWidgetSize) async throws {
        let fixture = try await NookDesignFixture("render")
        defer { fixture.cleanUp() }
        try fillColors(fixture.kit)
        let before = try card("design-\(size.rawValue)-colors", fixture.kit, size)

        let first = try #require(fixture.kit.palettes.activePalette.map { NookDesignLibrary.compactOrder($0.swatches) }?.first)
        fixture.kit.copy(first.color, from: first.id)
        let copied = try card("design-\(size.rawValue)-colors-copied", fixture.kit, size)

        #expect(before != copied)
        #expect(fixture.copies.texts == ["#FF6B35"])
    }

    @Test(arguments: NookWidgetSize.allCases)
    func aPickShowsItsColorAndSaysItWasCopied(size: NookWidgetSize) async throws {
        let fixture = try await NookDesignFixture("render")
        defer { fixture.cleanUp() }
        try fillColors(fixture.kit)
        fixture.kit.pickColor(from: .shortcut)
        let sampling = try card("design-\(size.rawValue)-colors-sampling", fixture.kit, size)

        fixture.sampler.finish(NookDesignColor(red: 6, green: 214, blue: 160))
        let picked = try card("design-\(size.rawValue)-colors-picked", fixture.kit, size)

        #expect(sampling != picked)
    }

    @Test(arguments: NookWidgetSize.allCases)
    func aPaletteTooLongForTheCardEndsInAPlusTile(size: NookWidgetSize) async throws {
        let fixture = try await NookDesignFixture("render")
        defer { fixture.cleanUp() }
        try fillColors(fixture.kit)
        let few = try card("design-\(size.rawValue)-colors", fixture.kit, size)

        for index in 0..<40 {
            fixture.kit.palettes.addColor(
                NookDesignColor(hue: Double(index) * 9, saturation: 0.7, lightness: 0.55),
                defaultPaletteName: ""
            )
        }
        let many = try card("design-\(size.rawValue)-colors-many", fixture.kit, size)

        #expect(few != many)
    }

    @Test func theFormatAndPaletteSwitchesShowWhatIsChosen() async throws {
        let fixture = try await NookDesignFixture("render")
        defer { fixture.cleanUp() }
        try fillColors(fixture.kit)
        let hex = try card("design-medium-colors", fixture.kit, .medium)

        fixture.kit.copyFormat = .hsl
        fixture.kit.palettes.selectNextPalette()
        let switched = try card("design-medium-colors-switched", fixture.kit, .medium)

        #expect(hex != switched)
    }

    // MARK: References

    @Test(arguments: NookWidgetSize.allCases)
    func theReferencesTabShowsThumbnailsOnceThereAreSome(size: NookWidgetSize) async throws {
        let fixture = try await NookDesignFixture("render")
        defer { fixture.cleanUp() }
        fixture.kit.tab = .references

        let empty = try card("design-\(size.rawValue)-references-empty", fixture.kit, size)
        _ = try await fillReferences(fixture)
        let filled = try card("design-\(size.rawValue)-references", fixture.kit, size)

        #expect(empty != filled)
    }

    @Test(arguments: NookWidgetSize.allCases)
    func aFloatingPictureIsMarkedOnItsTile(size: NookWidgetSize) async throws {
        let fixture = try await NookDesignFixture("render")
        defer { fixture.cleanUp() }
        fixture.kit.tab = .references
        let items = try await fillReferences(fixture)
        let resting = try card("design-\(size.rawValue)-references", fixture.kit, size)

        // The newest picture is the first tile, which every size shows.
        await fixture.kit.openReference(items[4].id)?.value
        await fixture.kit.openReference(items[3].id)?.value
        let floating = try card("design-\(size.rawValue)-references-floating", fixture.kit, size)

        #expect(resting != floating)
        #expect(fixture.presenter.presented.count == 2)
    }

    @Test(arguments: NookWidgetSize.allCases)
    func picturesDraggedOverTheCardLightItUp(size: NookWidgetSize) async throws {
        let fixture = try await NookDesignFixture("render")
        defer { fixture.cleanUp() }
        fixture.kit.tab = .references
        let resting = try card("design-\(size.rawValue)-references-empty", fixture.kit, size)

        fixture.kit.isPictureDragOverCard = true
        let over = try card("design-\(size.rawValue)-drop", fixture.kit, size)

        #expect(resting != over)
    }

    @Test func aPictureBeingRenamedShowsItsField() async throws {
        let fixture = try await NookDesignFixture("render")
        defer { fixture.cleanUp() }
        fixture.kit.tab = .references
        let items = try await fillReferences(fixture)
        let resting = try card("design-large-references", fixture.kit, .large)

        fixture.kit.renamingReferenceID = items[4].id
        let renaming = try card("design-large-references-renaming", fixture.kit, .large)

        #expect(resting != renaming)
    }

    @Test func theSettingsPreviewHasASampleAtEverySize() throws {
        for size in NookWidgetSize.allCases {
            let cardSize = Self.cardSize(size)
            let sample = NookSampleCard(kind: .design, size: size, calendarStyle: .strip)
                .frame(width: cardSize.width, height: cardSize.height)
            _ = try render("design-\(size.rawValue)-sample", sample.padding(8).background(V6Palette.ink))
        }
    }

    // MARK: Floating panel

    @Test func theFloatingPanelShowsThePictureOverItsControls() async throws {
        let panel = try #require(Self.picture(width: 480, height: 320))
        let reference = NookDesignReference(
            id: UUID(), collectionID: NookDesignCollection.globalID, name: "Landing hero",
            fileName: "original.png", pixelWidth: 480, pixelHeight: 320, isFavorite: false, addedAt: Samples.day
        )
        let state = NookDesignPanelState(reference: reference, image: panel)
        let size = NookDesignPanelRules.initialSize(pictureAspect: reference.aspectRatio, available: CGSize(width: 1400, height: 880))

        let fit = try self.panel("design-panel-fit", state, size)
        state.zoom = state.zoom.zoomed(to: 2.5, around: CGPoint(x: -0.3, y: -0.3), fitted: state.fitted)
        let zoomed = try self.panel("design-panel-zoomed", state, size)
        state.isFocused = true
        state.isPinned = false
        state.opacity = 0.5
        let focused = try self.panel("design-panel-focused", state, size)

        #expect(fit != zoomed)
        #expect(zoomed != focused)
        #expect(state.zoom.percentText == "250%")
    }

    @Test func aLongPageIsFittedInsideItsPanel() async throws {
        let page = try #require(Self.picture(width: 200, height: 1600))
        let reference = NookDesignReference(
            id: UUID(), collectionID: NookDesignCollection.globalID, name: "Long page",
            fileName: "original.png", pixelWidth: 200, pixelHeight: 1600, isFavorite: false, addedAt: Samples.day
        )
        let state = NookDesignPanelState(reference: reference, image: page)
        let size = NookDesignPanelRules.initialSize(pictureAspect: reference.aspectRatio, available: CGSize(width: 1400, height: 880))

        let fit = try self.panel("design-panel-long-fit", state, size)
        // Four times is the page at the panel's full width.
        state.zoom = state.zoom.zoomed(to: 4, fitted: state.fitted)
            .panned(by: CGSize(width: 0, height: 9), fitted: state.fitted)
        let reading = try self.panel("design-panel-long-zoomed", state, size)

        #expect(fit != reading)
        #expect(size == NookDesignPanelRules.panelSize(width: NookDesignPanelRules.minimumWidth, pictureAspect: 0.125))
    }

    @Test(arguments: NookWidgetSize.allCases)
    func theKeepPickingPillFollowsTheSetting(size: NookWidgetSize) async throws {
        let fixture = try await NookDesignFixture("render")
        defer { fixture.cleanUp() }
        try fillColors(fixture.kit)
        let off = try card("design-\(size.rawValue)-colors", fixture.kit, size)

        fixture.kit.keepsPicking = true
        let resting = try card("design-\(size.rawValue)-colors-keep-picking", fixture.kit, size)
        fixture.kit.pickColor(from: .shortcut)
        let sampling = try card("design-\(size.rawValue)-colors-keep-picking-sampling", fixture.kit, size)

        #expect(off != resting, "the pill shows nothing about the mode")
        #expect(resting != sampling)
    }

    /// An open picture adds a button to the row, which is the one case where
    /// the pill has no room beside the tab names at the wider sizes.
    @Test(arguments: NookWidgetSize.allCases)
    func thePillHasItsPlaceOnTheReferencesTabWithAPictureFloating(size: NookWidgetSize) async throws {
        let fixture = try await NookDesignFixture("render")
        defer { fixture.cleanUp() }
        fixture.kit.tab = .references
        let items = try await fillReferences(fixture)
        await fixture.kit.openReference(items[4].id)?.value
        let off = try card("design-\(size.rawValue)-references-one-floating", fixture.kit, size)

        fixture.kit.keepsPicking = true
        let on = try card("design-\(size.rawValue)-references-one-floating-keep-picking", fixture.kit, size)

        #expect(off != on)
    }

    // MARK: Palette editor

    @Test func thePaletteEditorListsPalettesAndTheirColors() async throws {
        let fixture = try await NookDesignFixture("render")
        defer { fixture.cleanUp() }
        let none = try editor("design-editor-empty", fixture.kit)

        try fillColors(fixture.kit)
        let filled = try editor("design-editor", fixture.kit)
        fixture.kit.palettes.selectNextPalette()
        fixture.kit.savesPicksToPalette = true
        fixture.kit.copyFormat = .rgb
        let other = try editor("design-editor-other-palette", fixture.kit)

        #expect(none != filled)
        #expect(filled != other)
    }

    // MARK: Rendering

    private func card(_ name: String, _ kit: NookDesignKit, _ size: NookWidgetSize) throws -> Data {
        let cardSize = Self.cardSize(size)
        let framed = NookDesignCard(kit: kit, isStill: true)
            .environment(\.nookWidgetSize, size)
            .frame(width: cardSize.width, height: cardSize.height)
            .padding(8)
            .background(V6Palette.ink)
            .environment(\.colorScheme, .dark)
        return try render(name, framed)
    }

    private func panel(_ name: String, _ state: NookDesignPanelState, _ size: CGSize) throws -> Data {
        let framed = NookDesignPanelView(state: state, actions: NookDesignPanelActions(), isStill: true)
            .frame(width: size.width, height: size.height)
            // The window fades as one piece, which is what its alpha does.
            .compositingGroup()
            .opacity(state.opacity)
            .padding(16)
            .background(Color(white: 0.35))
        return try render(name, framed)
    }

    private func editor(_ name: String, _ kit: NookDesignKit) throws -> Data {
        let size = NookDesignPaletteEditor.idealSize
        let framed = NookDesignPaletteEditor(kit: kit, isStill: true)
            .frame(width: size.width, height: size.height)
        return try render(name, framed)
    }

    private func render(_ name: String, _ view: some View) throws -> Data {
        let renderer = ImageRenderer(content: view)
        renderer.scale = Self.scale
        let rendered = renderer.cgImage
        let image = try #require(rendered, "ImageRenderer returned no image for \(name)")

        let representation = NSBitmapImageRep(cgImage: image)
        let encoded = representation.representation(using: .png, properties: [:])
        let png = try #require(encoded, "PNG encoding failed for \(name)")

        if ProcessInfo.processInfo.environment[Self.snapshotEnvKey] == "1" {
            let directory = Self.repoRoot.appendingPathComponent("output/render/design", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return png
    }

    /// A picture with bands of color and a few shapes, drawn in memory.
    private static func picture(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let bands: [NookDesignColor] = [
            NookDesignColor(red: 255, green: 107, blue: 53), NookDesignColor(red: 247, green: 197, blue: 72),
            NookDesignColor(red: 46, green: 196, blue: 182), NookDesignColor(red: 58, green: 134, blue: 255),
            NookDesignColor(red: 131, green: 56, blue: 236),
        ]
        let bandHeight = CGFloat(height) / CGFloat(bands.count)
        for (index, color) in bands.enumerated() {
            context.setFillColor(
                red: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255,
                blue: CGFloat(color.blue) / 255, alpha: 1
            )
            context.fill(CGRect(x: 0, y: CGFloat(index) * bandHeight, width: CGFloat(width), height: bandHeight))
        }
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.85)
        let side = CGFloat(min(width, height)) * 0.4
        context.fillEllipse(in: CGRect(x: CGFloat(width) * 0.1, y: CGFloat(height) * 0.55, width: side, height: side))
        context.setFillColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 0.9)
        context.fill(CGRect(x: CGFloat(width) * 0.55, y: CGFloat(height) * 0.1, width: side, height: side * 0.6))
        return context.makeImage()
    }

    /// `Tests/OpenIslandAppTests/<this file>` sits three levels below the root.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
