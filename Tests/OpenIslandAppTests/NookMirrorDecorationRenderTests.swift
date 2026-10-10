import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Draws every frame and sticker with `ImageRenderer`, the way the photo
/// booth draws them into a photo, and reads the pixels back. Only the
/// decoration overlay is drawn: never the live mirror, never the camera.
/// Set `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to also write contact sheets to
/// `output/render/decorations/` under the repo root for a visual check.
@MainActor
@Suite struct NookMirrorDecorationRenderTests {
    private static let snapshotEnvKey = "OPEN_ISLAND_RENDER_SNAPSHOTS"
    /// The mirror's picture on the notch page.
    private static let picture = CGSize(width: 432, height: 243)

    /// Pixels of a drawing, four bytes each, alpha last.
    private struct Bitmap {
        let pixels: [UInt8]
        let width: Int
        let height: Int

        func alpha(x: Int, y: Int) -> UInt8 { pixels[(y * width + x) * 4 + 3] }

        /// How many pixels in a part of the drawing are more than faintly there.
        func inked(in rect: CGRect? = nil) -> Int {
            let area = rect ?? CGRect(x: 0, y: 0, width: width, height: height)
            var count = 0
            for y in max(0, Int(area.minY))..<min(height, Int(area.maxY)) {
                for x in max(0, Int(area.minX))..<min(width, Int(area.maxX)) where alpha(x: x, y: y) > 8 {
                    count += 1
                }
            }
            return count
        }
    }

    private static func bitmap(_ view: some View, size: CGSize, scale: CGFloat = 1) throws -> Bitmap {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = scale
        let image = try #require(renderer.cgImage, "the drawing did not render")
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        try #require(drawn, "the pixels could not be read")
        return Bitmap(pixels: pixels, width: image.width, height: image.height)
    }

    private static func overlay(_ decorations: NookMirrorDecorationSet) -> some View {
        NookMirrorDecorationOverlay(decorations: decorations)
    }

    // MARK: The designs

    @Test func thereAreEnoughDesignsAndNoIDIsUsedTwice() {
        #expect(NookMirrorDesigns.frames.count >= 10)
        #expect(NookMirrorDesigns.stickers.count >= 24)
        #expect(NookMirrorDesigns.frameIDs.count == NookMirrorDesigns.frames.count)
        #expect(NookMirrorDesigns.stickerIDs.count == NookMirrorDesigns.stickers.count)
        #expect(NookMirrorDesigns.frameIDs.isDisjoint(with: NookMirrorDesigns.stickerIDs))
        for design in NookMirrorDesigns.stickers {
            #expect(design.variants >= 1, "\(design.id) has no colorway")
            #expect(design.wrapped(design.variants) == 0)
            #expect(design.wrapped(-1) == design.variants - 1)
        }
    }

    @Test func everyFrameDrawsAroundTheEdgeAndLeavesTheMiddleClear() throws {
        // A frame may reach 15 hundredths of the picture's height in from
        // an edge. The middle 70 percent each way is the face's.
        let reach = NookMirrorFrameDesigns.deepestReach / 100
        let middle = CGRect(
            x: Self.picture.width * reach,
            y: Self.picture.height * reach,
            width: Self.picture.width * (1 - 2 * reach),
            height: Self.picture.height * (1 - 2 * reach)
        )
        for design in NookMirrorDesigns.frames {
            let drawing = try Self.bitmap(
                Self.overlay(NookMirrorDecorationSet(frameID: design.id)), size: Self.picture
            )
            #expect(drawing.inked() > 400, "\(design.id) draws almost nothing")
            #expect(drawing.inked(in: middle) == 0, "\(design.id) draws over the middle of the picture")
        }
    }

    @Test func everyStickerDrawsSomethingInEveryColorway() throws {
        let side = CGSize(width: 120, height: 120)
        for design in NookMirrorDesigns.stickers {
            var first: [UInt8]?
            for variant in 0..<design.variants {
                let drawing = try Self.bitmap(
                    NookMirrorStickerThumbnail(design: design, variant: variant), size: side
                )
                #expect(drawing.inked() > 600, "\(design.id) colorway \(variant) draws almost nothing")
                if let first {
                    #expect(drawing.pixels != first, "\(design.id) colorway \(variant) looks like the first one")
                } else {
                    first = drawing.pixels
                }
            }
        }
    }

    @Test func aStickerStillShowsAtTheSizeOfAPickerTile() throws {
        let tile = CGSize(width: 40, height: 40)
        for design in NookMirrorDesigns.stickers {
            let drawing = try Self.bitmap(NookMirrorStickerThumbnail(design: design), size: tile, scale: 2)
            #expect(drawing.inked() > 500, "\(design.id) nearly vanishes in a picker tile")
        }
    }

