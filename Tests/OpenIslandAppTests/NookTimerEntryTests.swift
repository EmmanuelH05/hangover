import AppKit
import Foundation
import Testing
@testable import OpenIslandApp

struct NookTimerEntryTests {
    private func seconds(_ text: String) -> TimeInterval? {
        NookTimerEntry.parse(text)
    }

    // MARK: Plain minutes

    @Test(arguments: [("25", 1500.0), ("90", 5400.0), ("1", 60.0), ("5", 300.0), ("007", 420.0), ("1440", 86400.0)])
    func plainNumberIsMinutes(text: String, expected: TimeInterval) {
        #expect(seconds(text) == expected)
    }

    // MARK: h:mm

    @Test(arguments: [("1:30", 5400.0), ("0:45", 2700.0), ("2:00", 7200.0), ("12:05", 43500.0),
                      ("1:05", 3900.0), ("1:5", 3900.0), ("0:01", 60.0), ("24:00", 86400.0), ("0:59", 3540.0)])
    func hourMinuteForm(text: String, expected: TimeInterval) {
        #expect(seconds(text) == expected)
    }

    @Test(arguments: ["1:75", "1:60", "0:99", "1:", ":30", ":", "1:30:00", "1::30", "25:00", "24:01", "0:00", "1:3x", "1:123"])
    func badHourMinuteFormIsNil(text: String) {
        #expect(seconds(text) == nil)
    }

    // MARK: Unit forms

    @Test(arguments: [("1h", 3600.0), ("1h30", 5400.0), ("1h30m", 5400.0), ("45m", 2700.0), ("90s", 90.0),
                      ("2h 15m", 8100.0), ("1h 5m 30s", 3930.0), ("1h5", 3900.0), ("1h 30", 5400.0),
                      ("30s", 30.0), ("1s", 1.0), ("90m", 5400.0), ("2h30s", 7230.0), ("1m30s", 90.0),
                      ("24h", 86400.0), ("1h90m", 9000.0), ("0h30m", 1800.0), ("3600s", 3600.0)])
    func unitForms(text: String, expected: TimeInterval) {
        #expect(seconds(text) == expected)
    }

    @Test(arguments: ["25x", "25h1", "h", "m", "s", "1h30m5", "1m30", "30s1m", "1h1h", "1m1h", "1s1s", "1h75", "1.5h",
                      "1h-30m", "1h,30m", "5 minutes", "1hr", "1hm", "1hh", "h30", "-5", "+5", "1e3", "25m x"])
    func badUnitFormIsNil(text: String) {
        #expect(seconds(text) == nil)
    }

    // MARK: Case and spaces

    @Test(arguments: [("1H30M", 5400.0), (" 25 ", 1500.0), ("  1:30\n", 5400.0), ("2 h 15 m", 8100.0),
                      ("1 H 5 M 30 S", 3930.0), ("\t45m", 2700.0), ("1 : 30", 5400.0), ("2 5", 1500.0)])
    func ignoresCaseAndSpaces(text: String, expected: TimeInterval) {
        #expect(seconds(text) == expected)
    }

    // MARK: Invalid, zero and range

    @Test(arguments: ["", "   ", "abc", "1:75", "25x", "0", "25h", "00", "0m", "0s", "0h0m0s", "0:00"])
    func invalidInputIsNil(text: String) {
        #expect(seconds(text) == nil)
    }

    @Test func limitIsTwentyFourHours() {
        #expect(seconds("24h") == 86_400)
        #expect(seconds("1440") == 86_400)
        #expect(seconds("86400s") == 86_400)
        #expect(seconds("23h59m59s") == 86_399)
        #expect(seconds("24h1s") == nil)
        #expect(seconds("1441") == nil)
        #expect(seconds("86401s") == nil)
        #expect(seconds("25h") == nil)
    }

    @Test func hugeNumbersAreNilNotACrash() {
        #expect(seconds("99999999999999999999") == nil)
        #expect(seconds("9999999") == nil)
        #expect(seconds("999999999999h") == nil)
        #expect(seconds("999999:00") == nil)
        #expect(seconds("1h99999999999999999999m") == nil)
    }

    @Test func nonASCIIInputIsNil() {
        #expect(seconds("٢٥") == nil)
        #expect(seconds("２５") == nil)
        #expect(seconds("25分") == nil)
    }

