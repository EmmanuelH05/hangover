import Foundation
import Testing
@testable import OpenIslandApp

/// The commands a test's stand-in for the adapter was asked to run.
@MainActor
private final class SeekCommandLog {
    var sent: [[String]] = []
}

/// The scrub bar on the now-playing card: when it can be dragged, when it
/// only shows progress, when it is not there, and how a seek is followed.
@Suite struct NookScrubBarTests {
    private static let start = NookMediaSamples.start

    // MARK: What the bar can do

    @Test func aTrackWithNoLengthGetsNoBar() {
        #expect(NookScrubRules.mode(duration: nil, refusesSeek: false) == .hidden)
        #expect(NookScrubRules.mode(duration: 0, refusesSeek: false) == .hidden)
        #expect(NookScrubRules.mode(duration: -4, refusesSeek: false) == .hidden)
        #expect(NookScrubRules.mode(duration: .infinity, refusesSeek: false) == .hidden)
        #expect(NookScrubRules.mode(duration: .nan, refusesSeek: false) == .hidden)
    }

    @Test func aPlayerThatIgnoredASeekGetsAProgressLineAndOthersCanBeDragged() {
        #expect(NookScrubRules.mode(duration: 200, refusesSeek: true) == .progressOnly)
        #expect(NookScrubRules.mode(duration: 200, refusesSeek: false) == .seekable)
    }

    @Test func thePointerMapsToAFractionOfTheBarAndStaysInside() {
        let half: Double = 0.5
        let none: Double = 0
        let all: Double = 1
        #expect(NookScrubRules.fraction(atX: 100, width: 200) == half)
        #expect(NookScrubRules.fraction(atX: -30, width: 200) == none)
        #expect(NookScrubRules.fraction(atX: 900, width: 200) == all)
        #expect(NookScrubRules.fraction(atX: 50, width: 0) == none)
    }

    @Test func aDragWinsThenAnUnansweredSeekThenThePlayersClock() {
        let dragged: TimeInterval = 150
        let held: TimeInterval = 90
        let reported: TimeInterval = 12
        let end: TimeInterval = 200
        let zero: TimeInterval = 0
        #expect(NookScrubRules.position(reported: 12, held: 90, dragFraction: 0.75, duration: 200) == dragged)
        #expect(NookScrubRules.position(reported: 12, held: 90, dragFraction: nil, duration: 200) == held)
        #expect(NookScrubRules.position(reported: 12, held: nil, dragFraction: nil, duration: 200) == reported)
        #expect(NookScrubRules.position(reported: 999, held: nil, dragFraction: nil, duration: 200) == end)
        #expect(NookScrubRules.position(reported: nil, held: nil, dragFraction: nil, duration: 200) == zero)
    }

    @Test func timesReadAsMinutesAndSecondsAndGainHoursFromAnHourOn() {
        #expect(NookScrubRules.clock(0) == "0:00")
        #expect(NookScrubRules.clock(65.9) == "1:05")
        #expect(NookScrubRules.clock(3599) == "59:59")
        #expect(NookScrubRules.clock(3723) == "1:02:03")
        #expect(NookScrubRules.clock(-5) == "0:00")
        #expect(NookScrubRules.clock(.infinity) == "0:00")
    }

    @Test func theThumbStaysInsideTheBar() {
        let atStart: CGFloat = 0
        let middle: CGFloat = 95.5
        let atEnd: CGFloat = 191
        #expect(NookScrubBarLayout.thumbOffset(progress: 0, width: 200) == atStart)
        #expect(NookScrubBarLayout.thumbOffset(progress: 0.5, width: 200) == middle)
        #expect(NookScrubBarLayout.thumbOffset(progress: 1, width: 200) == atEnd)
        #expect(NookScrubBarLayout.thumbOffset(progress: 4, width: 200) == atEnd)
    }

    // MARK: Following a seek

