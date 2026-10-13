import AppKit
import SwiftUI

/// The window of one floating reference. It is a non-activating panel
/// that becomes key only when asked to: opening it, dragging in it,
/// scrolling, pinching and pressing its controls all leave the keyboard
/// with the app the user is working in. A plain click on the picture is
/// the one thing that gives it the keyboard, and Escape then closes it.
final class NookDesignReferencePanel: NSPanel {
    var onClose: (() -> Void)?
    var onZoomIn: (() -> Void)?
    var onZoomOut: (() -> Void)?
    var onFit: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Escape, when the panel has the keyboard.
    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == AgentHotkeyKeyboard.escape {
            onClose?()
            return
        }
        switch event.charactersIgnoringModifiers {
        case "+", "=": onZoomIn?()
        case "-": onZoomOut?()
        case "0": onFit?()
        default: super.keyDown(with: event)
        }
    }
}

/// Hosts the panel's SwiftUI view and hears the two things SwiftUI does
/// not report with a pointer position: scrolling and pinching.
final class NookDesignPanelHostingView: NSHostingView<NookDesignPanelView> {
    /// True when the scroll was used.
    var onScroll: ((NSEvent) -> Bool)?
    var onMagnify: ((NSEvent) -> Void)?

    required init(rootView: NookDesignPanelView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The panel is seldom key. Without this the first click on it would
    /// be spent on nothing.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func scrollWheel(with event: NSEvent) {
        if onScroll?(event) != true {
            super.scrollWheel(with: event)
        }
    }

    override func magnify(with event: NSEvent) {
        onMagnify?(event)
    }
}

/// Opens, places and closes the floating reference panels. Only a real
/// launch makes one: tests and harness runs never open a window.
@MainActor
final class NookDesignReferencePanelController: NSObject, NookDesignReferencePresenting, NSWindowDelegate {
    private struct Entry {
        let panel: NookDesignReferencePanel
        let state: NookDesignPanelState
        let onClose: @MainActor () -> Void
    }

    private var entries: [UUID: Entry] = [:]
    /// Where the pointer and the panel were when a drag began to move it.
    private var moveStart: (id: UUID, pointer: CGPoint, origin: CGPoint)?

    // MARK: Rules that need AppKit's types

    /// An always on top panel floats over other apps' windows.
    nonisolated static func level(isPinned: Bool) -> NSWindow.Level {
        isPinned ? .floating : .normal
    }

    /// A panel may sit over another app's full screen window. An always
    /// on top panel also follows from one Space to the next. One that is
    /// not stays on the Space it was opened on, like any window.
    nonisolated static func collectionBehavior(isPinned: Bool) -> NSWindow.CollectionBehavior {
        isPinned ? [.fullScreenAuxiliary, .canJoinAllSpaces] : [.fullScreenAuxiliary]
    }

    // MARK: NookDesignReferencePresenting

    func present(
        _ reference: NookDesignReference,
        image: CGImage,
        slot: Int,
        onClose: @escaping @MainActor () -> Void
    ) {
        if let existing = entries[reference.id] {
            existing.panel.orderFrontRegardless()
            return
        }
        let id = reference.id
        let state = NookDesignPanelState(reference: reference, image: image)
        let screen = Self.screenUnderPointer()
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 720)
        let size = NookDesignPanelRules.initialSize(pictureAspect: reference.aspectRatio, available: Self.room(in: visible))
        let origin = NookDesignPanelRules.frameOrigin(slot: slot, size: size, in: visible)

        let panel = NookDesignReferencePanel(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = reference.name.isEmpty
            ? LanguageManager.shared.t("nook.design.reference.untitled")
            : reference.name
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .black
        panel.animationBehavior = Motion.prefersReducedMotion ? .none : .utilityWindow
        panel.minSize = NookDesignPanelRules.panelSize(
            width: NookDesignPanelRules.minimumWidth, pictureAspect: reference.aspectRatio
        )
        apply(isPinned: state.isPinned, to: panel)

        let actions = NookDesignPanelActions(
            setPinned: { [weak self] pinned in self?.setPinned(pinned, for: id) },
            setOpacity: { [weak self] opacity in self?.setOpacity(opacity, for: id) },
            close: { [weak self] in self?.close(id) },
            focus: { [weak self] in self?.entries[id]?.panel.makeKey() },
            beginMove: { [weak self] in self?.beginMove(id) },
            move: { [weak self] in self?.continueMove(id) }
        )
        let hosting = NookDesignPanelHostingView(rootView: NookDesignPanelView(state: state, actions: actions))
        // The panel's size is the rules' to decide, never the view's.
        hosting.sizingOptions = []
        hosting.onScroll = { [weak self] event in self?.scroll(event, for: id) ?? false }
        hosting.onMagnify = { [weak self] event in self?.magnify(event, for: id) }
        panel.contentView = hosting
        panel.onClose = { [weak self] in self?.close(id) }
        panel.onZoomIn = { [weak state] in state?.zoomIn() }
        panel.onZoomOut = { [weak state] in state?.zoomOut() }
        panel.onFit = { [weak state] in state?.fit() }
        panel.delegate = self
        panel.setFrame(CGRect(origin: origin, size: size), display: false)

        entries[id] = Entry(panel: panel, state: state, onClose: onClose)
        // Shown without being made key: the keyboard stays where it is.
        panel.orderFrontRegardless()
    }

