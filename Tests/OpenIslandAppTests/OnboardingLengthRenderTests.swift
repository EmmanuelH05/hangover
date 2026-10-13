import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Draws the question page, the last pages of the shorter tours and pages of
/// the long tour offscreen, the way the other tour pages are drawn. Set
/// `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to also write one PNG a picture to
/// `output/render/onboarding/` under the repo root.
@MainActor
struct OnboardingLengthRenderTests {
    private static let scale: CGFloat = 2
    private static let snapshotEnvKey = "OPEN_ISLAND_RENDER_SNAPSHOTS"

    private static func state(length: OnboardingLength?, agents: Bool = true) -> OnboardingState {
        var state = OnboardingState(
            agentsEnabled: agents,
            closedSide: .count,
            enabledWidgets: Set(NookWidgetKind.defaultEnabled),
            appliedTemplate: .planner,
            approveKeys: ["control", "option", "Y"],
            denyKeys: ["control", "option", "N"]
        )
        state.length = length
        return state
    }

    // MARK: The question page

    @Test func theQuestionPageDrawsNothingChosenAndEachCardChosen() throws {
        let none = try render("02-length-none") { tourView(.length, Self.state(length: nil)) }
        let pictures = try OnboardingLength.allCases.map { length in
            try render("02-length-\(length.rawValue)") { tourView(.length, Self.state(length: length)) }
        }

        #expect(Set(pictures + [none]).count == 4, "nothing and each card should draw a picture of its own")
        let size = try image { tourView(.length, Self.state(length: nil)) }
        #expect(size.width == Int(OnboardingStyle.windowSize.width * Self.scale))
        #expect(size.height == Int(OnboardingStyle.windowSize.height * Self.scale))
    }

    @Test func theQuestionPageCountsTheAgentsOutOfItsCardsWithTheSwitchOff() throws {
        let on = try render("02-length-agents-on") { tourView(.length, Self.state(length: nil, agents: true)) }
        let off = try render("02-length-agents-off") { tourView(.length, Self.state(length: nil, agents: false)) }
        #expect(on != off, "the cards show fewer pages with the agents off")
    }

    // MARK: A last page offers the longer tours

    @Test func theShortAndTheMainToursEndOnPagesThatOfferTheLongerOnes() throws {
        let short = try render("29-done-short") { tourView(.done, Self.state(length: .short)) }
        let medium = try render("29-done-medium") { tourView(.done, Self.state(length: .medium)) }
        let long = try render("29-done-long") { tourView(.done, Self.state(length: .long)) }

        #expect(Set([short, medium, long]).count == 3)
        for length in OnboardingLength.allCases {
            let size = try image { tourView(.done, Self.state(length: length)) }
            #expect(size.width == Int(OnboardingStyle.windowSize.width * Self.scale), "\(length)")
            #expect(size.height == Int(OnboardingStyle.windowSize.height * Self.scale), "\(length)")
        }
    }

    @Test func theLastPageOffersExactlyTheLongerToursInTheNavigationBar() {
        for (length, offered) in [(OnboardingLength.short, 2), (.medium, 1), (.long, 0)] {
            let tour = OnboardingTour(startingAt: .done, state: { Self.state(length: length) })
            #expect(tour.isLastPage)
            #expect(tour.carryOnLengths.count == offered, "\(length)")
        }
    }

    // MARK: Pages of the long tour

    @Test func pagesOfTheLongTourDrawThePictureOfTheirFeature() throws {
        let state = Self.state(length: .long)
        let power = try render("\(OnboardingPage.power.snapshotName)-long") { tourView(.power, state) }
        let usage = try render("\(OnboardingPage.usage.snapshotName)-long") { tourView(.usage, state) }
        let phone = try render("\(OnboardingPage.phone.snapshotName)-long") { tourView(.phone, state) }
        let links = try render("\(OnboardingPage.links.snapshotName)-long") { tourView(.links, state) }

        #expect(Set([power, usage, phone, links]).count == 4)
        for page in [OnboardingPage.power, .usage, .phone, .links] {
            let size = try image { tourView(page, state) }
            #expect(size.width == Int(OnboardingStyle.windowSize.width * Self.scale), "\(page)")
            #expect(size.height == Int(OnboardingStyle.windowSize.height * Self.scale), "\(page)")
        }
    }

    // MARK: Rendering

    private func tourView(_ page: OnboardingPage, _ state: OnboardingState) -> some View {
        let size = OnboardingTestSize.of(page)
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

    private func render<Content: View>(_ name: String, @ViewBuilder _ content: () -> Content) throws -> Data {
        let representation = NSBitmapImageRep(cgImage: try image(content))
        let png = try #require(representation.representation(using: .png, properties: [:]), "PNG encoding failed")
        if ProcessInfo.processInfo.environment[Self.snapshotEnvKey] == "1" {
            let directory = HangoverBrandTests.repoRoot.appendingPathComponent("output/render/onboarding", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return png
    }
}
