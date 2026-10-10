import AppKit
import Combine
import OSLog
import SwiftUI
import OpenIslandCore

private let overlayLog = Logger(subsystem: "app.openisland", category: "overlay")

/// `OPEN_ISLAND_TRACE_OVERLAY=1` logs every requested and performed layout
/// refresh and every window frame change. The signposts are always on; they
/// cost nothing unless Instruments is recording.
enum OverlayTrace {
    static let isEnabled = ProcessInfo.processInfo.environment["OPEN_ISLAND_TRACE_OVERLAY"] == "1"
    static let signposter = OSSignposter(subsystem: "app.openisland", category: "overlay")

    /// Logs `message` when tracing is on. The message is not built otherwise.
    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let text = message()
        overlayLog.notice("\(text, privacy: .public)")
    }
}

/// Where the island window goes on a screen and how tall the opened island
/// is there. Resolving it has no side effects.
struct IslandPlacement {
    let screen: NSScreen
    let screenID: String
    let layout: IslandOpenedLayout
    /// Target window frame: `layout.windowHeight` tall, top-anchored.
    let frame: NSRect
}

/// What one `updatePlacement` call found and did.
struct IslandPlacementUpdate {
    let placement: IslandPlacement
    let diagnostics: OverlayPlacementDiagnostics?
}

@MainActor
final class OverlayPanelController {
    /// Width the text of a card is measured at under the standard opened
    /// look. A card is as wide as the island at every look (D35); a wider
    /// look adds its extra page width to this measure.
    private static let preferredNotificationPanelWidth: CGFloat = 620
    private static let openedContentWidthPadding: CGFloat = 0
    private static let openedContentBottomPadding: CGFloat = 0
    /// Must match `IslandPanelView.maxSessionListHeight` — the AutoHeightScrollView cap.
    private static let maxSessionListHeight: CGFloat = 560
    private static let maxVisibleSessionRows: Int = 6
    private static let openedRowSpacing: CGFloat = 0
    // Content padding top + scroll padding + v8 list header/footer + bottom inset.
    // Rows are now full-width scan rows, so the old inter-card spacing is gone.
    private static let openedContentVerticalInsets: CGFloat = 84
    private static let notificationMeasuredContentPadding: CGFloat = 8
    private static let notificationEstimatedVerticalInsets: CGFloat = 36
    private static let openedEmptyStateHeight: CGFloat = IslandOpenedLayout.minimumContentHeight
    private static let questionCardBaseHeight: CGFloat = 110
    private static let questionCardMaxHeight: CGFloat = 420
    // Completion card chrome breakdown (everything except the scrollable text):
    // openedContent vertical padding: 24, card container padding: 28,
    // card VStack spacing: 14, card header (title+prompt): ~50,
    // completionBody header ("You:"/Done row): ~42, divider: 1,
    // text area vertical padding: 28  →  total ≈ 187
    private static let completionCardChromeHeight: CGFloat = 187
    private static let completionCardMinHeight: CGFloat = 210
    private static let completionCardMaxHeight: CGFloat = 400

    private var panel: NotchPanel?
    private var eventMonitors = NotchEventMonitors()
    /// Follows the scroll events over the island to tell a swipe (D46).
    private var swipe = IslandSwipeRecognizer()
    private var lastStrayClickRepair: Date = .distantPast
    private var hoverTimer: DispatchWorkItem?
    private var hoverCancelGrace: DispatchWorkItem?
    /// Set when a click on the notch closed the island, until the pointer
    /// has left the closed island once (`IslandPointerRules.hoverOpens`).
    private(set) var isHoverSuppressedUntilExit = false
    /// Tells a file drag from any other drag for the press in progress.
    private(set) var fileDrag = IslandFileDragTracker()
    /// True while the closed panel takes mouse events only to be offered a
    /// file drop on the pill.
    private(set) var isClosedPanelDragReceptive = false
    private var pendingDragReceptiveRestore: DispatchWorkItem?
    weak var model: AppModel?
    private(set) var notchRect: NSRect = .zero

    /// A window shrink waiting for the shape to finish animating (see
    /// `scheduleShrink`). Cancelled by a grow, a screen change or a refresh
    /// that finds nothing to shrink.
    private var pendingShrink: DispatchWorkItem?
    /// A narrower frame waiting for a close fade to end.
    private var pendingWidthChange: DispatchWorkItem?
    /// The window height the pending shrink was asked for. A refresh that
    /// asks for the same height keeps the deadline instead of restarting it.
    private(set) var pendingShrinkTargetHeight: CGFloat?
    /// When the pending shrink is due, by `clock`. Nil when none is pending.
    private(set) var pendingShrinkDeadline: Date?

    /// Test seam for time: the shrink deadline is computed from it.
    var clock: () -> Date = { Date() }
    /// Test seam for the synthetic click, which would otherwise be posted
    /// to the real screen.
    var mouseDownReposter: ((NSPoint) -> Void)?
    /// Test seams for the drag pasteboard. Only its change count and its
    /// types are ever read, never what is on it.
    var dragPasteboardChangeCount: () -> Int = { NSPasteboard(name: .drag).changeCount }
    var dragPasteboardTypes: () -> [String] = { NSPasteboard(name: .drag).types?.map(\.rawValue) ?? [] }
    /// The display the last placement asked for, so a delayed shrink can
    /// resolve the same screen.
    private var lastPreferredScreenID: String?

    /// How many times the window frame was set after the panel existed.
    /// `HarnessArtifactRecorder` writes it into report.json.
    private(set) var frameChangeCount = 0

    /// Called after a delayed shrink changed the frame, so the coordinator
    /// can refresh the diagnostics that carry the frame height.
    var onDeferredFrameChange: (@MainActor () -> Void)?

    var isVisible: Bool {
        panel?.isVisible == true
    }

    var hasPanel: Bool {
        panel != nil
    }

    /// The island window's current frame, nil before the panel exists.
    var windowFrame: NSRect? {
        panel?.frame
    }

    /// A click opens the island with the keyboard. The tour's hold (D44)
    /// never does: Return, Escape and the arrows stay with the tour's window.
    nonisolated static func shouldActivatePanel(for reason: NotchOpenReason?, holdsOpenForTour: Bool = false) -> Bool {
        reason == .click && !holdsOpenForTour
    }

    func availableDisplayOptions() -> [OverlayDisplayOption] {
        OverlayDisplayResolver.availableDisplayOptions()
    }

    func ensurePanel(model: AppModel, preferredScreenID: String?) {
        self.model = model
        lastPreferredScreenID = preferredScreenID
        let panel = self.panel ?? makePanel(model: model)
        self.panel = panel
        positionPanel(preferredScreenID: preferredScreenID)
        panel.orderFrontRegardless()
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = false
        startEventMonitoring()
    }

    func show(model: AppModel, preferredScreenID: String?) -> OverlayPlacementDiagnostics? {
        self.model = model
        lastPreferredScreenID = preferredScreenID
        let panel = self.panel ?? makePanel(model: model)
        self.panel = panel
        let diagnostics = positionPanel(preferredScreenID: preferredScreenID)
        presentPanel(panel, activates: Self.shouldActivatePanel(
            for: model.notchOpenReason,
            holdsOpenForTour: model.tourHoldsIslandOpen
        ))
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        startEventMonitoring()
        return diagnostics
    }

    func hide() {
        panel?.ignoresMouseEvents = true
        panel?.acceptsMouseMovedEvents = false
    }

    func setInteractive(_ interactive: Bool) {
        guard let panel else {
            return
        }

        panel.ignoresMouseEvents = !interactive
        panel.acceptsMouseMovedEvents = interactive

        if interactive {
            presentPanel(panel, activates: Self.shouldActivatePanel(
                for: model?.notchOpenReason,
                holdsOpenForTour: model?.tourHoldsIslandOpen ?? false
            ))
        }
    }

