import SwiftUI

struct NookSettingsPane: View {
    var model: AppModel
    /// Switches the settings window to the Personalization tab.
    var onOpenPersonalization: () -> Void = {}
    private var nook: NookModel { model.nook }

    var body: some View {
        @Bindable var nook = nook
        Form {
            Section("Widgets") {
                ForEach(NookWidgetKind.allCases) { kind in
                    Toggle(isOn: Binding(
                        get: { nook.isWidgetEnabled(kind) },
                        set: { isOn in
                            nook.setWidget(kind, enabled: isOn)
                            // Turning the calendar or the to-do widget on
                            // is when macOS is asked for its permission.
                            if isOn { nook.widgetTurnedOn(kind) }
                        }
                    )) {
                        Label(kind.title, systemImage: kind.systemImage)
                    }
                }
                Text("To arrange widgets, open the island and right-click a widget or press and hold it. Drag widgets to reorder them, drag the corner grip to resize, and use Done when you are finished. Each display keeps its own layout.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Every row here is about agents, the link to the per-display
            // rows included.
            if model.agentsEnabled {
                Section("Working with the agents") {
                    LabeledContent("Per-display options") {
                        Button("Open Personalization…", action: onOpenPersonalization)
                    }
                    Text("What the closed island shows while music plays, which page opens first, and the rows that link the agents and the Nook are set per display, for the MacBook notch and for external displays, in Personalization.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Focus timer silences completion pop-ups", isOn: $nook.focusSuppressesCompletions)
                    Toggle("Meetings silence completion pop-ups", isOn: $nook.meetingSuppressesCompletions)
                    Text("A meeting is a calendar event with a video link that is on right now. Permission requests and questions still come through during a focus session or a meeting. The timer's end sound follows the island's mute switch.")
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
                    Button("Choose GIF…") { nook.chooseGIF() }
                    Button("Use visualizer") { nook.clearGIF() }
                        .disabled(nook.gifURL == nil)
                }
                Slider(value: $nook.gifScale, in: 0.5...2.5, step: 0.05) {
                    Text("Scale \(nook.gifScale, format: .number.precision(.fractionLength(2)))")
                }
                Slider(value: $nook.gifOffsetX, in: -40...40, step: 1) {
                    Text("Horizontal offset \(Int(nook.gifOffsetX))")
                }
                Slider(value: $nook.gifOffsetY, in: -20...20, step: 1) {
                    Text("Vertical offset \(Int(nook.gifOffsetY))")
                }
            }

            NookCalendarSettings(nook: nook)
            NookTodoSettings(nook: nook)
            NookNotesSettings(nook: nook)
            NookTraySettings(nook: nook)
            NookTimerSettings(nook: nook)
            NookMirrorSettings(nook: nook)
            NookPhotoBoothSettings(nook: nook)
            NookWeatherSettings(nook: nook)
            NookPowerSettings(nook: nook)
            NookVolumeSettings(nook: nook)
        }
        .formStyle(.grouped)
    }
}