    // MARK: Entry characters

    @Test(arguments: Array("0123456789 :hmsHMS"))
    func entryAcceptsItsCharacters(character: Character) {
        #expect(NookTimerEntry.accepts(character))
    }

    @Test(arguments: Array("abcdefgijklnopqrtuvwxyz.,-+/;!?"))
    func entryRejectsOtherCharacters(character: Character) {
        #expect(!NookTimerEntry.accepts(character))
    }

    // MARK: Entry state

    @MainActor
    @Test func entryStartsEmptyAndClosed() {
        let entry = NookTimerEntryState()
        #expect(entry.text == nil)
        #expect(!entry.isActive)
        #expect(!entry.isInvalid)
    }

    @MainActor
    @Test func beginWithSeedKeepsThatDigit() {
        let entry = NookTimerEntryState()
        entry.begin(with: "4")
        #expect(entry.text == "4")
        #expect(entry.isActive)
    }

    @MainActor
    @Test func typingBuildsTextAndBackspaceRemoves() {
        let entry = NookTimerEntryState()
        entry.begin(with: "1")
        for character in "H30M" { entry.append(character) }
        #expect(entry.text == "1h30m")
        entry.deleteLast()
        #expect(entry.text == "1h30")
        entry.deleteLast()
        entry.deleteLast()
        entry.deleteLast()
        entry.deleteLast()
        #expect(entry.text == "")
        #expect(entry.isActive)
    }

    @MainActor
    @Test func entryIgnoresCharactersItDoesNotTake() {
        let entry = NookTimerEntryState()
        entry.begin()
        entry.append("x")
        entry.append("-")
        entry.append("2")
        #expect(entry.text == "2")
    }

    @MainActor
    @Test func entryStopsAtMaxLength() {
        let entry = NookTimerEntryState()
        entry.begin()
        for _ in 0..<(NookTimerEntryState.maxLength + 5) { entry.append("1") }
        #expect(entry.text?.count == NookTimerEntryState.maxLength)
    }

    @MainActor
    @Test func appendWhileClosedDoesNothing() {
        let entry = NookTimerEntryState()
        entry.append("5")
        entry.deleteLast()
        #expect(entry.text == nil)
    }

    @MainActor
    @Test func validSubmitReturnsLengthAndCloses() {
        let entry = NookTimerEntryState()
        entry.begin(with: "9")
        entry.append("0")
        #expect(entry.submit() == 5400)
        #expect(!entry.isActive)
        #expect(!entry.isInvalid)
    }

    @MainActor
    @Test func invalidSubmitStaysOpenAndFlagsThenTypingClears() {
        let entry = NookTimerEntryState()
        entry.begin(with: "1")
        for character in ":75" { entry.append(character) }
        #expect(entry.submit() == nil)
        #expect(entry.isActive)
        #expect(entry.isInvalid)
        #expect(entry.text == "1:75")
        entry.deleteLast()
        #expect(!entry.isInvalid)
        #expect(entry.text == "1:7")
    }

    @MainActor
    @Test func emptySubmitIsInvalid() {
        let entry = NookTimerEntryState()
        entry.begin()
        #expect(entry.submit() == nil)
        #expect(entry.isActive)
        #expect(entry.isInvalid)
    }

    @MainActor
    @Test func cancelClosesAndClearsInvalid() {
        let entry = NookTimerEntryState()
        entry.begin(with: "0")
        _ = entry.submit()
        entry.cancel()
        #expect(entry.text == nil)
        #expect(!entry.isInvalid)
    }

    // MARK: Key mapping

    private func action(
        _ characters: String,
        keyCode: UInt16 = 0,
        modifiers: NSEvent.ModifierFlags = [],
        active: Bool = false
    ) -> NookTimerKeyAction? {
        NookTimerKeyMonitor.action(characters: characters, keyCode: keyCode, modifiers: modifiers, isEntryActive: active)
    }

    @Test(arguments: Array("0123456789"))
    func idleDigitStartsEntry(digit: Character) {
        #expect(action(String(digit)) == .insert(digit))
    }

