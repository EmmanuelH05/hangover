import AppKit
import Foundation
import Observation
import OpenIslandCore
import SwiftUI

@MainActor
@Observable
final class OverlayUICoordinator {

    private static let notificationSurfaceAutoCollapseDelay: TimeInterval = 10

    // Each of these three can change which request is the card on screen.
    // The agent shortcuts time a card from that moment.
    var notchStatus: NotchStatus = .closed {
        didSet {
            guard notchStatus != oldValue else { return }
            appModel?.refreshAgentHotkeyCard()
            appModel?.nook.widgetsCameIntoView()
        }
    }
    var notchOpenReason: NotchOpenReason? {
        didSet {
            guard notchOpenReason != oldValue else { return }
            appModel?.refreshAgentHotkeyCard()
            // A click that pins a boot-opened island puts its tiles in the
            // user's view without any of them appearing anew.
            appModel?.nook.widgetsCameIntoView()
        }
    }
    var islandSurface: IslandSurface = .sessionList() {
        didSet { if islandSurface != oldValue { appModel?.refreshAgentHotkeyCard() } }
    }
    var isOverlayVisible: Bool { notchStatus != .closed }

    /// True while the welcome tour holds the island open on the Nook page
    /// (D44). Set only by `setTourHoldsIslandOpen`.
    private(set) var tourHoldsIslandOpen = false

    /// Heights the opened island animates to. The panel controller resolves
    /// them and `publishOpenedLayout` writes it, only when it changed (D16).
    var openedLayout: IslandOpenedLayout = .placeholder

    /// What the opened island showed when `notchClose()` began, kept until
    /// the fade finishes or the island opens again (D16).
    var closingPresentation: IslandOpenedPresentation?

    var overlayDisplayOptions: [OverlayDisplayOption] = []
    var overlayPlacementDiagnostics: OverlayPlacementDiagnostics?

    var overlayDisplaySelectionID = OverlayDisplayOption.automaticID {
        didSet {
            guard overlayDisplaySelectionID != oldValue else {
                return
            }
            persistOverlayDisplayPreference()
            refreshOverlayPlacementNow()
        }
    }

    @ObservationIgnored
    weak var appModel: AppModel?

    @ObservationIgnored
    var onStatusMessage: ((String) -> Void)?

    @ObservationIgnored
    var activeIslandCardSessionAccessor: (() -> AgentSession?)?

    @ObservationIgnored
    var isSoundMutedAccessor: (() -> Bool)?

    @ObservationIgnored
    var ignoresPointerExitAccessor: (() -> Bool)?

    /// Overrides the global cursor query so pointer-sensitive behavior stays
    /// deterministic when the host machine's real cursor happens to hover the
    /// overlay area (e.g. during unit tests).
    @ObservationIgnored
    var pointerLocationProvider: (() -> NSPoint)?

    @ObservationIgnored
    var harnessRuntimeMonitor: HarnessRuntimeMonitor?

    @ObservationIgnored
    let overlayPanelController = OverlayPanelController()

    @ObservationIgnored
    private var screenParametersObserver: NSObjectProtocol?

    @ObservationIgnored
    private var overlayDisplaySelectionTitle: String?

    @ObservationIgnored
    private var overlayTransitionGeneration: UInt64 = 0

    @ObservationIgnored
    private var notificationAutoCollapseTask: Task<Void, Never>?

    /// True from the first `scheduleLayoutRefresh()` of a run-loop turn until
    /// the one refresh it queued has run.
    @ObservationIgnored
    private var isLayoutRefreshPending = false

    /// How many layout refreshes ran. Tests read it to check coalescing.
    @ObservationIgnored
    private(set) var performedLayoutRefreshCount = 0

    /// The screen the last refresh resolved, so a layout change on the same
    /// screen can animate and one that moved screens cannot.
    @ObservationIgnored
    private var lastLayoutScreenID: String?

    var hasPendingNotificationAutoCollapse: Bool {
        notificationAutoCollapseTask != nil
    }

    @ObservationIgnored
    private var autoCollapseSurfaceHasBeenEntered = false

    /// True when the hold opened the island, or held it against a close.
    /// Releasing the hold closes an island it owns and no other.
    @ObservationIgnored
    private var tourOwnsOpenIsland = false

    @ObservationIgnored
    private var isPointerInsideIslandSurface = false

