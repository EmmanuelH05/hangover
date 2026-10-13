import AppKit
import Foundation
import OpenIslandCore
import Testing
@testable import OpenIslandApp

// Edge cases for a click inside a hover-opened island, which no longer pins
// it (D20, changed on 2026-10-10), and for the unsaved lines that keep it
// open instead: what every click does, every guard that holds the island
// against the pointer leaving, and a line set and cleared in every order.

// MARK: - What every click does

struct EdgeCaseClickTableTests {
    private struct Case: CustomStringConvertible {
        var context: IslandClickContext
        var description: String {
            let c = context
            return "\(c.status) \(c.reason.map { "\($0)" } ?? "no reason") pill:\(c.isInClosedSurface)"
                + " area:\(c.isInExpandedArea) notch:\(c.isOnNotch) blocks:\(c.blocksDismiss)"
                + " picker:\(c.hasOpenPicker) tour:\(c.holdsOpenForTour)"
        }
    }

    private static let cases: [Case] = {
        var all: [Case] = []
        let bools = [false, true]
        let reasons: [NotchOpenReason?] = [nil, .hover, .click, .notification, .boot]
        for status in [NotchStatus.closed, .opened, .popping] {
            for reason in reasons {
                for pill in bools { for area in bools { for notch in bools {
                    for blocks in bools { for picker in bools { for tour in bools {
                        all.append(Case(context: IslandClickContext(
                            status: status, reason: reason, isInClosedSurface: pill, isInExpandedArea: area,
                            isOnNotch: notch, blocksDismiss: blocks, hasOpenPicker: picker, holdsOpenForTour: tour
                        )))
                    } } }
                } } }
            }
        }
        return all
    }()

    @Test func theTableHoldsEveryStatusByEveryReasonByEveryPlaceAndRefusal() {
        #expect(Self.cases.count == 3 * 5 * 64)
    }

    @Test func aClosedIslandOpensOnAClickOnItsPillAndNothingElse() {
        for entry in Self.cases where entry.context.status == .closed {
            let expected: IslandClickAction = entry.context.isInClosedSurface ? .open : .none
            #expect(IslandPointerRules.clickAction(entry.context) == expected, "\(entry)")
        }
    }

    @Test func aPoppingIslandTakesNoClickAtAll() {
        for entry in Self.cases where entry.context.status == .popping {
            #expect(IslandPointerRules.clickAction(entry.context) == .none, "\(entry)")
        }
    }

    @Test func theToursHoldAnswersNothingToAnyClickOnTheOpenIsland() {
        for entry in Self.cases where entry.context.status == .opened && entry.context.holdsOpenForTour {
            #expect(IslandPointerRules.clickAction(entry.context) == .none, "\(entry)")
        }
    }

    /// Outside the island the reason it was opened for does not matter: a
    /// card, the boot animation, a hover and a click all close on a click
    /// outside unless a decision, a picker or the tour holds them.
    @Test func aClickOutsideTheOpenIslandAnswersTheSameWhateverOpenedIt() {
        for entry in Self.cases where entry.context.status == .opened && !entry.context.isInExpandedArea {
            let c = entry.context
            let expected: IslandClickAction = c.holdsOpenForTour || c.hasOpenPicker ? .none
                : c.blocksDismiss ? .holdForDecision : .dismiss
            #expect(IslandPointerRules.clickAction(c) == expected, "\(entry)")
        }
    }

    @Test func aDismissNeedsAnOpenIslandAClickOutsideAndNothingHoldingIt() {
        for entry in Self.cases {
            let c = entry.context
            let isOutsideAndFree = c.status == .opened && !c.isInExpandedArea
                && !c.holdsOpenForTour && !c.hasOpenPicker && !c.blocksDismiss
            #expect((IslandPointerRules.clickAction(c) == .dismiss) == isOutsideAndFree, "\(entry)")
        }
    }

    @Test func holdingForADecisionNeedsAClickOutsideAndNoPickerOrTourToTakeItFirst() {
        for entry in Self.cases {
            let c = entry.context
            let applies = c.status == .opened && !c.isInExpandedArea && c.blocksDismiss
                && !c.holdsOpenForTour && !c.hasOpenPicker
            #expect((IslandPointerRules.clickAction(c) == .holdForDecision) == applies, "\(entry)")
        }
    }

