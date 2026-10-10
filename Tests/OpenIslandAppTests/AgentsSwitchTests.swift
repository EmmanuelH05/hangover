import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// The agents switch (D41): one preference that turns the whole agent half
/// off. Every model here keeps the switch in a `MemoryDefaults`, and none is
/// ever started with the switch on, which would open the bridge socket and
/// read the real home folder.
@MainActor
struct AgentsSwitchTests {
    private static func model(agentsEnabled: Bool? = nil) -> (AppModel, MemoryDefaults) {
        let defaults = MemoryDefaults()
        if let agentsEnabled {
            defaults.set(agentsEnabled, forKey: AgentsSwitch.defaultsKey)
        }
        return (AppModel(agentsDefaults: defaults, defaults: MemoryDefaults()), defaults)
    }

    private static func session(
        id: String = "session",
        phase: SessionPhase = .waitingForApproval
    ) -> AgentSession {
        var session = AgentSession(
            id: id,
            title: "Claude · project",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: "Working",
            updatedAt: .now,
            permissionRequest: phase == .waitingForApproval
                ? PermissionRequest(title: "Approve", summary: "Allow edit?", affectedPath: "/tmp/file.swift")
                : nil
        )
        session.isProcessAlive = true
        return session
    }

    // MARK: - The preference

    @Test
    func theSwitchIsOnWhenNothingWasSaved() {
        #expect(AgentsSwitch.defaultsKey == "app.agentsEnabled")
        #expect(AgentsSwitch.load(from: MemoryDefaults()))
        #expect(Self.model().0.agentsEnabled)
    }

    @Test
    func theSwitchLoadsWhatWasSaved() {
        #expect(Self.model(agentsEnabled: false).0.agentsEnabled == false)
        #expect(Self.model(agentsEnabled: true).0.agentsEnabled)
    }

    @Test
    func aChangeIsSavedUnderItsKey() {
        let (model, defaults) = Self.model()
        #expect(defaults.all.isEmpty)

        model.agentsEnabled = false
        #expect(defaults.object(forKey: "app.agentsEnabled") as? Bool == false)
        #expect(AppModel(agentsDefaults: defaults, defaults: MemoryDefaults()).agentsEnabled == false)

        model.agentsEnabled = true
        #expect(defaults.object(forKey: "app.agentsEnabled") as? Bool == true)
    }

    // MARK: - Nothing runs while off

    @Test
    func aLaunchAsksForNoPartOfTheAgentHalfWhileOff() {
        let everything = AgentRuntimeParts.launch(startBridge: true, loadRuntimeState: true)
        #expect(everything == [.sessions, .bridge])
        #expect(everything.allowed(agentsEnabled: true) == everything)
        #expect(everything.allowed(agentsEnabled: false).isEmpty)

        // A harness launch asks for less, and off still means nothing.
        #expect(AgentRuntimeParts.launch(startBridge: false, loadRuntimeState: true) == [.sessions])
        #expect(AgentRuntimeParts.launch(startBridge: false, loadRuntimeState: false).isEmpty)
        #expect(AgentRuntimeParts.launch(startBridge: true, loadRuntimeState: false).allowed(agentsEnabled: false).isEmpty)
    }

    @Test
    func nothingOfTheAgentHalfStartsInAModelStartedWithTheSwitchOff() {
        let (model, _) = Self.model(agentsEnabled: false)
        // What a real launch asks for.
        model.agentLaunch = [.sessions, .bridge]

        model.startAgentRuntime()

        #expect(model.agentRuntime.isEmpty)
        #expect(model.isBridgeReady == false)
        #expect(model.monitoring.isMonitoring == false)
        #expect(model.hooks.isUsageMonitoring == false)
        #expect(model.codexAppServer.isConnected == false)
        #expect(model.watchRelay == nil)
        #expect(model.isResolvingInitialLiveSessions == false)
        #expect(model.state.sessions.isEmpty)
    }