    @Test func aSeekThePlayerTookIsForgottenAndTheTrackStaysSeekable() {
        let track = NookMediaSamples.track(elapsed: 10)
        var tracker = NookSeekTracker()
        tracker.begin(target: 120, state: track, now: Self.start)

        // Half a second later the player reports the new position.
        let answered = NookMediaSamples.track(elapsed: 120, at: Self.start.addingTimeInterval(0.5))
        tracker.observe(answered, now: Self.start.addingTimeInterval(0.5))

        #expect(tracker.pending == nil)
        #expect(!tracker.refusesSeek(track))
    }

    @Test func aSeekThePlayerIgnoredTurnsThatTrackIntoAProgressLine() {
        let track = NookMediaSamples.track(elapsed: 10)
        var tracker = NookSeekTracker()
        tracker.begin(target: 120, state: track, now: Self.start)

        // Still inside the answer window: nothing is decided.
        tracker.observe(track, now: Self.start.addingTimeInterval(1))
        #expect(tracker.pending != nil)
        #expect(!tracker.refusesSeek(track))

        // The window is over and the player is where it was.
        tracker.observe(track, now: Self.start.addingTimeInterval(NookSeekTracker.answerWindow))
        #expect(tracker.pending == nil)
        #expect(tracker.refusesSeek(track))
    }

    @Test func oneTrackRefusingDoesNotSwitchSeekingOffForTheWholeApp() {
        let live = NookMediaSamples.track(bundle: "com.google.Chrome", item: "live-stream", elapsed: 10)
        let video = NookMediaSamples.track(bundle: "com.google.Chrome", item: "video", elapsed: 10)
        var tracker = NookSeekTracker()
        tracker.begin(target: 120, state: live, now: Self.start)
        tracker.observe(live, now: Self.start.addingTimeInterval(10))

        #expect(tracker.refusesSeek(live))
        #expect(!tracker.refusesSeek(video))
    }

    @Test func aTrackChangeDropsTheSeekWithoutBlamingEitherTrack() {
        let first = NookMediaSamples.track(item: "one", elapsed: 190)
        let second = NookMediaSamples.track(item: "two", elapsed: 0, at: Self.start.addingTimeInterval(5))
        var tracker = NookSeekTracker()
        tracker.begin(target: 199, state: first, now: Self.start)
        tracker.observe(second, now: Self.start.addingTimeInterval(5))

        #expect(tracker.pending == nil)
        #expect(!tracker.refusesSeek(first))
        #expect(!tracker.refusesSeek(second))

        tracker.begin(target: 50, state: second, now: Self.start.addingTimeInterval(6))
        tracker.observe(nil, now: Self.start.addingTimeInterval(20))
        #expect(tracker.pending == nil)
        #expect(!tracker.refusesSeek(second))
    }

    @Test func theBarHoldsTheAskedPositionUntilThePlayerAnswers() {
        let playing = NookMediaSamples.track(isPlaying: true, elapsed: 10)
        var tracker = NookSeekTracker()
        tracker.begin(target: 120, state: playing, now: Self.start)

        let atOnce: TimeInterval = 120
        let twoSecondsOn: TimeInterval = 122
        #expect(tracker.heldPosition(for: playing, now: Self.start) == atOnce)
        #expect(tracker.heldPosition(for: playing, now: Self.start.addingTimeInterval(2)) == twoSecondsOn)
        // Another track is not held anywhere.
        #expect(tracker.heldPosition(for: NookMediaSamples.track(item: "other"), now: Self.start) == nil)

        // A paused track stays put.
        let paused = NookMediaSamples.track(isPlaying: false, elapsed: 10)
        tracker.begin(target: 60, state: paused, now: Self.start)
        let still: TimeInterval = 60
        #expect(tracker.heldPosition(for: paused, now: Self.start.addingTimeInterval(2)) == still)

        // Never past the end.
        tracker.begin(target: 199, state: playing, now: Self.start)
        let end: TimeInterval = 200
        #expect(tracker.heldPosition(for: playing, now: Self.start.addingTimeInterval(30)) == end)
    }

