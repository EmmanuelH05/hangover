import Foundation
import Testing
@testable import OpenIslandApp

// MARK: - The eyedropper's shortcut

@MainActor
@Suite struct NookDesignHotkeyTests {
    private static let combo = AgentHotkeyCombo(keyCode: 8, modifiers: [.control, .option])
    private static let approve = AgentHotkeySettings.defaultApprove

    private func controller(
        _ defaults: MemoryDefaults = MemoryDefaults(),
        registrar: FakeDesignHotkeyRegistrar? = nil,
        live: Bool = true
    ) -> NookDesignHotkeyController {
        let controller = NookDesignHotkeyController(defaults: defaults)
        controller.agentShortcuts = { [Self.approve, AgentHotkeySettings.defaultDeny] }
        if let registrar { controller.activate(registrar: registrar) }
        controller.setLive(live)
        return controller
    }

    @Test func thereIsNoShortcutUntilOneIsChosen() {
        let registrar = FakeDesignHotkeyRegistrar()
        let hotkey = controller(registrar: registrar)

        #expect(hotkey.combo == nil)
        #expect(hotkey.status == .none)
        #expect(hotkey.displayText == nil)
        #expect(registrar.registerCount == 0)
        #expect(registrar.registered == nil)
    }

    @Test func aChosenShortcutIsSavedAndRegisteredWhileTheWidgetIsOn() {
        let defaults = MemoryDefaults()
        let registrar = FakeDesignHotkeyRegistrar()
        let hotkey = controller(defaults, registrar: registrar)

        #expect(hotkey.setCombo(Self.combo) == nil)

        #expect(hotkey.combo == Self.combo)
        #expect(hotkey.status == .ready)
        #expect(hotkey.displayText == "⌃⌥C")
        #expect(registrar.registered == Self.combo)
        #expect(defaults.all.keys.sorted() == [NookDesignHotkeyController.comboKey])
        #expect(defaults.string(forKey: NookDesignHotkeyController.comboKey) == Self.combo.storageValue)

        // The next launch reads it back.
        let next = NookDesignHotkeyController(defaults: defaults)
        #expect(next.combo == Self.combo)
        #expect(next.status == .inactive)
    }

    @Test func theKeysAreHeldOnlyWhileTheWidgetIsOn() {
        let registrar = FakeDesignHotkeyRegistrar()
        let hotkey = controller(registrar: registrar, live: false)

        hotkey.setCombo(Self.combo)
        #expect(hotkey.status == .inactive)
        #expect(registrar.registered == nil)
        #expect(registrar.registerCount == 0)

        hotkey.setLive(true)
        #expect(hotkey.status == .ready)
        #expect(registrar.registered == Self.combo)

        hotkey.setLive(false)
        #expect(hotkey.status == .inactive)
        #expect(registrar.registered == nil)
    }

    @Test func withoutTheSystemRegistrarNothingIsEverRegistered() {
        let hotkey = controller()
        hotkey.setCombo(Self.combo)
        #expect(hotkey.status == .inactive)
    }

    @Test func aPressStartsAPick() {
        let registrar = FakeDesignHotkeyRegistrar()
        let hotkey = controller(registrar: registrar)
        var presses = 0
        hotkey.onPress = { presses += 1 }

        registrar.press()
        #expect(presses == 0)
        hotkey.setCombo(Self.combo)
        registrar.press()
        #expect(presses == 1)
    }

    @Test func aShortcutNeedsTwoModifiersWithControlOrOption() {
        let registrar = FakeDesignHotkeyRegistrar()
        let hotkey = controller(registrar: registrar)

        for modifiers: AgentHotkeyModifiers in [[], [.control], [.option], [.command, .shift]] {
            let problem = hotkey.setCombo(AgentHotkeyCombo(keyCode: 8, modifiers: modifiers))
            #expect(problem == .needsModifiers, "\(modifiers.symbols)")
        }
        #expect(hotkey.combo == nil)
        #expect(registrar.registerCount == 0)
        #expect(hotkey.setCombo(AgentHotkeyCombo(keyCode: 8, modifiers: [.command, .option])) == nil)
    }

    @Test func itMayNotBeAnAgentShortcut() {
        let registrar = FakeDesignHotkeyRegistrar()
        let hotkey = controller(registrar: registrar)
        hotkey.setCombo(Self.combo)

        #expect(hotkey.setCombo(Self.approve) == .usedByAgentShortcut)
        #expect(hotkey.setCombo(AgentHotkeySettings.defaultDeny) == .usedByAgentShortcut)

        // The shortcut it had is kept and stays registered.
        #expect(hotkey.combo == Self.combo)
        #expect(registrar.registered == Self.combo)
        #expect(NookDesignHotkeyProblem.usedByAgentShortcut.messageKey == "nook.design.hotkey.problem.agent")
    }

