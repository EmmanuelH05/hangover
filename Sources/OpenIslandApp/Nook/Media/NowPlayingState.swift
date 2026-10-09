import Foundation

/// Snapshot of what the system "Now Playing" reports, as delivered by the
/// MediaRemote adapter stream. Artwork is kept as raw bytes here so the
/// value stays `Sendable`; the service decodes it into an `NSImage` once.
struct NowPlayingState: Equatable, Sendable {
    var bundleIdentifier: String
    var title: String
    var artist: String?
    var album: String?
    var isPlaying: Bool
    var playbackRate: Double
    /// Track length in seconds, when the player reports one.
    var duration: TimeInterval?
    /// Playback position in seconds at `timestamp`.
    var elapsedTime: TimeInterval?
    /// Wall-clock moment `elapsedTime` was measured.
    var timestamp: Date?
    var artworkData: Data?
    var artworkMimeType: String?
    /// Stable identity for the current item, used to notice track changes.
    var itemIdentifier: String?

    /// Live playback position, extrapolated from the last reported
    /// elapsed time when the player is running.
    func position(at now: Date = Date()) -> TimeInterval? {
        guard let elapsedTime else { return nil }
        guard isPlaying, let timestamp else { return elapsedTime }
        let rate = playbackRate > 0 ? playbackRate : 1
        let position = elapsedTime + now.timeIntervalSince(timestamp) * rate
        if let duration, duration > 0 { return min(position, duration) }
        return position
    }

    func progress(at now: Date = Date()) -> Double? {
        guard let duration, duration > 0, let position = position(at: now) else { return nil }
        return max(0, min(1, position / duration))
    }

    /// Builds a state from the merged adapter payload. Returns nil when the
    /// mandatory keys are missing, which is how the adapter signals "nothing
    /// is playing".
    init?(payload: [String: Any]) {
        guard let bundleIdentifier = payload["bundleIdentifier"] as? String,
              let title = payload["title"] as? String else {
            return nil
        }
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        artist = payload["artist"] as? String
        album = payload["album"] as? String
        isPlaying = (payload["playing"] as? Bool) ?? false
        playbackRate = (payload["playbackRate"] as? Double) ?? (isPlaying ? 1 : 0)
        duration = payload["duration"] as? Double
        elapsedTime = payload["elapsedTime"] as? Double
        if let stamp = payload["timestamp"] as? String {
            timestamp = Self.parseTimestamp(stamp)
        }
        if let base64 = payload["artworkData"] as? String {
            artworkData = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters])
        }
        artworkMimeType = payload["artworkMimeType"] as? String
        itemIdentifier = (payload["contentItemIdentifier"] as? String)
            ?? (payload["uniqueIdentifier"] as? String)
    }

    private static func parseTimestamp(_ stamp: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle().parse(stamp) {
            return date
        }
        return try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(stamp)
    }
}

/// MediaRemote command IDs accepted by `mediaremote-adapter.pl send N`.
enum MediaRemoteCommand: Int, Sendable {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case stop = 3
    case nextTrack = 4
    case previousTrack = 5
    case toggleShuffle = 6
    case toggleRepeat = 7
    case goBackFifteenSeconds = 12
    case skipFifteenSeconds = 13
}
