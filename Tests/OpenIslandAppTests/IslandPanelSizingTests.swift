import AppKit
import Observation
import SwiftUI
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// Counts `withObservationTracking` change callbacks from a `@Sendable` closure.
private final class ChangeCounter: @unchecked Sendable {
    var count = 0
}

@MainActor
@Suite(.serialized)
struct IslandPanelSizingTests {
    // MARK: - resizeStep

    @Test
    func resizeStepGrowsWhenTheTargetIsTaller() {
        #expect(IslandPanelSizing.resizeStep(current: 300, target: 420) == .grow)
        #expect(IslandPanelSizing.resizeStep(current: 300, target: 300.51) == .grow)
    }

    @Test
    func resizeStepShrinksWhenTheTargetIsShorter() {
        #expect(IslandPanelSizing.resizeStep(current: 420, target: 300) == .shrink)
        #expect(IslandPanelSizing.resizeStep(current: 300, target: 299.49) == .shrink)
    }

    @Test
    func resizeStepIgnoresDifferencesInsideTheDeadZone() {
        #expect(IslandPanelSizing.resizeStep(current: 300, target: 300) == .none)
        #expect(IslandPanelSizing.resizeStep(current: 300, target: 300.5) == .none)
        #expect(IslandPanelSizing.resizeStep(current: 300, target: 299.5) == .none)
        #expect(IslandPanelSizing.resizeStep(current: 300, target: 300.25) == .none)
    }

    @Test
    func heightOnlyChangeKeepsTheTopEdgeAndWidth() {
        let current = NSRect(x: 100, y: 500, width: 576, height: 300)
        let taller = NSRect(x: 100, y: 380, width: 576, height: 420)
        let narrower = NSRect(x: 130, y: 380, width: 516, height: 420)
        let otherScreen = NSRect(x: 100, y: 1_580, width: 576, height: 300)

        #expect(IslandPanelSizing.isHeightOnlyChange(from: current, to: taller))
        #expect(!IslandPanelSizing.isHeightOnlyChange(from: current, to: narrower))
        #expect(!IslandPanelSizing.isHeightOnlyChange(from: current, to: otherScreen))
    }

    // MARK: - Content clamp and the Nook cap

    @Test
    func contentHeightIsNeverUnderTheMinimum() {
        #expect(IslandOpenedLayout.minimumContentHeight == 108)
        #expect(IslandOpenedLayout.clampedContentHeight(requested: 40, nookRoom: nil) == 108)
        #expect(IslandOpenedLayout.clampedContentHeight(requested: 108, nookRoom: nil) == 108)
        #expect(IslandOpenedLayout.clampedContentHeight(requested: 340, nookRoom: nil) == 340)
    }

    @Test
    func nookPageIsCappedToTheRoomOnScreen() {
        #expect(IslandOpenedLayout.clampedContentHeight(requested: 900, nookRoom: 540) == 540)
        #expect(IslandOpenedLayout.clampedContentHeight(requested: 400, nookRoom: 540) == 400)
        // A screen too short for the minimum still gets the minimum.
        #expect(IslandOpenedLayout.clampedContentHeight(requested: 900, nookRoom: 50) == 108)
        // Pages other than Nook ignore the screen cap.
        #expect(IslandOpenedLayout.clampedContentHeight(requested: 900, nookRoom: nil) == 900)
    }

    @Test
    func nookRoomSubtractsHeaderBottomInsetAndMargin() {
        let room = IslandOpenedLayout.nookContentRoom(
            screenMaxY: 982,
            visibleMinY: 80,
            headerHeight: 34,
            bottomPadding: 0,
            shadowBottomInset: IslandChromeMetrics.openedShadowBottomInset
        )
        // 982 - 80 - 34 - 0 - 22 - 8
        #expect(room == 838)
    }

