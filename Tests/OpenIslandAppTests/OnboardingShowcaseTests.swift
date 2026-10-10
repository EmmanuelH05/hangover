import AppKit
import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

// The features page's lines and the integrations page of the welcome tour
// (D43, D47).

// MARK: - What each line and each card stands on

struct OnboardingShowcaseProofTests {
    private static let abilityProofs = OnboardingAbility.allCases.flatMap { $0.proofs }
    private static let integrationProofs = OnboardingIntegration.allCases.flatMap { $0.proofs }

    /// Each feature line names something a widget does. These are the
    /// pieces of code that do it, and a line whose code is renamed fails
    /// here first.
    @Test(arguments: abilityProofs)
    func theCodeBehindAFeatureLineIsStillThere(proof: OnboardingProof) throws {
        let source = try HangoverBrandTests.text(of: proof.file)
        #expect(source.contains(proof.text), "\(proof.file) no longer has: \(proof.text)")
    }

    /// Same for each outside thing the integrations page names.
    @Test(arguments: integrationProofs)
    func theCodeBehindAnIntegrationIsStillThere(proof: OnboardingProof) throws {
        let source = try HangoverBrandTests.text(of: proof.file)
        #expect(source.contains(proof.text), "\(proof.file) no longer has: \(proof.text)")
    }

    @Test func everyLineAndEveryCardHasAtLeastOneProof() {
        for ability in OnboardingAbility.allCases {
            #expect(!ability.proofs.isEmpty, "\(ability) has no proof")
        }
        for integration in OnboardingIntegration.allCases {
            #expect(!integration.proofs.isEmpty, "\(integration) has no proof")
        }
    }

    @Test func everyWidgetHasFourToSevenLines() {
        for kind in NookWidgetKind.allCases {
            let lines = OnboardingAbility.lines(for: kind)
            #expect((4...7).contains(lines.count), "\(kind) has \(lines.count) lines")
        }
        #expect(OnboardingAbility.allCases.allSatisfy { OnboardingAbility.lines(for: $0.widget).contains($0) })
    }

    @Test func aWidgetsLinesAreItsOwnInTheOrderTheyAreTold() {
        #expect(OnboardingAbility.lines(for: .mirror) == [
            .mirrorOn, .mirrorRing, .mirrorBooth, .mirrorLooks, .mirrorSaved, .mirrorStrip, .mirrorFrames,
        ])
        #expect(OnboardingAbility.lines(for: .tray) == [.trayDrag, .trayActions, .trayClipboard, .trayPrivate])
        #expect(OnboardingAbility.lines(for: .notes) == [.notesAdd, .notesRecent, .notesDelete, .notesWhere])
    }
}

// MARK: - The integrations page

struct OnboardingIntegrationsTests {
    @Test func theAgentsAndTheTerminalsShowOnlyWithTheAgentsOn() {
        let on = OnboardingIntegration.shown(agentsEnabled: true)
        let off = OnboardingIntegration.shown(agentsEnabled: false)

        #expect(on == OnboardingIntegration.allCases)
        #expect(off == [.calendar, .appleNotes, .notion, .tickTick, .music, .power, .volume, .weather])
        #expect(off.allSatisfy { !$0.needsAgents })
        #expect(Set(on).subtracting(off) == [.agents, .terminals])
    }

    /// With the switch off the page says nothing about agents, in any word
    /// it shows.
    @Test func withTheAgentsOffNoCardSaysAnythingAboutAgents() throws {
        let english = try HangoverBrandTests.table("en")
        let words = ["agent", "terminal", "claude", "codex", "session"]
        for integration in OnboardingIntegration.shown(agentsEnabled: false) {
            for key in [integration.nameKey, integration.textKey, integration.whereKey] {
                let value = try #require(english[key]).lowercased()
                for word in words {
                    #expect(!value.contains(word), "\(key) says \(word) with the agents off")
                }
            }
        }
        for key in ["title", "body", "note"] {
            let value = try #require(english["onboarding.integrations.\(key)"]).lowercased()
            #expect(!value.contains("agent"), "\(key) says agent")
        }
    }

    @MainActor
    @Test func theCardsSitInRowsOfFive() {
        let all = OnboardingIntegration.shown(agentsEnabled: true)
        #expect(OnboardingIntegrationsPage.rows(all).map(\.count) == [5, 5])
        #expect(OnboardingIntegrationsPage.rows(OnboardingIntegration.shown(agentsEnabled: false)).map(\.count) == [5, 3])
    }

    @Test func theCardsNameWhereTheyAreSetUp() throws {
        let english = try HangoverBrandTests.table("en")
        for integration in OnboardingIntegration.allCases {
            let place = try #require(english[integration.whereKey])
            #expect(place.hasPrefix("Settings") || place == "Nothing to set up", "\(integration): \(place)")
        }
    }

    @Test func thePageSitsRightBeforeTheTipsInTheLastChapter() {
        let pages = OnboardingPage.allCases
        let index = pages.firstIndex(of: .integrations) ?? -1
        #expect(index >= 0 && pages[index + 1] == .tips)
        #expect(OnboardingPage.integrations.chapter == .know)
        #expect(OnboardingPage.integrations.snapshotName == "16-integrations")
        #expect(!OnboardingPage.integrations.isAgentsOnly)
        #expect(!OnboardingPage.integrations.needsTodoWidget)
    }

    @MainActor
    @Test func theStepCountAndTheProgressLineCountThePage() {
        let state = OnboardingState()
        let tour = OnboardingTour(startingAt: .integrations, state: { state })
        let pages = tour.pages

        #expect(pages.count == 17)
        #expect(pages.firstIndex(of: .integrations) == 14)
        var nookOnly = state
        nookOnly.agentsEnabled = false
        #expect(OnboardingTour.pages(for: nookOnly).count == 16)
        #expect(OnboardingView.progressFraction(step: 15, count: pages.count) == CGFloat(15) / CGFloat(17))
    }
}

// MARK: - Drawn pages

@MainActor
struct OnboardingShowcaseRenderTests {
    private static let scale: CGFloat = 2
    private static let snapshotEnvKey = "OPEN_ISLAND_RENDER_SNAPSHOTS"

    private static func state(agents: Bool = true) -> OnboardingState {
        var state = OnboardingState()
        state.agentsEnabled = agents
        state.enabledWidgets = Set(NookWidgetKind.defaultEnabled)
        state.appliedTemplate = .planner
        return state
    }

    @Test func theIntegrationsPageLeavesTheAgentsOutWithTheSwitchOff() throws {
        let on = try render("integrations-agents-on") { tourView(.integrations, Self.state(agents: true)) }
        let off = try render("integrations-agents-off") { tourView(.integrations, Self.state(agents: false)) }
        #expect(on != off)

        let size = try image { tourView(.integrations, Self.state(agents: false)) }
        #expect(size.width == Int(OnboardingStyle.windowSize.width * Self.scale))
        #expect(size.height == Int(OnboardingStyle.windowSize.height * Self.scale))
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
