import Foundation
import OpenIslandCore
import SwiftUI
import Testing
@testable import OpenIslandApp

// MARK: - The flow

struct OnboardingFlowTests {
    @Test func nextWalksEveryPageInOrderAndThenFinishes() {
        var flow = OnboardingFlow()
        var seen = [flow.page]
        for _ in 1..<OnboardingPage.allCases.count {
            flow.next()
            seen.append(flow.page)
        }

        #expect(seen == OnboardingPage.allCases)
        #expect(flow.isLastPage)
        #expect(flow.outcome == nil)

        flow.next()
        #expect(flow.outcome == .finished)
        #expect(flow.recordsCompletion)
    }

    @Test func backStepsOnePageAndStopsAtTheFirst() {
        var flow = OnboardingFlow()
        flow.back()
        #expect(flow.page == .welcome)
        #expect(flow.isFirstPage)

        flow.next()
        flow.next()
        flow.back()
        #expect(flow.page == .opening)
        #expect(flow.outcome == nil)
    }

    @Test(arguments: OnboardingPage.allCases)
    func skipEndsTheTourFromAnyPage(page: OnboardingPage) {
        var flow = OnboardingFlow(startingAt: page)
        #expect(!flow.recordsCompletion)

        flow.skip()

        #expect(flow.outcome == .skipped)
        #expect(flow.recordsCompletion)
        #expect(flow.page == page)
    }

    @Test func aDotGoesStraightToItsPage() {
        var flow = OnboardingFlow()
        flow.go(to: .permissions)
        #expect(flow.page == .permissions)
        flow.go(to: .opening)
        #expect(flow.page == .opening)
    }

    @Test func nothingMovesOnceTheTourHasEnded() {
        var finished = OnboardingFlow(startingAt: .done)
        finished.next()
        finished.back()
        finished.go(to: .welcome)
        finished.skip()
        #expect(finished.page == .done)
        #expect(finished.outcome == .finished)

        var skipped = OnboardingFlow(startingAt: .agents)
        skipped.skip()
        skipped.next()
        #expect(skipped.page == .agents)
        #expect(skipped.outcome == .skipped)
    }

    @Test func aTourCanStartOnTheAgentsPage() {
        let flow = OnboardingFlow(startingAt: .agents)
        #expect(flow.page == .agents)
        #expect(!flow.isFirstPage)
        #expect(!flow.hasEnded)
    }

    @Test func everyPageHasItsOwnSnapshotName() {
        let names = OnboardingPage.allCases.map(\.snapshotName)
        #expect(Set(names).count == OnboardingPage.allCases.count)
    }
}

// MARK: - The gate

struct OnboardingGateTests {
    private static func facts(isCompleted: Bool = false, isHarness: Bool = false) -> OnboardingGate.Facts {
        OnboardingGate.Facts(isCompleted: isCompleted, isHarness: isHarness)
    }

    @Test func anInstallThatHasNotEndedTheTourGetsItByItself() {
        #expect(OnboardingGate.showsByItself(Self.facts()))
    }

    @Test func anInstallThatEndedTheTourNeverGetsItByItselfAgain() {
        #expect(!OnboardingGate.showsByItself(Self.facts(isCompleted: true)))
    }

    @Test func aHarnessRunNeverGetsTheTour() {
        #expect(!OnboardingGate.showsByItself(Self.facts(isHarness: true)))
        #expect(!OnboardingGate.showsByItself(Self.facts(isCompleted: true, isHarness: true)))
    }

    /// A Mac that already had agents connected was marked as past its first
    /// launch by the startup migration, and was never shown the tour. It
    /// gets the tour all the same.
    @Test func aMacThatHadAgentsConnectedBeforeStillGetsTheTour() {
        let store = AgentIntentStore(defaults: MemoryDefaults())
        store.migrateFromLegacyStateIfNeeded { $0 == .claudeCode }

        #expect(store.firstLaunchCompleted)
        #expect(!store.welcomeTourEnded)
        #expect(OnboardingGate.showsByItself(Self.facts(isCompleted: store.welcomeTourEnded)))
    }

