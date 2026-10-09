import Foundation
import Testing
@testable import OpenIslandApp

struct AgentHotkeyRulesTests {
    private static let now = Date(timeIntervalSince1970: 10_000)
    private static let requestA = UUID()
    private static let requestB = UUID()

    private static func candidate(_ sessionID: String, request: UUID) -> AgentHotkeyCandidate {
        AgentHotkeyCandidate(sessionID: sessionID, requestID: request)
    }

    /// `card` is the request shown as the island's single card.
    /// `shownSecondsAgo` nil means the app never saw it come on screen.
    private static func context(
        card: AgentHotkeyCard? = nil,
        foldedCard: AgentHotkeyCard? = nil,
        shownSecondsAgo: TimeInterval? = 30,
        decidedSecondsAgo: TimeInterval? = nil,
        waiting: [AgentHotkeyCandidate]
    ) -> AgentHotkeyContext {
        AgentHotkeyContext(
            card: card,
            foldedCard: foldedCard,
            cardShownAt: card == nil ? nil : shownSecondsAgo.map { now.addingTimeInterval(-$0) },
            lastDecisionAt: decidedSecondsAgo.map { now.addingTimeInterval(-$0) },
            waiting: waiting,
            now: now
        )
    }

    private static let cardA = AgentHotkeyCard(sessionID: "a", requestID: requestA)
    private static let cardB = AgentHotkeyCard(sessionID: "b", requestID: requestB)
    private static let bothWaiting = [candidate("a", request: requestA), candidate("b", request: requestB)]

    // MARK: Keys

    @Test
    func theDefaultKeysAreFarApartOnTheKeyboard() {
        let settings = AgentHotkeySettings()
        #expect(settings.approve.keyCode == AgentHotkeyKeyboard.keyY)
        #expect(settings.deny.keyCode == AgentHotkeyKeyboard.keyN)
        #expect(!AgentHotkeyKeyboard.areNeighbours(settings.approve.keyCode, settings.deny.keyCode))
        #expect(settings.approve.displayText() == "⌃⌥Y")
        #expect(settings.deny.displayText() == "⌃⌥N")
    }

    @Test
    func keysThatTouchAreNeighbours() {
        let a: UInt16 = 0, s: UInt16 = 1, d: UInt16 = 2
        let y: UInt16 = 16, h: UInt16 = 4, g: UInt16 = 5, j: UInt16 = 38, u: UInt16 = 32

        #expect(AgentHotkeyKeyboard.areNeighbours(a, s))
        #expect(!AgentHotkeyKeyboard.areNeighbours(a, d))
        #expect(AgentHotkeyKeyboard.areNeighbours(y, u))
        // The row below sits under the gaps of the row above.
        #expect(AgentHotkeyKeyboard.areNeighbours(y, h))
        #expect(AgentHotkeyKeyboard.areNeighbours(y, g))
        #expect(!AgentHotkeyKeyboard.areNeighbours(y, j))
        #expect(AgentHotkeyKeyboard.areNeighbours(y, y))
    }

    @Test
    func keysOutsideTheMainRowsOnlyClashWithThemselves() {
        let space: UInt16 = 49, returnKey: UInt16 = 36
        #expect(!AgentHotkeyKeyboard.areNeighbours(space, returnKey))
        #expect(AgentHotkeyKeyboard.areNeighbours(space, space))
        #expect(AgentHotkeyKeyboard.usName(for: space) == "Space")
        #expect(AgentHotkeyKeyboard.usName(for: 200) == nil)
    }

    @Test
    func aShortcutNeedsTwoModifiersWithControlOrOption() {
        let key = AgentHotkeyKeyboard.keyY
        #expect(AgentHotkeyRules.problem(with: AgentHotkeyCombo(keyCode: key, modifiers: [])) == .needsModifiers)
        #expect(AgentHotkeyRules.problem(with: AgentHotkeyCombo(keyCode: key, modifiers: [.command])) == .needsModifiers)
        #expect(AgentHotkeyRules.problem(with: AgentHotkeyCombo(keyCode: key, modifiers: [.control])) == .needsModifiers)
        // Command and Shift alone would take a shortcut apps use themselves.
        #expect(AgentHotkeyRules.problem(with: AgentHotkeyCombo(keyCode: key, modifiers: [.command, .shift])) == .needsModifiers)
        #expect(AgentHotkeyRules.problem(with: AgentHotkeyCombo(keyCode: key, modifiers: [.control, .option])) == nil)
        #expect(AgentHotkeyRules.problem(with: AgentHotkeyCombo(keyCode: key, modifiers: [.option, .command])) == nil)
    }

