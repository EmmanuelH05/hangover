import AppKit
import Foundation
import Observation
import OpenIslandCore
import SwiftUI

extension Notification.Name {
    /// Posted by `AppModel.showSetupSettings()` to ask `SettingsView` to
    /// switch to the Setup tab. Lets the welcome tour deliver the user to
    /// the right place without `SettingsView`'s `@State` having to leak
    /// into `AppModel`.
    static let openIslandSelectSetupTab = Notification.Name("openIslandSelectSetupTab")
    static let openIslandSelectNookTodo = Notification.Name("openIslandSelectNookTodo")
}

@MainActor
@Observable
final class AppModel {
    private static let soundMutedDefaultsKey = "overlay.sound.muted"
    private static let showDockIconDefaultsKey = "app.showDockIcon"
    private static let hapticFeedbackEnabledDefaultsKey = "app.hapticFeedbackEnabled"
    /// When true, click-outside does not dismiss the notch while any session
    /// is waiting for approval or an answer (#547).
    private static let keepNotchOpenUntilDecisionDefaultsKey = "app.keepNotchOpenUntilDecision"
    static let islandOpenTriggerDefaultsKey = "app.islandOpenTrigger"
    static let allowsLinksFromOtherAppsDefaultsKey = "app.allowsLinksFromOtherApps"
    private static let islandRightSlotDefaultsKey = "appearance.island.v6.rightSlot"
    private static let islandCenterLabelDefaultsKey = "appearance.island.v6.centerLabel"
    static let showCodexUsageDefaultsKey = "app.showCodexUsage"
    private static let completionReplyEnabledDefaultsKey = "feature.completionReply.enabled"
    private static let suppressFrontmostNotificationsDefaultsKey = "app.suppressFrontmostNotifications"
    private static let legacyIslandSessionStateIndicatorDefaultsKey = "appearance.island.v8.stateIndicator"
    private static let legacyIslandSessionGroupDefaultsKey = "appearance.island.v8.sessionGroup"
    private static let legacyIslandSessionSortDefaultsKey = "appearance.island.v8.sessionSort"
    private static let legacyCompletedStaleThresholdDefaultsKey = "appearance.island.v8.completedStaleThreshold"
    private static let appearanceProfileSettingsDefaultsKey = "appearance.island.v8.settingsProfile"

    private static let syntheticClaudeSessionPrefix = "claude-process:"
    private static let liveSessionStalenessWindow: TimeInterval = 15 * 60
    private static let jumpOverlayDismissLeadTime: Duration = .milliseconds(20)
    private static let agentsGridObservedSequenceLimit = 512
    static let hoverOpenDelay: TimeInterval = 0.15

    struct AcceptanceStep: Identifiable {
        let id: String
        let title: String
        let detail: String
        let isComplete: Bool
    }

    let lang = LanguageManager.shared

    var state = SessionState() {
        didSet {
            _cachedSessionBuckets = nil
            pruneAgentsGridObservationTicketsIfNeeded()
            bridgeServer.updateStateSnapshot(state)
            agentToolsStateDidChange()
        }
    }
    @ObservationIgnored private var _cachedSessionBuckets: (primary: [AgentSession], overflow: [AgentSession])?

    /// Monotonic ticket assigned the first time a session ID shows up in the
    /// closed-island's right-slot surfaced set. Drives the grid's display
    /// order: newly-surfaced sessions always land at the end, and a session
    /// that briefly leaves (e.g. attachment flip) keeps its old slot when it
    /// returns. Persists for the process lifetime; session IDs are UUIDs so
    /// accumulation over time is bounded in practice.
    @ObservationIgnored private var _agentsGridObservedSequence: [String: Int] = [:]
    @ObservationIgnored private var _agentsGridNextTicket: Int = 0
    var selectedSessionID: String?
    let hooks: HookInstallationCoordinator
    let overlay = OverlayUICoordinator()
    /// Completion flashes for the status halo.
    let halo = IslandHaloController()
    let discovery = SessionDiscoveryCoordinator()
    let monitoring = ProcessMonitoringCoordinator()
    let codexAppServer = CodexAppServerCoordinator()
    let updateChecker = UpdateChecker()
    let nook: NookModel

    /// Approve and deny from the keyboard, replies being typed, and what
    /// each session did since its last prompt. Glue in
    /// `AppModel+AgentTools`.
    let agentHotkeys: AgentHotkeyController
    var agentReplies = AgentReplyDraftStore()
    var agentTurns = AgentTurnLedger()
    var agentApprovals = AgentApprovalTracker()
    /// The session whose reply field is being typed in.
    @ObservationIgnored
    var agentReplyEditingSessionID: String?

    var notchStatus: NotchStatus {
        get { overlay.notchStatus }
        set { overlay.notchStatus = newValue }
    }
    var notchOpenReason: NotchOpenReason? {
        get { overlay.notchOpenReason }
        set { overlay.notchOpenReason = newValue }
    }
    var islandSurface: IslandSurface {
        get { overlay.islandSurface }
        set { overlay.islandSurface = newValue }
    }
    var isOverlayVisible: Bool { overlay.isOverlayVisible }
    var isOverlayCloseTransitionPending: Bool { overlay.isCloseTransitionPending }
    var isCodexSetupBusy: Bool { hooks.isCodexSetupBusy }
    var isClaudeHookSetupBusy: Bool { hooks.isClaudeHookSetupBusy }
    var isClaudeUsageSetupBusy: Bool { hooks.isClaudeUsageSetupBusy }
    var codexHookStatus: CodexHookInstallationStatus? { hooks.codexHookStatus }
    var claudeHookStatus: ClaudeHookInstallationStatus? { hooks.claudeHookStatus }
    var claudeStatusLineStatus: ClaudeStatusLineInstallationStatus? { hooks.claudeStatusLineStatus }
    var claudeUsageSnapshot: ClaudeUsageSnapshot? { hooks.claudeUsageSnapshot }
    var codexUsageSnapshot: CodexUsageSnapshot? { hooks.codexUsageSnapshot }
    var hooksBinaryURL: URL? { hooks.hooksBinaryURL }
    var codexHooksInstalled: Bool { hooks.codexHooksInstalled }
    var claudeHooksInstalled: Bool { hooks.claudeHooksInstalled }
    var qoderHooksInstalled: Bool { hooks.qoderHooksInstalled }
    var qwenCodeHooksInstalled: Bool { hooks.qwenCodeHooksInstalled }
    var factoryHooksInstalled: Bool { hooks.factoryHooksInstalled }
    var codebuddyHooksInstalled: Bool { hooks.codebuddyHooksInstalled }
    var qoderHookStatus: ClaudeHookInstallationStatus? { hooks.qoderHookStatus }
    var qwenCodeHookStatus: ClaudeHookInstallationStatus? { hooks.qwenCodeHookStatus }
    var factoryHookStatus: ClaudeHookInstallationStatus? { hooks.factoryHookStatus }
    var codebuddyHookStatus: ClaudeHookInstallationStatus? { hooks.codebuddyHookStatus }
    var isQoderHookSetupBusy: Bool { hooks.isQoderHookSetupBusy }
    var isQwenCodeHookSetupBusy: Bool { hooks.isQwenCodeHookSetupBusy }
    var isFactoryHookSetupBusy: Bool { hooks.isFactoryHookSetupBusy }
    var isCodebuddyHookSetupBusy: Bool { hooks.isCodebuddyHookSetupBusy }
    var openCodePluginInstalled: Bool { hooks.openCodePluginInstalled }
    var claudeUsageInstalled: Bool { hooks.claudeUsageInstalled }
    var claudeHookStatusTitle: String { hooks.claudeHookStatusTitle }
    var claudeHookStatusSummary: String { hooks.claudeHookStatusSummary }
    var claudeUsageStatusTitle: String { hooks.claudeUsageStatusTitle }
    var claudeUsageStatusSummary: String { hooks.claudeUsageStatusSummary }
    var claudeUsageSummaryText: String? { hooks.claudeUsageSummaryText }
    var codexUsageStatusTitle: String { hooks.codexUsageStatusTitle }
    var codexUsageStatusSummary: String { hooks.codexUsageStatusSummary }
    var codexUsageSummaryText: String? { hooks.codexUsageSummaryText }
    var openCodePluginStatus: OpenCodePluginInstallationStatus? { hooks.openCodePluginStatus }
    var isOpenCodeSetupBusy: Bool { hooks.isOpenCodeSetupBusy }
    var openCodePluginStatusTitle: String { hooks.openCodePluginStatusTitle }
    var openCodePluginStatusSummary: String { hooks.openCodePluginStatusSummary }
    var healthReports: [HookHealthReport] { hooks.healthReports }
    var cursorHooksInstalled: Bool { hooks.cursorHooksInstalled }
    var isCursorHookSetupBusy: Bool { hooks.isCursorHookSetupBusy }
    var cursorHookStatus: CursorHookInstallationStatus? { hooks.cursorHookStatus }
    var cursorHookStatusTitle: String { hooks.cursorHookStatusTitle }
    var cursorHookStatusSummary: String { hooks.cursorHookStatusSummary }
    var geminiHooksInstalled: Bool { hooks.geminiHooksInstalled }
    var isGeminiHookSetupBusy: Bool { hooks.isGeminiHookSetupBusy }
    var geminiHookStatus: GeminiHookInstallationStatus? { hooks.geminiHookStatus }
    var geminiHookStatusTitle: String { hooks.geminiHookStatusTitle }
    var geminiHookStatusSummary: String { hooks.geminiHookStatusSummary }
    var kimiHooksInstalled: Bool { hooks.kimiHooksInstalled }
    var isKimiHookSetupBusy: Bool { hooks.isKimiHookSetupBusy }
    var kimiHookStatus: KimiHookInstallationStatus? { hooks.kimiHookStatus }
    var kimiHookStatusTitle: String { hooks.kimiHookStatusTitle }
    var kimiHookStatusSummary: String { hooks.kimiHookStatusSummary }
    var grokHooksInstalled: Bool { hooks.grokHooksInstalled }
    var isGrokHookSetupBusy: Bool { hooks.isGrokHookSetupBusy }
    var grokHookStatus: GrokHookInstallationStatus? { hooks.grokHookStatus }
    var grokHookStatusTitle: String { hooks.grokHookStatusTitle }
    var grokHookStatusSummary: String { hooks.grokHookStatusSummary }
    var piExtensionInstalled: Bool { hooks.piExtensionInstalled }
    var ohMyPiExtensionInstalled: Bool { hooks.ohMyPiExtensionInstalled }
    var isPiSetupBusy: Bool { hooks.isPiSetupBusy }
    var isOhMyPiSetupBusy: Bool { hooks.isOhMyPiSetupBusy }
    var piExtensionStatus: PiExtensionInstallationStatus? { hooks.piExtensionStatus }
    var ohMyPiExtensionStatus: PiExtensionInstallationStatus? { hooks.ohMyPiExtensionStatus }
    var codexHookStatusTitle: String { hooks.codexHookStatusTitle }
    var codexHookStatusSummary: String { hooks.codexHookStatusSummary }

    /// Mirrors `AgentIntentStore.firstLaunchCompleted`. Onboarding sets this
    /// to true after the user completes (or explicitly skips) the flow;
    /// legacy migration also flips it for users upgrading with existing
    /// hooks.
    var firstLaunchCompleted: Bool {
        get { hooks.intentStore.firstLaunchCompleted }
        set { hooks.intentStore.firstLaunchCompleted = newValue }
    }

