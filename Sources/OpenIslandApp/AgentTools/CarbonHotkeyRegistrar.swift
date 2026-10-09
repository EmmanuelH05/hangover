import AppKit
import Carbon.HIToolbox
import OSLog

private let hotkeyLog = Logger(subsystem: "app.openisland", category: "agentHotkeys")

/// Four-letter tag macOS hands back with each of the app's hot keys.
private let agentHotkeySignature: OSType = 0x4F49_4148 // "OIAH"

/// Carbon calls this for every hot key press and release in the app.
private func agentHotkeyEventHandler(
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
    guard status == noErr, hotKeyID.signature == agentHotkeySignature else {
        return OSStatus(eventNotHandledErr)
    }

    let id = hotKeyID.id
    let isPress = GetEventKind(event) == UInt32(kEventHotKeyPressed)
    // When the key went down, which can be a moment before this runs. A
    // press is judged by that time: one made before a card changed must
    // not count as made after it.
    let age = max(0, GetCurrentEventTime() - GetEventTime(event))
    let happenedAt = Date.now.addingTimeInterval(-age)
    let registrar = Unmanaged<CarbonHotkeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        registrar.handle(id: id, isPress: isPress, at: happenedAt)
    }
    return noErr
}

/// Global shortcuts through Carbon hot keys. They work in every app and
/// need no permission. The keys are taken from other apps only while they
/// are registered.
@MainActor
final class CarbonHotkeyRegistrar: AgentHotkeyRegistering {
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?
    private var onPress: (@MainActor (AgentHotkeyAction, Date) -> Void)?
    /// Hot keys that are down. A held key repeats, and a repeat must not
    /// count as a second press.
    private var heldIDs: Set<UInt32> = []

    isolated deinit {
        unregisterAll()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    func register(
        _ combos: [AgentHotkeyAction: AgentHotkeyCombo],
        onPress: @escaping @MainActor (AgentHotkeyAction, Date) -> Void
    ) -> [AgentHotkeyAction: AgentHotkeyRegistrationOutcome] {
        unregisterAll()
        self.onPress = onPress

        var outcomes: [AgentHotkeyAction: AgentHotkeyRegistrationOutcome] = [:]
        let handlerStatus = installHandlerIfNeeded()
        guard handlerStatus == noErr else {
            hotkeyLog.error("Could not install the hot key handler: status \(handlerStatus, privacy: .public)")
            for action in combos.keys { outcomes[action] = .failed(code: handlerStatus) }
            return outcomes
        }

        for (action, combo) in combos {
            let id = Self.id(for: action)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(combo.keyCode),
                Self.carbonModifiers(combo.modifiers),
                EventHotKeyID(signature: agentHotkeySignature, id: id),
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                hotKeyRefs[id] = ref
                outcomes[action] = .registered
            } else {
                // Most often another app holds these keys already.
                hotkeyLog.error(
                    "macOS refused the \(action.rawValue, privacy: .public) shortcut (key \(combo.keyCode, privacy: .public)): status \(status, privacy: .public)"
                )
                outcomes[action] = .failed(code: status)
            }
        }
        return outcomes
    }

    func unregisterAll() {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs = [:]
        // A release of a key that is no longer registered never arrives.
        heldIDs = []
    }

    func systemShortcuts() -> Set<AgentHotkeyCombo> {
        var copied: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&copied)
        guard status == noErr,
              let entries = copied?.takeRetainedValue() as? [[String: Any]] else {
            // An empty answer here reads as "macOS uses none of them", which
            // is not known. The log keeps the difference.
            hotkeyLog.error("Could not read the shortcuts macOS uses itself: status \(status, privacy: .public)")
            return []
        }

        var result = Set<AgentHotkeyCombo>()
        for entry in entries {
            guard (entry["kHISymbolicHotKeyEnabled"] as? Bool) == true,
                  let keyCode = entry["kHISymbolicHotKeyCode"] as? Int,
                  let modifiers = entry["kHISymbolicHotKeyModifiers"] as? Int,
                  keyCode >= 0, keyCode <= Int(UInt16.max) else {
                continue
            }
            result.insert(AgentHotkeyCombo(keyCode: UInt16(keyCode), modifiers: Self.modifiers(fromCarbon: modifiers)))
        }
        return result
    }

    func keyName(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawLayout = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(rawLayout).takeUnretainedValue() as Data

        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(1 << kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let name = String(utf16CodeUnits: characters, count: length)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return name.isEmpty ? nil : name
    }

    fileprivate func handle(id: UInt32, isPress: Bool, at time: Date) {
        guard hotKeyRefs[id] != nil else { return }
        guard isPress else {
            heldIDs.remove(id)
            return
        }
        guard heldIDs.insert(id).inserted, let action = Self.action(for: id) else { return }
        onPress?(action, time)
    }

    private func installHandlerIfNeeded() -> OSStatus {
        guard handlerRef == nil else { return noErr }
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        return InstallEventHandler(
            GetApplicationEventTarget(),
            agentHotkeyEventHandler,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }

    private static func id(for action: AgentHotkeyAction) -> UInt32 {
        action == .approve ? 1 : 2
    }

    private static func action(for id: UInt32) -> AgentHotkeyAction? {
        switch id {
        case 1: .approve
        case 2: .deny
        default: nil
        }
    }

    private static func carbonModifiers(_ modifiers: AgentHotkeyModifiers) -> UInt32 {
        var result = 0
        if modifiers.contains(.control) { result |= controlKey }
        if modifiers.contains(.option) { result |= optionKey }
        if modifiers.contains(.shift) { result |= shiftKey }
        if modifiers.contains(.command) { result |= cmdKey }
        return UInt32(result)
    }

    private static func modifiers(fromCarbon carbon: Int) -> AgentHotkeyModifiers {
        var result: AgentHotkeyModifiers = []
        if carbon & controlKey != 0 { result.insert(.control) }
        if carbon & optionKey != 0 { result.insert(.option) }
        if carbon & shiftKey != 0 { result.insert(.shift) }
        if carbon & cmdKey != 0 { result.insert(.command) }
        return result
    }
}

extension AgentHotkeyModifiers {
    /// The modifiers of a key event, for the recorder in Settings.
    init(eventFlags flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.command) { insert(.command) }
    }
}
