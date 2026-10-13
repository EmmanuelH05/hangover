import SwiftUI

/// Settings section for Link to MP3: where the files go, which programs
/// were found and where, and a word about what to save. The widget has no
/// switches of its own: it is one switch under Widgets.
struct NookLinkAudioSettings: View {
    var nook: NookModel

    var body: some View {
        let lang = LanguageManager.shared
        let service = nook.linkAudio
        Section(lang.t("nook.linkAudio.settings.section")) {
            if !nook.isWidgetEnabled(.linkAudio) {
                Text(lang.t("nook.linkAudio.settings.off"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LabeledContent(lang.t("nook.linkAudio.settings.folder")) {
                HStack(spacing: 10) {
                    Text((service.folder.path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Button(lang.t("nook.linkAudio.settings.chooseFolder")) {
                        NookLinkAudioFolderPicker.choose(for: nook)
                    }
                }
            }
            if let reason = service.folderProblem {
                Text(lang.t(reason.messageKey))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Looked for again each time the section is shown, which picks up
            // a brew install made while the app was open.
            ForEach(NookLinkAudioToolName.allCases, id: \.self) { name in
                LabeledContent(name.rawValue) {
                    Text(service.toolStatus.path(of: name)?.path ?? lang.t("nook.linkAudio.settings.notFound"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            if let key = service.toolStatus.missingLineKey {
                Text(lang.t(key))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(lang.t("nook.linkAudio.settings.caption"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { service.refreshTools() }
    }
}
