import Foundation

/// What the scrub bar on the now-playing card can do for the current track.
enum NookScrubMode: Equatable, Sendable {
    /// The player reports a length and takes seeks: the bar can be dragged.
    case seekable
    /// The player reports a length but ignored a seek: the bar only shows
    /// how far along the track is.
    case progressOnly
    /// No length to measure against (a live stream, a player that reports
    /// nothing): no bar at all.
    case hidden
}

/// Pure rules for the scrub bar. A plain enum and not part of a view, which
/// keeps them callable from tests without the main actor.
enum NookScrubRules {
    static func mode(duration: TimeInterval?, refusesSeek: Bool) -> NookScrubMode {
        guard let duration, duration.isFinite, duration > 0 else { return .hidden }
        return refusesSeek ? .progressOnly : .seekable
    }

    /// How far along the bar a pointer at `x` is, from 0 to 1.
    static func fraction(atX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(max(x / width, 0), 1))
    }

    /// The position the bar draws. A drag wins, then a seek the player has
    /// not answered yet, then the player's own clock.
    static func position(
        reported: TimeInterval?,
        held: TimeInterval?,
        dragFraction: Double?,
        duration: TimeInterval
    ) -> TimeInterval {
        if let dragFraction { return min(max(dragFraction, 0), 1) * duration }
        return min(max(held ?? reported ?? 0, 0), duration)
    }

    /// "1:05", or "1:02:03" from an hour on.
    static func clock(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(max(0, seconds).rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// Follows the seeks the scrub bar sends. It holds the bar at the asked
/// position until the player reports it, and it remembers the tracks whose
/// player ignored a seek, which turns their bar into a plain progress line.
///
/// MediaRemote has no "can seek" flag. The only way to learn that a player
/// refuses is to ask once and watch its clock. A track is blamed only when
/// its clock carried on as if nothing was asked, and it is forgiven as soon
/// as its clock jumps: a player that buffers for longer than the answer
/// window, or lands on a keyframe some seconds off, did take the seek.
struct NookSeekTracker: Equatable, Sendable {
    /// A player that took the seek reports a position this close to it. A
    /// clock that moves by more than this between two reports has jumped.
    static let tolerance: TimeInterval = 3
    /// How long a player gets to answer before the seek counts as ignored.
    static let answerWindow: TimeInterval = 3
    static let maxRemembered = 32

    struct Pending: Equatable, Sendable {
        var track: String
        var target: TimeInterval
        var sentAt: Date
        var wasPlaying: Bool
    }

    private(set) var pending: Pending?
    /// Tracks whose player ignored a seek, oldest first.
    private(set) var refusing: [String] = []

    /// One key per track: a browser tab that will not seek must not switch
    /// seeking off for every other page in that browser.
    static func trackKey(_ state: NowPlayingState) -> String {
        "\(state.bundleIdentifier)|\(state.itemIdentifier ?? state.title)"
    }

    func refusesSeek(_ state: NowPlayingState) -> Bool {
        refusing.contains(Self.trackKey(state))
    }

    mutating func begin(target: TimeInterval, state: NowPlayingState, now: Date) {
        pending = Pending(
            track: Self.trackKey(state),
            target: max(0, target),
            sentAt: now,
            wasPlaying: state.isPlaying
        )
    }

    /// Where the bar should sit while the player has not answered: the
    /// asked position, moving on with the clock when the track plays.
    func heldPosition(for state: NowPlayingState, now: Date) -> TimeInterval? {
        guard let pending, pending.track == Self.trackKey(state) else { return nil }
        let drift = pending.wasPlaying ? max(0, now.timeIntervalSince(pending.sentAt)) : 0
        let position = pending.target + drift
        if let duration = state.duration, duration > 0 { return min(position, duration) }
        return position
    }

    /// True when the same track's clock jumped between two reports: the
    /// new report is more than the tolerance away from where the earlier
    /// one would have the track by now. Pausing, resuming and plain playing
    /// do not jump. A playing report with no timestamp cannot be carried
    /// forward and proves nothing.
    static func clockJumped(from old: NowPlayingState, to new: NowPlayingState, now: Date) -> Bool {
        guard trackKey(old) == trackKey(new) else { return false }
        if old.isPlaying, old.timestamp == nil { return false }
        guard let before = old.position(at: now), let after = new.position(at: now) else { return false }
        return abs(after - before) > tolerance
    }

    /// Checks what the player reports now. Call it for every new state
    /// with the state it replaces, and once more, with no `previous`, when
    /// the answer window is over.
    mutating func observe(_ state: NowPlayingState?, previous: NowPlayingState? = nil, now: Date) {
        guard pending != nil || !refusing.isEmpty else { return }
        var jumped = false
        if let state, let previous, Self.clockJumped(from: previous, to: state, now: now) {
            jumped = true
            // A clock that jumps can be moved: the track is no longer blamed
            // for a seek it answered late, or far from where it was asked.
            let key = Self.trackKey(state)
            refusing.removeAll { $0 == key }
        }
        guard let pending else { return }
        // Another track, or nothing playing: the seek no longer applies.
        guard let state, Self.trackKey(state) == pending.track else {
            self.pending = nil
            return
        }
        if jumped {
            self.pending = nil
            return
        }
        let waited = now.timeIntervalSince(pending.sentAt)
        let expected = pending.target + (pending.wasPlaying && state.isPlaying ? max(0, waited) : 0)
        if let position = state.position(at: now) {
            if abs(position - expected) <= Self.tolerance {
                self.pending = nil
                return
            }
            // Asked for the very end, and the track is back at its start:
            // it ran out and began again, which is an answer too.
            if let duration = state.duration, duration > 0,
               pending.target >= duration - Self.tolerance, position <= Self.tolerance {
                self.pending = nil
                return
            }
        }
        guard waited >= Self.answerWindow else { return }
        self.pending = nil
        guard !refusing.contains(pending.track) else { return }
        refusing.append(pending.track)
        if refusing.count > Self.maxRemembered {
            refusing.removeFirst(refusing.count - Self.maxRemembered)
        }
    }
}