    @Test
    func nookRoomUsesTheClosedIslandHeightNotTheSimulatedNotch() {
        // External display: the menu bar is 24pt, the simulated notch 38pt.
        // The header is the menu bar height now, so the Nook page gets 14pt more.
        let closedHeight = NSScreen.computeIslandClosedHeight(safeAreaInsetsTop: 0, topStatusBarHeight: 24)
        #expect(closedHeight == 24)
        #expect(NSScreen.externalDisplayNotchHeight == 38)

        func room(header: CGFloat) -> CGFloat {
            IslandOpenedLayout.nookContentRoom(
                screenMaxY: 1_080,
                visibleMinY: 0,
                headerHeight: header,
                bottomPadding: 0,
                shadowBottomInset: IslandChromeMetrics.openedShadowBottomInset
            )
        }

        #expect(room(header: closedHeight) - room(header: NSScreen.externalDisplayNotchHeight) == 14)
        let expected: CGFloat = 1_080 - 24 - 22 - 8
        #expect(room(header: closedHeight) == expected)
    }

    @Test
    func windowHeightIsTheShapePlusTheBottomShadowInset() {
        let layout = IslandOpenedLayout(headerHeight: 34, contentHeight: 300, bottomPadding: 0)
        #expect(layout.shapeHeight == 334)
        #expect(layout.windowHeight == 334 + IslandChromeMetrics.openedShadowBottomInset)
    }

    // MARK: - Refresh coalescing

    private func runOneMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @Test
    func threeRequestsInOneTurnPerformOneRefresh() async {
        let coordinator = OverlayUICoordinator()
        #expect(coordinator.performedLayoutRefreshCount == 0)

        coordinator.refreshOverlayPlacementIfVisible()
        coordinator.refreshOverlayPlacement()
        coordinator.scheduleLayoutRefresh()

        // Nothing runs inside the turn that asked.
        #expect(coordinator.performedLayoutRefreshCount == 0)

        await runOneMainQueueTurn()
        #expect(coordinator.performedLayoutRefreshCount == 1)

        // Later requests start a new turn, and a new refresh.
        coordinator.scheduleLayoutRefresh()
        coordinator.scheduleLayoutRefresh()
        await runOneMainQueueTurn()
        #expect(coordinator.performedLayoutRefreshCount == 2)
    }

    @Test
    func refreshNowRunsSynchronously() {
        let coordinator = OverlayUICoordinator()

        coordinator.refreshOverlayPlacementNow()

        #expect(coordinator.performedLayoutRefreshCount == 1)
    }

    @Test
    func contentChangesThroughTheModelCoalesce() async {
        let model = AppModel()
        let before = model.overlay.performedLayoutRefreshCount

        model.measuredNotificationContentHeight = 200
        model.measuredNotificationContentHeight = 260
        model.measuredNotificationContentHeight = 330
        #expect(model.overlay.performedLayoutRefreshCount == before)

        await runOneMainQueueTurn()
        #expect(model.overlay.performedLayoutRefreshCount == before + 1)
    }

    // MARK: - Publishing

    @Test
    func publishingAnEqualLayoutDoesNotTouchTheObservedValue() {
        let coordinator = OverlayUICoordinator()
        let layout = IslandOpenedLayout(headerHeight: 34, contentHeight: 200)
        coordinator.publishOpenedLayout(layout, screenID: "screen", animated: false)

        let changes = ChangeCounter()
        withObservationTracking {
            _ = coordinator.openedLayout
        } onChange: {
            changes.count += 1
        }

        coordinator.publishOpenedLayout(layout, screenID: "screen", animated: false)
        #expect(changes.count == 0)

        coordinator.publishOpenedLayout(
            IslandOpenedLayout(headerHeight: 34, contentHeight: 260),
            screenID: "screen",
            animated: false
        )
        #expect(changes.count == 1)
        #expect(coordinator.openedLayout.contentHeight == 260)
    }