    func focus(_ id: UUID) {
        entries[id]?.panel.orderFrontRegardless()
    }

    func close(_ id: UUID) {
        // Closing runs `windowWillClose`, which lets go of the entry.
        entries[id]?.panel.close()
    }

    func closeAll() {
        for id in Array(entries.keys) {
            close(id)
        }
    }

    // MARK: NSWindowDelegate

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard let entry = entry(for: sender) else { return frameSize }
        let visible = sender.screen?.visibleFrame ?? CGRect(origin: .zero, size: frameSize)
        return NookDesignPanelRules.resizedSize(
            proposed: frameSize,
            current: sender.frame.size,
            pictureAspect: entry.state.reference.aspectRatio,
            available: visible.size
        )
    }

    func windowDidBecomeKey(_ notification: Notification) {
        entry(for: notification.object as? NSWindow)?.state.isFocused = true
    }

    func windowDidResignKey(_ notification: Notification) {
        entry(for: notification.object as? NSWindow)?.state.isFocused = false
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = entries.first(where: { $0.value.panel === window })?.key,
              let entry = entries.removeValue(forKey: id) else { return }
        if moveStart?.id == id { moveStart = nil }
        entry.panel.delegate = nil
        entry.onClose()
    }

    // MARK: Controls

    private func setPinned(_ pinned: Bool, for id: UUID) {
        guard let entry = entries[id] else { return }
        entry.state.isPinned = pinned
        apply(isPinned: pinned, to: entry.panel)
    }

    private func apply(isPinned: Bool, to panel: NSPanel) {
        panel.isFloatingPanel = isPinned
        panel.level = Self.level(isPinned: isPinned)
        panel.collectionBehavior = Self.collectionBehavior(isPinned: isPinned)
    }

    private func setOpacity(_ opacity: Double, for id: UUID) {
        guard let entry = entries[id] else { return }
        let clamped = NookDesignPanelRules.clampedOpacity(opacity)
        entry.state.opacity = clamped
        entry.panel.alphaValue = clamped
    }

    private func scroll(_ event: NSEvent, for id: UUID) -> Bool {
        guard let entry = entries[id] else { return false }
        let state = entry.state
        let size = entry.panel.frame.size
        if !event.modifierFlags.isDisjoint(with: [.command, .option]) {
            state.zoom = state.zoom.zoomed(
                by: NookDesignPanelRules.zoomFactor(forScroll: event.scrollingDeltaY),
                around: NookDesignPanelRules.anchor(forPanelPoint: event.locationInWindow, panelSize: size),
                fitted: state.fitted
            )
            return true
        }
        // At the fit there is nothing to scroll to.
        let areaHeight = size.height - NookDesignPanelRules.barHeight
        guard state.zoom.scale > 1, size.width > 0, areaHeight > 0 else { return false }
        state.zoom = state.zoom.panned(
            by: CGSize(width: event.scrollingDeltaX / size.width, height: event.scrollingDeltaY / areaHeight),
            fitted: state.fitted
        )
        return true
    }

    private func magnify(_ event: NSEvent, for id: UUID) {
        guard let entry = entries[id] else { return }
        let state = entry.state
        state.zoom = state.zoom.zoomed(
            by: 1 + event.magnification,
            around: NookDesignPanelRules.anchor(forPanelPoint: event.locationInWindow, panelSize: entry.panel.frame.size),
            fitted: state.fitted
        )
    }

    /// A drag at the fit moves the panel. The pointer's place on the
    /// screen is read, and never the drag's own numbers, which shift as
    /// the panel moves under it.
    private func beginMove(_ id: UUID) {
        guard let entry = entries[id] else { return }
        moveStart = (id, NSEvent.mouseLocation, entry.panel.frame.origin)
    }

    private func continueMove(_ id: UUID) {
        guard let start = moveStart, start.id == id, let entry = entries[id] else { return }
        let pointer = NSEvent.mouseLocation
        entry.panel.setFrameOrigin(CGPoint(
            x: start.origin.x + pointer.x - start.pointer.x,
            y: start.origin.y + pointer.y - start.pointer.y
        ))
    }

    // MARK: Private

    private func entry(for window: NSWindow?) -> Entry? {
        guard let window else { return nil }
        return entries.values.first { $0.panel === window }
    }

    /// The screen the pointer is on, which is the one the island was just
    /// clicked on.
    private static func screenUnderPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
    }

    /// The room a new panel may take: the usable area less a margin.
    private static func room(in visible: CGRect) -> CGSize {
        let margin = NookDesignPanelRules.screenMargin * 2
        return CGSize(width: max(0, visible.width - margin), height: max(0, visible.height - margin))
    }
}