    /// Where the opened island sits and the screen it is on, for the
    /// welcome tour to step aside (D44). Works while the island is closed:
    /// it is the frame the island opens into. The screen is its visible
    /// frame, the island the part of the window the shape covers.
    func openedIslandFootprint(model: AppModel?, preferredScreenID: String?) -> OnboardingIslandFootprint? {
        guard let placement = resolvePlacement(model: model ?? self.model, preferredScreenID: preferredScreenID) else {
            return nil
        }
        return OnboardingIslandFootprint(
            screen: placement.screen.visibleFrame,
            island: placement.frame.insetBy(dx: panelShadowInsets.horizontal, dy: 0)
        )
    }

    func placementDiagnostics(preferredScreenID: String?) -> OverlayPlacementDiagnostics? {
        let panelSize = panel?.frame.size ?? OverlayDisplayResolver.defaultPanelSize
        return OverlayDisplayResolver.diagnostics(preferredScreenID: preferredScreenID, panelSize: panelSize)
    }

    // MARK: - Panel creation

    private func makePanel(model: AppModel) -> NotchPanel {
        let windowFrame = resolvePlacement(model: model, preferredScreenID: lastPreferredScreenID)?.frame ?? .zero

        let panel = NotchPanel(
            contentRect: windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .statusBar
        panel.sharingType = .readOnly
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = false
        // `.stationary` keeps the overlay pinned during the macOS Sonoma+
        // "click wallpaper to reveal desktop" gesture (and Mission Control
        // / Show Desktop). Without it the panel slides off-screen with the
        // user's other windows — on built-in notch displays it disappears
        // below the menu bar, and on external displays it falls out of the
        // top bar entirely.
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle, .stationary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.ignoresMouseEvents = true

        let hostingView = NotchHostingView(rootView: IslandPanelView(model: model))
        hostingView.notchController = self
        panel.contentView = hostingView
        panel.notchController = self

        computeNotchRect(screen: resolveTargetScreen(preferredScreenID: lastPreferredScreenID))
        return panel
    }

    // MARK: - Positioning

    private enum FrameChange: String {
        case grow
        case shrink
        case screen
    }

    @discardableResult
    private func positionPanel(preferredScreenID: String?) -> OverlayPlacementDiagnostics? {
        updatePlacement(model: model, preferredScreenID: preferredScreenID)?.diagnostics
    }

    /// Resolves the placement for `model` and, when a panel exists, applies
    /// the window frame: a taller target at once (before the shape grows
    /// into it), a shorter one after `Motion.islandResizeSettle` (after the
    /// shape has shrunk), and a different screen or width exactly and at
    /// once. Returns nil only when no display is connected.
    func updatePlacement(model: AppModel?, preferredScreenID: String?) -> IslandPlacementUpdate? {
        lastPreferredScreenID = preferredScreenID
        guard let placement = resolvePlacement(model: model ?? self.model, preferredScreenID: preferredScreenID) else {
            return nil
        }

        if let panel {
            applyFrame(for: placement, to: panel)
            computeNotchRect(screen: placement.screen)
        }

        return IslandPlacementUpdate(
            placement: placement,
            diagnostics: placementDiagnostics(preferredScreenID: preferredScreenID)
        )
    }

    /// The screen, the opened layout and the window frame for `model`. No
    /// side effects, so the coordinator can call it to learn the target
    /// before it publishes the layout.
    func resolvePlacement(model: AppModel?, preferredScreenID: String?) -> IslandPlacement? {
        guard let screen = resolveTargetScreen(preferredScreenID: preferredScreenID) else {
            return nil
        }

        let layout = openedLayout(for: model, on: screen)
        return IslandPlacement(
            screen: screen,
            screenID: OverlayDisplayResolver.screenID(for: screen),
            layout: layout,
            frame: panelFrame(for: layout, on: screen)
        )
    }

    private func applyFrame(for placement: IslandPlacement, to panel: NSPanel) {
        let current = panel.frame
        let target = placement.frame

        guard IslandPanelSizing.isHeightOnlyChange(from: current, to: target) else {
            // A narrower look chosen while the island fades out: the fading
            // shape still has the old width, and a window cut to the new
            // one would clip its sides. Wait for the fade and come back.
            if let model, model.notchStatus != .opened, model.overlay.closingPresentation != nil,
               IslandPanelSizing.isNarrowing(from: current, to: target) {
                armWidthChange()
                return
            }
            // Another screen or width with nothing mid-animation that the
            // old frame has to protect: apply the exact frame now.
            cancelPendingShrink()
            cancelPendingWidthChange()
            if current != target {
                setFrame(target, change: .screen, on: panel)
            }
            return
        }
        cancelPendingWidthChange()

        switch IslandPanelSizing.resizeStep(current: current.height, target: target.height) {
        case .grow:
            cancelPendingShrink()
            // Grow before the shape animates so it never draws past the window.
            panel.disableScreenUpdatesUntilFlush()
            setFrame(target, change: .grow, on: panel)
        case .shrink:
            scheduleShrink(toHeight: target.height)
        case .none:
            cancelPendingShrink()
        }
    }

    /// Gives the space back `Motion.islandResizeSettle` after the shape has
    /// started shrinking. A refresh that asks for a different height
    /// restarts the wait, so a run of small steps (a resize grip drag)
    /// shrinks the window once. A refresh that asks for the same height
    /// keeps the deadline: agent events arrive faster than the settle delay,
    /// and restarting on each of them would hold the old, taller window
    /// (and its transparent strip) for as long as they keep coming.
    private func scheduleShrink(toHeight targetHeight: CGFloat) {
        if pendingShrink != nil,
           !Self.shouldRestartShrinkTimer(pendingTarget: pendingShrinkTargetHeight, newTarget: targetHeight) {
            OverlayTrace.log("shrink to \(targetHeight) already pending, deadline kept")
            return
        }

        armShrink(after: Motion.islandResizeSettle, targetHeight: targetHeight)
    }

    private func armShrink(after delay: TimeInterval, targetHeight: CGFloat) {
        pendingShrink?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.performPendingShrink()
        }
        pendingShrink = item
        pendingShrinkTargetHeight = targetHeight
        pendingShrinkDeadline = clock().addingTimeInterval(delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Comes back for a narrower frame once the close fade has had time to
    /// unmount the opened surface.
    private func armWidthChange() {
        pendingWidthChange?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, let panel = self.panel, let model = self.model,
                  let placement = self.resolvePlacement(model: model, preferredScreenID: self.lastPreferredScreenID)
            else { return }
            self.pendingWidthChange = nil
            self.applyFrame(for: placement, to: panel)
            self.onDeferredFrameChange?()
        }
        pendingWidthChange = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Motion.openedSurfaceUnmountDelay, execute: item)
    }

    private func cancelPendingWidthChange() {
        pendingWidthChange?.cancel()
        pendingWidthChange = nil
    }

    private func cancelPendingShrink() {
        pendingShrink?.cancel()
        pendingShrink = nil
        pendingShrinkTargetHeight = nil
        pendingShrinkDeadline = nil
    }

    /// Whether a refresh that still wants to shrink to `newTarget` must
    /// restart the settle wait: yes with nothing pending or a different
    /// target, no for the same target (within the resize dead zone).
    nonisolated static func shouldRestartShrinkTimer(
        pendingTarget: CGFloat?,
        newTarget: CGFloat
    ) -> Bool {
        guard let pendingTarget else { return true }
        return abs(pendingTarget - newTarget) > IslandPanelSizing.deadZone
    }

    /// What a due shrink should do given what the view still draws.
    enum ShrinkDecision: Equatable {
        /// Set the window to this height.
        case apply(height: CGFloat)
        /// A close fade still draws the opened layout: try again after it
        /// has unmounted.
        case deferUntilCloseFadeEnds
        /// Nothing to shrink.
        case skip
    }

