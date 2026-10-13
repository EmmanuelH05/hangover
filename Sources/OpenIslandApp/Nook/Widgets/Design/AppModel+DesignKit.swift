import Foundation

extension AppModel {
    /// Joins the design kit to the parts of the app it must not own: the
    /// island, which a pick from the card closes, and the agent
    /// shortcuts, which the eyedropper's shortcut must stay clear of.
    func wireDesignKit() {
        let kit = nook.design
        // The loupe samples what is under it. An open island would be in
        // the way of whatever sits behind it.
        kit.willSampleFromIsland = { [weak self] in
            guard let self, self.notchStatus == .opened else { return }
            self.notchClose()
        }
        // A name question needs the keyboard. A right click on a widget
        // does not make the island's panel the key window by itself.
        kit.onNameQuestionOpened = { [weak self] in
            self?.overlay.overlayPanelController.makePanelKey()
        }
        kit.openSettings = { [weak self] in self?.showSettings() }
        // The kit's own windows have no root that hands the accent down.
        HangoverAccentSource.tint = { [weak self] in self?.accentTint ?? .standard }
        // The eyedropper's keys are not the agents' to take while it is on.
        agentHotkeys.reservedShortcuts = { [weak kit] in
            guard let kit, kit.isLive, let combo = kit.hotkey.combo else { return [] }
            return [combo]
        }
        kit.hotkey.agentShortcuts = { [weak self] in
            guard let hotkeys = self?.agentHotkeys else { return [] }
            return AgentHotkeyAction.allCases.map { hotkeys.combo(for: $0) }
        }
        // While the eyedropper's shortcut is being recorded the agent
        // shortcuts are let go of too. A press meant for the recorder
        // must not approve a request.
        kit.hotkey.onRecordingChange = { [weak self] isRecording in
            guard let hotkeys = self?.agentHotkeys else { return }
            if isRecording {
                hotkeys.beginRecording()
            } else {
                hotkeys.endRecording()
            }
        }
    }
}

/// What the app does about the design kit's files when it is asked to quit.
enum NookDesignQuitDecision: Equatable, Sendable {
    /// Nothing is waiting to be written.
    case now
    /// Something is, and the quit waits for it.
    case afterWrites
}

extension AppModel {
    /// Whether a quit can go on at once. A change made a moment before it
    /// is still on its way to the disk, and a quit would lose it.
    var designKitQuitDecision: NookDesignQuitDecision {
        nook.design.hasPendingWrites ? .afterWrites : .now
    }

    /// Waits until every change of the kit is on disk.
    func flushDesignKitBeforeQuit() async {
        await nook.design.flush()
    }
}

extension NookModel {
    /// A widget's switch on the Nook tab of Settings. Turning the calendar or
    /// the to-do widget on is when macOS is asked for its permission. The
    /// design kit and Link to MP3 start off, and a layout may have taken
    /// either off the display in use while it was off. Switching it on there
    /// is asking for the card, which it gets back. Only these two are taken
    /// off the hidden list: the other widgets are switched on the way they
    /// always were, and the other displays keep their own lists.
    func setWidgetFromSettings(_ kind: NookWidgetKind, enabled: Bool) {
        // A widget the build does not offer has no switch to flip.
        guard kind.isOffered else { return }
        setWidget(kind, enabled: enabled)
        guard enabled else { return }
        if kind == .design || kind == .linkAudio {
            updateDisplayPreferences(for: activeProfile()) { $0.hiddenWidgets.remove(kind) }
        }
        widgetTurnedOn(kind)
    }
}

extension NookWidgetKind {
    /// The order a display's page goes back to when the tour puts it back:
    /// the widgets it listed first, in its order, then every other widget in
    /// the order it has now. The tour offers and draws every widget, and none
    /// keeps a slot of its own.
    static func orderRestoring(_ listed: [NookWidgetKind], in current: [NookWidgetKind]) -> [NookWidgetKind] {
        var seen: Set<NookWidgetKind> = []
        let listedNow = listed.filter { current.contains($0) && seen.insert($0).inserted }
        return listedNow + current.filter { !seen.contains($0) }
    }

    /// The widgets that are off until the user switches them on: mirror and
    /// weather, and the design kit and Link to MP3. The welcome tour lists
    /// every widget on its widgets page and says which ones start off.
    static var startsOff: [NookWidgetKind] {
        offered.filter { !defaultEnabled.contains($0) }
    }

    /// The two tools, which start off and have their own step at the end of
    /// the tour's widget walk. A layout does not list either, and the tour
    /// puts back the ones the user switched on.
    static var tools: [NookWidgetKind] { [.design, .linkAudio].filter(\.isOffered) }
}
