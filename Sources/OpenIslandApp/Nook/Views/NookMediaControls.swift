import SwiftUI

/// Sizes of the scrub bar. A plain enum and not part of the view, which
/// keeps them callable from tests without the main actor.
enum NookScrubBarLayout {
    /// The line at rest, and while the pointer is on it or dragging it.
    static let restThickness: CGFloat = 3
    static let activeThickness: CGFloat = 5
    static let thumbSize: CGFloat = 9
    /// The band that takes the pointer. It is taller than the line, which
    /// makes a thin line easy to grab, and it lays out as the line alone.
    static let hitHeight: CGFloat = 11
    static let labelSpacing: CGFloat = 4

    /// Where the thumb's leading edge sits, kept inside the bar.
    static func thumbOffset(progress: Double, width: CGFloat) -> CGFloat {
        let center = width * CGFloat(min(max(progress, 0), 1))
        return min(max(center - thumbSize / 2, 0), max(0, width - thumbSize))
    }
}

/// The scrub bar on the now-playing card: elapsed time, the track's length
/// and a line that can be dragged to seek. The seek is sent once, when the
/// drag ends. A player that reports no length gets no bar, and a player
/// that ignored a seek gets a line that only shows progress.
struct NookScrubBar: View {
    let state: NowPlayingState
    var media: MediaRemoteService

    @State private var dragFraction: Double?
    @State private var isHovering = false

    var body: some View {
        let mode = NookScrubRules.mode(
            duration: state.duration,
            refusesSeek: media.seekTracker.refusesSeek(state)
        )
        if mode != .hidden, let duration = state.duration {
            // One tick a second, and none while the track is paused.
            TimelineView(.animation(minimumInterval: 1, paused: !state.isPlaying)) { context in
                bar(mode: mode, duration: duration, now: context.date)
            }
        }
    }

    private func bar(mode: NookScrubMode, duration: TimeInterval, now: Date) -> some View {
        let position = NookScrubRules.position(
            reported: state.position(at: now),
            held: media.seekTracker.heldPosition(for: state, now: now),
            dragFraction: dragFraction,
            duration: duration
        )
        let progress = position / duration
        let isActive = mode == .seekable && (isHovering || dragFraction != nil)
        let thickness = isActive ? NookScrubBarLayout.activeThickness : NookScrubBarLayout.restThickness
        return VStack(spacing: NookScrubBarLayout.labelSpacing) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                        .frame(height: thickness)
                    Capsule().fill(Color.white.opacity(0.85))
                        .frame(width: max(0, width * progress), height: thickness)
                    if isActive {
                        Circle().fill(Color.white)
                            .frame(width: NookScrubBarLayout.thumbSize, height: NookScrubBarLayout.thumbSize)
                            .offset(x: NookScrubBarLayout.thumbOffset(progress: progress, width: width))
                            .transition(.opacity)
                    }
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(mode == .seekable ? seekGesture(width: width, duration: duration) : nil)
                .onHover { hovering in
                    withMotion(Motion.hover) { isHovering = hovering }
                }
            }
            .frame(height: NookScrubBarLayout.hitHeight)
            .padding(.vertical, -(NookScrubBarLayout.hitHeight - NookScrubBarLayout.restThickness) / 2)

            HStack {
                Text(NookScrubRules.clock(position))
                Spacer()
                Text(NookScrubRules.clock(duration))
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(dragFraction == nil ? 0.4 : 0.75))
            // The band above reaches into this row's space.
            .allowsHitTesting(false)
        }
    }

    /// The line follows the pointer during the drag. The player is asked
    /// once, on release.
    private func seekGesture(width: CGFloat, duration: TimeInterval) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                dragFraction = NookScrubRules.fraction(atX: value.location.x, width: width)
            }
            .onEnded { value in
                let fraction = NookScrubRules.fraction(atX: value.location.x, width: width)
                media.seek(to: fraction * duration)
                dragFraction = nil
            }
    }
}

/// The button on the now-playing card that opens the speaker list. It
/// shows the output sound goes to now.
struct NookSpeakerButton: View {
    var outputs: NookAudioOutputs
    var size: CGFloat = 12
    var hit: CGFloat = 26
    var action: () -> Void

    private var lang: LanguageManager { .shared }

    var body: some View {
        Button(action: action) {
            Image(systemName: outputs.current.map(NookAudioOutputRules.symbol(for:)) ?? "hifispeaker.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: hit, height: hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(lang.t("nook.media.speakers.choose"))
        .accessibilityLabel(lang.t("nook.media.speakers.choose"))
    }
}

/// The speaker list that takes the now-playing card's place while an
/// output is picked. It is drawn inside the card and is not a menu: a menu
/// opens outside the island, and the pointer leaving the island closes it.
struct NookSpeakerList: View {
    var outputs: NookAudioOutputs
    var onDone: () -> Void

    static let rowHeight: CGFloat = 24
    /// How long the list stays after a pick, which lets the check mark be
    /// seen on the new output.
    static let closeDelay: Duration = .milliseconds(450)

    private var lang: LanguageManager { .shared }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Button(action: onDone) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 22, height: Self.rowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lang.t("nook.media.speakers.back"))

            if outputs.devices.isEmpty {
                Text(lang.t("nook.media.speakers.none"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
            } else {
                // The list scrolls only when the card is too short for it.
                ViewThatFits(in: .vertical) {
                    rows
                    ScrollView(.vertical) { rows }
                        .scrollBounceBehavior(.basedOnSize)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var rows: some View {
        VStack(spacing: 2) {
            ForEach(outputs.devices) { output in
                row(output)
            }
        }
    }

    private func row(_ output: NookAudioOutput) -> some View {
        let isCurrent = output.id == outputs.currentID
        let failed = output.id == outputs.failedID
        return Button {
            pick(output)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: NookAudioOutputRules.symbol(for: output))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(isCurrent ? 0.95 : 0.55))
                    .frame(width: 18)
                Text(output.name)
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(isCurrent ? 0.95 : 0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if failed {
                    Text(lang.t("nook.media.speakers.failed"))
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                } else if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 8)
            .frame(height: Self.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(isCurrent ? 0.1 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: 7, opacity: 0.06)
    }

    private func pick(_ output: NookAudioOutput) {
        guard output.id != outputs.currentID else {
            onDone()
            return
        }
        withMotion(Motion.selection) { outputs.select(output.id) }
        // A switch that failed keeps the list up, with the reason on its row.
        guard outputs.failedID == nil else { return }
        Task { @MainActor in
            try? await Task.sleep(for: Self.closeDelay)
            onDone()
        }
    }
}