    @Test
    func aShortcutNextToTheOtherOneIsRefusedWhateverItsModifiers() {
        let settings = AgentHotkeySettings()
        let besideDeny = AgentHotkeyCombo(keyCode: 46, modifiers: [.control, .option, .command]) // M, beside N
        let onDeny = AgentHotkeyCombo(keyCode: AgentHotkeyKeyboard.keyN, modifiers: [.option, .command])
        let farAway = AgentHotkeyCombo(keyCode: 0, modifiers: [.control, .option]) // A

        #expect(AgentHotkeyRules.problem(with: besideDeny, for: .approve, in: settings) == .tooCloseToOther)
        #expect(AgentHotkeyRules.problem(with: onDeny, for: .approve, in: settings) == .tooCloseToOther)
        #expect(AgentHotkeyRules.problem(with: farAway, for: .approve, in: settings) == nil)
        // Moving deny is checked against approve, not against itself.
        #expect(AgentHotkeyRules.problem(with: besideDeny, for: .deny, in: settings) == nil)
    }

    @Test
    func onlyShortcutsThatAreOnValidAndFreeAreUsable() {
        var settings = AgentHotkeySettings()
        #expect(AgentHotkeyRules.usable(settings) == [.approve: settings.approve, .deny: settings.deny])

        settings.isDenyEnabled = false
        #expect(AgentHotkeyRules.usable(settings) == [.approve: settings.approve])

        settings.isDenyEnabled = true
        #expect(AgentHotkeyRules.usable(settings, systemShortcuts: [settings.approve]) == [.deny: settings.deny])

        // Saved settings that put the two keys side by side register nothing.
        settings.approve = AgentHotkeyCombo(keyCode: 46, modifiers: [.control, .option])
        #expect(AgentHotkeyRules.usable(settings).isEmpty)
    }

    @Test
    func aShortcutSurvivesBeingSaved() {
        let combo = AgentHotkeyCombo(keyCode: 45, modifiers: [.control, .option, .shift])
        #expect(AgentHotkeyCombo(storageValue: combo.storageValue) == combo)
        #expect(AgentHotkeyCombo(storageValue: "nonsense") == nil)
        #expect(AgentHotkeyCombo(storageValue: "99:45") == nil)
    }

    // MARK: Which request

    @Test
    func nothingWaitingMeansThePressDoesNothing() {
        #expect(AgentHotkeyRules.decision(in: Self.context(waiting: [])) == .ignore)
        // A card for a request that no longer waits is nothing to decide.
        #expect(AgentHotkeyRules.decision(in: Self.context(card: Self.cardA, waiting: [])) == .ignore)
    }

    @Test
    func theRequestOnTheCardIsDecided() {
        let context = Self.context(card: Self.cardB, waiting: Self.bothWaiting)
        #expect(AgentHotkeyRules.decision(in: context) == .act(sessionID: "b", requestID: Self.requestB))
        #expect(AgentHotkeyRules.isOnCard(sessionID: "b", requestID: Self.requestB, in: context))
        #expect(!AgentHotkeyRules.isOnCard(sessionID: "a", requestID: Self.requestA, in: context))
    }

    @Test
    func aRequestInTheOpenListIsNeverDecidedEvenInItsTopRow() {
        // The list is open, which is no card at all. The top row is "a".
        let context = Self.context(waiting: Self.bothWaiting)
        #expect(AgentHotkeyRules.decision(in: context) == .reveal(sessionID: "a"))
        #expect(!AgentHotkeyRules.isOnCard(sessionID: "a", requestID: Self.requestA, in: context))
    }

    @Test
    func aRequestThatIsNotTheCardIsShownAndNotDecided() {
        let waiting = [Self.candidate("a", request: Self.requestA)]

        // Island closed, on its list, on the Nook page, or on a folded
        // card: no card with buttons is on screen.
        #expect(AgentHotkeyRules.decision(in: Self.context(waiting: waiting)) == .reveal(sessionID: "a"))
        // Island showing another session's card and nothing else.
        let otherCard = AgentHotkeyCard(sessionID: "other", requestID: UUID())
        #expect(AgentHotkeyRules.decision(in: Self.context(card: otherCard, waiting: waiting)) == .reveal(sessionID: "a"))
    }

