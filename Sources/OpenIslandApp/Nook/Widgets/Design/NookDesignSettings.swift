import AppKit
import SwiftUI

/// Settings section for the designer kit: how colors are copied, what a
/// pick does, the eyedropper's shortcut and where the files are. The tabs
/// of the card have no switches of their own: the widget is one switch.
struct NookDesignSettings: View {
    var nook: NookModel

    @State private var isRecording = false
    /// The sentence for the rule the last recorded shortcut broke.
    @State private var rejectionKey: String?
    @State private var recorder = AgentHotkeyRecorder()
    /// "Remove every reference picture" asks twice.
    @State private var clearAsk = NookDesignTwoStepAsk()

    var body: some View {
        let lang = LanguageManager.shared
        let kit = nook.design
        let isOn = nook.isWidgetEnabled(.design)
        Section(lang.t("nook.design.settings.section")) {
            if !isOn {
                Text(lang.t("nook.design.settings.off"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker(lang.t("nook.design.settings.format"), selection: Binding(
                get: { kit.copyFormat },
                set: { kit.copyFormat = $0 }
            )) {
                ForEach(NookDesignColorFormat.allCases) { format in
                    Text(lang.t(format.titleKey)).tag(format)
                }
            }
            .settingsAnchor(SettingsIndex.entry("nook.design.format")!)

            Toggle(lang.t("nook.design.settings.savePicks"), isOn: Binding(
                get: { kit.savesPicksToPalette },
                set: { kit.savesPicksToPalette = $0 }
            ))
            .settingsAnchor(SettingsIndex.entry("nook.design.savePicks")!)
            Text(lang.t("nook.design.settings.savePicks.note"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(lang.t("nook.design.settings.keepPicking"), isOn: Binding(
                get: { kit.keepsPicking },
                set: { kit.keepsPicking = $0 }
            ))
            .settingsAnchor(SettingsIndex.entry("nook.design.keepPicking")!)
            Text(lang.t("nook.design.settings.keepPicking.note"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            shortcutRow(kit.hotkey)
                .settingsAnchor(SettingsIndex.entry("nook.design.hotkey")!)
            Text(lang.t("nook.design.settings.hotkey.note"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // The shelves are read only while the widget is on. A count of
            // zero for a shelf that was never read would be a lie.
            if isOn {
                LabeledContent(lang.t("nook.design.settings.colors"), value: "\(kit.palettes.colorCount)")
                LabeledContent(lang.t("nook.design.settings.links"), value: "\(kit.links.links.count)")
                LabeledContent(lang.t("nook.design.settings.references"), value: "\(kit.references.items.count)")
            }
            // One caption for each shelf that has trouble, not only the first.
            ForEach(kit.storeProblems) { problem in
                Text(problem.settingsLine())
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(lang.t("nook.design.settings.openEditor")) { kit.showPaletteEditor() }
                .disabled(!isOn)
                .settingsAnchor(SettingsIndex.entry("nook.design.openEditor")!)
            Button(lang.t("nook.design.settings.revealFolder")) { revealFolder(kit) }
                .settingsAnchor(SettingsIndex.entry("nook.design.revealFolder")!)
            HStack {
                Button(
                    clearAsk.isAsking
                        ? lang.t("nook.design.settings.clearReferences.confirm", kit.references.items.count)
                        : lang.t("nook.design.settings.clearReferences"),
                    role: .destructive
                ) {
                    if clearAsk.press() { kit.clearReferences() }
                }
                .disabled(kit.references.items.isEmpty)
                if clearAsk.isAsking {
                    Button(lang.t("nook.design.settings.clearReferences.cancel")) { clearAsk.cancel() }
                }
            }
            // The question does not outlast the pictures it asked about.
            .onChange(of: kit.references.items.isEmpty) { _, isEmpty in if isEmpty { clearAsk.cancel() } }
            .settingsAnchor(SettingsIndex.entry("nook.design.clearReferences")!)
            Text(lang.t("nook.design.settings.local"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onDisappear(perform: stopRecording)
    }

    // MARK: Shortcut

    private func shortcutRow(_ hotkey: NookDesignHotkeyController) -> some View {
        let lang = LanguageManager.shared
        return LabeledContent {
            HStack(spacing: 10) {
                Button {
                    isRecording ? stopRecording() : startRecording()
                } label: {
                    Text(isRecording
                        ? lang.t("settings.general.agentHotkeys.recording")
                        : hotkey.displayText ?? lang.t("nook.design.settings.hotkey.none"))
                        .font(.system(.body, design: .monospaced))
                        .frame(minWidth: 64)
                }
                .help(lang.t("settings.general.agentHotkeys.change"))
                .accessibilityLabel(lang.t("nook.design.settings.hotkey"))
                .accessibilityValue(hotkey.displayText ?? lang.t("nook.design.settings.hotkey.none"))

                Button(lang.t("nook.design.settings.hotkey.clear")) {
                    stopRecording()
                    rejectionKey = nil
                    hotkey.clear()
                }
                .disabled(hotkey.combo == nil)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(lang.t("nook.design.settings.hotkey"))
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
    private func message(for hotkey: NookDesignHotkeyController) -> String? {
        let lang = LanguageManager.shared
        if let rejectionKey { return lang.t(rejectionKey) }
        switch hotkey.status {
        case let .failed(code):
            return lang.t("settings.general.agentHotkeys.status.failed", Int(code))
        case .usedBySystem:
            return lang.t("settings.general.agentHotkeys.status.usedBySystem")
        case let .invalid(problem):
            return lang.t(nook.design.problemMessageKey(problem, combo: hotkey.combo))
        case .none, .inactive, .ready:
            return nil
        }
    }

    private func startRecording() {
        rejectionKey = nil
        isRecording = true
        nook.design.hotkey.beginRecording()
        recorder.start { event in
            handleRecordedKey(event)
        }
    }

    private func stopRecording() {
        guard isRecording || recorder.isRecording else { return }
        recorder.stop()
        isRecording = false
        nook.design.hotkey.endRecording()
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
        let problem = nook.design.hotkey.setCombo(combo)
        stopRecording()
        rejectionKey = problem.map { nook.design.problemMessageKey($0, combo: combo) }
    }

    // MARK: Files

    private func revealFolder(_ kit: NookDesignKit) {
        let folder = kit.palettes.folderURL
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