    @Test func aShortcutMacOSUsesItselfIsNotRegistered() {
        let registrar = FakeDesignHotkeyRegistrar()
        registrar.system = [Self.combo]
        let hotkey = controller(registrar: registrar)

        #expect(hotkey.setCombo(Self.combo) == nil)
        #expect(hotkey.status == .usedBySystem)
        #expect(registrar.registered == nil)
        #expect(registrar.registerCount == 0)
    }

    @Test func aShortcutMacOSRefusesShowsItsCode() {
        let registrar = FakeDesignHotkeyRegistrar()
        registrar.refusalCode = -9878
        let hotkey = controller(registrar: registrar)

        hotkey.setCombo(Self.combo)
        #expect(hotkey.status == .failed(code: -9878))

        // Another shortcut is tried afresh.
        registrar.refusalCode = nil
        hotkey.setCombo(AgentHotkeyCombo(keyCode: 9, modifiers: [.control, .option]))
        #expect(hotkey.status == .ready)
    }

    @Test func recordingLetsGoOfTheKeysAndTellsTheApp() {
        let registrar = FakeDesignHotkeyRegistrar()
        let hotkey = controller(registrar: registrar)
        hotkey.setCombo(Self.combo)
        var changes: [Bool] = []
        hotkey.onRecordingChange = { changes.append($0) }

        hotkey.beginRecording()
        hotkey.beginRecording()
        #expect(hotkey.isRecording)
        #expect(registrar.registered == nil)

        hotkey.endRecording()
        hotkey.endRecording()
        #expect(!hotkey.isRecording)
        #expect(registrar.registered == Self.combo)
        #expect(hotkey.status == .ready)
        #expect(changes == [true, false])
    }

    @Test func clearingGoesBackToNoShortcut() {
        let defaults = MemoryDefaults()
        let registrar = FakeDesignHotkeyRegistrar()
        let hotkey = controller(defaults, registrar: registrar)
        hotkey.setCombo(Self.combo)

        hotkey.clear()

        #expect(hotkey.combo == nil)
        #expect(hotkey.status == .none)
        #expect(registrar.registered == nil)
        #expect(defaults.all.isEmpty)
    }

    @Test func aSavedShortcutThatBreaksARuleIsShownAsInvalidAndNotRegistered() {
        let defaults = MemoryDefaults()
        defaults.set(Self.approve.storageValue, forKey: NookDesignHotkeyController.comboKey)
        let registrar = FakeDesignHotkeyRegistrar()
        let hotkey = controller(defaults, registrar: registrar)

        #expect(hotkey.status == .invalid(.usedByAgentShortcut))
        #expect(registrar.registered == nil)

        defaults.set("not a shortcut", forKey: NookDesignHotkeyController.comboKey)
        #expect(NookDesignHotkeyController(defaults: defaults).combo == nil)
    }

    @Test func theRulesAreTheAgentShortcutsRulesPlusOne() {
        let agents = [Self.approve]
        #expect(NookDesignHotkeyRules.problem(with: Self.combo, agentShortcuts: agents) == nil)
        #expect(NookDesignHotkeyRules.problem(with: Self.approve, agentShortcuts: agents) == .usedByAgentShortcut)
        #expect(NookDesignHotkeyRules.restingStatus(for: nil, agentShortcuts: agents, systemShortcuts: []) == .none)
        #expect(NookDesignHotkeyRules.restingStatus(for: Self.combo, agentShortcuts: agents, systemShortcuts: []) == .inactive)
        #expect(NookDesignHotkeyRules.restingStatus(for: Self.combo, agentShortcuts: agents, systemShortcuts: [Self.combo]) == .usedBySystem)
    }

    @Test func switchingTheWidgetOnAndOffMovesTheShortcutWithIt() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        fixture.kit.hotkey.setCombo(Self.combo)
        #expect(fixture.registrar.registered == Self.combo)

        // The press reaches the eyedropper.
        fixture.registrar.press()
        #expect(fixture.sampler.sampleCount == 1)
        fixture.sampler.finish(nil)

        fixture.kit.setLive(false)
        #expect(fixture.registrar.registered == nil)
        fixture.kit.setLive(true)
        #expect(fixture.registrar.registered == Self.combo)
    }
}
