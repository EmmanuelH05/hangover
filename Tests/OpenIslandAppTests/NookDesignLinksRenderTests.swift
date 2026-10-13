import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Draws the Links tab with `ImageRenderer` on a kit of its own, still, like
/// the other design kit pictures. Set `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to
/// also write the PNGs to `output/render/design/` for a visual check.
@MainActor
struct NookDesignLinksRenderTests {
    private static let scale: CGFloat = 2
    private static let snapshotEnvKey = "OPEN_ISLAND_RENDER_SNAPSHOTS"

    private static let links: [(String, String, Bool)] = [
        ("https://www.figma.com/design/KEY1/Brand-Kit?node-id=12-34&t=abc", "Brand kit", true),
        ("https://www.figma.com/board/KEY2/Workshop-Notes", "Workshop notes", false),
        ("https://www.figma.com/proto/KEY3/Checkout-Flow?node-id=3-4", "Checkout flow", false),
        ("https://www.figma.com/slides/KEY4/Pitch", "Pitch deck", true),
        ("https://developer.apple.com/design/human-interface-guidelines/", "", false),
        ("http://localhost:3000/app", "Local build", false),
        ("https://example.com/a-very-long-path/that-goes-on/and-on/until-it-is-cut", "", false),
    ]

    private func fill(_ fixture: NookDesignFixture) throws {
        let kit = fixture.kit
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        kit.now = { clock }
        for (url, name, favorite) in Self.links {
            clock.addTimeInterval(60)
            guard case let .added(link) = kit.addLink(text: url) else { throw CancellationError() }
            if !name.isEmpty { kit.links.renameLink(link.id, to: name) }
            if favorite { kit.toggleLinkFavorite(link.id) }
        }
        let first = try #require(kit.links.links.last)
        let second = try #require(kit.links.links.first)
        kit.moveLink(first.id, toCollectionNamed: "Client work")
        kit.moveLink(second.id, toCollectionNamed: "Home")
        kit.moveLink(kit.links.links[2].id, toCollectionNamed: "Client work")
        kit.tab = .links
    }

    @Test(arguments: NookWidgetSize.allCases)
    func theLinksTabShowsLinksOnceThereAreSome(size: NookWidgetSize) async throws {
        let fixture = try await NookDesignFixture("render-links")
        defer { fixture.cleanUp() }
        fixture.kit.tab = .links
        let empty = try card("links-\(size.rawValue)-empty", fixture.kit, size)
        try fill(fixture)
        let filled = try card("links-\(size.rawValue)", fixture.kit, size)
        #expect(empty != filled)
    }

    @Test func eachSizeDrawsItsOwnPicture() async throws {
        let fixture = try await NookDesignFixture("render-links")
        defer { fixture.cleanUp() }
        try fill(fixture)
        let pictures = try NookWidgetSize.allCases.map { try card("links-sizes-\($0.rawValue)", fixture.kit, $0) }
        #expect(Set(pictures).count == 3)
    }

    @Test(arguments: [NookWidgetSize.medium, .large])
    func aLitCollectionNarrowsTheList(size: NookWidgetSize) async throws {
        let fixture = try await NookDesignFixture("render-links")
        defer { fixture.cleanUp() }
        try fill(fixture)
        let all = try card("links-\(size.rawValue)", fixture.kit, size)
        fixture.kit.selectLinkCollection(fixture.kit.links.collections.first?.id)
        let narrowed = try card("links-\(size.rawValue)-collection", fixture.kit, size)
        #expect(all != narrowed)
    }

    @Test(arguments: NookWidgetSize.allCases)
    func aCopiedLinkShowsATickAndALine(size: NookWidgetSize) async throws {
        let fixture = try await NookDesignFixture("render-links")
        defer { fixture.cleanUp() }
        try fill(fixture)
        let before = try card("links-\(size.rawValue)", fixture.kit, size)
        let top = try #require(fixture.kit.links.library.orderedLinks(in: nil).first)
        fixture.kit.copyLink(top.id)
        let copied = try card("links-\(size.rawValue)-copied", fixture.kit, size)
        #expect(before != copied)
    }

