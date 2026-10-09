import SwiftUI

/// The template gallery at the top of the Personalization tab, for the
/// display being edited. It reads the model in a body of its own, which
/// keeps the pane from re-running when a Nook choice changes which template
/// is on.
struct TemplatesSection: View {
    var model: AppModel
    let profile: IslandAppearanceDisplayProfile
    let ringNamespace: Namespace.ID

    /// The gallery is tall. It can be folded away once a setup is chosen.
    @AppStorage("settings.appearance.templates.collapsed") private var isCollapsed = false
    /// The template the preview stage is showing, not applied.
    @State private var previewed: PersonalizationTemplate?

    var body: some View {
        gallery
            .sheet(item: $previewed) { template in
                PreviewStageSheet(
                    title: TemplateText(template.id, lang: model.lang).title,
                    setup: model.templateSetup(template, for: profile),
                    profile: profile,
                    enabledWidgets: model.nook.enabledWidgets,
                    lang: model.lang,
                    primaryTitle: model.appliedTemplateID(for: profile) == template.id
                        ? nil
                        : model.lang.t("settings.appearance.stage.useTemplate"),
                    onPrimary: {
                        previewed = nil
                        withMotion(Motion.morph) { model.applyTemplate(template, for: profile) }
                    },
                    onClose: { previewed = nil }
                )
            }
    }

    private var gallery: some View {
        TemplateGallery(
            lang: model.lang,
            applied: model.appliedTemplateID(for: profile),
            switchedOff: model.templateWidgetsSwitchedOff(for: profile),
            canUndo: model.canUndoTemplate(for: profile),
            isCollapsed: $isCollapsed,
            ringNamespace: ringNamespace,
            // The whole tab changes with a template. It morphs the way a
            // display switch does.
            apply: { template in withMotion(Motion.morph) { model.applyTemplate(template, for: profile) } },
            undo: { withMotion(Motion.morph) { model.undoTemplate(for: profile) } },
            preview: { previewed = $0 }
        )
    }
}

