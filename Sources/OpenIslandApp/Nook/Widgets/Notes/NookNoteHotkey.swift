import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Observation
import OSLog

private let noteHotkeyLog = Logger(subsystem: "app.openisland", category: "nook.notes")

/// The new note shortcut registers the same way the eyedropper's does, so it
/// takes the same registrar shape. Its own Carbon key (below) keeps the two
/// from answering each other's presses.
typealias NookNoteHotkeyRegistering = NookDesignHotkeyRegistering

/// Why a shortcut cannot be the new note shortcut.
enum NookNoteHotkeyProblem: Equatable, Sendable {
    /// Fewer than two modifier keys, or neither Control nor Option. The
    /// same rule the agent shortcuts follow.
    case needsModifiers
    /// An agent shortcut, Record's or the eyedropper's already has these keys.
    case usedByAnotherShortcut

    var messageKey: String {
        switch self {
        case .needsModifiers: "settings.general.agentHotkeys.problem.needsModifiers"
        case .usedByAnotherShortcut: "nook.notes.settings.hotkey.problem.taken"
        }
    }
}

/// Whether the new note shortcut is ready, for Settings.
enum NookNoteHotkeyStatus: Equatable, Sendable {
    /// Set, and macOS is not holding it: the app never asked (tests and
    /// harness runs).
    case inactive
    /// macOS accepted it. It works from any app.
    case ready
    /// macOS refused it, with its error code.
    case failed(code: Int32)
    /// A macOS shortcut of its own already uses these keys.
    case usedBySystem
    /// The saved shortcut breaks a rule.
    case invalid(NookNoteHotkeyProblem)
}

/// Pure rules for the new note shortcut: the agent shortcuts' rules plus
/// "not a key another Hangover shortcut holds".
enum NookNoteHotkeyRules {
    /// Control Option J. Control Option N is the agents' Deny.
    static let defaultCombo = AgentHotkeyCombo(keyCode: UInt16(kVK_ANSI_J), modifiers: [.control, .option])

    static func problem(
        with combo: AgentHotkeyCombo,
        otherShortcuts: [AgentHotkeyCombo]
    ) -> NookNoteHotkeyProblem? {
        if AgentHotkeyRules.problem(with: combo) != nil { return .needsModifiers }
        return otherShortcuts.contains(combo) ? .usedByAnotherShortcut : nil
    }

    /// What Settings shows for a shortcut macOS was not asked about.
    static func restingStatus(
        for combo: AgentHotkeyCombo,
        otherShortcuts: [AgentHotkeyCombo],
        systemShortcuts: Set<AgentHotkeyCombo>
    ) -> NookNoteHotkeyStatus {
        if let problem = problem(with: combo, otherShortcuts: otherShortcuts) { return .invalid(problem) }
        return systemShortcuts.contains(combo) ? .usedBySystem : .inactive
    }
}

/// Owns the new note shortcut: the saved choice, its state with macOS and
/// when it is live. Unlike Record's and the eyedropper's it is held whether
/// or not the Notes widget is on the page, which is what lets a note start
/// from any app.
@MainActor
@Observable
final class NookNoteHotkeyController {
    nonisolated static let comboKey = "nook.notes.newNoteHotkey"

    private(set) var combo: AgentHotkeyCombo
    private(set) var status: NookNoteHotkeyStatus = .inactive
    /// True while Settings records a new shortcut. Nothing is registered
    /// then, which keeps the press meant for the recorder from starting a note.
    private(set) var isRecording = false

    /// Runs for each press that reaches the app.
    @ObservationIgnored var onPress: (() -> Void)?
    /// The approve and deny shortcuts, Record's and the eyedropper's, which
    /// this one may not take. The app model supplies them.
    @ObservationIgnored var otherShortcuts: () -> [AgentHotkeyCombo] = { [] }
    /// Tells the app model a recording began or ended, which lets it hold
    /// the agent shortcuts back for as long.
    @ObservationIgnored var onRecordingChange: (Bool) -> Void = { _ in }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var registrar: (any NookNoteHotkeyRegistering)?
    /// What macOS holds for the app right now.
    @ObservationIgnored private var registered: AgentHotkeyCombo?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        combo = defaults.string(forKey: Self.comboKey).flatMap(AgentHotkeyCombo.init(storageValue:))
            ?? NookNoteHotkeyRules.defaultCombo
        applyRegistration()
    }

    // MARK: Settings

    /// Saves a new shortcut. One that breaks a rule is not saved, and the
    /// rule it breaks is returned.
    @discardableResult
    func setCombo(_ combo: AgentHotkeyCombo) -> NookNoteHotkeyProblem? {
        if let problem = NookNoteHotkeyRules.problem(with: combo, otherShortcuts: otherShortcuts()) {
            return problem
        }
        guard self.combo != combo else { return nil }
        self.combo = combo
        defaults.set(combo.storageValue, forKey: Self.comboKey)
        applyRegistration()
        return nil
    }

    /// Goes back to Control Option J.
    func resetToDefault() {
        guard combo != NookNoteHotkeyRules.defaultCombo else { return }
        combo = NookNoteHotkeyRules.defaultCombo
        defaults.removeObject(forKey: Self.comboKey)
        applyRegistration()
    }

    /// "⌃⌥J" on the keyboard layout in use.
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
    func activate(registrar: any NookNoteHotkeyRegistering) {
        self.registrar = registrar
        applyRegistration()
    }

    /// Looks at the other shortcuts again, for when one of them changed.
    func refresh() {
        applyRegistration()
    }

    // MARK: Registration

    /// Brings what macOS holds in line with the settings.
    private func applyRegistration() {
        let others = otherShortcuts()
        let system = registrar?.systemShortcuts() ?? []
        let resting = NookNoteHotkeyRules.restingStatus(for: combo, otherShortcuts: others, systemShortcuts: system)

        guard let registrar, resting == .inactive, !isRecording else {
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

/// Four-letter tag macOS hands back with the new note hot key. The other
/// shortcuts carry their own, and each handler passes on a press that is
/// not its own.
private let noteHotkeySignature: OSType = 0x4F49_4E4B // "OINK"
private let noteHotkeyID: UInt32 = 1

private func noteHotkeyEventHandler(
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
    guard status == noErr, hotKeyID.signature == noteHotkeySignature, hotKeyID.id == noteHotkeyID else {
        return OSStatus(eventNotHandledErr)
    }

    let isPress = GetEventKind(event) == UInt32(kEventHotKeyPressed)
    let registrar = Unmanaged<NookNoteCarbonHotkey>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        registrar.handle(isPress: isPress)
    }
    return noErr
}

/// The new note shortcut as a Carbon hot key, the same kind the agent
/// shortcuts use. It works in every app and needs no permission. What macOS
/// uses itself, and what a key is called, come from the agent shortcuts'
/// own registrar.
@MainActor
final class NookNoteCarbonHotkey: NookNoteHotkeyRegistering {
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
            noteHotkeyLog.error("Could not install the new note hot key handler: status \(handlerStatus, privacy: .public)")
            return .failed(code: handlerStatus)
        }

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode),
            CarbonHotkeyRegistrar.carbonModifiers(combo.modifiers),
            EventHotKeyID(signature: noteHotkeySignature, id: noteHotkeyID),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            // Most often another app holds these keys already.
            noteHotkeyLog.error("macOS refused the new note shortcut (key \(combo.keyCode, privacy: .public)): status \(status, privacy: .public)")
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
            noteHotkeyEventHandler,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }
}
