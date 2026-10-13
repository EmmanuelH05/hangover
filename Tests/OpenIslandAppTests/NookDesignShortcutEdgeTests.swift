import Foundation
import Testing
@testable import OpenIslandApp

// MARK: - The eyedropper's shortcut

@MainActor
@Suite struct NookDesignShortcutEdgeTests {
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

    @Test func theSameShortcutChosenAgainRegistersNothingNew() {
        let registrar = FakeDesignHotkeyRegistrar()
        let hotkey = controller(registrar: registrar)

        hotkey.setCombo(Self.combo)
        #expect(hotkey.setCombo(Self.combo) == nil)

        #expect(registrar.registerCount == 1)
        #expect(hotkey.status == .ready)
    }

    @Test func aDifferentShortcutTakesTheOldOnesPlace() {
        let registrar = FakeDesignHotkeyRegistrar()
        let hotkey = controller(registrar: registrar)
        let other = AgentHotkeyCombo(keyCode: 9, modifiers: [.control, .shift])

        hotkey.setCombo(Self.combo)
        #expect(hotkey.setCombo(other) == nil)

        #expect(registrar.registered == other)
        #expect(registrar.registerCount == 2)
        #expect(hotkey.displayText == "⌃⇧V")
    }

    @Test func aShortcutChosenWhileRecordingIsSavedAndHeldOnlyOnceRecordingEnds() {
        let defaults = MemoryDefaults()
        let registrar = FakeDesignHotkeyRegistrar()
        let hotkey = controller(defaults, registrar: registrar)

        hotkey.beginRecording()
        #expect(hotkey.setCombo(Self.combo) == nil)
        #expect(registrar.registered == nil)
        #expect(defaults.string(forKey: NookDesignHotkeyController.comboKey) == Self.combo.storageValue)

        hotkey.endRecording()
        #expect(registrar.registered == Self.combo)
        #expect(hotkey.status == .ready)
    }

    @Test func clearingWhileRecordingLeavesNothingToRegisterAfterwards() {
        let registrar = FakeDesignHotkeyRegistrar()
        let hotkey = controller(registrar: registrar)
        hotkey.setCombo(Self.combo)

        hotkey.beginRecording()
        hotkey.clear()
        hotkey.endRecording()

        #expect(hotkey.combo == nil)
        #expect(hotkey.status == .none)
        #expect(registrar.registered == nil)
    }

    @Test func theKeysAreRegisteredOncePerSwitchOnAndLetGoOnEverySwitchOff() {
        let registrar = FakeDesignHotkeyRegistrar()
        let hotkey = controller(registrar: registrar)
        hotkey.setCombo(Self.combo)

        hotkey.setLive(true)
        hotkey.setLive(true)
        #expect(registrar.registerCount == 1)

        hotkey.setLive(false)
        hotkey.setLive(false)
        #expect(registrar.unregisterCount == 1)
        #expect(registrar.registered == nil)

        hotkey.setLive(true)
        #expect(registrar.registerCount == 2)
        #expect(registrar.registered == Self.combo)
    }

    @Test func aPressAfterTheWidgetIsOffOrTheShortcutClearedReachesNothing() {
        let registrar = FakeDesignHotkeyRegistrar()
        let hotkey = controller(registrar: registrar)
        var presses = 0
        hotkey.onPress = { presses += 1 }
        hotkey.setCombo(Self.combo)

        registrar.press()
        hotkey.setLive(false)
        registrar.press()
        hotkey.setLive(true)
        registrar.press()
        hotkey.clear()
        registrar.press()

        #expect(presses == 2)
    }

    @Test func aRefusedShortcutIsTriedAgainWhenTheWidgetComesBackOn() {
        let registrar = FakeDesignHotkeyRegistrar()
        registrar.refusalCode = -9878
        let hotkey = controller(registrar: registrar)
        hotkey.setCombo(Self.combo)
        #expect(hotkey.status == .failed(code: -9878))

        registrar.refusalCode = nil
        hotkey.setLive(false)
        hotkey.setLive(true)

        #expect(hotkey.status == .ready)
        #expect(registrar.registered == Self.combo)
    }

    @Test func theRegistrarComingLateStillHoldsAShortcutThatWasAlreadyChosen() {
        let defaults = MemoryDefaults()
        defaults.set(Self.combo.storageValue, forKey: NookDesignHotkeyController.comboKey)
        let hotkey = controller(defaults, live: true)
        #expect(hotkey.status == .inactive)

        let registrar = FakeDesignHotkeyRegistrar()
        hotkey.activate(registrar: registrar)

        #expect(hotkey.status == .ready)
        #expect(registrar.registered == Self.combo)
    }