    /// Decides a due shrink. The window never goes below the published
    /// layout while the island is open or fading out, because the view is
    /// still drawing that layout. While it only fades out (not open, a
    /// close snapshot is held) nothing is applied at all.
    nonisolated static func shrinkDecision(
        currentHeight: CGFloat,
        resolvedTargetHeight: CGFloat,
        publishedWindowHeight: CGFloat,
        isOpened: Bool,
        hasClosingPresentation: Bool
    ) -> ShrinkDecision {
        guard IslandPanelSizing.resizeStep(current: currentHeight, target: resolvedTargetHeight) == .shrink else {
            return .skip
        }

        if !isOpened && hasClosingPresentation {
            return .deferUntilCloseFadeEnds
        }

        let drawsPublishedLayout = isOpened || hasClosingPresentation
        let targetHeight = drawsPublishedLayout
            ? max(resolvedTargetHeight, publishedWindowHeight)
            : resolvedTargetHeight
        guard IslandPanelSizing.resizeStep(current: currentHeight, target: targetHeight) == .shrink else {
            return .skip
        }

        return .apply(height: targetHeight)
    }

    /// `frame` with a different height, still hanging from the same top edge.
    nonisolated static func frame(_ frame: NSRect, withHeight height: CGFloat) -> NSRect {
        NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
    }

    /// Re-resolves the latest target and shrinks only if it is still a
    /// shrink and the view is done with the taller layout. If the content
    /// grew back meanwhile, the refresh that noticed already cancelled this
    /// work item or applied the grow.
    func performPendingShrink() {
        cancelPendingShrink()
        guard let panel,
              let model,
              let placement = resolvePlacement(model: model, preferredScreenID: lastPreferredScreenID),
              IslandPanelSizing.isHeightOnlyChange(from: panel.frame, to: placement.frame)
        else {
            return
        }

        let decision = Self.shrinkDecision(
            currentHeight: panel.frame.height,
            resolvedTargetHeight: placement.frame.height,
            publishedWindowHeight: model.islandOpenedLayout.windowHeight,
            isOpened: model.notchStatus == .opened,
            hasClosingPresentation: model.overlay.closingPresentation != nil
        )

        switch decision {
        case .skip:
            return
        case .deferUntilCloseFadeEnds:
            // No refresh restarts the timer after a close, so ask again for
            // when the opened surface has unmounted.
            OverlayTrace.log("shrink deferred, a close fade still draws the opened layout")
            armShrink(after: Motion.openedSurfaceUnmountDelay, targetHeight: placement.frame.height)
        case .apply(let height):
            setFrame(Self.frame(placement.frame, withHeight: height), change: .shrink, on: panel)
            onDeferredFrameChange?()
        }
    }

    /// Applies a waiting shrink at once, down to the published layout, and
    /// drops the timer. For a click that landed in the leftover strip.
    private func applyPendingShrinkNow(on panel: NSPanel) {
        cancelPendingShrink()
        guard let model else { return }

        let height = model.islandOpenedLayout.windowHeight
        guard IslandPanelSizing.resizeStep(current: panel.frame.height, target: height) == .shrink else {
            return
        }

        setFrame(Self.frame(panel.frame, withHeight: height), change: .shrink, on: panel)
        onDeferredFrameChange?()
    }

    private func setFrame(_ frame: NSRect, change: FrameChange, on panel: NSPanel) {
        let fromHeight = panel.frame.height
        let signpost = OverlayTrace.signposter.beginInterval("SetFrame")
        defer { OverlayTrace.signposter.endInterval("SetFrame", signpost) }

        // The frame is always set instantly, never through AppKit animation.
        // The shape animates inside the window through SwiftUI, so mixing in
        // NSAnimationContext would give two systems with different timing.
        panel.setFrame(frame, display: true)
        frameChangeCount += 1
        OverlayTrace.log("frame \(change.rawValue) from \(fromHeight) to \(frame.height)")
    }

    private func presentPanel(_ panel: NSPanel, activates: Bool) {
        if activates {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func computeNotchRect(screen: NSScreen?) {
        guard let screen else {
            notchRect = .zero
            return
        }

        let notchSize = screen.notchSize
        let screenFrame = screen.frame
        let notchX = screenFrame.midX - notchSize.width / 2
        let notchY = screenFrame.maxY - notchSize.height
        notchRect = NSRect(x: notchX, y: notchY, width: notchSize.width, height: notchSize.height)
    }

    /// Picks the screen to anchor the overlay to.
    ///
    /// Priority: persisted manual preference (matched via the stable
    /// `OverlayDisplayResolver.screenID` so a hotplug-reassigned
    /// `CGDirectDisplayID` can't silently re-target the wrong monitor) →
    /// first notched screen → `NSScreen.main` → first available screen.
    /// Returns `nil` only when no displays are connected.
    private func resolveTargetScreen(preferredScreenID: String? = nil) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        if let preferredScreenID,
           let screen = screens.first(where: { OverlayDisplayResolver.screenID(for: $0) == preferredScreenID }) {
            return screen
        }

        if let notchScreen = screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notchScreen
        }

        return NSScreen.main ?? screens[0]
    }

    // MARK: - Mouse event monitoring

    /// Registers the mouse monitors that drive hover-open, auto-collapse,
    /// and click-outside dismissal. Skipped during deterministic harness
    /// runs; a no-op while monitors are already active.
    private func startEventMonitoring() {
        if model?.disablesOverlayEventMonitoringDuringHarness == true {
            return
        }

        guard !eventMonitors.isActive else { return }

        eventMonitors.start { [weak self] location in
            self?.handleMouseMoved(location)
        } mouseDownHandler: { [weak self] location, isLocalEvent in
            self?.handleMouseDown(location, isLocalEvent: isLocalEvent)
        } mouseDragHandler: { [weak self] location in
            self?.handleMouseDragged(location)
        } mouseUpHandler: { [weak self] in
            self?.handleMouseUp()
        } scrollHandler: { [weak self] sample, screenLocation, windowLocation, windowNumber, isLocalEvent in
            self?.handleScroll(
                sample,
                screenLocation: screenLocation,
                windowLocation: windowLocation,
                windowNumber: windowNumber,
                isLocalEvent: isLocalEvent
            ) ?? false
        }
    }

    func handleMouseMoved(_ screenLocation: NSPoint) {
        guard let model else { return }

        // The pointer only moves freely with no button down. A file drag
        // whose mouse-up was never seen ends here.
        if fileDrag.hasReachedIsland {
            handleMouseUp()
        }

        let inClosedSurfaceArea = isPointInClosedSurfaceArea(screenLocation)

        if model.notchStatus == .closed && inClosedSurfaceArea {
            if IslandPointerRules.hoverOpens(
                trigger: model.islandOpenTrigger,
                isSuppressed: isHoverSuppressedUntilExit
            ) {
                scheduleHoverOpen()
            }
        } else if model.notchStatus == .closed && !inClosedSurfaceArea {
            isHoverSuppressedUntilExit = false
            cancelHoverOpen()
        }

        let shouldTrackNotificationPointer = model.notchStatus == .opened
            && model.notchOpenReason == .notification
            && model.showsNotificationCard

        if shouldTrackNotificationPointer || model.shouldAutoCollapseOnMouseLeave {
            if isPointInExpandedArea(screenLocation) {
                model.notePointerInsideIslandSurface()
            } else {
                model.handlePointerExitedIslandSurface()
            }
        }
    }

