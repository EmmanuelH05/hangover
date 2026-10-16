import Carbon.HIToolbox
import Foundation
import Observation
import OSLog

private let designHotkeyLog = Logger(subsystem: "app.openisland", category: "nook.design")

/// Why a shortcut cannot be the eyedropper's.
enum NookDesignHotkeyProblem: Equatable, Sendable {
    /// Fewer than two modifier keys, or neither Control nor Option. The
    /// same rule the agent shortcuts follow.
    case needsModifiers
    /// It is the approve or the deny shortcut.
    case usedByAgentShortcut

    var messageKey: String {
        switch self {
        case .needsModifiers: "settings.general.agentHotkeys.problem.needsModifiers"
        case .usedByAgentShortcut: "nook.design.hotkey.problem.agent"
        }
    }
}

/// Whether the eyedropper's shortcut is ready, for Settings.
enum NookDesignHotkeyStatus: Equatable, Sendable {
    /// No shortcut is set. This is how the app starts.
    case none
    /// Set, and macOS is not holding it: the widget is off, or the app
    /// never asked (tests and harness runs).
    case inactive
    /// macOS accepted it. It works from any app.
    case ready
    /// macOS refused it, with its error code.
    case failed(code: Int32)
    /// A macOS shortcut of its own already uses these keys.
    case usedBySystem
    /// The saved shortcut breaks a rule.
    case invalid(NookDesignHotkeyProblem)

    var isInvalid: Bool {
        if case .invalid = self { return true }
        return false
    }
}

/// Pure rules for the eyedropper's shortcut. They are the agent
/// shortcuts' rules plus one: it may not be either of those two.
enum NookDesignHotkeyRules {
    static func problem(
        with combo: AgentHotkeyCombo,
        agentShortcuts: [AgentHotkeyCombo]
    ) -> NookDesignHotkeyProblem? {
        if AgentHotkeyRules.problem(with: combo) != nil { return .needsModifiers }
        return agentShortcuts.contains(combo) ? .usedByAgentShortcut : nil
    }

    /// What Settings shows for a shortcut macOS was not asked about.
    static func restingStatus(
        for combo: AgentHotkeyCombo?,
        agentShortcuts: [AgentHotkeyCombo],
        systemShortcuts: Set<AgentHotkeyCombo>
    ) -> NookDesignHotkeyStatus {
        guard let combo else { return .none }
        if let problem = problem(with: combo, agentShortcuts: agentShortcuts) { return .invalid(problem) }
        return systemShortcuts.contains(combo) ? .usedBySystem : .inactive
    }
}

/// Registers the one shortcut with the system. The app uses a Carbon hot
/// key, which needs no permission. Tests pass a fake.
@MainActor
protocol NookDesignHotkeyRegistering: AnyObject {
    /// Registers this shortcut in place of the one before. `onPress` runs
    /// once per press, never for a key that is held down.
    func register(_ combo: AgentHotkeyCombo, onPress: @escaping @MainActor () -> Void) -> AgentHotkeyRegistrationOutcome
    func unregister()
    /// Shortcuts macOS itself has switched on.
    func systemShortcuts() -> Set<AgentHotkeyCombo>
    /// The label of a key on the keyboard layout in use.
    func keyName(for keyCode: UInt16) -> String?
}

/// Owns the eyedropper's shortcut: the saved choice, its state with macOS
/// and when it is live. There is no default. The keys are taken from
/// other apps only while the Design kit widget is switched on.
@MainActor
@Observable
final class NookDesignHotkeyController {
    nonisolated static let comboKey = "nook.design.eyedropper.hotkey"

    private(set) var combo: AgentHotkeyCombo?
    private(set) var status: NookDesignHotkeyStatus = .none
    /// True while Settings records a new shortcut. Nothing is registered
    /// then, which keeps the press meant for the recorder from starting a
    /// pick.
    private(set) var isRecording = false

