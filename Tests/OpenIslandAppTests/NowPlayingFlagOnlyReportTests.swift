import Foundation
import Testing
@testable import OpenIslandApp

/// A player can send the playing flag by itself and the position a moment
/// later. Spotify does (read from its stream on 2026-10-12: seven reports
/// in a row that changed nothing but `playing`). Such a report has no clock
/// of its own: read as one, a pause sits where the last position report
/// left the song, and a resume leaps ahead by the length of the pause.
@MainActor
@Suite struct NowPlayingFlagOnlyReportTests {
    private static let start = NookMediaSamples.start

    @Test func aReportThatOnlyFlipsThePlayingFlagIsNotAClockJump() {
        let playing = NookMediaSamples.track(elapsed: 10)
        var paused = playing
        paused.isPlaying = false
        let aMinuteOn = Self.start.addingTimeInterval(60)
        #expect(!NookSeekTracker.clockJumped(from: playing, to: paused, now: aMinuteOn))
        #expect(!NookSeekTracker.clockJumped(from: paused, to: playing, now: aMinuteOn))
    }

    @Test func aBlamedTrackStaysBlamedThroughAPauseThatBringsNoPosition() {
        let live = NookMediaSamples.track(elapsed: 10)
        var tracker = NookSeekTracker()
        tracker.begin(target: 120, state: live, now: Self.start)
        tracker.observe(live, now: Self.start.addingTimeInterval(3.2))
        #expect(tracker.refusesSeek(live))

        var paused = live
        paused.isPlaying = false
        tracker.observe(paused, previous: live, now: Self.start.addingTimeInterval(60))
        #expect(tracker.refusesSeek(live))
    }

    @Test func aPauseSitsWhereTheSongIsAndAResumeDoesNotLeap() {
        let service = MediaRemoteService(commandLauncher: { _ in true })
        let playing = NookMediaSamples.track(elapsed: 10)
        service.apply(playing, now: Self.start)

        // A minute in, the flag arrives alone: the clock is the old one.
        var paused = playing
        paused.isPlaying = false
        let aMinuteOn = Self.start.addingTimeInterval(60)
        service.apply(paused, now: aMinuteOn)
        #expect(service.state?.isPlaying == false)
        #expect(service.state?.position(at: aMinuteOn) == 70)
        // It stays there while paused.
        #expect(service.state?.position(at: aMinuteOn.addingTimeInterval(5)) == 70)

        // Ten seconds later the flag flips back, alone again.
        let resumedAt = aMinuteOn.addingTimeInterval(10)
        service.apply(playing, now: resumedAt)
        #expect(service.state?.isPlaying == true)
        #expect(service.state?.position(at: resumedAt) == 70)
        #expect(service.state?.position(at: resumedAt.addingTimeInterval(2)) == 72)

        // The position report that follows is taken as it comes.
        let report = NookMediaSamples.track(elapsed: 71, at: resumedAt.addingTimeInterval(1))
        service.apply(report, now: resumedAt.addingTimeInterval(1))
        #expect(service.state?.elapsedTime == 71)
        #expect(service.state?.timestamp == resumedAt.addingTimeInterval(1))
    }

    @Test func aReportThatChangesSomethingElseKeepsTheClockInHand() {
        let service = MediaRemoteService(commandLauncher: { _ in true })
        let playing = NookMediaSamples.track(elapsed: 10)
        service.apply(playing, now: Self.start)
        var paused = playing
        paused.isPlaying = false
        let aMinuteOn = Self.start.addingTimeInterval(60)
        service.apply(paused, now: aMinuteOn)

        // The picture arrives next, still with the old clock.
        var withArt = paused
        withArt.artworkData = Data([1, 2, 3])
        service.apply(withArt, now: aMinuteOn.addingTimeInterval(1))
        #expect(service.state?.artworkData == Data([1, 2, 3]))
        #expect(service.state?.position(at: aMinuteOn.addingTimeInterval(1)) == 70)

        // The same report twice changes nothing.
        let before = service.state
        service.apply(withArt, now: aMinuteOn.addingTimeInterval(2))
        #expect(service.state == before)
    }

    @Test func anotherTrackOrAnotherAppTakesItsReportAsItComes() {
        let service = MediaRemoteService(commandLauncher: { _ in true })
        let playing = NookMediaSamples.track(elapsed: 10)
        service.apply(playing, now: Self.start)
        // The next song with the same clock values is not this song's clock.
        let next = NookMediaSamples.track(title: "Next song", isPlaying: false, elapsed: 10)
        service.apply(next, now: Self.start.addingTimeInterval(60))
        #expect(service.state?.position(at: Self.start.addingTimeInterval(60)) == 10)
        // Nothing playing forgets the clock.
        service.apply(nil, now: Self.start.addingTimeInterval(61))
        service.apply(playing, now: Self.start.addingTimeInterval(62))
        #expect(service.state == playing)
    }

    @Test func theAlbumArtIsKeptUnderTheTrackNotThePlayersIdentifier() {
        var before = NookMediaSamples.track(identifier: "9f697a", isPlaying: false)
        var after = NookMediaSamples.track(identifier: "08b151", isPlaying: true)
        #expect(before.artworkKey == nil)
        before.artworkData = Data([1, 2, 3])
        after.artworkData = Data([1, 2, 3])
        #expect(before.artworkKey != nil)
        #expect(before.artworkKey == after.artworkKey)
        // Another picture for the same song is another entry.
        after.artworkData = Data([1, 2, 3, 4])
        #expect(before.artworkKey != after.artworkKey)
        #expect(NookMediaSamples.track(title: "Other").artworkKey == nil)
    }
}