    @Test func aSecondClickOnTheNotchNeedsAClickOpenedIslandAndNothingHoldingIt() {
        for entry in Self.cases {
            let c = entry.context
            let applies = c.status == .opened && c.reason == .click && c.isInExpandedArea && c.isOnNotch
                && !c.blocksDismiss && !c.holdsOpenForTour
            #expect((IslandPointerRules.clickAction(c) == .closeFromNotch) == applies, "\(entry)")
        }
    }

    /// The pin is gone: whatever a click inside a hover-opened island lands
    /// on, it changes nothing.
    @Test func aClickInsideAHoverOpenedIslandIsNeverAnythingWhateverElseIsTrue() {
        for entry in Self.cases where entry.context.status == .opened
            && entry.context.reason == .hover && entry.context.isInExpandedArea {
            #expect(IslandPointerRules.clickAction(entry.context) == .none, "\(entry)")
        }
    }

    @Test func aClickInsideACardOrTheBootAnimationIsNeverAnything() {
        for entry in Self.cases where entry.context.status == .opened && entry.context.isInExpandedArea {
            let reason = entry.context.reason
            if reason == nil || reason == .notification || reason == .boot {
                #expect(IslandPointerRules.clickAction(entry.context) == .none, "\(entry)")
            }
        }
    }

    @Test func theOnlyActionsAClickCanAnswerAreTheFiveThatExist() {
        let answers = Set(Self.cases.map { IslandPointerRules.clickAction($0.context) })
        #expect(answers == [.open, .dismiss, .holdForDecision, .closeFromNotch, .none])
    }
}

// MARK: - Lines that are not saved

@MainActor
struct EdgeCaseDraftTests {
    private static func nook() -> NookModel {
        NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
    }

    private static let drafts: [NookDraft] = [.note, .todo, .timerEntry]

    private static func permutations<T>(_ items: [T]) -> [[T]] {
        guard items.count > 1 else { return [items] }
        return items.indices.flatMap { index -> [[T]] in
            var rest = items
            let head = rest.remove(at: index)
            return permutations(rest).map { [head] + $0 }
        }
    }

    @Test func lineSetInAnyOrderAndClearedInAnyOrderHoldsUntilTheLastOneIsGone() {
        let nook = Self.nook()
        for setOrder in Self.permutations(Self.drafts) {
            for clearOrder in Self.permutations(Self.drafts) {
                for draft in setOrder {
                    nook.setDraft(draft, isUnsaved: true)
                    #expect(nook.holdsUnsavedDraft)
                }
                for (index, draft) in clearOrder.enumerated() {
                    #expect(nook.holdsUnsavedDraft, "\(setOrder) then \(clearOrder), before clearing \(draft)")
                    nook.setDraft(draft, isUnsaved: false)
                    #expect(nook.holdsUnsavedDraft == (index < clearOrder.count - 1))
                }
            }
        }
    }

    /// A widget reports what it holds and not what happened. Saying "unsaved"
    /// twice and "saved" once is saved.
    @Test func sayingAnUnsavedLineTwiceAndSavedOnceIsSaved() {
        let nook = Self.nook()
        nook.setDraft(.note, isUnsaved: true)
        nook.setDraft(.note, isUnsaved: true)
        nook.setDraft(.note, isUnsaved: false)
        #expect(nook.holdsUnsavedDraft == false)
    }

    @Test func clearingALineThatWasNeverSetChangesNothingAndDoesNotClearAnother() {
        let nook = Self.nook()
        nook.setDraft(.note, isUnsaved: false)
        #expect(nook.holdsUnsavedDraft == false)

        nook.setDraft(.todo, isUnsaved: true)
        nook.setDraft(.note, isUnsaved: false)
        nook.setDraft(.timerEntry, isUnsaved: false)
        #expect(nook.holdsUnsavedDraft, "the to-do line is still held")
    }

    @Test func forgettingDropsEveryLineAtOnceAndASetAfterwardsHoldsAgain() {
        let nook = Self.nook()
        Self.drafts.forEach { nook.setDraft($0, isUnsaved: true) }
        nook.forgetDrafts()
        #expect(nook.holdsUnsavedDraft == false)

        nook.forgetDrafts()
        #expect(nook.holdsUnsavedDraft == false, "forgetting nothing is fine")

        nook.setDraft(.timerEntry, isUnsaved: true)
        #expect(nook.holdsUnsavedDraft)
        // The widget that held it says it is saved: only now is it free.
        nook.setDraft(.timerEntry, isUnsaved: false)
        #expect(nook.holdsUnsavedDraft == false)
    }

