import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Draws every page of the welcome tour offscreen with `ImageRenderer`. The
/// pages are plain SwiftUI, which is what lets this work: an AppKit-backed
/// control would come out as a placeholder. Set
/// `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to also write one PNG a page to
/// `output/render/onboarding/` under the repo root.
///
/// Nothing here opens a window, and the tours are fed a fixed state with
/// actions that do nothing.
@MainActor
struct OnboardingRenderTests {
    private static let scale: CGFloat = 2
    private static let snapshotEnvKey = "OPEN_ISLAND_RENDER_SNAPSHOTS"

    /// A setup part of the way through: one agent connected, one busy, one
    /// that cannot be connected yet, and a template on.
    private static var sampleState: OnboardingState {
        OnboardingState(
            openTrigger: .hover,
            isIslandOpen: false,
            agents: [
                .claudeCode: OnboardingAgentStatus(isConnected: true),
                .codex: OnboardingAgentStatus(isBusy: true),
                .cursor: OnboardingAgentStatus(canConnect: false),
            ],
            enabledWidgets: Set(NookWidgetKind.defaultEnabled),
            appliedTemplate: .planner,
            glowStyle: .subtle,
            glowThemeID: IslandHaloTheme.standard.id,
            approveKeys: ["control", "option", "Y"],
            denyKeys: ["control", "option", "N"]
        )
    }

    @Test func everyPageDrawsSomethingOfItsOwn() throws {
        let blank = try render(nil) {
            V6Palette.ink.frame(width: OnboardingStyle.windowSize.width, height: OnboardingStyle.windowSize.height)
        }
        let pages = try OnboardingPage.allCases.map { page in
            try render(page.snapshotName) { tourView(page, Self.sampleState) }
        }

        for (page, png) in zip(OnboardingPage.allCases, pages) {
            #expect(png != blank, "\(page) came out blank")
        }
        #expect(Set(pages).count == OnboardingPage.allCases.count, "every page should draw its own picture")
    }

    @Test func everyPageIsTheSizeOfTheWindow() throws {
        let expectedWidth = Int(OnboardingStyle.windowSize.width * Self.scale)
        let expectedHeight = Int(OnboardingStyle.windowSize.height * Self.scale)
        for page in OnboardingPage.allCases {
            let image = try image { tourView(page, Self.sampleState) }
            #expect(image.width == expectedWidth, "\(page) is \(image.width) wide")
            #expect(image.height == expectedHeight, "\(page) is \(image.height) tall")
        }
    }

    @Test func aChoiceShowsOnItsPage() throws {
        var click = Self.sampleState
        click.openTrigger = .click
        #expect(try render(nil) { tourView(.opening, Self.sampleState) } != render(nil) { tourView(.opening, click) })

        var opened = Self.sampleState
        opened.isIslandOpen = true
        #expect(
            try render("2-opening-tried") { tourView(.opening, opened) }
                != render(nil) { tourView(.opening, Self.sampleState) },
            "opening the real island should change the line under the choices"
        )

        var vivid = Self.sampleState
        vivid.glowStyle = .vivid
        #expect(try render(nil) { tourView(.look, Self.sampleState) } != render(nil) { tourView(.look, vivid) })

        var focus = Self.sampleState
        focus.appliedTemplate = .focus
        #expect(try render(nil) { tourView(.nook, Self.sampleState) } != render(nil) { tourView(.nook, focus) })