    /// - Parameter isLocalEvent: Whether the click was delivered to this app
    ///   (local monitor) or to another app (global monitor). Global monitors
    ///   only observe — the clicked app already received the event — so the
    ///   synthetic repost must be skipped there or it lands as a duplicate
    ///   click (double-click word selection, double activation).
    func handleMouseDown(_ screenLocation: NSPoint, isLocalEvent: Bool) {
        guard let model else { return }

        let isOpened = model.notchStatus == .opened
        let inExpandedArea = isPointInExpandedArea(screenLocation)

        // A press on the island closes any share picker the tray put up,
        // whether or not the picker said it closed.
        if isOpened && inExpandedArea {
            model.nook.tray.sharePickerDidClose()
        }

        // A new press means the last one is over, even if its mouse-up was
        // never seen.
        if fileDrag.hasReachedIsland {
            handleMouseUp()
        }

        // Every press starts a fresh look at the drag pasteboard. A press
        // on the open island is a tray file going out or a widget moving,
        // never a file coming in.
        fileDrag.mouseDown(
            changeCount: dragPasteboardChangeCount(),
            insideIsland: isOpened && inExpandedArea
        )

        let context = IslandClickContext(
            status: model.notchStatus,
            reason: model.notchOpenReason,
            isInClosedSurface: isPointInClosedSurfaceArea(screenLocation),
            isInExpandedArea: inExpandedArea,
            isOnNotch: isOpened && isPointOnNotch(screenLocation, model: model),
            // Keep the island open while a permission/question is pending
            // when the user opted into “keep open until decision” (#547).
            blocksDismiss: isOpened && model.shouldBlockDismissWhileAwaitingDecision,
            hasOpenPicker: isOpened && model.nook.tray.isSharePickerOpen,
            holdsOpenForTour: isOpened && model.tourHoldsIslandOpen
        )

        switch IslandPointerRules.clickAction(context) {
        case .open:
            cancelHoverOpenImmediately()
            model.notchOpen(reason: .click)
        case .holdForDecision:
            passThroughClickInSettleStrip(at: screenLocation, isLocalEvent: isLocalEvent)
        case .dismiss:
            model.notchClose()
            // Repost only when our panel actually swallowed the original
            // click: the event entered this app and landed inside the
            // panel frame, which means nothing under the cursor received it. When
            // another app got the click (notification opened while the
            // user works elsewhere), reposting injects a second click on
            // top of the real one and the user's next click “jumps”.
            if isLocalEvent, let panel, NSPointInRect(screenLocation, panel.frame) {
                repostMouseDown(at: screenLocation)
            }
        case .pin:
            // Observe only: the click still reaches the control under it.
            model.pinHoverOpenedIsland()
        case .closeFromNotch:
            // The pointer is still on the notch. Without this, hover mode
            // would open the island again under it.
            isHoverSuppressedUntilExit = true
            model.notchClose()
        case .none:
            break
        }
    }

    // MARK: - Swipes

    /// Turns the scroll events over the island into a swipe (D46). Runs for
    /// every scroll event on the Mac. The pointer test comes first and
    /// everything else waits for it.
    /// - Returns: Whether the local monitor should swallow the event: the
    ///   island acted on this gesture and the rest of it is not for the view
    ///   under the pointer. A global event is only observed.
    func handleScroll(
        _ sample: IslandScrollSample,
        screenLocation: NSPoint,
        windowLocation: NSPoint,
        windowNumber: Int,
        isLocalEvent: Bool
    ) -> Bool {
        guard let model else { return false }

        let inClosedSurface = isPointInClosedSurfaceArea(screenLocation)
        let inExpandedArea = isPointInExpandedArea(screenLocation)
        guard inClosedSurface || inExpandedArea else {
            swipe.reset()
            return false
        }

        let direction = swipe.feed(sample)
        let swallows = isLocalEvent && swipe.isConsumed
        guard let direction else { return swallows }

        let isOpened = model.notchStatus == .opened
        let context = IslandSwipeContext(
            status: model.notchStatus,
            direction: direction,
            isInClosedSurface: inClosedSurface,
            isInExpandedArea: inExpandedArea,
            isOverScrollableContent: isLocalEvent && isOpened
                && isOverScrollableContent(windowLocation: windowLocation, windowNumber: windowNumber),
            blocksDismiss: isOpened && model.shouldBlockDismissWhileAwaitingDecision,
            hasOpenPicker: isOpened && model.nook.tray.isSharePickerOpen,
            holdsOpenForTour: isOpened && model.tourHoldsIslandOpen
        )

        switch IslandPointerRules.swipeAction(context) {
        case .close:
            // The pointer is still on the island. Without this, hover mode
            // would open it again under the pointer.
            isHoverSuppressedUntilExit = true
            model.notchClose()
        case .toggleClosedContent:
            model.toggleClosedContentHidden()
        case .none:
            return swallows
        }
        swipe.markConsumed()
        return isLocalEvent
    }

    /// Whether the view under a local scroll event sits in a scroll view
    /// with more to scroll. Nothing found answers false.
    private func isOverScrollableContent(windowLocation: NSPoint, windowNumber: Int) -> Bool {
        guard let panel, panel.windowNumber == windowNumber,
              let content = panel.contentView, let frameView = content.superview else { return false }
        let hit = content.hitTest(frameView.convert(windowLocation, from: nil))
        return IslandScrollContent.isScrollable(from: hit, windowPoint: windowLocation)
    }

    // MARK: - Files dragged to the island

    /// How long the closed panel keeps taking mouse events after the button
    /// comes up. A drop on the pill is delivered around the mouse-up, and
    /// the panel must still be taking events when it arrives.
    private static let fileDropSettleDelay: TimeInterval = 0.3

    /// Mouse-moved events stop while a button is held, which means a drag
    /// never triggers hover-open. This is what opens the island for a
    /// dragged file instead (`IslandFileDragTracker`).
    func handleMouseDragged(_ screenLocation: NSPoint) {
        guard let model else { return }

        let step = fileDrag.dragged(
            isPointerOverIsland: isPointInFileDragZone(screenLocation),
            changeCount: dragPasteboardChangeCount,
            types: dragPasteboardTypes
        )
        applyFileDragStep(step)

        // A placement refresh in the middle of the drag puts the closed
        // panel back to passing events through. Take them again while the
        // files are still over the pill.
        if isClosedPanelDragReceptive, model.notchStatus != .opened,
           let panel, panel.ignoresMouseEvents {
            panel.ignoresMouseEvents = false
        }
    }

    func handleMouseUp() {
        applyFileDragStep(fileDrag.mouseUp())
    }

    private func applyFileDragStep(_ step: IslandFileDragTracker.Step) {
        guard let model else { return }

        switch step {
        case .entered:
            model.nook.tray.isFileDragOverIsland = true

            switch IslandPointerRules.fileDragArrival(
                status: model.notchStatus,
                reason: model.notchOpenReason,
                showsNookPage: model.showsNookPage,
                trayIsOnPage: model.nookVisibleWidgets.contains(.tray)
            ) {
            case .openOnNook:
                // Opened like a hover: once the drag is over, the island
                // closes when the pointer leaves it.
                cancelHoverOpenImmediately()
                model.notchOpen(reason: .hover, page: .nook)
            case .turnToNook:
                withMotion(Motion.pageSwitch) { model.showNookPage() }
            case .acceptOnClosedPill:
                setClosedPanelDragReceptive(true)
            case .none:
                break
            }
        case .left:
            model.nook.tray.isFileDragOverIsland = false
            setClosedPanelDragReceptive(false)
        case .ended:
            model.nook.tray.isFileDragOverIsland = false
            scheduleDragReceptiveRestore()
        case .none:
            break
        }
    }

    /// A closed panel passes every mouse event through, and macOS never
    /// offers a drop to a window that does. While files hover over the
    /// closed pill the panel takes events, and it goes back to passing them
    /// through as soon as the drag moves off or ends. No click can land in
    /// between: the button is down for the whole drag.
    private func setClosedPanelDragReceptive(_ receptive: Bool) {
        pendingDragReceptiveRestore?.cancel()
        pendingDragReceptiveRestore = nil

        guard isClosedPanelDragReceptive != receptive else { return }
        isClosedPanelDragReceptive = receptive

        // An open island already takes events, and closing it restores the
        // pass-through by itself.
        guard let panel, model?.notchStatus != .opened else { return }
        panel.ignoresMouseEvents = !receptive
    }

