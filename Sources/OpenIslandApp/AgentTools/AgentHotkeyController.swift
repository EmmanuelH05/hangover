import Foundation
import Observation

/// What macOS said about one shortcut.
enum AgentHotkeyRegistrationOutcome: Equatable, Sendable {
    case registered
    case failed(code: Int32)
}

/// Registers global shortcuts with the system. The app uses Carbon hot
/// keys, which need no permission. Tests pass a fake.
@MainActor
protocol AgentHotkeyRegistering: AnyObject {
    /// Registers these shortcuts in place of any registered before and
    /// reports each one's outcome. `onPress` runs once per press, never for
    /// a key that is held down, with the time the key went down.
    func register(
        _ combos: [AgentHotkeyAction: AgentHotkeyCombo],
        onPress: @escaping @MainActor (AgentHotkeyAction, Date) -> Void
    ) -> [AgentHotkeyAction: AgentHotkeyRegistrationOutcome]

    func unregisterAll()

    /// Shortcuts macOS itself has switched on (Spotlight, screenshots and
    /// the like).
    func systemShortcuts() -> Set<AgentHotkeyCombo>

    /// The label of a key on the keyboard layout in use.
    func keyName(for keyCode: UInt16) -> String?
}

/// Owns the approve and deny shortcuts: the saved choices, their state with
/// macOS, and when they are live. They are registered only while an agent
/// waits for approval, which leaves the keys to other apps the rest of the
/// time.
@MainActor
@Observable
final class AgentHotkeyController {
    static let approveComboKey = "agentHotkeys.approve.combo"
    static let denyComboKey = "agentHotkeys.deny.combo"
    static let approveEnabledKey = "agentHotkeys.approve.enabled"
    static let denyEnabledKey = "agentHotkeys.deny.enabled"

    /// How long the shortcuts stay registered after the last request is
    /// decided. A key still held from that decision is then seen as held,
    /// not as a new press on the next request.
    static let disarmDelay: Duration = .seconds(2)

    private(set) var settings: AgentHotkeySettings
    private(set) var statuses: [AgentHotkeyAction: AgentHotkeyStatus] = [:]
    /// True while Settings records a new shortcut. Nothing is registered
    /// then, which keeps a press meant for the recorder from deciding a
    /// request.
    private(set) var isRecording = false

    /// Goes up by one each time a press asks a folded card to open again.
    /// The card's row watches it.
    private(set) var unfoldRequests = 0