    @Test
    func theCardOfARequestThatWasReplacedIsNotDecided() {
        // The card still holds the old request of session "a". The session
        // now waits with another one.
        let stale = AgentHotkeyCard(sessionID: "a", requestID: UUID())
        let context = Self.context(card: stale, waiting: [Self.candidate("a", request: Self.requestA)])
        #expect(AgentHotkeyRules.decision(in: context) == .reveal(sessionID: "a"))
    }

    @Test
    func aCardThatOnlyJustCameOnScreenIsNotDecided() {
        let fresh = Self.context(card: Self.cardA, shownSecondsAgo: 0.2, waiting: Self.bothWaiting)
        #expect(AgentHotkeyRules.decision(in: fresh) == .tooSoon)

        let settled = Self.context(
            card: Self.cardA,
            shownSecondsAgo: AgentHotkeyRules.minimumVisibleTime + 0.5,
            waiting: Self.bothWaiting
        )
        #expect(AgentHotkeyRules.decision(in: settled) == .act(sessionID: "a", requestID: Self.requestA))
    }

    @Test
    func theTimeRunsFromTheCardComingOnScreenAndNotFromTheRequestArriving() {
        // The request arrived long ago. Its card has been up for 50 ms.
        let context = Self.context(card: Self.cardA, shownSecondsAgo: 0.05, waiting: Self.bothWaiting)
        #expect(AgentHotkeyRules.decision(in: context) == .tooSoon)
    }

    @Test
    func aCardTheAppNeverSawComeOnScreenIsNotDecided() {
        let context = Self.context(card: Self.cardA, shownSecondsAgo: nil, waiting: Self.bothWaiting)
        #expect(AgentHotkeyRules.decision(in: context) == .tooSoon)
    }

    @Test
    func aPressMadeBeforeTheCardCameUpDecidesNothing() {
        // The key went down 100 ms before the card changed, and the app
        // only got to the press afterwards.
        let context = Self.context(card: Self.cardA, shownSecondsAgo: -0.1, waiting: Self.bothWaiting)
        #expect(AgentHotkeyRules.decision(in: context) == .tooSoon)
    }

    @Test
    func aFoldedCardIsOpenedAgainAndNotDecided() {
        // "b" is the card, with its buttons folded away. "a" is first in
        // the list. The press is about the card on screen.
        let context = Self.context(foldedCard: Self.cardB, waiting: Self.bothWaiting)
        #expect(AgentHotkeyRules.decision(in: context) == .reveal(sessionID: "b"))
        #expect(!AgentHotkeyRules.isOnCard(sessionID: "b", requestID: Self.requestB, in: context))

        // A folded card whose request no longer waits is not in the way.
        let gone = Self.context(foldedCard: Self.cardB, waiting: [Self.candidate("a", request: Self.requestA)])
        #expect(AgentHotkeyRules.decision(in: gone) == .reveal(sessionID: "a"))
    }

    @Test
    func aSecondPressRightAfterADecisionDecidesNothing() {
        // "a" was decided 150 ms ago. The card of "b" has been up a while.
        let rightAfter = Self.context(
            card: Self.cardB,
            shownSecondsAgo: 20,
            decidedSecondsAgo: 0.15,
            waiting: [Self.candidate("b", request: Self.requestB)]
        )
        #expect(AgentHotkeyRules.decision(in: rightAfter) == .tooSoon)

        let later = Self.context(
            card: Self.cardB,
            shownSecondsAgo: 20,
            decidedSecondsAgo: 2,
            waiting: [Self.candidate("b", request: Self.requestB)]
        )
        #expect(AgentHotkeyRules.decision(in: later) == .act(sessionID: "b", requestID: Self.requestB))
    }

    @Test
    func aSecondPressAfterADecisionOnlyShowsTheNextRequestInTheList() {
        // "a" was just decided with the list open. "b" moved to the top row.
        let context = Self.context(decidedSecondsAgo: 0.15, waiting: [Self.candidate("b", request: Self.requestB)])
        #expect(AgentHotkeyRules.decision(in: context) == .reveal(sessionID: "b"))
    }
}