    @Test func idleKeysThatAreNotDigitsPassThrough() {
        for key in ["a", "h", "m", "s", ":", " ", "x", "-", ""] {
            #expect(action(key) == nil)
        }
        #expect(action("\r", keyCode: 36) == nil)
        #expect(action("\u{1B}", keyCode: 53) == nil)
        #expect(action("\u{7F}", keyCode: 51) == nil)
    }

    @Test func shortcutsAreNeverTaken() {
        for flag in [NSEvent.ModifierFlags.command, .option, .control, .function] {
            #expect(action("5", modifiers: flag) == nil)
            #expect(action("5", modifiers: [flag, .shift]) == nil)
            #expect(action("5", modifiers: flag, active: true) == nil)
            #expect(action("\r", keyCode: 36, modifiers: flag, active: true) == nil)
            #expect(action("\u{1B}", keyCode: 53, modifiers: flag, active: true) == nil)
        }
    }

    @Test func shiftCapsLockAndKeypadStillCount() {
        #expect(action("5", modifiers: .shift) == .insert("5"))
        #expect(action("5", modifiers: .capsLock) == .insert("5"))
        #expect(action("5", modifiers: .numericPad) == .insert("5"))
        #expect(action(":", modifiers: .shift, active: true) == .insert(":"))
    }

    @Test func activeEntryTakesItsKeys() {
        for key in ["7", "h", "m", "s", "H", "M", "S", ":", " "] {
            #expect(action(key, active: true) == .insert(Character(key)))
        }
        #expect(action("\r", keyCode: 36, active: true) == .submit)
        #expect(action("\u{3}", keyCode: 76, active: true) == .submit)
        #expect(action("\u{1B}", keyCode: 53, active: true) == .cancel)
        #expect(action("\u{7F}", keyCode: 51, active: true) == .backspace)
        #expect(action("\u{F728}", keyCode: 117, active: true) == .backspace)
        // Real forward-delete events carry the Fn flag.
        #expect(action("\u{F728}", keyCode: 117, modifiers: .function, active: true) == .backspace)
    }

    @Test func activeEntryLeavesOtherKeysAlone() {
        for key in ["a", "x", "z", "-", ".", "\t", "\u{F700}"] {
            #expect(action(key, active: true) == nil)
        }
        #expect(action("ab", active: true) == nil)
        #expect(action("", active: true) == nil)
    }
}

// MARK: - Monitor through NSApplication

/// A window that reports itself key, so the monitor can be driven without
/// activating the test process.
private final class KeyReportingWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}

@MainActor
struct NookTimerKeyMonitorTests {
    private static func makeWindow() -> KeyReportingWindow {
        KeyReportingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
    }

    private static func send(_ characters: String, keyCode: UInt16, to window: NSWindow) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ) else { return }
        NSApp.sendEvent(event)
    }

    @Test func takesKeysOnlyForItsOwnKeyWindowAndIdleTimer() {
        _ = NSApplication.shared
        let window = Self.makeWindow()
        let other = Self.makeWindow()
        let monitor = NookTimerKeyMonitor()
        monitor.window = window
        var received: [NookTimerKeyAction] = []
        var isEnabled = true
        let install = {
            monitor.install(isEnabled: { isEnabled }, isEntryActive: { !received.isEmpty }, perform: { received.append($0) })
        }
        // Installing twice still leaves one monitor: each key arrives once.
        install()
        install()
        defer { monitor.remove() }
        #expect(monitor.isInstalled)

        Self.send("5", keyCode: 23, to: other)
        #expect(received.isEmpty)

        Self.send("5", keyCode: 23, to: window)
        Self.send("h", keyCode: 4, to: window)
        Self.send("\r", keyCode: 36, to: window)
        #expect(received == [.insert("5"), .insert("h"), .submit])

        received.removeAll()
        isEnabled = false
        Self.send("6", keyCode: 22, to: window)
        #expect(received.isEmpty)
        isEnabled = true

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        window.contentView?.addSubview(textView)
        window.makeFirstResponder(textView)
        Self.send("8", keyCode: 28, to: window)
        #expect(received.isEmpty)
        window.makeFirstResponder(nil)

        monitor.remove()
        #expect(!monitor.isInstalled)
        Self.send("7", keyCode: 26, to: window)
        #expect(received.isEmpty)
    }
}
