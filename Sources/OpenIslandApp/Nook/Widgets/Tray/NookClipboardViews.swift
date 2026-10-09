import AppKit
import SwiftUI

/// The clipboard side of the tray card: the offer to switch the history
/// on, a word about access when macOS holds reads back, and the copies.
struct NookClipboardTab: View {
    var store: NookTrayStore
    @Environment(\.nookWidgetSize) private var size

    var body: some View {
        let clipboard = store.clipboard
        Group {
            if !clipboard.isEnabled {
                NookClipboardOffer(store: store, size: size)
            } else if clipboard.history.entries.isEmpty, clipboard.access == .allowed {
                Text(LanguageManager.shared.t("nook.tray.clipboard.empty"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                list(clipboard)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The rows sit still while they all fit, and scroll once they do not.
    private func list(_ clipboard: NookClipboardMonitor) -> some View {
        let entries = clipboard.history.entries
        return ViewThatFits(in: .vertical) {
            rows(clipboard, entries)
            ScrollView(.vertical, showsIndicators: false) {
                rows(clipboard, entries)
            }
        }
        .motionAnimation(Motion.reflow, value: entries.map(\.id))
    }

    private func rows(_ clipboard: NookClipboardMonitor, _ entries: [NookClipboardEntry]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if clipboard.access != .allowed {
                NookClipboardAccessNote(store: store, access: clipboard.access, size: size)
            }
            ForEach(entries) { entry in
                NookClipboardRow(
                    store: store,
                    entry: entry,
                    isJustCopied: clipboard.justCopiedID == entry.id
                )
            }
        }
    }
}

// MARK: - Switching it on

/// Shown while the history is off. One click switches it on. Nothing is
/// read from the pasteboard before that click.
private struct NookClipboardOffer: View {
    var store: NookTrayStore
    let size: NookWidgetSize

    var body: some View {
        switch size {
        case .medium:
            HStack(spacing: 10) {
                note("nook.tray.clipboard.offer.short")
                Spacer(minLength: 0)
                turnOnButton
            }
            .frame(maxHeight: .infinity)
        case .small, .large:
            VStack(alignment: .leading, spacing: 8) {
                note(size == .large ? "nook.tray.clipboard.offer.long" : "nook.tray.clipboard.offer.short")
                turnOnButton
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private func note(_ key: String) -> some View {
        Text(LanguageManager.shared.t(key))
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.5))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var turnOnButton: some View {
        Button(LanguageManager.shared.t("nook.tray.clipboard.turnOn")) {
            withMotion(Motion.contentSwap) { store.clipboard.setEnabled(true) }
        }
        .buttonStyle(NookTrayPillButtonStyle(prominent: true))
    }
}

// MARK: - Access

/// Says why copies are not being recorded while macOS asks before each
/// read or refuses them, and offers the two ways forward.
///
/// Large has room for the whole explanation and a named second button.
/// Small and medium get the short line and a plus for the second button.
private struct NookClipboardAccessNote: View {
    var store: NookTrayStore
    let access: NookClipboardAccess
    let size: NookWidgetSize

    var body: some View {
        switch size {
        case .medium:
            HStack(alignment: .center, spacing: 10) {
                message
                Spacer(minLength: 0)
                buttons
            }
            .padding(.bottom, 4)
        case .small, .large:
            VStack(alignment: .leading, spacing: 6) {
                message
                buttons
            }
            .padding(.bottom, 4)
        }
    }

    private var messageKey: String {
        let base = access == .denied ? "nook.tray.clipboard.denied" : "nook.tray.clipboard.asks"
        return size == .large ? base : base + ".short"
    }

    private var message: some View {
        Text(LanguageManager.shared.t(messageKey))
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.55))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var buttons: some View {
        HStack(spacing: 6) {
            Button(LanguageManager.shared.t("nook.tray.clipboard.openSettings")) {
                store.openPasteSettings()
            }
            .buttonStyle(NookTrayPillButtonStyle(prominent: true))
            if access == .asks {
                addCurrentButton
            }
        }
    }

    @ViewBuilder
    private var addCurrentButton: some View {
        let title = LanguageManager.shared.t("nook.tray.clipboard.addCurrent")
        let action = { withMotion(Motion.reflow) { store.captureClipboardNow() } }
        if size == .large {
            Button(title, action: action)
                .buttonStyle(NookTrayPillButtonStyle(prominent: false))
        } else {
            Button(action: action) {
                Image(systemName: "plus")
            }
            .buttonStyle(NookTrayPillButtonStyle(prominent: false))
            .help(title)
            .accessibilityLabel(title)
        }
    }
}

// MARK: - Rows

/// One copy. A click puts it back on the clipboard.
private struct NookClipboardRow: View {
    var store: NookTrayStore
    let entry: NookClipboardEntry
    let isJustCopied: Bool
    @State private var isHovering = false

    /// Sized for two rows to fit the medium card without scrolling.
    private static let iconSide: CGFloat = 14
    private static let verticalPadding: CGFloat = 3

    var body: some View {
        Button {
            withMotion(Motion.reflow) { store.copyAgain(entry) }
        } label: {
            HStack(spacing: 6) {
                icon
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if isJustCopied {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.green)
                        .transition(.opacity)
                }
            }
            .padding(.leading, 6)
            // Room for the remove button, which sits over the row.
            .padding(.trailing, 22)
            .padding(.vertical, Self.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: 6, opacity: 0.08)
        .overlay(alignment: .trailing) {
            if isHovering, !isJustCopied {
                Button {
                    withMotion(Motion.reflow) { store.clipboard.remove(entry) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7), .white.opacity(0.12))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .accessibilityLabel(LanguageManager.shared.t("nook.tray.clipboard.remove"))
            }
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(LanguageManager.shared.t("nook.tray.clipboard.copyAgain")) { store.copyAgain(entry) }
            Button(LanguageManager.shared.t("nook.tray.clipboard.remove")) { store.clipboard.remove(entry) }
        }
    }

    private var title: String {
        switch entry.content {
        case let .text(text): NookClipboardHistory.preview(of: text)
        case .image: LanguageManager.shared.t("nook.tray.clipboard.image")
        }
    }

    @ViewBuilder
    private var icon: some View {
        if case let .image(_, _, thumbnail) = entry.content,
           let thumbnail, let image = NSImage(data: thumbnail) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: Self.iconSide, height: Self.iconSide)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        } else {
            Image(systemName: isImage ? "photo" : "text.alignleft")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: Self.iconSide, height: Self.iconSide)
        }
    }

    private var isImage: Bool {
        if case .image = entry.content { return true }
        return false
    }
}

// MARK: - Shared pieces

/// The small capsule buttons of the clipboard tab.
private struct NookTrayPillButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(prominent ? Color.black : Color.white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(prominent ? Color.orange : Color.white.opacity(0.1)))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
