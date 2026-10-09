import SwiftUI

/// Settings for the photo booth: what the strip looks like, how the
/// session is paced, and where strips are kept.
struct NookPhotoBoothSettings: View {
    var nook: NookModel

    private var lang: LanguageManager { .shared }

    var body: some View {
        @Bindable var booth = nook.photoBooth
        Section(lang.t("nook.photoBooth.settings.section")) {
            Picker(lang.t("nook.photoBooth.settings.layout"), selection: $booth.layoutKind) {
                ForEach(NookPhotoStripLayout.Kind.allCases) { kind in
                    Text(lang.t(kind.nameKey)).tag(kind)
                }
            }
            Picker(lang.t("nook.photoBooth.settings.theme"), selection: $booth.themeID) {
                ForEach(NookPhotoStripTheme.all) { theme in
                    Text(lang.t(theme.nameKey)).tag(theme.id)
                }
            }
            TextField(
                lang.t("nook.photoBooth.settings.caption"),
                text: $booth.caption,
                prompt: Text(lang.t(booth.theme.defaultCaptionKey))
            )
            Picker(lang.t("nook.photoBooth.settings.countdown"), selection: $booth.countdown) {
                ForEach(NookPhotoBoothPlan.countdownChoices, id: \.self) { seconds in
                    Text(lang.t("nook.photoBooth.settings.countdown.seconds", seconds)).tag(seconds)
                }
            }
            Toggle(lang.t("nook.photoBooth.settings.sound"), isOn: $booth.playsSound)
            LabeledContent(lang.t("nook.photoBooth.settings.folder")) {
                Text((booth.folderURL.path as NSString).abbreviatingWithTildeInPath)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack {
                Button(lang.t("nook.photoBooth.settings.folder.choose")) { booth.chooseFolder() }
                Button(lang.t("nook.photoBooth.settings.folder.default")) { booth.useDefaultFolder() }
                    .disabled(booth.folderPath == nil)
                Button(lang.t("nook.photoBooth.settings.folder.reveal")) { booth.revealFolder() }
            }
            Text(lang.t("nook.photoBooth.settings.note"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
