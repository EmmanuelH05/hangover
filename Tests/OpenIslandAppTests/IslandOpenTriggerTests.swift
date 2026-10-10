import AppKit
import Foundation
import Testing
@testable import OpenIslandApp

// MARK: - Pure rules

@Suite struct IslandPointerRulesTests {
    private static func context(
        status: NotchStatus,
        reason: NotchOpenReason? = nil,
        inClosedSurface: Bool = false,
        inExpandedArea: Bool = false,
        onNotch: Bool = false,
        blocksDismiss: Bool = false
    ) -> IslandClickContext {
        IslandClickContext(
            status: status,
            reason: reason,
            isInClosedSurface: inClosedSurface,
            isInExpandedArea: inExpandedArea,
            isOnNotch: onNotch,
            blocksDismiss: blocksDismiss
        )
    }

    // MARK: Hover

    @Test func hoverOpensOnlyInHoverMode() {
        #expect(IslandPointerRules.hoverOpens(trigger: .hover, isSuppressed: false))
        #expect(!IslandPointerRules.hoverOpens(trigger: .click, isSuppressed: false))
    }

    @Test func hoverStaysQuietRightAfterANotchClickClosedTheIsland() {
        #expect(!IslandPointerRules.hoverOpens(trigger: .hover, isSuppressed: true))
        #expect(!IslandPointerRules.hoverOpens(trigger: .click, isSuppressed: true))
    }

    // MARK: Clicks

    @Test func aClickOnTheClosedIslandOpensItAndAClickElsewhereDoesNothing() {
        #expect(IslandPointerRules.clickAction(Self.context(status: .closed, inClosedSurface: true)) == .open)
        #expect(IslandPointerRules.clickAction(Self.context(status: .closed)) == .none)
        #expect(IslandPointerRules.clickAction(Self.context(status: .popping, inClosedSurface: true)) == .none)
    }

    @Test func aClickOutsideTheOpenIslandClosesItUnlessADecisionIsPending() {
        for reason in [NotchOpenReason.click, .hover, .notification, .boot] {
            #expect(IslandPointerRules.clickAction(Self.context(status: .opened, reason: reason)) == .dismiss)
            #expect(
                IslandPointerRules.clickAction(Self.context(status: .opened, reason: reason, blocksDismiss: true))
                    == .holdForDecision
            )
        }
    }

    @Test func aClickInsideAHoverOpenedIslandPinsItWhereverItLands() {
        let body = Self.context(status: .opened, reason: .hover, inExpandedArea: true)
        let notch = Self.context(status: .opened, reason: .hover, inExpandedArea: true, onNotch: true)

        #expect(IslandPointerRules.clickAction(body) == .pin)
        #expect(IslandPointerRules.clickAction(notch) == .pin)
    }

    @Test func aSecondClickOnTheNotchClosesAHeldIslandButAClickOnItsContentDoesNot() {
        let notch = Self.context(status: .opened, reason: .click, inExpandedArea: true, onNotch: true)
        let body = Self.context(status: .opened, reason: .click, inExpandedArea: true)
        let pending = Self.context(
            status: .opened, reason: .click, inExpandedArea: true, onNotch: true, blocksDismiss: true
        )

        #expect(IslandPointerRules.clickAction(notch) == .closeFromNotch)
        #expect(IslandPointerRules.clickAction(body) == .none)
        #expect(IslandPointerRules.clickAction(pending) == .none)
    }

    @Test func clicksInsideCardsAndTheBootAnimationKeepTheirOwnRules() {
        for reason in [NotchOpenReason.notification, .boot] {
            let inside = Self.context(status: .opened, reason: reason, inExpandedArea: true, onNotch: true)
            #expect(IslandPointerRules.clickAction(inside) == .none)
        }
        #expect(IslandPointerRules.clickAction(Self.context(status: .opened, inExpandedArea: true)) == .none)
    }

    // MARK: Geometry

    @Test func theNotchToggleStaysInsideTheHeaderAndClearOfTheLanes() {
        // An external display: the notch is 38 tall, the opened header 24.
        let notch = CGRect(x: 865, y: 1_042, width: 190, height: 38)
        let toggle = IslandPointerRules.notchToggleRect(notchRect: notch, headerHeight: 24)

        #expect(toggle.maxY == notch.maxY)
        #expect(toggle.height == 24)
        #expect(toggle.minX == notch.minX + IslandPointerRules.notchToggleInset)
        #expect(toggle.maxX == notch.maxX - IslandPointerRules.notchToggleInset)

        // A MacBook: header and notch are the same height.
        let macbook = IslandPointerRules.notchToggleRect(
            notchRect: CGRect(x: 660, y: 950, width: 192, height: 32), headerHeight: 32
        )
        #expect(macbook.height == 32)
    }

    @Test func aDraggedFileCountsAsArrivingALittleBeforeTheClosedIsland() {
        let closed = CGRect(x: 800, y: 1_042, width: 280, height: 38)
        let zone = IslandPointerRules.fileDragZone(closedSurface: closed)

        #expect(zone.contains(CGPoint(x: 790, y: 1_050)))
        #expect(zone.contains(CGPoint(x: 940, y: 1_030)))
        #expect(!zone.contains(CGPoint(x: 940, y: 1_000)))
        #expect(!zone.contains(CGPoint(x: 700, y: 1_050)))
        #expect(zone.maxY == closed.maxY)
    }

    // MARK: Files arriving

    @Test func filesOpenTheClosedIslandOnlyWhenTheTrayIsOnThePage() {
        for status in [NotchStatus.closed, .popping] {
            #expect(IslandPointerRules.fileDragArrival(
                status: status, reason: nil, showsNookPage: false, trayIsOnPage: true
            ) == .openOnNook)
            #expect(IslandPointerRules.fileDragArrival(
                status: status, reason: nil, showsNookPage: false, trayIsOnPage: false
            ) == .acceptOnClosedPill)
        }
    }

    @Test func filesTurnAnOpenIslandToTheTrayButNeverPushACardAside() {
        #expect(IslandPointerRules.fileDragArrival(
            status: .opened, reason: .click, showsNookPage: false, trayIsOnPage: true
        ) == .turnToNook)
        #expect(IslandPointerRules.fileDragArrival(
            status: .opened, reason: .hover, showsNookPage: true, trayIsOnPage: true
        ) == .none)
        #expect(IslandPointerRules.fileDragArrival(
            status: .opened, reason: .notification, showsNookPage: false, trayIsOnPage: true
        ) == .none)
        #expect(IslandPointerRules.fileDragArrival(
            status: .opened, reason: .click, showsNookPage: false, trayIsOnPage: false
        ) == .none)
    }
}