    @Test func aPausedTrackThatTookTheSeekIsNotBlamed() {
        let paused = NookMediaSamples.track(isPlaying: false, elapsed: 10)
        var tracker = NookSeekTracker()
        tracker.begin(target: 80, state: paused, now: Self.start)
        let answered = NookMediaSamples.track(isPlaying: false, elapsed: 80, at: Self.start.addingTimeInterval(1))
        // Checked late: a paused track's clock does not move on.
        tracker.observe(answered, now: Self.start.addingTimeInterval(8))

        #expect(tracker.pending == nil)
        #expect(!tracker.refusesSeek(paused))
    }

    // MARK: Tracks that took the seek in their own way

    @Test func aPlayerThatAnswersAfterTheWindowIsForgiven() {
        // A stream that buffers: nothing for four seconds, then the new place.
        let stream = NookMediaSamples.track(duration: 3600, elapsed: 10)
        var tracker = NookSeekTracker()
        tracker.begin(target: 1800, state: stream, now: Self.start)

        // The window ends with the old clock still running: blamed for now.
        tracker.observe(stream, now: Self.start.addingTimeInterval(3.2))
        #expect(tracker.refusesSeek(stream))

        let landed = NookMediaSamples.track(duration: 3600, elapsed: 1800, at: Self.start.addingTimeInterval(4))
        tracker.observe(landed, previous: stream, now: Self.start.addingTimeInterval(4))
        #expect(tracker.pending == nil)
        #expect(!tracker.refusesSeek(stream))
    }

    @Test func aPlayerThatLandsFarFromTheAskedPlaceStillTookTheSeek() {
        // A video that snaps to a keyframe six seconds before the target.
        let video = NookMediaSamples.track(elapsed: 10)
        var tracker = NookSeekTracker()
        tracker.begin(target: 120, state: video, now: Self.start)

        let snapped = NookMediaSamples.track(elapsed: 114, at: Self.start.addingTimeInterval(0.5))
        tracker.observe(snapped, previous: video, now: Self.start.addingTimeInterval(0.5))
        #expect(tracker.pending == nil)

        // The check at the end of the window finds nothing left to blame.
        tracker.observe(snapped, now: Self.start.addingTimeInterval(3.2))
        #expect(!tracker.refusesSeek(video))
    }

    @Test func aDragToTheVeryEndThatRestartsTheTrackIsNotBlamed() {
        // Repeat one: asked for the end, the track begins again.
        let song = NookMediaSamples.track(elapsed: 100)
        var tracker = NookSeekTracker()
        tracker.begin(target: 200, state: song, now: Self.start)
        let restarted = NookMediaSamples.track(elapsed: 0, at: Self.start.addingTimeInterval(0.4))
        tracker.observe(restarted, previous: song, now: Self.start.addingTimeInterval(0.4))
        #expect(tracker.pending == nil)
        tracker.observe(restarted, now: Self.start.addingTimeInterval(3.2))
        #expect(!tracker.refusesSeek(song))

        // From the first second the restart is too small a move to count as
        // a jump. Being back at the start is the answer.
        let early = NookMediaSamples.track(elapsed: 1)
        tracker.begin(target: 200, state: early, now: Self.start)
        tracker.observe(restarted, previous: early, now: Self.start.addingTimeInterval(0.4))
        #expect(tracker.pending == nil)
        #expect(!tracker.refusesSeek(early))
    }

    @MainActor
    @Test func aSeekThatCouldNotBeSentBlamesNoTrack() {
        // Paused, which keeps the position free of the test's wall clock.
        let track = NookMediaSamples.track(isPlaying: false, elapsed: 10)
        let failing = MediaRemoteService(commandLauncher: { _ in false })
        failing.apply(track)
        failing.seek(to: 120)
        #expect(failing.seekTracker.pending == nil)
        #expect(failing.seekTracker.heldPosition(for: track, now: Date()) == nil)

        let log = SeekCommandLog()
        let working = MediaRemoteService(commandLauncher: { arguments in
            log.sent.append(arguments)
            return true
        })
        working.apply(track)
        working.seek(to: 120)
        let asked: TimeInterval = 120
        #expect(working.seekTracker.pending?.target == asked)
        #expect(log.sent == [["seek", "120000000"]])

        // The stream's next report is compared with the one it replaces.
        working.apply(NookMediaSamples.track(isPlaying: false, elapsed: 114))
        #expect(working.seekTracker.pending == nil)
        #expect(!working.seekTracker.refusesSeek(track))
    }