    private func scheduleDragReceptiveRestore() {
        guard isClosedPanelDragReceptive else { return }

        let item = DispatchWorkItem { [weak self] in
            self?.setClosedPanelDragReceptive(false)
        }
        pendingDragReceptiveRestore?.cancel()
        pendingDragReceptiveRestore = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fileDropSettleDelay, execute: item)
    }

    /// Where a dragged file counts as over the island: the visible shape
    /// while it is open, the closed surface with some room around it
    /// otherwise.
    func isPointInFileDragZone(_ screenPoint: NSPoint) -> Bool {
        guard let model else { return false }

        if model.notchStatus == .opened {
            return isPointInExpandedArea(screenPoint)
        }

        let closedSurface = closedSurfaceRect(for: model) ?? notchRect
        return Self.rectContainsIncludingEdges(
            IslandPointerRules.fileDragZone(closedSurface: closedSurface),
            point: screenPoint
        )
    }

    private func isPointOnNotch(_ screenPoint: NSPoint, model: AppModel) -> Bool {
        Self.rectContainsIncludingEdges(
            IslandPointerRules.notchToggleRect(
                notchRect: notchRect,
                headerHeight: model.islandOpenedLayout.headerHeight
            ),
            point: screenPoint
        )
    }

    /// The island stays open for a pending decision, but a click in the
    /// leftover strip (inside the window, below the visible shape) must not
    /// vanish: the panel's hit test refuses it, so the app below would never
    /// see it. Give the strip back at once by shrinking to the published
    /// layout, then repost the click if it now falls outside the panel.
    /// Never repost while the point is still inside the panel: the posted
    /// event would land on the panel again and loop.
    private func passThroughClickInSettleStrip(at screenLocation: NSPoint, isLocalEvent: Bool) {
        // A click another app received needs nothing from us.
        guard isLocalEvent, let panel, NSPointInRect(screenLocation, panel.frame) else {
            return
        }

        applyPendingShrinkNow(on: panel)

        guard !NSPointInRect(screenLocation, panel.frame) else { return }
        repostMouseDown(at: screenLocation)
    }

    /// Grace period before a hover-open timer is cancelled.  Prevents
    /// mouse jitter at the notch edge from resetting the delay.
    private static let hoverCancelGracePeriod: TimeInterval = 0.1

    private func scheduleHoverOpen() {
        // Mouse re-entered during grace period — just revoke the cancel.
        hoverCancelGrace?.cancel()
        hoverCancelGrace = nil

        guard model != nil else { return }

        guard hoverTimer == nil else { return }

        let item = DispatchWorkItem { [weak self] in
            guard let self, let model = self.model else { return }
            self.performHoverOpen(model)
            self.hoverTimer = nil
        }

        hoverTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + AppModel.hoverOpenDelay, execute: item)
    }

    private func performHoverOpen(_ model: AppModel) {
        guard model.notchStatus == .closed else { return }

        if model.hapticFeedbackEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(
                NSHapticFeedbackManager.FeedbackPattern.alignment,
                performanceTime: .now
            )
        }

        model.notchOpen(reason: .hover)
    }

    private func cancelHoverOpen() {
        guard hoverTimer != nil else { return }

        // Don't cancel immediately — allow a short grace period so that
        // mouse jitter at the notch edge doesn't restart the timer.
        guard hoverCancelGrace == nil else { return }

        let grace = DispatchWorkItem { [weak self] in
            self?.hoverTimer?.cancel()
            self?.hoverTimer = nil
            self?.hoverCancelGrace = nil
        }

        hoverCancelGrace = grace
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.hoverCancelGracePeriod,
            execute: grace
        )
    }

    /// Cancel without grace period — used for click-to-open where the
    /// hover timer must not fire after the click already opened the panel.
    private func cancelHoverOpenImmediately() {
        hoverCancelGrace?.cancel()
        hoverCancelGrace = nil
        hoverTimer?.cancel()
        hoverTimer = nil
    }

    // MARK: - Hit testing geometry

    func isPointInClosedSurfaceArea(_ screenPoint: NSPoint) -> Bool {
        guard let model else { return false }

        if let closedSurfaceRect = closedSurfaceRect(for: model) {
            return Self.rectContainsIncludingEdges(closedSurfaceRect, point: screenPoint)
        }

        let expandedNotch = notchRect.insetBy(dx: -20, dy: -10)
        return Self.rectContainsIncludingEdges(expandedNotch, point: screenPoint)
    }

    func isPointInExpandedArea(_ screenPoint: NSPoint) -> Bool {
        guard let model, model.notchStatus == .opened else {
            return isPointInClosedSurfaceArea(screenPoint)
        }

        guard let panel else {
            return false
        }

        // The window can be taller than the island (a shrink waits for the
        // shape), so only the visible shape counts as inside.
        guard let contentRect = contentRect(for: model, in: panel.frame) else {
            return false
        }

        return Self.rectContainsIncludingEdges(contentRect, point: screenPoint)
    }

    func openedPanelWidth(for screen: NSScreen?) -> CGFloat {
        openedMetrics(for: screen).panelWidth
    }

    /// The opened island's sizes on `screen`, from the look saved for that
    /// kind of display (D35). The window, the click area and the text
    /// measures below all come through here.
    func openedMetrics(for screen: NSScreen?) -> IslandOpenedMetrics {
        let profile = Self.displayProfile(for: screen)
        return IslandOpenedMetrics.resolve(
            look: openedLook(for: profile),
            profile: profile,
            screenWidth: screen?.visibleFrame.width
        )
    }

    private func openedLook(for profile: IslandAppearanceDisplayProfile) -> IslandOpenedLook {
        model?.nook.displayPreferences(for: profile).openedLook ?? .standard
    }

    /// A screen with a notch takes the notch profile, every other screen
    /// and no screen at all the top bar's.
    private static func displayProfile(for screen: NSScreen?) -> IslandAppearanceDisplayProfile {
        (screen?.safeAreaInsets.top ?? 0) > 0 ? .notch : .topBar
    }

    /// Width the text of a completion card is measured at on the island's
    /// screen: the standard measure plus what the opened look adds.
    private var cardTextMeasureWidth: CGFloat {
        // The island's own screen, which with two displays is not always
        // the first one with a notch.
        let screen = resolveTargetScreen(preferredScreenID: lastPreferredScreenID)
        let profile = Self.displayProfile(for: screen)
        let gain = IslandOpenedMetrics.pageWidthGain(
            look: openedLook(for: profile),
            profile: profile,
            screenWidth: screen?.visibleFrame.width
        )
        return Self.preferredNotificationPanelWidth - 96 + gain
    }

    /// The part of `bounds` (the window, bottom-up) that takes hits. While
    /// the island is open that is the visible shape: a top-anchored rect of
    /// `openedLayout.shapeHeight`, inset by the shadow on both sides. Closed,
    /// it is the whole window above the bottom shadow inset, as before.
    func contentRect(for model: AppModel, in bounds: NSRect) -> NSRect? {
        let insets = panelShadowInsets

        if model.notchStatus == .opened {
            return IslandPanelSizing.visibleShapeRect(
                in: bounds,
                shapeHeight: model.islandOpenedLayout.shapeHeight,
                horizontalInset: insets.horizontal
            )
        }

        return NSRect(
            x: bounds.minX + insets.horizontal,
            y: bounds.minY + insets.bottom,
            width: max(0, bounds.width - (insets.horizontal * 2)),
            height: max(0, bounds.height - insets.bottom)
        )
    }

    nonisolated static func closedSurfaceRect(
        notchRect: NSRect,
        closedWidth: CGFloat
    ) -> NSRect {
        let cx = notchRect.midX
        return NSRect(
            x: cx - closedWidth / 2,
            y: notchRect.minY,
            width: closedWidth,
            height: notchRect.height
        )
    }

    nonisolated static func rectContainsIncludingEdges(_ rect: NSRect, point: NSPoint) -> Bool {
        point.x >= rect.minX
            && point.x <= rect.maxX
            && point.y >= rect.minY
            && point.y <= rect.maxY
    }

    /// Hit-area width of the v6 closed pill.
    ///
    /// - On a MacBook (physical notch present) the pill is locked to
    ///   `44 + notchWidth + 44`, per the v6 design spec.
    /// - On an external display the width is content-driven; we return a
    ///   generous fixed hit-area so hover / click detection works without
    ///   the controller having to introspect live session state.
    nonisolated static func closedPanelWidth(
        notchWidth: CGFloat,
        isNotchedDisplay: Bool,
        notchStatus: NotchStatus
    ) -> CGFloat {
        let popBonus: CGFloat = notchStatus == .popping ? 18 : 0
        if isNotchedDisplay {
            return notchWidth + 88 + popBonus
        }
        return 360 + popBonus
    }

    private func closedSurfaceRect(for model: AppModel) -> NSRect? {
        guard let screen = resolveTargetScreen() else {
            return nil
        }

        let closedWidth = closedPanelWidth(for: model, on: screen)
        return Self.closedSurfaceRect(
            notchRect: notchRect,
            closedWidth: closedWidth
        )
    }

    /// The window frame for `layout` on `screen`: top-anchored and centered,
    /// as tall as the shape plus the transparent inset under it.
    private func panelFrame(for layout: IslandOpenedLayout, on screen: NSScreen) -> NSRect {
        IslandPanelSizing.windowFrame(
            panelWidth: openedPanelWidth(for: screen) + Self.openedContentWidthPadding,
            windowHeight: layout.windowHeight,
            screenFrame: screen.frame,
            horizontalInset: panelShadowInsets.horizontal
        )
    }

    /// The opened island's heights on `screen`. The header is the closed
    /// island height on both the window and the view side, so an external
    /// display has no extra black space above its content.
    private func openedLayout(for model: AppModel?, on screen: NSScreen) -> IslandOpenedLayout {
        let headerHeight = screen.islandClosedHeight

        guard let model else {
            return IslandOpenedLayout(
                headerHeight: headerHeight,
                contentHeight: Self.openedEmptyStateHeight,
                bottomPadding: Self.openedContentBottomPadding
            )
        }

        // Large widgets can make the Nook page taller than the screen.
        // Stop at the bottom of the visible area; the grid scrolls.
        let nookRoom: CGFloat? = model.showsNookPage
            ? IslandOpenedLayout.nookContentRoom(
                screenMaxY: screen.frame.maxY,
                visibleMinY: screen.visibleFrame.minY,
                headerHeight: headerHeight,
                bottomPadding: Self.openedContentBottomPadding,
                shadowBottomInset: panelShadowInsets.bottom
            )
            : nil

        // At least the empty-state height, so the island doesn't shrink
        // when sessions come and go while opened.
        return IslandOpenedLayout(
            headerHeight: headerHeight,
            contentHeight: IslandOpenedLayout.clampedContentHeight(
                requested: openedContentHeight(for: model),
                nookRoom: nookRoom
            ),
            bottomPadding: Self.openedContentBottomPadding
        )
    }

    /// Insets around the opened shape for its shadow and the status halo.
    private var panelShadowInsets: (horizontal: CGFloat, bottom: CGFloat) {
        (
            horizontal: IslandChromeMetrics.openedShadowHorizontalInset,
            bottom: IslandChromeMetrics.openedShadowBottomInset
        )
    }

    private func closedPanelWidth(for model: AppModel, on screen: NSScreen) -> CGFloat {
        let notchWidth = screen.notchSize.width
        let isNotched = screen.safeAreaInsets.top > 0
        return Self.closedPanelWidth(
            notchWidth: notchWidth,
            isNotchedDisplay: isNotched,
            notchStatus: model.notchStatus
        )
    }

    private func openedContentHeight(for model: AppModel) -> CGFloat {
        if model.showsNookPage {
            return NookPanelView.preferredHeight(
                for: model.nookWidgetPlacements,
                calendarStyle: model.nookDisplay.calendarStyle,
                isEditing: model.nook.isEditingLayout,
                extras: model.nookPageExtras
            ) + model.nookBarsHeight
        }
        return agentsContentHeight(for: model) + model.nookBarsHeight
    }

    private func agentsContentHeight(for model: AppModel) -> CGFloat {
        let now = Date.now
        let visibleSessions = openedVisibleSessions(
            sessions: model.islandListSessions
        )

        if visibleSessions.isEmpty {
            return Self.openedEmptyStateHeight
        }

        let actionableID = model.islandSurface.sessionID
        let isNotificationMode = model.notchOpenReason == .notification && actionableID != nil

        if isNotificationMode {
            // Use SwiftUI-measured height when available (accurate after first render).
            if model.measuredNotificationContentHeight > 0 {
                return model.measuredNotificationContentHeight + Self.notificationMeasuredContentPadding
            }
            // First render: estimate from the actionable session's content so the
            // initial window is close to the final size. This avoids a large blank
            // panel flash (the previous 500pt fallback) and reduces the chance of
            // a measurement→reposition cycle.
            if let actionableID,
               let session = model.state.session(id: actionableID) {
                let rowHeight = session.estimatedIslandRowHeight(at: now)
                let bodyHeight = actionableBodyHeight(for: session, model: model)
                return rowHeight + bodyHeight + Self.notificationEstimatedVerticalInsets
            }
            return 300
        }

        let rowHeights = visibleSessions.map { session -> CGFloat in
            if session.id == actionableID {
                return session.estimatedIslandRowHeight(at: now)
                    + actionableBodyHeight(for: session, model: model)
            }
            return session.estimatedIslandRowHeight(at: now)
                + model.agentTurnSummaryRowHeight(for: session, at: now)
        }

        let rowsHeight = rowHeights.reduce(CGFloat.zero, +)
        let spacingHeight = CGFloat(max(0, rowHeights.count - 1)) * Self.openedRowSpacing
        let listHeight = rowsHeight + spacingHeight
        // Cap to match AutoHeightScrollView's maxHeight in IslandPanelView.
        let cappedListHeight = min(listHeight, Self.maxSessionListHeight)
        return cappedListHeight + Self.openedContentVerticalInsets
    }

    /// Additional height for the actionable session's inline action area.
    private func actionableBodyHeight(for session: AgentSession, model: AppModel) -> CGFloat {
        switch session.phase {
        case .waitingForApproval:
            return 118 + model.agentApprovalExtraHeight(for: session)
        case .waitingForAnswer:
            return questionCardHeight(for: session.questionPrompt) - 44
        case .completed:
            return completionBodyHeight(for: session, model: model)
        case .running:
            return 0
        }
    }

    /// Height of the inline completion expansion area (not the old full-card height).
    private func completionBodyHeight(for session: AgentSession, model: AppModel) -> CGFloat {
        let headerHeight: CGFloat = 44

        let text = (session.completionAssistantMessageText ?? session.summary)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            return headerHeight
        }

        let availableWidth = cardTextMeasureWidth
        let font = NSFont.systemFont(ofSize: 13.5, weight: .medium)
        let textSize = (text as NSString).boundingRect(
            with: NSSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let markdownHeight = min(260, ceil(textSize.height) + 20)
        // Reply input: divider (1) + input bar padding+content (~52)
        let replyInputHeight: CGFloat = TerminalTextSender.canReply(to: session, enabled: model.completionReplyEnabled) ? 53 : 0
        let summaryHeight: CGFloat = model.agentTurnSummary(for: session) == nil ? 0 : AgentTurnSummaryMetrics.cardHeight
        return headerHeight + 1 + markdownHeight + replyInputHeight + summaryHeight
    }

    /// Estimates the question card height based on prompt content (question count,
    /// option count per question, and whether the prompt title is shown).
    private func questionCardHeight(for prompt: QuestionPrompt?) -> CGFloat {
        guard let prompt else {
            return Self.questionCardBaseHeight
        }

        let questions = prompt.questions.isEmpty && !prompt.options.isEmpty
            ? [
                QuestionPromptItem(
                    question: prompt.title,
                    header: "",
                    options: prompt.options.map { QuestionOption(label: $0) }
                ),
            ]
            : prompt.questions

        guard !questions.isEmpty else {
            return Self.questionCardBaseHeight
        }

        // Card chrome: outer padding + submit button.
        // When the prompt title is suppressed (single question whose title
        // matches the question text), reduce chrome because the body carries it.
        let titleSuppressed = questions.count == 1
            && prompt.title == questions.first?.question
        let chromeHeight: CGFloat = titleSuppressed ? 82 : 102
        var contentHeight: CGFloat = 0

        for question in questions {
            if questions.count > 1 {
                contentHeight += 16 // header
            }
            contentHeight += 20 // question text
            contentHeight += CGFloat(question.options.count) * 38 // option rows
        }

        // Inter-question spacing (only between questions, not after the last).
        contentHeight += CGFloat(max(0, questions.count - 1)) * 10

        let estimated = chromeHeight + contentHeight
        return min(Self.questionCardMaxHeight, max(Self.questionCardBaseHeight, estimated))
    }

    private func completionCardHeight(for model: AppModel) -> CGFloat {
        guard let session = model.activeIslandCardSession else {
            return Self.completionCardMinHeight
        }

        let text = (session.completionAssistantMessageText ?? session.summary)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Estimate text height using NSString measurement with the actual font.
        // Available text width ≈ notificationPanelWidth - card horizontal chrome
        // Card chrome: openedContent padding (18*2) + card padding (16*2) + text padding (14*2) = 96
        let availableWidth = cardTextMeasureWidth
        let font = NSFont.systemFont(ofSize: 13.5, weight: .medium)
        let textSize = (text as NSString).boundingRect(
            with: NSSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )

        let estimatedHeight = Self.completionCardChromeHeight + ceil(textSize.height)
        // Use a smaller minimum to avoid blank space when content is short
        let minHeight: CGFloat = Self.completionCardChromeHeight + 20
        return min(Self.completionCardMaxHeight, max(minHeight, estimatedHeight))
    }

    private func openedVisibleSessions(sessions: [AgentSession]) -> [AgentSession] {
        Array(sessions.prefix(Self.maxVisibleSessionRows))
    }

    // MARK: - Stray clicks on a closed island

    /// Minimum spacing between two repaired stray clicks. If the re-asserted
    /// pass-through did not take, the reposted click would land on us again;
    /// the throttle turns that into a dropped click instead of a loop.
    private static let strayClickRepairInterval: TimeInterval = 0.5

    /// Called by `NotchPanel` for every left mouse down it receives. While the
    /// island is closed the panel is `ignoresMouseEvents`, so it should never
    /// see a click outside the pill — yet occasionally it does (macOS keeps
    /// routing clicks to the panel until it is re-ordered, and the user has to
    /// expand and collapse the island to "unstick" the desktop underneath).
    /// Re-assert pass-through, re-order the window so the change takes, and
    /// forward the click to whatever is below. Returns `true` when the event
    /// must not reach SwiftUI.
    func panelReceivedMouseDown(_ event: NSEvent) -> Bool {
        guard let panel, let model, model.notchStatus != .opened else { return false }

        let screenPoint = NSEvent.mouseLocation
        // A click on the pill itself is legitimate: the click monitor opens the island.
        guard !isPointInClosedSurfaceArea(screenPoint) else { return false }

        let now = Date()
        let repost = now.timeIntervalSince(lastStrayClickRepair) > Self.strayClickRepairInterval
        overlayLog.error(
            "Closed island panel received a click at (\(screenPoint.x, privacy: .public), \(screenPoint.y, privacy: .public)); ignoresMouseEvents=\(panel.ignoresMouseEvents, privacy: .public) isKey=\(panel.isKeyWindow, privacy: .public) status=\(String(describing: model.notchStatus), privacy: .public) reason=\(String(describing: model.notchOpenReason), privacy: .public). Re-asserting pass-through\(repost ? " and reposting the click" : "", privacy: .public)."
        )

        panel.ignoresMouseEvents = false
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = false
        panel.orderFrontRegardless()

        if repost {
            lastStrayClickRepair = now
            repostMouseDown(at: screenPoint)
        }
        return true
    }

    // MARK: - Event reposting

    /// Re-injects a synthetic click after the panel swallowed the original
    /// one (event delivered to this app inside the panel frame). Callers must
    /// not invoke this for clicks another app already received — the window
    /// under the cursor would see two clicks and treat them as a double click.
    private func repostMouseDown(at screenPoint: NSPoint) {
        if let mouseDownReposter {
            mouseDownReposter(screenPoint)
            return
        }

        let flippedY = NSScreen.main.map { $0.frame.height - screenPoint.y } ?? screenPoint.y

        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: CGPoint(x: screenPoint.x, y: flippedY),
            mouseButton: .left
        ) else { return }

        event.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            guard let upEvent = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: CGPoint(x: screenPoint.x, y: flippedY),
                mouseButton: .left
            ) else { return }
            upEvent.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - NotchPanel

