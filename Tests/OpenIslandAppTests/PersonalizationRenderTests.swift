import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Renders each Personalization component in its rest and selected states
/// with `ImageRenderer`. Set `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to also write
/// the PNGs to `output/render/` under the repo root for a visual check.
@MainActor
struct PersonalizationRenderTests {
    private static let scale: CGFloat = 2
    private static let snapshotEnvKey = "OPEN_ISLAND_RENDER_SNAPSHOTS"

    // MARK: Card

    @Test
    func tileCardRendersRestAndSelected() throws {
        let size = CGSize(width: 160, height: 120)
        let rest = try renderPNG("tile-rest", size: size, padding: 0) { tileCard(selected: false) }
        let selected = try renderPNG("tile-selected", size: size, padding: 0) { tileCard(selected: true) }
        #expect(rest != selected, "the selected tile should differ from the rest tile (fill and ring)")
    }

    @Test
    func rowCardRendersRestAndSelected() throws {
        let size = CGSize(width: 340, height: 84)
        let rest = try renderPNG("row-rest", size: size, padding: 0) { rowCard(selected: false) }
        let selected = try renderPNG("row-selected", size: size, padding: 0) { rowCard(selected: true) }
        #expect(rest != selected, "the selected row should differ from the rest row (fill, ring and checkmark)")
    }

    @Test
    func cardsSharingARingNamespaceRender() throws {
        let size = CGSize(width: 520, height: 120)
        let first = try renderPNG("ring-group-first", size: size, padding: 0) {
            RingGroupHarness(selectedIndex: 0)
        }
        let second = try renderPNG("ring-group-second", size: size, padding: 0) {
            RingGroupHarness(selectedIndex: 1)
        }
        #expect(first != second, "moving the selection should move the ring")
    }

    // MARK: Chip

    @Test
    func monoChipRendersRestAndSelected() throws {
        let size = CGSize(width: 120, height: 36)
        let rest = try renderPNG("chip-rest", size: size, padding: 0) {
            MonoChip(title: "15 min", selected: false) {}
        }
        let selected = try renderPNG("chip-selected", size: size, padding: 0) {
            MonoChip(title: "15 min", selected: true) {}
        }
        #expect(rest != selected, "the selected chip should differ from the rest chip")
    }

    // MARK: Header and toggle

    @Test
    func sectionHeaderRendersWithAndWithoutNote() throws {
        let size = CGSize(width: 360, height: 56)
        let withNote = try renderPNG("header-note", size: size, padding: 0) {
            PersonalizationSectionHeader(title: "05 · Status glow", note: "One soft color at a time.")
        }
        let withoutNote = try renderPNG("header-no-note", size: size, padding: 0) {
            PersonalizationSectionHeader(title: "05 · Status glow", note: nil)
        }
        #expect(withNote != withoutNote, "the note line should change the render")
    }

    @Test
    func toggleRowRendersOnOffAndDisabled() throws {
        let size = CGSize(width: 380, height: 64)
        _ = try renderPNG("toggle-off", size: size, padding: 0) {
            PersonalizationToggleRow(title: "Show usage", note: "Adds a compact usage readout.", isOn: .constant(false))
        }
        _ = try renderPNG("toggle-on", size: size, padding: 0) {
            PersonalizationToggleRow(title: "Show usage", note: "Adds a compact usage readout.", isOn: .constant(true))
        }
        let enabled = try renderPNG("toggle-enabled", size: size, padding: 0) {
            PersonalizationToggleRow(title: "Show usage", note: "Adds a compact usage readout.", isOn: .constant(true))
        }
        let disabled = try renderPNG("toggle-disabled", size: size, padding: 0) {
            PersonalizationToggleRow(
                title: "Show usage",
                note: "Adds a compact usage readout.",
                isOn: .constant(true),
                isEnabled: false
            )
        }
        #expect(enabled != disabled, "a disabled row should render dimmed")
    }

    // MARK: Templates

    @Test
    func templateThumbnailsRenderDistinctly() throws {
        let renders = try PersonalizationTemplate.all.map { template in
            try renderPNG("template-thumbnail-\(template.id.rawValue)", size: TemplateThumbnail.size, padding: 0) {
                TemplateThumbnail(template: template)
            }
        }
        #expect(Set(renders).count == renders.count, "every template should draw its own thumbnail")
    }