    @Test
    func equalDiagnosticsCompareEqualAndDifferentFramesDoNot() {
        func diagnostics(overlayHeight: CGFloat, topInset: CGFloat = 37) -> OverlayPlacementDiagnostics {
            OverlayPlacementDiagnostics(
                targetScreenID: "display-notch",
                targetScreenName: "Built-in Display",
                selectionSummary: "test",
                mode: .notch,
                screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
                visibleFrame: NSRect(x: 0, y: 0, width: 1512, height: 944),
                safeAreaInsets: NSEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0),
                overlayFrame: NSRect(x: 400, y: 982 - overlayHeight, width: 576, height: overlayHeight)
            )
        }

        #expect(diagnostics(overlayHeight: 300) == diagnostics(overlayHeight: 300))
        #expect(diagnostics(overlayHeight: 300) != diagnostics(overlayHeight: 340))
        #expect(diagnostics(overlayHeight: 300) != diagnostics(overlayHeight: 300, topInset: 0))
    }

    // MARK: - Close snapshot

    private func notificationModel() -> AppModel {
        let model = AppModel()
        var session = AgentSession(
            id: "session-1",
            title: "Claude · project",
            tool: .claudeCode,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Approve edit",
            updatedAt: .now,
            permissionRequest: PermissionRequest(
                title: "Edit",
                summary: "file.swift",
                affectedPath: "/tmp/file.swift"
            )
        )
        session.isProcessAlive = true
        model.state = SessionState(sessions: [session])
        model.notchStatus = .opened
        model.notchOpenReason = .notification
        model.islandSurface = .sessionList(actionableSessionID: "session-1")
        return model
    }

    @Test
    func closeKeepsThePresentationWhileTheReasonClears() async throws {
        let model = notificationModel()
        #expect(model.openedPresentation.isNotificationMode)

        model.notchClose()

        // The reason and surface reset at once, as other code relies on.
        #expect(model.notchStatus == .closed)
        #expect(model.notchOpenReason == nil)
        #expect(model.islandSurface == .sessionList())
        // The view keeps drawing the notification while it fades.
        #expect(model.openedPresentation.isNotificationMode)
        #expect(model.openedPresentation.openReason == .notification)
        #expect(model.openedPresentation.surface == .sessionList(actionableSessionID: "session-1"))

        // Once the opened surface has unmounted, the snapshot is gone.
        try await Task.sleep(for: .seconds(Motion.openedSurfaceUnmountDelay + 0.25))
        #expect(model.overlay.closingPresentation == nil)
        #expect(!model.openedPresentation.isNotificationMode)
        #expect(model.openedPresentation.openReason == nil)
    }

    @Test
    func aSecondCloseDuringTheFadeKeepsTheFirstSnapshot() {
        let model = notificationModel()

        model.notchClose()
        model.notchClose()

        #expect(model.openedPresentation.isNotificationMode)
        #expect(model.openedPresentation.surface.sessionID == "session-1")
    }

    @Test
    func openingAgainDropsTheSnapshotAtOnce() {
        let model = notificationModel()
        model.notchClose()
        #expect(model.overlay.closingPresentation != nil)

        model.notchOpen(reason: .click)

        #expect(model.overlay.closingPresentation == nil)
        #expect(model.notchStatus == .opened)
        #expect(!model.openedPresentation.isNotificationMode)
    }

    // MARK: - Visible shape hit area

    @Test
    func visibleShapeRectIsTopAnchoredAndInsetBothSides() {
        let bounds = NSRect(x: 0, y: 0, width: 576, height: 400)

        let rect = IslandPanelSizing.visibleShapeRect(in: bounds, shapeHeight: 300, horizontalInset: 18)

        #expect(rect == NSRect(x: 18, y: 100, width: 540, height: 300))
        // Inside the shape, near the top and near its bottom edge.
        #expect(rect.contains(NSPoint(x: 288, y: 395)))
        #expect(rect.contains(NSPoint(x: 288, y: 101)))
        // Below the shape (still inside the taller window) and in the side insets.
        #expect(!rect.contains(NSPoint(x: 288, y: 60)))
        #expect(!rect.contains(NSPoint(x: 10, y: 300)))
        #expect(!rect.contains(NSPoint(x: 570, y: 300)))
    }

    @Test
    func visibleShapeRectFollowsTheTopOfAWindowOffTheOrigin() {
        // Screen coordinates: the window hangs from the top of the screen.
        let frame = NSRect(x: 468, y: 582, width: 576, height: 400)

        let rect = IslandPanelSizing.visibleShapeRect(in: frame, shapeHeight: 250, horizontalInset: 18)

        #expect(rect.maxY == frame.maxY)
        #expect(rect.minY == frame.maxY - 250)
        #expect(rect.minX == frame.minX + 18)
    }

    @Test
    func visibleShapeRectNeverExceedsTheWindow() {
        let bounds = NSRect(x: 0, y: 0, width: 576, height: 200)

        let rect = IslandPanelSizing.visibleShapeRect(in: bounds, shapeHeight: 500, horizontalInset: 18)

        #expect(rect.height == 200)
        #expect(rect.minY == 0)
    }

    @Test
    func contentRectUsesTheVisibleShapeWhileOpenAndTheWindowWhileClosed() {
        let model = AppModel()
        let controller = OverlayPanelController()
        let bounds = NSRect(x: 0, y: 0, width: 576, height: 400)
        model.overlay.openedLayout = IslandOpenedLayout(headerHeight: 32, contentHeight: 200)

        model.notchStatus = .opened
        #expect(controller.contentRect(for: model, in: bounds) == NSRect(x: 18, y: 168, width: 540, height: 232))

        // Closed behavior is unchanged: everything above the bottom shadow inset.
        model.notchStatus = .closed
        #expect(controller.contentRect(for: model, in: bounds) == NSRect(x: 18, y: 22, width: 540, height: 378))
    }

    @Test
    func hostingViewIgnoresClicksBelowTheVisibleShape() {
        let model = AppModel()
        let controller = OverlayPanelController()
        controller.model = model
        model.overlay.openedLayout = IslandOpenedLayout(headerHeight: 32, contentHeight: 200)
        model.notchStatus = .opened

        let hostingView = NotchHostingView(rootView: Color.clear)
        hostingView.notchController = controller
        hostingView.frame = NSRect(x: 0, y: 0, width: 576, height: 400)

        #expect(hostingView.hitTest(NSPoint(x: 288, y: 380)) != nil)
        #expect(hostingView.hitTest(NSPoint(x: 288, y: 100)) == nil)
        #expect(hostingView.hitTest(NSPoint(x: 5, y: 380)) == nil)
    }

    // MARK: - Window frame, on real screens

    /// Drives a real panel through grow, a delayed shrink and a grow that
    /// cancels one. Skipped where no display is connected.
    @Test
    func windowGrowsAtOnceAndShrinksAfterTheSettleDelay() async throws {
        guard !NSScreen.screens.isEmpty else { return }

        let model = notificationModel()
        let coordinator = model.overlay
        model.measuredNotificationContentHeight = 300
        coordinator.ensureOverlayPanel()
        coordinator.refreshOverlayPlacementNow()
        let controller = coordinator.overlayPanelController
        let startingChanges = controller.frameChangeCount

        // Grow: the window is taller immediately, before anything animates.
        model.measuredNotificationContentHeight = 420
        coordinator.refreshOverlayPlacementNow()
        let grownLayout = coordinator.openedLayout
        let grownHeight = try #require(controller.windowFrame?.height)
        #expect(grownHeight == grownLayout.windowHeight)
        #expect(controller.frameChangeCount == startingChanges + 1)

        // Shrink: the shape's layout is smaller now, the window waits.
        model.measuredNotificationContentHeight = 220
        coordinator.refreshOverlayPlacementNow()
        let shrunkLayout = coordinator.openedLayout
        #expect(shrunkLayout.windowHeight < grownLayout.windowHeight)
        #expect(controller.windowFrame?.height == grownHeight)
        #expect(controller.frameChangeCount == startingChanges + 1)

        // A grow inside the settle window cancels the pending shrink.
        model.measuredNotificationContentHeight = 500
        coordinator.refreshOverlayPlacementNow()
        let regrownHeight = try #require(controller.windowFrame?.height)
        #expect(regrownHeight == coordinator.openedLayout.windowHeight)
        #expect(controller.frameChangeCount == startingChanges + 2)
        try await Task.sleep(for: .seconds(Motion.islandResizeSettle + 0.3))
        #expect(controller.windowFrame?.height == regrownHeight)
        #expect(controller.frameChangeCount == startingChanges + 2)

        // Shrink and wait: the window gives the space back after the delay.
        model.measuredNotificationContentHeight = 220
        coordinator.refreshOverlayPlacementNow()
        #expect(controller.windowFrame?.height == regrownHeight)
        try await Task.sleep(for: .seconds(Motion.islandResizeSettle + 0.3))
        #expect(controller.windowFrame?.height == coordinator.openedLayout.windowHeight)
        #expect(controller.frameChangeCount == startingChanges + 3)
    }

    // MARK: - Shrink timer and guards

    @Test
    func sameShrinkTargetKeepsTheTimerAndADifferentOneRestartsIt() {
        #expect(OverlayPanelController.shouldRestartShrinkTimer(pendingTarget: nil, newTarget: 300))
        #expect(!OverlayPanelController.shouldRestartShrinkTimer(pendingTarget: 300, newTarget: 300))
        #expect(!OverlayPanelController.shouldRestartShrinkTimer(pendingTarget: 300, newTarget: 300.4))
        #expect(OverlayPanelController.shouldRestartShrinkTimer(pendingTarget: 300, newTarget: 260))
    }

    @Test
    func shrinkDecisionNeverGoesBelowThePublishedLayoutWhileOpenOrClosing() {
        // Open: clamp to the published window height.
        #expect(OverlayPanelController.shrinkDecision(
            currentHeight: 500, resolvedTargetHeight: 200, publishedWindowHeight: 340,
            isOpened: true, hasClosingPresentation: false
        ) == .apply(height: 340))
        // Open and already at the published height: nothing to do.
        #expect(OverlayPanelController.shrinkDecision(
            currentHeight: 340, resolvedTargetHeight: 200, publishedWindowHeight: 340,
            isOpened: true, hasClosingPresentation: false
        ) == .skip)
        // Close fade: wait for the unmount.
        #expect(OverlayPanelController.shrinkDecision(
            currentHeight: 500, resolvedTargetHeight: 200, publishedWindowHeight: 340,
            isOpened: false, hasClosingPresentation: true
        ) == .deferUntilCloseFadeEnds)
        // Closed and settled: the resolved target applies.
        #expect(OverlayPanelController.shrinkDecision(
            currentHeight: 500, resolvedTargetHeight: 200, publishedWindowHeight: 340,
            isOpened: false, hasClosingPresentation: false
        ) == .apply(height: 200))
    }

    private func openedControllerWithPanel() throws -> (AppModel, OverlayPanelController) {
        let model = notificationModel()
        model.measuredNotificationContentHeight = 300
        model.overlay.ensureOverlayPanel()
        model.overlay.refreshOverlayPlacementNow()
        return (model, model.overlay.overlayPanelController)
    }

    @Test
    func repeatedSameTargetRefreshKeepsTheDeadlineAndAChangedTargetMovesIt() async throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = try openedControllerWithPanel()
        let coordinator = model.overlay
        var now = Date(timeIntervalSince1970: 1_000)
        controller.clock = { now }

        model.measuredNotificationContentHeight = 420
        coordinator.refreshOverlayPlacementNow()

        model.measuredNotificationContentHeight = 220
        coordinator.refreshOverlayPlacementNow()
        let firstDeadline = try #require(controller.pendingShrinkDeadline)

        now = now.addingTimeInterval(0.3)
        coordinator.refreshOverlayPlacementNow()
        #expect(controller.pendingShrinkDeadline == firstDeadline)

        model.measuredNotificationContentHeight = 180
        coordinator.refreshOverlayPlacementNow()
        let secondDeadline = try #require(controller.pendingShrinkDeadline)
        #expect(secondDeadline > firstDeadline)
    }

    @Test
    func delayedShrinkNeverGoesBelowThePublishedLayoutWhileOpen() throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = try openedControllerWithPanel()
        let coordinator = model.overlay

        model.measuredNotificationContentHeight = 420
        coordinator.refreshOverlayPlacementNow()
        // The model resolves a shorter target, but the view still draws a
        // layout this tall.
        let published = IslandOpenedLayout(headerHeight: 34, contentHeight: 380)
        coordinator.openedLayout = published
        model.measuredNotificationContentHeight = 120
        coordinator.refreshOverlayPlacementNow()
        coordinator.openedLayout = published

        controller.performPendingShrink()

        let height = try #require(controller.windowFrame?.height)
        #expect(height >= published.windowHeight)
    }

    @Test
    func delayedShrinkIsRescheduledDuringACloseFade() throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = try openedControllerWithPanel()
        let coordinator = model.overlay
        var now = Date(timeIntervalSince1970: 1_000)
        controller.clock = { now }

        model.measuredNotificationContentHeight = 420
        coordinator.refreshOverlayPlacementNow()
        let grownHeight = try #require(controller.windowFrame?.height)
        model.measuredNotificationContentHeight = 150
        coordinator.refreshOverlayPlacementNow()

        model.notchClose()
        #expect(coordinator.closingPresentation != nil)
        controller.performPendingShrink()

        #expect(controller.windowFrame?.height == grownHeight)
        let deadline = try #require(controller.pendingShrinkDeadline)
        #expect(deadline == now.addingTimeInterval(Motion.openedSurfaceUnmountDelay))
        now = deadline
    }

    @Test
    func keepOpenStripClickShrinksAndRepostsOnlyOutsideThePanel() throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = try openedControllerWithPanel()
        let coordinator = model.overlay
        model.keepNotchOpenUntilDecision = true
        // The preference is saved to the shared defaults. Put it back, or a
        // later test that expects the default reads this one's value.
        defer { model.keepNotchOpenUntilDecision = false }
        #expect(model.shouldBlockDismissWhileAwaitingDecision)
        var reposted: [NSPoint] = []
        controller.mouseDownReposter = { reposted.append($0) }

        model.measuredNotificationContentHeight = 420
        coordinator.refreshOverlayPlacementNow()
        model.measuredNotificationContentHeight = 150
        coordinator.refreshOverlayPlacementNow()
        let frame = try #require(controller.windowFrame)
        let layout = coordinator.openedLayout
        #expect(layout.windowHeight < frame.height)

        // In the leftover strip, below the shape and the shrunk window.
        let point = NSPoint(x: frame.midX, y: frame.minY + 2)
        controller.handleMouseDown(point, isLocalEvent: true)

        #expect(controller.windowFrame?.height == layout.windowHeight)
        #expect(controller.pendingShrinkDeadline == nil)
        #expect(model.notchStatus == .opened)
        #expect(reposted == [point])

        // A strip click that stays inside the panel is not reposted.
        reposted.removeAll()
        let inside = NSPoint(x: frame.midX, y: frame.maxY - layout.windowHeight + 1)
        controller.handleMouseDown(inside, isLocalEvent: true)
        #expect(reposted.isEmpty)
    }
}