private final class NotchPanel: NSPanel {
    weak var notchController: OverlayPanelController?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// A hover- or notification-opened island is ordered front without
    /// becoming key. AppKit treats the first click on a non-key window as a
    /// "make key" click and drops it unless the hit view accepts first mouse.
    /// `NotchHostingView` does, but the session list lives in a SwiftUI
    /// `ScrollView`, whose backing `NSScrollView` subviews don't — so the
    /// first click on a session row was swallowed and only the second one
    /// reached `onTapGesture`. Become key before AppKit inspects the click so
    /// it is delivered on the first press, matching click-opened islands
    /// (presented with `makeKeyAndOrderFront`).
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            if notchController?.panelReceivedMouseDown(event) == true {
                return
            }
            if !isKeyWindow, !ignoresMouseEvents {
                makeKey()
            }
        }
        super.sendEvent(event)
    }
}

// MARK: - NotchHostingView

final class NotchHostingView<Content: View>: NSHostingView<Content> {
    weak var notchController: OverlayPanelController?

    override var isOpaque: Bool {
        false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        // Ensure the panel is key before SwiftUI processes the click.
        // With nonactivatingPanel, hover-opened panels aren't key, so
        // SwiftUI Button may consume the first click for key acquisition
        // instead of firing its action.
        window?.makeKey()
        super.mouseDown(with: event)
    }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        configureTransparency()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let controller = notchController,
              let model = controller.model else {
            return nil
        }