// MARK: - File drag tracker

@Suite struct IslandFileDragTrackerTests {
    private static let fileTypes = ["public.file-url", "NSFilenamesPboardType"]

    /// A press somewhere else on screen with the drag pasteboard at 5.
    private static func pressed(insideIsland: Bool = false) -> IslandFileDragTracker {
        var tracker = IslandFileDragTracker()
        tracker.mouseDown(changeCount: 5, insideIsland: insideIsland)
        return tracker
    }

    @Test func aFileDragEntersLeavesComesBackAndEnds() {
        var tracker = Self.pressed()

        #expect(tracker.dragged(isPointerOverIsland: false, changeCount: { 6 }, types: { Self.fileTypes }) == .none)
        #expect(tracker.dragged(isPointerOverIsland: true, changeCount: { 6 }, types: { Self.fileTypes }) == .entered)
        #expect(tracker.dragged(isPointerOverIsland: true, changeCount: { 6 }, types: { Self.fileTypes }) == .none)
        #expect(tracker.dragged(isPointerOverIsland: false, changeCount: { 6 }, types: { Self.fileTypes }) == .left)
        #expect(tracker.dragged(isPointerOverIsland: true, changeCount: { 6 }, types: { Self.fileTypes }) == .entered)
        #expect(tracker.mouseUp() == .ended)
        #expect(tracker == IslandFileDragTracker())
    }

    @Test func aDragThatLeftBeforeTheMouseCameUpStillEnds() {
        var tracker = Self.pressed()
        _ = tracker.dragged(isPointerOverIsland: true, changeCount: { 6 }, types: { Self.fileTypes })
        _ = tracker.dragged(isPointerOverIsland: false, changeCount: { 6 }, types: { Self.fileTypes })

        #expect(tracker.mouseUp() == .ended)
    }

    @Test func draggedTextAndPromisedFilesDoNotCount() {
        var text = Self.pressed()
        var promise = Self.pressed()
        let promised = ["com.apple.pasteboard.promised-file-url", "com.apple.pasteboard.promised-file-content-type"]

        #expect(text.dragged(isPointerOverIsland: true, changeCount: { 6 }, types: { ["public.utf8-plain-text"] }) == .none)
        #expect(promise.dragged(isPointerOverIsland: true, changeCount: { 6 }, types: { promised }) == .none)
        #expect(text.mouseUp() == .none)
    }

