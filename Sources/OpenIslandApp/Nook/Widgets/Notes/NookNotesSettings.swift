import AppKit
import SwiftUI

/// Settings, Nook, Notes (D70): where notes are saved, the folder, and the
/// shortcut that starts a new note.
struct NookNotesSettings: View {
    var nook: NookModel

    private static let notesAppURL = URL(fileURLWithPath: "/System/Applications/Notes.app")

    @State private var isRecording = false
    /// The rule the last recorded shortcut broke.
    @State private var rejection: NookNoteHotkeyProblem?
    @State private var recorder = AgentHotkeyRecorder()

    var body: some View {
        let lang = LanguageManager.shared
        let store = nook.notes
        Section(lang.t("nook.notes.settings.section")) {
            Picker(lang.t("nook.notes.settings.saveTo"), selection: Binding(
                get: { store.saveTo },
                set: { store.setSaveTo($0) }
            )) {
                ForEach(NookNotesSaveTo.allCases) { choice in
                    Text(lang.t(Self.titleKey(for: choice))).tag(choice)
                }
            }
            .settingsAnchor(SettingsIndex.entry("nook.notes.saveTo")!)

            if store.saveTo.usesFolder {
                folderRows(store)
                // A folder that is gone or cannot be read: the card says so on
                // the island, and Settings is a window of its own.
                if let notice = store.problem, notice.isAboutFolder {
                    problemRows(notice, store: store)
                }
            }
            Text(lang.t(Self.noteKey(for: store.saveTo)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if store.saveTo.usesAppleNotes {
                if let notice = store.appleNotesNotice {
                    problemRows(notice, store: store)
                }
                Button(lang.t("nook.notes.settings.openNotes")) {
                    NSWorkspace.shared.open(Self.notesAppURL)
                }
            }

            shortcutRow(store.hotkey)
                .settingsAnchor(SettingsIndex.entry("nook.notes.hotkey")!)
            Text(lang.t("nook.notes.settings.hotkey.note"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onDisappear(perform: stopRecording)
    }

    // MARK: Words

    static func titleKey(for choice: NookNotesSaveTo) -> String {
        "nook.notes.saveTo.\(choice.rawValue)"
    }

    /// The line under the picker: what the choice does.
    static func noteKey(for choice: NookNotesSaveTo) -> String {
        "nook.notes.settings.\(choice.rawValue).note"
    }

    /// What is wrong with where the notes go, in words, and the buttons that
    /// fix it: Apple Notes not getting the notes (N4), which stays until a
    /// send works, or a folder that is gone or cannot be read (N6).
    private func problemRows(_ notice: NookNotesNotice, store: NookNotesStore) -> some View {
        let lang = LanguageManager.shared
        return VStack(alignment: .leading, spacing: 6) {
            Label(NookNotesProblemLine.sentence(for: notice), systemImage: notice.symbol)
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(notice.actions, id: \.self) { action in
                Button(lang.t(action.titleKey)) { store.perform(action) }
            }
        }
    }

    // MARK: Folder

    private func folderRows(_ store: NookNotesStore) -> some View {
        let lang = LanguageManager.shared
        return Group {
            LabeledContent(lang.t("nook.notes.settings.folder")) {
                Text((store.folderURL.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .settingsAnchor(SettingsIndex.entry("nook.notes.folder")!)
            HStack {
                Button(lang.t("nook.notes.settings.chooseFolder")) { chooseFolder(store) }
                Button(lang.t("nook.notes.settings.reveal")) { store.revealFolder() }
            }
        }
    }

    /// Opens the folder chooser in the Obsidian iCloud folder when there is
    /// one, otherwise in the folder notes are in now.
    private func chooseFolder(_ store: NookNotesStore) {
        NookNotesFolderChooser.choose(for: store)
    }

    // MARK: Shortcut

    private func shortcutRow(_ hotkey: NookNoteHotkeyController) -> some View {
        let lang = LanguageManager.shared
        return LabeledContent {
            HStack(spacing: 10) {
                Button {
                    isRecording ? stopRecording() : startRecording()
                } label: {
                    Text(isRecording ? lang.t("settings.general.agentHotkeys.recording") : hotkey.displayText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minWidth: 64)
                }
                .help(lang.t("settings.general.agentHotkeys.change"))
                .accessibilityLabel(lang.t("nook.notes.settings.hotkey"))
                .accessibilityValue(hotkey.displayText)

                Button(lang.t("nook.notes.settings.hotkey.reset")) {
                    stopRecording()
                    rejection = nil
                    hotkey.resetToDefault()
                }
                .disabled(hotkey.combo == NookNoteHotkeyRules.defaultCombo)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(lang.t("nook.notes.settings.hotkey"))
                if let message = message(for: hotkey) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// What is wrong with the shortcut, if anything: the rule the last
    /// recording broke first, what macOS said otherwise.
    private func message(for hotkey: NookNoteHotkeyController) -> String? {
        let lang = LanguageManager.shared
        if let rejection { return lang.t(rejection.messageKey) }
        switch hotkey.status {
        case let .failed(code):
            return lang.t("settings.general.agentHotkeys.status.failed", Int(code))
        case .usedBySystem:
            return lang.t("settings.general.agentHotkeys.status.usedBySystem")
        case let .invalid(problem):
            return lang.t(problem.messageKey)
        case .inactive, .ready:
            return nil
        }
    }

    private func startRecording() {
        rejection = nil
        isRecording = true
        nook.notes.hotkey.beginRecording()
        recorder.start { event in
            handleRecordedKey(event)
        }
    }

    private func stopRecording() {
        guard isRecording || recorder.isRecording else { return }
        recorder.stop()
        isRecording = false
        nook.notes.hotkey.endRecording()
    }

    private func handleRecordedKey(_ event: NSEvent) {
        let modifiers = AgentHotkeyModifiers(eventFlags: event.modifierFlags)
        // Escape on its own gives up and keeps what was there.
        if event.keyCode == AgentHotkeyKeyboard.escape, modifiers.isEmpty {
            stopRecording()
            return
        }
        let combo = AgentHotkeyCombo(keyCode: event.keyCode, modifiers: modifiers)
        // The controller checks the shortcut before it lets go of the old one.
        let problem = nook.notes.hotkey.setCombo(combo)
        stopRecording()
        rejection = problem
    }
}
