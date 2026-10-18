import AppKit
import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

/// The two glow styles side by side on a closed pill, at their resting
/// opacities, for a look. Vivid is the wider blur, which spread the same
/// opacity thinner and read as faint; its resting opacities sit well above
/// subtle's now. Set `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to write the PNGs to
/// `output/render/glow/`.
@MainActor
@Suite struct IslandHaloStylesRenderTests {
    @Test func vividRestsWellAboveSubtle() {
        let subtle = IslandHaloMetrics.subtle
        let vivid = IslandHaloMetrics.vivid
        #expect(vivid.runningOpacity >= 0.8 && vivid.musicOpacity >= 0.8)
        #expect(vivid.runningOpacity - subtle.runningOpacity >= 0.3)
        #expect(vivid.musicOpacity - subtle.musicOpacity >= 0.3)
        #expect(vivid.breathingLow > subtle.breathingLow && vivid.pulseLow > subtle.pulseLow)
        // The flash still rises above the resting glow.
        #expect(vivid.flashPeak > vivid.runningOpacity)
    }

    @Test func theTwoStylesDrawOnAClosedPill() throws {
        for style in [IslandHaloStyle.subtle, .vivid] {
            let metrics = IslandHaloMetrics.metrics(for: style)
            for (name, source, opacity, color) in [
                ("running", IslandHaloSource.running, metrics.runningOpacity, IslandHaloRGB.running),
                ("approval", .approval, metrics.breathingHigh, .approval),
            ] {
                let state = IslandHaloState(
                    source: source, color: color, motion: .steady,
                    restOpacity: opacity, radius: metrics.radius, drop: metrics.drop
                )
                let image = try Self.render(
                    Capsule().fill(Color.black)
                        .frame(width: 220, height: 32)
                        .islandHaloPreview(state, cornerRadius: 16)
                )
                #expect(image.width > 0)
                try Self.write(image, name: "glow-\(style.rawValue)-\(name)")
            }
        }
    }

    private static func render(_ view: some View) throws -> CGImage {
        let renderer = ImageRenderer(
            content: view
                .padding(60)
                .background(V6Palette.ink)
                .environment(\.colorScheme, .dark)
                .environment(\.nookDrawsStill, true)
        )
        renderer.scale = 2
        return try #require(renderer.cgImage, "no picture of the glow")
    }

    private static func write(_ image: CGImage, name: String) throws {
        guard ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_SNAPSHOTS"] == "1" else { return }
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("output/render/glow", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
