import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Draws the pages this week's features changed, offscreen, the way the other
/// tour pages are drawn: the design kit's step, the glow page with the lights,
/// the permissions page with the sound, the last page with the kit and the
/// lights chosen, and the lights page of the long tour. Set
/// `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to also write one PNG a picture to
/// `output/render/onboarding/` under the repo root.
@MainActor
struct OnboardingExtrasRenderTests {
    private static let scale: CGFloat = 2
    private static let snapshotEnvKey = "OPEN_ISLAND_RENDER_SNAPSHOTS"

    private static func base(length: OnboardingLength = .long) -> OnboardingState {
        var state = OnboardingState(
            closedSide: .count,
            enabledWidgets: Set(NookWidgetKind.defaultEnabled),
            glowThemeID: IslandHaloTheme.standard.id,
            approveKeys: ["control", "option", "Y"],
            denyKeys: ["control", "option", "N"]
        )
        state.length = length
        return state
    }

    private static func kitStep(isOn: Bool, isReady: Bool, picked: Bool = false) -> OnboardingState {
        var state = base()
        state.featureKind = .design
        state.features.design = OnboardingDesignReading(
            isOn: isOn, isReady: isReady, lastPickAt: picked ? Date(timeIntervalSince1970: 2) : nil
        )
        var progress = OnboardingFeatureProgress()
        if isOn { progress.note(OnboardingFeatureReading(design: OnboardingDesignReading(isOn: true, isReady: true))) }
        if picked { progress.note(state.features) }
        state.featureProgress = progress
        return state
    }

    // MARK: The kit's step

    @Test func theKitsStepDrawsOffOnAndAfterAPick() throws {
        let off = try render("08-features-design-off-320") { tourView(.features, Self.kitStep(isOn: false, isReady: false), narrow: 320) }
        let on = try render("08-features-design-on-320") { tourView(.features, Self.kitStep(isOn: true, isReady: true), narrow: 320) }
        let picked = try render("08-features-design-picked-320") {
            tourView(.features, Self.kitStep(isOn: true, isReady: true, picked: true), narrow: 320)
        }
        #expect(Set([off, on, picked]).count == 3, "the three states of the kit's step should each draw")
        // The widest narrow window draws it too.
        _ = try render("08-features-design-on-420") { tourView(.features, Self.kitStep(isOn: true, isReady: true), narrow: 420) }
    }

    // MARK: The glow page with the lights

    @Test func theGlowPageDrawsTheLightsInEachState() throws {
        func state(_ change: (inout OnboardingBeatReading) -> Void) -> OnboardingState {
            var state = Self.base(length: .medium)
            change(&state.beat)
            return state
        }
        let off = try render("15-look-lights-off") { tourView(.look, state { _ in }) }
        let on = try render("15-look-lights-on") { tourView(.look, state { $0.isOn = true }) }
        let lasers = try render("15-look-lights-lasers") { tourView(.look, state { $0.isOn = true; $0.look = .lasers }) }
        let notes = try render("15-look-lights-notes") {
            tourView(.look, state { $0.isOn = true; $0.reduceMotion = true; $0.dimsFlashingLights = true })
        }
        let dim = try render("15-look-lights-dim-flashing") { tourView(.look, state { $0.isOn = true; $0.dimsFlashingLights = true }) }
        let needsGlow = try render("15-look-lights-needs-glow") { tourView(.look, state { $0.canPulse = false; $0.glowIsOff = true }) }
        let oldMac = try render("15-look-lights-old-mac") { tourView(.look, state { $0.isAvailable = false }) }

        #expect(Set([off, on, lasers, notes, dim, needsGlow, oldMac]).count == 7, "each state should draw its own picture")
    }

    // MARK: The permission

    @Test func thePermissionsPageHasTheSoundRowOnlyWithThePulseOn() throws {
        var on = Self.base()
        on.beat.isOn = true
        let without = try render("26-permissions-no-sound") { tourView(.permissions, Self.base()) }
        let with = try render("26-permissions-sound") { tourView(.permissions, on) }
        #expect(without != with)
    }

