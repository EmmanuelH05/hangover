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

/// Decoded GIFs by file URL, so the same file is never decoded twice (the
/// island and the Settings preview show the same one). The file is read off
/// the main thread; the `NSImage` is created on the main actor.
@MainActor
enum GIFImageCache {
    private static let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 8
        return cache
    }()

    static func cachedImage(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    /// The decoded image for `url`: from the cache, or read and decoded once.
    /// Nil when the file cannot be read or is not an image.
    static func image(for url: URL) async -> NSImage? {
        if let cached = cachedImage(for: url) { return cached }
        let data = await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url)
        }.value
        // A second request for the same file may have finished while this one read.
        if let cached = cachedImage(for: url) { return cached }
        guard let data, let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// Plays an animated GIF through `NSImageView`, which handles frame timing
/// natively. SwiftUI's `Image` only ever shows the first frame. A new URL
/// keeps the old image on screen until the new one has loaded.
struct AnimatedGIFView: NSViewRepresentable {
    let url: URL
    var isAnimating: Bool

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageAlignment = .alignCenter
        view.animates = isAnimating
        view.canDrawSubviewsIntoLayer = true
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        context.coordinator.show(url, in: view)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        context.coordinator.show(url, in: view)
        if view.animates != isAnimating {
            view.animates = isAnimating
        }
    }

    static func dismantleNSView(_ view: NSImageView, coordinator: Coordinator) {
        coordinator.cancel()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        private var url: URL?
        private var loadTask: Task<Void, Never>?

        /// Shows `url` in `view`: at once when it is cached, otherwise after
        /// it has loaded. Does nothing when `url` is already the one shown.
        func show(_ url: URL, in view: NSImageView) {
            guard self.url != url else { return }
            self.url = url
            loadTask?.cancel()
            loadTask = nil

            if let cached = GIFImageCache.cachedImage(for: url) {
                view.image = cached
                return
            }
            loadTask = Task { [weak self, weak view] in
                let image = await GIFImageCache.image(for: url)
                guard !Task.isCancelled, let self, let view, self.url == url, let image else { return }
                view.image = image
            }
        }

        func cancel() {
            loadTask?.cancel()
            loadTask = nil
        }
    }
}

/// Four bars bouncing on a timeline while playing, flat while paused.
struct NookBarVisualizer: View {
    var isPlaying: Bool
    var barCount: Int = 4
    var height: CGFloat = 16
    var color: Color = .white
    /// False pauses the timeline while the visualizer is hidden.
    var isLive: Bool = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !isPlaying || !isLive)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    let phase = t * (2.6 + Double(index) * 0.45) + Double(index) * 1.3
                    let level = isPlaying ? (0.35 + 0.65 * abs(sin(phase))) : 0.25
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(color.opacity(isPlaying ? 0.9 : 0.4))
                        .frame(width: 3, height: max(3, height * level))
                }
            }
            .frame(height: height, alignment: .center)
        }
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