    @Test
    func switchingOnBeforeAnyLaunchStartsNothing() {
        let (model, _) = Self.model(agentsEnabled: false)

        model.agentsEnabled = true

        // No launch has said what to run, and a test must never open the
        // bridge socket.
        #expect(model.agentLaunch == nil)
        #expect(model.agentRuntime.isEmpty)
        #expect(model.isBridgeReady == false)
        #expect(model.monitoring.isMonitoring == false)
    }

    @Test
    func anEventThatArrivesWhileOffIsDropped() {
        let (model, _) = Self.model(agentsEnabled: false)

        model.applyTrackedEvent(.sessionStarted(SessionStarted(
            sessionID: "late",
            title: "Claude · late",
            tool: .claudeCode,
            summary: "Started",
            timestamp: .now
        )))

        #expect(model.state.sessions.isEmpty)
    }

    @Test
    func discoveryIsToldWhenTheSwitchIsOff() {
        // A late rescan and every registry save ask this first, which is
        // what keeps the session files on disk as they were.
        let (model, _) = Self.model()
        #expect(model.discovery.isActive())

        model.agentsEnabled = false
        #expect(model.discovery.isActive() == false)

        model.agentsEnabled = true
        #expect(model.discovery.isActive())
    }

    @Test
    func theAgentShortcutsAreNeverRegisteredWhileOff() {
        let (model, _) = Self.model(agentsEnabled: false)
        let registrar = FakeHotkeyRegistrar()
        model.state = SessionState(sessions: [Self.session()])

        model.activateAgentHotkeys(registrar: registrar)

        // Not even the one registration that checks whether macOS takes
        // the shortcuts.
        #expect(registrar.registerCalls == 0)
        #expect(model.agentHotkeys.isActive == false)
        #expect(model.agentHotkeyWaiting().isEmpty)
        model.refreshAgentHotkeyArming(hasWaitingSession: true)
        #expect(registrar.registerCalls == 0)
        #expect(registrar.registered.isEmpty)
    }

    @Test
    func theAgentShortcutsFollowTheSwitch() {
        let (model, _) = Self.model(agentsEnabled: false)
        let registrar = FakeHotkeyRegistrar()
        model.activateAgentHotkeys(registrar: registrar)

        model.agentsEnabled = true
        #expect(model.agentHotkeys.isActive)
        #expect(registrar.registerCalls == 1)

        model.agentsEnabled = false
        #expect(model.agentHotkeys.isActive == false)
        #expect(registrar.registered.isEmpty)
        #expect(registrar.unregisterCalls >= 1)
    }

    // MARK: - Switching off at runtime

    @Test
    func switchingOffDropsTheSessionsAndTheCard() {
        let (model, _) = Self.model()
        let session = Self.session()
        model.state = SessionState(sessions: [session])
        model.selectedSessionID = session.id
        model.notchStatus = .opened
        model.notchOpenReason = .notification
        model.islandSurface = .sessionList(actionableSessionID: session.id)
        #expect(model.surfacedSessions.count == 1)

        model.agentsEnabled = false

        #expect(model.state.sessions.isEmpty)
        #expect(model.selectedSessionID == nil)
        #expect(model.islandSurface.sessionID == nil)
        #expect(model.agentRuntime.isEmpty)
        #expect(model.isBridgeReady == false)
    }

    // MARK: - Nothing shows while off

    @Test
    func theGatesReturnNothingWhileOff() {
        let (model, _) = Self.model(agentsEnabled: false)
        // A session that got in some other way must still not show.
        let session = Self.session()
        model.state = SessionState(sessions: [session, Self.session(id: "running", phase: .running)])

        #expect(model.sessions.isEmpty)
        #expect(model.surfacedSessions.isEmpty)
        #expect(model.recentSessions.isEmpty)
        #expect(model.islandListSessions.isEmpty)
        #expect(model.liveSessionCount == 0)
        #expect(model.liveAttentionCount == 0)
        #expect(model.focusedSession == nil)
        #expect(model.hasAnySession == false)
        #expect(model.shouldShowSessionBootstrapPlaceholder == false)
    }

