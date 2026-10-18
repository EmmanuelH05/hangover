import SwiftUI

/// Settings for the Mirror widget: which camera to show.
struct NookMirrorSettings: View {
    var nook: NookModel

    @State private var devices: [NookMirrorDevices.Option] = []
    @AppStorage(NookMirrorDevices.deviceIDKey) private var deviceID: String = ""

    var body: some View {
        Section("Mirror") {
            Picker(LanguageManager.shared.t("nook.mirror.settings.camera"), selection: $deviceID) {
                Text("Default").tag("")
                ForEach(devices) { device in
                    Text(device.name).tag(device.id)
                }
            }
            .settingsAnchor(SettingsIndex.entry("nook.mirror.camera")!)
            NookRingLightTintRow()
            Text(LanguageManager.shared.t("nook.mirror.settings.note"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(LanguageManager.shared.t("nook.mirror.decorations.settings.clear"), role: .destructive) {
                nook.clearMirrorDecorations()
            }
            .disabled(nook.mirrorDecorations.isEmpty)
            .settingsAnchor(SettingsIndex.entry("nook.mirror.clearDecorations")!)
        }
        .onAppear { devices = NookMirrorDevices.available() }
    }
}
