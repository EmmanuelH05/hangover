import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Draws the Personalization tab offscreen with the agents switch on and
/// off (D41). Set `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to also write the PNGs to
/// `output/render/agents-switch/` under the repo root.
///
/// Nothing here opens a window. The models keep the switch in a
/// `MemoryDefaults`, and nothing is written to any settings.
@MainActor
struct AgentsSwitchRenderTests {
    private static let scale: CGFloat = 1
    private static let width: CGFloat = 700
    private static let snapshotEnvKey = "OPEN_ISLAND_RENDER_SNAPSHOTS"

    private static func model(agentsEnabled: Bool) -> AppModel {
        let defaults = MemoryDefaults()
        defaults.set(agentsEnabled, forKey: AgentsSwitch.defaultsKey)
        return AppModel(agentsDefaults: defaults, defaults: MemoryDefaults())
    }

    @Test
    func personalizationLeavesTheAgentChoicesOutWhileOff() throws {
        let withAgents = try image("personalization-agents-on") {
            AppearanceSettingsPane(model: Self.model(agentsEnabled: true)).contentColumn
        }
        let nookOnly = try image("personalization-agents-off") {
            AppearanceSettingsPane(model: Self.model(agentsEnabled: false)).contentColumn
        }

        #expect(withAgents.width == nookOnly.width)
        // Whole sections go: the center label, the session list and its
        // four rows of choices, and the rows that link the two pages.
        #expect(nookOnly.height < withAgents.height - 400, "\(nookOnly.height) against \(withAgents.height)")
    }

    private func image<Content: View>(_ name: String, @ViewBuilder _ content: () -> Content) throws -> CGImage {
        let view = content()
            .frame(width: Self.width)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
            .environment(\.nookDrawsStill, true)
        let renderer = ImageRenderer(content: view)
        renderer.scale = Self.scale
        let image = try #require(renderer.cgImage, "ImageRenderer returned no image for \(name)")

        if ProcessInfo.processInfo.environment[Self.snapshotEnvKey] == "1" {
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            let directory = Self.repoRoot.appendingPathComponent("output/render/agents-switch", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try #require(png, "PNG encoding failed for \(name)")
                .write(to: directory.appendingPathComponent("\(name).png"))
        }
        return image
    }

    /// `Tests/OpenIslandAppTests/<this file>` sits three levels below the root.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