    @Test func aSecondLaunchWithTheTourStillOpenOffersItAgain() {
        let store = AgentIntentStore(defaults: MemoryDefaults())
        store.migrateFromLegacyStateIfNeeded { _ in false }
        store.migrateFromLegacyStateIfNeeded { _ in false }

        #expect(OnboardingGate.showsByItself(Self.facts(isCompleted: store.welcomeTourEnded)))
    }

    @Test func endingTheTourIsWhatStopsIt() {
        let store = AgentIntentStore(defaults: MemoryDefaults())

        store.welcomeTourEnded = true

        #expect(!OnboardingGate.showsByItself(Self.facts(isCompleted: store.welcomeTourEnded)))
    }

    // MARK: A launch set up through the environment

    @Test(arguments: [
        "OPEN_ISLAND_HARNESS_SCENARIO",
        "OPEN_ISLAND_HALO",
        "OPEN_ISLAND_HALO_THEME",
        "OPEN_ISLAND_NOOK_PAGE",
        "OPEN_ISLAND_NOOK_EDITING",
        "OPEN_ISLAND_MOTION_POLICY",
        "OPEN_ISLAND_TRACE_OVERLAY",
    ])
    func anyOpenIslandSwitchInTheEnvironmentMakesALaunchAHarness(name: String) {
        #expect(OnboardingGate.isHarnessLaunch(environment: ["PATH": "/usr/bin", name: "1"]))
    }

    @Test func anOrdinaryEnvironmentIsNotAHarness() {
        #expect(!OnboardingGate.isHarnessLaunch(environment: [:]))
        #expect(!OnboardingGate.isHarnessLaunch(environment: ["PATH": "/usr/bin", "HOME": "/Users/someone"]))
        // The prefix has to lead the name.
        #expect(!OnboardingGate.isHarnessLaunch(environment: ["MY_OPEN_ISLAND_HALO": "1", "OPEN_ISLANDS": "1"]))
    }
}

// MARK: - The tour on the app model

/// What the app model hands the gate and the pages. Nothing here opens a
/// window, installs anything or writes a setting.
@MainActor
struct OnboardingAppModelTests {
    private static func makeModel() -> AppModel {
        let model = AppModel()
        model.nook.presentRingLight = { _ in }
        return model
    }

    @Test func aLaunchDrivenOnlyByAForcedGlowOrPageCountsAsAHarness() {
        let model = Self.makeModel()

        let plain = model.welcomeTourFacts(environment: ["PATH": "/usr/bin"])
        let glow = model.welcomeTourFacts(environment: ["OPEN_ISLAND_HALO": "approval"])
        let page = model.welcomeTourFacts(environment: ["OPEN_ISLAND_NOOK_PAGE": "1"])

        #expect(plain.isHarness == false)
        #expect(glow.isHarness == true)
        #expect(page.isHarness == true)
        #expect(!OnboardingGate.showsByItself(glow))
        #expect(!OnboardingGate.showsByItself(page))
    }

    @Test func theFactsCarryWhetherTheTourWasEndedOnThisInstall() {
        let model = Self.makeModel()

        let facts = model.welcomeTourFacts(environment: [:])

        #expect(facts.isCompleted == model.hooks.intentStore.welcomeTourEnded)
        #expect(facts.isHarness == false)
    }

    @Test func aHarnessScenarioStillCountsThroughTheModelsOwnFlags() {
        let model = Self.makeModel()
        model.ignoresPointerExitDuringHarness = true

        #expect(model.welcomeTourFacts(environment: [:]).isHarness == true)
    }

    /// The pages are told what the app holds for the display the island is
    /// on, and whether the real island is open.
    @Test func theStateThePagesGetIsReadFromTheApp() {
        let model = Self.makeModel()
        let profile = model.activeAppearanceProfile
        let display = model.nook.displayPreferences(for: profile)

        let state = model.onboardingState

        #expect(state.displayProfile == profile)
        #expect(state.openedLook == display.openedLook)
        #expect(state.glowStyle == display.haloStyle)
        #expect(state.openTrigger == model.islandOpenTrigger)
        #expect(state.enabledWidgets == Set(model.nook.enabledWidgets))
        #expect(state.appliedTemplate == model.appliedTemplateID(for: profile))
        let theme = display.haloColors.usesSingleColor ? nil : IslandHaloTheme.matching(display.haloColors.palette)?.id
        #expect(state.glowThemeID == theme)
        #expect(state.isIslandOpen == (model.notchStatus == .opened))
        // The app model never claims a pick or a failure: those are the
        // tour's own.
        #expect(state.pickedTemplate == nil)
        #expect(state.hasOpenedIsland == false)
        #expect(OnboardingAgent.allCases.allSatisfy { state.status(of: $0).didFail == false })
    }

