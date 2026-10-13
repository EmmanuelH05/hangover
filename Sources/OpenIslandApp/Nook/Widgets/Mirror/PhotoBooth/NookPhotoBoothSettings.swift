import SwiftUI

/// Settings for the photo booth: what the strip looks like, how the
/// session is paced, and where strips are kept.
struct NookPhotoBoothSettings: View {
    var nook: NookModel
    private let previews: NookPhotoBoothPreviews

    /// The caption the previews are drawn with. It trails the field by
    /// `NookPhotoBoothPreviews.captionPause`, which keeps a preview from
    /// being drawn again on every key. Until the section first appears it is
    /// nil and the field's own text stands in. It is not read when the view is
    /// made, which would make the form that holds this section follow every key.
    @State private var settledCaption: String?
    @Namespace private var ringNamespace

    private var lang: LanguageManager { .shared }

    private static let tileSpacing: CGFloat = 8

    init(nook: NookModel, previews: NookPhotoBoothPreviews = .shared) {
        self.nook = nook
        self.previews = previews
    }

    var body: some View {
        @Bindable var booth = nook.photoBooth
        let typed = booth.caption
        Section(lang.t("nook.photoBooth.settings.section")) {
            layoutChoices(booth)
            themeChoices(booth)
            TextField(
                lang.t("nook.photoBooth.settings.caption"),
                text: $booth.caption,
                prompt: Text(lang.t(booth.theme.defaultCaptionKey))
            )
            .onAppear {
                if settledCaption == nil { settledCaption = nook.photoBooth.caption }
            }
            .task(id: typed) {
                if let settled = await NookPhotoBoothPreviews.settled(typed) {
                    settledCaption = settled
                }
            }
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

    // MARK: Choices

    /// One tile per layout, each a picture of that layout's strip in the
    /// theme chosen now.
    private func layoutChoices(_ booth: NookPhotoBoothModel) -> some View {
        let set = previewSet(booth)
        let wanted = set.keys
        return VStack(alignment: .leading, spacing: Self.tileSpacing) {
            Text(lang.t("nook.photoBooth.settings.layout"))
            HStack(spacing: Self.tileSpacing) {
                ForEach(NookPhotoStripLayout.Kind.allCases) { kind in
                    NookPhotoBoothTile(
                        choice: .layout(kind, chosen: booth.layoutKind, name: lang.t(kind.nameKey)),
                        pictureKind: kind,
                        picture: previews.image(for: set.layoutTile(kind)),
                        nameLines: 1,
                        ringNamespace: ringNamespace,
                        ringGroup: "layout",
                        select: { Self.choose(kind, on: booth) }
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(lang.t("nook.photoBooth.settings.layout"))
        // Draws what the tiles of both groups show. It runs again, and
        // draws only what is new, when the layout, the theme, the settled
        // caption or the language changes.
        .task(id: wanted) { await previews.request(wanted) }
    }

    /// One tile per theme in a grid that wraps, each a picture of that
    /// theme's strip in the layout chosen now.
    private func themeChoices(_ booth: NookPhotoBoothModel) -> some View {
        let set = previewSet(booth)
        return VStack(alignment: .leading, spacing: Self.tileSpacing) {
            Text(lang.t("nook.photoBooth.settings.theme"))
            NookPhotoBoothTileFlow(
                minimumWidth: NookPhotoBoothTile.minimumWidth(showing: booth.layoutKind),
                spacing: Self.tileSpacing
            ) {
                ForEach(NookPhotoStripTheme.all) { theme in
                    NookPhotoBoothTile(
                        choice: .theme(theme, chosen: booth.themeID, name: lang.t(theme.nameKey)),
                        pictureKind: booth.layoutKind,
                        picture: previews.image(for: set.themeTile(theme)),
                        nameLines: 2,
                        ringNamespace: ringNamespace,
                        ringGroup: "theme",
                        select: { Self.choose(theme, on: booth) }
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(lang.t("nook.photoBooth.settings.theme"))
    }

    // MARK: Choosing

    /// What a layout tile's button does.
    static func choose(_ kind: NookPhotoStripLayout.Kind, on booth: NookPhotoBoothModel) {
        booth.layoutKind = kind
    }

    /// What a theme tile's button does.
    static func choose(_ theme: NookPhotoStripTheme, on booth: NookPhotoBoothModel) {
        booth.themeID = theme.id
    }

    // MARK: Previews

    private func previewSet(_ booth: NookPhotoBoothModel) -> NookPhotoBoothPreviewSet {
        Self.previewSet(for: booth, settledCaption: settledCaption)
    }

    /// The previews on screen for the booth's choices. They follow the
    /// settled caption and not the field's text, which moves with every key.
    /// With no settled caption yet, the field's text is the one.
    static func previewSet(for booth: NookPhotoBoothModel, settledCaption: String?) -> NookPhotoBoothPreviewSet {
        NookPhotoBoothPreviewSet(
            layout: booth.layoutKind,
            theme: booth.theme,
            typedCaption: settledCaption ?? booth.caption,
            defaultLine: booth.defaultCaption
        )
    }
}