    @Test func anyAmountOfSpaceOrLineBreakIsNotAnUnsavedLine() {
        let blanks = [
            "", " ", "   ", "\t", "\n", "\r\n", " \n \t ", "\u{00A0}", "\u{3000}", "\u{2028}", "\u{2029}", "\u{0085}",
        ]
        for text in blanks { #expect(NookDraft.isUnsaved(text) == false, "\(text.unicodeScalars.map(\.value))") }
    }

    @Test func anythingElseAtAllIsAnUnsavedLineEvenWithSpaceAroundIt() {
        for text in ["a", " a ", "\n1", "25", "1:30", "0", ".", "\u{1F600}", "  x\n"] {
            #expect(NookDraft.isUnsaved(text), "\(text)")
        }
    }
}

// MARK: - What holds the island against the pointer leaving

@MainActor
@Suite(.serialized, .noNewWindows)
struct EdgeCaseAutoCollapseTests {
    /// A guard that holds an open island when the pointer leaves it.
    enum Hold: CaseIterable {
        case harness, editing, eventEditor, mirror, draft, tour, typingReply
    }

    private static func model() -> AppModel {
        let model = AppModel(defaults: MemoryDefaults())
        model.nook.presentRingLight = { _ in }
        model.nook.addWidget(.mirror, for: model.activeAppearanceProfile)
        var session = AgentSession(
            id: "done", title: "Claude · project", tool: .claudeCode,
            attachmentState: .attached, phase: .completed, summary: "Done", updatedAt: .now
        )
        session.isProcessAlive = true
        model.state = SessionState(sessions: [session])
        model.notchStatus = .opened
        model.notchOpenReason = .hover
        model.nook.pageOverride = .nook
        return model
    }

    private static func set(_ hold: Hold, _ isOn: Bool, in model: AppModel) {
        switch hold {
        case .harness: model.ignoresPointerExitDuringHarness = isOn
        case .editing: model.nook.isEditingLayout = isOn
        case .eventEditor:
            if isOn { model.nook.beginAddingEvent(on: Date()) } else { model.nook.closeEventEditor(keepingDraft: false) }
        case .mirror: model.nook.isMirrorOn = isOn
        case .draft: model.nook.setDraft(.note, isUnsaved: isOn)
        case .tour: model.setTourHoldsIslandOpen(isOn)
        case .typingReply: model.setAgentReplyEditing(isOn, sessionID: "done")
        }
    }

    private static func clearAll(in model: AppModel) {
        for hold in Hold.allCases { set(hold, false, in: model) }
        model.nook.forgetDrafts()
    }

    // MARK: Each guard alone