/// One card per `PersonalizationTemplate` with a thumbnail of its look, who
/// it suits and what it changes. A click applies the template, and the link
/// under the list puts the earlier setup back.
struct TemplateGallery: View {
    let lang: LanguageManager
    /// The template the display is on, if any.
    let applied: PersonalizationTemplate.ID?
    /// Widgets of the applied template that are off in the Nook tab.
    var switchedOff: [NookWidgetKind] = []
    let canUndo: Bool
    @Binding var isCollapsed: Bool
    let ringNamespace: Namespace.ID
    let apply: (PersonalizationTemplate) -> Void
    let undo: () -> Void
    /// Opens the preview stage for a template. Nil leaves the control out.
    var preview: ((PersonalizationTemplate) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !isCollapsed {
                cards
                    .transition(Motion.transition(.opacity, reduceMotion: reduceMotion))

                if canUndo {
                    Button(action: undo) {
                        Label(lang.t("settings.appearance.templates.undo"), systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .transition(Motion.transition(.opacity, reduceMotion: reduceMotion))
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            PersonalizationSectionHeader(title: lang.t("settings.appearance.templates.title"), note: note)
            Spacer(minLength: 8)
            Button {
                withMotion(Motion.reflow) { isCollapsed.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(lang.t(isCollapsed ? "settings.appearance.templates.show" : "settings.appearance.templates.hide"))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isCollapsed ? 0 : 180))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.55))
            .fixedSize()
        }
    }

    /// Folded away, the header still says which template the display is on.
    private var note: String {
        if isCollapsed, let applied {
            return lang.t("settings.appearance.templates.current", TemplateText(applied, lang: lang).title)
        }
        return lang.t("settings.appearance.templates.note")
    }

    /// Says which of the applied template's widgets are left out, because a
    /// template never switches a widget on in the Nook tab.
    private var switchedOffNote: String? {
        guard !switchedOff.isEmpty else { return nil }
        return lang.t("settings.appearance.templates.switchedOff", switchedOff.map(\.title).joined(separator: ", "))
    }

    /// The panel card's own padding. The preview control is placed from it.
    private static let cardPadding: CGFloat = 12

    private var previewTitle: String { lang.t("settings.appearance.stage.preview") }

    private var cards: some View {
        VStack(spacing: 8) {
            ForEach(PersonalizationTemplate.all) { template in
                let text = TemplateText(template.id, lang: lang)
                PersonalizationCard(
                    title: text.spokenSummary,
                    selected: applied == template.id,
                    style: .panel,
                    ringNamespace: ringNamespace,
                    ringGroup: "template",
                    action: { apply(template) }
                ) {
                    TemplateRow(
                        template: template,
                        text: text,
                        isApplied: applied == template.id,
                        appliedTitle: lang.t("settings.appearance.templates.applied"),
                        switchedOffNote: applied == template.id ? switchedOffNote : nil,
                        previewTitle: preview == nil ? nil : previewTitle
                    )
                }
                // A sibling above the card, not inside its label: a click
                // here opens the preview and never applies the template. It
                // lands on the room the row keeps under the thumbnail.
                .overlay(alignment: .topLeading) {
                    if let preview {
                        Button {
                            preview(template)
                        } label: {
                            TemplatePreviewControl.label(previewTitle)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .padding(.leading, Self.cardPadding)
                        .padding(.top, Self.cardPadding + TemplateThumbnail.size.height + TemplatePreviewControl.gap)
                        .accessibilityLabel("\(previewTitle): \(text.title)")
                    }
                }
            }
        }
    }
}

/// A template's words in the current language. The keys are
/// `settings.appearance.templates.<id>.title`, `.bestFor` and `.point1` to
/// `.point3`.
struct TemplateText: Equatable, Sendable {
    static let pointCount = 3

    let title: String
    let bestFor: String
    let points: [String]

    init(_ id: PersonalizationTemplate.ID, lang: LanguageManager) {
        let keys = Self.keys(for: id)
        title = lang.t(keys.title)
        bestFor = lang.t(keys.bestFor)
        points = keys.points.map { lang.t($0) }
    }

    static func keys(for id: PersonalizationTemplate.ID) -> (title: String, bestFor: String, points: [String]) {
        let base = "settings.appearance.templates.\(id.rawValue)"
        return ("\(base).title", "\(base).bestFor", (1...pointCount).map { "\(base).point\($0)" })
    }

    /// Everything on the card as one sentence run, for VoiceOver.
    var spokenSummary: String {
        ([title, bestFor] + points).joined(separator: ". ")
    }
}

/// One template card's content: the thumbnail, then the name, who it suits
/// and what it changes.
private struct TemplateRow: View {
    let template: PersonalizationTemplate
    let text: TemplateText
    let isApplied: Bool
    let appliedTitle: String
    /// Shown under the points while a widget of this template is off.
    var switchedOffNote: String?
    /// Keeps room under the thumbnail for the gallery's preview control,
    /// which sits above the card. Nil keeps none.
    var previewTitle: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: TemplatePreviewControl.gap) {
                TemplateThumbnail(template: template)
                if previewTitle != nil {
                    Color.clear
                        .frame(width: TemplateThumbnail.size.width, height: TemplatePreviewControl.height)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: template.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(V6Palette.paper.opacity(0.6))
                        .frame(width: 14)
                    Text(text.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(V6Palette.paper.opacity(0.94))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if isApplied {
                        Label(appliedTitle, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(V6Palette.paper.opacity(0.9))
                            .fixedSize()
                            .transition(Motion.transition(.scale.combined(with: .opacity), reduceMotion: reduceMotion))
                    }
                }

                Text(text.bestFor)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(V6Palette.paper.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(text.points, id: \.self) { point in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•")
                                .foregroundStyle(V6Palette.paper.opacity(0.3))
                            Text(point)
                                .foregroundStyle(V6Palette.paper.opacity(0.42))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.system(size: 11))
                    }
                }

                if let switchedOffNote {
                    Label(switchedOffNote, systemImage: "exclamationmark.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.orange.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .motionAnimation(Motion.selection, value: isApplied)
    }
}

/// The control under a card's thumbnail that opens the preview stage. As
/// wide as the thumbnail, which lines it up from card to card.
@MainActor
enum TemplatePreviewControl {
    static let height: CGFloat = 22
    static let gap: CGFloat = 6
    private static let cornerRadius: CGFloat = 7

    static func label(_ title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "play.fill")
                .font(.system(size: 7.5, weight: .bold))
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(V6Palette.paper.opacity(0.9))
        .frame(width: TemplateThumbnail.size.width, height: height)
        .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Color.white.opacity(0.1)))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// A template's look in miniature: its closed island on top, its Nook page
/// under it. Everything is drawn from the template's own settings, which
/// keeps the picture from drifting away from what applying it does. Pure
/// SwiftUI and still.
struct TemplateThumbnail: View {
    let template: PersonalizationTemplate

    static let size = CGSize(width: 148, height: 92)
    private static let contentWidth: CGFloat = 110
    private static let pillHeight: CGFloat = 22
    private static let slotSize: CGFloat = 16
    private static let tileGap: CGFloat = 3
    /// The real glow is sized for the full island; the thumbnail's pill is
    /// about half as tall.
    private static let glowScale: CGFloat = 0.5
    private static let vividGlowOpacity = 0.9
    private static let subtleGlowOpacity = 0.55

    var body: some View {
        VStack(spacing: 8) {
            pill
            page
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }

    // MARK: Closed island

    private var pill: some View {
        HStack(spacing: 0) {
            glyph(template.previewLeft)
            Spacer(minLength: 0)
            glyph(template.previewRight)
        }
        .padding(.horizontal, 5)
        .frame(width: Self.contentWidth, height: Self.pillHeight)
        .background(Capsule().fill(Color.black))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
        .islandHaloPreview(glow, cornerRadius: Self.pillHeight / 2)
    }

    private var glow: IslandHaloState {
        let style = template.nook.haloStyle
        guard style != .off, let color = template.previewGlow else { return .off }
        let metrics = IslandHaloMetrics.metrics(for: style)
        return IslandHaloState(
            source: .approval,
            color: color,
            motion: .steady,
            restOpacity: style == .vivid ? Self.vividGlowOpacity : Self.subtleGlowOpacity,
            radius: metrics.radius * Self.glowScale,
            drop: metrics.drop * Self.glowScale
        )
    }

    @ViewBuilder
    private func glyph(_ glyph: PersonalizationTemplate.Glyph) -> some View {
        switch glyph {
        case .bars:
            TemplateMiniBars(levels: [0.45, 0.9, 0.6])
                .frame(width: Self.slotSize, height: Self.slotSize)
        case .visualizer:
            TemplateMiniBars(levels: [0.5, 0.95, 0.65, 0.35])
                .frame(width: Self.slotSize, height: Self.slotSize)
        case .count:
            Text("×3")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(V6Palette.paper.opacity(0.75))
                .frame(height: Self.slotSize)
        case .agents:
            HStack(spacing: 2.5) {
                ForEach(Array([Color.orange, Color.blue, Color.green].enumerated()), id: \.offset) { _, color in
                    Circle().fill(color).frame(width: 4.5, height: 4.5)
                }
            }
            .frame(height: Self.slotSize)
        case .date:
            sample(.date)
        case .battery:
            sample(.battery)
        case .countdown:
            sample(.countdown)
        case .artwork:
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.pink.opacity(0.85), Color.purple.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: Self.slotSize - 2, height: Self.slotSize - 2)
                .frame(width: Self.slotSize, height: Self.slotSize)
        case .none:
            Color.clear.frame(width: Self.slotSize, height: Self.slotSize)
        }
    }

    /// The same sample the slot cards further down the tab show.
    @ViewBuilder
    private func sample(_ slot: NookSideSlot) -> some View {
        if let content = AppearanceSettingsPane.sampleSideSlot(slot) {
            NookSideSlotView(content: content, size: Self.slotSize, isLive: false)
        }
    }

    // MARK: Nook page

    private var page: some View {
        VStack(spacing: Self.tileGap) {
            ForEach(NookWidgetLayout.rows(template.widgets)) { row in
                HStack(spacing: Self.tileGap) {
                    ForEach(row.placements) { placement in
                        tile(placement.kind)
                    }
                    // A lone small widget keeps its half of the row.
                    if row.isSmallRow, row.placements.count == 1 {
                        Color.clear
                    }
                }
                .frame(height: Self.tileHeight(row))
            }
        }
        .frame(width: Self.contentWidth)
    }

    private static func tileHeight(_ row: NookWidgetRow) -> CGFloat {
        row.placements[0].size == .large ? 17 : 11
    }

    private func tile(_ kind: NookWidgetKind) -> some View {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(Color.white.opacity(0.1))
            .overlay(
                Image(systemName: kind.systemImage)
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.75))
            )
    }
}

/// A few still bars: the agents' activity bars or the music visualizer at
/// thumbnail size.
private struct TemplateMiniBars: View {
    /// Each bar's height as a share of the tallest.
    let levels: [Double]

    private static let barWidth: CGFloat = 2
    private static let maxHeight: CGFloat = 10

    var body: some View {
        HStack(alignment: .center, spacing: 1.5) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(V6Palette.paper.opacity(0.9))
                    .frame(width: Self.barWidth, height: Self.maxHeight * level)
            }
        }
    }
}