    @Test func aDragThatPutNothingOnThePasteboardNeverReadsItsTypes() {
        // A window being moved or a slider: the last file drag is still on
        // the pasteboard, but its count has not moved since the press.
        var tracker = Self.pressed()
        var typeReads = 0

        let step = tracker.dragged(isPointerOverIsland: true, changeCount: { 5 }, types: {
            typeReads += 1
            return Self.fileTypes
        })

        #expect(step == .none)
        #expect(typeReads == 0)
    }

    @Test func thePasteboardIsNotAskedWhileThePointerIsAwayFromTheIsland() {
        var tracker = Self.pressed()
        var reads = 0

        _ = tracker.dragged(isPointerOverIsland: false, changeCount: {
            reads += 1
            return 6
        }, types: {
            reads += 1
            return Self.fileTypes
        })

        #expect(reads == 0)
    }

    @Test func aPressThatBeganOnTheIslandIsNeverAFileComingIn() {
        // A tray file being dragged out, or a widget being moved.
        var tracker = Self.pressed(insideIsland: true)

        #expect(tracker.dragged(isPointerOverIsland: true, changeCount: { 6 }, types: { Self.fileTypes }) == .none)
        #expect(tracker.mouseUp() == .none)
    }

    @Test func aDragWhosePressWasNeverSeenIsIgnored() {
        var tracker = IslandFileDragTracker()

        #expect(tracker.dragged(isPointerOverIsland: true, changeCount: { 6 }, types: { Self.fileTypes }) == .none)
    }

    @Test func aNewPressStartsOver() {
        var tracker = Self.pressed()
        _ = tracker.dragged(isPointerOverIsland: true, changeCount: { 6 }, types: { Self.fileTypes })

        tracker.mouseDown(changeCount: 6, insideIsland: false)

        #expect(!tracker.isOverIsland)
        #expect(!tracker.hasReachedIsland)
        // The same pasteboard content is now the baseline, not a new drag.
        #expect(tracker.dragged(isPointerOverIsland: true, changeCount: { 6 }, types: { Self.fileTypes }) == .none)
    }
}

// MARK: - Setting and live behavior

@MainActor
@Suite(.serialized, .noNewWindows)
struct IslandOpenTriggerTests {
    private static let far = NSPoint(x: -10_000, y: -10_000)
    /// Comfortably past `AppModel.hoverOpenDelay`.
    private static let hoverWait: Duration = .milliseconds(500)

    /// A model with a real panel, kept off screen, and no live mouse monitors. Only the
    /// events a test sends reach the controller.
    private func modelWithPanel() -> (AppModel, OverlayPanelController) {
        let model = AppModel(defaults: MemoryDefaults())
        model.disablesOverlayEventMonitoringDuringHarness = true
        model.overlay.pointerLocationProvider = { Self.far }
        model.overlay.ensureOverlayPanel()
        return (model, model.overlay.overlayPanelController)
    }

    private func pill(_ controller: OverlayPanelController) -> NSPoint {
        NSPoint(x: controller.notchRect.midX, y: controller.notchRect.midY)
    }

    /// Inside the open island's content, well below the header.
    private func content(_ model: AppModel, _ controller: OverlayPanelController) throws -> NSPoint {
        let frame = try #require(controller.windowFrame)
        return NSPoint(x: frame.midX, y: frame.maxY - model.islandOpenedLayout.shapeHeight + 12)
    }

    // MARK: Setting

    @Test func theIslandOpensOnHoverUnlessToldOtherwise() {
        let defaults = MemoryDefaults()
        #expect(AppModel(defaults: defaults).islandOpenTrigger == .hover)

        defaults.set("sideways", forKey: AppModel.islandOpenTriggerDefaultsKey)
        #expect(AppModel(defaults: defaults).islandOpenTrigger == .hover)
    }

    @Test func theChoiceIsSaved() {
        let defaults = MemoryDefaults()
        let model = AppModel(defaults: defaults)
        model.islandOpenTrigger = .click
        #expect(AppModel(defaults: defaults).islandOpenTrigger == .click)

        model.islandOpenTrigger = .hover
        #expect(AppModel(defaults: defaults).islandOpenTrigger == .hover)
    }