    /// True if at least one managed hook is currently present on disk.
    /// Drives the "configure agents" empty-state prompts in the island and
    /// the settings window.
    var hasAnyInstalledAgent: Bool {
        hooks.claudeHooksInstalled
            || hooks.codexHooksInstalled
            || hooks.cursorHooksInstalled
            || hooks.qoderHooksInstalled
            || hooks.qwenCodeHooksInstalled
            || hooks.factoryHooksInstalled
            || hooks.codebuddyHooksInstalled
            || hooks.openCodePluginInstalled
            || hooks.geminiHooksInstalled
            || hooks.kimiHooksInstalled
            || hooks.grokHooksInstalled
            || hooks.piExtensionInstalled
            || hooks.ohMyPiExtensionInstalled
    }
    func refreshCodexHookStatus() { hooks.refreshCodexHookStatus() }
    func refreshClaudeHookStatus() { hooks.refreshClaudeHookStatus() }
    func refreshOpenCodePluginStatus() { hooks.refreshOpenCodePluginStatus() }
    func refreshCursorHookStatus() { hooks.refreshCursorHookStatus() }
    func refreshClaudeUsageState() { hooks.refreshClaudeUsageState() }
    func refreshCodexUsageState() { hooks.refreshCodexUsageState() }
    func installCodexHooks() { hooks.installCodexHooks() }
    func uninstallCodexHooks() { hooks.uninstallCodexHooks() }
    func installClaudeHooks() { hooks.installClaudeHooks() }
    func uninstallClaudeHooks() { hooks.uninstallClaudeHooks() }
    func installQoderHooks() { hooks.installQoderHooks() }
    func uninstallQoderHooks() { hooks.uninstallQoderHooks() }
    func installQwenCodeHooks() { hooks.installQwenCodeHooks() }
    func uninstallQwenCodeHooks() { hooks.uninstallQwenCodeHooks() }
    func installFactoryHooks() { hooks.installFactoryHooks() }
    func uninstallFactoryHooks() { hooks.uninstallFactoryHooks() }
    func installCodebuddyHooks() { hooks.installCodebuddyHooks() }
    func uninstallCodebuddyHooks() { hooks.uninstallCodebuddyHooks() }
    func refreshCCForkHookStatuses() { hooks.refreshCCForkHookStatuses() }
    func installOpenCodePlugin() { hooks.installOpenCodePlugin() }
    func uninstallOpenCodePlugin() { hooks.uninstallOpenCodePlugin() }
    func installCursorHooks() { hooks.installCursorHooks() }
    func uninstallCursorHooks() { hooks.uninstallCursorHooks() }
    func refreshGeminiHookStatus() { hooks.refreshGeminiHookStatus() }
    func installGeminiHooks() { hooks.installGeminiHooks() }
    func uninstallGeminiHooks() { hooks.uninstallGeminiHooks() }
    func refreshKimiHookStatus() { hooks.refreshKimiHookStatus() }
    func installKimiHooks() { hooks.installKimiHooks() }
    func uninstallKimiHooks() { hooks.uninstallKimiHooks() }
    func refreshGrokHookStatus() { hooks.refreshGrokHookStatus() }
    func installGrokHooks() { hooks.installGrokHooks() }
    func uninstallGrokHooks() { hooks.uninstallGrokHooks() }
    func refreshPiExtensionStatuses() { hooks.refreshPiExtensionStatuses() }
    func installPiExtension() { hooks.installPiExtension() }
    func uninstallPiExtension() { hooks.uninstallPiExtension() }
    func installOhMyPiExtension() { hooks.installOhMyPiExtension() }
    func uninstallOhMyPiExtension() { hooks.uninstallOhMyPiExtension() }
    func installClaudeUsageBridge() { hooks.installClaudeUsageBridge() }
    func uninstallClaudeUsageBridge() { hooks.uninstallClaudeUsageBridge() }
    func updateClaudeConfigDirectory(to newDirectory: URL?) { hooks.updateClaudeConfigDirectory(to: newDirectory) }
    func runHealthChecks() { hooks.runHealthChecks() }
    func repairHooks() {
        Task { @MainActor in
            await hooks.repairHooksIfNeeded()
        }
    }
    var isBridgeReady = false
    var lastActionMessage = "Waiting for agent hook events..." {
        didSet {
            guard lastActionMessage != oldValue else {
                return
            }

            harnessRuntimeMonitor?.recordLog(lastActionMessage)
        }
    }
    var isResolvingInitialLiveSessions: Bool {
        get { monitoring.isResolvingInitialLiveSessions }
        set { monitoring.isResolvingInitialLiveSessions = newValue }
    }
    var overlayDisplayOptions: [OverlayDisplayOption] {
        get { overlay.overlayDisplayOptions }
        set { overlay.overlayDisplayOptions = newValue }
    }
    var overlayPlacementDiagnostics: OverlayPlacementDiagnostics? {
        get { overlay.overlayPlacementDiagnostics }
        set { overlay.overlayPlacementDiagnostics = newValue }
    }
    var showDockIcon: Bool = false {
        didSet {
            guard hasFinishedInit, showDockIcon != oldValue else { return }
            defaults.set(showDockIcon, forKey: Self.showDockIconDefaultsKey)
            NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
            if !showDockIcon {
                // macOS does not immediately refresh the Dock when switching to
                // .accessory at runtime. Briefly activating another app forces
                // the Dock to drop the icon.
                NSApp.hide(nil)
                DispatchQueue.main.async {
                    NSApp.unhide(nil)
                }
            }
        }
    }
    /// The agent half of the app (Settings, General). On by default. Off,
    /// nothing of it runs or shows, and the app is the Nook alone (D41).
    var agentsEnabled: Bool = true {
        didSet {
            guard hasFinishedInit, agentsEnabled != oldValue else { return }
            AgentsSwitch.save(agentsEnabled, to: agentsDefaults)
            agentsEnabledDidChange()
        }
    }
    /// Where the agents switch is saved. A test hands in its own store.
    @ObservationIgnored
    private let agentsDefaults: UserDefaults
    /// Where every setting this model keeps is read and saved. The app uses
    /// the standard store. A test hands in one held in memory.
    @ObservationIgnored
    private let defaults: UserDefaults
    /// False for a model on a store of its own, which is a test or a preview.
    private var usesTheStandardStore: Bool { defaults === UserDefaults.standard }
    /// What this launch asked the agent half to run. Nil until the app has
    /// started, and kept for the agents switch, which starts the same parts
    /// when it is switched on later.
    @ObservationIgnored
    var agentLaunch: AgentRuntimeParts?
    /// The parts of the agent half that run right now.
    private(set) var agentRuntime: AgentRuntimeParts = []
    /// Goes up each time the agent half stops, which tells work that was
    /// under way that its results are no longer wanted.
    @ObservationIgnored
    private var agentRuntimeGeneration: UInt64 = 0
    /// Handed over once by the app, never by a harness run or a test.
    @ObservationIgnored
    private var agentHotkeyRegistrar: (any AgentHotkeyRegistering)?
    /// The welcome tour is offered once a launch.
    @ObservationIgnored
    private var hasOfferedWelcomeTour = false
    /// Whether `hangover://` links from other apps are carried out
    /// (Settings, General). On by default. Off, every link is ignored.
    var allowsLinksFromOtherApps: Bool = true {
        didSet {
            guard hasFinishedInit, allowsLinksFromOtherApps != oldValue else { return }
            defaults.set(allowsLinksFromOtherApps, forKey: Self.allowsLinksFromOtherAppsDefaultsKey)
        }
    }
    var hapticFeedbackEnabled: Bool = false {
        didSet {
            guard hasFinishedInit, hapticFeedbackEnabled != oldValue else { return }
            defaults.set(hapticFeedbackEnabled, forKey: Self.hapticFeedbackEnabledDefaultsKey)
        }
    }
    /// Keep the island open until the user acts on a pending approval /
    /// question surface (Settings → General). Opt-in: permission and
    /// question cards never auto-collapse, so with this on the only way to
    /// get rid of one is to answer it — clicking into the terminal to type
    /// the answer no longer dismisses the card.
    var keepNotchOpenUntilDecision: Bool = false {
        didSet {
            guard hasFinishedInit, keepNotchOpenUntilDecision != oldValue else { return }
            defaults.set(keepNotchOpenUntilDecision, forKey: Self.keepNotchOpenUntilDecisionDefaultsKey)
        }
    }
    /// Two-finger swipes on the island (Settings → General, D46). Opt-in:
    /// off, a scroll over the island does nothing, and anything a swipe hid
    /// comes back.
    var swipeGesturesEnabled: Bool = false {
        didSet {
            guard hasFinishedInit, swipeGesturesEnabled != oldValue else { return }
            defaults.set(swipeGesturesEnabled, forKey: IslandSwipeSetting.defaultsKey)
            if !swipeGesturesEnabled { nook.closedContentHiddenBySwipe = false }
            // The scroll monitors exist only while the swipe is on.
            overlay.overlayPanelController.setSwipeMonitoring(enabled: swipeGesturesEnabled)
        }
    }
    /// How many swipes the island has acted on since the app started. Not
    /// saved. The welcome tour reads it to tell that its swipe was tried.
    private(set) var swipeActionCount = 0
    /// Whether the closed island opens when the pointer rests on it or only
    /// on a click (Settings → General). Files dragged to the island open it
    /// either way.
    var islandOpenTrigger: IslandOpenTrigger = .hover {
        didSet {
            guard hasFinishedInit, islandOpenTrigger != oldValue else { return }
            defaults.set(islandOpenTrigger.rawValue, forKey: Self.islandOpenTriggerDefaultsKey)
        }
    }
    var showCodexUsage: Bool = false {
        didSet {
            guard hasFinishedInit, showCodexUsage != oldValue else { return }
            defaults.set(showCodexUsage, forKey: Self.showCodexUsageDefaultsKey)
        }
    }
    var completionReplyEnabled: Bool = false {
        didSet {
            guard hasFinishedInit, completionReplyEnabled != oldValue else { return }
            defaults.set(completionReplyEnabled, forKey: Self.completionReplyEnabledDefaultsKey)
            refreshOverlayPlacementIfVisible()
        }
    }
    var suppressFrontmostNotifications: Bool = true {
        didSet {
            guard hasFinishedInit, suppressFrontmostNotifications != oldValue else { return }
            defaults.set(suppressFrontmostNotifications, forKey: Self.suppressFrontmostNotificationsDefaultsKey)
        }
    }
    var launchAtLoginEnabled: Bool = false {
        didSet {
            guard !isApplyingLaunchAtLogin, hasFinishedInit, launchAtLoginEnabled != oldValue else { return }
            do {
                try LaunchAtLoginService.shared.setEnabled(launchAtLoginEnabled)
            } catch {
                isApplyingLaunchAtLogin = true
                launchAtLoginEnabled = oldValue
                isApplyingLaunchAtLogin = false
                presentLaunchAtLoginError(error)
            }
        }
    }
    private func presentLaunchAtLoginError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = lang.t("settings.general.launchAtLogin")
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
    @ObservationIgnored
    private var isApplyingLaunchAtLogin = false
    var isSoundMuted = false {
        didSet {
            guard isSoundMuted != oldValue else {
                return
            }

            defaults.set(isSoundMuted, forKey: Self.soundMutedDefaultsKey)
            lastActionMessage = isSoundMuted
                ? "Island sound notifications muted."
                : "Island sound notifications enabled."
        }
    }
    var selectedSoundName: String = NotificationSoundService.defaultSoundName {
        didSet {
            guard selectedSoundName != oldValue else { return }
            NotificationSoundService.setSelectedSoundName(selectedSoundName, in: defaults)
        }
    }
    var overlayDisplaySelectionID: String {
        get { overlay.overlayDisplaySelectionID }
        set { overlay.overlayDisplaySelectionID = newValue }
    }

    // MARK: - Appearance

    var appearanceSettingsProfile: IslandAppearanceDisplayProfile = .topBar {
        didSet {
            guard appearanceSettingsProfile != oldValue else { return }
            defaults.set(appearanceSettingsProfile.rawValue, forKey: Self.appearanceProfileSettingsDefaultsKey)
        }
    }

    private var notchAppearancePreferences = IslandAppearancePreferences() {
        didSet {
            guard notchAppearancePreferences != oldValue else { return }
            persistAppearancePreferences(notchAppearancePreferences, for: .notch)
            if activeAppearanceProfile == .notch { appearancePreferencesDidChange(oldValue: oldValue, newValue: notchAppearancePreferences) }
        }
    }

    private var topBarAppearancePreferences = IslandAppearancePreferences() {
        didSet {
            guard topBarAppearancePreferences != oldValue else { return }
            persistAppearancePreferences(topBarAppearancePreferences, for: .topBar)
            if activeAppearanceProfile == .topBar { appearancePreferencesDidChange(oldValue: oldValue, newValue: topBarAppearancePreferences) }
        }
    }

    /// Each display's setup from before a template replaced it. Kept for
    /// the session, which lets the Personalization tab put it back.
    var templateUndo: [IslandAppearanceDisplayProfile: PersonalizationSetup] = [:]

    /// Runtime profile selected from current overlay placement. External
    /// displays use the top-bar presentation; built-in notch displays keep
    /// notch-aware geometry and their own persisted appearance choices.
    var activeAppearanceProfile: IslandAppearanceDisplayProfile {
        overlayPlacementDiagnostics?.mode == .notch ? .notch : .topBar
    }

    var islandRightSlot: IslandRightSlot {
        get { appearancePreferences(for: activeAppearanceProfile).rightSlot }
        set { updateAppearancePreferences(for: activeAppearanceProfile) { $0.rightSlot = newValue } }
    }

    var islandCenterLabel: IslandCenterLabel {
        get { appearancePreferences(for: activeAppearanceProfile).centerLabel }
        set { updateAppearancePreferences(for: activeAppearanceProfile) { $0.centerLabel = newValue } }
    }

    var islandUsageDisplay: IslandUsageDisplay {
        get { appearancePreferences(for: activeAppearanceProfile).usageDisplay }
        set { updateAppearancePreferences(for: activeAppearanceProfile) { $0.usageDisplay = newValue } }
    }

    var islandSessionStateIndicator: IslandSessionStateIndicator {
        get { appearancePreferences(for: activeAppearanceProfile).sessionStateIndicator }
        set { updateAppearancePreferences(for: activeAppearanceProfile) { $0.sessionStateIndicator = newValue } }
    }

    var islandSessionGroup: IslandSessionGroup {
        get { appearancePreferences(for: activeAppearanceProfile).sessionGroup }
        set { updateAppearancePreferences(for: activeAppearanceProfile) { $0.sessionGroup = newValue } }
    }

    var islandSessionSort: IslandSessionSort {
        get { appearancePreferences(for: activeAppearanceProfile).sessionSort }
        set { updateAppearancePreferences(for: activeAppearanceProfile) { $0.sessionSort = newValue } }
    }