    @Test func aHoverOpenedIslandWithNothingHoldingItFollowsThePointer() {
        let model = Self.model()
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave)
        model.nook.pageOverride = .agents
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave)
    }

    @Test(arguments: [Hold.harness, .editing, .eventEditor, .mirror, .draft, .tour])
    func eachGuardAloneOnTheNookPageHoldsTheIslandAndLettingGoFreesIt(hold: Hold) {
        let model = Self.model()
        defer { Self.clearAll(in: model) }

        Self.set(hold, true, in: model)
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave == false, "\(hold) on")
        Self.set(hold, false, in: model)
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave, "\(hold) off")
    }

    @Test func aReplyBeingTypedHoldsTheIslandOnTheAgentsPageAndLettingGoFreesIt() {
        let model = Self.model()
        model.nook.pageOverride = .agents
        Self.set(.typingReply, true, in: model)
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave == false)
        Self.set(.typingReply, false, in: model)
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave)
    }

    // MARK: Each guard on the wrong page

    /// Edit mode, an event being added and the mirror belong to the Nook
    /// page. A flag left over on the agents page holds nothing.
    @Test(arguments: [Hold.editing, .eventEditor, .mirror])
    func aGuardOfTheNookPageHoldsNothingOnTheAgentsPage(hold: Hold) {
        let model = Self.model()
        defer { Self.clearAll(in: model) }
        Self.set(hold, true, in: model)
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave == false)

        model.nook.pageOverride = .agents
        #expect(model.showsNookPage == false)
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave, "\(hold) is for the Nook page")
    }

    @Test func aReplyBeingTypedHoldsNothingOnTheNookPage() {
        let model = Self.model()
        model.nook.pageOverride = .agents
        Self.set(.typingReply, true, in: model)
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave == false)

        model.nook.pageOverride = .nook
        #expect(model.isTypingAgentReply == false)
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave)
        model.setAgentReplyEditing(false, sessionID: "done")
    }

    /// A line typed in a widget holds on the Nook page, where the widgets
    /// are. On the agents page no widget is on screen and nothing is held.
    @Test func anUnsavedLineHoldsTheIslandOnTheNookPageOnly() {
        let model = Self.model()
        model.nook.pageOverride = .nook
        model.nook.setDraft(.note, isUnsaved: true)
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave == false)
        model.nook.pageOverride = .agents
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave)
        model.nook.pageOverride = .nook
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave == false)
        model.nook.setDraft(.note, isUnsaved: false)
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave)
    }

    // MARK: Together

    /// Every subset of the guards that share the Nook page: switched on in
    /// order, the island is held the whole way, and switched off in order it
    /// is held until the last one lets go.
    @Test func everyCombinationOfGuardsHoldsUntilTheLastLetsGo() {
        let model = Self.model()
        defer { Self.clearAll(in: model) }
        let holds: [Hold] = [.harness, .editing, .eventEditor, .mirror, .draft, .tour]

        for mask in 1..<(1 << holds.count) {
            let on = holds.indices.filter { mask & (1 << $0) != 0 }.map { holds[$0] }
            Self.clearAll(in: model)
            model.nook.pageOverride = .nook
            #expect(model.overlay.shouldAutoCollapseOnMouseLeave, "clean start for \(on)")

            for hold in on { Self.set(hold, true, in: model) }
            #expect(model.overlay.shouldAutoCollapseOnMouseLeave == false, "\(on) on")

            for (index, hold) in on.enumerated() {
                Self.set(hold, false, in: model)
                let remaining = on.count - index - 1
                #expect(
                    model.overlay.shouldAutoCollapseOnMouseLeave == (remaining == 0),
                    "\(on) after letting go of \(hold)"
                )
            }
        }
    }

    @Test func theGuardsOfTheAgentsPageHoldTogetherAndInAnyOrderToo() {
        let model = Self.model()
        defer { Self.clearAll(in: model) }
        model.nook.pageOverride = .agents

        Self.set(.draft, true, in: model)
        Self.set(.typingReply, true, in: model)
        Self.set(.harness, true, in: model)
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave == false)
        Self.set(.typingReply, false, in: model)
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave == false)
        Self.set(.harness, false, in: model)
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave, "a line holds nothing on the agents page")
        Self.set(.draft, false, in: model)
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave)
    }

    // MARK: A line when the page it was typed on goes away

    /// Leaving the Nook page turns off edit mode, the mirror and the event
    /// editor in the model, because the views that would do it can be late or
    /// never. The unsaved line is the one thing that is left to its view. It
    /// belongs to no page, which means a line that outlived its widget would
    /// keep the agents page open when the pointer leaves.
    @Test func switchingToTheAgentsPageForgetsALineTypedOnTheNookPageLikeItDoesTheOtherHolds() {
        let model = Self.model()
        defer { Self.clearAll(in: model) }
        Self.set(.editing, true, in: model)
        Self.set(.mirror, true, in: model)
        Self.set(.eventEditor, true, in: model)
        model.nook.setDraft(.note, isUnsaved: true)

        model.showAgentsPage()

        #expect(model.nook.isEditingLayout == false)
        #expect(model.nook.isMirrorOn == false)
        #expect(model.nook.isEventEditorOpen == false)
        let holdsStill = model.nook.holdsUnsavedDraft
        #expect(holdsStill == false)
    }

    /// The same for a card that takes the island's page: no widget is on
    /// screen, and none can hold a line.
    @Test func aCardOnTheIslandIsNotHeldOpenByALineTypedInAWidgetThatIsNoLongerThere() {
        let model = Self.model()
        defer { Self.clearAll(in: model) }
        model.nook.setDraft(.note, isUnsaved: true)
        model.notchOpenReason = .notification
        model.islandSurface = .sessionList(actionableSessionID: "done")
        #expect(model.showsNookPage == false, "the card has the page")

        model.notePointerInsideIslandSurface()
        let followsPointer = model.overlay.shouldAutoCollapseOnMouseLeave
        #expect(followsPointer)
    }

    // MARK: The tour with and without a line

    @Test func theToursHoldAndALineAreTwoHoldsAndTheIslandIsFreeOnlyWhenBothAreGone() {
        let model = Self.model()
        defer { Self.clearAll(in: model) }
        model.nook.setDraft(.todo, isUnsaved: true)
        model.setTourHoldsIslandOpen(true)
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave == false)

        model.setTourHoldsIslandOpen(false)
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave == false, "the line holds it alone")

        model.nook.setDraft(.todo, isUnsaved: false)
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave)
    }

    @Test func theToursHoldOutranksTheOtherRulesWhenTheyWouldCloseTheIsland() {
        let model = Self.model()
        defer { Self.clearAll(in: model) }
        model.setTourHoldsIslandOpen(true)
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave == false)
        #expect(model.notchStatus == .opened)

        model.handlePointerExitedIslandSurface()
        #expect(model.notchStatus == .opened)
    }

    // MARK: Other statuses and reasons

    @Test func aClosedOrPoppingIslandNeverCollapsesAnythingWhateverIsHeld() {
        let model = Self.model()
        defer { Self.clearAll(in: model) }
        for status in [NotchStatus.closed, .popping] {
            model.notchStatus = status
            #expect(model.overlay.shouldAutoCollapseOnMouseLeave == false)
            model.nook.setDraft(.note, isUnsaved: true)
            #expect(model.overlay.shouldAutoCollapseOnMouseLeave == false)
            model.nook.setDraft(.note, isUnsaved: false)
        }
    }

    @Test func aClickOpenedIslandNeverFollowsThePointerWithOrWithoutAGuard() {
        let model = Self.model()
        defer { Self.clearAll(in: model) }
        model.notchOpenReason = .click
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave == false)
        model.nook.setDraft(.note, isUnsaved: true)
        model.nook.setDraft(.note, isUnsaved: false)
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave == false)
    }

    /// The setting is read when the island opens. One that is already open
    /// goes on by the reason it was opened for, in both directions.
    @Test func changingTheOpenTriggerDoesNotChangeAnIslandThatIsAlreadyOpen() {
        let model = Self.model()
        defer { Self.clearAll(in: model) }
        model.islandOpenTrigger = .click
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave, "opened by hover, still follows the pointer")

        model.notchOpenReason = .click
        model.islandOpenTrigger = .hover
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave == false, "opened by a click, still stays")
    }

    // MARK: The pointer leaves and comes back

    @Test func aHoverOpenedIslandClosesTheMomentThePointerLeavesAndNoLineIsHeld() {
        let model = Self.model()
        model.notePointerInsideIslandSurface()
        model.handlePointerExitedIslandSurface()
        #expect(model.notchStatus == .closed)
        #expect(model.notchOpenReason == nil)
    }

    @Test func aPointerThatLeavesAndComesBackAndLeavesAgainWithALineHeldClosesNothing() {
        let model = Self.model()
        model.nook.setDraft(.note, isUnsaved: true)

        for _ in 0..<3 {
            model.handlePointerExitedIslandSurface()
            #expect(model.notchStatus == .opened)
            model.notePointerInsideIslandSurface()
        }

        model.nook.setDraft(.note, isUnsaved: false)
        model.handlePointerExitedIslandSurface()
        #expect(model.notchStatus == .closed)
    }

    @Test func aLineClearedWhileThePointerIsInsideDoesNotCloseUntilItLeaves() {
        let model = Self.model()
        model.nook.setDraft(.todo, isUnsaved: true)
        model.notePointerInsideIslandSurface()

        model.nook.setDraft(.todo, isUnsaved: false)
        #expect(model.notchStatus == .opened)
        model.handlePointerExitedIslandSurface()
        #expect(model.notchStatus == .closed)
    }

    // MARK: A card

    @Test func aCardPresentedOverAnIslandThatHoldsNoLineCollapsesAsBefore() {
        let model = Self.model()
        model.notchOpenReason = .notification
        model.islandSurface = .sessionList(actionableSessionID: "done")
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave)

        model.notePointerInsideIslandSurface()
        model.handlePointerExitedIslandSurface()
        #expect(model.notchStatus == .closed)
    }
}

