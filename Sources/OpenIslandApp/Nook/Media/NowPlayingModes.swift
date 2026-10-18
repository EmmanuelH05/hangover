import Foundation

/// Shuffle, as a player reports it through the adapter (`MRAShuffleMode`).
/// A player that reports none has no value at all: nothing is guessed.
enum NowPlayingShuffle: Int, CaseIterable, Sendable {
    case off = 1
    case albums = 2
    case tracks = 3

    var isOn: Bool { self != .off }

    /// What one press of the shuffle button asks the player for.
    var toggled: NowPlayingShuffle { isOn ? .off : .tracks }

    /// The string key of what the button says about itself.
    var labelKey: String { isOn ? "nook.media.shuffle.on" : "nook.media.shuffle" }
}

/// Repeat, as a player reports it through the adapter (`MRARepeatMode`).
enum NowPlayingRepeat: Int, CaseIterable, Sendable {
    case off = 1
    case track = 2
    case playlist = 3

    var isOn: Bool { self != .off }

    /// What one press of the repeat button asks the player for: everything,
    /// then this one song, then off again.
    var next: NowPlayingRepeat {
        switch self {
        case .off: .playlist
        case .playlist: .track
        case .track: .off
        }
    }

    var symbol: String { self == .track ? "repeat.1" : "repeat" }

    var labelKey: String {
        switch self {
        case .off: "nook.media.repeat"
        case .playlist: "nook.media.repeat.all"
        case .track: "nook.media.repeat.one"
        }
    }
}

/// Whether the music card shows the shuffle and repeat buttons. The release
/// app does not: they are parked there. On 2026-10-12 Spotify answered "cannot
/// be switched" for everything that was played, with its own two buttons greyed
/// out, which left ours dimmed for good. The dev copy shows them, to try them
/// against real players before a release does. Where they are not offered
/// nothing shows them, and no player is ever sent an Apple Event.
enum NookModeButtonsOffer {
    /// What a test sets to draw the buttons. A task-local, which keeps tests
    /// that run side by side from changing each other's answer.
    @TaskLocal static var override: Bool?

    /// Offered in the dev copy only, the way Link to MP3 is
    /// (`NookLinkAudioOffer`), for a look before any release has it. The
    /// 2026-10-12 reading was one context: on 2026-10-18 Spotify answered
    /// "shuffling enabled: true" for a playlist, and the card already dims the
    /// two while the player says they cannot be switched (`modesUnavailable`).
    static var isOffered: Bool { override ?? isOffered(bundleID: Bundle.main.bundleIdentifier) }

    /// The rule itself, for a bundle identifier: the dev copy and nothing else.
    static func isOffered(bundleID: String?) -> Bool {
        NookLinkAudioOffer.isOffered(bundleID: bundleID)
    }
}
