import SwiftUI
import UniformTypeIdentifiers

/// The designer kit's card. Its header holds three tabs, the colors, the
/// links and the reference pictures, and the eyedropper, which is one press
/// away on any tab. Small shows a row of swatches or pictures, or a few
/// links; medium adds the recent colors or the field and the collections of
/// the links; and large adds names, the palette switcher and a field to
/// type a color into. Anything larger than that, the palette editor and a
/// picture at full size, opens in a floating panel.
///
/// The card never changes height, which keeps it out of the page's
/// height math beyond its three fixed sizes.
struct NookDesignCard: View {
    var kit: NookDesignKit
    private let isStill: Bool
    @Environment(\.nookWidgetSize) private var size

    init(nook: NookModel) {
        kit = nook.design
        isStill = false
    }

    /// A card on a kit of its own, which is how the render tests draw it.
    /// `isStill` swaps what `ImageRenderer` cannot draw for look-alikes.
    init(kit: NookDesignKit, isStill: Bool = false) {
        self.kit = kit
        self.isStill = isStill
    }

    static func height(for size: NookWidgetSize) -> CGFloat {
        NookDesignCardLayout.height(for: size)
    }

    var body: some View {
        // The header carries the gap under it: it is 8 points, or 4 when the
        // pill has a line of its own.
        VStack(alignment: .leading, spacing: 0) {
            NookDesignHeader(kit: kit, isCompact: size == .small)
            switch kit.tab {
            case .colors: NookDesignColorsTab(kit: kit)
            case .links: NookDesignLinksTab(kit: kit)
            case .references: NookDesignReferencesTab(kit: kit)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // Fill the cell the grid gives us; the grid owns the outer height.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NookCardBackground())
        .overlay {
            if kit.isPictureDragOverCard {
                NookDesignDropHighlight(isCompact: size == .small)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if let notice = kit.notice {
                NookDesignNoticeBar(notice: notice)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            } else if let standing = kit.standingNotice {
                NookDesignStandingBar(notice: standing) { kit.openSettingsFromStandingNotice() }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
        }
        .motionAnimation(Motion.hover, value: kit.standingNotice)
        .motionAnimation(Motion.hover, value: kit.isPictureDragOverCard)
        .motionAnimation(Motion.hover, value: kit.notice)
        .environment(\.nookDesignIsStill, isStill)
        .modifier(NookDesignDropTarget(kit: kit, isOn: !isStill))
        // With the card gone nobody is typing in it.
        .onDisappear {
            kit.renamingReferenceID = nil
            kit.linkNaming = nil
            kit.isPictureDragOverCard = false
        }
    }
}

// MARK: - Header

/// The card's title row: the three tab names where the title was, then the
/// pill that keeps the eyedropper going, the buttons that belong to the tab,
/// and the eyedropper.
private struct NookDesignHeader: View {
    @Environment(\.hangoverAccent) private var accent
    var kit: NookDesignKit
    let isCompact: Bool

    var body: some View {
        // The pill sits in the row, left of the buttons, when the row has room
        // for it beside the tab names. When it has not it takes a line of its
        // own under the row, under the buttons, and the row keeps all it had.
        ViewThatFits(in: .horizontal) {
            row(showsPill: true)
                .padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 4) {
                row(showsPill: false)
                NookDesignKeepPill(kit: kit)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.bottom, 4)
        }
    }

    private func row(showsPill: Bool) -> some View {
        let lang = LanguageManager.shared
        let gap: CGFloat = isCompact ? 8 : 10
        // The pill sits a little closer to the buttons than they sit to each
        // other: the row has no room to spare for it beside the tab names.
        return HStack(spacing: 0) {
            HStack(spacing: gap) {
                ForEach(NookDesignTab.allCases) { tab in
                    tabButton(tab)
                }
            }
            Spacer(minLength: 8)
            if showsPill {
                NookDesignKeepPill(kit: kit)
                    .padding(.trailing, 5)
            }
            HStack(spacing: gap) {
                tabButtons(lang)
            }
        }
        .frame(height: 20)
        .motionAnimation(Motion.selection, value: kit.tab)
    }

    /// The buttons that belong to the tab, then the eyedropper.
    @ViewBuilder
    private func tabButtons(_ lang: LanguageManager) -> some View {
        switch kit.tab {
        case .colors:
            NookDesignIconButton(
                symbol: "slider.horizontal.3",
                label: lang.t("nook.design.action.editPalettes")
            ) { kit.showPaletteEditor() }
        case .links:
            NookDesignIconButton(
                symbol: "doc.on.clipboard",
                label: lang.t("nook.design.action.pasteLink")
            ) { kit.pasteLink() }
        case .references:
            if !kit.openPanels.isEmpty {
                NookDesignIconButton(
                    symbol: "xmark.rectangle",
                    label: lang.t("nook.design.action.closePanels")
                ) { kit.closeAllReferencePanels() }
            }
            NookDesignIconButton(
                symbol: "doc.on.clipboard",
                label: lang.t("nook.design.action.paste")
            ) { kit.pasteReference() }
        }
        NookDesignIconButton(
            symbol: "eyedropper",
            label: lang.t("nook.design.action.pick"),
            tint: accent.highlight(.orange),
            isOn: kit.isSampling
        ) { kit.pickColor(from: .island) }
    }

    private func tabButton(_ tab: NookDesignTab) -> some View {
        let isSelected = kit.tab == tab
        let title = LanguageManager.shared.t(tab.titleKey)
        return Button {
            kit.tab = tab
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tab.symbol)
                    .font(.system(size: isCompact ? 11 : 10, weight: .semibold))
                if !isCompact {
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.6)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white.opacity(isSelected ? 0.8 : 0.3))
            .frame(minWidth: isCompact ? 20 : 0, minHeight: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .demoTarget(.designTab(tab))
    }
}

// MARK: - Drops

/// Makes the whole card take dropped pictures, on either tab.
private struct NookDesignDropTarget: ViewModifier {
    var kit: NookDesignKit
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.onDrop(
                of: [.fileURL, .image],
                isTargeted: Binding(
                    get: { kit.isPictureDragOverCard },
                    set: { kit.isPictureDragOverCard = $0 }
                )
            ) { providers in
                kit.handlePictureDrop(providers)
            }
        } else {
            content
        }
    }
}

/// Covers the card while pictures are dragged over it, which marks it as
/// the place they land. It takes no hits: the drop still goes to the card
/// under it.
struct NookDesignDropHighlight: View {
    @Environment(\.hangoverAccent) private var accent
    let isCompact: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    var body: some View {
        shape
            .fill(Color.black.opacity(0.72))
            .overlay(shape.fill(accent.highlight(.orange).opacity(0.14)))
            .overlay(shape.strokeBorder(accent.highlight(.orange), style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            .overlay {
                HStack(spacing: 6) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: isCompact ? 13 : 15, weight: .semibold))
                    Text(LanguageManager.shared.t(isCompact ? "nook.design.drop.short" : "nook.design.drop.long"))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .foregroundStyle(accent.highlight(.orange))
                .padding(.horizontal, 10)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Sample

extension NookDesignCard {
    /// A still picture of the colors tab for the Settings preview, which
    /// never reads the user's own shelf.
    static func sample(size: NookWidgetSize) -> some View {
        NookDesignSampleContent(size: size)
    }
}

/// Fixed colors drawn the way the card draws them.
private struct NookDesignSampleContent: View {
    @Environment(\.hangoverAccent) private var accent
    let size: NookWidgetSize

    private static let colors: [NookDesignColor] = [
        NookDesignColor(red: 255, green: 107, blue: 53),
        NookDesignColor(red: 247, green: 197, blue: 72),
        NookDesignColor(red: 46, green: 196, blue: 182),
        NookDesignColor(red: 58, green: 134, blue: 255),
        NookDesignColor(red: 131, green: 56, blue: 236),
        NookDesignColor(red: 240, green: 240, blue: 240),
        NookDesignColor(red: 34, green: 34, blue: 34, alpha: 128),
    ]

    var body: some View {
        let side = NookDesignCardLayout.swatchSide(for: size)
        let shown = size == .small ? 5 : Self.colors.count
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: NookDesignTab.colors.symbol)
                    .font(.system(size: 10, weight: .semibold))
                if size != .small {
                    Text(LanguageManager.shared.t(NookDesignTab.colors.titleKey).uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.6)
                }
                Spacer(minLength: 0)
                Image(systemName: "eyedropper")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(accent.highlight(.orange))
            }
            .foregroundStyle(.white.opacity(0.5))
            HStack(spacing: NookDesignCardLayout.spacing) {
                ForEach(Array(Self.colors.prefix(shown).enumerated()), id: \.offset) { index, color in
                    NookDesignSwatchChip(color: color, side: side, isFavorite: index == 0)
                }
                Spacer(minLength: 0)
            }
            if size != .small {
                HStack(spacing: 5) {
                    ForEach(Array(Self.colors.suffix(4).enumerated()), id: \.offset) { _, color in
                        NookDesignSwatchChip(color: color, side: 16, isRound: true)
                    }
                    Spacer(minLength: 0)
                    NookDesignChipLabel(text: NookDesignColorFormat.hex.shortTitle)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }
}