// MARK: - Every way the island closes forgets the lines

@MainActor
@Suite(.serialized, .noNewWindows)
struct EdgeCaseDraftCloseTests {
    private static let far = NSPoint(x: -10_000, y: -10_000)

    private func modelWithPanel() -> (AppModel, OverlayPanelController) {
        let model = AppModel(defaults: MemoryDefaults())
        model.disablesOverlayEventMonitoringDuringHarness = true
        model.overlay.pointerLocationProvider = { Self.far }
        model.nook.presentRingLight = { _ in }
        model.swipeGesturesEnabled = true
        model.overlay.ensureOverlayPanel()
        let controller = model.overlay.overlayPanelController
        // A click outside the panel would be posted to the real screen.
        controller.mouseDownReposter = { _ in }
        return (model, controller)
    }

    private func pill(_ controller: OverlayPanelController) -> NSPoint {
        NSPoint(x: controller.notchRect.midX, y: controller.notchRect.midY)
    }

    private func content(_ model: AppModel, _ controller: OverlayPanelController) throws -> NSPoint {
        let frame = try #require(controller.windowFrame)
        return NSPoint(x: frame.midX, y: frame.maxY - model.islandOpenedLayout.shapeHeight + 12)
    }

    private func swipe(dx: Double = 0, dy: Double = 0, on controller: OverlayPanelController, at point: NSPoint) {
        var samples = [IslandScrollSample(dx: 0, dy: 0, phase: .began, isMomentum: false, timestamp: 0)]
        for step in 1...4 {
            samples.append(IslandScrollSample(dx: dx / 4, dy: dy / 4, phase: .changed, isMomentum: false, timestamp: Double(step) * 0.01))
        }
        for sample in samples {
            _ = controller.handleScroll(sample, screenLocation: point, windowLocation: .zero, windowNumber: 0, isLocalEvent: true)
        }
    }

