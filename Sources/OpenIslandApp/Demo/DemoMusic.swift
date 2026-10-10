import AppKit
import Foundation

/// One sample track (D51). Made-up names, in the words the Settings preview
/// already uses for its first one.
struct DemoTrack: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    /// The hue of the cover, 0 to 1.
    let hue: Double

    static let all = [
        DemoTrack(title: "Midnight Drive", artist: "Neon Coast", album: "Afterglow", duration: 214, hue: 0.92),
        DemoTrack(title: "Paper Lanterns", artist: "Hollow Pines", album: "Small Hours", duration: 187, hue: 0.08),
        DemoTrack(title: "Slow Tide", artist: "Marlow", album: "Low Light", duration: 241, hue: 0.55),
        DemoTrack(title: "Window Seat", artist: "The Quiet Parade", album: "Long Way Home", duration: 198, hue: 0.36),
    ]
}

/// A cover drawn in code, as PNG bytes: the way a player hands over art.
@MainActor
enum DemoArtwork {
    static func png(hue: Double) -> Data? {
        let image = NSImage(size: NSSize(width: 240, height: 240), flipped: false) { rect in
            let top = NSColor(hue: hue, saturation: 0.62, brightness: 1.0, alpha: 1)
            let bottom = NSColor(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.85, brightness: 0.62, alpha: 1)
            NSGradient(colors: [top, bottom])?.draw(in: rect, angle: -45)
            NSColor.white.withAlphaComponent(0.2).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.3, dy: rect.height * 0.3)).fill()
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

/// The sample player behind the music widget (D51). It plays, pauses and
/// skips among a few sample tracks and sends nothing outside the app. The
/// clock is handed in, which lets a test move it.
@MainActor
final class DemoPlayer {
    /// The bundle identifier the sample reports. No player app has it.
    static let bundleIdentifier = "app.hangover.demo-player"

    let tracks: [DemoTrack]
    private let covers: [Data?]
    private let now: () -> Date
    private(set) var index: Int
    private(set) var isPlaying: Bool
    /// Where the track was at `anchor`.
    private var elapsedAtAnchor: TimeInterval
    private var anchor: Date

    init(
        tracks: [DemoTrack] = DemoTrack.all,
        startsPlaying: Bool = true,
        elapsed: TimeInterval = 38,
        now: @escaping () -> Date = Date.init
    ) {
        self.tracks = tracks
        self.covers = tracks.map { DemoArtwork.png(hue: $0.hue) }
        self.now = now
        index = 0
        isPlaying = startsPlaying
        elapsedAtAnchor = elapsed
        anchor = now()
    }

    var track: DemoTrack { tracks[index] }

    /// How far into the track it is, right now.
    var position: TimeInterval {
        guard isPlaying else { return elapsedAtAnchor }
        return min(track.duration, elapsedAtAnchor + now().timeIntervalSince(anchor))
    }

    /// What the system would report: the same value the adapter stream gives.
    var state: NowPlayingState {
        var state = NowPlayingState(payload: [
            "bundleIdentifier": Self.bundleIdentifier,
            "title": track.title,
            "artist": track.artist,
            "album": track.album,
            "playing": isPlaying,
            "playbackRate": isPlaying ? 1.0 : 0.0,
            "duration": track.duration,
            "elapsedTime": elapsedAtAnchor,
            "contentItemIdentifier": "demo-track-\(index)",
        ])!
        state.timestamp = anchor
        state.artworkData = covers[index]
        state.artworkMimeType = "image/png"
        return state
    }

    /// The commands the music widget sends. Others do nothing.
    func handle(_ command: MediaRemoteCommand) {
        switch command {
        case .play: setPlaying(true)
        case .pause, .stop: setPlaying(false)
        case .togglePlayPause: setPlaying(!isPlaying)
        case .nextTrack: move(to: (index + 1) % tracks.count)
        case .previousTrack:
            // Like a real player: a few seconds in, "previous" starts the
            // track again, and near its start it goes back one.
            if position > 3 {
                move(to: index)
            } else {
                move(to: (index + tracks.count - 1) % tracks.count)
            }
        case .skipFifteenSeconds: seek(to: position + 15)
        case .goBackFifteenSeconds: seek(to: position - 15)
        case .toggleShuffle, .toggleRepeat: break
        }
    }

    func seek(to seconds: TimeInterval) {
        elapsedAtAnchor = min(max(0, seconds), track.duration)
        anchor = now()
    }

    private func setPlaying(_ playing: Bool) {
        guard playing != isPlaying else { return }
        elapsedAtAnchor = position
        anchor = now()
        isPlaying = playing
    }

    private func move(to next: Int) {
        index = next
        elapsedAtAnchor = 0
        anchor = now()
    }
}
