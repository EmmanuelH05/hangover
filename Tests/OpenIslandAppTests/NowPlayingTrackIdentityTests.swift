import Foundation
import Testing
@testable import OpenIslandApp

/// What tells one track from the next. Spotify hands out a new
/// `contentItemIdentifier` on every play, pause and seek of the same song
/// (read from its stream on 2026-10-12), which made a pause count as the
/// next track in the tour and gave the scrub bar a new track on every seek.
@Suite struct NowPlayingTrackIdentityTests {
    private static func song(
        identifier: String?,
        title: String = "Song",
        artist: String? = "Band",
        album: String? = "Record",
        isPlaying: Bool = true
    ) -> NowPlayingState {
        NookMediaSamples.track(identifier: identifier, title: title, artist: artist, album: album, isPlaying: isPlaying)
    }

    @Test func aNewPlayerIdentifierOnTheSameSongIsTheSameTrack() {
        let before = Self.song(identifier: "9f697a", isPlaying: false)
        let after = Self.song(identifier: "08b151", isPlaying: true)
        #expect(before.trackIdentity == after.trackIdentity)
        #expect(NookSeekTracker.trackKey(before) == NookSeekTracker.trackKey(after))
        #expect(Self.song(identifier: nil).trackIdentity == before.trackIdentity)
    }

    @Test func aTitleAnArtistOrAnAlbumThatChangesIsAnotherTrack() {
        let song = Self.song(identifier: "one")
        #expect(song.trackIdentity != Self.song(identifier: "one", title: "Other").trackIdentity)
        #expect(song.trackIdentity != Self.song(identifier: "one", artist: "Another band").trackIdentity)
        #expect(song.trackIdentity != Self.song(identifier: "one", album: "Another record").trackIdentity)
        // Two fields that run together must not read as one.
        let split = Self.song(identifier: "one", title: "Song Band", artist: nil)
        let joined = Self.song(identifier: "one", title: "Song", artist: "Band")
        #expect(split.trackIdentity != joined.trackIdentity)
    }

    @Test func playAndPauseOnSpotifyTickOnlyPlayOrPauseInTheTour() {
        var progress = OnboardingFeatureProgress()
        // The page comes up on a paused song.
        progress.note(OnboardingFeatureReading(music: OnboardingMusicReading(Self.song(identifier: "9f697a", isPlaying: false))))
        #expect(progress.done.isEmpty)
        // Play, then pause: Spotify reports a new identifier each time.
        progress.note(OnboardingFeatureReading(music: OnboardingMusicReading(Self.song(identifier: "08b151", isPlaying: true))))
        progress.note(OnboardingFeatureReading(music: OnboardingMusicReading(Self.song(identifier: "f43780", isPlaying: false))))
        #expect(progress.done == [.musicPlay])
        // The next song is what ticks the second button.
        progress.note(OnboardingFeatureReading(music: OnboardingMusicReading(Self.song(identifier: "ad586e", title: "Next song"))))
        #expect(progress.done == [.musicPlay, .musicNext])
    }
}
