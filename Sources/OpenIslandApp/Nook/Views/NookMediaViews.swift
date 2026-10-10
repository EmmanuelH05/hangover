import AppKit
import SwiftUI

// MARK: - Closed island

/// Album art tile for the left wing of the closed notch. Falls back to a
/// music note on the same rounded square when the player has not handed
/// over artwork yet.
struct NookAlbumArtView: View {
    let image: NSImage?
    var size: CGFloat
    var cornerRadius: CGFloat = 6

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.12)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Right wing of the closed notch while music plays: the user's GIF, or a
/// small bar visualizer when no GIF is chosen.
struct NookMediaSideView: View {
    let activity: NookClosedMediaActivity
    var height: CGFloat
    var width: CGFloat
    /// False freezes the GIF and the visualizer while the pill is hidden.
    var isLive: Bool = true

    var body: some View {
        if let url = activity.gifURL {
            AnimatedGIFView(url: url, isAnimating: activity.isPlaying && isLive)
                .frame(width: width, height: height)
                .scaleEffect(activity.gifScale, anchor: .center)
                .offset(activity.gifOffset)
                .clipped()
        } else {
            NookBarVisualizer(isPlaying: activity.isPlaying, barCount: 4, height: height * 0.6, isLive: isLive)
                .frame(width: width, height: height)
        }
    }
}

/// Four bars bouncing while playing, flat while paused.
///
/// The bars are Core Animation layers (`NookBarVisualizerLayerView`), which
/// the system moves without waking the app. A SwiftUI timeline here changed
/// the bars' frames twenty times a second, and each change re-laid out the
/// whole window it sat in: the island while music played, and the Settings
/// window for as long as the Personalization tab was open.
struct NookBarVisualizer: View {
    var isPlaying: Bool
    var barCount: Int = 4
    var height: CGFloat = 16
    var color: Color = .white
    /// False holds the bars still while the visualizer is hidden.
    var isLive: Bool = true

    static let barWidth: CGFloat = 3
    static let barSpacing: CGFloat = 2
    /// A bar at rest, and the lowest a moving bar gets, as parts of the height.
    static let pausedLevel: CGFloat = 0.25
    static let lowLevel: CGFloat = 0.35
    static let minimumBarHeight: CGFloat = 3

    static func width(barCount: Int) -> CGFloat {
        let count = CGFloat(max(barCount, 0))
        return count * barWidth + max(count - 1, 0) * barSpacing
    }

    /// The bars of a picture drawn offscreen, which shows no layers: playing
    /// bars at fixed, uneven heights.
    static func stillLevel(index: Int, isPlaying: Bool) -> CGFloat {
        guard isPlaying else { return pausedLevel }
        return lowLevel + (1 - lowLevel) * abs(sin(1.1 + Double(index) * 1.3))
    }

    @Environment(\.nookDrawsStill) private var drawsStill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if drawsStill {
                stillBars
            } else {
                NookBarVisualizerLayers(
                    isMoving: isPlaying && isLive && !reduceMotion,
                    isPlaying: isPlaying,
                    barCount: barCount,
                    height: height,
                    color: NSColor(color)
                )
            }
        }
        .frame(width: Self.width(barCount: barCount), height: height, alignment: .center)
    }

    private var stillBars: some View {
        HStack(alignment: .center, spacing: Self.barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(color.opacity(isPlaying ? 0.9 : 0.4))
                    .frame(
                        width: Self.barWidth,
                        height: max(Self.minimumBarHeight, height * Self.stillLevel(index: index, isPlaying: isPlaying))
                    )
            }
        }
    }
}

private struct NookBarVisualizerLayers: NSViewRepresentable {
    let isMoving: Bool
    let isPlaying: Bool
    let barCount: Int
    let height: CGFloat
    let color: NSColor

    func makeNSView(context: Context) -> NookBarVisualizerLayerView {
        let view = NookBarVisualizerLayerView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NookBarVisualizerLayerView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NookBarVisualizerLayerView) {
        view.update(isMoving: isMoving, isPlaying: isPlaying, barCount: barCount, height: height, color: color.cgColor)
    }
}

/// The visualizer's bars as layers. Each bar's height runs on a loop the
/// render server plays. Applying the same state twice changes nothing, which
/// keeps a SwiftUI re-render from restarting the bars.
final class NookBarVisualizerLayerView: NSView {
    static let loopKey = "visualizer.loop"
    /// How long one bar takes from low to full. Each bar has its own pace,
    /// which keeps the four from moving as one.
    static func riseDuration(index: Int) -> CFTimeInterval {
        .pi / (2 * (2.6 + Double(index) * 0.45))
    }