    enum Closer: CaseIterable {
        case notchClose, toggle, hide, clickOutside, notchClick, swipeUp, swipeSideways, cardGone, tourReleased
    }

    private func close(_ closer: Closer, _ model: AppModel, _ controller: OverlayPanelController) throws {
        switch closer {
        case .notchClose: model.notchClose()
        case .toggle: model.overlay.toggleOverlay()
        case .hide: model.hideOverlay()
        case .clickOutside: controller.handleMouseDown(Self.far, isLocalEvent: false)
        case .notchClick:
            controller.handleMouseDown(NSPoint(x: controller.notchRect.midX, y: controller.notchRect.maxY - 2), isLocalEvent: true)
        case .swipeUp: swipe(dy: 40, on: controller, at: try content(model, controller))
        case .swipeSideways: swipe(dx: 40, on: controller, at: pill(controller))
        case .cardGone:
            // The session a card showed is gone from the list.
            model.notchOpenReason = .notification
            model.islandSurface = .sessionList(actionableSessionID: "no-such-session")
            model.overlay.reconcileIslandSurfaceAfterStateChange()
        case .tourReleased: model.setTourHoldsIslandOpen(false)
        }
    }

    @Test(arguments: Closer.allCases)
    func aLineLeftSetWhenTheIslandClosesIsForgottenWhicheverWayItClosed(closer: Closer) throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()
        if closer == .tourReleased {
            model.setTourHoldsIslandOpen(true)
        } else {
            // A click opened island has a notch to click and a hover opened
            // one has not: the notch click is made on the first.
            model.notchOpen(reason: closer == .notchClick ? .click : .hover)
        }
        model.nook.setDraft(.note, isUnsaved: true)
        model.nook.setDraft(.timerEntry, isUnsaved: true)

        if closer == .clickOutside || closer == .swipeUp || closer == .swipeSideways {
            // A line holds the island against the pointer, not against these.
            #expect(model.overlay.shouldAutoCollapseOnMouseLeave == false)
        }
        try close(closer, model, controller)

