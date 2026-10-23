import SwiftUI

/// Settings section for the file tray and its clipboard history.
struct NookTraySettings: View {
    var nook: NookModel

    var body: some View {
        let lang = LanguageManager.shared
        let clipboard = nook.tray.clipboard
        Section(lang.t("nook.tray.settings.section")) {
            LabeledContent(lang.t("nook.tray.settings.count"), value: "\(nook.tray.items.count)")
            Picker(lang.t("nook.tray.settings.overflow"), selection: Binding(
                get: { nook.tray.overflow },
                set: { nook.tray.overflow = $0 }
            )) {
                ForEach(NookTrayOverflow.allCases) { option in
                    Text(lang.t(option.titleKey)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .settingsAnchor(SettingsIndex.entry("nook.tray.overflow")!)
            Text(lang.t("nook.tray.settings.overflow.note"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(lang.t("nook.tray.settings.revealFolder")) { nook.tray.revealFolder() }
                .settingsAnchor(SettingsIndex.entry("nook.tray.revealFolder")!)
            Button(lang.t("nook.tray.settings.clear"), role: .destructive) { nook.tray.clear() }
                .disabled(nook.tray.items.isEmpty)
                .settingsAnchor(SettingsIndex.entry("nook.tray.clear")!)

            Toggle(lang.t("nook.tray.settings.clipboard"), isOn: Binding(
                get: { clipboard.isEnabled },
                set: { clipboard.setEnabled($0) }
            ))
            .settingsAnchor(SettingsIndex.entry("nook.tray.clipboard")!)
            Text(lang.t("nook.tray.settings.clipboard.note"))
                .font(.caption)
                .foregroundStyle(.secondary)
            if clipboard.isEnabled {
                if clipboard.access != .allowed {
                    Text(lang.t(clipboard.access == .denied ? "nook.tray.clipboard.denied" : "nook.tray.clipboard.asks"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button(lang.t("nook.tray.clipboard.openSettings")) { nook.tray.openPasteSettings() }
                }
                LabeledContent(
                    lang.t("nook.tray.settings.clipboard.count"),
                    value: "\(clipboard.history.entries.count)"
                )
                Button(lang.t("nook.tray.settings.clipboard.clear"), role: .destructive) { clipboard.clear() }
                    .disabled(clipboard.history.entries.isEmpty)
            }
        }
    }
}
