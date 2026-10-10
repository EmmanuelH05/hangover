import Testing
@testable import OpenIslandApp

@Suite(.serialized)
struct KeystrokeInjectorTests {
    @Test
    func defaultInjectorHandsTheTabScriptToItsRunner() {
        // The runner is a recorder. Nothing here reaches AppleScript or
        // System Events.
        let recorder = ScriptRecorder()
        let injector = DefaultKeystrokeInjector(runScript: recorder.run)

        injector.sendCmdShiftRightBracket()

        #expect(recorder.sources.count == 1)
        let source = recorder.sources.first ?? ""
        #expect(source.contains(#"tell application id "dev.warp.Warp-Stable" to activate"#))
        #expect(source.contains(#"click menu item "Switch to Next Tab" of menu "Tab" of menu bar item "Tab" of menu bar 1"#))
        #expect(source == DefaultKeystrokeInjector.advanceTabScript)
    }

    @Test
    func aRunnerThatFailsDoesNotStopTheInjector() {
        let recorder = ScriptRecorder(failure: "Can't get application id")
        let injector = DefaultKeystrokeInjector(runScript: recorder.run)

        injector.sendCmdShiftRightBracket()
        injector.sendCmdShiftRightBracket()

        #expect(recorder.sources.count == 2)
    }

    @Test
    func spyKeystrokerRecordsCalls() {
        let spy = KeystrokeInjectorSpy()
        spy.sendCmdShiftRightBracket()
        spy.sendCmdShiftRightBracket()
        #expect(spy.callCount == 2)
    }
}

/// Stands in for the AppleScript runner and keeps the source it was given.
final class ScriptRecorder: @unchecked Sendable {
    private(set) var sources: [String] = []
    private let failure: String?

    init(failure: String? = nil) {
        self.failure = failure
    }

    func run(_ source: String) -> String? {
        sources.append(source)
        return failure
    }
}

final class KeystrokeInjectorSpy: KeystrokeInjector, @unchecked Sendable {
    var callCount = 0
    func sendCmdShiftRightBracket() {
        callCount += 1
    }
}
