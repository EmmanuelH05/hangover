import AppKit
import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

// The widget spotlight and the integrations page of the welcome tour (D43).

// MARK: - What each line and each card stands on

struct OnboardingShowcaseProofTests {
    private static let abilityProofs = OnboardingAbility.allCases.flatMap { $0.proofs }
    private static let integrationProofs = OnboardingIntegration.allCases.flatMap { $0.proofs }

    /// Each spotlight line names something a widget does. These are the
    /// pieces of code that do it, and a line whose code is renamed fails
    /// here first.
    @Test(arguments: abilityProofs)
    func theCodeBehindASpotlightLineIsStillThere(proof: OnboardingProof) throws {
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

    @Test func everyWidgetHasAtLeastOneLineAndAtMostThree() {
        for kind in NookWidgetKind.allCases {
            let lines = OnboardingAbility.lines(for: kind)
            #expect(!lines.isEmpty, "\(kind) has no spotlight line")
            #expect(lines.count <= 3, "\(kind) has \(lines.count) lines")
        }
        #expect(OnboardingAbility.allCases.allSatisfy { OnboardingAbility.lines(for: $0.widget).contains($0) })
    }

    @Test func aWidgetsLinesAreItsOwnInTheOrderTheyAreTold() {
        #expect(OnboardingAbility.lines(for: .mirror) == [.mirrorBooth, .mirrorStrip, .mirrorFrames])
        #expect(OnboardingAbility.lines(for: .tray) == [.trayDrag, .trayActions, .trayClipboard])
        #expect(OnboardingAbility.lines(for: .notes) == [.notesAdd, .notesWhere])
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
        #expect(OnboardingPage.integrations.snapshotName == "15-integrations")
        #expect(!OnboardingPage.integrations.isAgentsOnly)
        #expect(!OnboardingPage.integrations.needsTodoWidget)
    }

    @MainActor
    @Test func theStepCountAndTheProgressLineCountThePage() {
        let state = OnboardingState()
        let tour = OnboardingTour(startingAt: .integrations, state: { state })
        let pages = tour.pages

        #expect(pages.count == 16)
        #expect(pages.firstIndex(of: .integrations) == 13)
        var nookOnly = state
        nookOnly.agentsEnabled = false
        #expect(OnboardingTour.pages(for: nookOnly).count == 15)
        #expect(OnboardingView.progressFraction(step: 14, count: pages.count) == CGFloat(14) / CGFloat(16))
    }
}

// MARK: - Drawn pages

@MainActor
struct OnboardingShowcaseRenderTests {
    private static let scale: CGFloat = 2
    private static let snapshotEnvKey = "OPEN_ISLAND_RENDER_SNAPSHOTS"

    private static func state(agents: Bool = true, spotlight: NookWidgetKind? = nil) -> OnboardingState {
        var state = OnboardingState()
        state.agentsEnabled = agents
        state.enabledWidgets = Set(NookWidgetKind.defaultEnabled)
        state.appliedTemplate = .planner
        if let spotlight { state.spotlight = spotlight }
        return state
    }

    @Test func theFirstWidgetIsSelectedToBeginWith() {
        #expect(OnboardingState().spotlight == NookWidgetKind.allCases.first)
    }

    /// Every widget has its own spotlight, the ones that are off included.
    @Test func selectingAWidgetChangesTheSpotlight() throws {
        var pictures: [Data] = []
        for kind in NookWidgetKind.allCases {
            let page = try render("widgets-spotlight-\(kind.rawValue)") { tourView(.widgets, Self.state(spotlight: kind)) }
            pictures.append(page)
        }
        #expect(Set(pictures).count == NookWidgetKind.allCases.count, "every widget should draw its own spotlight")

        let off = Self.state(spotlight: .mirror)
        #expect(!off.showsWidget(.mirror), "the mirror starts switched off")
    }

    @Test func aClickOnARowSelectsItAndLeavesTheSwitchAlone() {
        var chosen: [NookWidgetKind] = []
        var switched: [NookWidgetKind] = []
        var actions = OnboardingActions()
        actions.spotlightWidget = { chosen.append($0) }
        actions.setWidget = { kind, _ in switched.append(kind) }
        let tour = OnboardingTour(startingAt: .widgets, state: { Self.state() }, actions: actions)

        tour.actions.spotlightWidget(.timer)

        #expect(chosen == [.timer])
        #expect(switched.isEmpty)
        #expect(tour.state.spotlight == .timer)
        tour.actions.spotlightWidget(.tray)
        #expect(tour.state.spotlight == .tray)
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