        #expect(model.notchStatus == .closed, "\(closer)")
        #expect(model.nook.holdsUnsavedDraft == false, "\(closer)")

        // The next island opened by hover follows the pointer from the start.
        model.notchOpen(reason: .hover)
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave, "\(closer)")
        model.notchClose()
    }

    // MARK: Clicks with a line held

    @Test func aClickInsideAHoverOpenedIslandWithALineHeldChangesNothingAndKeepsTheLine() throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()
        model.notchOpen(reason: .hover)
        model.nook.setDraft(.note, isUnsaved: true)

        controller.handleMouseDown(try content(model, controller), isLocalEvent: true)
        controller.handleMouseDown(NSPoint(x: controller.notchRect.midX, y: controller.notchRect.maxY - 2), isLocalEvent: true)

        #expect(model.notchStatus == .opened)
        #expect(model.notchOpenReason == .hover)
        #expect(model.nook.holdsUnsavedDraft)
        model.notchClose()
    }

    @Test func aClickOutsideWithALineHeldClosesTheIslandAndDropsTheLine() throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()
        model.notchOpen(reason: .hover)
        model.nook.setDraft(.todo, isUnsaved: true)

        controller.handleMouseDown(Self.far, isLocalEvent: false)

        #expect(model.notchStatus == .closed)
        #expect(model.nook.holdsUnsavedDraft == false)
    }

    @Test func aClickOutsideWithALineHeldAndADecisionPendingStaysOpenAndKeepsTheLine() throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()
        var session = AgentSession(
            id: "waiting", title: "Claude · project", tool: .claudeCode,
            attachmentState: .attached, phase: .waitingForApproval, summary: "Approve", updatedAt: .now,
            permissionRequest: PermissionRequest(title: "Edit", summary: "x", affectedPath: "/tmp/x")
        )
        session.isProcessAlive = true
        model.state = SessionState(sessions: [session])
        model.keepNotchOpenUntilDecision = true
        model.notchOpen(reason: .hover)
        model.nook.setDraft(.note, isUnsaved: true)

        controller.handleMouseDown(Self.far, isLocalEvent: false)

        #expect(model.notchStatus == .opened)
        #expect(model.nook.holdsUnsavedDraft)
        model.keepNotchOpenUntilDecision = false
        model.notchClose()
    }

    // MARK: The pointer, through the controller

    @Test func thePointerLeavingAndComingBackWithALineHeldClosesOnlyAfterTheLineIsGone() throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()
        model.notchOpen(reason: .hover)
        let inside = try content(model, controller)
        model.nook.setDraft(.note, isUnsaved: true)

        controller.handleMouseMoved(Self.far)
        controller.handleMouseMoved(inside)
        controller.handleMouseMoved(Self.far)
        #expect(model.notchStatus == .opened)

        model.nook.setDraft(.note, isUnsaved: false)
        #expect(model.notchStatus == .opened, "clearing the line closes nothing by itself")
        controller.handleMouseMoved(Self.far)
        #expect(model.notchStatus == .closed)
    }

    @Test func aHoverOpenedIslandWithNoLineClosesOnTheFirstMoveOutAndNotWhileInside() throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()
        model.notchOpen(reason: .hover)
        let inside = try content(model, controller)

        controller.handleMouseMoved(inside)
        controller.handleMouseMoved(inside)
        #expect(model.notchStatus == .opened)
        controller.handleMouseMoved(Self.far)
        #expect(model.notchStatus == .closed)
    }

    // MARK: A late report

    /// The widgets report their line as it changes. One that reports "unsaved"
    /// after the island closed (a card still on screen for the fade) must
    /// not hold the next island, which the close comment promises starts clean.
    @Test func aLineReportedAfterTheIslandClosedDoesNotHoldTheNextOpenIsland() throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, _) = modelWithPanel()
        model.notchOpen(reason: .hover)
        model.notchClose()

        model.nook.setDraft(.note, isUnsaved: true)
        model.notchOpen(reason: .hover)
        let holdsNextIsland = !model.overlay.shouldAutoCollapseOnMouseLeave
        #expect(holdsNextIsland == false)
        model.notchClose()
    }
}
