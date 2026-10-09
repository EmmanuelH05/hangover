import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// The ring light's tints and the pure SwiftUI parts of the glow color
/// settings, drawn with `ImageRenderer`. Nothing here shows the real light
/// or opens a color panel. Set `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to also
/// write the PNGs to `output/render/` under the repo root.
struct GlowColorsRenderTests {
    private static let scale: CGFloat = 2

    // MARK: Ring light tints

    @Test func warmWhiteIsTheLightTheRingAlwaysHad() {
        let warm = NookRingLightTint.warmWhite.components
        let red: Double = 1.0
        let green: Double = 0.965
        let blue: Double = 0.9

        #expect(warm.red == red)
        #expect(warm.green == green)
        #expect(warm.blue == blue)
        #expect(NookRingLightLayout.color == NookRingLightTint.warmWhite.color)
        #expect(NookRingLightTint.allCases.first == .warmWhite)
    }

    @Test func theSavedTintFallsBackToWarmWhite() {
        #expect(NookRingLightTint.resolve(nil) == .warmWhite)
        #expect(NookRingLightTint.resolve("") == .warmWhite)
        #expect(NookRingLightTint.resolve("ultraviolet") == .warmWhite)
        #expect(NookRingLightTint.resolve("rose") == .rose)
        for tint in NookRingLightTint.allCases {
            #expect(NookRingLightTint.resolve(tint.rawValue) == tint)
        }
    }

    @Test func everyTintIsItsOwnLightAndStaysCloseToWhite() {
        let tints = NookRingLightTint.allCases
        let hexes = tints.map { tint -> String in
            let parts = tint.components
            return IslandHaloRGB(red: parts.red, green: parts.green, blue: parts.blue).hex
        }
        let floor: Double = 0.65
        let brightest: Double = 1.0

        #expect(Set(hexes).count == tints.count, "two tints are the same light")
        for tint in tints {
            let parts = tint.components
            // A light is there to show a face. A strong color would paint it.
            #expect(min(parts.red, parts.green, parts.blue) >= floor, "\(tint) is too strong a color")
            #expect(max(parts.red, parts.green, parts.blue) == brightest, "\(tint) is dimmer than it could be")
        }
    }

    @Test @MainActor func theRingLightDrawsInItsTint() throws {
        let size = CGSize(width: 400, height: 260)
        let thickness = NookRingLightLayout.thickness(for: size)
        let warm = try render("ring-light-warm", size: size, background: .black) {
            NookRingLightView(thickness: thickness)
        }
        let sky = try render("ring-light-sky", size: size, background: .black) {
            NookRingLightView(thickness: thickness, tint: .sky)
        }
        let warmEdge = try #require(NSBitmapImageRep(data: warm)?.colorAt(x: 12, y: 12))
        let skyEdge = try #require(NSBitmapImageRep(data: sky)?.colorAt(x: 12, y: 12))

        // Warm white leans red, sky leans blue.
        #expect(warmEdge.redComponent > warmEdge.blueComponent)
        #expect(skyEdge.blueComponent > skyEdge.redComponent)
    }

    // MARK: Theme cards

    @Test @MainActor func aThemesDotsShowItsColors() throws {
        let size = CGSize(width: 120, height: 40)
        let signal = try render("glow-swatches-signal", size: size) {
            GlowThemeSwatches(colors: IslandHaloTheme.signal.swatches)
        }
        let lagoon = try render("glow-swatches-lagoon", size: size) {
            GlowThemeSwatches(colors: IslandHaloTheme.lagoon.swatches)
        }
        let standard = try render("glow-swatches-default", size: size) {
            GlowThemeSwatches(colors: IslandHaloTheme.standard.swatches)
        }

        #expect(signal != lagoon)
        #expect(signal != standard)
    }

    @Test @MainActor func theThemeGridMovesItsRingWithTheSelection() throws {
        let size = CGSize(width: 640, height: 380)
        let none = try render("glow-themes-none", size: size) { grid(selected: nil) }
        let standard = try render("glow-themes-default", size: size) { grid(selected: "default") }
        let aurora = try render("glow-themes-aurora", size: size) { grid(selected: "aurora") }

        #expect(none != standard, "the default theme should show as picked")
        #expect(standard != aurora, "picking another theme should move the ring")
    }

    @MainActor
    private func grid(selected: String?) -> some View {
        GlowThemeGrid(selectedID: selected, title: { $0.id }, pick: { _ in })
            .padding(12)
    }

    // MARK: Rendering

    @MainActor
    private func render<Content: View>(
        _ name: String,
        size: CGSize,
        background: Color = V6Palette.ink,
        @ViewBuilder content: () -> Content
    ) throws -> Data {
        let framed = content()
            .frame(width: size.width, height: size.height)
            .background(background)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: framed.environment(\.nookDrawsStill, true))
        renderer.scale = Self.scale
        let image = try #require(renderer.cgImage, "no image for \(name)")
        let expectedWidth = Int(size.width * Self.scale)
        #expect(image.width == expectedWidth, "\(name) pixel width")
        let png = try #require(
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
            "PNG encoding failed for \(name)"
        )
        if ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_SNAPSHOTS"] == "1" {
            let directory = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("output/render", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return png
    }
}