    /// Runs for each press that reaches the app.
    @ObservationIgnored var onPress: (() -> Void)?
    /// The approve and deny shortcuts. The app model supplies them.
    @ObservationIgnored var agentShortcuts: () -> [AgentHotkeyCombo] = { [] }
    /// Tells the app model a recording began or ended, which lets it hold
    /// the agent shortcuts back for as long.
    @ObservationIgnored var onRecordingChange: (Bool) -> Void = { _ in }
    /// Tells the app model the keys or the live state changed, which lets the
    /// Record shortcut check itself against them again.
    @ObservationIgnored var onShortcutsChange: () -> Void = {}

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var registrar: (any NookDesignHotkeyRegistering)?
    @ObservationIgnored private var isLive = false
    /// What macOS holds for the app right now.
    @ObservationIgnored private var registered: AgentHotkeyCombo?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        combo = defaults.string(forKey: Self.comboKey).flatMap(AgentHotkeyCombo.init(storageValue:))
        applyRegistration()
    }

    // MARK: Settings

    /// Saves a new shortcut. One that breaks a rule is not saved, and the
    /// rule it breaks is returned.
    @discardableResult
    func setCombo(_ combo: AgentHotkeyCombo) -> NookDesignHotkeyProblem? {
        if let problem = NookDesignHotkeyRules.problem(with: combo, agentShortcuts: agentShortcuts()) {
            return problem
        }
        guard self.combo != combo else { return nil }
        self.combo = combo
        defaults.set(combo.storageValue, forKey: Self.comboKey)
        applyRegistration()
        onShortcutsChange()
        return nil
    }

    /// Goes back to no shortcut.
    func clear() {
        guard combo != nil else { return }
        combo = nil
        defaults.removeObject(forKey: Self.comboKey)
        applyRegistration()
        onShortcutsChange()
    }

    /// "⌃⌥C" on the keyboard layout in use, nil with no shortcut set.
    var displayText: String? {
        combo.map { combo in
            combo.displayText { [registrar] keyCode in
                AgentHotkeyKeyboard.fixedName(for: keyCode)
                    ?? registrar?.keyName(for: keyCode)
                    ?? AgentHotkeyKeyboard.usName(for: keyCode)
            }
        }
    }

    func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        onRecordingChange(true)
        applyRegistration()
    }

    func endRecording() {
        guard isRecording else { return }
        isRecording = false
        onRecordingChange(false)
        applyRegistration()
    }

    // MARK: Lifecycle

    /// Hands the controller the system registrar. The app does this once
    /// on a real launch. Without it nothing is ever registered.
    func activate(registrar: any NookDesignHotkeyRegistering) {
        self.registrar = registrar
        applyRegistration()
    }

    /// Tells the controller whether the Design kit widget is switched on.
    func setLive(_ live: Bool) {
        guard live != isLive else { return }
        isLive = live
        applyRegistration()
        onShortcutsChange()
    }

    /// Checks the shortcut against the others again, because one of them changed.
    func refresh() {
        applyRegistration()
    }

    // MARK: Registration

    /// Brings what macOS holds in line with the settings.
    private func applyRegistration() {
        let agents = agentShortcuts()
        let system = registrar?.systemShortcuts() ?? []
        let resting = NookDesignHotkeyRules.restingStatus(for: combo, agentShortcuts: agents, systemShortcuts: system)

        guard let registrar, let combo, resting == .inactive, isLive, !isRecording else {
            if registered != nil {
                registrar?.unregister()
                registered = nil
            }
            // While a recording runs the row keeps what it showed.
            if !isRecording, status != resting { status = resting }
            return
        }

        // Already live with this shortcut. Registering again would forget
        // that its key may still be held down.
        if registered == combo, status == .ready { return }

        switch registrar.register(combo, onPress: { [weak self] in self?.onPress?() }) {
        case .registered:
            registered = combo
            status = .ready
        case let .failed(code):
            registered = nil
            status = .failed(code: code)
        }
    }
}

// MARK: - Carbon

/// Four-letter tag macOS hands back with the eyedropper's hot key. The
/// agent shortcuts carry their own, and each handler passes on a press
/// that is not its own.
private let designHotkeySignature: OSType = 0x4F49_444B // "OIDK"
private let designHotkeyID: UInt32 = 1

private func designHotkeyEventHandler(
    _ call: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == designHotkeySignature, hotKeyID.id == designHotkeyID else {
        return OSStatus(eventNotHandledErr)
    }

    let isPress = GetEventKind(event) == UInt32(kEventHotKeyPressed)
    let registrar = Unmanaged<NookDesignCarbonHotkey>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        registrar.handle(isPress: isPress)
    }
    return noErr
}

/// The eyedropper's shortcut as a Carbon hot key, the same kind the agent
/// shortcuts use. It works in every app and needs no permission. What
/// macOS uses itself, and what a key is called, come from the agent
/// shortcuts' own registrar.
@MainActor
final class NookDesignCarbonHotkey: NookDesignHotkeyRegistering {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onPress: (@MainActor () -> Void)?
    /// A held key repeats, and a repeat must not count as a second press.
    private var isHeld = false
    private let system = CarbonHotkeyRegistrar()

    isolated deinit {
        unregister()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    func register(_ combo: AgentHotkeyCombo, onPress: @escaping @MainActor () -> Void) -> AgentHotkeyRegistrationOutcome {
        unregister()
        self.onPress = onPress

        let handlerStatus = installHandlerIfNeeded()
        guard handlerStatus == noErr else {
            designHotkeyLog.error("Could not install the eyedropper hot key handler: status \(handlerStatus, privacy: .public)")
            return .failed(code: handlerStatus)
        }

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode),
            CarbonHotkeyRegistrar.carbonModifiers(combo.modifiers),
            EventHotKeyID(signature: designHotkeySignature, id: designHotkeyID),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            // Most often another app holds these keys already.
            designHotkeyLog.error("macOS refused the eyedropper shortcut (key \(combo.keyCode, privacy: .public)): status \(status, privacy: .public)")
            return .failed(code: status)
        }
        hotKeyRef = ref
        return .registered
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        // A release of a key that is no longer registered never arrives.
        isHeld = false
    }

    func systemShortcuts() -> Set<AgentHotkeyCombo> {
        system.systemShortcuts()
    }

    func keyName(for keyCode: UInt16) -> String? {
        system.keyName(for: keyCode)
    }

    fileprivate func handle(isPress: Bool) {
        guard hotKeyRef != nil else { return }
        guard isPress else {
            isHeld = false
            return
        }
        guard !isHeld else { return }
        isHeld = true
        onPress?()
    }

    private func installHandlerIfNeeded() -> OSStatus {
        guard handlerRef == nil else { return noErr }
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        return InstallEventHandler(
            GetApplicationEventTarget(),
            designHotkeyEventHandler,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }
}
