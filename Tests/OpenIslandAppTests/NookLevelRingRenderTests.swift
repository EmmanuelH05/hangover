import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Draws the closed pill's level ring, the charger's notice, with
/// `ImageRenderer`. Set `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to also write the
/// PNGs to `output/render/` under the repo root for a visual check.
@MainActor
@Suite struct NookLevelRingRenderTests {
    private static let scale: CGFloat = 4

    @Test func theRingChangesWithItsLevel() throws {
        let low = try renderWing("level-ring-12", percent: 12)
        let high = try renderWing("level-ring-78", percent: 78)
        let full = try renderWing("level-ring-100", percent: 100)

        #expect(low != high)
        #expect(high != full)
    }

    /// An external display's pill is 24pt tall, which leaves an 18pt ring.
    /// Three digits must still fit it at the smallest size the number may
    /// shrink to, or the number is cut to "1…".
    @Test(arguments: [CGFloat(18), 20, 24])
    func aHundredFitsTheRingAtEverySize(size: CGFloat) {
        let smallest = size * NookLevelRingView.fontScale * NookLevelRingView.minimumTextScale
        let largest = size * NookLevelRingView.fontScale
        let room = NookLevelRingView.textWidth(size: size)

        #expect(Self.width(of: "100", fontSize: smallest) <= room)
        // Two digits fit at full size, with no shrinking at all.
        #expect(Self.width(of: "88", fontSize: largest) <= room)
    }

    @Test func theSmallRingOnAnExternalDisplayDrawsAHundred() throws {
        let full = try render("level-ring-100-small", size: CGSize(width: 60, height: 24)) {
            NookTrailingWingView(trailing: .level(percent: 100, tint: .green), height: 18, width: 52)
        }
        let ten = try render("level-ring-10-small", size: CGSize(width: 60, height: 24)) {
            NookTrailingWingView(trailing: .level(percent: 10, tint: .green), height: 18, width: 52)
        }
        let pill = try render("pill-charging-100-external", size: CGSize(width: 240, height: 36)) {
            V6ClosedPill(
                mode: .idle,
                layout: .external,
                height: 24,
                activity: NookClosedActivity(
                    leading: .symbol("bolt.fill", .green),
                    trailing: .level(percent: 100, tint: .green),
                    yieldsToAgents: false
                )
            )
        }

        #expect(full != ten)
        #expect(!pill.isEmpty)
    }

    @Test func thePillShowsTheRingBesideTheNotch() throws {
        let charging = try renderPill(
            "pill-charging-78",
            activity: NookClosedActivity(
                leading: .symbol("bolt.fill", .green),
                trailing: .level(percent: 78, tint: .green),
                yieldsToAgents: false
            )
        )
        let words = try renderPill(
            "pill-charging-words",
            activity: NookClosedActivity(
                leading: .symbol("bolt.fill", .green),
                trailing: .text("Charging · 78%"),
                yieldsToAgents: false
            )
        )

        #expect(charging != words)
    }

    // MARK: Rendering

    /// Width of a string in the ring's type: bold, rounded, at this size.
    private static func width(of text: String, fontSize: CGFloat) -> CGFloat {
        let base = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let rounded = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: fontSize) }
        let font = rounded ?? base
        return NSAttributedString(string: text, attributes: [.font: font]).size().width
    }

    private func renderWing(_ name: String, percent: Int) throws -> Data {
        try render(name, size: CGSize(width: 60, height: 32)) {
            NookTrailingWingView(
                trailing: .level(percent: percent, tint: .green),
                height: 26,
                width: 52
            )
        }
    }

    private func renderPill(_ name: String, activity: NookClosedActivity) throws -> Data {
        try render(name, size: CGSize(width: 420, height: 44)) {
            V6ClosedPill(
                mode: .idle,
                layout: .macbook,
                physicalNotchWidth: 224,
                activity: activity
            )
        }
    }

    private func render<Content: View>(
        _ name: String,
        size: CGSize,
        @ViewBuilder content: () -> Content
    ) throws -> Data {
        let framed = content()
            .frame(width: size.width, height: size.height)
            .background(Color(white: 0.25))
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = Self.scale
        let image = try #require(renderer.cgImage, "no image for \(name)")
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
