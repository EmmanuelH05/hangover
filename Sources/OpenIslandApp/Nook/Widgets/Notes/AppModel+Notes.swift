import CoreGraphics
import Foundation

extension AppModel {
    /// Joins the notes to the parts of the app they must not own: the
    /// island, which the new note shortcut opens, and the other shortcuts,
    /// which this one must stay clear of and they of it. Runs after
    /// `wireDesignKit` and `wireRecord`, whose reserved shortcuts it adds to.
    func wireNotes() {
        let notes = nook.notes
        notes.hotkey.onPress = { [weak self] in self?.openNewNoteFromShortcut() }

        // The agent shortcuts may not take the new note keys.
        let reservedBefore = agentHotkeys.reservedShortcuts
        agentHotkeys.reservedShortcuts = { [weak notes] in
            reservedBefore() + (notes.map { [$0.hotkey.combo] } ?? [])
        }
        // Nor Record's, nor the eyedropper's. Their own checks are read as
        // they are and the new note keys are added, which leaves their
        // files as they were.
        let record = nook.record
        let recordOthers = record.hotkey.otherShortcuts
        record.hotkey.otherShortcuts = { [weak notes] in
            recordOthers() + (notes.map { [$0.hotkey.combo] } ?? [])
        }
        let kit = nook.design
        let kitOthers = kit.hotkey.agentShortcuts
        kit.hotkey.agentShortcuts = { [weak notes] in
            kitOthers() + (notes.map { [$0.hotkey.combo] } ?? [])
        }

        // The new note shortcut stays clear of the agents', Record's and the
        // eyedropper's, the way those refuse each other.
        notes.hotkey.otherShortcuts = { [weak self] in
            guard let self else { return [] }
            var others = AgentHotkeyAction.allCases.map { self.agentHotkeys.combo(for: $0) }
            if self.nook.record.isLive { others.append(self.nook.record.hotkey.combo) }
            let kit = self.nook.design
            if kit.isLive, let combo = kit.hotkey.combo { others.append(combo) }
            return others
        }
        // While the shortcut is being recorded the agent shortcuts are let go
        // of too. A press meant for the recorder must not approve a request.
        notes.hotkey.onRecordingChange = { [weak self] isRecording in
            guard let hotkeys = self?.agentHotkeys else { return }
            if isRecording {
                hotkeys.beginRecording()
            } else {
                hotkeys.endRecording()
            }
        }
        // The others may have been set before the keys that refuse them were
        // wired, so the shortcut looks at them now.
        notes.hotkey.refresh()
    }

    /// Saves what is typed in a note, which queues its send to Apple Notes,
    /// and says whether any send is in line. The quit asks before it decides
    /// to wait: the notification that saves a note on quit comes after the wait.
    func prepareNotesForQuit() -> Bool {
        nook.notes.appWillTerminate()
        return nook.notes.hasPendingAppleSync
    }

    /// Waits until every send to Apple Notes in line has been made.
    func flushNotesBeforeQuit() async {
        await nook.notes.waitForAppleNotes()
    }

    /// Control Option J, or the key chosen in Settings: the island opens on
    /// the Nook page with a new blank note and the cursor in it. With the
    /// Notes widget off the page the editor stands alone above the grid. An
    /// approval or a question on screen comes first, and the press does
    /// nothing then.
    func openNewNoteFromShortcut() {
        guard perform(.openNook) else { return }
        nook.notes.beginNewNote()
        // The island's panel does not take the keyboard by itself. The
        // editor asks for the cursor when it appears.
        overlay.overlayPanelController.makePanelKey()
    }
}
