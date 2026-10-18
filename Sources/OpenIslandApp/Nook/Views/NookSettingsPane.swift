import SwiftUI

struct NookSettingsPane: View {
    var model: AppModel
    /// Switches the settings window to the Personalization tab.
    var onOpenPersonalization: () -> Void = {}
    /// Changes each time the tab is asked to show its to-do section.
    var todoRequest: UUID?
    private var nook: NookModel { model.nook }

    /// The form lays its rows out a moment after the tab is shown.
    private static let scrollDelay: Duration = .milliseconds(250)

    var body: some View {
        ScrollViewReader { proxy in
            form
                .task(id: todoRequest) {
                    guard todoRequest != nil else { return }
                    try? await Task.sleep(for: Self.scrollDelay)
                    guard !Task.isCancelled else { return }
                    withAnimation { proxy.scrollTo(NookSettingsAnchor.todo, anchor: .top) }
                }
                .settingsScrollsToJump(proxy)
        }
    }

    /// A widget's switch with the anchor of its own entry. The ids are
    /// written out one by one so the index test can read them.
    @ViewBuilder
    private func widgetAnchored<Content: View>(_ kind: NookWidgetKind, _ content: Content) -> some View {
        switch kind {
        case .media: content.settingsAnchor(SettingsIndex.entry("nook.widget.media")!)
        case .calendar: content.settingsAnchor(SettingsIndex.entry("nook.widget.calendar")!)
        case .todo: content.settingsAnchor(SettingsIndex.entry("nook.widget.todo")!)
        case .notes: content.settingsAnchor(SettingsIndex.entry("nook.widget.notes")!)
        case .tray: content.settingsAnchor(SettingsIndex.entry("nook.widget.tray")!)
        case .timer: content.settingsAnchor(SettingsIndex.entry("nook.widget.timer")!)
        case .mirror: content.settingsAnchor(SettingsIndex.entry("nook.widget.mirror")!)
        case .weather: content.settingsAnchor(SettingsIndex.entry("nook.widget.weather")!)
        case .record: content.settingsAnchor(SettingsIndex.entry("nook.widget.record")!)
        case .design: content.settingsAnchor(SettingsIndex.entry("nook.widget.design")!)
        case .linkAudio: content.settingsAnchor(SettingsIndex.entry("nook.widget.linkAudio")!)
        }
    }

    private var form: some View {
        @Bindable var nook = nook
        return Form {
            Section("Widgets") {
                ForEach(NookWidgetKind.offered) { kind in
                    widgetAnchored(kind, Toggle(isOn: Binding(
                        get: { nook.isWidgetEnabled(kind) },
                        set: { isOn in
                            nook.setWidgetFromSettings(kind, enabled: isOn)
                        }
                    )) {
                        Label(kind.title, systemImage: kind.systemImage)
                    })
                }
                Text(LanguageManager.shared.t("settings.nook.arrange.note"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .settingsAnchor(SettingsIndex.entry("nook.arrange")!)
            }

            // Every row here is about agents, the link to the per-display
            // rows included.
            if model.agentsEnabled {
                Section("Working with the agents") {
                    LabeledContent(LanguageManager.shared.t("settings.nook.perDisplay.title")) {
                        Button("Open Personalization…", action: onOpenPersonalization)
                    }
                    .settingsAnchor(SettingsIndex.entry("nook.perDisplay")!)
                    Text(LanguageManager.shared.t("settings.nook.perDisplay.note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle(LanguageManager.shared.t("settings.nook.focusSuppresses.title"), isOn: $nook.focusSuppressesCompletions)
                        .settingsAnchor(SettingsIndex.entry("nook.focusSuppressesCompletions")!)
                    Toggle(LanguageManager.shared.t("settings.nook.meetingSuppresses.title"), isOn: $nook.meetingSuppressesCompletions)
                        .settingsAnchor(SettingsIndex.entry("nook.meetingSuppressesCompletions")!)
                    Text(LanguageManager.shared.t("settings.nook.meetingSuppresses.note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Now playing in the notch") {
                LabeledContent("Player") {
                    Text(nook.nowPlaying.map { "\($0.title) · \($0.bundleIdentifier)" } ?? (nook.media.isAvailable ? "Nothing playing" : (nook.media.lastError ?? "Starting…")))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                LabeledContent("GIF") {
                    Text(nook.gifURL?.lastPathComponent ?? "None (bar visualizer)")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack {
                    Button(LanguageManager.shared.t("settings.nook.gif.choose")) { nook.chooseGIF() }
                        .settingsAnchor(SettingsIndex.entry("nook.nowPlaying.gif")!)
                    Button(LanguageManager.shared.t("settings.nook.gif.visualizer")) { nook.clearGIF() }
                        .disabled(nook.gifURL == nil)
                        .settingsAnchor(SettingsIndex.entry("nook.nowPlaying.visualizer")!)
                }
                Slider(value: $nook.gifScale, in: 0.5...2.5, step: 0.05) {
                    Text("\(LanguageManager.shared.t("settings.nook.gif.scale")) \(nook.gifScale, format: .number.precision(.fractionLength(2)))")
                }
                .settingsAnchor(SettingsIndex.entry("nook.nowPlaying.scale")!)
                Slider(value: $nook.gifOffsetX, in: -40...40, step: 1) {
                    Text("\(LanguageManager.shared.t("settings.nook.gif.offsetX")) \(Int(nook.gifOffsetX))")
                }
                .settingsAnchor(SettingsIndex.entry("nook.nowPlaying.offsetX")!)
                Slider(value: $nook.gifOffsetY, in: -20...20, step: 1) {
                    Text("\(LanguageManager.shared.t("settings.nook.gif.offsetY")) \(Int(nook.gifOffsetY))")
                }
                .settingsAnchor(SettingsIndex.entry("nook.nowPlaying.offsetY")!)
            }

            NookCalendarSettings(nook: nook)
            NookTodoSettings(nook: nook)
            NookNotesSettings(nook: nook)
            NookTraySettings(nook: nook)
            NookTimerSettings(nook: nook)
            NookMirrorSettings(nook: nook)
            NookPhotoBoothSettings(nook: nook)
            NookWeatherSettings(nook: nook)
            NookDesignSettings(nook: nook)
            NookRecordSettings(nook: nook)
            if nook.offersLinkAudio { NookLinkAudioSettings(nook: nook) }
            NookPowerSettings(nook: nook)
            NookVolumeSettings(nook: nook)
        }
        .formStyle(.grouped)
    }
}