        guard let contentRect = controller.contentRect(for: model, in: bounds),
              contentRect.contains(point) else {
            return nil
        }

        return super.hitTest(point) ?? self
    }

    private func convertToScreen(_ viewPoint: NSPoint) -> NSPoint {
        guard let window else { return viewPoint }
        let windowPoint = convert(viewPoint, to: nil)
        return window.convertPoint(toScreen: windowPoint)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureTransparency()
    }

    private func configureTransparency() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func layout() {
        super.layout()
        // NSHostingView wraps content in internal NSScrollViews.
        // SwiftUI may recreate them when the view tree changes (e.g.
        // AutoHeightScrollView toggling between scroll/non-scroll mode),
        // so we must re-disable on every layout pass.
        // Guard: only modify properties when they differ to avoid
        // triggering additional layout passes that could loop.
        disableInternalScrollers(in: self)
    }

    private func disableInternalScrollers(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            if scrollView.hasVerticalScroller { scrollView.hasVerticalScroller = false }
            if scrollView.hasHorizontalScroller { scrollView.hasHorizontalScroller = false }
            if scrollView.scrollerStyle != .overlay { scrollView.scrollerStyle = .overlay }
            return
        }
        for child in view.subviews {
            disableInternalScrollers(in: child)
        }
    }
}

// MARK: - NotchEventMonitors

