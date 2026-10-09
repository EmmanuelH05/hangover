import SwiftUI

/// Settings for the Mirror widget: which camera to show.
struct NookMirrorSettings: View {
    var nook: NookModel

    @State private var devices: [NookMirrorDevices.Option] = []
    @AppStorage(NookMirrorDevices.deviceIDKey) private var deviceID: String = ""

    var body: some View {
        Section("Mirror") {
            Picker("Camera", selection: $deviceID) {
                Text("Default").tag("")
                ForEach(devices) { device in
                    Text(device.name).tag(device.id)
                }
            }
            NookRingLightTintRow()
            Text("The camera stays off until you click the Mirror widget. The mirror then shows above your widgets and holds the island open until you turn it off or close the island. The bulb on the mirror lights the edge of your screen like a vanity mirror.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(LanguageManager.shared.t("nook.mirror.decorations.settings.clear"), role: .destructive) {
                nook.clearMirrorDecorations()
            }
            .disabled(nook.mirrorDecorations.isEmpty)
        }
        .onAppear { devices = NookMirrorDevices.available() }
    }
}