    /// Kept for API compatibility; always false. The close is a SwiftUI
    /// fade over a snapshot (`closingPresentation`), so nothing is pending.
    var isCloseTransitionPending: Bool { false }

    private var activeIslandCardSession: AgentSession? {
        activeIslandCardSessionAccessor?()
    }

    private var isSoundMuted: Bool {
        isSoundMutedAccessor?() ?? false
    }

    private var ignoresPointerExitDuringHarness: Bool {
        ignoresPointerExitAccessor?() ?? false
    }

    private var currentPointerLocation: NSPoint {
        pointerLocationProvider?() ?? NSEvent.mouseLocation
    }

    private var preferredOverlayScreenID: String? {
        overlayDisplaySelectionID == OverlayDisplayOption.automaticID
            ? nil
            : overlayDisplaySelectionID
    }

    // MARK: - Initialization

    /// Where the chosen display is saved. The app model hands in its own store.
    @ObservationIgnored var defaults: UserDefaults = .standard

    init() {
        overlayPanelController.onDeferredFrameChange = { [weak self] in
            self?.refreshPlacementDiagnostics()
        }
    }

    func restoreDisplayPreference() {
        let storedSelectionID = defaults.string(
            forKey: OverlayDisplayPreferencePolicy.preferenceDefaultsKey
        )
        let restoredSelectionID = OverlayDisplayPreferencePolicy.restoredSelectionID(
            from: storedSelectionID
        )

        if storedSelectionID != nil,
           restoredSelectionID == OverlayDisplayOption.automaticID {
            defaults.removeObject(forKey: OverlayDisplayPreferencePolicy.preferenceDefaultsKey)
            defaults.removeObject(forKey: OverlayDisplayPreferencePolicy.preferenceTitleDefaultsKey)
        }

        overlayDisplaySelectionTitle = defaults.string(
            forKey: OverlayDisplayPreferencePolicy.preferenceTitleDefaultsKey
        )
        overlayDisplaySelectionID = restoredSelectionID
    }

