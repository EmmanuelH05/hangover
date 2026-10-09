import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Renders the agent tool views with `ImageRenderer`: the shortcut keys
/// under an approval card's buttons and the "what it did" summary as a row
/// line, a folded card and an unfolded one. Set
/// `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to also write the PNGs to
/// `output/render/` under the repo root for a visual check.
@MainActor
struct AgentToolsRenderTests {
    private static let scale: CGFloat = 2
    private static let snapshotEnvKey = "OPEN_ISLAND_RENDER_SNAPSHOTS"

    private static let summary = AgentTurnSummary(
        duration: 252,
        endedAt: Date(timeIntervalSince1970: 1_000),
        fileEdits: .files(["/repo/Sources/App/Model.swift", "/repo/Tests/ModelTests.swift"]),
        commands: ["swift build", "swift test --filter ModelTests", "git status", "git diff --stat"],
        testCommands: ["swift test --filter ModelTests"],
        permissionRequests: 2
    )

    @Test
    func theHintLineNamesEachKeyItIsGiven() throws {
        let size = CGSize(width: 360, height: 28)
        let both = try renderPNG("agent-hotkey-hint-both", size: size) {
            AgentHotkeyHintLine(
                hint: AgentHotkeyHint(approve: "⌃⌥Y", deny: "⌃⌥N"),
                approveTitle: "Allow Once",
                denyTitle: "Deny"
            )
        }
        let denyOnly = try renderPNG("agent-hotkey-hint-deny", size: size) {
            AgentHotkeyHintLine(
                hint: AgentHotkeyHint(approve: nil, deny: "⌃⌥N"),
                approveTitle: "Allow Once",
                denyTitle: "Deny"
            )
        }
        #expect(both != denyOnly, "a missing shortcut should leave its part of the line out")
    }

    @Test
    func theSummaryRendersAsALineAndAsACard() throws {
        // The shared manager as it is: setting a language would write to
        // the defaults every other test reads.
        let lang = LanguageManager.shared

        let row = try renderPNG("agent-summary-row", size: CGSize(width: 420, height: 28)) {
            AgentTurnSummaryView(summary: Self.summary, lang: lang, style: .row)
        }
        let cardSize = CGSize(width: 420, height: 260)
        let folded = try renderPNG("agent-summary-card-folded", size: cardSize) {
            VStack(spacing: 0) {
                AgentTurnSummaryView(summary: Self.summary, lang: lang, style: .card)
                Spacer(minLength: 0)
            }
        }
        let unfolded = try renderPNG("agent-summary-card-unfolded", size: cardSize) {
            VStack(spacing: 0) {
                AgentTurnSummaryView(summary: Self.summary, lang: lang, style: .card, startsUnfolded: true)
                Spacer(minLength: 0)
            }
        }
        #expect(!row.isEmpty)
        #expect(folded != unfolded, "unfolding the card should show the files and the commands")
    }

    private func renderPNG<Content: View>(
        _ name: String,
        size: CGSize,
        @ViewBuilder content: () -> Content
    ) throws -> Data {
        let framed = content()
            .frame(width: size.width, height: size.height)
            .background(V6Palette.ink)
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: framed.environment(\.nookDrawsStill, true))
        renderer.scale = Self.scale
        let rendered = renderer.cgImage
        let image = try #require(rendered, "ImageRenderer returned no image for \(name)")

        let representation = NSBitmapImageRep(cgImage: image)
        let encoded = representation.representation(using: .png, properties: [:])
        let png = try #require(encoded, "PNG encoding failed for \(name)")

        if ProcessInfo.processInfo.environment[Self.snapshotEnvKey] == "1" {
            let directory = Self.repoRoot.appendingPathComponent("output/render", isDirectory: true)
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
