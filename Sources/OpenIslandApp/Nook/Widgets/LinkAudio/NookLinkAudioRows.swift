import SwiftUI

/// One job on the card: a title, then what it is doing, then the button
/// that fits. Waiting and running jobs can be cancelled, and a finished one
/// can be shown in Finder. A failed one says why in words.
struct NookLinkAudioRow: View {
    static let height: CGFloat = 30
    static let spacing: CGFloat = 4

    let job: NookLinkAudioJob
    var isCompact = false
    var onCancel: () -> Void = {}
    var onShow: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(job.title ?? job.link.text)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(job.title == nil ? 0.55 : 0.85))
                    .lineLimit(1)
                    .truncationMode(job.title == nil ? .middle : .tail)
                detail
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .frame(maxWidth: .infinity, minHeight: Self.height, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    // MARK: Second line

    @ViewBuilder
    private var detail: some View {
        let lang = LanguageManager.shared
        switch job.phase {
        case .waiting:
            note(lang.t("nook.linkAudio.job.waiting"))
        case let .downloading(fraction):
            HStack(spacing: 6) {
                NookLinkAudioBar(fraction: fraction)
                if let fraction {
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 30, alignment: .trailing)
                }
            }
        case .converting:
            HStack(spacing: 6) {
                NookLinkAudioBar(fraction: 1)
                note(lang.t("nook.linkAudio.job.converting"))
                    .fixedSize()
            }
        case .cancelling:
            note(lang.t("nook.linkAudio.job.cancelling"))
        case .done:
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.green)
                // The small card has no room for both words and the findings:
                // the tick says it is saved.
                if job.findings?.shownText == nil || !isCompact {
                    note(lang.t("nook.linkAudio.job.done"))
                }
                if let found = job.findings?.shownText {
                    if !isCompact {
                        note("·")
                            .accessibilityHidden(true)
                    }
                    Text(found)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .accessibilityLabel(job.findings?.spokenText ?? found)
                }
            }
        case let .failed(failure):
            Text(lang.t(failure.messageKey))
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.45))
            .lineLimit(1)
    }

    // MARK: Button

    @ViewBuilder
    private var trailing: some View {
        let lang = LanguageManager.shared
        switch job.phase {
        case .waiting, .downloading, .converting:
            let name = job.title ?? job.link.text
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(lang.t("nook.linkAudio.job.cancel"))
            .accessibilityLabel(lang.t("nook.linkAudio.job.cancelNamed", name))
        case .done:
            Button(action: onShow) {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 10, weight: .semibold))
                    if !isCompact {
                        Text(lang.t("nook.linkAudio.job.showInFinder"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 8)
                .frame(minWidth: 24, minHeight: 22)
                .background(Capsule().fill(Color.white.opacity(0.1)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(lang.t("nook.linkAudio.job.showInFinder"))
            .accessibilityLabel(lang.t("nook.linkAudio.job.showInFinder"))
        case .cancelling, .failed:
            EmptyView()
        }
    }
}

/// A thin bar for a fraction. Drawn from shapes, which `ImageRenderer`
/// can draw, and with nothing that moves by itself. A size that is not
/// known yet is a dim bar with no fill.
struct NookLinkAudioBar: View {
    let fraction: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(fraction == nil ? 0.2 : 0.12))
                if let fraction {
                    Capsule()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: max(4, proxy.size.width * min(max(fraction, 0), 1)))
                }
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityValue(fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "")
    }
}
