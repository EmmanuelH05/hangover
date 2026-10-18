import SwiftUI

/// Sizes of the update cards on the open island (D82). The island sizes
/// its window before SwiftUI lays anything out, which is why every card
/// has one height per kind.
enum UpdateCardLayout {
    /// The ask: eyebrow, title, body, the line of keys, two buttons.
    static let askHeight: CGFloat = 150
    /// Update ready: the same without the line of keys.
    static let readyHeight: CGFloat = 132
    /// What's new: eyebrow and footer around one row per item.
    static let whatsNewBaseHeight: CGFloat = 94
    static let whatsNewRowHeight: CGFloat = 50
    static let plateSize: CGFloat = 40

    static func height(for kind: UpdateCardKind) -> CGFloat {
        switch kind {
        case .ask: askHeight
        case .ready: readyHeight
        case let .whatsNew(pending): whatsNewBaseHeight + CGFloat(pending.shown.count) * whatsNewRowHeight
        }
    }

    /// Height the card adds to the page: itself and one row gap under it.
    static func pageHeight(for kind: UpdateCardKind) -> CGFloat {
        height(for: kind) + NookWidgetLayout.rowSpacing
    }
}

/// The three cards of the update flow: the ask ("New version dropped!
/// Install?"), Update ready after Later, and What's new after the relaunch.
/// Each spans the page like the Join bar does. The buttons that go ahead
/// are paper, never the amber of an agent approval (K5).
struct UpdateCardView: View {
    let kind: UpdateCardKind
    /// The shortcut keys under the ask's body, nil when none is ready.
    var hint: AgentHotkeyHint? = nil
    var lang: LanguageManager = .shared
    var onLater: () -> Void = {}
    var onInstall: () -> Void = {}
    var onDone: () -> Void = {}
    var onSeeAll: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch kind {
            case let .ask(version):
                eyebrow(lang.t("update.card.eyebrow"))
                title(lang.t("update.ask"))
                    .padding(.top, 8)
                bodyLine(lang.t("update.card.ask.body", version))
                    .padding(.top, 4)
                if let hint {
                    // The pill's own chips, keys first and Install in
                    // paper, the same on the card (K5, K6).
                    NookClosedChipsView(chips: NookClosedChips(
                        deny: NookClosedChip(keys: hint.deny, title: lang.t("update.ask.later")),
                        approve: NookClosedChip(keys: hint.approve, title: lang.t("update.ask.install"), isPrimary: true)
                    ))
                    .frame(height: 16)
                    .padding(.top, 7)
                }
                Spacer(minLength: 0)
                buttons(secondary: lang.t("update.ask.later"), primary: lang.t("update.ask.install"))
            case let .ready(version):
                eyebrow(lang.t("update.card.eyebrow"))
                title(lang.t("update.card.ready.title", version))
                    .padding(.top, 8)
                bodyLine(lang.t("update.card.ready.body"))
                    .padding(.top, 4)
                Spacer(minLength: 0)
                buttons(secondary: lang.t("update.ask.later"), primary: lang.t("update.card.ready.restart"))
            case let .whatsNew(pending):
                HStack(spacing: 6) {
                    eyebrow(lang.t("update.card.whatsNew.eyebrow", pending.version))
                    Spacer(minLength: 0)
                    Text("\(pending.totalCount)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(pending.shown.enumerated()), id: \.offset) { _, item in
                        whatsNewRow(item, drawsPlate: pending.shown.count > 1)
                            .frame(height: UpdateCardLayout.whatsNewRowHeight)
                    }
                }
                .padding(.top, 6)
                Spacer(minLength: 0)
                HStack {
                    Button(action: onSeeAll) {
                        Text(lang.t("update.card.whatsNew.seeAll"))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("update.whatsNew.seeAll")
                    Spacer(minLength: 0)
                    Button(action: onDone) {
                        Text(lang.t("update.card.whatsNew.done"))
                    }
                    .buttonStyle(UpdateCardButtonStyle(prominent: true))
                    .accessibilityIdentifier("update.whatsNew.done")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NookCardBackground())
        .accessibilityElement(children: .contain)
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.5))
            .lineLimit(1)
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white.opacity(0.94))
            .lineLimit(1)
    }

    private func bodyLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .regular))
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func buttons(secondary: String, primary: String) -> some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button(action: onLater) { Text(secondary) }
                .buttonStyle(UpdateCardButtonStyle(prominent: false))
                .accessibilityIdentifier("update.later")
            Button(action: onInstall) { Text(primary) }
                .buttonStyle(UpdateCardButtonStyle(prominent: true))
                .accessibilityIdentifier("update.install")
        }
    }

    private func whatsNewRow(_ item: WhatsNewItem, drawsPlate: Bool) -> some View {
        HStack(spacing: 12) {
            if drawsPlate {
                Image(systemName: item.symbol ?? "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(item.symbol == nil ? 0.45 : 0.9))
                    .frame(width: UpdateCardLayout.plateSize, height: UpdateCardLayout.plateSize)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08))
                    )
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                if let detail = item.detail {
                    Text(detail)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// The card's buttons: paper for the one that goes ahead, a quiet capsule
/// for the one that holds off.
struct UpdateCardButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(prominent ? V6Palette.ink : .white.opacity(0.85))
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(Capsule().fill(prominent ? V6Palette.paper : Color.white.opacity(0.1)))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
