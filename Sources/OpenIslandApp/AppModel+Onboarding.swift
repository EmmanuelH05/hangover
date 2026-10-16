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
            accent: { [weak self] in self?.accentTint ?? .standard },
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

    /// Opens Settings on a tab: the section a Good to know page's button is
    /// about.
    func showSettings(tab: SettingsTab) {
        showSettings()
        NotificationCenter.default.post(
            name: .openIslandSelectSettingsTab,
            object: nil,
            userInfo: [SettingsTab.userInfoKey: tab.rawValue]
        )
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
            notesSaveTo: nook.notes.saveTo,
            notesFolderPath: (nook.notes.folderURL.path as NSString).abbreviatingWithTildeInPath,
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
                : nil,
            beat: OnboardingBeatReading(
                display: display,
                cannotHear: beat.problem == .cannotHear,
                policy: SystemMotionMonitor.shared.policy,
                reduceMotion: SystemMotionMonitor.shared.reduceMotion,
                dimsFlashingLights: SystemFlashingLightsSetting.shared.dimsFlashingLights
            ),
            more: onboardingMoreReading
        )
    }

    /// What the Good to know pages read: each switch as Settings reads it.
    var onboardingMoreReading: OnboardingMoreReading {
        var on: Set<OnboardingMoreSwitch> = []
        func note(_ item: OnboardingMoreSwitch, _ isOn: Bool) { if isOn { on.insert(item) } }
        note(.powerNotices, nook.power.isEnabled)
        note(.volumeNotice, nook.volume.isNoticeEnabled)
        note(.volumeKeys, nook.volume.keys.status != .off)
        note(.usageMeter, islandUsageDisplay == .compact)
        note(.focusQuiet, nook.focusSuppressesCompletions)
        note(.meetingQuiet, nook.meetingSuppressesCompletions)
        note(.mute, isSoundMuted)
        note(.links, allowsLinksFromOtherApps)
        note(.launchAtLogin, launchAtLoginEnabled)
        note(.dockIcon, showDockIcon)
        note(.autoUpdates, updateChecker.installsAutomatically)
        note(.mirrorWidget, isOnThePage(.mirror))
        note(.weatherWidget, isOnThePage(.weather))
        let keys = nook.volume.keys
        let access: OnboardingKeysAccess = switch keys.status {
        case .off: .off
        case .waitingForAccess: .waiting
        case .active: .active
        case .unavailable: .unavailable
        }
        return OnboardingMoreReading(
            on: on,
            keys: access,
            keysAccessWasMissingAtLaunch: keys.accessWasMissingAtLaunch,
            canCheckForUpdates: updateChecker.canCheckForUpdates
        )
    }

    /// The Good to know switches. Each writes what the switch of the same
    /// name in Settings writes: the model's own setting, or the key the
    /// Settings view stores through `@AppStorage`.
    func setTourMore(_ item: OnboardingMoreSwitch, enabled: Bool) {
        switch item {
        case .powerNotices: nook.power.setEnabled(enabled)
        case .volumeNotice: nook.volume.setNoticeEnabled(enabled)
        case .volumeKeys: nook.volume.keys.setEnabled(enabled)
        case .usageMeter: islandUsageDisplay = enabled ? .compact : .hidden
        case .focusQuiet: nook.focusSuppressesCompletions = enabled
        case .meetingQuiet: nook.meetingSuppressesCompletions = enabled
        case .mute: isSoundMuted = enabled
        case .links: allowsLinksFromOtherApps = enabled
        case .launchAtLogin: launchAtLoginEnabled = enabled
        case .dockIcon: showDockIcon = enabled
        // The widgets switch on by the tour's own widget door, which switches the
        // widget and nothing else: the camera stays off until its button is pressed.
        case .mirrorWidget: setTourWidget(.mirror, enabled: enabled)
        case .weatherWidget: setTourWidget(.weather, enabled: enabled)
        case .autoUpdates:
            // Settings dims this switch where the updater does not run.
            guard updateChecker.canCheckForUpdates else { return }
            updateChecker.installsAutomatically = enabled
        }
    }

    /// The button beside "Waiting for Accessibility access", as Settings has it.
    func requestTourKeysAccess() {
        nook.volume.keys.requestAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            openSystemURL(url)
        }
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
            setWidget: { [weak self] kind, isEnabled in
                self?.setTourWidget(kind, enabled: isEnabled)
                // Link to MP3 looks for its two programs once more as it comes
                // on, which keeps the step's note about a missing one current
                // for a user who installed them since the app started.
                if kind == .linkAudio, isEnabled, self?.nook.offersLinkAudio == true { self?.nook.linkAudio.refreshTools() }
            },
            // The preference the Source picker in Settings writes. Settings
            // also asks macOS for Reminders at that moment. The tour does
            // not: there the prompt waits until the widget is first shown.
            setTodoSource: { [weak self] in self?.nook.todo.selectedKind = $0 },
            openTodoSetupPage: { kind in
                if let url = NookTodoSetupLink.url(for: kind) { NSWorkspace.shared.open(url) }
            },
            showTodoSettings: { [weak self] in self?.showNookTodoSettings() },
            // The token goes from the page's field to the service and from
            // there to its file. Nothing here keeps it.
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
            setNotesSaveTo: { [weak self] in self?.nook.notes.setSaveTo($0) },
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
            // The writes Settings makes for the lights (D56). The switch is the
            // one thing in the tour that starts the app listening to the Mac's
            // sound, and only when the user flips it.
            setBeatPulse: { [weak self] isOn in
                self?.setTourBeatPulse(isOn)
            },

            setBeatLook: { [weak self] look in
                guard let self else { return }
                nook.updateDisplayPreferences(for: activeAppearanceProfile) { $0.haloBeatLook = look }
            },
            setMore: { [weak self] item, isOn in self?.setTourMore(item, enabled: isOn) },
            requestKeysAccess: { [weak self] in self?.requestTourKeysAccess() },
            openSettings: { [weak self] tab in self?.showSettings(tab: tab) },
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
            },
            // The kit's pick door, from the shortcut: it leaves the island as
            // it is, which the tour holds open. The loupe is the system's.
            pickDesignColor: { [weak self] in _ = self?.nook.design.pickColor(from: .shortcut) }
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
            isRecordBusy: nook.record.phase.isBusy,
            isMirrorOn: nook.isMirrorOn,
            isRingLightOn: nook.isRingLightOn,
            camera: onboardingCameraAccess,
            canStartBooth: nook.photoBooth.canStart,
            isBoothShowing: nook.photoBooth.isShowing,
            hasBoothStrip: nook.photoBooth.result != nil,
            music: nook.media.state.map(OnboardingMusicReading.init),
            isTimerActive: nook.timer.isActive,
            // A pomodoro round has a length too, and is not the tour's minute.
            timerOneOff: nook.timer.pomodoro == nil ? nook.timer.oneOffTotal : nil,
            isClipboardOn: nook.tray.clipboard.isEnabled,
            hasSampleLine: nook.tray.clipboard.history.entries.contains { $0.content == sample },
            calendar: calendar,
            design: OnboardingDesignReading(
                isOn: isOnThePage(.design) && nook.design.isLive,
                isReady: nook.design.isLive && nook.design.palettes.isLoaded && !nook.design.isSampling,
                isSampling: nook.design.isSampling,
                lastPickAt: nook.design.palettes.recents.first?.pickedAt
            ),
            // Link to MP3 (D59): only whether it is on, and the widget's own
            // line about a missing program. The tour starts no download.
            linkAudio: OnboardingLinkAudioReading(
                isOn: isOnThePage(.linkAudio),
                missingNoteKey: nook.linkAudio.toolStatus.missingLineKey
            )
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

    /// Opens the system folder chooser and keeps the notes in the
    /// folder picked. The panel is the app's own, like
    /// the one in Settings, and not part of the page.
    private func chooseNotesFolderForTour() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = NookNoteLocations.pickerStart(
            home: FileManager.default.homeDirectoryForCurrentUser, current: nook.notes.folderURL
        )
        panel.prompt = lang.t("onboarding.notes.folder.panelPrompt")
        // The chooser opens under the island the tour holds open (D52).
        nook.systemPromptBegan()
        let answer = panel.runModal()
        nook.systemPromptEnded()
        guard answer == .OK, let folder = panel.url else { return }
        nook.notes.setFolder(folder)
    }

    /// The notes folder in Finder, or the Notes app.
    private func showTourNotes() {
        switch nook.notes.saveTo {
        case .folder, .both:
            // A folder never made is made, so there is something to show; one
            // that is gone is not made again silently (N12).
            nook.notes.revealFolder()
        case .appleNotes:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Notes.app"))
        }
    }

    /// Puts the order and the sizes of the widgets on a display's page back
    /// as they were. The widgets stay as they are; only where they sit and
    /// how large they are comes back.
    func restoreTourPlacements(_ placements: [NookWidgetPlacement], for profile: IslandAppearanceDisplayProfile) {
        nook.updateDisplayPreferences(for: profile) { preferences in
            // The listed widgets go first, in the order the tour listed them.
            preferences.widgetOrder = NookWidgetKind.orderRestoring(
                placements.map(\.kind),
                in: preferences.normalizedWidgetOrder
            )
            for placement in placements {
                // Medium is the default and is stored as no entry.
                preferences.widgetSizes[placement.kind] = placement.size == .medium ? nil : placement.size
            }
        }
    }

    /// True while a widget is on the page of the display in use: switched on
    /// and not hidden there. A layout hides what it does not list, which
    /// leaves the switch on and the card gone.
    private func isOnThePage(_ kind: NookWidgetKind) -> Bool {
        nook.widgetPlacements(for: activeAppearanceProfile).contains { $0.kind == kind }
    }

    /// A widget's switch in the tour. On is the Nook tab's switch plus
    /// what adding a widget in Personalization does for the display in
    /// use: a widget a layout left off this display comes back onto it.
    /// Off is the Nook tab's switch. The design kit and Link to MP3 go
    /// through Settings' own door, `setWidgetFromSettings`, which also tells
    /// each of them when it is switched on or off (`widgetSwitched`).
    /// The lights' switch. Switching it on needs the glow and the closed
    /// island's music, which the strength cards and the closed page set: with
    /// either missing nothing is written. Glow with music is the one thing the
    /// switch sets itself, because the pulse follows the music glow and the
    /// card says that. Switching off is always allowed.
    func setTourBeatPulse(_ isOn: Bool) {
        let profile = activeAppearanceProfile
        let display = nook.displayPreferences(for: profile)
        if isOn, display.haloStyle == .off || display.mediaStyle == .off { return }
        nook.updateDisplayPreferences(for: profile) {
            $0.haloPulsesWithBeat = isOn
            if isOn { $0.haloFollowsMusic = true }
        }
    }

    func setTourWidget(_ kind: NookWidgetKind, enabled: Bool) {
        if NookWidgetKind.tools.contains(kind) {
            nook.setWidgetFromSettings(kind, enabled: enabled)
            return
        }
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