    @Test func aShortcutThatMacOSUsesIsFoundWhenTheRegistrarComesLate() {
        let defaults = MemoryDefaults()
        defaults.set(Self.combo.storageValue, forKey: NookDesignHotkeyController.comboKey)
        let hotkey = controller(defaults, live: true)
        let registrar = FakeDesignHotkeyRegistrar()
        registrar.system = [Self.combo]

        hotkey.activate(registrar: registrar)

        #expect(hotkey.status == .usedBySystem)
        #expect(registrar.registerCount == 0)
    }

    @Test(arguments: [
        ([AgentHotkeyModifiers.control, .option], true),
        ([.control, .shift], true),
        ([.option, .shift], true),
        ([.control, .command], true),
        ([.option, .command], true),
        ([.control, .option, .command, .shift], true),
        ([.control, .option, .shift], true),
        ([.command, .shift], false),
        ([.control], false),
        ([.option], false),
        ([.command], false),
        ([.shift], false),
        ([], false),
    ] as [([AgentHotkeyModifiers], Bool)])
    func twoModifiersWithControlOrOptionAmongThemMakeAShortcut(modifiers: [AgentHotkeyModifiers], isAllowed: Bool) {
        let set = modifiers.reduce(into: AgentHotkeyModifiers()) { $0.formUnion($1) }
        let problem = NookDesignHotkeyRules.problem(with: AgentHotkeyCombo(keyCode: 8, modifiers: set), agentShortcuts: [])
        #expect((problem == nil) == isAllowed, "\(set.symbols)")
    }

    @Test func theAgentShortcutsKeysWithOtherModifiersAreFree() {
        let withCommand = AgentHotkeyCombo(keyCode: Self.approve.keyCode, modifiers: [.control, .option, .command])
        #expect(NookDesignHotkeyRules.problem(with: withCommand, agentShortcuts: [Self.approve]) == nil)
        let sameKeyOtherModifiers = AgentHotkeyCombo(keyCode: Self.approve.keyCode, modifiers: [.control, .shift])
        #expect(NookDesignHotkeyRules.problem(with: sameKeyOtherModifiers, agentShortcuts: [Self.approve]) == nil)
        #expect(NookDesignHotkeyRules.problem(with: Self.approve, agentShortcuts: [Self.approve]) == .usedByAgentShortcut)
        // A shortcut with too few modifiers is told that, before it is told anything else.
        let weak = AgentHotkeyCombo(keyCode: Self.approve.keyCode, modifiers: [.control])
        #expect(NookDesignHotkeyRules.problem(with: weak, agentShortcuts: [weak]) == .needsModifiers)
    }

    @Test func aSavedShortcutOfAnyOddKindIsReadOrDropped() {
        for value in ["", "garbage", "1", "1:2:3", "-1:8", "16:8", "99:8", "3:-1", "3:70000", "3:abc", "x:8"] {
            let defaults = MemoryDefaults()
            defaults.set(value, forKey: NookDesignHotkeyController.comboKey)
            #expect(NookDesignHotkeyController(defaults: defaults).combo == nil, "\(value)")
        }
        let defaults = MemoryDefaults()
        defaults.set(AgentHotkeyCombo(keyCode: 65535, modifiers: [.control, .option]).storageValue, forKey: NookDesignHotkeyController.comboKey)
        #expect(NookDesignHotkeyController(defaults: defaults).combo?.keyCode == 65535)
        // A saved shortcut with one modifier is kept and shown as not valid.
        let weak = MemoryDefaults()
        weak.set(AgentHotkeyCombo(keyCode: 8, modifiers: [.command, .shift]).storageValue, forKey: NookDesignHotkeyController.comboKey)
        #expect(NookDesignHotkeyController(defaults: weak).status == .invalid(.needsModifiers))
    }

    @Test func aKeyWithNoNameOnTheLayoutIsShownByItsCode() {
        let hotkey = controller(registrar: FakeDesignHotkeyRegistrar())
        hotkey.setCombo(AgentHotkeyCombo(keyCode: 200, modifiers: [.control, .option]))
        #expect(hotkey.displayText == "⌃⌥Key 200")
    }
}