        var withMirror = Self.sampleState
        withMirror.enabledWidgets.insert(.mirror)
        #expect(try render(nil) { tourView(.nook, Self.sampleState) } != render(nil) { tourView(.nook, withMirror) })
    }

    @Test func theAgentsPageShowsEachAgentsStanding() throws {
        var none = Self.sampleState
        none.agents = [:]
        #expect(try render("3-agents-none") { tourView(.agents, none) } != render(nil) { tourView(.agents, Self.sampleState) })

        var noKeys = Self.sampleState
        noKeys.approveKeys = nil
        noKeys.denyKeys = nil
        #expect(
            try render("3-agents-shortcuts-off") { tourView(.agents, noKeys) }
                != render(nil) { tourView(.agents, Self.sampleState) }
        )
    }

    @Test func theLastPageSaysBackWhatWasChosen() throws {
        var other = Self.sampleState
        other.openTrigger = .click
        other.agents = [:]
        other.hasAgentOutsideTour = true
        other.appliedTemplate = nil
        other.glowStyle = .off
        other.denyKeys = nil
        #expect(try render("8-done-other") { tourView(.done, other) } != render(nil) { tourView(.done, Self.sampleState) })
    }

    @Test func aConnectThatFailedShowsOnItsRowAndUnderTheList() throws {
        var failed = Self.sampleState
        failed.agents[.gemini] = OnboardingAgentStatus(didFail: true)
        #expect(
            try render("3-agents-failed") { tourView(.agents, failed) }
                != render(nil) { tourView(.agents, Self.sampleState) }
        )
    }

    @Test func theTryItLineStaysAnsweredOnceTheIslandWasOpened() throws {
        var opened = Self.sampleState
        opened.hasOpenedIsland = true
        var open = Self.sampleState
        open.isIslandOpen = true
        let waiting = try render(nil) { tourView(.opening, Self.sampleState) }

        // Closed again after having been opened draws what open draws.
        #expect(try render(nil) { tourView(.opening, opened) } != waiting)
        #expect(try render(nil) { tourView(.opening, opened) } == render(nil) { tourView(.opening, open) })
    }

    @Test func theOpenedPageShowsTheChosenWidthAndCorners() throws {
        var wide = Self.sampleState
        wide.openedLook = IslandOpenedLook(width: .widest, corners: .square)
        var topBar = Self.sampleState
        topBar.displayProfile = .topBar
        let standard = try render(nil) { tourView(.opened, Self.sampleState) }

        #expect(try render("5-opened-widest-square") { tourView(.opened, wide) } != standard)
        #expect(try render("5-opened-top-bar") { tourView(.opened, topBar) } != standard)
    }

    @Test func theGlowPageShowsTheChosenTheme() throws {
        var themed = Self.sampleState
        themed.glowThemeID = IslandHaloTheme.lagoon.id
        var own = Self.sampleState
        own.glowThemeID = nil
        let standard = try render(nil) { tourView(.look, Self.sampleState) }

        #expect(try render("6-look-lagoon") { tourView(.look, themed) } != standard)
        #expect(try render(nil) { tourView(.look, own) } != standard)
    }

    /// The recap names the template picked in the tour even after another
    /// choice made the setup the user's own.
    @Test func theRecapNamesTheTemplateThatWasPicked() throws {
        var own = Self.sampleState
        own.appliedTemplate = nil
        var picked = own
        picked.pickedTemplate = .planner

        #expect(try render(nil) { tourView(.done, picked) } != render(nil) { tourView(.done, own) })
        #expect(try render(nil) { tourView(.done, picked) } == render(nil) { tourView(.done, Self.sampleState) })
    }

    // MARK: - Rendering

    private func tourView(_ page: OnboardingPage, _ state: OnboardingState) -> some View {
        OnboardingView(
            tour: OnboardingTour(startingAt: page, state: { state }),
            lang: LanguageManager.shared
        )
    }

    private func image<Content: View>(@ViewBuilder _ content: () -> Content) throws -> CGImage {
        let renderer = ImageRenderer(content: content().environment(\.nookDrawsStill, true))
        renderer.scale = Self.scale
        let rendered = renderer.cgImage
        return try #require(rendered, "ImageRenderer returned no image")
    }

    private func render<Content: View>(_ name: String?, @ViewBuilder _ content: () -> Content) throws -> Data {
        let representation = NSBitmapImageRep(cgImage: try image(content))
        let encoded = representation.representation(using: .png, properties: [:])
        let png = try #require(encoded, "PNG encoding failed for \(name ?? "a picture")")

        if let name, ProcessInfo.processInfo.environment[Self.snapshotEnvKey] == "1" {
            let directory = Self.repoRoot.appendingPathComponent("output/render/onboarding", isDirectory: true)
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