    /// The request the island shows as its single card, and since when.
    @ObservationIgnored private(set) var shownCard: AgentHotkeyCard?
    @ObservationIgnored private(set) var cardShownAt: Date?
    /// The card on screen, when the user has folded its buttons away.
    @ObservationIgnored private(set) var foldedCard: AgentHotkeyCard?
    /// When a press last approved or denied a request.
    @ObservationIgnored var lastDecisionAt: Date?
    /// Runs for each press that reaches the app, with the time the key
    /// went down.
    @ObservationIgnored var onPress: ((AgentHotkeyAction, Date) -> Void)?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var registrar: (any AgentHotkeyRegistering)?
    @ObservationIgnored private var isArmed = false
    /// What macOS holds for the app right now. Empty when nothing is
    /// registered.
    @ObservationIgnored private var registeredCombos: [AgentHotkeyAction: AgentHotkeyCombo] = [:]
    @ObservationIgnored private var disarmTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = Self.loadSettings(from: defaults)
        refreshStatuses(outcomes: nil)
    }

    // MARK: - Settings

    func combo(for action: AgentHotkeyAction) -> AgentHotkeyCombo {
        settings.combo(for: action)
    }

    func isEnabled(_ action: AgentHotkeyAction) -> Bool {
        settings.isEnabled(action)
    }

    func setEnabled(_ isEnabled: Bool, for action: AgentHotkeyAction) {
        guard settings.isEnabled(action) != isEnabled else { return }
        settings.setEnabled(isEnabled, for: action)
        defaults.set(isEnabled, forKey: action == .approve ? Self.approveEnabledKey : Self.denyEnabledKey)
        applyRegistration(probing: true)
    }

    /// Saves a new shortcut for `action`. A shortcut that breaks a rule is
    /// not saved, and the rule it breaks is returned.
    @discardableResult
    func setCombo(_ combo: AgentHotkeyCombo, for action: AgentHotkeyAction) -> AgentHotkeyProblem? {
        if let problem = AgentHotkeyRules.problem(with: combo, for: action, in: settings) {
            return problem
        }
        guard settings.combo(for: action) != combo else { return nil }
        settings.setCombo(combo, for: action)
        defaults.set(combo.storageValue, forKey: action == .approve ? Self.approveComboKey : Self.denyComboKey)
        applyRegistration(probing: true)
        return nil
    }

    func resetToDefaults() {
        settings = AgentHotkeySettings()
        for key in [Self.approveComboKey, Self.denyComboKey, Self.approveEnabledKey, Self.denyEnabledKey] {
            defaults.removeObject(forKey: key)
        }
        applyRegistration(probing: true)
    }

    /// "⌃⌥Y" on the keyboard layout in use.
    func displayText(for action: AgentHotkeyAction) -> String {
        displayText(for: settings.combo(for: action))
    }

    func displayText(for combo: AgentHotkeyCombo) -> String {
        combo.displayText { [registrar] keyCode in
            AgentHotkeyKeyboard.fixedName(for: keyCode)
                ?? registrar?.keyName(for: keyCode)
                ?? AgentHotkeyKeyboard.usName(for: keyCode)
        }
    }

    /// The keys to print on an approval card: only shortcuts macOS took.
    var hint: AgentHotkeyHint {
        AgentHotkeyHint(
            approve: statuses[.approve] == .ready ? displayText(for: .approve) : nil,
            deny: statuses[.deny] == .ready ? displayText(for: .deny) : nil
        )
    }

    // MARK: - Recording in Settings

    func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        applyRegistration(probing: false)
    }

    func endRecording() {
        guard isRecording else { return }
        isRecording = false
        applyRegistration(probing: true)
    }

    // MARK: - Lifecycle

    /// Hands the controller the system registrar. The app does this once at
    /// launch. Without it nothing is ever registered.
    func activate(registrar: any AgentHotkeyRegistering) {
        self.registrar = registrar
        applyRegistration(probing: true)
    }

    /// Tells the controller whether any agent is waiting for approval.
    func setArmed(_ armed: Bool) {
        guard armed != isArmed else { return }
        isArmed = armed
        disarmTask?.cancel()
        disarmTask = nil
        if armed {
            applyRegistration(probing: false)
            return
        }
        guard !registeredCombos.isEmpty else { return }
        disarmTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.disarmDelay)
            guard !Task.isCancelled, let self, !self.isArmed else { return }
            self.applyRegistration(probing: false)
        }
    }

    /// Tells the controller which request the island shows as its single
    /// card. The time is stamped when the card changes, which is when the
    /// request came on screen, and never when the request arrived.
    func noteShownCard(_ card: AgentHotkeyCard?, now: Date = .now) {
        guard card != shownCard else { return }
        shownCard = card
        cardShownAt = card == nil ? nil : now
        // A card that comes on screen starts unfolded.
        foldedCard = nil
    }

    /// The card's row reports its buttons being folded away and opened
    /// again. Opening them counts as the request coming on screen.
    func noteCard(_ card: AgentHotkeyCard, isFolded: Bool, now: Date = .now) {
        if isFolded {
            guard card == shownCard else { return }
            foldedCard = card
        } else if foldedCard == card {
            foldedCard = nil
            if card == shownCard { cardShownAt = now }
        }
    }

    /// Asks the folded card on screen to open its buttons again.
    func requestUnfold() {
        unfoldRequests += 1
    }

    /// A shortcut just brought the card on screen. Its time starts at the
    /// press, which no later press can then be close to.
    func noteRevealed(now: Date) {
        guard shownCard != nil else { return }
        cardShownAt = now
    }

    // MARK: - Registration

    /// Brings the system's registrations in line with the settings.
    /// `probing` registers once even when no agent waits, to learn whether
    /// macOS accepts the shortcuts, and lets go of them again.
    private func applyRegistration(probing: Bool) {
        guard let registrar else {
            refreshStatuses(outcomes: nil)
            return
        }

        let systemShortcuts = registrar.systemShortcuts()
        let usable = AgentHotkeyRules.usable(settings, systemShortcuts: systemShortcuts)
        let wantsLive = isArmed && !isRecording

        // Already live with these shortcuts. Registering again would forget
        // which keys are still held down.
        if wantsLive, !usable.isEmpty, registeredCombos == usable { return }

        guard !isRecording, wantsLive || probing, !usable.isEmpty else {
            registrar.unregisterAll()
            registeredCombos = [:]
            if !isRecording {
                refreshStatuses(outcomes: [:], systemShortcuts: systemShortcuts)
            }
            return
        }

        let outcomes = registrar.register(usable) { [weak self] action, pressedAt in
            self?.onPress?(action, pressedAt)
        }
        registeredCombos = usable.filter { outcomes[$0.key] == .registered }
        refreshStatuses(outcomes: outcomes, systemShortcuts: systemShortcuts)

        if !wantsLive {
            registrar.unregisterAll()
            registeredCombos = [:]
        }
    }

    /// `outcomes` nil means macOS was never asked.
    private func refreshStatuses(
        outcomes: [AgentHotkeyAction: AgentHotkeyRegistrationOutcome]?,
        systemShortcuts: Set<AgentHotkeyCombo> = []
    ) {
        var result: [AgentHotkeyAction: AgentHotkeyStatus] = [:]
        for action in AgentHotkeyAction.allCases {
            let combo = settings.combo(for: action)
            if !settings.isEnabled(action) {
                result[action] = .off
            } else if let problem = AgentHotkeyRules.problem(with: combo) {
                result[action] = .invalid(problem)
            } else if settings.isEnabled(action.other),
                      AgentHotkeyKeyboard.areNeighbours(combo.keyCode, settings.combo(for: action.other).keyCode) {
                result[action] = .invalid(.tooCloseToOther)
            } else if systemShortcuts.contains(combo) {
                result[action] = .usedBySystem
            } else if let outcomes {
                switch outcomes[action] {
                case .registered?: result[action] = .ready
                case let .failed(code)?: result[action] = .failed(code: code)
                // Not asked this time (nothing to probe): keep what is known.
                case nil: result[action] = statuses[action].flatMap { Self.carriedOver($0) } ?? .inactive
                }
            } else {
                result[action] = .inactive
            }
        }
        if result != statuses { statuses = result }
    }

    /// A status that still holds when macOS was not asked again.
    private static func carriedOver(_ status: AgentHotkeyStatus) -> AgentHotkeyStatus? {
        switch status {
        case .ready, .failed: status
        case .off, .inactive, .usedBySystem, .invalid: nil
        }
    }

    private static func loadSettings(from defaults: UserDefaults) -> AgentHotkeySettings {
        var settings = AgentHotkeySettings()
        if let combo = defaults.string(forKey: approveComboKey).flatMap(AgentHotkeyCombo.init(storageValue:)) {
            settings.approve = combo
        }
        if let combo = defaults.string(forKey: denyComboKey).flatMap(AgentHotkeyCombo.init(storageValue:)) {
            settings.deny = combo
        }
        if defaults.object(forKey: approveEnabledKey) != nil {
            settings.isApproveEnabled = defaults.bool(forKey: approveEnabledKey)
        }
        if defaults.object(forKey: denyEnabledKey) != nil {
            settings.isDenyEnabled = defaults.bool(forKey: denyEnabledKey)
        }
        return settings
    }
}
