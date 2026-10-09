import SwiftUI

/// Settings for the battery and headphones notices. Renders inside the
/// Nook settings `Form`.
struct NookPowerSettings: View {
    var nook: NookModel

    @AppStorage(NookPowerMonitor.enabledKey) private var enabled = true

    var body: some View {
        Section("Battery and headphones") {
            Toggle("Show charger and headphone notices", isOn: $enabled)
            Button("Test notice") {
                nook.showTransient(symbol: "bolt.fill", text: "Charging · 78%", tint: .green, level: 78)
            }
        }
    }
}