    @Test func eachAgentsRowReadsThatAgentsOwnInstallState() {
        let model = Self.makeModel()

        let state = model.onboardingState

        #expect(state.status(of: .claudeCode).isConnected == model.claudeHooksInstalled)
        #expect(state.status(of: .codex).isConnected == model.codexHooksInstalled)
        #expect(state.status(of: .cursor).isConnected == model.cursorHooksInstalled)
        #expect(state.status(of: .gemini).isConnected == model.geminiHooksInstalled)
        #expect(state.status(of: .openCode).isConnected == model.openCodePluginInstalled)
        // OpenCode loads a plugin and never waits for the hooks helper.
        #expect(state.status(of: .openCode).canConnect == true)
        #expect(state.status(of: .claudeCode).canConnect == (model.hooksBinaryURL != nil))
    }
}

// MARK: - The tour

/// Counts every call a tour makes into the app.
@MainActor
private final class OnboardingCallCounter {
    var openTriggers: [IslandOpenTrigger] = []
    var connected: [OnboardingAgent] = []
    var allAgents = 0
    var widgets: [NookWidgetKind] = []
    var templates: [PersonalizationTemplate.ID] = []
    var glowStyles: [IslandHaloStyle] = []
    var glowThemes: [String] = []
    var widths: [IslandOpenedWidth] = []
    var corners: [IslandOpenedCorners] = []
    /// Every call in the order it came, by the action's name.
    var order: [String] = []
    var ends: [OnboardingOutcome] = []
    var closes = 0

    var actionCalls: Int { order.count }

    var actions: OnboardingActions {
        OnboardingActions(
            setOpenTrigger: { self.openTriggers.append($0); self.order.append("openTrigger") },
            connect: { self.connected.append($0); self.order.append("connect") },
            showAllAgents: { self.allAgents += 1; self.order.append("allAgents") },
            setWidget: { kind, _ in self.widgets.append(kind); self.order.append("widget") },
            applyTemplate: { self.templates.append($0.id); self.order.append("template") },
            setGlowStyle: { self.glowStyles.append($0); self.order.append("glowStyle") },
            setGlowTheme: { self.glowThemes.append($0.id); self.order.append("glowTheme") },
            setOpenedWidth: { self.widths.append($0); self.order.append("width") },
            setOpenedCorners: { self.corners.append($0); self.order.append("corners") }
        )
    }
}

@MainActor
struct OnboardingTourTests {
    @Test func finishingRecordsTheTourAndClosesItOnce() {
        let store = AgentIntentStore(defaults: MemoryDefaults())
        let counter = OnboardingCallCounter()
        let tour = OnboardingTour.recording(in: store, state: { OnboardingState() }) { counter.closes += 1 }

        for _ in 1..<OnboardingPage.allCases.count { tour.next() }
        #expect(tour.page == .done)
        #expect(store.firstLaunchCompleted == false)
        #expect(counter.closes == 0)

        tour.next()
        #expect(store.firstLaunchCompleted == true)
        #expect(counter.closes == 1)

        // The window closing after the end must not end it again.
        tour.skip()
        tour.next()
        #expect(counter.closes == 1)
    }

    @Test func skippingRecordsTheTourTheSameWay() {
        let store = AgentIntentStore(defaults: MemoryDefaults())
        let counter = OnboardingCallCounter()
        let tour = OnboardingTour.recording(in: store, startingAt: .agents, state: { OnboardingState() }) {
            counter.closes += 1
        }

        tour.skip()

        #expect(store.firstLaunchCompleted == true)
        #expect(counter.closes == 1)
        #expect(tour.flow.outcome == .skipped)
    }

    @Test func turningPagesRecordsNothing() {
        let store = AgentIntentStore(defaults: MemoryDefaults())
        let tour = OnboardingTour.recording(in: store, state: { OnboardingState() })

        tour.next()
        tour.next()
        tour.back()
        tour.go(to: .permissions)

        #expect(store.firstLaunchCompleted == false)
        #expect(tour.flow.outcome == nil)
    }

