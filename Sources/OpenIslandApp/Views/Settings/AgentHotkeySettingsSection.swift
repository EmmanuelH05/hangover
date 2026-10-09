import AppKit
import SwiftUI

/// Listens for the next key press in the Settings window while a shortcut
/// is being recorded. A local monitor: it sees keys typed in this app only
/// and needs no permission.
@MainActor
final class AgentHotkeyRecorder {
    nonisolated(unsafe) private var token: Any?
    private var onKey: @MainActor (NSEvent) -> Void = { _ in }

    var isRecording: Bool { token != nil }

    func start(onKey: @escaping @MainActor (NSEvent) -> Void) {
        self.onKey = onKey
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.onKey(event)
            // The press belongs to the recorder, not to the window under it.
            return nil
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }

    deinit {
        if let token { NSEvent.removeMonitor(token) }
    }
}

/// Settings → General → Agent shortcuts: the keys that approve or deny the
/// waiting agent from any app.
struct AgentHotkeySettingsSection: View {
    var hotkeys: AgentHotkeyController
    var lang: LanguageManager

    @State private var recordingAction: AgentHotkeyAction?
    /// The rule the last recorded shortcut broke, and for which row.
    @State private var rejectedAction: AgentHotkeyAction?
    @State private var rejection: AgentHotkeyProblem?
    @State private var recorder = AgentHotkeyRecorder()

    var body: some View {
        Section(lang.t("settings.general.agentHotkeys")) {
            ForEach(AgentHotkeyAction.allCases) { action in
                row(for: action)
            }

            Text(lang.t("settings.general.agentHotkeys.note"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(lang.t("settings.general.agentHotkeys.reset")) {
                stopRecording()
                rejectedAction = nil
                rejection = nil
                hotkeys.resetToDefaults()
            }
            .disabled(hotkeys.settings == AgentHotkeySettings())
        }
        .onDisappear(perform: stopRecording)
    }

    private func row(for action: AgentHotkeyAction) -> some View {
        LabeledContent {
            HStack(spacing: 10) {
                Button {
                    recordingAction == action ? stopRecording() : startRecording(action)
                } label: {
                    Text(recordingAction == action
                        ? lang.t("settings.general.agentHotkeys.recording")
                        : hotkeys.displayText(for: action))
                        .font(.system(.body, design: .monospaced))
                        .frame(minWidth: 64)
                }
                .disabled(!hotkeys.isEnabled(action))
                .help(lang.t("settings.general.agentHotkeys.change"))

                Toggle(lang.t(action.titleKey), isOn: Binding(
                    get: { hotkeys.isEnabled(action) },
                    set: { isEnabled in
                        if recordingAction == action { stopRecording() }
                        hotkeys.setEnabled(isEnabled, for: action)
                    }
                ))
                .labelsHidden()
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(lang.t(action.titleKey))
                if let message = message(for: action) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// What is wrong with a row's shortcut, if anything: the rule the last
    /// recording broke first, what macOS said otherwise.
    private func message(for action: AgentHotkeyAction) -> String? {
        if rejectedAction == action, let rejection {
            return lang.t(rejection.messageKey)
        }
        switch hotkeys.statuses[action] {
        case let .failed(code)?:
            return lang.t("settings.general.agentHotkeys.status.failed", Int(code))
        case .usedBySystem?:
            return lang.t("settings.general.agentHotkeys.status.usedBySystem")
        case let .invalid(problem)?:
            return lang.t(problem.messageKey)
        case .off?, .inactive?, .ready?, nil:
            return nil
        }
    }

    private func startRecording(_ action: AgentHotkeyAction) {
        rejectedAction = nil
        rejection = nil
        recordingAction = action
        hotkeys.beginRecording()
        recorder.start { event in
            handleRecordedKey(event, for: action)
        }
    }

    private func stopRecording() {
        guard recordingAction != nil || recorder.isRecording else { return }
        recorder.stop()
        recordingAction = nil
        hotkeys.endRecording()
    }

    private func handleRecordedKey(_ event: NSEvent, for action: AgentHotkeyAction) {
        let modifiers = AgentHotkeyModifiers(eventFlags: event.modifierFlags)
        // Escape on its own gives up and keeps the old shortcut.
        if event.keyCode == AgentHotkeyKeyboard.escape, modifiers.isEmpty {
            stopRecording()
            return
        }

        let combo = AgentHotkeyCombo(keyCode: event.keyCode, modifiers: modifiers)
        // The controller checks the shortcut before it lets go of the old one.
        let problem = hotkeys.setCombo(combo, for: action)
        stopRecording()
        rejectedAction = problem == nil ? nil : action
        rejection = problem
    }
}