    // MARK: The overlay

    @Test func anEmptySetDrawsNothing() throws {
        let drawing = try Self.bitmap(Self.overlay(.none), size: Self.picture)
        #expect(drawing.inked() == 0)
    }

    @Test func theSameSetDrawsTheSameTwice() throws {
        let set = NookMirrorDecorationSet(
            frameID: NookMirrorDesigns.frames[0].id,
            stickers: NookMirrorDesigns.stickers.prefix(4).enumerated().map { index, design in
                NookMirrorSticker(
                    designID: design.id,
                    x: 0.2 + Double(index) * 0.2,
                    y: 0.5,
                    width: 0.15,
                    rotation: Double(index) * 20
                )
            }
        )
        let first = try Self.bitmap(Self.overlay(set), size: Self.picture)
        let second = try Self.bitmap(Self.overlay(set), size: Self.picture)

        #expect(first.pixels == second.pixels)
        #expect(first.inked() > 2000)
    }

    @Test func aStickerIsDrawnWhereItWasPut() throws {
        let design = NookMirrorDesigns.stickers[0]
        let placed = NookMirrorSticker(designID: design.id, x: 0.75, y: 0.25, width: 0.2)
        let drawing = try Self.bitmap(Self.overlay(NookMirrorDecorationSet(stickers: [placed])), size: Self.picture)
        let home = NookMirrorDecorationLayout.rect(of: placed, in: Self.picture)
        let farSide = CGRect(x: 0, y: 0, width: Self.picture.width / 2, height: Self.picture.height)

        #expect(drawing.inked(in: home) > 600)
        #expect(drawing.inked(in: farSide) == 0)
    }

    @Test func aStickerFromANewerBuildIsLeftOutOfTheDrawing() throws {
        let unknown = NookMirrorSticker(designID: "sticker.from.a.newer.build", x: 0.5, y: 0.5, width: 0.3)
        let drawing = try Self.bitmap(
            Self.overlay(NookMirrorDecorationSet(frameID: "frame.from.a.newer.build", stickers: [unknown])),
            size: Self.picture
        )
        #expect(drawing.inked() == 0)
    }

    @Test func aBiggerPictureGetsTheSameDrawingScaledUp() throws {
        // The photo booth draws the set at the photo's size, far bigger
        // than the mirror. The share of the picture a sticker covers must
        // not change with the size.
        let placed = NookMirrorSticker(designID: NookMirrorDesigns.stickers[0].id, x: 0.5, y: 0.5, width: 0.3)
        let set = NookMirrorDecorationSet(stickers: [placed])
        let small = try Self.bitmap(Self.overlay(set), size: Self.picture)
        let large = try Self.bitmap(
            Self.overlay(set), size: CGSize(width: Self.picture.width * 2, height: Self.picture.height * 2)
        )

        let smallShare = Double(small.inked()) / Double(small.width * small.height)
        let largeShare = Double(large.inked()) / Double(large.width * large.height)
        #expect(abs(smallShare - largeShare) < 0.01)
    }

    // MARK: Words

