import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Observation
import OSLog

private let recordHotkeyLog = Logger(subsystem: "app.openisland", category: "nook.record")

/// The Record shortcut registers the same way the eyedropper's does, so it
/// takes the same registrar shape. Its own Carbon key (below) keeps the two
/// from answering each other's presses.
typealias NookRecordHotkeyRegistering = NookDesignHotkeyRegistering

/// Why a shortcut cannot be the Record shortcut.
enum NookRecordHotkeyProblem: Equatable, Sendable {
    /// Fewer than two modifier keys, or neither Control nor Option. The
    /// same rule the agent shortcuts follow.
    case needsModifiers
    /// An agent shortcut or the eyedropper's already has these keys.
    case usedByAnotherShortcut

    var messageKey: String {
        switch self {
        case .needsModifiers: "settings.general.agentHotkeys.problem.needsModifiers"
        case .usedByAnotherShortcut: "nook.record.settings.hotkey.problem.taken"
        }
    }
}

/// Whether the Record shortcut is ready, for Settings.
enum NookRecordHotkeyStatus: Equatable, Sendable {
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
    case invalid(NookRecordHotkeyProblem)

    var isInvalid: Bool {
        if case .invalid = self { return true }
        return false
    }
}

/// Pure rules for the Record shortcut: the agent shortcuts' rules plus
/// "not a key another Hangover shortcut holds".
enum NookRecordHotkeyRules {
    /// Control Option R.
    static let defaultCombo = AgentHotkeyCombo(keyCode: UInt16(kVK_ANSI_R), modifiers: [.control, .option])

    static func problem(
        with combo: AgentHotkeyCombo,
        otherShortcuts: [AgentHotkeyCombo]
    ) -> NookRecordHotkeyProblem? {
        if AgentHotkeyRules.problem(with: combo) != nil { return .needsModifiers }
        return otherShortcuts.contains(combo) ? .usedByAnotherShortcut : nil
    }

    /// What Settings shows for a shortcut macOS was not asked about.
    static func restingStatus(
        for combo: AgentHotkeyCombo,
        otherShortcuts: [AgentHotkeyCombo],
        systemShortcuts: Set<AgentHotkeyCombo>
    ) -> NookRecordHotkeyStatus {
        if let problem = problem(with: combo, otherShortcuts: otherShortcuts) { return .invalid(problem) }
        return systemShortcuts.contains(combo) ? .usedBySystem : .inactive
    }
}

/// Owns the Record shortcut: the saved choice, its state with macOS and
/// when it is live. The keys are taken from other apps only while the
/// Record widget is switched on.
@MainActor
@Observable
final class NookRecordHotkeyController {
    nonisolated static let comboKey = "nook.record.hotkey"

    private(set) var combo: AgentHotkeyCombo
    private(set) var status: NookRecordHotkeyStatus = .inactive
    /// True while Settings records a new shortcut. Nothing is registered
    /// then, which keeps the press meant for the recorder from starting a
    /// recording.
    private(set) var isRecording = false

    /// Runs for each press that reaches the app.
    @ObservationIgnored var onPress: (() -> Void)?
    /// The approve and deny shortcuts and the eyedropper's, which this one
    /// may not take. The app model supplies them.
    @ObservationIgnored var otherShortcuts: () -> [AgentHotkeyCombo] = { [] }
    /// Tells the app model a recording began or ended, which lets it hold
    /// the agent shortcuts back for as long.
    @ObservationIgnored var onRecordingChange: (Bool) -> Void = { _ in }
    /// Tells the app model the keys or the live state changed. The eyedropper's
    /// shortcut checks itself against these keys again when they do.
    @ObservationIgnored var onShortcutsChange: () -> Void = {}
    /// Told once per shortcut when macOS refuses it, or already uses it. Settings
    /// shows it too, but nobody is looking at Settings when the widget is switched on.
    @ObservationIgnored var onRefused: (NookRecordHotkeyStatus) -> Void = { _ in }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var registrar: (any NookRecordHotkeyRegistering)?
    @ObservationIgnored private var isLive = false
    /// What macOS holds for the app right now.
    @ObservationIgnored private var registered: AgentHotkeyCombo?
    /// The shortcut a refusal was already reported for.
    @ObservationIgnored private var refusalReported: AgentHotkeyCombo?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        combo = defaults.string(forKey: Self.comboKey).flatMap(AgentHotkeyCombo.init(storageValue:))
            ?? NookRecordHotkeyRules.defaultCombo
        applyRegistration()
    }

    // MARK: Settings

    /// Saves a new shortcut. One that breaks a rule is not saved, and the
    /// rule it breaks is returned.
    @discardableResult
    func setCombo(_ combo: AgentHotkeyCombo) -> NookRecordHotkeyProblem? {
        if let problem = NookRecordHotkeyRules.problem(with: combo, otherShortcuts: otherShortcuts()) {
            return problem
        }
        guard self.combo != combo else { return nil }
        self.combo = combo
        defaults.set(combo.storageValue, forKey: Self.comboKey)
        applyRegistration()
        onShortcutsChange()
        return nil
    }

    /// Goes back to Control Option R.
    func resetToDefault() {
        guard combo != NookRecordHotkeyRules.defaultCombo else { return }
        combo = NookRecordHotkeyRules.defaultCombo
        defaults.removeObject(forKey: Self.comboKey)
        applyRegistration()
        onShortcutsChange()
    }

    /// "⌃⌥R" on the keyboard layout in use.
    var displayText: String {
        combo.displayText { [registrar] keyCode in
            AgentHotkeyKeyboard.fixedName(for: keyCode)
                ?? registrar?.keyName(for: keyCode)
                ?? AgentHotkeyKeyboard.usName(for: keyCode)
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
    func activate(registrar: any NookRecordHotkeyRegistering) {
        self.registrar = registrar
        applyRegistration()
    }

    /// Tells the controller whether the Record widget is switched on.
    func setLive(_ live: Bool) {
        guard live != isLive else { return }
        isLive = live
        // Switching it on again is a new try, and a refusal is told again.
        if !live { refusalReported = nil }
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
        let others = otherShortcuts()
        let system = registrar?.systemShortcuts() ?? []
        let resting = NookRecordHotkeyRules.restingStatus(for: combo, otherShortcuts: others, systemShortcuts: system)

        guard let registrar, resting == .inactive, isLive, !isRecording else {
            if registered != nil {
                registrar?.unregister()
                registered = nil
            }
            // While a recording runs the row keeps what it showed.
            if !isRecording, status != resting { status = resting }
            if resting == .usedBySystem, isLive, !isRecording { reportRefusal(resting) }
            return
        }

        // Already live with this shortcut. Registering again would forget
        // that its key may still be held down.
        if registered == combo, status == .ready { return }

        switch registrar.register(combo, onPress: { [weak self] in self?.onPress?() }) {
        case .registered:
            registered = combo
            status = .ready
            refusalReported = nil
        case let .failed(code):
            registered = nil
            status = .failed(code: code)
            reportRefusal(status)
        }
    }

    private func reportRefusal(_ status: NookRecordHotkeyStatus) {
        guard refusalReported != combo else { return }
        refusalReported = combo
        onRefused(status)
    }
}

// MARK: - Carbon

/// Four-letter tag macOS hands back with the Record hot key. The other
/// shortcuts carry their own, and each handler passes on a press that is
/// not its own.
private let recordHotkeySignature: OSType = 0x4F49_524B // "OIRK"
private let recordHotkeyID: UInt32 = 1

private func recordHotkeyEventHandler(
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
    guard status == noErr, hotKeyID.signature == recordHotkeySignature, hotKeyID.id == recordHotkeyID else {
        return OSStatus(eventNotHandledErr)
    }

    let isPress = GetEventKind(event) == UInt32(kEventHotKeyPressed)
    let registrar = Unmanaged<NookRecordCarbonHotkey>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        registrar.handle(isPress: isPress)
    }
    return noErr
}