    @Test
    func theClosedIslandShowsNothingOfTheAgentsWhileOff() {
        let (model, _) = Self.model(agentsEnabled: false)
        model.state = SessionState(sessions: [Self.session()])

        #expect(model.islandClosedMode == .idle)
        #expect(model.islandClosedSpotlight == nil)
        #expect(model.islandClosedLabel() == nil)
        #expect(model.islandClosedRightSlotContent() == nil)
        #expect(model.islandSlotContent(for: .count) == nil)
        #expect(model.islandSlotContent(for: .agents) == nil)
        #expect(model.nookAgentStatusTint == nil)
        // Neither side shows a choice that is the agents', and the left
        // side has no bars to fall back to. The slot is named here: the
        // saved one comes from settings a test must not depend on.
        for slot in [NookSideSlot.agents, .count, .grid] {
            #expect(model.nookSideSlotContent(for: slot) == nil)
            #expect(model.nookLeftSlotContent(for: slot) == .hidden)
        }
        #expect(model.nookLeftSlotContent(for: .none) == .hidden)
        #expect(model.nookLeftSlotContent(for: .date) != .hidden)
    }

    @Test
    func theGlowNeverShowsAnAgentStateWhileOff() {
        let (model, _) = Self.model(agentsEnabled: false)
        model.state = SessionState(sessions: [Self.session(), Self.session(id: "running", phase: .running)])

        let inputs = model.islandHaloInputs
        #expect(inputs.waiting == nil)
        #expect(inputs.isRunning == false)
        #expect(inputs.flashToken == nil)
    }

    @Test
    func theOpenedIslandIsTheNookPageAloneWhileOff() {
        let (model, _) = Self.model(agentsEnabled: false)
        let session = Self.session()
        model.state = SessionState(sessions: [session])

        #expect(model.showsNookPage)
        #expect(model.showsPageSwitch == false)

        // Neither the header control nor a link can turn to the agents page.
        model.showAgentsPage()
        #expect(model.showsNookPage)
        model.nook.pageOverride = .agents
        #expect(model.showsNookPage)
        #expect(model.perform(.openAgents) == false)

        #expect(model.showsNookAgentsBar == false)
        #expect(model.showsNookCompactBar == false)

        // A card left over from before the switch is not drawn.
        model.notchStatus = .opened
        model.notchOpenReason = .notification
        model.islandSurface = .sessionList(actionableSessionID: session.id)
        #expect(model.showsNookPage)
        #expect(model.activeIslandCardSession == nil)
        #expect(model.liveOpenedPresentation().session == nil)
        #expect(model.shouldBlockDismissWhileAwaitingDecision == false)
    }

    @Test
    func theSameModelShowsItsAgentsWhileOn() {
        let (model, _) = Self.model()
        model.state = SessionState(sessions: [Self.session()])

        #expect(model.surfacedSessions.count == 1)
        #expect(model.islandClosedMode == .waiting)
        #expect(model.islandSlotContent(for: .count) == .count(1))
        #expect(model.showsPageSwitch)
        #expect(model.islandHaloInputs.waiting == .approval)
        // The agent bars keep the left side, which nil stands for.
        #expect(model.nookLeftSlotContent(for: .agents) == nil)
        #expect(model.nookSideSlotContent(for: .agents) == .bars(.waiting))
        #expect(model.nookSideSlotContent(for: .count) == .agentSlot(.count(1)))
    }

    // MARK: - Personalization

    @Test
    func choicesThatNeedAgentsAreNamed() {
        #expect(IslandRightSlot.allCases.filter(\.needsAgents) == [.count, .agents])
        #expect(IslandCenterLabel.allCases.filter(\.needsAgents) == [.sessionName, .agentAction])
        #expect(NookSideSlot.allCases.filter(\.needsAgents) == [.agents, .count, .grid])
        #expect(NookOpenedPage.allCases.filter(\.needsAgents) == [.auto, .agents])
    }