    @Test func everyDesignAndPickerStringExistsInEveryLanguageAndHasNoDash() throws {
        var keys = Set(NookMirrorDesigns.frames.map(\.nameKey) + NookMirrorDesigns.stickers.map(\.nameKey))
        keys.formUnion(NookMirrorDecorationPicker.Tab.allCases.map(\.titleKey))
        keys.formUnion([
            "nook.mirror.decorations.button.open", "nook.mirror.decorations.button.close",
            "nook.mirror.decorations.none", "nook.mirror.decorations.clearAll", "nook.mirror.decorations.done",
            "nook.mirror.decorations.count", "nook.mirror.decorations.full",
            "nook.mirror.decorations.hint.stickers", "nook.mirror.decorations.hint.frames",
            "nook.mirror.decorations.sticker.remove", "nook.mirror.decorations.sticker.color",
            "nook.mirror.decorations.sticker.resize", "nook.mirror.decorations.settings.clear",
        ])

        for language in ["en", "zh-Hans", "zh-Hant"] {
            let url = Self.repoRoot
                .appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String], "\(language) did not load")
            for key in keys.sorted() {
                let value = table[key] ?? ""
                #expect(!value.isEmpty, "\(language) is missing \(key)")
                #expect(!value.contains("\u{2014}") && !value.contains("\u{2013}"), "\(language) \(key) has a dash")
            }
        }
    }

    // MARK: Contact sheets

    @Test func contactSheetsAreWrittenWhenAsked() throws {
        guard ProcessInfo.processInfo.environment[Self.snapshotEnvKey] == "1" else { return }
        let directory = Self.repoRoot.appendingPathComponent("output/render/decorations", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lang = LanguageManager.shared

        for design in NookMirrorDesigns.frames {
            let name = design.id.replacingOccurrences(of: ".", with: "-")
            try Self.write(Self.framed(NookMirrorDecorationSet(frameID: design.id)), size: Self.picture, to: directory, name: name)
        }

        let frameCell = CGSize(width: 216, height: 140)
        let frames = Self.sheet(NookMirrorDesigns.frames, columns: 4, cell: frameCell) { design in
            VStack(spacing: 4) {
                Self.framed(NookMirrorDecorationSet(frameID: design.id))
                    .frame(width: 208, height: 117)
                Text(lang.t(design.nameKey)).font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
            }
        }
        try Self.write(frames.view, size: frames.size, to: directory, name: "frames-sheet")

        let stickerCell = CGSize(width: 150, height: 86)
        let stickers = Self.sheet(NookMirrorDesigns.stickers, columns: 6, cell: stickerCell) { design in
            VStack(spacing: 4) {
                HStack(spacing: 2) {
                    ForEach(0..<design.variants, id: \.self) { variant in
                        NookMirrorStickerThumbnail(design: design, variant: variant).frame(width: 46, height: 46)
                    }
                }
                .frame(height: 60)
                Text(lang.t(design.nameKey)).font(.system(size: 10, weight: .medium)).foregroundStyle(.white)
            }
        }
        try Self.write(stickers.view, size: stickers.size, to: directory, name: "stickers-sheet")

        let tiles = Self.sheet(NookMirrorDesigns.stickers, columns: 9, cell: CGSize(width: 46, height: 46)) { design in
            NookMirrorStickerThumbnail(design: design)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
        }
        try Self.write(tiles.view, size: tiles.size, to: directory, name: "stickers-picker-size")

        let example = NookMirrorDecorationSet(
            frameID: "frame.hearts",
            stickers: NookMirrorDesigns.stickers.prefix(8).enumerated().map { index, design in
                NookMirrorSticker(
                    designID: design.id,
                    x: 0.14 + Double(index % 4) * 0.24,
                    y: index < 4 ? 0.3 : 0.72,
                    width: 0.15,
                    rotation: Double(index % 3 - 1) * 14
                )
            }
        )
        try Self.write(Self.framed(example), size: Self.picture, to: directory, name: "mirror-example")

        // The picker as it sits under the mirror on the notch page. A bare
        // model: nothing is started, and nothing is changed.
        let nook = NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
        let pickerSize = CGSize(width: 448, height: NookMirrorDecorationLayout.pickerHeight)
        for tab in NookMirrorDecorationPicker.Tab.allCases {
            let picker = NookMirrorDecorationPicker(nook: nook, startingTab: tab, isScrollable: false)
                .padding(8)
                .background(Color(red: 0.05, green: 0.05, blue: 0.06))
            try Self.write(
                picker,
                size: CGSize(width: pickerSize.width + 16, height: pickerSize.height + 16),
                to: directory,
                name: "picker-\(tab.rawValue)"
            )
        }
    }

    /// A decoration set over a plain gray stand-in for the camera picture.
    private static func framed(_ decorations: NookMirrorDecorationSet) -> some View {
        ZStack {
            Color(white: 0.45)
            NookMirrorDecorationOverlay(decorations: decorations)
        }
    }

    private static func sheet<Item: Identifiable>(
        _ items: [Item],
        columns: Int,
        cell: CGSize,
        @ViewBuilder content: @escaping (Item) -> some View
    ) -> (view: AnyView, size: CGSize) {
        let rows = Int((Double(items.count) / Double(columns)).rounded(.up))
        let padding: CGFloat = 12
        let size = CGSize(
            width: CGFloat(columns) * cell.width + padding * 2,
            height: CGFloat(rows) * cell.height + padding * 2
        )
        let view = VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(items.dropFirst(row * columns).prefix(columns)) { item in
                        content(item).frame(width: cell.width, height: cell.height)
                    }
                }
            }
        }
        .padding(padding)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Color(red: 0.05, green: 0.05, blue: 0.06))
        return (AnyView(view), size)
    }

    private static func write(_ view: some View, size: CGSize, to directory: URL, name: String) throws {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        let image = try #require(renderer.cgImage, "\(name) did not render")
        let png = try #require(
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
            "\(name) could not be made into a PNG"
        )
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    /// `Tests/OpenIslandAppTests/<this file>` sits three levels below the root.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