    @Test func aBlamedTrackThatOnlyPlaysPausesAndResumesStaysAProgressLine() {
        let live = NookMediaSamples.track(elapsed: 10)
        var tracker = NookSeekTracker()
        tracker.begin(target: 120, state: live, now: Self.start)
        tracker.observe(live, now: Self.start.addingTimeInterval(3.2))
        #expect(tracker.refusesSeek(live))

        // A fresh report five seconds on, exactly where the clock would be.
        let playing = NookMediaSamples.track(elapsed: 15, at: Self.start.addingTimeInterval(5))
        tracker.observe(playing, previous: live, now: Self.start.addingTimeInterval(5))
        // Paused at twenty seconds in.
        let paused = NookMediaSamples.track(isPlaying: false, elapsed: 20, at: Self.start.addingTimeInterval(10))
        tracker.observe(paused, previous: playing, now: Self.start.addingTimeInterval(10))
        // Resumed a minute later from the same place.
        let resumed = NookMediaSamples.track(elapsed: 20, at: Self.start.addingTimeInterval(70))
        tracker.observe(resumed, previous: paused, now: Self.start.addingTimeInterval(70))

        #expect(tracker.refusesSeek(live))
    }

    @Test func aClockJumpIsOnlyReadFromReportsThatCanBeCompared() {
        let now = Self.start.addingTimeInterval(30)
        let one = NookMediaSamples.track(item: "one", elapsed: 10)
        let two = NookMediaSamples.track(item: "two", elapsed: 150)
        // Another track is a track change, not a jump.
        #expect(!NookSeekTracker.clockJumped(from: one, to: two, now: now))

        // Playing with no timestamp: where it would be by now is unknown.
        var unstamped = NookMediaSamples.track(elapsed: 10)
        unstamped.timestamp = nil
        var later = NookMediaSamples.track(elapsed: 90)
        later.timestamp = nil
        #expect(!NookSeekTracker.clockJumped(from: unstamped, to: later, now: now))

        // No position at all proves nothing either.
        let silent = NookMediaSamples.track(elapsed: nil)
        #expect(!NookSeekTracker.clockJumped(from: silent, to: one, now: now))

        // The same track, far from where its clock would be.
        let moved = NookMediaSamples.track(item: "one", elapsed: 150, at: now)
        #expect(NookSeekTracker.clockJumped(from: one, to: moved, now: now))
    }

    @Test func onlyTheNewestRefusalsAreRemembered() {
        var tracker = NookSeekTracker()
        let count = NookSeekTracker.maxRemembered + 5
        for index in 0..<count {
            let track = NookMediaSamples.track(item: "track-\(index)", elapsed: 10)
            tracker.begin(target: 120, state: track, now: Self.start)
            tracker.observe(track, now: Self.start.addingTimeInterval(10))
        }

        #expect(tracker.refusing.count == NookSeekTracker.maxRemembered)
        #expect(!tracker.refusesSeek(NookMediaSamples.track(item: "track-0")))
        #expect(tracker.refusesSeek(NookMediaSamples.track(item: "track-\(count - 1)")))
    }

    @Test func aTrackWithoutAnItemIdentifierIsKeyedByItsTitle() {
        let one = NookMediaSamples.track(item: nil, title: "First")
        let two = NookMediaSamples.track(item: nil, title: "Second")
        #expect(NookSeekTracker.trackKey(one) != NookSeekTracker.trackKey(two))
        #expect(NookSeekTracker.trackKey(one) == "com.spotify.client|First")
    }
}
