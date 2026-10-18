import AppKit
import SwiftUI

/// Settings section for the Record widget: whether the notch shows in the
/// video, the start and stop shortcut and where the files are. What to
/// capture, the switches and the quality live on the card.
struct NookRecordSettings: View {
    var nook: NookModel

    @State private var isRecording = false
    /// The rule the last recorded shortcut broke.
    @State private var rejection: NookRecordHotkeyProblem?
    @State private var recorder = AgentHotkeyRecorder()

    var body: some View {
        let lang = LanguageManager.shared
        let record = nook.record
        Section(lang.t("nook.record.settings.section")) {
            if !nook.isWidgetEnabled(.record) {
                Text(lang.t("nook.record.settings.off"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle(lang.t("nook.record.settings.includeIsland"), isOn: Binding(
                get: { record.options.includeIsland },
                set: { record.options.includeIsland = $0 }
            ))
            .settingsAnchor(SettingsIndex.entry("nook.record.includeIsland")!)
            Text(lang.t("nook.record.settings.includeIsland.note"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            shortcutRow(record.hotkey)
                .settingsAnchor(SettingsIndex.entry("nook.record.hotkey")!)
            Text(lang.t("nook.record.settings.hotkey.note"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(lang.t("nook.record.settings.openFolder")) { openFolder() }
                .settingsAnchor(SettingsIndex.entry("nook.record.openFolder")!)
            Text(lang.t("nook.record.settings.folder.note"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onDisappear(perform: stopRecording)
    }

    // MARK: Shortcut

    private func shortcutRow(_ hotkey: NookRecordHotkeyController) -> some View {
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
                .accessibilityLabel(lang.t("nook.record.settings.hotkey"))
                .accessibilityValue(hotkey.displayText)

                Button(lang.t("nook.record.settings.hotkey.reset")) {
                    stopRecording()
                    rejection = nil
                    hotkey.resetToDefault()
                }
                .disabled(hotkey.combo == NookRecordHotkeyRules.defaultCombo)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(lang.t("nook.record.settings.hotkey"))
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
    private func message(for hotkey: NookRecordHotkeyController) -> String? {
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
        nook.record.hotkey.beginRecording()
        recorder.start { event in
            handleRecordedKey(event)
        }
    }

    private func stopRecording() {
        guard isRecording || recorder.isRecording else { return }
        recorder.stop()
        isRecording = false
        nook.record.hotkey.endRecording()
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
        let problem = nook.record.hotkey.setCombo(combo)
        stopRecording()
        rejection = problem
    }

    // MARK: Files

    private func openFolder() {
        let folder = NookRecordFiles.folder()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
