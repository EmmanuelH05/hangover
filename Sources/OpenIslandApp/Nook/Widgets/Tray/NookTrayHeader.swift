import SwiftUI

/// Sizes of the tray card's header row, in a plain enum and not the View: a
/// closure in a View static traps when a nonisolated test reads it.
enum NookTrayHeaderLayout {
    /// The row is this tall on every tab, with or without the chip, which
    /// keeps the files and the clipboard list from shifting when the tab
    /// changes. It also keeps the medium card's tiles inside the card.
    static let height: CGFloat = 14
    /// Between the pieces that sit together: FILES, its count and its chip.
    static let gap: CGFloat = 6
    /// The least room kept between the files side and the clipboard tab.
    static let tabGap: CGFloat = 10
}

enum NookTrayHeaderRules {
    /// The Convert chip hangs off the FILES tab, which keeps it only there,
    /// and only when there is a file to convert. Every card size has it: the
    /// small card is short, not narrow, and a narrow one gets the chip's
    /// icon alone (`NookTrayConvertChip`).
    static func showsConvertChip(tab: NookTrayTab, hasFiles: Bool) -> Bool {
        tab == .files && hasFiles
    }
}

/// The card's title row. The FILES tab is on the left with the count of files
/// and the Convert chip after it, which makes the chip read as part of Files. The
/// CLIPBOARD tab is pushed to the right edge with its clear button after it.
/// The tab being shown is bright, and a click on the other switches to it.
/// A header too narrow for the names shows the icons alone, all at once: a
/// whole icon reads better than a name cut short, and one tab named beside
/// one not reads as a mistake.
struct NookTrayHeader: View {
    var store: NookTrayStore

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(isCompact: false)
            row(isCompact: true)
        }
        .frame(height: NookTrayHeaderLayout.height)
        .motionAnimation(Motion.selection, value: store.tab)
        .motionAnimation(Motion.selection, value: store.isPickingToConvert)
    }

    private func row(isCompact: Bool) -> some View {
        HStack(spacing: NookTrayHeaderLayout.gap) {
            tabButton(.files, isCompact: isCompact)
            // The count belongs to FILES. After the chip it read as a count
            // of conversions.
            if store.tab == .files, !store.items.isEmpty {
                Text("\(store.items.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            }
            if NookTrayHeaderRules.showsConvertChip(tab: store.tab, hasFiles: !store.items.isEmpty) {
                NookTrayConvertChip(store: store, isCompact: isCompact)
            }
            Spacer(minLength: NookTrayHeaderLayout.tabGap)
            tabButton(.clipboard, isCompact: isCompact)
            if store.tab == .clipboard, !store.clipboard.history.entries.isEmpty {
                clearButton
            }
        }
    }

    /// A tab's icon and name, or its icon alone in the compact row. The name
    /// stays for VoiceOver and the pointer.
    private func tabButton(_ tab: NookTrayTab, isCompact: Bool) -> some View {
        let isSelected = store.tab == tab
        let title = LanguageManager.shared.t(tab.titleKey)
        return Button {
            store.tab = tab
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tab.symbol)
                if !isCompact {
                    Text(title.uppercased())
                        .tracking(0.6)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(isSelected ? 0.8 : 0.3))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var clearButton: some View {
        Button {
            withMotion(Motion.selection) { store.clipboard.clear() }
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(LanguageManager.shared.t("nook.tray.clipboard.clear"))
        .accessibilityLabel(LanguageManager.shared.t("nook.tray.clipboard.clear"))
    }
}

/// The small capsule after FILES that turns picking on. Off it is an outline
/// with a quiet label. While picking it fills with the accent, says what to
/// do and shows an xmark, and pressing it again cancels. In the compact row it
/// keeps the icon, and the label stays for VoiceOver and the pointer.
struct NookTrayConvertChip: View {
    var store: NookTrayStore
    var isCompact = false
    @Environment(\.hangoverAccent) private var accent

    /// A little shorter than the row, so the capsule never makes it grow.
    private static let height = NookTrayHeaderLayout.height - 1

    var body: some View {
        let isPicking = store.isPickingToConvert
        let label = LanguageManager.shared.t(isPicking ? "nook.tray.convert.chip.picking" : "nook.tray.convert.chip")
        Button {
            withMotion(Motion.selection) { store.togglePickingToConvert() }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "arrow.triangle.2.circlepath")
                if !isCompact {
                    Text(label)
                        .lineLimit(1)
                        .fixedSize()
                }
                if isPicking {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                }
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(isPicking ? accent.textOnHighlight(.black) : Color.white.opacity(0.55))
            .padding(.horizontal, 7)
            .frame(height: Self.height)
            .background(Capsule().fill(isPicking ? accent.highlight(.orange) : Color.clear))
            .overlay(Capsule().strokeBorder(Color.white.opacity(isPicking ? 0 : 0.22), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isPicking ? .isSelected : [])
    }
}