    /// Walking the whole tour forward, back and to its end, with every
    /// page drawn on the way, touches the app through none of its actions.
    /// They run from a button and from nothing else.
    @Test func walkingTheTourAndDrawingEveryPageCallsNoAction() throws {
        let counter = OnboardingCallCounter()
        let tour = OnboardingTour(
            state: { OnboardingState() },
            actions: counter.actions,
            onEnd: { counter.ends.append($0) }
        )

        try draw(tour)
        for _ in 1..<OnboardingPage.allCases.count {
            tour.next()
            try draw(tour)
        }
        for _ in 1..<OnboardingPage.allCases.count {
            tour.back()
            try draw(tour)
        }
        for page in OnboardingPage.allCases {
            tour.go(to: page)
            try draw(tour)
        }
        #expect(counter.actionCalls == 0)
        #expect(counter.ends.isEmpty)

        tour.next()
        #expect(counter.actionCalls == 0)
        #expect(counter.ends == [.finished])
    }

    /// Builds the page a tour is on the way its window does, which runs
    /// the page's body and everything in it.
    private func draw(_ tour: OnboardingTour) throws {
        let renderer = ImageRenderer(content: OnboardingView(tour: tour, lang: .shared).environment(\.nookDrawsStill, true))
        renderer.scale = 1
        _ = try #require(renderer.cgImage, "the \(tour.page) page did not draw")
    }

    /// The pages are handed the tour's own wrapped actions. Each one must
    /// still reach the app's, once, with what it was given.
    @Test func theToursActionsPassThroughToTheApps() {
        let counter = OnboardingCallCounter()
        let tour = OnboardingTour(state: { OnboardingState() }, actions: counter.actions)

        tour.actions.connect(.claudeCode)
        tour.actions.setOpenTrigger(.click)
        tour.actions.setWidget(.mirror, true)
        tour.actions.applyTemplate(.planner)
        tour.actions.setGlowTheme(.lagoon)
        tour.actions.setOpenedWidth(.widest)
        tour.actions.setOpenedCorners(.square)
        tour.actions.showAllAgents()

        #expect(counter.connected == [.claudeCode])
        #expect(counter.openTriggers == [.click])
        #expect(counter.widgets == [.mirror])
        #expect(counter.templates == [.planner])
        #expect(counter.glowThemes == [IslandHaloTheme.lagoon.id])
        #expect(counter.widths == [.widest])
        #expect(counter.corners == [.square])
        #expect(counter.allAgents == 1)
        #expect(counter.order.count == 8)
    }

    // MARK: Choices on one page and choices on another

    /// A template carries a glow style of its own. One the user picked on
    /// the glow page is put back after the template is applied.
    @Test func aTemplatePickedAfterAGlowLeavesTheGlowAsItWasPicked() {
        let counter = OnboardingCallCounter()
        let tour = OnboardingTour(state: { OnboardingState() }, actions: counter.actions)

        tour.actions.setGlowStyle(.vivid)
        tour.actions.applyTemplate(.planner)

        #expect(counter.order == ["glowStyle", "template", "glowStyle"])
        #expect(counter.glowStyles == [.vivid, .vivid])
    }

    /// With no glow picked in the tour, a template brings its own and the
    /// tour adds nothing.
    @Test func aTemplateAloneSetsItsOwnGlow() {
        let counter = OnboardingCallCounter()
        let tour = OnboardingTour(state: { OnboardingState() }, actions: counter.actions)

        tour.actions.applyTemplate(.planner)

        #expect(counter.order == ["template"])
    }

    /// Changing the glow after a template makes the setup the user's own
    /// as far as Settings can tell (`appliedTemplate` goes nil). The tour
    /// still names the template that was picked.
    @Test func theTemplatePickedInTheTourStaysNamedAfterAnotherChoice() {
        let counter = OnboardingCallCounter()
        var applied: PersonalizationTemplate.ID? = .planner
        let tour = OnboardingTour(state: { OnboardingState(appliedTemplate: applied) }, actions: counter.actions)
        #expect(tour.state.shownTemplate == .planner)

        tour.actions.applyTemplate(.cockpit)
        applied = nil
        tour.actions.setGlowStyle(.off)

        #expect(tour.state.appliedTemplate == nil)
        #expect(tour.state.pickedTemplate == .cockpit)
        #expect(tour.state.shownTemplate == .cockpit)
    }