/// The Record shortcut as a Carbon hot key, the same kind the agent
/// shortcuts use. It works in every app and needs no permission. What macOS
/// uses itself, and what a key is called, come from the agent shortcuts'
/// own registrar.
@MainActor
final class NookRecordCarbonHotkey: NookRecordHotkeyRegistering {
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
            recordHotkeyLog.error("Could not install the Record hot key handler: status \(handlerStatus, privacy: .public)")
            return .failed(code: handlerStatus)
        }

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode),
            CarbonHotkeyRegistrar.carbonModifiers(combo.modifiers),
            EventHotKeyID(signature: recordHotkeySignature, id: recordHotkeyID),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            // Most often another app holds these keys already.
            recordHotkeyLog.error("macOS refused the Record shortcut (key \(combo.keyCode, privacy: .public)): status \(status, privacy: .public)")
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
            recordHotkeyEventHandler,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }
}

// MARK: - App wiring

extension AppModel {
    /// Joins the Record widget to the parts of the app it must not own: the
    /// island's window and screen, and the other shortcuts, which the Record
    /// shortcut must stay clear of, and which must stay clear of it. Runs after
    /// `wireDesignKit`, whose checks it adds to.
    func wireRecord() {
        let record = nook.record
        let kit = nook.design
        record.surroundings = NookRecordSurroundings(
            displayID: { [weak self] in
                self?.islandScreen?.nookDisplayID ?? CGMainDisplayID()
            },
            islandWindows: { [weak self] in
                guard let number = self?.overlay.overlayPanelController.windowNumber else { return [] }
                return [CGWindowID(number)]
            }
        )
        // The agent shortcuts may not take the Record keys while the widget is on.
        let designReserved = agentHotkeys.reservedShortcuts
        agentHotkeys.reservedShortcuts = { [weak record] in
            designReserved() + (record?.reservedShortcuts ?? [])
        }
        // The Record shortcut stays clear of the agents' and the eyedropper's.
        // The eyedropper's keys count only while it can hold them: two shortcuts
        // each giving way to the other would leave neither working.
        record.hotkey.otherShortcuts = { [weak self, weak kit] in
            guard let self, let kit else { return [] }
            var others = AgentHotkeyAction.allCases.map { self.agentHotkeys.combo(for: $0) }
            if kit.isLive, !kit.hotkey.status.isInvalid, let combo = kit.hotkey.combo { others.append(combo) }
            return others
        }
        // And the eyedropper's shortcut stays clear of Record's. It checked the
        // agent shortcuts only, so Record's keys could be set as the eyedropper's.
        let agentChecks = kit.hotkey.agentShortcuts
        kit.hotkey.agentShortcuts = { [weak record] in
            agentChecks() + (record?.reservedShortcuts ?? [])
        }
        // When either one's keys or live state change, the other checks itself
        // against them again, or it would keep an old verdict until something
        // else moved.
        record.hotkey.onShortcutsChange = { [weak kit] in kit?.hotkey.refresh() }
        kit.hotkey.onShortcutsChange = { [weak record] in record?.hotkey.refresh() }
        // While the shortcut is being recorded the agent shortcuts are let go
        // of too. A press meant for the recorder must not approve a request.
        record.hotkey.onRecordingChange = { [weak self] isRecording in
            guard let hotkeys = self?.agentHotkeys else { return }
            if isRecording {
                hotkeys.beginRecording()
            } else {
                hotkeys.endRecording()
            }
        }
    }
}
