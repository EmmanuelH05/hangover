import AppKit
import SwiftUI

/// Settings for the volume notice and the optional takeover of the volume
/// and brightness keys. Renders inside the Nook settings `Form`.
struct NookVolumeSettings: View {
    var nook: NookModel

    @AppStorage(NookVolumeMonitor.noticeKey) private var showsNotice = true

    private static let accessibilitySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )

    private var lang: LanguageManager { .shared }

    var body: some View {
        let keys = nook.volume.keys
        Section(lang.t("nook.volume.settings.title")) {
            Toggle(lang.t("nook.volume.settings.notice"), isOn: $showsNotice)
            Button(lang.t("nook.volume.settings.test")) {
                nook.volume.showSample()
            }
            Toggle(lang.t("nook.volume.settings.keys"), isOn: Binding(
                get: { keys.status != .off },
                set: { keys.setEnabled($0) }
            ))
            Text(lang.t("nook.volume.settings.keys.note"))
                .font(.caption)
                .foregroundStyle(.secondary)
            switch keys.status {
            case .off, .active:
                EmptyView()
            case .waitingForAccess:
                LabeledContent(lang.t("nook.volume.settings.keys.waiting")) {
                    Button(lang.t("nook.volume.settings.keys.openSettings")) {
                        if let url = Self.accessibilitySettingsURL { NSWorkspace.shared.open(url) }
                    }
                }
            case .unavailable:
                Text(lang.t("nook.volume.settings.keys.unavailable"))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}
