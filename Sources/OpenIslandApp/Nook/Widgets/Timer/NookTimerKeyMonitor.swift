import AppKit
import SwiftUI

/// What a key press means to the timer entry.
enum NookTimerKeyAction: Equatable {
    case insert(Character)
    case backspace
    case submit
    case cancel
}

/// Turns typing on the Nook page into timer entry, without a text field.
///
/// A local `keyDown` monitor exists only while the timer card is on screen.
/// It takes a digit only when the timer is idle, the key event belongs to
/// the key window that hosts the card, and no text view is first responder
/// (so the todo add field, the notes editor and the calendar quick add keep
/// their keys). Once an entry is open it also takes h, m, s, colon, space,
/// backspace, Return and Escape. Everything else goes through untouched.
@MainActor
final class NookTimerKeyMonitor {
    nonisolated(unsafe) private var token: Any?
    private var isEnabled: @MainActor () -> Bool = { false }
    private var isEntryActive: @MainActor () -> Bool = { false }
    private var perform: @MainActor (NookTimerKeyAction) -> Void = { _ in }

    /// The window that hosts the card, filled in by `NookTimerWindowReader`.
    weak var window: NSWindow?

    var isInstalled: Bool { token != nil }

    /// Installs the monitor. Calling it again only swaps the closures, so
    /// there is never more than one monitor.
    func install(
        isEnabled: @escaping @MainActor () -> Bool,
        isEntryActive: @escaping @MainActor () -> Bool,
        perform: @escaping @MainActor (NookTimerKeyAction) -> Void
    ) {
        self.isEnabled = isEnabled
        self.isEntryActive = isEntryActive
        self.perform = perform
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    func remove() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }

    deinit {
        if let token { NSEvent.removeMonitor(token) }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window,
              event.window === window,
              window.isKeyWindow,
              !(window.firstResponder is NSTextView),
              isEnabled()
        else { return event }

        guard let action = Self.action(
            characters: event.characters ?? "",
            keyCode: event.keyCode,
            modifiers: event.modifierFlags,
            isEntryActive: isEntryActive()
        ) else { return event }

        perform(action)
        return nil
    }

    // MARK: Key mapping

    private nonisolated static let returnKeyCodes: Set<UInt16> = [36, 76]
    private nonisolated static let escapeKeyCode: UInt16 = 53
    private nonisolated static let forwardDeleteKeyCode: UInt16 = 117
    private nonisolated static let backspaceKeyCodes: Set<UInt16> = [51, forwardDeleteKeyCode]
    /// Command, option, control and the Fn key all make a shortcut. Shift is
    /// allowed (a colon needs it), and so are caps lock and the keypad flag.
    private nonisolated static let blockingModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .function]

    /// What a key press does to the entry, nil when it is not ours. Pure so
    /// the tests can cover it without making events.
    nonisolated static func action(
        characters: String,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        isEntryActive: Bool
    ) -> NookTimerKeyAction? {
        // AppKit always sets .function on forward delete, so it is not a shortcut there.
        let blocking = keyCode == forwardDeleteKeyCode ? blockingModifiers.subtracting(.function) : blockingModifiers
        guard modifiers.intersection(blocking).isEmpty else { return nil }

        if isEntryActive {
            if returnKeyCodes.contains(keyCode) { return .submit }
            if keyCode == escapeKeyCode { return .cancel }
            if backspaceKeyCodes.contains(keyCode) { return .backspace }
        }

        guard characters.count == 1, let character = characters.first else { return nil }
        if NookTimerEntry.isDigit(character) { return .insert(character) }
        guard isEntryActive, NookTimerEntry.accepts(character) else { return nil }
        return .insert(character)
    }
}

/// Reports the window a SwiftUI view ends up in, so the monitor can tell the
/// island panel's keys from any other window's.
struct NookTimerWindowReader: NSViewRepresentable {
    var onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ReaderView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ReaderView)?.onChange = onChange
    }

    private final class ReaderView: NSView {
        var onChange: (NSWindow?) -> Void = { _ in }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onChange(window)
        }
    }
}