    private struct Applied: Equatable {
        var isMoving: Bool
        var isPlaying: Bool
        var barCount: Int
        var height: CGFloat
        var color: CGColor
    }

    private(set) var bars: [CALayer] = []
    private var applied: Applied?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func isAccessibilityElement() -> Bool { false }

    override func layout() {
        super.layout()
        placeBars()
    }

    /// A layer can lose its animations when its view leaves a window. Back
    /// in one, bars that should move and have no loop get theirs again.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, let applied, applied.isMoving,
              bars.contains(where: { $0.animation(forKey: Self.loopKey) == nil }) else { return }
        applyMotion(applied)
    }

    func update(isMoving: Bool, isPlaying: Bool, barCount: Int, height: CGFloat, color: CGColor) {
        let next = Applied(
            isMoving: isMoving, isPlaying: isPlaying, barCount: max(barCount, 0), height: height, color: color
        )
        guard next != applied else { return }
        let previous = applied
        applied = next

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if previous?.barCount != next.barCount { rebuildBars(count: next.barCount) }
        for bar in bars {
            bar.backgroundColor = next.color
            bar.opacity = next.isPlaying ? 0.9 : 0.4
        }
        placeBars()
        // A change of size or of pace starts the loops again. Anything else
        // (a new tint) leaves them running.
        let restarts = previous?.isMoving != next.isMoving || previous?.height != next.height
            || previous?.barCount != next.barCount
        if restarts { applyMotion(next) }
        CATransaction.commit()
    }

    private func rebuildBars(count: Int) {
        bars.forEach { $0.removeFromSuperlayer() }
        bars = (0..<count).map { _ in
            let bar = CALayer()
            bar.cornerRadius = 1
            bar.cornerCurve = .continuous
            layer?.addSublayer(bar)
            return bar
        }
    }

    private func restingHeight(_ state: Applied, index: Int) -> CGFloat {
        let level: CGFloat = state.isPlaying
            ? (state.isMoving ? 1 : NookBarVisualizer.stillLevel(index: index, isPlaying: true))
            : NookBarVisualizer.pausedLevel
        return max(NookBarVisualizer.minimumBarHeight, state.height * level)
    }

    /// Centers the row of bars in the view. Leaves the loops alone.
    private func placeBars() {
        guard let applied else { return }
        let rowWidth = NookBarVisualizer.width(barCount: bars.count)
        let originX = (bounds.width - rowWidth) / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            let x = originX + CGFloat(index) * (NookBarVisualizer.barWidth + NookBarVisualizer.barSpacing)
            bar.bounds = CGRect(x: 0, y: 0, width: NookBarVisualizer.barWidth, height: restingHeight(applied, index: index))
            bar.position = CGPoint(x: x + NookBarVisualizer.barWidth / 2, y: bounds.midY)
        }
        CATransaction.commit()
    }

    private func applyMotion(_ state: Applied) {
        for (index, bar) in bars.enumerated() {
            bar.removeAnimation(forKey: Self.loopKey)
            guard state.isMoving else { continue }
            let low = max(NookBarVisualizer.minimumBarHeight, state.height * NookBarVisualizer.lowLevel)
            let loop = CABasicAnimation(keyPath: "bounds.size.height")
            loop.fromValue = low
            loop.toValue = max(low, state.height)
            loop.duration = Self.riseDuration(index: index)
            loop.autoreverses = true
            loop.repeatCount = .infinity
            loop.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            // Starts each bar at a different point of its loop.
            loop.timeOffset = loop.duration * 2 * (Double(index) * 0.37).truncatingRemainder(dividingBy: 1)
            bar.add(loop, forKey: Self.loopKey)
        }
    }
}

/// True while a view is drawn into a picture offscreen (a test, the README
/// art). Layers are not drawn there, and a view that moves on a layer draws
/// a still copy of itself in SwiftUI.
private struct NookDrawsStillKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var nookDrawsStill: Bool {
        get { self[NookDrawsStillKey.self] }
        set { self[NookDrawsStillKey.self] = newValue }
    }
}

// MARK: - Opened island

/// Now-playing card for the Nook page: art, title, scrub bar, transport and
/// a speaker button. Each widget size has its own layout. The grid sets the
/// frame; small and large fill it, medium keeps its natural height.
struct NookMediaCard: View {
    var nook: NookModel

    @Environment(\.nookWidgetSize) private var size
    /// True while the speaker list has the card.
    @State private var isPickingSpeaker = false

    static let height: CGFloat = 96

