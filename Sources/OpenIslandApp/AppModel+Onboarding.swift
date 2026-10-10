import AppKit
import AVFoundation
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
            lang: lang,
            islandFootprint: { [weak self] in self?.overlay.openedIslandFootprint() }
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

    /// Opens Settings on the Nook tab at its to-do section, where a task
    /// source is picked and its token is pasted.
    func showNookTodoSettings() {
        showSettings()
        NotificationCenter.default.post(name: .openIslandSelectNookTodo, object: nil)
    }

    /// A tour wired to this model. Ending it, by its last button, by Skip
    /// or by closing its window, records that the tour was seen and puts
    /// the window away.
    func makeWelcomeTour(
        startingAt page: OnboardingPage = .welcome,
        close: @escaping @MainActor () -> Void = {}
    ) -> OnboardingTour {
        let own = OnboardingOwnLayouts()
        return OnboardingTour.recording(
            in: hooks.intentStore,
            startingAt: page,
            state: { [weak self] in self?.onboardingState(keeping: own) ?? OnboardingState() },
            actions: onboardingActions(keeping: own),
            close: close
        )
    }

    /// The tour's state with the layout it holds to go back to, which the
    /// "Keep mine" card draws.
    private func onboardingState(keeping own: OnboardingOwnLayouts) -> OnboardingState {
        var state = onboardingState
        state.ownPlacements = own.setups[activeAppearanceProfile]?
            .nook.placements(enabled: Array(nook.enabledWidgets))
        return state
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
            agentsEnabled: agentsEnabled,
            swipeEnabled: swipeGesturesEnabled,
            swipeCount: swipeActionCount,
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
            closedSide: OnboardingClosedSide.reading(
                own: appearancePreferences(for: profile).rightSlot,
                nook: display.rightSlot,
                agentsEnabled: agentsEnabled
            ),
            closedLeft: OnboardingClosedLeft.reading(display.leftSlot, agentsEnabled: agentsEnabled),
            closedMusic: OnboardingClosedMusic(display),
            enabledWidgets: Set(nook.enabledWidgets),
            nookPlacements: nook.widgetPlacements(for: profile),
            calendarStyle: display.calendarStyle,
            todoSource: nook.todo.selectedKind,
            isTodoSourceReady: nook.todo.source(reminders: nook.reminders).connection == .ready,
            todoSetup: todoConnector.setup(),
            notesDestination: nook.notes.destination,
            notesFilePath: (nook.notes.fileURL.path as NSString).abbreviatingWithTildeInPath,
            notesSavedCount: nook.notes.savedCount,
            weather: OnboardingWeatherSetup(reading: nook.weather),
            appliedTemplate: appliedTemplateID(for: profile),
            glowStyle: display.haloStyle,
            glowPalette: display.haloColors.palette,
            glowThemeID: display.haloColors.usesSingleColor
                ? nil
                : IslandHaloTheme.matching(display.haloColors.palette)?.id,
            openedLook: display.openedLook,
            displayProfile: profile,
            isEditingWidgets: nook.isEditingLayout,
            features: onboardingFeatureReading,
            approveKeys: keys.isApproveEnabled
                ? OnboardingShortcutWords.caps(for: keys.approve, keyName: keyName)
                : nil,
            denyKeys: keys.isDenyEnabled
                ? OnboardingShortcutWords.caps(for: keys.deny, keyName: keyName)
                : nil
        )
    }

    /// A pick of what the closed island shows brings back what a swipe hid
    /// (D46). A sideways swipe tried on the opening page would otherwise
    /// leave the real island blank while the picks are made.
    private func showClosedContentForPick() {
        guard nook.closedContentHiddenBySwipe else { return }
        nook.closedContentHiddenBySwipe = false
    }

    /// The same rule the Setup tab uses: these agents need the hooks
    /// helper, which is found a moment after launch.
    private func agentStatus(installed: Bool, busy: Bool) -> OnboardingAgentStatus {
        OnboardingAgentStatus(isConnected: installed, isBusy: busy, canConnect: hooksBinaryURL != nil)
    }

    /// What the tour's buttons do. Each runs from a click and from nothing
    /// else. Only two can raise a macOS prompt, the mirror's camera and the
    /// calendar's access, each from a button whose note names the prompt
    /// first (D47). `own` holds, for one run of the tour, the layout a
    /// display had before a template.
    private func onboardingActions(keeping own: OnboardingOwnLayouts) -> OnboardingActions {
        OnboardingActions(
            setAgentsEnabled: { [weak self] in self?.agentsEnabled = $0 },
            setOpenTrigger: { [weak self] in self?.islandOpenTrigger = $0 },
            setSwipeEnabled: { [weak self] in self?.swipeGesturesEnabled = $0 },
            setClosedSide: { [weak self] in
                self?.showClosedContentForPick()
                self?.chooseClosedSide($0)
            },
            setClosedLeft: { [weak self] in
                self?.showClosedContentForPick()
                self?.chooseClosedLeft($0)
            },
            setClosedMusic: { [weak self] in
                self?.showClosedContentForPick()
                self?.chooseClosedMusic($0)
            },
            connect: { [weak self] in self?.connect($0) },
            showAllAgents: { [weak self] in self?.showSetupSettings() },
            setWidget: { [weak self] kind, isEnabled in self?.setTourWidget(kind, enabled: isEnabled) },
            // The preference the Source picker in Settings writes. Settings
            // also asks macOS for Reminders at that moment. The tour does
            // not: there the prompt waits until the widget is first shown.
            setTodoSource: { [weak self] in self?.nook.todo.selectedKind = $0 },
            openTodoSetupPage: { kind in
                if let url = NookTodoSetupLink.url(for: kind) { NSWorkspace.shared.open(url) }
            },
            showTodoSettings: { [weak self] in self?.showNookTodoSettings() },
            // The token goes from the page's field to the service and from
            // there to the Keychain. Nothing here keeps it.
            connectTodo: { [weak self] token in
                guard let connector = self?.todoConnector else { return }
                Task { await connector.connect(token: token) }
            },
            checkTodoAgain: { [weak self] in
                guard let connector = self?.todoConnector else { return }
                Task { await connector.checkAgain() }
            },
            chooseTodo: { [weak self] id in
                guard let connector = self?.todoConnector else { return }
                Task { await connector.choose(id) }
            },
            // Runs from the page's button, which says macOS will ask.
            allowReminders: { [weak self] in
                guard let connector = self?.todoConnector else { return }
                Task { await connector.allowReminders() }
            },
            openRemindersSettings: { [weak self] in self?.nook.reminders.openSystemSettings() },
            setNotesDestination: { [weak self] in self?.nook.notes.setDestination($0) },
            chooseNotesFolder: { [weak self] in self?.chooseNotesFolderForTour() },
            showNotes: { [weak self] in self?.showTourNotes() },
            // The calls NookWeatherSettings makes. The search sends the typed
            // city to Open-Meteo, from the page's button.
            searchWeather: { [weak self] text in
                guard let self else { return }
                nook.weather.search(text, language: lang.language.resolvedCode)
            },
            chooseWeatherPlace: { [weak self] in self?.nook.weather.setPlace($0) },
            setWeatherUnit: { [weak self] in self?.nook.weather.unit = $0 },
            applyTemplate: { [weak self] template in
                guard let self else { return }
                let profile = activeAppearanceProfile
                // Only a layout that is on no template is the user's own.
                if own.setups[profile] == nil, appliedTemplateID(for: profile) == nil {
                    own.setups[profile] = personalizationSetup(for: profile)
                }
                applyTemplate(template, for: profile)
            },
            keepOwnLayout: { [weak self] in
                guard let self else { return }
                let profile = activeAppearanceProfile
                guard let setup = own.setups[profile] else { return }
                restoreSetup(setup, for: profile)
                // Let go of it: a template picked later holds the layout
                // as it is then.
                own.setups[profile] = nil
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
            },
            // The one door to the island's hold (D44).
            holdIsland: { [weak self] in self?.setTourHoldsIslandOpen($0) },
            restorePlacements: { [weak self] placements in
                guard let self else { return }
                restoreTourPlacements(placements, for: activeAppearanceProfile)
            },
            // The tour's doors into widget editing: what a long press does,
            // and the ring the grid draws on the widget it names.
            setEditingWidgets: { [weak self] in self?.nook.isEditingLayout = $0 },
            outlineWidget: { [weak self] in self?.nook.tourOutlinedWidget = $0 },
            // The features page's buttons: each makes the real widget do the
            // thing, through the call the widget's own button makes (D47).
            setMirror: { [weak self] isOn in
                guard let self else { return }
                // The link's own switch: it shows the widgets page first, and turns down
                // a mirror with no tile or an approval on screen.
                _ = withMotion(Motion.reflow) { setMirror(isOn) }
            },
            setRingLight: { [weak self] in self?.nook.isRingLightOn = $0 },
            openPhotoBooth: { [weak self] in self?.nook.photoBooth.start() },
            cancelPhotoBooth: { [weak self] in self?.nook.photoBooth.cancel() },
            openCameraSettings: { NookMirrorController.openCameraSettings() },
            playOrPause: { [weak self] in self?.nook.media.togglePlayPause() },
            nextTrack: { [weak self] in self?.nook.media.nextTrack() },
            startTimer: { [weak self] in self?.nook.timer.start(length: $0) },
            stopTimer: { [weak self] in self?.nook.timer.reset() },
            copySampleLine: { [weak self] text in self?.nook.tray.clipboard.copy(text: text) ?? false },
            // The click that raises the Calendar prompt, after the note that
            // names it. `NookAccessTiming` allows it for a widget that is on.
            showCalendar: { [weak self] in
                guard let nook = self?.nook else { return }
                Task { await nook.askForAccess(for: .calendar, at: .requested) }
            },
            // The write the calendar look picker in Settings makes, for the
            // display the island is on.
            setCalendarStyle: { [weak self] style in
                guard let self else { return }
                nook.updateDisplayPreferences(for: activeAppearanceProfile) { $0.calendarStyle = style }
            }
        )
    }

    /// What the features page's buttons read: the mirror, the booth, the
    /// music, the timer, the clipboard list and the calendar's access.
    private var onboardingFeatureReading: OnboardingFeatureReading {
        let sample = NookClipboardContent.text(lang.t(OnboardingFeatureSample.clipboardKey))
        let calendar: OnboardingCalendarAccess = switch nook.calendar.authorization {
        case .fullAccess: .allowed
        case .notDetermined: .undecided
        default: .refused
        }
        return OnboardingFeatureReading(
            isMirrorOn: nook.isMirrorOn,
            isRingLightOn: nook.isRingLightOn,
            camera: onboardingCameraAccess,
            canStartBooth: nook.photoBooth.canStart,
            isBoothShowing: nook.photoBooth.isShowing,
            hasBoothStrip: nook.photoBooth.result != nil,
            music: nook.media.state.map {
                OnboardingMusicReading(isPlaying: $0.isPlaying, track: $0.itemIdentifier ?? $0.title)
            },
            isTimerActive: nook.timer.isActive,
            // A pomodoro round has a length too, and is not the tour's minute.
            timerOneOff: nook.timer.pomodoro == nil ? nook.timer.oneOffTotal : nil,
            isClipboardOn: nook.tray.clipboard.isEnabled,
            hasSampleLine: nook.tray.clipboard.history.entries.contains { $0.content == sample },
            calendar: calendar
        )
    }

    /// The camera permission as macOS has it right now. This only reads: the
    /// prompt is raised by the mirror's button and nothing else.
    private var onboardingCameraAccess: OnboardingCameraAccess {
        // The demo mode (D51) never looks at the camera or its list.
        if DemoMode.isActive { return .unavailable }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        // The device list is looked up only when the answer is not a refusal.
        let hasCamera = status == .denied || status == .restricted || NookMirrorDevices.selectedDevice() != nil
        return OnboardingCameraAccess(status: status, hasCamera: hasCamera)
    }

    /// The to-dos page's door to the task services.
    private var todoConnector: OnboardingTodoConnector {
        OnboardingTodoConnector(hub: nook.todo, reminders: nook.reminders, lang: lang)
    }

    /// Opens the system folder chooser and keeps the notes file in the
    /// folder picked, under its usual name. The panel is the app's own, like
    /// the one in Settings, and not part of the page.
    private func chooseNotesFolderForTour() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = nook.notes.fileURL.deletingLastPathComponent()
        panel.prompt = lang.t("onboarding.notes.file.panelPrompt")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        nook.notes.setFolder(folder)
    }

    /// The notes file in Finder, or the Notes app.
    private func showTourNotes() {
        switch nook.notes.destination {
        case .file:
            NSWorkspace.shared.activateFileViewerSelecting([nook.notes.fileURL])
        case .appleNotes:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Notes.app"))
        }
    }

    /// Puts the order and the sizes of the widgets on a display's page back
    /// as they were. The widgets stay as they are; only where they sit and
    /// how large they are comes back.
    func restoreTourPlacements(_ placements: [NookWidgetPlacement], for profile: IslandAppearanceDisplayProfile) {
        nook.updateDisplayPreferences(for: profile) { preferences in
            let listed = placements.map(\.kind)
            preferences.widgetOrder = listed + preferences.normalizedWidgetOrder.filter { !listed.contains($0) }
            for placement in placements {
                // Medium is the default and is stored as no entry.
                preferences.widgetSizes[placement.kind] = placement.size == .medium ? nil : placement.size
            }
        }
    }

    /// A widget's switch in the tour. On is the Nook tab's switch plus
    /// what adding a widget in Personalization does for the display in
    /// use: a widget a layout left off this display comes back onto it.
    /// Off is the Nook tab's switch.
    func setTourWidget(_ kind: NookWidgetKind, enabled: Bool) {
        nook.setWidget(kind, enabled: enabled)
        guard enabled else { return }
        nook.updateDisplayPreferences(for: activeAppearanceProfile) { $0.hiddenWidgets.remove(kind) }
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

/// The layouts one run of the tour can put back: what each display was on
/// before a template was picked over a layout of the user's own.
@MainActor
final class OnboardingOwnLayouts {
    var setups: [IslandAppearanceDisplayProfile: PersonalizationSetup] = [:]
}

extension OnboardingCameraAccess {
    /// What the page needs of macOS's camera answer. A refusal wins over a
    /// missing camera, because it is the one the user can fix. Plain values
    /// in, which keeps a test from touching the camera.
    init(status: AVAuthorizationStatus, hasCamera: Bool) {
        switch status {
        case .denied, .restricted: self = .refused
        case .authorized: self = hasCamera ? .allowed : .unavailable
        case .notDetermined: self = hasCamera ? .undecided : .unavailable
        @unknown default: self = .refused
        }
    }
}