    @Test
    func templateGalleryShowsTheRingTheBadgeTheUndoLinkAndTheNote() throws {
        let size = CGSize(width: 520, height: 800)
        let rest = try renderPNG("template-gallery-rest", size: size, padding: 16) {
            TemplateGalleryHarness(applied: nil)
        }
        let applied = try renderPNG("template-gallery-applied", size: size, padding: 16) {
            TemplateGalleryHarness(applied: .planner)
        }
        let withUndo = try renderPNG("template-gallery-undo", size: size, padding: 16) {
            TemplateGalleryHarness(applied: .planner, canUndo: true)
        }
        let withNote = try renderPNG("template-gallery-switched-off", size: size, padding: 16) {
            TemplateGalleryHarness(applied: .planner, switchedOff: [.calendar])
        }
        #expect(rest != applied, "the applied template should show its ring and badge")
        #expect(applied != withUndo, "the undo link should show only while an earlier setup is held")
        #expect(applied != withNote, "a switched-off widget should be named on the applied card")
    }

    @Test
    func collapsedTemplateGalleryKeepsOnlyItsHeader() throws {
        let open = try fittedHeight { TemplateGalleryHarness(applied: .planner, canUndo: true) }
        let collapsed = try fittedHeight { TemplateGalleryHarness(applied: .planner, canUndo: true, isCollapsed: true) }

        // Five cards are several hundred points; the header alone is a few lines.
        #expect(open > 500, "the open gallery should hold its five cards")
        #expect(collapsed < 80, "folding the gallery should take the cards and the undo link away")
    }

    // MARK: Fixtures

    private struct TemplateGalleryHarness: View {
        let applied: PersonalizationTemplate.ID?
        var switchedOff: [NookWidgetKind] = []
        var canUndo = false
        var isCollapsed = false
        @Namespace private var ring

        var body: some View {
            TemplateGallery(
                lang: .shared,
                applied: applied,
                switchedOff: switchedOff,
                canUndo: canUndo,
                isCollapsed: .constant(isCollapsed),
                ringNamespace: ring,
                apply: { _ in },
                undo: {}
            )
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    /// The height `content` takes at the gallery's width when nothing limits it.
    private func fittedHeight<Content: View>(@ViewBuilder _ content: () -> Content) throws -> CGFloat {
        let renderer = ImageRenderer(
            content: content()
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 488)
                .environment(\.colorScheme, .dark)
        )
        renderer.scale = Self.scale
        let image = try #require(renderer.cgImage, "ImageRenderer returned no image")
        return CGFloat(image.height) / Self.scale
    }

    private func tileCard(selected: Bool) -> some View {
        PersonalizationCard(title: "Agents", selected: selected, action: {}) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(V6Palette.paper.opacity(0.9))
        }
        .padding(8)
    }

    private func rowCard(selected: Bool) -> some View {
        PersonalizationCard(
            title: "MacBook",
            selected: selected,
            style: .row(note: "Shapes the island around the notch."),
            action: {}
        ) {
            Image(systemName: "laptopcomputer")
        }
        .padding(8)
    }

    private struct RingGroupHarness: View {
        let selectedIndex: Int
        @Namespace private var ring

        var body: some View {
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { index in
                    PersonalizationCard(
                        title: "Option \(index + 1)",
                        selected: index == selectedIndex,
                        ringNamespace: ring,
                        ringGroup: "options",
                        action: {}
                    ) {
                        Text("\(index + 1)")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(V6Palette.paper.opacity(0.9))
                    }
                }
            }
            .padding(8)
        }
    }

    // MARK: Rendering

    /// Renders `content` on the dark island background inside a fixed frame,
    /// checks the pixel size, optionally writes the PNG, and returns the PNG
    /// bytes so callers can compare states.
    private func renderPNG<Content: View>(
        _ name: String,
        size: CGSize,
        padding: CGFloat,
        @ViewBuilder content: () -> Content
    ) throws -> Data {
        let framed = content()
            .padding(padding)
            .frame(width: size.width, height: size.height)
            .background(V6Palette.ink)
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: framed)
        renderer.scale = Self.scale
        let rendered = renderer.cgImage
        let image = try #require(rendered, "ImageRenderer returned no image for \(name)")

        #expect(image.width == Int(size.width * Self.scale), "\(name) pixel width")
        #expect(image.height == Int(size.height * Self.scale), "\(name) pixel height")

        let representation = NSBitmapImageRep(cgImage: image)
        let encoded = representation.representation(using: .png, properties: [:])
        let png = try #require(encoded, "PNG encoding failed for \(name)")

        if ProcessInfo.processInfo.environment[Self.snapshotEnvKey] == "1" {
            try writeSnapshot(png, name: name)
        }
        return png
    }

    private func writeSnapshot(_ png: Data, name: String) throws {
        let directory = Self.repoRoot.appendingPathComponent("output/render", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