    @Test(arguments: NookWidgetSize.allCases)
    func aNameBeingAskedForTakesTheFieldsPlace(size: NookWidgetSize) async throws {
        let fixture = try await NookDesignFixture("render-links")
        defer { fixture.cleanUp() }
        try fill(fixture)
        let before = try card("links-\(size.rawValue)", fixture.kit, size)
        let top = try #require(fixture.kit.links.library.orderedLinks(in: nil).first)
        fixture.kit.beginNaming(.renamingLink(top.id))
        let naming = try card("links-\(size.rawValue)-naming", fixture.kit, size)
        #expect(before != naming)
    }

    @Test(arguments: NookWidgetSize.allCases)
    func aRefusalOrADuplicateShowsItsLine(size: NookWidgetSize) async throws {
        let fixture = try await NookDesignFixture("render-links")
        defer { fixture.cleanUp() }
        try fill(fixture)
        let before = try card("links-\(size.rawValue)", fixture.kit, size)
        fixture.kit.addLink(text: "javascript:alert(1)")
        let refused = try card("links-\(size.rawValue)-refused", fixture.kit, size)
        #expect(before != refused)
    }

    @Test func aHundredLinksDrawWithoutGrowingTheCard() async throws {
        let fixture = try await NookDesignFixture("render-links")
        defer { fixture.cleanUp() }
        fixture.kit.tab = .links
        for index in 0..<100 { fixture.kit.addLink(text: "https://example.com/page-\(index)") }
        for size in NookWidgetSize.allCases {
            _ = try card("links-\(size.rawValue)-many", fixture.kit, size)
        }
    }

    @Test func theFigmaLabelNamesTheKindInPlainWords() throws {
        let kinds: [NookDesignFigmaKind?] = [nil] + NookDesignFigmaKind.allCases
        let pictures = try kinds.map { kind in
            try render("figma-label-\(kind?.rawValue ?? "plain")", NookDesignFigmaLabel(kind: kind).padding(8).background(V6Palette.ink))
        }
        #expect(Set(pictures).count == kinds.count)
        let compact = try render("figma-label-compact", NookDesignFigmaLabel(kind: .design, isCompact: true).padding(8).background(V6Palette.ink))
        // With no room it says "Figma" alone, which is how a link of no known kind reads.
        #expect(compact == pictures[0])
    }

    @Test func theTabsAreDrawnInTheOrderColorsLinksReferences() async throws {
        let fixture = try await NookDesignFixture("render-links")
        defer { fixture.cleanUp() }
        try fill(fixture)
        var pictures: [Data] = []
        for tab in NookDesignTab.allCases {
            fixture.kit.tab = tab
            pictures.append(try card("tabs-\(tab.rawValue)", fixture.kit, .large))
        }
        #expect(Set(pictures).count == 3)
        #expect(NookDesignTab.allCases.map(\.rawValue) == ["colors", "links", "references"])
    }

    // MARK: Rendering

    private func card(_ name: String, _ kit: NookDesignKit, _ size: NookWidgetSize) throws -> Data {
        let width: CGFloat = size == .small ? 204 : 416
        let framed = NookDesignCard(kit: kit, isStill: true)
            .environment(\.nookWidgetSize, size)
            .frame(width: width, height: NookDesignCard.height(for: size))
            .padding(8)
            .background(V6Palette.ink)
            .environment(\.colorScheme, .dark)
        return try render(name, framed)
    }

    private func render(_ name: String, _ view: some View) throws -> Data {
        let renderer = ImageRenderer(content: view)
        renderer.scale = Self.scale
        let image = try #require(renderer.cgImage, "ImageRenderer returned no image for \(name)")
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]), "PNG encoding failed for \(name)")
        if ProcessInfo.processInfo.environment[Self.snapshotEnvKey] == "1" {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let directory = root.appendingPathComponent("output/render/design", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return png
    }
}