    @Test func withNothingPickedTheTourShowsTheTemplateTheDisplayIsOn() {
        let tour = OnboardingTour(state: { OnboardingState(appliedTemplate: .planner) })
        #expect(tour.state.pickedTemplate == nil)
        #expect(tour.state.shownTemplate == .planner)
        #expect(OnboardingTour(state: { OnboardingState() }).state.shownTemplate == nil)
    }

    // MARK: A connect that did not work

    @Test func aConnectThatEndsWithoutAConnectionIsMarkedAsFailed() {
        var status = OnboardingAgentStatus()
        let tour = OnboardingTour(state: { OnboardingState(agents: [.codex: status]) })
        // Not pressed yet: an agent that is not connected has not failed.
        #expect(tour.state.status(of: .codex).didFail == false)

        status.isBusy = true
        tour.actions.connect(.codex)
        #expect(tour.state.status(of: .codex).didFail == false, "still installing")

        status.isBusy = false
        #expect(tour.state.status(of: .codex).didFail == true)
        #expect(tour.state.status(of: .cursor).didFail == false, "only the agent that was pressed")

        status.isConnected = true
        #expect(tour.state.status(of: .codex).didFail == false, "a retry that worked clears it")
    }

    // MARK: The try-it line

    @Test func havingOpenedTheIslandOnceStaysTrueAfterItCloses() {
        var isOpen = false
        let tour = OnboardingTour(state: { OnboardingState(isIslandOpen: isOpen) })
        #expect(tour.state.hasOpenedIsland == false)

        isOpen = true
        #expect(tour.state.hasOpenedIsland == true)

        isOpen = false
        #expect(tour.state.isIslandOpen == false)
        #expect(tour.state.hasOpenedIsland == true)
    }

    @Test func aTourReadsTheAppsStateFreshEveryTime() {
        var trigger = IslandOpenTrigger.hover
        let tour = OnboardingTour(state: { OnboardingState(openTrigger: trigger) })

        #expect(tour.state.openTrigger == .hover)
        trigger = .click
        #expect(tour.state.openTrigger == .click)
    }
}

// MARK: - What the pages are told

struct OnboardingStateTests {
    @Test func aShortcutIsSpelledOutAsTheWordsOnTheKeys() {
        let approve = OnboardingShortcutWords.caps(
            for: AgentHotkeySettings.defaultApprove,
            keyName: AgentHotkeyKeyboard.usName
        )
        let deny = OnboardingShortcutWords.caps(
            for: AgentHotkeySettings.defaultDeny,
            keyName: AgentHotkeyKeyboard.usName
        )

        #expect(approve == ["control", "option", "Y"])
        #expect(deny == ["control", "option", "N"])
    }

    @Test func modifiersComeInTheOrderMenusWriteThem() {
        let combo = AgentHotkeyCombo(
            keyCode: AgentHotkeyKeyboard.keyY,
            modifiers: [.command, .shift, .option, .control]
        )
        let caps = OnboardingShortcutWords.caps(for: combo, keyName: { _ in nil })

        #expect(caps == ["control", "option", "shift", "command", "Key \(AgentHotkeyKeyboard.keyY)"])
    }

    @Test func connectedAgentsKeepTheToursOrder() {
        var state = OnboardingState()
        #expect(state.connectedAgents.isEmpty)
        #expect(state.status(of: .codex) == OnboardingAgentStatus())

        state.agents[.openCode] = OnboardingAgentStatus(isConnected: true)
        state.agents[.claudeCode] = OnboardingAgentStatus(isConnected: true)
        state.agents[.cursor] = OnboardingAgentStatus(isBusy: true)

        #expect(state.connectedAgents == [.claudeCode, .openCode])
    }

    @Test func theToursStartingWidgetsAreTheAppsOwn() {
        #expect(OnboardingState().enabledWidgets == Set(NookWidgetKind.defaultEnabled))
        // The two the tour says start switched off.
        #expect(!NookWidgetKind.defaultEnabled.contains(.mirror))
        #expect(!NookWidgetKind.defaultEnabled.contains(.weather))
    }
}
