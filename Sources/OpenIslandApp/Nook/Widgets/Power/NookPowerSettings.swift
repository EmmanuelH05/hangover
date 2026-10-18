import SwiftUI

/// Settings for the battery and headphones notices. Renders inside the
/// Nook settings `Form`.
struct NookPowerSettings: View {
    var nook: NookModel

    @AppStorage(NookPowerMonitor.enabledKey) private var enabled = true

    var body: some View {
        Section("Battery and headphones") {
            Toggle(LanguageManager.shared.t("nook.power.settings.notices"), isOn: $enabled)
                .settingsAnchor(SettingsIndex.entry("nook.power.notices")!)
            Button(LanguageManager.shared.t("nook.power.settings.test")) {
                nook.showTransient(symbol: "bolt.fill", text: "Charging · 78%", tint: .green, level: 78)
            }
            .settingsAnchor(SettingsIndex.entry("nook.power.test")!)
        }
    }
}