@MainActor
struct AgentHotkeyControllerTests {
    private func makeController() -> (AgentHotkeyController, FakeHotkeyRegistrar, UserDefaults, String) {
        let (defaults, name) = AgentToolsFixtures.defaults()
        return (AgentHotkeyController(defaults: defaults), FakeHotkeyRegistrar(), defaults, name)
    }

    @Test
    func nothingIsRegisteredUntilTheAppHandsOverARegistrar() {
        let (controller, _, defaults, name) = makeController()
        defer { defaults.removePersistentDomain(forName: name) }

        controller.setArmed(true)
        #expect(controller.statuses[.approve] == .inactive)
        #expect(controller.statuses[.deny] == .inactive)
        #expect(controller.hint.isEmpty)
    }

    @Test
    func theShortcutsAreOnlyHeldWhileAnAgentWaits() {
        let (controller, registrar, defaults, name) = makeController()
        defer { defaults.removePersistentDomain(forName: name) }

        // Activating asks macOS once and lets go again.
        controller.activate(registrar: registrar)
        #expect(registrar.registerCalls == 1)
        #expect(registrar.registered.isEmpty)
        #expect(controller.statuses[.approve] == .ready)
        #expect(controller.statuses[.deny] == .ready)

        controller.setArmed(true)
        #expect(registrar.registered == [
            .approve: AgentHotkeySettings.defaultApprove,
            .deny: AgentHotkeySettings.defaultDeny,
        ])

        // Disarming does not let go at once: a key still held from the
        // decision must be seen as held.
        controller.setArmed(false)
        #expect(!registrar.registered.isEmpty)

        // Arming again inside that time keeps the registration as it is.
        let callsBefore = registrar.registerCalls
        controller.setArmed(true)
        #expect(registrar.registerCalls == callsBefore)
    }

    @Test
    func aPressReachesTheAppOnlyWhileRegistered() {
        let (controller, registrar, defaults, name) = makeController()
        defer { defaults.removePersistentDomain(forName: name) }

        var pressed: [AgentHotkeyAction] = []
        var times: [Date] = []
        controller.onPress = { action, time in
            pressed.append(action)
            times.append(time)
        }
        controller.activate(registrar: registrar)

        registrar.press(.approve)
        #expect(pressed.isEmpty)

        // The press comes with the time the key went down.
        let keyDown = Date(timeIntervalSince1970: 700)
        controller.setArmed(true)
        registrar.press(.deny, at: keyDown)
        #expect(pressed == [.deny])
        #expect(times == [keyDown])
    }

    @Test
    func aShortcutMacOSRefusesIsReportedAndKeptOffTheCard() {
        let (controller, registrar, defaults, name) = makeController()
        defer { defaults.removePersistentDomain(forName: name) }

        let refusal: Int32 = -9878
        registrar.failures = [.approve: refusal]
        controller.activate(registrar: registrar)

        #expect(controller.statuses[.approve] == .failed(code: refusal))
        #expect(controller.statuses[.deny] == .ready)
        #expect(controller.hint == AgentHotkeyHint(approve: nil, deny: "⌃⌥N"))
    }

    @Test
    func aShortcutMacOSUsesItselfIsNeverRegistered() {
        let (controller, registrar, defaults, name) = makeController()
        defer { defaults.removePersistentDomain(forName: name) }

        registrar.system = [AgentHotkeySettings.defaultDeny]
        controller.activate(registrar: registrar)
        controller.setArmed(true)

        #expect(controller.statuses[.deny] == .usedBySystem)
        #expect(registrar.registered == [.approve: AgentHotkeySettings.defaultApprove])
    }

    @Test
    func switchingOneOffLeavesTheOtherWorking() {
        let (controller, registrar, defaults, name) = makeController()
        defer { defaults.removePersistentDomain(forName: name) }

        controller.activate(registrar: registrar)
        controller.setArmed(true)
        controller.setEnabled(false, for: .approve)

        #expect(controller.statuses[.approve] == .off)
        #expect(registrar.registered == [.deny: AgentHotkeySettings.defaultDeny])
        #expect(controller.hint == AgentHotkeyHint(approve: nil, deny: "⌃⌥N"))
        #expect(defaults.persistentDomain(forName: name)?[AgentHotkeyController.approveEnabledKey] as? Bool == false)
    }

    @Test
    func aNewShortcutIsSavedAndABadOneIsNot() {
        let (controller, registrar, defaults, name) = makeController()
        defer { defaults.removePersistentDomain(forName: name) }
        controller.activate(registrar: registrar)

        let good = AgentHotkeyCombo(keyCode: 0, modifiers: [.control, .option]) // A
        #expect(controller.setCombo(good, for: .approve) == nil)
        #expect(controller.combo(for: .approve) == good)
        #expect(defaults.persistentDomain(forName: name)?[AgentHotkeyController.approveComboKey] as? String == good.storageValue)

        let besideDeny = AgentHotkeyCombo(keyCode: 46, modifiers: [.control, .option]) // M
        #expect(controller.setCombo(besideDeny, for: .approve) == .tooCloseToOther)
        #expect(controller.combo(for: .approve) == good)

        let bare = AgentHotkeyCombo(keyCode: 0, modifiers: [.command])
        #expect(controller.setCombo(bare, for: .approve) == .needsModifiers)
        #expect(controller.combo(for: .approve) == good)

        // A second controller on the same defaults reads the saved choice.
        #expect(AgentHotkeyController(defaults: defaults).combo(for: .approve) == good)

        controller.resetToDefaults()
        #expect(controller.settings == AgentHotkeySettings())
        #expect(defaults.persistentDomain(forName: name)?[AgentHotkeyController.approveComboKey] == nil)
    }

    @Test
    func recordingANewShortcutLetsGoOfTheOldOnes() {
        let (controller, registrar, defaults, name) = makeController()
        defer { defaults.removePersistentDomain(forName: name) }

        controller.activate(registrar: registrar)
        controller.setArmed(true)
        #expect(!registrar.registered.isEmpty)

        // A press meant for the recorder must not decide a request.
        controller.beginRecording()
        #expect(registrar.registered.isEmpty)
        #expect(controller.statuses[.approve] == .ready)

        controller.endRecording()
        #expect(registrar.registered.count == 2)
    }

    @Test
    func aCardIsStampedWhenItComesOnScreenAndNotAgainWhileItStays() {
        let (controller, _, defaults, name) = makeController()
        defer { defaults.removePersistentDomain(forName: name) }

        let first = AgentHotkeyCard(sessionID: "a", requestID: UUID())
        let second = AgentHotkeyCard(sessionID: "b", requestID: UUID())
        let early = Date(timeIntervalSince1970: 100)
        let late = Date(timeIntervalSince1970: 200)

        controller.noteShownCard(first, now: early)
        controller.noteShownCard(first, now: late)
        #expect(controller.cardShownAt == early)

        // Another request takes the card: its time starts then.
        controller.noteShownCard(second, now: late)
        #expect(controller.shownCard == second)
        #expect(controller.cardShownAt == late)

        controller.noteShownCard(nil, now: late)
        #expect(controller.shownCard == nil)
        #expect(controller.cardShownAt == nil)
    }

    @Test
    func foldingACardHidesItAndOpeningItAgainRestartsItsTime() {
        let (controller, _, defaults, name) = makeController()
        defer { defaults.removePersistentDomain(forName: name) }

        let card = AgentHotkeyCard(sessionID: "a", requestID: UUID())
        let other = AgentHotkeyCard(sessionID: "b", requestID: UUID())
        let shown = Date(timeIntervalSince1970: 100)
        let unfolded = Date(timeIntervalSince1970: 130)
        controller.noteShownCard(card, now: shown)

        // A row that is not the card on screen has no say.
        controller.noteCard(other, isFolded: true)
        #expect(controller.foldedCard == nil)

        controller.noteCard(card, isFolded: true)
        #expect(controller.foldedCard == card)

        controller.noteCard(card, isFolded: false, now: unfolded)
        #expect(controller.foldedCard == nil)
        #expect(controller.cardShownAt == unfolded)

        // A new card starts unfolded.
        controller.noteCard(card, isFolded: true)
        controller.noteShownCard(other, now: unfolded)
        #expect(controller.foldedCard == nil)
    }

    @Test
    func askingAFoldedCardToOpenCountsUp() {
        let (controller, _, defaults, name) = makeController()
        defer { defaults.removePersistentDomain(forName: name) }

        let before = controller.unfoldRequests
        controller.requestUnfold()
        #expect(controller.unfoldRequests == before + 1)
    }
}