    /// The most the page lists is six rows: the agents on, the pulse on and
    /// Record's row. Six sit above the buttons the way five do: the strip with
    /// the buttons in it is the same picture, which it would not be if the
    /// rows pushed the page out of the window.
    @Test func sixRowsOfPermissionsKeepTheButtonsWhereFiveHad() throws {
        var six = Self.base()
        six.beat.isOn = true
        #expect(OnboardingGrant.shown(agentsEnabled: true).count == 5)
        #expect(OnboardingGrant.shown(agentsEnabled: true, beatIsOn: true).count == 6)
        #expect(OnboardingPermissionsPage.rowPadding(rowCount: 6) < OnboardingPermissionsPage.rowPadding(rowCount: 5))

        let five = try image { tourView(.permissions, Self.base()) }
        let tall = try image { tourView(.permissions, six) }
        #expect(five.width == tall.width && five.height == tall.height)

        let strip = Int(Self.scale * 50)
        let rect = CGRect(x: 0, y: five.height - strip, width: five.width, height: strip)
        let fiveButtons = try #require(five.cropping(to: rect))
        let sixButtons = try #require(tall.cropping(to: rect))
        let fivePNG = try #require(NSBitmapImageRep(cgImage: fiveButtons).representation(using: .png, properties: [:]))
        let sixPNG = try #require(NSBitmapImageRep(cgImage: sixButtons).representation(using: .png, properties: [:]))
        #expect(fivePNG == sixPNG, "six rows pushed the buttons out of place")
    }

    // MARK: The summary

    @Test func theLastPageDrawsTheKitAndTheLightsWhenChosen() throws {
        var chosen = Self.base(length: .medium)
        chosen.enabledWidgets = Set(NookWidgetKind.allCases.filter { $0 != .linkAudio })
        chosen.nookPlacements = chosen.enabledWidgets.sorted { $0.rawValue < $1.rawValue }
            .map { NookWidgetPlacement(kind: $0, size: .medium) }
        chosen.features.design = OnboardingDesignReading(isOn: true, isReady: true)
        chosen.beat.isOn = true
        chosen.beat.look = .lasers
        let rows = OnboardingRecapRow.shown(
            agentsEnabled: true, hasDesignKit: true, hasLights: true
        )
        #expect(rows.count == 15)

        let plain = try render("30-done-plain") { tourView(.done, Self.base(length: .medium)) }
        let both = try render("30-done-kit-and-lights") { tourView(.done, chosen) }
        #expect(plain != both)
    }

    // MARK: The lights page of the long tour

    @Test func theLightsPageOfTheLongTourDrawsItsPicture() throws {
        let page = try render("16-lights-long") { tourView(.lights, Self.base()) }
        let power = try render(nil) { tourView(.power, Self.base()) }
        #expect(page != power)
        let size = try image { tourView(.lights, Self.base()) }
        #expect(size.width == Int(OnboardingStyle.windowSize.width * Self.scale))
        #expect(size.height == Int(OnboardingStyle.windowSize.height * Self.scale))
    }

    // MARK: Rendering

    private func tourView(_ page: OnboardingPage, _ state: OnboardingState, narrow: CGFloat? = nil) -> some View {
        let size = narrow.map { CGSize(width: $0, height: OnboardingWindowFrame.narrowMaxHeight) }
            ?? OnboardingTestSize.of(page)
        return OnboardingView(
            tour: OnboardingTour(startingAt: page, state: { state }),
            lang: LanguageManager.shared
        )
        .frame(width: size.width, height: size.height)
    }

    private func image<Content: View>(@ViewBuilder _ content: () -> Content) throws -> CGImage {
        let renderer = ImageRenderer(content: content().environment(\.nookDrawsStill, true))
        renderer.scale = Self.scale
        return try #require(renderer.cgImage, "ImageRenderer returned no image")
    }

    private func render<Content: View>(_ name: String?, @ViewBuilder _ content: () -> Content) throws -> Data {
        let representation = NSBitmapImageRep(cgImage: try image(content))
        let png = try #require(representation.representation(using: .png, properties: [:]), "PNG encoding failed")
        if let name, ProcessInfo.processInfo.environment[Self.snapshotEnvKey] == "1" {
            let directory = HangoverBrandTests.repoRoot.appendingPathComponent("output/render/onboarding", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return png
    }
}