    var completedStaleThreshold: IslandCompletedStaleThreshold {
        get { appearancePreferences(for: activeAppearanceProfile).completedStaleThreshold }
        set { updateAppearancePreferences(for: activeAppearanceProfile) { $0.completedStaleThreshold = newValue } }
    }

    @ObservationIgnored
    var openSettingsWindow: (() -> Void)?

    @ObservationIgnored
    private var hasFinishedInit = false

    func appearancePreferences(for profile: IslandAppearanceDisplayProfile) -> IslandAppearancePreferences {
        switch profile {
        case .notch: notchAppearancePreferences
        case .topBar: topBarAppearancePreferences
        }
    }

    func updateAppearancePreferences(
        for profile: IslandAppearanceDisplayProfile,
        _ update: (inout IslandAppearancePreferences) -> Void
    ) {
        switch profile {
        case .notch:
            update(&notchAppearancePreferences)
        case .topBar:
            update(&topBarAppearancePreferences)
        }
    }

    private func appearancePreferencesDidChange(
        oldValue: IslandAppearancePreferences,
        newValue: IslandAppearancePreferences
    ) {
        if oldValue.sessionGroup != newValue.sessionGroup ||
            oldValue.sessionSort != newValue.sessionSort ||
            oldValue.completedStaleThreshold != newValue.completedStaleThreshold {
            _cachedSessionBuckets = nil
        }
        refreshOverlayPlacementIfVisible()
    }

    private func persistAppearancePreferences(
        _ preferences: IslandAppearancePreferences,
        for profile: IslandAppearanceDisplayProfile
    ) {
        defaults.set(preferences.rightSlot.rawValue, forKey: Self.appearanceDefaultsKey(profile, "rightSlot"))
        defaults.set(preferences.centerLabel.rawValue, forKey: Self.appearanceDefaultsKey(profile, "centerLabel"))
        defaults.set(preferences.usageDisplay.rawValue, forKey: Self.appearanceDefaultsKey(profile, "usageDisplay"))
        defaults.set(preferences.sessionStateIndicator.rawValue, forKey: Self.appearanceDefaultsKey(profile, "stateIndicator"))
        defaults.set(preferences.sessionGroup.rawValue, forKey: Self.appearanceDefaultsKey(profile, "sessionGroup"))
        defaults.set(preferences.sessionSort.rawValue, forKey: Self.appearanceDefaultsKey(profile, "sessionSort"))
        defaults.set(preferences.completedStaleThreshold.rawValue, forKey: Self.appearanceDefaultsKey(profile, "completedStaleThreshold"))
    }

    // MARK: - Watch Notification

    private static let watchNotificationEnabledKey = "watch.notification.enabled"

    var watchNotificationEnabled: Bool = false {
        didSet {
            guard watchNotificationEnabled != oldValue else { return }
            defaults.set(watchNotificationEnabled, forKey: Self.watchNotificationEnabledKey)
            if watchNotificationEnabled {
                startWatchRelay()
            } else {
                stopWatchRelay()
            }
        }
    }

    @ObservationIgnored
    private(set) var watchRelay: WatchNotificationRelay?

    /// Current pairing code for display in the settings UI.
    var watchPairingCode: String {
        watchRelay?.endpoint.currentCode() ?? "----"
    }

    /// Number of currently connected iPhone SSE clients.
    var watchConnectedDevices: Int {
        // Placeholder — endpoint doesn't expose count yet
        0
    }

    private func startWatchRelay() {
        // The relay sends agent requests to a phone or a watch.
        guard agentsEnabled, watchRelay == nil else { return }
        let relay = WatchNotificationRelay()
        setupWatchRelayCallbacks(relay)
        relay.start()
        self.watchRelay = relay
    }

    /// Wire up resolution callbacks so Watch/iPhone actions flow back to the bridge.
    private func setupWatchRelayCallbacks(_ relay: WatchNotificationRelay) {
        relay.onResolvePermission = { [weak self] sessionID, approved in
            Task { @MainActor [weak self] in
                self?.approvePermission(for: sessionID, approved: approved)
            }
        }

        relay.onAnswerQuestion = { [weak self] sessionID, answer in
            Task { @MainActor [weak self] in
                self?.answerQuestion(
                    for: sessionID,
                    answer: QuestionPromptResponse(answer: answer)
                )
            }
        }

        relay.endpoint.activeSessionCountProvider = { [weak self] in
            // Safe to call from any queue — reads a snapshot count.
            guard let self else { return 0 }
            return MainActor.assumeIsolated {
                self.state.sessions.count
            }
        }
    }

    private func stopWatchRelay() {
        watchRelay?.stop()
        watchRelay = nil
    }

    var ignoresPointerExitDuringHarness = false
    var disablesOverlayEventMonitoringDuringHarness = false

    @ObservationIgnored
    private var bridgeTask: Task<Void, Never>?

    @ObservationIgnored
    private var bridgeReconnectTask: Task<Void, Never>?

    @ObservationIgnored
    private var hasStarted = false

    @ObservationIgnored
    /// On the path the launch names (`OPEN_ISLAND_SOCKET_PATH`), else the
    /// app's own. A copy started for a launch check names a path of its
    /// own, which keeps it off the running app's sockets.
    private let bridgeServer = BridgeServer(socketURL: BridgeSocketLocation.currentURL(), claudeAskRules: .live)

    @ObservationIgnored
    private var bridgeClient = LocalBridgeClient()

    @ObservationIgnored
    private let terminalJumpAction: @Sendable (JumpTarget) throws -> String

    @ObservationIgnored
    private let isNotificationSessionAlreadyFrontmost: @Sendable (AgentSession) async -> Bool


    @ObservationIgnored
    var harnessRuntimeMonitor: HarnessRuntimeMonitor? {
        didSet {
            overlay.harnessRuntimeMonitor = harnessRuntimeMonitor
        }
    }


    @ObservationIgnored
    private var jumpTask: Task<Void, Never>?

    @ObservationIgnored
    private var notificationPresentationTask: Task<Void, Never>?

    private static func appearanceDefaultsKey(_ profile: IslandAppearanceDisplayProfile, _ name: String) -> String {
        "appearance.island.v8.\(profile.rawValue).\(name)"
    }

    private static func loadAppearancePreferences(
        for profile: IslandAppearanceDisplayProfile,
        from defaults: UserDefaults
    ) -> IslandAppearancePreferences {
        return IslandAppearancePreferences(
            rightSlot: IslandRightSlot(
                rawValue: defaults.string(forKey: appearanceDefaultsKey(profile, "rightSlot"))
                    ?? defaults.string(forKey: islandRightSlotDefaultsKey)
                    ?? ""
            ) ?? .count,
            centerLabel: IslandCenterLabel(
                rawValue: defaults.string(forKey: appearanceDefaultsKey(profile, "centerLabel"))
                    ?? defaults.string(forKey: islandCenterLabelDefaultsKey)
                    ?? ""
            ) ?? .agentAction,
            usageDisplay: IslandUsageDisplay(
                rawValue: defaults.string(forKey: appearanceDefaultsKey(profile, "usageDisplay"))
                    ?? ""
            ) ?? .compact,
            sessionStateIndicator: IslandSessionStateIndicator(
                rawValue: defaults.string(forKey: appearanceDefaultsKey(profile, "stateIndicator"))
                    ?? defaults.string(forKey: legacyIslandSessionStateIndicatorDefaultsKey)
                    ?? ""
            ) ?? .animatedDot,
            sessionGroup: IslandSessionGroup(
                rawValue: defaults.string(forKey: appearanceDefaultsKey(profile, "sessionGroup"))
                    ?? defaults.string(forKey: legacyIslandSessionGroupDefaultsKey)
                    ?? ""
            ) ?? .none,
            sessionSort: IslandSessionSort(
                rawValue: defaults.string(forKey: appearanceDefaultsKey(profile, "sessionSort"))
                    ?? defaults.string(forKey: legacyIslandSessionSortDefaultsKey)
                    ?? ""
            ) ?? .attention,
            completedStaleThreshold: IslandCompletedStaleThreshold(
                rawValue: defaults.string(forKey: appearanceDefaultsKey(profile, "completedStaleThreshold"))
                    ?? defaults.string(forKey: legacyCompletedStaleThresholdDefaultsKey)
                    ?? ""
            ) ?? .fiveMinutes
        )
    }

