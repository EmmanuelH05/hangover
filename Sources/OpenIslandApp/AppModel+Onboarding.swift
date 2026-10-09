import Foundation

/// The welcome tour on the live app: when it shows, what its pages read
/// and what its buttons do. The pages and the flow know nothing about the
/// app model; this is the only place the two meet.
extension AppModel {
    /// Opens the welcome tour's window, or brings it forward when it is
    /// already up. Always the result of a click, except for the one time
    /// `offerWelcomeTour` shows it on a fresh install.
    func showWelcomeTour(startingAt page: OnboardingPage = .welcome) {
        OnboardingWindowController.shared.show(
            startingAt: page,
            title: lang.t("onboarding.window.title"),
            lang: lang
        ) { close in
            makeWelcomeTour(startingAt: page, close: close)
        }
    }

    /// Shows the tour by itself until it has been ended once on this
    /// install, and never in a harness run.
    func offerWelcomeTour() {
        guard OnboardingGate.showsByItself(welcomeTourFacts()) else { return }
        showWelcomeTour()
    }

    /// What the gate decides from. A launch counts as a harness when the
    /// app was told to be one, or when any `OPEN_ISLAND_` switch is set in
    /// its environment, which covers a run driven only by a forced glow or
    /// a forced page.
    func welcomeTourFacts(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> OnboardingGate.Facts {
        OnboardingGate.Facts(
            isCompleted: hooks.intentStore.welcomeTourEnded,
            isHarness: ignoresPointerExitDuringHarness
                || disablesOverlayEventMonitoringDuringHarness
                || OnboardingGate.isHarnessLaunch(environment: environment)
        )
    }

    /// Opens Settings on the Setup tab, where every agent is listed.
    func showSetupSettings() {
        showSettings()
        NotificationCenter.default.post(name: .openIslandSelectSetupTab, object: nil)
    }

    /// A tour wired to this model. Ending it, by its last button, by Skip
    /// or by closing its window, records that the tour was seen and puts
    /// the window away.
    func makeWelcomeTour(
        startingAt page: OnboardingPage = .welcome,
        close: @escaping @MainActor () -> Void = {}
    ) -> OnboardingTour {
        OnboardingTour.recording(
            in: hooks.intentStore,
            startingAt: page,
            state: { [weak self] in self?.onboardingState ?? OnboardingState() },
            actions: onboardingActions,
            close: close
        )
    }

    /// What the tour's pages show, read from the app as it is right now.
    var onboardingState: OnboardingState {
        let profile = activeAppearanceProfile
        let display = nook.displayPreferences(for: profile)
        let keys = agentHotkeys.settings
        let keyName: (UInt16) -> String? = { [agentHotkeys] keyCode in
            // The controller's own text ends in the key's name on the
            // keyboard layout in use.
            agentHotkeys.displayText(for: AgentHotkeyCombo(keyCode: keyCode, modifiers: []))
        }
        return OnboardingState(
            openTrigger: islandOpenTrigger,
            isIslandOpen: notchStatus == .opened,
            agents: [
                .claudeCode: agentStatus(installed: claudeHooksInstalled, busy: isClaudeHookSetupBusy),
                .codex: agentStatus(installed: codexHooksInstalled, busy: isCodexSetupBusy),
                .cursor: agentStatus(installed: cursorHooksInstalled, busy: isCursorHookSetupBusy),
                .gemini: agentStatus(installed: geminiHooksInstalled, busy: isGeminiHookSetupBusy),
                // OpenCode loads a plugin and needs no hooks helper.
                .openCode: OnboardingAgentStatus(
                    isConnected: openCodePluginInstalled,
                    isBusy: isOpenCodeSetupBusy,
                    canConnect: true
                ),
            ],
            hasAgentOutsideTour: qoderHooksInstalled || qwenCodeHooksInstalled || factoryHooksInstalled
                || codebuddyHooksInstalled || kimiHooksInstalled || grokHooksInstalled
                || piExtensionInstalled || ohMyPiExtensionInstalled,
            enabledWidgets: Set(nook.enabledWidgets),
            appliedTemplate: appliedTemplateID(for: profile),
            glowStyle: display.haloStyle,
            glowThemeID: display.haloColors.usesSingleColor
                ? nil
                : IslandHaloTheme.matching(display.haloColors.palette)?.id,
            openedLook: display.openedLook,
            displayProfile: profile,
            approveKeys: keys.isApproveEnabled
                ? OnboardingShortcutWords.caps(for: keys.approve, keyName: keyName)
                : nil,
            denyKeys: keys.isDenyEnabled
                ? OnboardingShortcutWords.caps(for: keys.deny, keyName: keyName)
                : nil
        )
    }

    /// The same rule the Setup tab uses: these agents need the hooks
    /// helper, which is found a moment after launch.
    private func agentStatus(installed: Bool, busy: Bool) -> OnboardingAgentStatus {
        OnboardingAgentStatus(isConnected: installed, isBusy: busy, canConnect: hooksBinaryURL != nil)
    }

    /// What the tour's buttons do. Each runs from a click and from nothing
    /// else, and none of them asks macOS for a permission.
    private var onboardingActions: OnboardingActions {
        OnboardingActions(
            setOpenTrigger: { [weak self] in self?.islandOpenTrigger = $0 },
            connect: { [weak self] in self?.connect($0) },
            showAllAgents: { [weak self] in self?.showSetupSettings() },
            setWidget: { [weak self] kind, isEnabled in self?.nook.setWidget(kind, enabled: isEnabled) },
            applyTemplate: { [weak self] template in
                guard let self else { return }
                applyTemplate(template, for: activeAppearanceProfile)
            },
            setGlowStyle: { [weak self] style in
                guard let self else { return }
                nook.updateDisplayPreferences(for: activeAppearanceProfile) { $0.haloStyle = style }
            },
            // The same write the theme cards in Settings make (D31).
            setGlowTheme: { [weak self] theme in
                guard let self else { return }
                nook.updateDisplayPreferences(for: activeAppearanceProfile) {
                    $0.haloColors.palette = theme.palette
                    $0.haloColors.usesSingleColor = false
                }
            },
            setOpenedWidth: { [weak self] width in
                guard let self else { return }
                nook.updateDisplayPreferences(for: activeAppearanceProfile) { $0.openedLook.width = width }
            },
            setOpenedCorners: { [weak self] corners in
                guard let self else { return }
                nook.updateDisplayPreferences(for: activeAppearanceProfile) { $0.openedLook.corners = corners }
            }
        )
    }

    /// Installs through the same calls the Setup tab's buttons make.
    private func connect(_ agent: OnboardingAgent) {
        switch agent {
        case .claudeCode: installClaudeHooks()
        case .codex: installCodexHooks()
        case .cursor: installCursorHooks()
        case .gemini: installGeminiHooks()
        case .openCode: installOpenCodePlugin()
        }
    }
}