    @Test func everySettingStringExistsInEveryLanguage() throws {
        let keys = [IslandOpenTrigger.settingTitleKey, IslandOpenTrigger.filesNoteKey]
            + IslandOpenTrigger.allCases.flatMap { [$0.titleKey, $0.noteKey] }
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        for language in ["en", "zh-Hans", "zh-Hant"] {
            let url = root.appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String], "\(language) did not load")
            for key in keys {
                #expect(!(table[key] ?? "").isEmpty, "\(language) is missing \(key)")
            }
        }
    }

    // MARK: Pinning

    @Test func pinningAHoverOpenedIslandStopsItFollowingThePointer() {
        let model = AppModel(defaults: MemoryDefaults())
        model.notchStatus = .opened
        model.notchOpenReason = .hover
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave)

        model.pinHoverOpenedIsland()

        #expect(model.notchOpenReason == .click)
        #expect(!model.overlay.shouldAutoCollapseOnMouseLeave)
    }

    @Test func pinningLeavesCardsAndAClosedIslandAlone() {
        let model = AppModel(defaults: MemoryDefaults())
        model.notchStatus = .opened
        model.notchOpenReason = .notification
        model.pinHoverOpenedIsland()
        #expect(model.notchOpenReason == .notification)

        model.notchStatus = .closed
        model.notchOpenReason = nil
        model.pinHoverOpenedIsland()
        #expect(model.notchOpenReason == nil)
    }

    @Test func aClickInsideAHoverOpenedIslandPinsIt() throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()
        model.notchOpen(reason: .hover)

        controller.handleMouseDown(try content(model, controller), isLocalEvent: true)

        #expect(model.notchStatus == .opened)
        #expect(model.notchOpenReason == .click)
        model.notchClose()
    }

    // MARK: Hover and click modes

    @Test func hoverModeOpensWhenThePointerRestsOnTheIsland() async throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()

        controller.handleMouseMoved(pill(controller))
        try await Task.sleep(for: Self.hoverWait)

        #expect(model.notchStatus == .opened)
        #expect(model.notchOpenReason == .hover)
        model.notchClose()
    }

    @Test func clickModeIgnoresHoverAndOpensOnAClickThatStays() async throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()
        model.islandOpenTrigger = .click


        controller.handleMouseMoved(pill(controller))
        try await Task.sleep(for: Self.hoverWait)
        #expect(model.notchStatus == .closed)

        controller.handleMouseDown(pill(controller), isLocalEvent: false)
        #expect(model.notchStatus == .opened)
        #expect(model.notchOpenReason == .click)

        // The pointer leaves. A click-opened island stays.
        controller.handleMouseMoved(Self.far)
        #expect(model.notchStatus == .opened)

        // A click outside closes it.
        controller.handleMouseDown(Self.far, isLocalEvent: false)
        #expect(model.notchStatus == .closed)
    }

    @Test func aSecondClickOnTheNotchClosesTheIslandAndHoverWaitsForThePointerToLeave() async throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()
        let notch = NSPoint(x: controller.notchRect.midX, y: controller.notchRect.maxY - 2)

        controller.handleMouseDown(pill(controller), isLocalEvent: false)
        #expect(model.notchOpenReason == .click)

        controller.handleMouseDown(notch, isLocalEvent: true)
        #expect(model.notchStatus == .closed)
        #expect(controller.isHoverSuppressedUntilExit)

        // Still on the notch: hover mode must not open it again.
        controller.handleMouseMoved(pill(controller))
        try await Task.sleep(for: Self.hoverWait)
        #expect(model.notchStatus == .closed)

        // Once the pointer has left, hover works as before.
        controller.handleMouseMoved(Self.far)
        #expect(!controller.isHoverSuppressedUntilExit)
        controller.handleMouseMoved(pill(controller))
        try await Task.sleep(for: Self.hoverWait)
        #expect(model.notchStatus == .opened)
        model.notchClose()
    }

    // MARK: Files dragged to the island

    @Test func aFileDraggedToTheClosedIslandOpensItOrIsTakenByThePill() throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()
        var changeCount = 5
        controller.dragPasteboardChangeCount = { changeCount }
        controller.dragPasteboardTypes = { ["public.file-url"] }
        let trayIsOnPage = model.nookVisibleWidgets.contains(.tray)

        // The press lands on a file somewhere else, then the drag begins.
        controller.handleMouseDown(Self.far, isLocalEvent: false)
        changeCount = 6
        controller.handleMouseDragged(pill(controller))

        #expect(model.nook.tray.isFileDragOverIsland)
        if trayIsOnPage {
            #expect(model.notchStatus == .opened)
            #expect(model.notchOpenReason == .hover)
            #expect(model.showsNookPage)
            #expect(!controller.isClosedPanelDragReceptive)
        } else {
            #expect(model.notchStatus == .closed)
            #expect(controller.isClosedPanelDragReceptive)
        }

        // Off the island with the button still down: nothing closes.
        controller.handleMouseDragged(Self.far)
        #expect(!model.nook.tray.isFileDragOverIsland)
        #expect(!controller.isClosedPanelDragReceptive)
        #expect(model.notchStatus == (trayIsOnPage ? .opened : .closed))

        // Back over it, then the drop.
        controller.handleMouseDragged(trayIsOnPage ? try content(model, controller) : pill(controller))
        #expect(model.nook.tray.isFileDragOverIsland)
        controller.handleMouseUp()
        #expect(!model.nook.tray.isFileDragOverIsland)
        #expect(model.notchStatus == (trayIsOnPage ? .opened : .closed))

        // The drag is over. The island closes once the pointer has left it.
        controller.handleMouseMoved(Self.far)
        #expect(model.notchStatus == .closed)
    }

    @Test func aFileDragOpensTheIslandInClickModeToo() throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()
        guard model.nookVisibleWidgets.contains(.tray) else { return }
        model.islandOpenTrigger = .click

        var changeCount = 5
        controller.dragPasteboardChangeCount = { changeCount }
        controller.dragPasteboardTypes = { ["NSFilenamesPboardType"] }

        controller.handleMouseDown(Self.far, isLocalEvent: false)
        changeCount = 6
        controller.handleMouseDragged(pill(controller))

        #expect(model.notchStatus == .opened)
        #expect(model.showsNookPage)
        controller.handleMouseUp()
        controller.handleMouseMoved(Self.far)
        #expect(model.notchStatus == .closed)
    }

    @Test func otherDragsOverTheIslandLeaveItClosed() {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()
        var changeCount = 5
        var types = ["public.utf8-plain-text"]
        controller.dragPasteboardChangeCount = { changeCount }
        controller.dragPasteboardTypes = { types }

        // Dragged text.
        controller.handleMouseDown(Self.far, isLocalEvent: false)
        changeCount = 6
        controller.handleMouseDragged(pill(controller))
        controller.handleMouseUp()
        #expect(model.notchStatus == .closed)

        // A window being moved: files from the last drag are still on the
        // pasteboard, but nothing new was put there.
        types = ["public.file-url"]
        controller.handleMouseDown(Self.far, isLocalEvent: false)
        controller.handleMouseDragged(pill(controller))
        controller.handleMouseUp()
        #expect(model.notchStatus == .closed)
        #expect(!model.nook.tray.isFileDragOverIsland)
        #expect(!controller.isClosedPanelDragReceptive)
    }

    @Test func aMissedMouseUpIsCaughtByTheNextPointerMove() throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()
        var changeCount = 5
        controller.dragPasteboardChangeCount = { changeCount }
        controller.dragPasteboardTypes = { ["public.file-url"] }

        controller.handleMouseDown(Self.far, isLocalEvent: false)
        changeCount = 6
        controller.handleMouseDragged(pill(controller))
        #expect(model.nook.tray.isFileDragOverIsland)

        // No mouse-up arrives. The pointer only moves with the button up.
        controller.handleMouseMoved(Self.far)

        #expect(!model.nook.tray.isFileDragOverIsland)
        #expect(!controller.fileDrag.hasReachedIsland)
        #expect(model.notchStatus == .closed)
    }
}

// MARK: - Tray

@Suite struct NookTrayDropTests {
    @Test func aFileAlreadyInTheTrayFolderIsNotCopiedInAgain() {
        let folder = URL(fileURLWithPath: "/Users/demo/Library/Application Support/OpenIsland/Tray", isDirectory: true)
        let stored = folder.appendingPathComponent("0B6C/report.pdf")
        let desktop = URL(fileURLWithPath: "/Users/demo/Desktop/report.pdf")
        let lookalike = URL(fileURLWithPath: "/Users/demo/Library/Application Support/OpenIsland/Tray-old/report.pdf")

        #expect(NookTrayStore.isInside(folder, stored))
        #expect(!NookTrayStore.isInside(folder, desktop))
        #expect(!NookTrayStore.isInside(folder, lookalike))
    }
}