    @Test
    func personalizationOffersOnlyChoicesThatWorkWithoutAgentsWhileOff() {
        #expect(AgentsSwitch.offered([IslandRightSlot.count, .agents, .none], agentsEnabled: false) == [.none])
        #expect(AgentsSwitch.offered([IslandRightSlot.count, .agents, .none], agentsEnabled: true) == [.count, .agents, .none])
        #expect(
            AgentsSwitch.offered([NookSideSlot.agents, .count, .grid, .none], agentsEnabled: false) == [.none]
        )
        #expect(
            AgentsSwitch.offered([NookSideSlot.agents, .date, .battery, .countdown], agentsEnabled: false)
                == [.date, .battery, .countdown]
        )
        #expect(AgentsSwitch.offered(IslandCenterLabel.allCases, agentsEnabled: false) == [.off])
    }

    @Test
    func aSavedAgentChoiceIsShownAsNoneWhileOffAndKept() {
        // The saved choice is not rewritten: it is back when the switch is.
        #expect(AgentsSwitch.shown(IslandRightSlot.count, agentsEnabled: false) == IslandRightSlot.none)
        #expect(AgentsSwitch.shown(IslandRightSlot.count, agentsEnabled: true) == .count)
        #expect(AgentsSwitch.shown(NookSideSlot.agents, agentsEnabled: false) == NookSideSlot.none)
        #expect(AgentsSwitch.shown(NookSideSlot.battery, agentsEnabled: false) == .battery)
    }

    @Test
    func theAgentsTemplateIsNotOfferedWhileOff() {
        let off = PersonalizationTemplate.offered(agentsEnabled: false).map(\.id)
        #expect(off == [.everything, .nowPlaying, .planner, .focus, .study, .minimal])
        #expect(PersonalizationTemplate.offered(agentsEnabled: true) == PersonalizationTemplate.all)
    }

    @Test
    func aTemplateCardSaysNothingAboutAgentsWhileOff() {
        let minimal = TemplateText.keys(for: .minimal, showsAgents: false).points
        #expect(minimal == [
            "settings.appearance.templates.minimal.point1.nookOnly",
            "settings.appearance.templates.minimal.point2.nookOnly",
            "settings.appearance.templates.minimal.point3",
        ])
        #expect(TemplateText.keys(for: .minimal, showsAgents: true) == TemplateText.keys(for: .minimal))
        #expect(TemplateText.keys(for: .planner, showsAgents: false) == TemplateText.keys(for: .planner))

        // A thumbnail leaves a side empty where the template shows agents.
        let glyphs: [PersonalizationTemplate.Glyph] = [
            .bars, .count, .agents, .date, .battery, .countdown, .artwork, .visualizer, .none,
        ]
        #expect(glyphs.filter(\.needsAgents) == [.bars, .count, .agents])
    }

    @Test
    func theGlowListsOnlyNoticeAndMusicColorsWhileOff() {
        #expect(IslandHaloMoment.shown(agentsEnabled: false) == [.notice, .music])
        #expect(IslandHaloMoment.shown(agentsEnabled: true) == IslandHaloMoment.allCases)
    }

    // MARK: - Settings

    @Test
    func settingsHidesTheTabsThatAreOnlyAboutAgentsWhileOff() {
        let off = SettingsTab.shown(agentsEnabled: false)
        #expect(!off.contains(.setup))
        #expect(!off.contains(.watch))
        #expect(off == [.general, .display, .sound, .appearance, .nook, .shortcuts, .lab, .about])
        #expect(SettingsTab.shown(agentsEnabled: true) == SettingsTab.allCases)

        #expect(SettingsSection.system.tabs(agentsEnabled: false) == [.general, .display, .sound, .appearance, .nook])
        #expect(SettingsSection.system.tabs(agentsEnabled: true) == SettingsSection.system.tabs)
    }

    @Test
    func aHiddenTabFallsBackToGeneral() {
        #expect(SettingsTab.setup.landing(agentsEnabled: false) == .general)
        #expect(SettingsTab.watch.landing(agentsEnabled: false) == .general)
        #expect(SettingsTab.nook.landing(agentsEnabled: false) == .nook)
        #expect(SettingsTab.setup.landing(agentsEnabled: true) == .setup)
    }

    @Test
    func generalHidesTheRowsThatAreOnlyAboutAgentsWhileOff() {
        let off = GeneralSettingsRow.shown(agentsEnabled: false)
        #expect(off == [.showDockIcon, .linksFromOtherApps, .openTrigger, .swipeGestures, .hapticFeedback])
        #expect(GeneralSettingsRow.shown(agentsEnabled: true) == GeneralSettingsRow.allCases)
    }

    // MARK: - The welcome tour

    @Test
    func theTourLeavesItsAgentsPageOutWhileOff() {
        let off = OnboardingPage.shown(agentsEnabled: false)
        #expect(off == [.welcome, .purpose, .opening, .closed, .widgets, .features, .layout, .arrange, .todos, .notes, .weather, .opened, .look, .permissions, .integrations, .tips, .done])
        #expect(OnboardingPage.shown(agentsEnabled: true) == OnboardingPage.allCases)
    }

    @Test
    func theFlowWalksOnlyThePagesItWasGiven() {
        var flow = OnboardingFlow(pages: OnboardingPage.shown(agentsEnabled: false))
        var seen = [flow.page]
        while !flow.isLastPage {
            flow.next()
            seen.append(flow.page)
        }
        #expect(seen == [.welcome, .purpose, .opening, .closed, .widgets, .features, .layout, .arrange, .todos, .notes, .weather, .opened, .look, .permissions, .integrations, .tips, .done])

        flow.go(to: .agents)
        #expect(flow.page == .done)

        flow.go(to: .widgets)
        flow.back()
        #expect(flow.page == .closed)
        flow.back()
        flow.back()
        flow.back()
        #expect(flow.page == .welcome)
        #expect(flow.isFirstPage)
    }

    @Test
    func aTourAskedToStartOnTheAgentsPageStartsOnThePageBeforeItWhileOff() {
        let flow = OnboardingFlow(startingAt: .agents, pages: OnboardingPage.shown(agentsEnabled: false))
        #expect(flow.page == .closed)
        #expect(OnboardingFlow(startingAt: .agents).page == .agents)
    }

    @Test
    func theTourOffersTheSwitchAndFollowsIt() {
        var agentsEnabled = true
        var actions = OnboardingActions()
        actions.setAgentsEnabled = { agentsEnabled = $0 }
        let tour = OnboardingTour(
            state: {
                var state = OnboardingState()
                state.agentsEnabled = agentsEnabled
                return state
            },
            actions: actions
        )
        // Weather starts switched off, so its page is not walked.
        #expect(tour.pages == OnboardingPage.shown(agentsEnabled: true, hasWeatherWidget: false))

        // The switch is the purpose page, which no run leaves out.
        #expect(OnboardingPage.shown(agentsEnabled: false).contains(.purpose))
        #expect(OnboardingPage.purpose.offersAgentsSwitch)
        #expect(OnboardingPage.allCases.filter(\.offersAgentsSwitch) == [.purpose])
        tour.actions.setAgentsEnabled(false)
        #expect(agentsEnabled == false)
        #expect(tour.state.agentsEnabled == false)
        #expect(tour.pages == OnboardingPage.shown(agentsEnabled: false, hasWeatherWidget: false))

        tour.go(to: .closed)
        tour.next()
        #expect(tour.page == .widgets)
        tour.back()
        #expect(tour.page == .closed)

        tour.actions.setAgentsEnabled(true)
        tour.next()
        #expect(tour.page == .agents)
    }

    @Test
    func aTourLeftOnTheAgentsPageMovesBackWhenTheSwitchGoesOffElsewhere() {
        var agentsEnabled = true
        let tour = OnboardingTour(startingAt: .agents, state: {
            var state = OnboardingState()
            state.agentsEnabled = agentsEnabled
            return state
        })
        #expect(tour.page == .agents)

        // Switched off in Settings while the tour is up.
        agentsEnabled = false
        #expect(tour.page == .closed)
        #expect(tour.isFirstPage == false)

        tour.next()
        #expect(tour.page == .widgets)
    }

    @Test
    func theTourSaysNothingAboutAgentsWhileOff() {
        #expect(OnboardingGrant.shown(agentsEnabled: false) == [.camera, .accessibility, .calendar])
        #expect(OnboardingGrant.shown(agentsEnabled: true) == OnboardingGrant.allCases)

        #expect(OnboardingRecapRow.shown(agentsEnabled: false) == [.opens, .closed, .widgets, .calendar, .todos, .notes, .weather, .layout, .opened, .glow])
        #expect(OnboardingRecapRow.shown(agentsEnabled: true) == OnboardingRecapRow.allCases)
    }

    @Test
    func theModelHandsTheTourItsSwitch() {
        let (model, defaults) = Self.model()
        #expect(model.onboardingState.agentsEnabled)

        model.agentsEnabled = false
        #expect(model.onboardingState.agentsEnabled == false)
        #expect(defaults.object(forKey: AgentsSwitch.defaultsKey) as? Bool == false)
    }

    /// The purpose page's two cards call this action. It writes the same
    /// preference as the switch in Settings, and the tour follows it.
    @Test
    func theToursPurposePageWritesTheSwitch() {
        let (model, defaults) = Self.model()
        let tour = model.makeWelcomeTour(startingAt: .purpose)
        #expect(tour.page == .purpose)
        // Weather starts switched off, so its page is not walked.
        #expect(tour.pages == OnboardingPage.shown(agentsEnabled: true, hasWeatherWidget: false))

        tour.actions.setAgentsEnabled(false)

        #expect(model.agentsEnabled == false)
        #expect(defaults.object(forKey: AgentsSwitch.defaultsKey) as? Bool == false)
        #expect(tour.state.agentsEnabled == false)
        #expect(tour.page == .purpose, "the page with the switch stays up")
        #expect(tour.pages == OnboardingPage.shown(agentsEnabled: false, hasWeatherWidget: false))
        #expect(tour.state.closedSide.map { !$0.needsAgents } ?? true)
    }

    @Test
    func thePermissionsPageNamesATerminalJumpOnlyWithTheAgentsOn() {
        #expect(OnboardingGrant.accessibility.noteKey(agentsEnabled: true) == "onboarding.permissions.accessibility.note.agents")
        #expect(OnboardingGrant.accessibility.noteKey(agentsEnabled: false) == "onboarding.permissions.accessibility.note")
        #expect(OnboardingGrant.camera.noteKey(agentsEnabled: true) == OnboardingGrant.camera.noteKey(agentsEnabled: false))
    }

    // MARK: - Strings

    @Test(arguments: ["en", "zh-Hans", "zh-Hant"])
    func everyNewStringIsInEveryLanguage(language: String) throws {
        let url = Self.repoRoot
            .appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
        let strings = try #require(NSDictionary(contentsOf: url) as? [String: String], "\(language) did not load")
        for key in AgentsSwitch.stringKeys {
            let text = strings[key] ?? ""
            #expect(!text.isEmpty, "\(language) is missing \(key)")
            #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"), "\(key) in \(language) has a dash")
        }
    }

    /// `Tests/OpenIslandAppTests/<this file>` sits three levels below the root.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