@MainActor
final class NotchEventMonitors {
    private var globalMoveMonitor: Any?
    private var localMoveMonitor: Any?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var globalDragMonitor: Any?
    private var localDragMonitor: Any?
    private var globalUpMonitor: Any?
    private var localUpMonitor: Any?
    private var globalScrollMonitor: Any?
    private var localScrollMonitor: Any?
    private var lastMoveTime: TimeInterval = 0

    var isActive: Bool { globalMoveMonitor != nil }

    /// Registers throttled mouse-move monitors plus click monitors for both
    /// event destinations. The click handler receives `isLocalEvent: true`
    /// from the local monitor (event delivered to this app) and `false` from
    /// the global monitor (event delivered to another app, observe-only).
    /// Drag and mouse-up monitors follow a press to its end, which is how a
    /// file dragged to the island is noticed. They are mouse monitors like
    /// the others and need no permission the app does not already use.
    func start(
        mouseMoveHandler: @MainActor @escaping @Sendable (NSPoint) -> Void,
        mouseDownHandler: @MainActor @escaping @Sendable (NSPoint, _ isLocalEvent: Bool) -> Void,
        mouseDragHandler: @MainActor @escaping @Sendable (NSPoint) -> Void,
        mouseUpHandler: @MainActor @escaping @Sendable () -> Void,
        scrollHandler: @MainActor @escaping @Sendable (
            _ sample: IslandScrollSample,
            _ screenLocation: NSPoint,
            _ windowLocation: NSPoint,
            _ windowNumber: Int,
            _ isLocalEvent: Bool
        ) -> Bool
    ) {
        let throttleInterval: TimeInterval = 0.05

        nonisolated(unsafe) var sharedLastMove: TimeInterval = 0

        globalMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { event in
            let now = ProcessInfo.processInfo.systemUptime
            guard now - sharedLastMove >= throttleInterval else { return }
            sharedLastMove = now
            let location = NSEvent.mouseLocation
            Task { @MainActor in mouseMoveHandler(location) }
        }

        localMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
            let now = ProcessInfo.processInfo.systemUptime
            guard now - sharedLastMove >= throttleInterval else { return event }
            sharedLastMove = now
            let location = NSEvent.mouseLocation
            Task { @MainActor in mouseMoveHandler(location) }
            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { event in
            let location = NSEvent.mouseLocation
            Task { @MainActor in mouseDownHandler(location, false) }
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            let location = NSEvent.mouseLocation
            Task { @MainActor in mouseDownHandler(location, true) }
            return event
        }

        nonisolated(unsafe) var sharedLastDrag: TimeInterval = 0

        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { _ in
            let now = ProcessInfo.processInfo.systemUptime
            guard now - sharedLastDrag >= throttleInterval else { return }
            sharedLastDrag = now
            let location = NSEvent.mouseLocation
            Task { @MainActor in mouseDragHandler(location) }
        }

        localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { event in
            let now = ProcessInfo.processInfo.systemUptime
            guard now - sharedLastDrag >= throttleInterval else { return event }
            sharedLastDrag = now
            let location = NSEvent.mouseLocation
            Task { @MainActor in mouseDragHandler(location) }
            return event
        }

        globalUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            Task { @MainActor in mouseUpHandler() }
        }

        localUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
            Task { @MainActor in mouseUpHandler() }
            return event
        }

        // Scroll events arrive for the whole Mac. A monitor only reads the
        // numbers and hands plain values to the handler, which tests the
        // pointer first. The local one runs on the main thread and may
        // swallow the rest of a swipe the island acted on.
        globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { event in
            let sample = Self.sample(from: event)
            let location = NSEvent.mouseLocation
            Task { @MainActor in _ = scrollHandler(sample, location, .zero, 0, false) }
        }

        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            let sample = Self.sample(from: event)
            let location = NSEvent.mouseLocation
            let windowLocation = event.locationInWindow
            let windowNumber = event.windowNumber
            let swallows = MainActor.assumeIsolated {
                scrollHandler(sample, location, windowLocation, windowNumber, true)
            }
            return swallows ? nil : event
        }
    }

    private nonisolated static func sample(from event: NSEvent) -> IslandScrollSample {
        IslandScrollSample.make(
            scrollingDeltaX: Double(event.scrollingDeltaX),
            scrollingDeltaY: Double(event.scrollingDeltaY),
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas,
            isDirectionInvertedFromDevice: event.isDirectionInvertedFromDevice,
            phase: event.phase,
            momentumPhase: event.momentumPhase,
            timestamp: event.timestamp
        )
    }

    func stop() {
        if let m = globalMoveMonitor { NSEvent.removeMonitor(m) }
        if let m = localMoveMonitor { NSEvent.removeMonitor(m) }
        if let m = globalClickMonitor { NSEvent.removeMonitor(m) }
        if let m = localClickMonitor { NSEvent.removeMonitor(m) }
        if let m = globalDragMonitor { NSEvent.removeMonitor(m) }
        if let m = localDragMonitor { NSEvent.removeMonitor(m) }
        if let m = globalUpMonitor { NSEvent.removeMonitor(m) }
        if let m = localUpMonitor { NSEvent.removeMonitor(m) }
        if let m = globalScrollMonitor { NSEvent.removeMonitor(m) }
        if let m = localScrollMonitor { NSEvent.removeMonitor(m) }
        globalMoveMonitor = nil
        localMoveMonitor = nil
        globalClickMonitor = nil
        localClickMonitor = nil
        globalDragMonitor = nil
        localDragMonitor = nil
        globalUpMonitor = nil
        localUpMonitor = nil
        globalScrollMonitor = nil
        localScrollMonitor = nil
    }
}

// MARK: - NSScreen notch size helper

extension NSScreen {
    /// Simulated notch width used on non-notch (external) displays.
    /// Sized close to a real MacBook notch (~200pt) so the closed island
    /// doesn't feel disproportionately wide when the black rectangle is
    /// fully visible (not hidden behind a physical notch).
    static let externalDisplayNotchWidth: CGFloat = 190
    static let externalDisplayNotchHeight: CGFloat = 38

    var notchSize: CGSize {
        guard safeAreaInsets.top > 0 else {
            return CGSize(
                width: Self.externalDisplayNotchWidth,
                height: Self.externalDisplayNotchHeight
            )
        }

        let notchHeight = safeAreaInsets.top
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0
        let notchWidth = frame.width - leftPadding - rightPadding + 4

        return CGSize(width: notchWidth, height: notchHeight)
    }

    var topStatusBarHeight: CGFloat {
        let reservedTopInset = max(0, frame.maxY - visibleFrame.maxY)
        if reservedTopInset > 0 {
            return reservedTopInset
        }

        if safeAreaInsets.top > 0 {
            return safeAreaInsets.top
        }

        return 24
    }

    var islandClosedHeight: CGFloat {
        NSScreen.computeIslandClosedHeight(
            safeAreaInsetsTop: safeAreaInsets.top,
            topStatusBarHeight: topStatusBarHeight
        )
    }

    /// Pure helper so the height selection logic can be unit-tested without real screen hardware.
    ///
    /// On notch screens, use `safeAreaInsetsTop` directly — the island must match the
    /// physical notch height exactly so it sits flush with the notch bottom edge.
    /// Previously this used `min(safeAreaInsetsTop, topStatusBarHeight)`, but when the
    /// menu bar reserved area is smaller than the notch (e.g. auto-hide menu bar, or
    /// certain display configurations), the island ended up shorter than the physical
    /// notch, leaving a visible gap.
    /// On non-notch screens (`safeAreaInsetsTop == 0`), use `topStatusBarHeight` directly.
    static func computeIslandClosedHeight(
        safeAreaInsetsTop: CGFloat,
        topStatusBarHeight: CGFloat
    ) -> CGFloat {
        if safeAreaInsetsTop > 0 {
            return safeAreaInsetsTop
        }
        return topStatusBarHeight
    }
}