    /// Height at each size. Small rows always use the grid’s shared height.
    static func height(for size: NookWidgetSize) -> CGFloat {
        switch size {
        case .small: NookWidgetLayout.smallHeight
        case .medium: height
        case .large: 160
        }
    }

    var body: some View {
        if isPickingSpeaker {
            speakerBody
        } else if let state = nook.nowPlaying {
            switch size {
            case .small: smallPlayingBody(state)
            case .medium: playingBody(state)
            case .large: largePlayingBody(state)
            }
        } else {
            switch size {
            case .small: smallEmptyBody
            case .medium: emptyBody
            case .large: largeEmptyBody
            }
        }
    }

    // MARK: Medium

    private func playingBody(_ state: NowPlayingState) -> some View {
        HStack(spacing: 14) {
            NookAlbumArtView(image: nook.artwork, size: 64, cornerRadius: 12)
                .shadow(color: .black.opacity(0.4), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 5) {
                Text(state.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text([state.artist, state.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)

                NookScrubBar(state: state, media: nook.media)
            }

            HStack(spacing: 4) {
                transportButton("backward.fill") { nook.media.previousTrack() }
                transportButton(state.isPlaying ? "pause.fill" : "play.fill", size: 16) { nook.media.togglePlayPause() }
                transportButton("forward.fill") { nook.media.nextTrack() }
                speakerButton()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var emptyBody: some View {
        HStack(spacing: 12) {
            NookAlbumArtView(image: nil, size: 40, cornerRadius: 9)
            VStack(alignment: .leading, spacing: 3) {
                Text("Nothing playing")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(emptyMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    // MARK: Small

    /// Art and text on top, transport along the bottom. No progress bar.
    private func smallPlayingBody(_ state: NowPlayingState) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                NookAlbumArtView(image: nook.artwork, size: 48, cornerRadius: 9)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(Self.subtitle(state))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            transportRow(state, iconSize: 12, playSize: 14, hit: 28, spacing: 18)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(cardBackground)
    }

    private var smallEmptyBody: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
            Text("Nothing playing")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(cardBackground)
    }

    // MARK: Large

    /// Big art on the left; title, artist, progress and transport on the right.
    private func largePlayingBody(_ state: NowPlayingState) -> some View {
        HStack(spacing: 16) {
            NookAlbumArtView(image: nook.artwork, size: 120, cornerRadius: 14)
                .shadow(color: .black.opacity(0.4), radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(Self.subtitle(state))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                NookScrubBar(state: state, media: nook.media)
                transportRow(state, iconSize: 14, playSize: 18, hit: 36, spacing: 12)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var largeEmptyBody: some View {
        HStack(spacing: 16) {
            NookAlbumArtView(image: nil, size: 72, cornerRadius: 14)
            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing playing")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(emptyMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    // MARK: Shared

    private var cardBackground: some View {
        NookCardBackground()
    }

    private var emptyMessage: String {
        nook.media.isAvailable
            ? "Play something in Spotify or Music and it shows up here."
            : (nook.media.lastError ?? "Media helper is starting…")
    }

    /// Artist, or the album when the player gives no artist.
    private static func subtitle(_ state: NowPlayingState) -> String {
        [state.artist, state.album].compactMap { $0 }.first { !$0.isEmpty } ?? ""
    }

    /// Previous, play or pause, next, centered in the space it is given,
    /// with the speaker button at the trailing edge.
    private func transportRow(_ state: NowPlayingState, iconSize: CGFloat, playSize: CGFloat, hit: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            transportButton("backward.fill", size: iconSize, hit: hit) { nook.media.previousTrack() }
            transportButton(state.isPlaying ? "pause.fill" : "play.fill", size: playSize, hit: hit) { nook.media.togglePlayPause() }
            transportButton("forward.fill", size: iconSize, hit: hit) { nook.media.nextTrack() }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) { speakerButton(hit: hit) }
    }

    private func speakerButton(hit: CGFloat = 26) -> some View {
        NookSpeakerButton(outputs: nook.audioOutputs, hit: hit) {
            // Edit mode drags the card; it must not open the list too.
            guard !nook.isEditingLayout else { return }
            nook.audioOutputs.beginPicking()
            withMotion(Motion.contentSwap) { isPickingSpeaker = true }
        }
    }

    /// The speaker list, in the card's own frame at every size.
    private var speakerBody: some View {
        NookSpeakerList(outputs: nook.audioOutputs) {
            withMotion(Motion.contentSwap) { isPickingSpeaker = false }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
        // The next time the page opens, the player is back.
        .onDisappear { isPickingSpeaker = false }
    }

    private func transportButton(_ systemName: String, size: CGFloat = 13, hit: CGFloat = 30, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: hit, height: hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