    init(
        terminalJumpAction: @escaping @Sendable (JumpTarget) throws -> String = { target in
            try TerminalJumpService().jump(to: target)
        },
        isNotificationSessionAlreadyFrontmost: @escaping @Sendable (AgentSession) async -> Bool = { session in
            await ForegroundTerminalSessionProbe().matches(session: session)
        },
        agentsDefaults: UserDefaults? = nil,
        defaults: UserDefaults = .standard,
        nookModel: NookModel? = nil
    ) {
        self.terminalJumpAction = terminalJumpAction
        self.isNotificationSessionAlreadyFrontmost = isNotificationSessionAlreadyFrontmost
        self.defaults = defaults
        self.agentsDefaults = agentsDefaults ?? defaults
        hooks = HookInstallationCoordinator(intentStore: AgentIntentStore(defaults: defaults))
        agentHotkeys = AgentHotkeyController(defaults: defaults)
        // A model built on a store of its own is a test or a preview. It
        // does not go looking for the old NotchNook GIF in the real folder.
        // The demo mode (D51) hands in a Nook whose services hold sample
        // content.
        nook = nookModel ?? NookModel(defaults: defaults, looksForImportedGIF: defaults === UserDefaults.standard)
        defaults.register(defaults: [
            Self.showDockIconDefaultsKey: true,
            Self.hapticFeedbackEnabledDefaultsKey: false,
            Self.keepNotchOpenUntilDecisionDefaultsKey: false,
            IslandSwipeSetting.defaultsKey: false,
            Self.allowsLinksFromOtherAppsDefaultsKey: true,
            Self.completionReplyEnabledDefaultsKey: false,
            Self.suppressFrontmostNotificationsDefaultsKey: true,
        ])
        // Read first: the watch relay below belongs to the agent half.
        agentsEnabled = AgentsSwitch.load(from: self.agentsDefaults)
        isSoundMuted = defaults.bool(forKey: Self.soundMutedDefaultsKey)
        selectedSoundName = NotificationSoundService.selectedSoundName(in: defaults)
        showDockIcon = defaults.bool(forKey: Self.showDockIconDefaultsKey)
        hapticFeedbackEnabled = defaults.bool(forKey: Self.hapticFeedbackEnabledDefaultsKey)
        keepNotchOpenUntilDecision = defaults.bool(forKey: Self.keepNotchOpenUntilDecisionDefaultsKey)
        swipeGesturesEnabled = defaults.bool(forKey: IslandSwipeSetting.defaultsKey)
        allowsLinksFromOtherApps = defaults.bool(forKey: Self.allowsLinksFromOtherAppsDefaultsKey)
        islandOpenTrigger = defaults.string(forKey: Self.islandOpenTriggerDefaultsKey)
            .flatMap(IslandOpenTrigger.init(rawValue:)) ?? .hover
        suppressFrontmostNotifications = defaults.bool(forKey: Self.suppressFrontmostNotificationsDefaultsKey)
        if defaults.object(forKey: Self.showCodexUsageDefaultsKey) != nil {
            showCodexUsage = defaults.bool(forKey: Self.showCodexUsageDefaultsKey)
        } else {
            showCodexUsage = FileManager.default.fileExists(
                atPath: CodexRolloutDiscovery.defaultRootURL.path
            )
        }
        completionReplyEnabled = defaults.bool(forKey: Self.completionReplyEnabledDefaultsKey)
        launchAtLoginEnabled = LaunchAtLoginService.shared.isEnabled
        appearanceSettingsProfile = IslandAppearanceDisplayProfile(
            rawValue: defaults.string(forKey: Self.appearanceProfileSettingsDefaultsKey) ?? ""
        ) ?? .topBar
        notchAppearancePreferences = Self.loadAppearancePreferences(for: .notch, from: defaults)
        topBarAppearancePreferences = Self.loadAppearancePreferences(for: .topBar, from: defaults)
        watchNotificationEnabled = defaults.bool(forKey: Self.watchNotificationEnabledKey)
        if watchNotificationEnabled {
            startWatchRelay()
        }

        overlay.appModel = self
        overlay.overlayPanelController.putsPanelOnScreen = usesTheStandardStore
        overlay.defaults = defaults
        overlay.restoreDisplayPreference()
        overlay.startObservingDisplayChanges()
        overlay.onStatusMessage = { [weak self] message in
            self?.lastActionMessage = message
        }
        overlay.activeIslandCardSessionAccessor = { [weak self] in
            self?.activeIslandCardSession
        }
        overlay.isSoundMutedAccessor = { [weak self] in
            self?.isSoundMuted ?? false
        }
        overlay.ignoresPointerExitAccessor = { [weak self] in
            self?.ignoresPointerExitDuringHarness ?? false
        }

        hooks.onStatusMessage = { [weak self] message in
            self?.lastActionMessage = message
        }

        discovery.syntheticClaudeSessionPrefix = Self.syntheticClaudeSessionPrefix
        discovery.onStatusMessage = { [weak self] message in
            self?.lastActionMessage = message
        }
        discovery.stateAccessor = { [weak self] in self?.state ?? SessionState() }
        discovery.stateUpdater = { [weak self] in self?.takeAgentState($0) }
        discovery.isActive = { [weak self] in self?.agentsEnabled ?? false }
        discovery.onStateChanged = { [weak self] in
            self?.synchronizeSelection()
            self?.refreshOverlayPlacementIfVisible()
        }
        discovery.onAgentEvent = { [weak self] event in
            self?.applyTrackedEvent(
                event,
                updateLastActionMessage: false,
                ingress: .rollout
            )
        }

        discovery.codexRolloutWatcher.eventHandler = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.applyTrackedEvent(
                    event,
                    updateLastActionMessage: false,
                    ingress: .rollout
                )
            }
        }

        codexAppServer.onEvent = { [weak self] event in
            self?.noteCodexAppServerEvent(event)
            self?.applyTrackedEvent(event, ingress: .bridge)
        }
        codexAppServer.onStatusMessage = { [weak self] message in
            self?.lastActionMessage = message
        }
        codexAppServer.isSessionTracked = { [weak self] id in
            self?.state.session(id: id) != nil
        }

        monitoring.syntheticClaudeSessionPrefix = Self.syntheticClaudeSessionPrefix
        monitoring.stateAccessor = { [weak self] in self?.state ?? SessionState() }
        monitoring.stateUpdater = { [weak self] in self?.takeAgentState($0) }
        monitoring.onSessionsReconciled = { [weak self] in
            self?.synchronizeSelection()
            self?.refreshOverlayPlacementIfVisible()
        }
        monitoring.onPersistenceNeeded = { [weak self] in
            self?.discovery.scheduleCodexSessionPersistence()
            self?.discovery.scheduleClaudeSessionPersistence()
            self?.discovery.scheduleOpenCodeSessionPersistence()
            self?.discovery.scheduleCursorSessionPersistence()
            self?.discovery.schedulePiSessionPersistence()
        }
        monitoring.onCodexAppRunningChanged = { [weak self] isRunning in
            guard let self else { return }
            if isRunning {
                self.codexAppServer.ensureConnected()
            } else {
                self.codexAppServer.disconnect()
            }
        }
        monitoring.onCodexAppMaintenanceTick = { [weak self] in
            self?.discovery.maintainCodexAppSessionsIfNeeded()
        }
        configureAgentTools()
        refreshOverlayDisplayConfiguration()
        hasFinishedInit = true
    }

    /// Empty while the agents switch is off, like every list below.
    var sessions: [AgentSession] {
        agentsEnabled ? state.sessions : []
    }

    var allSessions: [AgentSession] {
        sessions
    }

    /// Measured by SwiftUI GeometryReader in notification mode. Used by panel controller for sizing.
    /// Uses a tolerance of 2pt to avoid infinite layout loops caused by floating-point jitter
    /// in GeometryReader measurements across consecutive layout passes.
    var measuredNotificationContentHeight: CGFloat = 0 {
        didSet {
            let delta = abs(measuredNotificationContentHeight - oldValue)
            if delta >= 2, measuredNotificationContentHeight > 0 {
                overlay.refreshOverlayPlacementIfVisible()
            }
        }
    }

    var surfacedSessions: [AgentSession] {
        sessionBuckets.primary
    }

    var recentSessions: [AgentSession] {
        sessionBuckets.overflow
    }

    var islandListSessions: [AgentSession] {
        islandSessionSections.flatMap(\.sessions)
    }

    var islandSessionSections: [IslandSessionSection] {
        let sessions = sortIslandSessions(surfacedSessions)
        switch islandSessionGroup {
        case .none:
            return [
                IslandSessionSection(
                    id: "all",
                    title: "island.section.sessions",
                    sessions: sessions
                )
            ]
        case .state:
            return stateGroupedSections(for: sessions)
        case .agent:
            return AgentTool.allCases.compactMap { tool in
                let list = sessions.filter { $0.tool == tool }
                guard !list.isEmpty else { return nil }
                return IslandSessionSection(id: "agent-\(tool.rawValue)", title: tool.displayName, sessions: list)
            }
        case .project:
            let names = Set(sessions.map(projectGroupName(for:))).sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }
            return names.compactMap { name in
                let list = sessions.filter { projectGroupName(for: $0) == name }
                guard !list.isEmpty else { return nil }
                return IslandSessionSection(id: "project-\(name)", title: name, sessions: list)
            }
        }
    }

    var recentSessionCount: Int {
        recentSessions.count
    }

    var liveSessionCount: Int {
        surfacedSessions.count
    }

    var liveAttentionCount: Int {
        surfacedSessions.filter { $0.phase.requiresAttention }.count
    }

    var liveRunningCount: Int {
        surfacedSessions.filter { $0.phase == .running }.count
    }

    private func sortIslandSessions(_ sessions: [AgentSession]) -> [AgentSession] {
        switch islandSessionSort {
        case .attention:
            return sessions
        case .lastUpdate:
            return sessions.sorted { lhs, rhs in
                if lhs.islandActivityDate == rhs.islandActivityDate {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.islandActivityDate > rhs.islandActivityDate
            }
        }
    }

    private func stateGroupedSections(for sessions: [AgentSession]) -> [IslandSessionSection] {
        let definitions: [(id: String, title: String, include: (AgentSession) -> Bool)] = [
            ("approval", "island.section.needsApproval", { $0.phase == .waitingForApproval }),
            ("answer", "island.section.needsAnswer", { $0.phase == .waitingForAnswer }),
            ("running", "island.section.inProgress", { $0.phase == .running }),
            ("done", "island.section.justDone", { [completedStaleThreshold] session in
                session.phase == .completed
                    && !session.isStaleCompletedForIsland(at: .now, threshold: completedStaleThreshold.seconds)
            }),
            ("idle", "island.section.idle", { [completedStaleThreshold] session in
                session.phase == .completed
                    && session.isStaleCompletedForIsland(at: .now, threshold: completedStaleThreshold.seconds)
            }),
        ]

        return definitions.compactMap { definition in
            let list = sessions.filter(definition.include)
            guard !list.isEmpty else { return nil }
            return IslandSessionSection(id: "state-\(definition.id)", title: definition.title, sessions: list)
        }
    }

    private func projectGroupName(for session: AgentSession) -> String {
        if let workspace = session.jumpTarget?.workspaceName.trimmingCharacters(in: .whitespacesAndNewlines),
           !workspace.isEmpty {
            return workspace
        }

        let title = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return session.tool.displayName }

        let pieces = title.split(separator: "·", maxSplits: 1).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return pieces.last?.isEmpty == false ? pieces.last! : title
    }

    // MARK: - v6 closed-island derivation

    /// The aggregate UnifiedBars state for the closed island. Waiting beats
    /// running; everything else is idle. Completed sessions are absorbed
    /// directly into idle so the pill never stops on a tick glyph.
    var islandClosedMode: UnifiedBars.Mode {
        let sessions = surfacedSessions
        if sessions.contains(where: { $0.phase.requiresAttention }) { return .waiting }
        if sessions.contains(where: { $0.phase == .running })       { return .running }
        return .idle
    }

    /// The spotlight session powering the center label (if any). Attention
    /// sessions first, then the most recent running one, then whatever's
    /// first.
    var islandClosedSpotlight: AgentSession? {
        surfacedSessions.first(where: { $0.phase.requiresAttention })
            ?? surfacedSessions.first(where: { $0.phase == .running })
            ?? surfacedSessions.first
    }

    /// Text to show in the closed island's center label. Respects the
    /// `islandCenterLabel` user preference.
    func islandClosedLabel() -> String? {
        guard islandCenterLabel != .off,
              let session = islandClosedSpotlight else { return nil }

        switch islandCenterLabel {
        case .off:
            return nil
        case .sessionName:
            let workspace = session.jumpTarget?.workspaceName ?? ""
            if !workspace.isEmpty { return workspace }
            return session.title.isEmpty ? session.tool.displayName : session.title
        case .agentAction:
            let action = session.displayCurrentToolName
            if let action, !action.isEmpty {
                return "\(session.tool.displayName) · \(action)"
            }
            return session.tool.displayName
        }
    }

    /// Right-slot payload derived from the user's `islandRightSlot`
    /// preference and current live state. Returns nil when the preference
    /// is `.none` or there's nothing meaningful to show.
    func islandClosedRightSlotContent() -> IslandRightSlotContent? {
        closedContentIsHidden ? nil : islandSlotContent(for: islandRightSlot)
    }

    /// The count badge or agent grid for either side of the closed island.
    func islandSlotContent(for slot: IslandRightSlot) -> IslandRightSlotContent? {
        let sessions = surfacedSessions
        switch slot {
        case .none:
            return nil
        case .count:
            let n = sessions.count
            guard n > 0 else { return nil }
            return .count(n)
        case .agents:
            // Display order = order-of-first-observation-in-the-island. A
            // session that later flips visibility (e.g. attachment churn,
            // completed↔running) keeps its existing slot instead of being
            // reshuffled by session.firstSeenAt, which tracks the historical
            // event time and can be older than visible peers. Bulk-observing
            // N sessions at once (e.g. at app launch) breaks the tie by
            // session.firstSeenAt so historical order is preserved.
            stampAgentsGridObservationTickets(for: sessions)
            let ordered = sessions.sorted { a, b in
                let ta = _agentsGridObservedSequence[a.id] ?? .max
                let tb = _agentsGridObservedSequence[b.id] ?? .max
                if ta != tb { return ta < tb }
                return a.id < b.id
            }
            var cells: [AgentGridCell] = []
            if ordered.count <= 9 {
                cells = ordered.map(Self.agentsGridCell(for:))
            } else {
                cells = ordered.prefix(7).map(Self.agentsGridCell(for:))
                cells.append(.overflow(ordered.count - 7))
            }
            return cells.isEmpty ? nil : .agents(cells)
        }
    }

    private func stampAgentsGridObservationTickets(for sessions: [AgentSession]) {
        let newcomers = sessions.filter { _agentsGridObservedSequence[$0.id] == nil }
        guard !newcomers.isEmpty else { return }
        let orderedNewcomers = newcomers.sorted { a, b in
            if a.firstSeenAt != b.firstSeenAt { return a.firstSeenAt < b.firstSeenAt }
            return a.id < b.id
        }
        for session in orderedNewcomers {
            _agentsGridObservedSequence[session.id] = _agentsGridNextTicket
            _agentsGridNextTicket += 1
        }
    }

    private func pruneAgentsGridObservationTicketsIfNeeded() {
        guard _agentsGridObservedSequence.count > Self.agentsGridObservedSequenceLimit else {
            return
        }

        let liveIDs = Set(state.sessions.map(\.id))
        let retainedHistoricalCapacity = max(Self.agentsGridObservedSequenceLimit - liveIDs.count, 0)
        let retainedHistoricalIDs = _agentsGridObservedSequence
            .filter { !liveIDs.contains($0.key) }
            .sorted { $0.value > $1.value }
            .prefix(retainedHistoricalCapacity)
            .map(\.key)
        let retainedIDs = liveIDs.union(retainedHistoricalIDs)
        _agentsGridObservedSequence = _agentsGridObservedSequence.filter {
            retainedIDs.contains($0.key)
        }
    }

    private static func agentsGridCell(for session: AgentSession) -> AgentGridCell {
        let color = Color(hex: session.tool.brandColorHex) ?? .gray
        let state: AgentGridCellState
        if session.phase.requiresAttention {
            state = .waiting
        } else if session.phase == .running {
            state = .running
        } else {
            state = .idle
        }
        return .session(color: color, state: state)
    }

    var shouldShowSessionBootstrapPlaceholder: Bool {
        isResolvingInitialLiveSessions
            && liveSessionCount == 0
            && sessions.contains(where: \.isTrackedLiveSession)
    }

    var focusedSession: AgentSession? {
        guard agentsEnabled else { return nil }
        return state.session(id: selectedSessionID) ?? surfacedSessions.first ?? state.activeActionableSession ?? state.sessions.first
    }

    var activeIslandCardSession: AgentSession? {
        guard agentsEnabled, let sessionID = islandSurface.sessionID else {
            return nil
        }

        return state.session(id: sessionID)
    }

    var hasAnySession: Bool {
        !sessions.isEmpty
    }

    var hasCodexSession: Bool {
        sessions.contains(where: { $0.tool == .codex })
    }

    var hasJumpableSession: Bool {
        sessions.contains(where: { $0.jumpTarget != nil })
    }

    var acceptanceSteps: [AcceptanceStep] {
        [
            AcceptanceStep(
                id: "bridge",
                title: "Bridge ready",
                detail: "The app must own the local socket and register as a bridge observer.",
                isComplete: isBridgeReady
            ),
            AcceptanceStep(
                id: "hooks",
                title: "Codex hooks installed",
                detail: "Managed `hooks.json` entries should be present in `~/.codex`.",
                isComplete: hooks.codexHooksInstalled
            ),
            AcceptanceStep(
                id: "overlay",
                title: "Island visible",
                detail: "Show the overlay at least once so the notch/top-bar surface is visible.",
                isComplete: isOverlayVisible
            ),
            AcceptanceStep(
                id: "session",
                title: "A Codex session is observed",
                detail: "Start Codex in Terminal and wait for the first session row to appear.",
                isComplete: hasCodexSession
            ),
            AcceptanceStep(
                id: "jump",
                title: "Jump target captured",
                detail: "At least one session should include terminal jump metadata.",
                isComplete: hasJumpableSession
            ),
        ]
    }

    var acceptanceCompletedCount: Int {
        acceptanceSteps.filter(\.isComplete).count
    }

    var isReadyForFirstAcceptance: Bool {
        acceptanceSteps.prefix(3).allSatisfy(\.isComplete)
    }

    var hasPassedAcceptanceFlow: Bool {
        acceptanceSteps.allSatisfy(\.isComplete)
    }

    var acceptanceStatusTitle: String {
        if hasPassedAcceptanceFlow {
            return "v0.1 acceptance passed"
        }

        if isReadyForFirstAcceptance {
            return "Ready for v0.1 acceptance"
        }

        return "v0.1 acceptance not ready"
    }

    var acceptanceStatusSummary: String {
        if hasPassedAcceptanceFlow {
            return "The current build has completed the first-run checklist end to end."
        }

        if isReadyForFirstAcceptance {
            return "You can start your first acceptance run now. Launch Codex in Terminal and walk the last two steps."
        }

        return "Finish the setup steps in the left column, then start Codex from Terminal."
    }

    func startIfNeeded(
        startBridge: Bool = true,
        shouldPerformBootAnimation: Bool = true,
        loadRuntimeState: Bool = true
    ) {
        guard !hasStarted else {
            return
        }
        hasStarted = true

        // Kept for the agents switch, which starts the same parts when it
        // is switched on after launch.
        let launch = AgentRuntimeParts.launch(startBridge: startBridge, loadRuntimeState: loadRuntimeState)
        agentLaunch = launch
        let startsAgents = !launch.allowed(agentsEnabled: agentsEnabled).isEmpty

        isResolvingInitialLiveSessions = false
        if startsAgents, launch.contains(.sessions) {
            startAgentSessions()
        }
        if loadRuntimeState {
            updateChecker.startIfNeeded()
            if !startsAgents {
                // The agent half offers the welcome tour once it has read
                // the hook status. With that half off the tour is offered
                // here, after the launch has put its windows away.
                Task { @MainActor [weak self] in self?.offerWelcomeTourOnce() }
            }
        }
        // Nook widgets run in harness launches too, so screenshots show live data.
        nook.onTransient = { [weak self] in
            // No pop on a display that has notices turned off.
            guard let self, self.nookDisplay.showsNotices else { return }
            self.notchPop()
        }
        nook.onDisplayPreferencesChanged = { [weak self] in self?.refreshOverlayPlacementIfVisible() }
        nook.activeProfile = { [weak self] in self?.activeAppearanceProfile ?? .topBar }
        nook.isSoundMuted = { [weak self] in self?.isSoundMuted ?? false }
        nook.widgetsInUserView = { [weak self] in self?.nookWidgetsInUserView ?? [] }
        // The volume and brightness keys go back to macOS while the closed
        // notch cannot show what they did.
        nook.volume.keys.canShowNotice = { [weak self] in
            guard let self else { return false }
            return self.notchStatus != .opened && self.nookDisplay.showsNotices
        }
        NookMirrorController.shared.onAspectRatioChange = { [weak self] in self?.refreshOverlayPlacementIfVisible() }
        nook.presentRingLight = { [weak self] isLit in
            NookRingLight.shared.setLit(isLit, on: self?.islandScreen)
        }
        NookRingLight.shared.onScreensChanged = { [weak self] in
            guard let nook = self?.nook else { return }
            nook.presentRingLight(nook.isMirrorOn && nook.isRingLightOn)
        }
        nook.start()
        SystemMotionMonitor.shared.start()
        refreshOverlayDisplayConfiguration()
        ensureOverlayPanel()
        if shouldPerformBootAnimation {
            performBootAnimation()
        }

        guard startBridge else {
            isBridgeReady = false
            lastActionMessage = loadRuntimeState
                ? "Harness mode active. Bridge startup skipped."
                : "Deterministic harness mode active. Runtime discovery and bridge startup skipped."
            harnessRuntimeMonitor?.recordMilestone("bridgeSkipped", message: lastActionMessage)
            return
        }

        guard startsAgents else {
            isBridgeReady = false
            lastActionMessage = Self.agentsOffMessage
            harnessRuntimeMonitor?.recordMilestone("bridgeSkipped", message: lastActionMessage)
            return
        }
        startAgentBridge()
    }

    // MARK: - The agents switch (D41)

    private static let agentsOffMessage = "Agents are switched off. Nothing of the agent half is running."

    /// Starts the parts of the agent half this launch asked for and that
    /// are not running yet. Nothing while the agents switch is off, and
    /// nothing before the app has started.
    func startAgentRuntime() {
        guard agentsEnabled, let launch = agentLaunch else { return }
        let missing = launch.subtracting(agentRuntime)
        if missing.contains(.sessions) { startAgentSessions() }
        if missing.contains(.bridge) { startAgentBridge() }
    }

    /// Session discovery, the hook status reads and the usage meters. The
    /// discovery's result starts hook repair and process monitoring.
    private func startAgentSessions() {
        agentRuntime.insert(.sessions)
        isResolvingInitialLiveSessions = true

        let generation = agentRuntimeGeneration
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let payload = self.discovery.loadStartupDiscoveryPayload()
            await MainActor.run {
                // The agents were switched off while the files were read.
                guard self.isAgentRuntimeCurrent(generation) else { return }
                self.applyStartupDiscoveryPayload(payload, generation: generation)
            }
        }

        // These are already async or lightweight, and safe to start at once.
        hooks.refreshCodexHookStatus()
        hooks.refreshClaudeHookStatus()
        hooks.refreshCCForkHookStatuses()
        hooks.refreshOpenCodePluginStatus()
        hooks.refreshPiExtensionStatuses()
        hooks.refreshCursorHookStatus()
        hooks.refreshGrokHookStatus()
        hooks.refreshClaudeUsageState()
        hooks.startClaudeUsageMonitoringIfNeeded()
        if showCodexUsage {
            hooks.refreshCodexUsageState()
            hooks.startCodexUsageMonitoringIfNeeded()
        }
    }

    /// The socket server the hooks talk to, and the app's connection to it.
    private func startAgentBridge() {
        do {
            try bridgeServer.start()
            agentRuntime.insert(.bridge)
            connectBridgeObserver()
        } catch {
            isBridgeReady = false
            lastActionMessage = "Failed to start local bridge: \(error.localizedDescription)"
            harnessRuntimeMonitor?.recordMilestone("bridgeStartFailed", message: lastActionMessage)
        }
    }

    /// True while the agent half that started with `generation` is still
    /// the one running.
    private func isAgentRuntimeCurrent(_ generation: UInt64) -> Bool {
        agentsEnabled && generation == agentRuntimeGeneration && agentRuntime.contains(.sessions)
    }

    /// Stops everything of the agent half that runs and takes what it
    /// showed off the screen. No agent's own files are touched: installed
    /// hooks stay where they are and find no bridge to talk to.
    private func stopAgentRuntime() {
        agentRuntimeGeneration &+= 1
        agentRuntime = []

        bridgeTask?.cancel()
        bridgeTask = nil
        bridgeReconnectTask?.cancel()
        bridgeReconnectTask = nil
        bridgeClient.disconnect()
        // Closing the server ends every hook that waits on an answer, and
        // each agent then asks in its own terminal.
        bridgeServer.stop()
        isBridgeReady = false

        monitoring.stopMonitoring()
        hooks.stopUsageMonitoring()
        codexAppServer.disconnect()
        discovery.codexRolloutWatcher.stop()
        notificationPresentationTask?.cancel()
        notificationPresentationTask = nil
        jumpTask?.cancel()
        jumpTask = nil
        stopWatchRelay()
        agentHotkeys.deactivate()
        isResolvingInitialLiveSessions = false

        // The session files on disk are left as they are, which lets the
        // same sessions come back when the switch does.
        state = SessionState()
        selectedSessionID = nil
        reconcileIslandSurfaceAfterStateChange()
        lastActionMessage = Self.agentsOffMessage
    }

    /// Runs when the agents switch changes, at launch or long after.
    private func agentsEnabledDidChange() {
        _cachedSessionBuckets = nil
        if agentsEnabled {
            if watchNotificationEnabled { startWatchRelay() }
            if let agentHotkeyRegistrar { agentHotkeys.activate(registrar: agentHotkeyRegistrar) }
            startAgentRuntime()
        } else {
            stopAgentRuntime()
        }
        refreshOverlayPlacementIfVisible()
    }

    /// Hands the agent shortcuts the system registrar. While the agents
    /// switch is off it is only kept, and nothing is registered with macOS.
    func activateAgentHotkeys(registrar: any AgentHotkeyRegistering) {
        agentHotkeyRegistrar = registrar
        guard agentsEnabled else { return }
        agentHotkeys.activate(registrar: registrar)
    }

    /// Session state from discovery or the process monitor. A result that
    /// was on its way when the agents were switched off is dropped.
    private func takeAgentState(_ newState: SessionState) {
        guard agentsEnabled else { return }
        state = newState
    }

    /// Shows the welcome tour by itself at most once a launch.
    private func offerWelcomeTourOnce() {
        guard !hasOfferedWelcomeTour else { return }
        hasOfferedWelcomeTour = true
        offerWelcomeTour()
    }

    // MARK: - Bridge observer connection

    private static let bridgeReconnectDelay: Duration = .seconds(2)
    private static let bridgeMaxReconnectDelay: Duration = .seconds(30)

    private func connectBridgeObserver() {
        bridgeTask?.cancel()
        bridgeReconnectTask?.cancel()

        // Explicitly disconnect the old client so its DispatchSource is
        // cancelled deterministically rather than relying on dealloc timing.
        bridgeClient.disconnect()

        // Create a fresh client for each connection attempt so we don't
        // have to worry about stale file-descriptor state.
        // The same path the server listens on.
        let client = LocalBridgeClient(socketURL: BridgeSocketLocation.currentURL())
        bridgeClient = client

        let stream: AsyncThrowingStream<AgentEvent, Error>
        do {
            stream = try client.connect()
        } catch {
            isBridgeReady = false
            lastActionMessage = "Failed to connect bridge observer: \(error.localizedDescription)"
            scheduleBridgeReconnect()
            return
        }

        // A single task handles both registration and event consumption so
        // there is no untracked task that could race with a reconnect.
        bridgeTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await client.send(.registerClient(role: .observer))
                // The agents were switched off while this was sent.
                guard !Task.isCancelled else { return }
                self.isBridgeReady = true
                self.lastActionMessage = "Bridge ready. Waiting for Claude and Codex hook events."
                self.harnessRuntimeMonitor?.recordMilestone("bridgeReady", message: self.lastActionMessage)
            } catch {
                guard !Task.isCancelled else { return }
                self.isBridgeReady = false
                self.lastActionMessage = "Failed to register bridge observer: \(error.localizedDescription)"
                self.harnessRuntimeMonitor?.recordMilestone(
                    "bridgeRegistrationFailed",
                    message: self.lastActionMessage
                )
                self.scheduleBridgeReconnect()
                return
            }

            do {
                for try await event in stream {
                    self.applyTrackedEvent(event)
                }
            } catch {}

            // Stream ended (server closed our connection or transient error).
            // Mark as disconnected and schedule reconnection.
            guard !Task.isCancelled else { return }
            self.isBridgeReady = false
            self.lastActionMessage = "Bridge observer disconnected. Reconnecting…"
            self.harnessRuntimeMonitor?.recordMilestone("bridgeDisconnected", message: self.lastActionMessage)
            self.scheduleBridgeReconnect()
        }
    }

    private func scheduleBridgeReconnect() {
        bridgeReconnectTask?.cancel()
        bridgeReconnectTask = Task { [weak self] in
            var delay = Self.bridgeReconnectDelay
            while !Task.isCancelled {
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled else { return }
                self.connectBridgeObserver()
                // If we're now connected, stop retrying.
                if self.isBridgeReady { return }
                delay = min(delay * 2, Self.bridgeMaxReconnectDelay)
            }
        }
    }

    func select(sessionID: String) {
        selectedSessionID = sessionID
    }

    // MARK: - Overlay forwarding

    func toggleOverlay() { overlay.toggleOverlay() }
    /// `page` forces the page for this open: a file dragged to the island
    /// opens it on the Nook page, where the tray is.
    func notchOpen(
        reason: NotchOpenReason,
        surface: IslandSurface = .sessionList(),
        page: NookOpenedPage? = nil
    ) {
        // Each open starts from the page setting; the header toggle only
        // lasts for one open.
        nook.pageOverride = page
        overlay.notchOpen(reason: reason, surface: surface)
    }

    /// A click inside a hover-opened island keeps it open.
    func pinHoverOpenedIsland() { overlay.pinHoverOpenedIsland() }

    /// True while the welcome tour holds the island open (D44).
    var tourHoldsIslandOpen: Bool { overlay.tourHoldsIslandOpen }
    func setTourHoldsIslandOpen(_ holds: Bool) { overlay.setTourHoldsIslandOpen(holds) }
    func notchClose() { overlay.notchClose() }

    /// Whether click-outside (and similar accidental dismissals) should be
    /// ignored because a session still needs an approve/deny or answer.
    var shouldBlockDismissWhileAwaitingDecision: Bool {
        guard keepNotchOpenUntilDecision else { return false }
        guard notchStatus == .opened else { return false }
        // Only sessions the island actually shows can pin it open; a hidden
        // subagent waiting on its parent must not block dismissal.
        return surfacedSessions.contains { session in
            session.phase.requiresAttention
        }
    }
    /// What refuses a swipe close right now, read for the scroll step.
    var swipeRefusals: IslandSwipeRefusals {
        IslandSwipeRefusals(
            blocksDismiss: shouldBlockDismissWhileAwaitingDecision,
            hasOpenPicker: nook.tray.isSharePickerOpen,
            holdsOpenForTour: tourHoldsIslandOpen
        )
    }
    func notchPop() { overlay.notchPop() }
    func performBootAnimation() { overlay.performBootAnimation() }
    func ensureOverlayPanel() { overlay.ensureOverlayPanel() }
    func showOverlay() { overlay.showOverlay() }
    func hideOverlay() { overlay.hideOverlay() }
    func expandNotificationToSessionList(clearExpansion: Bool = false) {
        overlay.expandNotificationToSessionList(clearExpansion: clearExpansion)
    }
    func refreshOverlayDisplayConfiguration() { overlay.refreshOverlayDisplayConfiguration() }
    func refreshOverlayPlacement() { overlay.refreshOverlayPlacement() }

    private var isShowingNotificationCard: Bool {
        notchOpenReason == .notification && islandSurface.sessionID != nil
    }

    /// The Nook choices for the kind of display the island is on right now.
    var nookDisplay: NookDisplayPreferences {
        nook.displayPreferences(for: activeAppearanceProfile)
    }

    /// Whether a swipe has sent what the closed island shows away (D46).
    /// An agent that waits on the user is never hidden.
    var closedContentIsHidden: Bool {
        nook.closedContentHiddenBySwipe && islandClosedMode != .waiting
    }

    /// The agent state the closed pill draws: idle while hidden.
    var islandClosedPillMode: UnifiedBars.Mode {
        closedContentIsHidden ? .idle : islandClosedMode
    }

    /// A sideways swipe on the closed island: hide what it shows, or bring
    /// it back. While an agent waits nothing is hidden and a swipe
    /// does nothing: setting the flag then would only arm a hide for when the
    /// wait ends.
    func toggleClosedContentHidden() {
        guard islandClosedMode != .waiting else { return }
        nook.closedContentHiddenBySwipe = !closedContentIsHidden
    }

    /// Counts a swipe the island acted on. A gesture it let pass is not one,
    /// and neither is a sideways swipe while an agent waits, which
    /// `toggleClosedContentHidden` answers with nothing.
    func noteSwipe(_ action: IslandSwipeAction) {
        switch action {
        case .none:
            return
        case .toggleClosedContent where islandClosedMode == .waiting:
            return
        case .close, .toggleClosedContent, .closeAndToggleClosedContent:
            swipeActionCount += 1
        }
    }

    /// What the Nook puts in the closed island on the current display.
    var nookClosedActivity: NookClosedActivity? {
        nook.closedActivity(for: nookDisplay, isHidden: closedContentIsHidden)
    }

    static let nookTrackLabelLimit = 26

    /// Center label for external displays: the track title while music is
    /// what the island shows and this display asks for it, the agent label
    /// otherwise. An agent waiting on the user always keeps the label.
    func islandClosedLabelWithNook() -> String? {
        if closedContentIsHidden { return nil }
        guard nookDisplay.centerLabelShowsTrack,
              islandClosedMode != .waiting,
              nookClosedActivity?.showsArtwork == true,
              let title = nook.nowPlaying?.title, !title.isEmpty else {
            return islandClosedLabel() ?? nookNextEventLabel()
        }
        return Self.truncatedLabel(title, limit: Self.nookTrackLabelLimit)
    }

    /// "Standup · in 20 min" for the center label while the agents are quiet.
    private func nookNextEventLabel() -> String? {
        guard nookDisplay.centerLabelShowsNextEvent, let event = nook.nextEvent else { return nil }
        let text = "\(event.title) · \(NookCompactBar.relativeStart(event))"
        return Self.truncatedLabel(text, limit: Self.nookEventLabelLimit)
    }

    static let nookEventLabelLimit = 34

    /// What the closed island's left shows on the current display. Nil
    /// means the agent bars, either by choice or because the chosen item
    /// has nothing to show (no battery, no event ahead).
    var nookLeftSlotContent: NookSideSlotContent? {
        closedContentIsHidden ? .hidden : nookLeftSlotContent(for: nookDisplay.leftSlot)
    }

    /// The left side for one choice. With the agents switched off there
    /// are no bars to fall back to, and the side is left empty.
    func nookLeftSlotContent(for slot: NookSideSlot) -> NookSideSlotContent? {
        guard agentsEnabled else { return nookSideSlotContent(for: slot) ?? .hidden }
        return slot == .agents ? nil : nookSideSlotContent(for: slot)
    }

    /// What the right side shows when this display overrides the island's
    /// own right slot. Nil leaves that slot in charge.
    var nookRightSlotContent: NookSideSlotContent? {
        if closedContentIsHidden { return nil }
        return nookDisplay.rightSlot.flatMap(nookSideSlotContent(for:))
    }

    /// What one side shows for a choice, nil when the choice has nothing
    /// to show. A choice that shows agents has nothing while they are
    /// switched off.
    func nookSideSlotContent(for slot: NookSideSlot) -> NookSideSlotContent? {
        if !agentsEnabled, slot.needsAgents { return nil }
        switch slot {
        case .agents:
            return .bars(islandClosedMode)
        case .count:
            return islandSlotContent(for: .count).map(NookSideSlotContent.agentSlot)
        case .grid:
            return islandSlotContent(for: .agents).map(NookSideSlotContent.agentSlot)
        case .none:
            return .hidden
        case .date:
            return .date(Calendar.current.component(.day, from: nook.calendar.lastTick))
        case .battery:
            return nook.power.batteryPercent.map { .battery(percent: $0, isCharging: nook.power.isCharging) }
        case .countdown:
            let now = nook.calendar.lastTick
            guard let event = nook.upcomingEvents.first(where: { !$0.isAllDay && $0.start > now }),
                  let text = NookSideSlotContent.countdownText(to: event.start, now: now) else { return nil }
            return .countdown(text)
        case .weather:
            return NookSideSlotContent.resolvedWeather(
                report: nook.weather.report,
                hasPlace: nook.weather.place != nil,
                unit: nook.weather.unit,
                now: nook.calendar.lastTick
            )
        case .timer:
            // The pill hides a side's item while the timer's own notice
            // shows (`V6ClosedPill`), which keeps the time from appearing twice.
            return NookSideSlotContent.timerText(remaining: nook.timer.remaining, isActive: nook.timer.isActive)
                .map(NookSideSlotContent.timer)
        case .todos:
            let source = nook.todo.source(reminders: nook.reminders)
            return NookSideSlotContent.resolvedTodos(items: source.items, connection: source.connection)
        }
    }

    /// Widgets on the Nook page for the current display: the Nook tab's
    /// list minus the ones this display hides.
    var nookVisibleWidgets: [NookWidgetKind] {
        nookWidgetPlacements.map(\.kind)
    }

    /// The same widgets in page order with the size each is drawn at.
    var nookWidgetPlacements: [NookWidgetPlacement] {
        nook.widgetPlacements(for: activeAppearanceProfile)
    }

    /// The screen the island is on, for the ring light and the demo mode.
    var islandScreen: NSScreen? {
        guard let frame = overlay.overlayPanelController.windowFrame else { return NSScreen.main }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
    }

    /// Height of the mirror above the widgets on the current display: the
    /// whole camera picture at the page's width. Nil while the mirror is
    /// off or its tile is not on this page.
    var nookMirrorHeight: CGFloat? { nookMirrorSize?.height }

    /// The opened island's sizes on the display it is on, from that
    /// display's look (D35).
    var islandOpenedMetrics: IslandOpenedMetrics {
        IslandOpenedMetrics.resolve(
            look: nookDisplay.openedLook,
            profile: activeAppearanceProfile,
            screenWidth: islandScreen?.visibleFrame.width
        )
    }

    /// The mirror's size above the widgets: the whole camera picture at the
    /// page's width, or smaller on a screen too short for that. Nil while
    /// the mirror is off or its tile is not on this page.
    var nookMirrorSize: CGSize? {
        guard NookMirrorLayout.isShown(isOn: nook.isMirrorOn, placements: nookWidgetPlacements) else { return nil }
        let room = islandScreen.map { screen in
            NookMirrorFit.room(
                contentRoom: IslandOpenedLayout.nookContentRoom(
                    screenMaxY: screen.frame.maxY,
                    visibleMinY: screen.visibleFrame.minY,
                    headerHeight: screen.islandClosedHeight,
                    bottomPadding: 0,
                    shadowBottomInset: IslandChromeMetrics.openedShadowBottomInset
                ),
                barsHeight: nookBarsHeight
            )
        }
        return NookMirrorFit.size(
            pageWidth: islandOpenedMetrics.pageWidth,
            aspectRatio: NookMirrorController.shared.aspectRatio,
            room: room
        )
    }

    /// What the Nook page holds beyond its grid on the current display.
    var nookPageExtras: NookPageExtras {
        let placements = nookWidgetPlacements
        // The small calendar lists no day, which leaves it nothing to grow.
        let calendarGrows = placements.contains { $0.kind == .calendar && $0.size != .small }
        let mirrorSize = nookMirrorSize
        let mirrorHeight = mirrorSize?.height
        // Only a mirror cut down for a short screen names its width.
        let mirrorWidth = mirrorSize.flatMap { $0.width < islandOpenedMetrics.pageWidth ? $0.width : nil }
        return NookPageExtras(
            mirrorHeight: mirrorHeight,
            mirrorWidth: mirrorWidth,
            showsEventEditor: nook.isEventEditorOpen && !placements.isEmpty,
            calendarExtraRows: calendarGrows ? nook.calendarExtraRows : 0,
            showsJoinBar: nook.meetingPrompt != nil,
            showsMirrorDecorationPicker: NookMirrorDecorationLayout.isPickerShown(
                isDecorating: nook.isDecoratingMirror,
                mirrorHeight: mirrorHeight
            )
        )
    }

    static func truncatedLabel(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Which page the opened island shows. A notification card always wins;
    /// then the header toggle's override for this open; then the setting,
    /// where Auto means agents while any session is running or waiting and
    /// the Nook the rest of the time.
    var showsNookPage: Bool {
        // The Nook is the only page while the agents switch is off.
        guard agentsEnabled else { return true }
        if isShowingNotificationCard { return false }
        switch nook.pageOverride ?? nook.forcedPage ?? nookDisplay.openedPage {
        case .agents:
            return false
        case .nook:
            return true
        case .auto:
            return !surfacedSessions.contains { $0.phase.requiresAttention || $0.phase == .running }
        }
    }

    /// The Nook widgets the user is looking at: the tiles of this display's
    /// page, while the island is open on it and the user opened it. The
    /// calendar and Reminders permissions wait for this.
    var nookWidgetsInUserView: Set<NookWidgetKind> {
        NookAccessTiming.widgetsInView(
            status: notchStatus,
            reason: notchOpenReason,
            showsNookPage: showsNookPage,
            pageWidgets: nook.widgetPlacements(for: activeAppearanceProfile).map(\.kind),
            isHeldByTour: tourHoldsIslandOpen
        )
    }

    func showNookPage() {
        nook.pageOverride = .nook
        refreshOverlayPlacementIfVisible()
    }

    /// Whether the opened island offers a second page to turn to.
    var showsPageSwitch: Bool { agentsEnabled }

    func showAgentsPage() {
        guard agentsEnabled else { return }
        nook.isEditingLayout = false
        nook.isMirrorOn = false
        nook.closeEventEditor(keepingDraft: true)
        nook.pageOverride = .agents
        refreshOverlayPlacementIfVisible()
    }

    func toggleNookPage() {
        if showsNookPage { showAgentsPage() } else { showNookPage() }
    }

    /// Now-playing row under the agent list.
    var showsNookCompactBar: Bool {
        !showsNookPage && !isShowingNotificationCard && nookDisplay.showsCompactBar && nook.hasCompactBarContent
    }

    /// Agent summary row above the Nook widgets.
    var showsNookAgentsBar: Bool {
        showsNookPage && nookDisplay.showsAgentsBar && !surfacedSessions.isEmpty
    }

    // MARK: - Opened island layout and presentation (D16)

    /// Heights the opened island animates to.
    var islandOpenedLayout: IslandOpenedLayout { overlay.openedLayout }

    /// What the opened island draws: live while open, the snapshot taken at
    /// `notchClose()` while it fades out.
    var openedPresentation: IslandOpenedPresentation {
        if notchStatus == .opened { return liveOpenedPresentation() }
        return overlay.closingPresentation ?? liveOpenedPresentation()
    }

    func liveOpenedPresentation() -> IslandOpenedPresentation {
        IslandOpenedPresentation(
            surface: islandSurface,
            openReason: notchOpenReason,
            showsNookPage: showsNookPage,
            showsNookAgentsBar: showsNookAgentsBar,
            showsNookCompactBar: showsNookCompactBar,
            // A copy of the card's session, so the close fade keeps drawing
            // the card as it was even after the session changes or goes.
            session: agentsEnabled ? state.session(id: islandSurface.sessionID) : nil
        )
    }

    /// Extra opened height the Nook bars add to the page content.
    var nookBarsHeight: CGFloat {
        if showsNookAgentsBar { return NookAgentsBar.outerHeight }
        if showsNookCompactBar { return NookCompactBar.outerHeight }
        return 0
    }

    /// Status dot drawn on the album art in the closed notch.
    var nookAgentStatusTint: Color? {
        guard !closedContentIsHidden, nookDisplay.showsAgentDotOnArt, !surfacedSessions.isEmpty else { return nil }
        switch islandClosedMode {
        case .waiting: return IslandDesignPalette.Status.waitingAggregate
        case .running: return IslandDesignPalette.Status.running
        case .idle: return nil
        }
    }
    private func refreshOverlayPlacementIfVisible() { overlay.refreshOverlayPlacementIfVisible() }
    func notePointerInsideIslandSurface() { overlay.notePointerInsideIslandSurface() }
    func handlePointerExitedIslandSurface() { overlay.handlePointerExitedIslandSurface() }
    private func presentNotificationSurface(_ surface: IslandSurface) { overlay.presentNotificationSurface(surface) }
    private func reconcileIslandSurfaceAfterStateChange() { overlay.reconcileIslandSurfaceAfterStateChange() }
    private func dismissNotificationSurfaceIfPresent(for sessionID: String) { overlay.dismissNotificationSurfaceIfPresent(for: sessionID) }
    private func dismissOverlayForJump() { overlay.dismissOverlayForJump() }

    var shouldAutoCollapseOnMouseLeave: Bool { overlay.shouldAutoCollapseOnMouseLeave }
    var autoCollapseOnMouseLeaveRequiresPriorSurfaceEntry: Bool { overlay.autoCollapseOnMouseLeaveRequiresPriorSurfaceEntry }
    var showsNotificationCard: Bool { overlay.showsNotificationCard }
    var shouldDeferTimedNotificationAutoCollapse: Bool { overlay.shouldDeferTimedNotificationAutoCollapse }
    var hasPendingNotificationAutoCollapse: Bool { overlay.hasPendingNotificationAutoCollapse }

    func loadDebugSnapshot(
        _ snapshot: IslandDebugSnapshot,
        presentOverlay: Bool = false,
        autoCollapseNotificationCards: Bool = false
    ) {
        state = SessionState(sessions: snapshot.sessions)
        selectedSessionID = snapshot.selectedSessionID ?? snapshot.sessions.first?.id
        lastActionMessage = "Loaded debug scenario: \(snapshot.title)."
        harnessRuntimeMonitor?.recordMilestone("scenarioLoaded", message: snapshot.title)

        overlay.applyOverlayState(from: snapshot, presentOverlay: presentOverlay, autoCollapseNotificationCards: autoCollapseNotificationCards)
    }

    func showSettings() {
        if let opener = openSettingsWindow {
            opener()
        } else {
            // First-launch fallback: SwiftUI's `openWindow` closure is registered
            // by `SettingsWindowContent.onAppear`, which doesn't fire until the
            // settings window renders the first time. Send the standard
            // `showSettingsWindow:` responder action (macOS 13+) so it fires
            // the `CommandGroup(.appSettings)` button that opens the window.
            NSApp.sendAction(NSSelectorFromString("showSettingsWindow:"), to: nil, from: nil)
        }
        if let window = NSApp.windows.first(where: { $0.title == AppBrand.settingsWindowTitle }) {
            window.level = DemoMode.raised(window.level)
            window.orderFrontRegardless()
            window.makeKey()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Opens the welcome tour on its agents page, where hooks are
    /// installed. Used by every "Set up agents" CTA in the empty-state UI.
    /// The Setup tab stays one click away from that page.
    func showOnboarding() {
        showWelcomeTour(startingAt: agentsEnabled ? .agents : .welcome)
    }

    func toggleSoundMuted() {
        isSoundMuted.toggle()
    }

    func approveFocusedPermission(_ approved: Bool) {
        guard let session = focusedSession else {
            return
        }
        guard !approved || canApproveFromIsland(session) else { return }

        send(
            .resolvePermission(sessionID: session.id, resolution: permissionResolution(for: approved)),
            userMessage: approved
                ? "Approving permission for \(session.title)."
                : "Denying permission for \(session.title)."
        )
    }

    func answerFocusedQuestion(_ answer: String) {
        guard let session = focusedSession else {
            return
        }
        guard canAnswerFromIsland(session) else { return }

        send(
            .answerQuestion(sessionID: session.id, response: QuestionPromptResponse(answer: answer)),
            userMessage: "Sending answer \"\(answer)\" for \(session.title)."
        )
    }

    func jumpToFocusedSession() {
        jump(to: focusedSession?.jumpTarget)
    }

    func jumpToSession(_ session: AgentSession) {
        guard let jumpTarget = session.jumpTarget,
              jumpTarget.terminalApp.lowercased() != "unknown" else {
            lastActionMessage = "Cannot jump: terminal app is unknown."
            return
        }
        jump(to: jumpTarget)
    }

    private func jump(to jumpTarget: JumpTarget?) {
        guard let jumpTarget else {
            lastActionMessage = "No jump target is available yet."
            return
        }

        let shouldDelayForDismissAnimation = isOverlayVisible
        let jumpAction = terminalJumpAction

        dismissOverlayForJump()
        jumpTask?.cancel()
        jumpTask = Task { [weak self] in
            if shouldDelayForDismissAnimation {
                try? await Task.sleep(for: Self.jumpOverlayDismissLeadTime)
            }

            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try jumpAction(jumpTarget)
                }.value

                guard !Task.isCancelled else {
                    return
                }

                self?.lastActionMessage = result
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                self?.lastActionMessage = "Jump failed: \(error.localizedDescription)"
            }
        }
    }

    func approvePermission(for sessionID: String, approved: Bool) {
        guard let session = state.session(id: sessionID), isWaitingForApproval(session) else {
            return
        }
        guard !approved || canApproveFromIsland(session) else { return }

        let resolution = permissionResolution(for: approved)
        dismissNotificationSurfaceIfPresent(for: sessionID)
        state.resolvePermission(sessionID: session.id, resolution: resolution)
        let resolved = state.session(id: session.id)
        synchronizeSelection()
        refreshOverlayPlacementIfVisible()

        send(
            .resolvePermission(sessionID: session.id, resolution: resolution),
            userMessage: approved
                ? "Approving permission for \(session.title)."
                : "Denying permission for \(session.title).",
            onFailure: { [weak self] error in
                self?.agentApprovalWasNotDelivered(waiting: session, resolved: resolved, error: error)
            }
        )
    }

    func approvePermission(for sessionID: String, action: ApprovalAction) {
        guard let session = state.session(id: sessionID), isWaitingForApproval(session) else {
            return
        }
        guard !action.isApproval || canApproveFromIsland(session) else { return }

        let resolution: PermissionResolution
        let message: String

        switch action {
        case .deny:
            resolution = .deny(message: "Permission denied in Hangover.", interrupt: false)
            message = "Denying permission for \(session.title)."
        case .allowOnce:
            resolution = .allowOnce()
            message = "Approving permission for \(session.title)."
        case let .allowWithUpdates(updates):
            resolution = .allowOnce(updatedPermissions: updates)
            message = "Always allowing for \(session.title)."
        }

        dismissNotificationSurfaceIfPresent(for: sessionID)
        state.resolvePermission(sessionID: session.id, resolution: resolution)
        let resolved = state.session(id: session.id)
        synchronizeSelection()
        refreshOverlayPlacementIfVisible()

        send(
            .resolvePermission(sessionID: session.id, resolution: resolution),
            userMessage: message,
            onFailure: { [weak self] error in
                self?.agentApprovalWasNotDelivered(waiting: session, resolved: resolved, error: error)
            }
        )
    }

    /// False for a request the agent wants approved where it runs: Claude
    /// Code ignores an approval from the island for a call one of its ask
    /// rules matches, and goes on waiting in the terminal. Such a request
    /// is left as it is, on screen and unanswered. A denial still goes.
    private func canApproveFromIsland(_ session: AgentSession) -> Bool {
        agentApprovals.route(for: session).canApprove
    }

    /// True while the session still has a request to decide. An answer
    /// that arrives after the request is over, from a device or a card that
    /// is closing, must not record a decision nobody could make.
    private func isWaitingForApproval(_ session: AgentSession) -> Bool {
        session.phase == .waitingForApproval && session.permissionRequest != nil
    }

    func dismissSession(_ sessionID: String) {
        // Close a card for this session first: the close snapshot copies the
        // session, and it must still exist then for the card to fade as is.
        dismissNotificationSurfaceIfPresent(for: sessionID)
        state.dismissSession(id: sessionID)
        synchronizeSelection()
    }

    /// False for a question the agent wants answered where it runs. An
    /// answer from the island, the watch or the phone would be ignored,
    /// and the card would close on a question that is still open.
    private func canAnswerFromIsland(_ session: AgentSession) -> Bool {
        AgentQuestionReplyRoute.route(for: session) == .bridge
    }

    func answerQuestion(for sessionID: String, answer: QuestionPromptResponse) {
        guard let session = state.session(id: sessionID) else {
            return
        }
        guard canAnswerFromIsland(session) else { return }

        dismissNotificationSurfaceIfPresent(for: sessionID)
        state.answerQuestion(sessionID: session.id, response: answer)
        synchronizeSelection()
        refreshOverlayPlacementIfVisible()

        send(
            .answerQuestion(sessionID: session.id, response: answer),
            userMessage: "Sending answer for \(session.title)."
        )
    }

    func replyToSession(_ session: AgentSession, text: String) {
        dismissNotificationSurfaceIfPresent(for: session.id)
        synchronizeSelection()
        refreshOverlayPlacementIfVisible()

        lastActionMessage = "Sending reply to \(session.title)…"

        Task { [weak self] in
            let success = await Task.detached(priority: .userInitiated) {
                TerminalTextSender.send(text, to: session)
            }.value

            self?.lastActionMessage = success
                ? "Sent reply to \(session.title)."
                : "Failed to send reply to \(session.title)."
            self?.agentReplyWasSent(text, to: session, succeeded: success)
        }
    }


    /// `onFailure` runs when the command never reached the bridge.
    private func send(
        _ command: BridgeCommand,
        userMessage: String,
        onFailure: (@MainActor (any Error) -> Void)? = nil
    ) {
        lastActionMessage = userMessage

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try await self.bridgeClient.send(command)
            } catch {
                self.lastActionMessage = "Failed to send bridge command: \(error.localizedDescription)"
                onFailure?(error)
            }
        }
    }

    private func permissionResolution(for approved: Bool) -> PermissionResolution {
        if approved {
            return .allowOnce()
        }

        return .deny(message: "Permission denied in Hangover.", interrupt: false)
    }

    func applyTrackedEvent(
        _ event: AgentEvent,
        updateLastActionMessage: Bool = true,
        ingress: TrackedEventIngress = .bridge
    ) {
        // An event that was on its way when the agents were switched off.
        guard agentsEnabled else { return }

        if case .sessionHeartbeat = event {
            state.apply(event)
            return
        }

        // Snapshot whether this session was already completed before applying
        // the event. Used to suppress duplicate/stale completion notifications
        // (e.g. rollout watcher re-discovering an old completion on startup,
        // or producing a duplicate sessionCompleted that races with the bridge).
        let wasAlreadyCompleted: Bool = {
            guard case let .sessionCompleted(payload) = event else { return false }
            return state.session(id: payload.sessionID)?.phase == .completed
        }()

        // Guard: don't let rollout events downgrade a session from completed
        // back to running. The bridge's sessionCompleted is authoritative; the
        // rollout watcher may have read the JSONL before task_complete was
        // flushed, producing a stale activityUpdated(phase: .running).
        if ingress == .rollout,
           case let .activityUpdated(payload) = event,
           payload.phase == .running,
           state.session(id: payload.sessionID)?.phase == .completed {
            return
        }

        state.apply(event)
        noteAgentToolsEvent(event, ingress: ingress)
        // An agent that starts waiting brings the closed island back (D46).
        if islandClosedMode == .waiting { nook.closedContentHiddenBySwipe = false }
        reconcileIslandSurfaceAfterStateChange()
        if ingress == .bridge {
            monitoring.markSessionAttached(for: event)
            monitoring.markSessionProcessAlive(for: event)
        }
        synchronizeSelection()
        discovery.refreshCodexRolloutTracking()
        refreshOverlayPlacementIfVisible()
        discovery.scheduleCodexSessionPersistence()
        discovery.scheduleClaudeSessionPersistence()
        discovery.scheduleOpenCodeSessionPersistence()
        discovery.scheduleCursorSessionPersistence()
        discovery.schedulePiSessionPersistence()

        // Push relevant events to the Watch/iPhone via the relay
        if let relay = watchRelay {
            let eventSessionID: String? = {
                switch event {
                case let .sessionStarted(p): return p.sessionID
                case let .activityUpdated(p): return p.sessionID
                case let .permissionRequested(p): return p.sessionID
                case let .questionAsked(p): return p.sessionID
                case let .sessionCompleted(p): return p.sessionID
                case let .jumpTargetUpdated(p): return p.sessionID
                case let .sessionMetadataUpdated(p): return p.sessionID
                case let .claudeSessionMetadataUpdated(p): return p.sessionID
                case let .geminiSessionMetadataUpdated(p): return p.sessionID
                case let .openCodeSessionMetadataUpdated(p): return p.sessionID
                case let .cursorSessionMetadataUpdated(p): return p.sessionID
                case let .piSessionMetadataUpdated(p): return p.sessionID
                case let .sessionHeartbeat(p): return p.sessionID
                case let .actionableStateResolved(p): return p.sessionID
                }
            }()
            let session = eventSessionID.flatMap { state.session(id: $0) }
            relay.notifyEvent(event, session: session)
        }

        if updateLastActionMessage {
            lastActionMessage = describe(event)
        }

        if let surface = IslandSurface.notificationSurface(for: event),
           !nook.shouldSuppressNotification(for: event) {
            // A finished agent flashes the halo green, under the same rules
            // that decide whether its completion card shows.
            if case .sessionCompleted = event,
               !wasAlreadyCompleted,
               notificationSurfaceIsEligibleForPresentation(surface, ingress: ingress) {
                halo.noteCompletion()
            }
            scheduleNotificationSurfacePresentationIfNeeded(
                surface,
                wasAlreadyCompleted: wasAlreadyCompleted,
                ingress: ingress
            )
        }
    }

    private func scheduleNotificationSurfacePresentationIfNeeded(
        _ surface: IslandSurface,
        wasAlreadyCompleted: Bool,
        ingress: TrackedEventIngress
    ) {
        guard !wasAlreadyCompleted,
              notificationSurfaceIsEligibleForPresentation(surface, ingress: ingress),
              let sessionID = surface.sessionID,
              let session = state.session(id: sessionID) else {
            return
        }

        guard suppressFrontmostNotifications else {
            presentNotificationSurface(surface)
            return
        }

        notificationPresentationTask?.cancel()
        notificationPresentationTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let shouldSuppress = await self.isNotificationSessionAlreadyFrontmost(session)
            guard !Task.isCancelled,
                  !shouldSuppress,
                  self.notificationSurfaceIsEligibleForPresentation(surface, ingress: ingress) else {
                return
            }

            self.presentNotificationSurface(surface)
        }
    }

    private func notificationSurfaceIsEligibleForPresentation(
        _ surface: IslandSurface,
        ingress: TrackedEventIngress
    ) -> Bool {
        guard let sessionID = surface.sessionID,
              let session = state.session(id: sessionID) else {
            return false
        }

        return (ingress == .bridge || !isResolvingInitialLiveSessions)
            && (notchStatus == .closed || notchOpenReason == .notification)
            && !overlay.shouldPreserveCurrentNotificationSurface(against: surface)
            && surface.matchesCurrentState(of: session)
    }

    private func synchronizeSelection() {
        let surfacedIDs = Set(surfacedSessions.map(\.id))

        if let activeAction = state.activeActionableSession {
            selectedSessionID = activeAction.id
            return
        }

        guard let selectedSessionID,
              surfacedIDs.contains(selectedSessionID),
              state.session(id: selectedSessionID) != nil else {
            self.selectedSessionID = surfacedSessions.first?.id ?? state.sessions.first?.id
            return
        }
    }

    /// Applies startup discovery results on the main thread after background I/O completes.
    /// `generation` names the start this payload belongs to. Each step
    /// that waits checks it again, which keeps a switch to off from being
    /// followed by a hook install or a repair.
    private func applyStartupDiscoveryPayload(
        _ payload: SessionDiscoveryCoordinator.StartupDiscoveryPayload,
        generation: UInt64
    ) {
        discovery.applyStartupDiscoveryPayload(payload)

        // Apply hooks binary URL and update the installed copy if the app ships a newer version.
        hooks.hooksBinaryURL = payload.hooksBinaryURL
        hooks.updateHooksBinaryIfNeeded()

        // Auto-install missing hooks and usage bridge, then run health checks.
        let hooksBinaryLocated = payload.hooksBinaryURL != nil
        Task { @MainActor [weak self] in
            guard let self else { return }

            // Wait for all status reads to complete before checking install state.
            await self.hooks.refreshAllHookStatusAndWait()
            guard self.isAgentRuntimeCurrent(generation) else { return }

            // Reconcile persisted intent with what is actually on disk. For
            // legacy users this records existing hooks as `.installed` and
            // marks first-launch as complete so onboarding does not appear
            // on upgrade. Must run after status reads and before any
            // install decision.
            self.hooks.migrateIntentStoreIfNeeded()
            // Every install gets the welcome tour once, whether or not it
            // had agents connected before.
            self.offerWelcomeTourOnce()

            // Pi and Oh My Pi load a runtime extension that talks to the
            // bridge socket directly, so they do not depend on the hooks
            // binary and are installed whether or not it was located.
            if self.hooks.shouldAutoInstall(.pi) { self.installPiExtension() }
            if self.hooks.shouldAutoInstall(.ohMyPi) { self.installOhMyPiExtension() }

            // Everything below writes the hooks binary path into agent
            // config, so it only runs once the binary has been located.
            guard hooksBinaryLocated else { return }

            // Install only hooks the user has not explicitly opted out of.
            // `shouldAutoInstall` skips `.uninstalled` agents and agents
            // whose hooks are already present — it is the single checkpoint
            // that fixes #324.
            if self.hooks.shouldAutoInstall(.claudeCode) { self.installClaudeHooks() }
            if self.hooks.shouldAutoInstall(.codex) { self.installCodexHooks() }
            if self.hooks.shouldAutoInstall(.qoder) { self.installQoderHooks() }
            if self.hooks.shouldAutoInstall(.qwenCode) { self.installQwenCodeHooks() }
            if self.hooks.shouldAutoInstall(.factory) { self.installFactoryHooks() }
            if self.hooks.shouldAutoInstall(.codebuddy) { self.installCodebuddyHooks() }
            if self.hooks.shouldAutoInstall(.openCode) { self.installOpenCodePlugin() }
            if self.hooks.shouldAutoInstall(.cursor) { self.installCursorHooks() }
            if self.hooks.shouldAutoInstall(.gemini) { self.installGeminiHooks() }
            if self.hooks.shouldAutoInstall(.kimi) { self.installKimiHooks() }
            if self.hooks.shouldAutoInstall(.grok) { self.installGrokHooks() }
            if self.hooks.shouldAutoInstall(.claudeUsageBridge) { self.installClaudeUsageBridge() }

            // Run health checks after install to detect stale paths, conflicts, etc.
            try? await Task.sleep(for: .milliseconds(500))
            guard self.isAgentRuntimeCurrent(generation) else { return }
            await self.hooks.repairHooksIfNeeded { [weak self] in
                self?.isAgentRuntimeCurrent(generation) ?? false
            }
        }

        // Reconcile attachments and start monitoring (requires sessions to be loaded).
        monitoring.reconcileSessionAttachments()
        monitoring.startMonitoringIfNeeded()
    }


    /// The one gate for what the island shows of the agents: the closed
    /// pill, the list, the glow, the bars and the shortcuts all read from
    /// here, and all of them get nothing while the agents switch is off.
    private var sessionBuckets: (primary: [AgentSession], overflow: [AgentSession]) {
        guard agentsEnabled else { return ([], []) }
        if let cached = _cachedSessionBuckets {
            return cached
        }
        let result = computeSessionBuckets()
        _cachedSessionBuckets = result
        return result
    }

    private func computeSessionBuckets() -> (primary: [AgentSession], overflow: [AgentSession]) {
        let now = Date.now
        let rankedSessions = state.sessions.sorted { lhs, rhs in
            let lhsScore = displayPriority(for: lhs, now: now)
            let rhsScore = displayPriority(for: rhs, now: now)

            if lhsScore == rhsScore {
                if lhs.islandActivityDate == rhs.islandActivityDate {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }

                return lhs.islandActivityDate > rhs.islandActivityDate
            }

            return lhsScore > rhsScore
        }

        var primary: [AgentSession] = []
        var claimedLiveAttachmentKeys: Set<String> = []

        for session in rankedSessions where session.isVisibleInIsland {
            guard !session.isSubagentSession else { continue }

            if let liveAttachmentKey = monitoring.liveAttachmentKey(for: session) {
                guard claimedLiveAttachmentKeys.insert(liveAttachmentKey).inserted else {
                    continue
                }
            }

            primary.append(session)
        }

        let primaryIDs = Set(primary.map(\.id))
        let overflow = rankedSessions.filter { !primaryIDs.contains($0.id) && !$0.isSubagentSession }
        return (primary, overflow)
    }

    private func displayPriority(for session: AgentSession, now: Date) -> Int {
        var score = 0

        let presence = session.islandPresence(at: now)

        if session.isProcessAlive {
            score += presence == .inactive ? 3_000 : 12_000
        } else if session.isDemoSession || session.phase.requiresAttention {
            score += 6_000
        }

        if session.phase.requiresAttention {
            score += 10_000
        }

        if session.currentToolName?.isEmpty == false {
            score += 6_000
        }

        if session.jumpTarget != nil {
            score += 4_000
        }

        switch session.phase {
        case .running:
            score += 2_000
        case .waitingForApproval:
            score += 1_500
        case .waitingForAnswer:
            score += 1_200
        case .completed:
            score += 600
        }

        if session.isStaleCompletedForIsland(at: now, threshold: completedStaleThreshold.seconds) {
            score -= 900
        }

        let age = now.timeIntervalSince(session.islandActivityDate)
        switch age {
        case ..<120:
            score += 500
        case ..<900:
            score += 250
        case ..<3_600:
            score += 120
        case ..<21_600:
            score += 40
        default:
            break
        }

        return score
    }

    private func describe(_ event: AgentEvent) -> String {
        switch event {
        case let .sessionStarted(payload):
            return "Session started: \(payload.title)"
        case let .activityUpdated(payload):
            return payload.summary
        case let .permissionRequested(payload):
            return payload.request.summary
        case let .questionAsked(payload):
            return payload.prompt.title
        case let .sessionCompleted(payload):
            return payload.summary
        case let .jumpTargetUpdated(payload):
            return "Jump target updated to \(payload.jumpTarget.terminalApp)."
        case let .sessionMetadataUpdated(payload):
            if let currentTool = payload.codexMetadata.currentTool {
                return "Codex is running \(currentTool)."
            }

            return payload.codexMetadata.lastAssistantMessage ?? "Codex session metadata updated."
        case let .claudeSessionMetadataUpdated(payload):
            if let currentTool = payload.claudeMetadata.currentTool {
                return "Claude is running \(currentTool)."
            }

            return payload.claudeMetadata.lastAssistantMessage ?? "Claude session metadata updated."
        case let .geminiSessionMetadataUpdated(payload):
            return payload.geminiMetadata.lastAssistantMessage ?? "Gemini session metadata updated."
        case let .openCodeSessionMetadataUpdated(payload):
            if let currentTool = payload.openCodeMetadata.currentTool {
                return "OpenCode is running \(currentTool)."
            }

            return payload.openCodeMetadata.lastAssistantMessage ?? "OpenCode session metadata updated."
        case let .cursorSessionMetadataUpdated(payload):
            if let currentTool = payload.cursorMetadata.currentTool {
                return "Cursor is running \(currentTool)."
            }

            return payload.cursorMetadata.lastAssistantMessage ?? "Cursor session metadata updated."
        case let .piSessionMetadataUpdated(payload):
            if let currentTool = payload.piMetadata.currentTool {
                return "\(state.session(id: payload.sessionID)?.tool.displayName ?? "Pi") is running \(currentTool)."
            }
            return payload.piMetadata.lastAssistantMessage ?? "Pi session metadata updated."
        case let .sessionHeartbeat(payload):
            return "Heartbeat received for session \(payload.sessionID)."
        case let .actionableStateResolved(payload):
            return "Actionable state resolved for session \(payload.sessionID)."
        }
    }

    func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

}

// MARK: - Hex color helpers

extension String {
    var normalizedHexColorString: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard raw.count == 6, raw.allSatisfy(\.isHexDigit) else { return "#6E9FFF" }
        return "#\(raw.uppercased())"
    }
}

extension Color {
    init?(hex: String) {
        let raw = String(hex.normalizedHexColorString.dropFirst())
        guard let value = Int(raw, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self = Color(red: red, green: green, blue: blue)
    }

    var opaqueHexString: String? {
        guard let nsColor = NSColor(self).usingColorSpace(.deviceRGB) else { return nil }
        let r = Int(round(nsColor.redComponent * 255))
        let g = Int(round(nsColor.greenComponent * 255))
        let b = Int(round(nsColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