    /// Re-syncs the cached display options and the target panel placement
    /// whenever macOS reports a screen configuration change (hotplug,
    /// arrangement change, sleep/wake). Without this, the picker list keeps
    /// stale entries after disconnect, and a saved preference whose
    /// `CGDirectDisplayID` gets reused for a different physical display can
    /// silently route the island to the wrong screen.
    func startObservingDisplayChanges() {
        guard screenParametersObserver == nil else { return }
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshOverlayDisplayConfiguration()
            }
        }
    }

    isolated deinit {
        if let observer = screenParametersObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Overlay transitions

    func toggleOverlay() {
        if notchStatus == .closed {
            notchOpen(reason: .click)
        } else {
            notchClose()
        }
    }

    func notchOpen(reason: NotchOpenReason, surface: IslandSurface = .sessionList()) {
        // A card has news to bring (D46). Opening by hover or click leaves
        // the swipe's hidden state alone.
        if IslandPointerRules.openingBringsBackHiddenContent(reason: reason) {
            appModel?.nook.closedContentHiddenBySwipe = false
        }
        transitionOverlay(
            to: .opened,
            reason: reason,
            surface: surface,
            interactive: true,
            beforeTransition: nil,
            afterStateChange: { [weak self] in
                guard let self else { return }
                self.autoCollapseSurfaceHasBeenEntered = false
                self.isPointerInsideIslandSurface = false
                self.updateNotificationAutoCollapse()
            },
            onPlacementResolved: { [weak self] in
                guard let self, let overlayPlacementDiagnostics else { return }
                self.onStatusMessage?("Overlay showing on \(overlayPlacementDiagnostics.targetScreenName) as \(overlayPlacementDiagnostics.modeDescription.lowercased()).")
            }
        )
    }

    func notchClose() {
        // The welcome tour holds the island open (D44). Whoever asks for a
        // close, a card that is gone, the 10 second timer, the boot
        // animation or a hotkey, gets the Nook page back instead, and the
        // hold closes it when it is released.
        if tourHoldsIslandOpen {
            returnToNookForTour()
            return
        }
        closeIsland()
    }

    private func closeIsland() {
        tourOwnsOpenIsland = false
        // Snapshot what is on screen before the surface and reason reset, so
        // the view keeps drawing it while the island fades out instead of
        // swapping a notification card for the list. A second close during
        // the fade keeps the first snapshot.
        if notchStatus != .closed || closingPresentation == nil {
            closingPresentation = appModel?.liveOpenedPresentation()
        }

        transitionOverlay(
            to: .closed,
            reason: nil,
            surface: .sessionList(),
            interactive: false,
            beforeTransition: { [weak self] in
                self?.notificationAutoCollapseTask?.cancel()
                self?.notificationAutoCollapseTask = nil
            },
            afterStateChange: { [weak self] in
                self?.autoCollapseSurfaceHasBeenEntered = false
                self?.isPointerInsideIslandSurface = false
                self?.appModel?.measuredNotificationContentHeight = 0
                self?.appModel?.nook.isEditingLayout = false
                // Closing the island turns the mirror, the camera and the
                // ring light off. The next open never starts the camera.
                self?.appModel?.nook.isMirrorOn = false
                // A half-typed event is kept for the next "+".
                self?.appModel?.nook.closeEventEditor(keepingDraft: true)
                self?.appModel?.nook.calendarExtraRows = 0
            }
        )
        scheduleClosingPresentationClear()
    }

    /// Drops the close snapshot once the opened surface has finished fading,
    /// unless the island opened again in the meantime (opening clears it too).
    private func scheduleClosingPresentationClear() {
        let generation = overlayTransitionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Motion.openedSurfaceUnmountDelay) { [weak self] in
            guard let self,
                  self.overlayTransitionGeneration == generation,
                  self.notchStatus != .opened else {
                return
            }
            self.closingPresentation = nil
        }
    }

    /// Coordinates overlay transitions.
    ///
    /// Shape morphing, content fade and corner radius are driven by SwiftUI
    /// `.animation()` modifiers reacting to `notchStatus` and `openedLayout`.
    /// The window is resized around them, never animated: it grows before the
    /// shape and shrinks after it (`OverlayPanelController.updatePlacement`).
    /// Opening publishes the layout before `notchStatus` flips, so the open
    /// spring lands on the right size.
    private func transitionOverlay(
        to status: NotchStatus,
        reason: NotchOpenReason?,
        surface: IslandSurface,
        interactive: Bool,
        beforeTransition: (() -> Void)?,
        afterStateChange: (() -> Void)? = nil,
        onPlacementResolved: (() -> Void)? = nil
    ) {
        beforeTransition?()

        overlayTransitionGeneration &+= 1

        // Reset measured notification height when the surface changes so stale
        // measurements from a previous notification don't mis-size the new one.
        if surface != islandSurface {
            appModel?.measuredNotificationContentHeight = 0
        }

        islandSurface = surface
        notchOpenReason = reason

        if status == .opened {
            closingPresentation = nil
            // Resolve and publish the heights now, with the surface and
            // reason already set and before `notchStatus` changes. Coming
            // from closed this is not animated; re-presenting while already
            // open follows the open-island rule in `publishOpenedLayout`.
            performLayoutRefresh(animated: true, allowsWithoutPanel: true)
        }

        notchStatus = status
        overlayPanelController.setInteractive(interactive)

        if status == .opened, let appModel {
            assignPlacementDiagnostics(
                overlayPanelController.show(
                    model: appModel,
                    preferredScreenID: preferredOverlayScreenID
                )
            )
        }

        afterStateChange?()
        onPlacementResolved?()
    }

    func notchPop() {
        guard notchStatus == .closed else { return }
        islandSurface = .sessionList()
        notchStatus = .popping
        DispatchQueue.main.asyncAfter(deadline: .now() + Motion.popDuration) { [weak self] in
            guard self?.notchStatus == .popping else { return }
            self?.notchStatus = .closed
        }
    }

    func performBootAnimation() {
        DispatchQueue.main.asyncAfter(deadline: .now() + IslandBootAnimation.openDelay) { [weak self] in
            // A link or a card may have opened the island already. The
            // animation leaves it alone.
            guard let self, IslandBootAnimation.shouldOpen(status: self.notchStatus) else { return }
            self.notchOpen(reason: .boot, surface: .sessionList())
            DispatchQueue.main.asyncAfter(deadline: .now() + IslandBootAnimation.openDuration) { [weak self] in
                // Closes only what it opened. An island a link pinned in
                // the meantime no longer carries the boot reason.
                guard let self, IslandBootAnimation.shouldClose(reason: self.notchOpenReason) else { return }
                self.notchClose()
            }
        }
    }

    func ensureOverlayPanel() {
        guard let appModel else { return }
        overlayPanelController.ensurePanel(model: appModel, preferredScreenID: preferredOverlayScreenID)
    }

    // Legacy compatibility
    func showOverlay() { notchOpen(reason: .click, surface: .sessionList()) }
    func hideOverlay() { notchClose() }

    /// A click inside a hover-opened island keeps it open: it stops
    /// following the pointer and closes on a click outside, like an island
    /// that was opened by a click. Nothing is presented again, because the
    /// click itself already made the panel key.
    func pinHoverOpenedIsland() {
        guard notchStatus == .opened, notchOpenReason == .hover else { return }
        notchOpenReason = .click
    }

    /// A link from another app turned the page of an island that was only
    /// passing through: hover-opened, or up for the boot animation. It now
    /// stays open like one opened by a click.
    func pinIslandOpenedForLink() {
        guard notchStatus == .opened, IslandURLPageMove.pinsOnTurn(reason: notchOpenReason) else { return }
        notchOpenReason = .click
    }

    /// Transition from notification mode (single session) to full session list.
    /// - Parameter clearExpansion: If true, clears the actionable session's expansion
    ///   (used for completion notifications which are informational only).
    func expandNotificationToSessionList(clearExpansion: Bool = false) {
        if clearExpansion {
            islandSurface = .sessionList()
        }
        // When not clearing, keep actionableSessionID so approval/question expansion persists
        notchOpenReason = .click
        notificationAutoCollapseTask?.cancel()
        notificationAutoCollapseTask = nil
        refreshOverlayPlacementIfVisible()
    }

    /// The island's footprint for the tour's window. See
    /// `OverlayPanelController.openedIslandFootprint`.
    func openedIslandFootprint() -> OnboardingIslandFootprint? {
        overlayPanelController.openedIslandFootprint(
            model: appModel,
            preferredScreenID: preferredOverlayScreenID
        )
    }

    // MARK: - Display configuration

    func refreshOverlayDisplayConfiguration() {
        let reconciliation = OverlayDisplayPreferencePolicy.reconcile(
            availableOptions: overlayPanelController.availableDisplayOptions(),
            selectionID: overlayDisplaySelectionID,
            rememberedSelectionTitle: overlayDisplaySelectionTitle
        )
        overlayDisplaySelectionID = reconciliation.selectionID
        overlayDisplaySelectionTitle = reconciliation.selectionTitle
        overlayDisplayOptions = reconciliation.displayOptions
        persistOverlayDisplayPreference()

        refreshOverlayPlacementNow()
    }

    /// Coalesced: any number of calls in one run-loop turn become one layout
    /// refresh at the end of it.
    func refreshOverlayPlacement() {
        scheduleLayoutRefresh()
    }

    func refreshOverlayPlacementIfVisible() {
        scheduleLayoutRefresh()
    }

    /// Refreshes at once, without animation. For display changes, the open
    /// and show paths and tests.
    func refreshOverlayPlacementNow() {
        performLayoutRefresh(animated: false)
    }

    /// Asks for one layout refresh at the end of this run-loop turn. Content
    /// changes often arrive in bursts (a page switch resizes two to four
    /// times), and each refresh resolves the layout and may resize the window.
    func scheduleLayoutRefresh() {
        guard !isLayoutRefreshPending else {
            OverlayTrace.log("layout refresh requested (already pending)")
            return
        }

        isLayoutRefreshPending = true
        if OverlayTrace.isEnabled {
            let target = overlayPanelController.resolvePlacement(
                model: appModel,
                preferredScreenID: preferredOverlayScreenID
            )?.frame.height
            OverlayTrace.log("layout refresh requested (target height \(target.map { "\($0)" } ?? "none"))")
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isLayoutRefreshPending = false
            self.performLayoutRefresh(animated: true)
        }
    }

    /// Resolves the layout, applies the window frame, then publishes the
    /// layout: a grow reaches the window before the shape moves, and a
    /// shrink is left to the controller's delayed work item.
    ///
    /// Without a panel there is nothing to size, so only the diagnostics
    /// update, unless `allowsWithoutPanel` (the open path, which must publish
    /// before the first panel exists).
    func performLayoutRefresh(animated: Bool) {
        performLayoutRefresh(animated: animated, allowsWithoutPanel: false)
    }

    private func performLayoutRefresh(animated: Bool, allowsWithoutPanel: Bool) {
        performedLayoutRefreshCount += 1
        let signpost = OverlayTrace.signposter.beginInterval("LayoutRefresh")
        defer { OverlayTrace.signposter.endInterval("LayoutRefresh", signpost) }

        guard allowsWithoutPanel || overlayPanelController.hasPanel else {
            assignPlacementDiagnostics(
                overlayPanelController.placementDiagnostics(preferredScreenID: preferredOverlayScreenID)
            )
            OverlayTrace.log("layout refresh performed without a panel")
            return
        }

        guard let update = overlayPanelController.updatePlacement(
            model: appModel,
            preferredScreenID: preferredOverlayScreenID
        ) else {
            assignPlacementDiagnostics(nil)
            return
        }

        // The open path can run before the first panel exists; `show()` then
        // returns the diagnostics for the real panel size.
        if overlayPanelController.hasPanel {
            assignPlacementDiagnostics(update.diagnostics)
        }
        let placement = update.placement
        OverlayTrace.log(
            "layout refresh performed (target height \(placement.frame.height), shape \(placement.layout.shapeHeight), animated \(animated), status \(String(describing: notchStatus)))"
        )

        // While the island fades out the view keeps drawing the opened
        // layout, so it must not change under the fade.
        let holdsLayoutForClose = notchStatus != .opened && closingPresentation != nil
        if !holdsLayoutForClose {
            publishOpenedLayout(placement.layout, screenID: placement.screenID, animated: animated)
        }
        lastLayoutScreenID = placement.screenID
    }

    /// Publishes `layout` only when it changed. It animates with
    /// `Motion.islandResize` when `animated` and the island is open on the
    /// same screen as the last refresh; otherwise (opening, closed, another
    /// screen) it lands without animation.
    func publishOpenedLayout(_ layout: IslandOpenedLayout, screenID: String, animated: Bool) {
        guard layout != openedLayout else { return }

        let animates = animated && notchStatus == .opened && lastLayoutScreenID == screenID
        if animates {
            withMotion(Motion.islandResize) {
                openedLayout = layout
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                openedLayout = layout
            }
        }
    }

    /// Assigns only when the value differs, so views that read the
    /// diagnostics do not re-render on every refresh.
    private func assignPlacementDiagnostics(_ diagnostics: OverlayPlacementDiagnostics?) {
        guard diagnostics != overlayPlacementDiagnostics else { return }
        overlayPlacementDiagnostics = diagnostics
    }

    /// Re-reads the diagnostics after the window frame changed on its own
    /// (a delayed shrink).
    private func refreshPlacementDiagnostics() {
        assignPlacementDiagnostics(
            overlayPanelController.placementDiagnostics(preferredScreenID: preferredOverlayScreenID)
        )
    }

    // MARK: - The tour's hold (D44)

    /// Turns the welcome tour's hold on or off. On: the island is open on
    /// the Nook page and stays open; the pointer leaving, a click outside,
    /// a click on the notch and every other request to close leave it
    /// open (`IslandPointerRules`, `notchClose`). It opens without
    /// taking keyboard focus from the tour's window. Off: an island the
    /// hold opened, or held against a close, is closed; one the user had
    /// open before follows its own rules again.
    func setTourHoldsIslandOpen(_ holds: Bool) {
        guard holds != tourHoldsIslandOpen else { return }
        tourHoldsIslandOpen = holds
        if holds {
            showNookForTour()
        } else if tourOwnsOpenIsland {
            let wasOpen = notchStatus != .closed
            tourOwnsOpenIsland = false
            if wasOpen { closeIsland() }
        }
    }

    private func showNookForTour() {
        if notchStatus == .opened {
            // Already open for another reason: keep it and turn it to
            // the Nook page. It stays the user's, and closes under its
            // own rules once the hold is off.
            appModel?.showNookPage()
            return
        }
        tourOwnsOpenIsland = true
        appModel?.notchOpen(reason: .click, page: .nook)
    }

    /// A close was asked for while the hold is on. A card or the boot
    /// animation is replaced by the Nook page; the Nook page stays.
    private func returnToNookForTour() {
        guard notchStatus != .opened || notchOpenReason == .notification || notchOpenReason == .boot else { return }
        tourOwnsOpenIsland = true
        notificationAutoCollapseTask?.cancel()
        notificationAutoCollapseTask = nil
        appModel?.notchOpen(reason: .click, page: .nook)
    }

    // MARK: - Pointer tracking

    var shouldAutoCollapseOnMouseLeave: Bool {
        IslandPointerRules.pointerLeaveCloses(
            otherRules: autoCollapsesWithoutTourHold,
            holdsOpenForTour: tourHoldsIslandOpen
        )
    }

    private var autoCollapsesWithoutTourHold: Bool {
        if ignoresPointerExitDuringHarness {
            return false
        }

        guard notchStatus == .opened else {
            return false
        }

        // Dragging and resizing Nook widgets must not close the island.
        if appModel?.nook.isEditingLayout == true, appModel?.showsNookPage == true {
            return false
        }

        // A mirror in use must not vanish when the pointer drifts off, and
        // neither must a half-typed calendar event.
        if appModel?.showsNookPage == true,
           appModel?.nookMirrorHeight != nil || appModel?.nook.isAddingEvent == true {
            return false
        }

        // The tray's share picker hangs off the island. Closing under it
        // would pull away the file being shared.
        if appModel?.nook.tray.isSharePickerOpen == true {
            return false
        }

        // Nor must a reply to an agent that is being typed.
        if appModel?.isTypingAgentReply == true {
            return false
        }

        if notchOpenReason == .hover && !islandSurface.isNotificationCard {
            return true
        }

        return notchOpenReason == .notification
            && islandSurface.autoDismissesWhenPresentedAsNotification(session: activeIslandCardSession)
    }

    var autoCollapseOnMouseLeaveRequiresPriorSurfaceEntry: Bool {
        guard notchOpenReason == .notification else { return false }
        // If the session was removed from state (e.g. by process monitoring),
        // default to requiring prior surface entry — prevents the notification
        // from closing immediately on pointer exit before the user sees it.
        guard let session = activeIslandCardSession else { return true }
        return islandSurface.autoDismissesWhenPresentedAsNotification(session: session)
    }

    var showsNotificationCard: Bool {
        islandSurface.isNotificationCard
    }

    func notePointerInsideIslandSurface() {
        guard shouldTrackPointerInsideIslandSurface else {
            return
        }

        isPointerInsideIslandSurface = true
        autoCollapseSurfaceHasBeenEntered = true

        if notchOpenReason == .notification {
            notificationAutoCollapseTask?.cancel()
            notificationAutoCollapseTask = nil
        }
    }

    func handlePointerExitedIslandSurface() {
        guard shouldTrackPointerInsideIslandSurface else {
            return
        }

        isPointerInsideIslandSurface = false

        guard shouldAutoCollapseOnMouseLeave else {
            return
        }

        guard !autoCollapseOnMouseLeaveRequiresPriorSurfaceEntry
                || autoCollapseSurfaceHasBeenEntered else {
            return
        }

        notchClose()
    }

    // MARK: - Notification surfaces

    func presentNotificationSurface(_ surface: IslandSurface) {
        guard surface.isNotificationCard else {
            return
        }

        guard !shouldPreserveCurrentNotificationSurface(against: surface) else {
            return
        }

        appModel?.measuredNotificationContentHeight = 0
        NotificationSoundService.playNotification(isMuted: isSoundMuted)
        notchOpen(reason: .notification, surface: surface)
    }

    func shouldPreserveCurrentNotificationSurface(against candidate: IslandSurface) -> Bool {
        guard candidate.isNotificationCard,
              notchStatus == .opened,
              notchOpenReason == .notification,
              islandSurface.isNotificationCard,
              islandSurface != candidate else {
            return false
        }

        return isPointerInsideCurrentNotificationCard
    }

    func reconcileIslandSurfaceAfterStateChange() {
        guard islandSurface.isNotificationCard else {
            return
        }

        let session = activeIslandCardSession
        guard islandSurface.matchesCurrentState(of: session) else {
            if notchOpenReason == .notification {
                notchClose()
            } else {
                islandSurface = .sessionList()
            }
            return
        }

        updateNotificationAutoCollapse()
    }

    func dismissNotificationSurfaceIfPresent(for sessionID: String) {
        guard islandSurface.sessionID == sessionID,
              notchOpenReason == .notification else {
            return
        }

        notchClose()
    }

    func dismissOverlayForJump() {
        guard isOverlayVisible else {
            return
        }

        notchClose()
    }

    private func updateNotificationAutoCollapse() {
        notificationAutoCollapseTask?.cancel()
        notificationAutoCollapseTask = nil

        guard notchStatus == .opened,
              notchOpenReason == .notification,
              islandSurface.autoDismissesWhenPresentedAsNotification(session: activeIslandCardSession) else {
            return
        }

        if overlayPanelController.isPointInExpandedArea(currentPointerLocation) {
            notePointerInsideIslandSurface()
            return
        }

        notificationAutoCollapseTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(Self.notificationSurfaceAutoCollapseDelay))
            } catch {
                // Task was cancelled (e.g. a new event reset the timer).
                // Do NOT proceed — the replacement task owns the new timer.
                return
            }

            guard let self,
                  self.notchStatus == .opened,
                  self.notchOpenReason == .notification,
                  self.islandSurface.autoDismissesWhenPresentedAsNotification(session: self.activeIslandCardSession) else {
                return
            }

            guard !self.shouldDeferTimedNotificationAutoCollapse else {
                return
            }

            self.notchClose()
        }
    }

    var shouldDeferTimedNotificationAutoCollapse: Bool {
        isPointerInsideIslandSurface
            || overlayPanelController.isPointInExpandedArea(currentPointerLocation)
            || appModel?.isTypingAgentReply == true
    }

    private var shouldTrackPointerInsideIslandSurface: Bool {
        shouldAutoCollapseOnMouseLeave
            || (notchStatus == .opened && notchOpenReason == .notification && islandSurface.isNotificationCard)
    }

    private var isPointerInsideCurrentNotificationCard: Bool {
        isPointerInsideIslandSurface
            || overlayPanelController.isPointInExpandedArea(currentPointerLocation)
    }

    // MARK: - Debug snapshots (overlay portion)

    func applyOverlayState(from snapshot: IslandDebugSnapshot, presentOverlay: Bool, autoCollapseNotificationCards: Bool) {
        notificationAutoCollapseTask?.cancel()
        notificationAutoCollapseTask = nil
        autoCollapseSurfaceHasBeenEntered = false
        isPointerInsideIslandSurface = false

        islandSurface = snapshot.islandSurface
        notchOpenReason = snapshot.notchOpenReason
        closingPresentation = nil
        if presentOverlay, snapshot.notchStatus == .opened {
            // Same order as a real open: heights first, then the status.
            performLayoutRefresh(animated: true, allowsWithoutPanel: true)
        }
        notchStatus = snapshot.notchStatus

        if autoCollapseNotificationCards {
            updateNotificationAutoCollapse()
        }

        guard presentOverlay, let appModel else {
            return
        }

        // Immediate interactivity update.
        let interactive = snapshot.notchStatus == .opened
        overlayPanelController.setInteractive(interactive)

        // Present the panel on the next run-loop iteration, after the state above lands.
        overlayTransitionGeneration &+= 1
        let capturedGeneration = overlayTransitionGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.overlayTransitionGeneration == capturedGeneration else { return }
            switch snapshot.notchStatus {
            case .opened:
                self.assignPlacementDiagnostics(
                    self.overlayPanelController.show(
                        model: appModel,
                        preferredScreenID: self.preferredOverlayScreenID
                    )
                )
            case .closed, .popping:
                self.overlayPanelController.ensurePanel(
                    model: appModel,
                    preferredScreenID: self.preferredOverlayScreenID
                )
                self.refreshOverlayPlacementNow()
            }
            self.harnessRuntimeMonitor?.recordMilestone("overlayPresented", message: snapshot.title)
        }
    }

    // MARK: - Persistence

    private func persistOverlayDisplayPreference() {
        if overlayDisplaySelectionID == OverlayDisplayOption.automaticID {
            overlayDisplaySelectionTitle = nil
            defaults.removeObject(forKey: OverlayDisplayPreferencePolicy.preferenceDefaultsKey)
            defaults.removeObject(forKey: OverlayDisplayPreferencePolicy.preferenceTitleDefaultsKey)
        } else {
            if let selectedOption = overlayDisplayOptions.first(where: {
                $0.id == overlayDisplaySelectionID && $0.isAvailable
            }) {
                overlayDisplaySelectionTitle = selectedOption.title
            }
            defaults.set(
                overlayDisplaySelectionID,
                forKey: OverlayDisplayPreferencePolicy.preferenceDefaultsKey
            )
            if let overlayDisplaySelectionTitle {
                defaults.set(
                    overlayDisplaySelectionTitle,
                    forKey: OverlayDisplayPreferencePolicy.preferenceTitleDefaultsKey
                )
            }
        }
    }
}
