import Foundation

/// The numbers a show keeps to (D56). None is a setting. Every time here
/// stands in for a count of beats or bars: a beat clock replaces them.
enum IslandLaserShow {
    /// Under this, a level is no sound, and after this long of it the
    /// lasers are dark.
    static let idleFloor = 0.06
    static let idleAfter: TimeInterval = 2
    /// Under this, the low band is near empty.
    static let emptyBass = 0.15
    /// The bass must have been this present, on a slow average, for its
    /// going to mean anything: a song with a kick now and then has gaps
    /// all the time.
    static let steadyBass = 0.3
    static let bassMemory: TimeInterval = 3
    /// A dip in the bass longer than this is a break in it, and the bass
    /// is steady once it has gone this long with no break. One held note
    /// a bar with rests between is never steady, which keeps its rests
    /// from reading as the bass going.
    static let bassBreak: TimeInterval = 0.6
    static let steadyFor: TimeInterval = 4
    /// The mids or the highs carry on when their level, smoothed over
    /// this long, is at least this.
    static let carryOn = 0.2
    static let smoothing: TimeInterval = 0.3
    /// How long the bass must be gone before the beams go dark, and the
    /// longest they stay dark for it.
    static let gapBeforeBlackout: TimeInterval = 1
    static let longestBlackout: TimeInterval = 8
    /// The beams must have been dark this long for the bass coming back
    /// to be a drop.
    static let leastDark: TimeInterval = 0.3
    /// The bass is back without a hit once its level is this.
    static let fullBass = 0.5
    /// A return is a drop when the low hit is at least this hard and the
    /// mids or the highs are at least this loud with it.
    static let dropPunch = 0.9
    static let dropBody = 0.5
    /// A look shows for at least this long, and a phrase is this long.
    static let leastHold: TimeInterval = 8
    static let phrase: TimeInterval = 16
    /// A low hit this hard or harder may end a phrase.
    static let strongHit = 0.8
    /// The colors change after this many phrases.
    static let phrasesAPalette = 4
    /// The burst of a drop: how long the beams take to light from the
    /// middle outward, how long they hold, and how long each takes to
    /// come back.
    static let burstSpread: TimeInterval = 0.08
    static let burstHold: TimeInterval = 0.4
    static let burstFall: TimeInterval = 0.14
    static let burstLength = burstSpread + burstHold + burstSpread + burstFall
    /// How long a low hit's push, a white flash and a hat's flicker take
    /// to let go.
    static let pushFall: TimeInterval = 0.14
    static let flashFall: TimeInterval = 0.12
    static let shimmerFall: TimeInterval = 0.08
    /// A low hit pushes the beams out by this share of their length.
    static let pushLength = 0.15
    /// One breath, and one wave across the fan: two bars, in seconds. A
    /// quiet look moves for one of these and is still again.
    static let slowPeriod: TimeInterval = 4
}

/// When a look gives way to the next (D56). A plain rule on time for now:
/// a beat clock that counts 32 beats replaces it.
enum IslandLaserPhrase {
    /// True when the look that has shown for `shownFor` seconds ends now:
    /// never before it has had its least hold, and at the first strong
    /// hit once a phrase has passed.
    static func turns(shownFor: TimeInterval, isStrongHit: Bool) -> Bool {
        guard shownFor >= IslandLaserShow.leastHold else { return false }
        return shownFor >= IslandLaserShow.phrase && isStrongHit
    }
}

/// Watches for the bass going and for silence (D56), with slow averages
/// of what the song's bands are doing. A plain value fed frames and a
/// clock.
struct IslandLaserGate: Equatable, Sendable {
    /// How much bass there has been over the last few seconds, 0 to 1.
    private(set) var bassPresence = 0.0
    /// The louder of the mids and the highs, smoothed.
    private(set) var rest = 0.0
    private var bassGoneSince: TimeInterval?
    /// Since when the bass has had no break.
    private var unbrokenSince: TimeInterval?
    private var wasSteady = false
    private var quietSince: TimeInterval?
    private var lastTime: TimeInterval?

    mutating func read(_ frame: IslandBeatFrame, at time: TimeInterval) {
        // A frame after a long stop counts for a second at most.
        let passed = lastTime.map { min(max(time - $0, 0), 1) } ?? 0
        lastTime = time
        // A low hit is bass, however low the level had fallen.
        let low = frame.hit == .kick ? 1 : Self.held(frame.low)
        let others = max(Self.held(frame.mid), Self.held(frame.high))

        if low >= IslandLaserShow.emptyBass {
            bassGoneSince = nil
            if unbrokenSince == nil { unbrokenSince = time }
        } else {
            let since = bassGoneSince ?? time
            if bassGoneSince == nil {
                bassGoneSince = time
                wasSteady = false
            }
            if time - since > IslandLaserShow.bassBreak, let began = unbrokenSince {
                // The dip is a break now. The gap counts when there was
                // plenty of bass before it, with no break in it.
                wasSteady = bassPresence >= IslandLaserShow.steadyBass
                    && since - began >= IslandLaserShow.steadyFor
                unbrokenSince = nil
            }
        }
        bassPresence += (low - bassPresence) * (1 - exp(-passed / IslandLaserShow.bassMemory))
        rest += (others - rest) * (1 - exp(-passed / IslandLaserShow.smoothing))

        if max(low, others) >= IslandLaserShow.idleFloor {
            quietSince = nil
        } else if quietSince == nil {
            quietSince = time
        }
    }

    /// How long the bass has been gone, and 0 while it is here.
    func bassGap(at time: TimeInterval) -> TimeInterval {
        bassGoneSince.map { max(time - $0, 0) } ?? 0
    }

    /// True when the gap is one that counts: the bass was steady before
    /// it, and the mids or the highs carry on through it.
    var isArmed: Bool {
        wasSteady && rest >= IslandLaserShow.carryOn
    }

    /// How long everything has been under the floor, and 0 while there
    /// is sound.
    func quiet(at time: TimeInterval) -> TimeInterval {
        quietSince.map { max(time - $0, 0) } ?? 0
    }

    private static func held(_ level: Double) -> Double {
        level.isFinite ? min(max(level, 0), 1) : 0
    }
}

/// What a show has on, as places and names: which look, which of the
/// four hues is the base and which the accent, and for the Odd Even which
/// group is lit. The stage turns it into beams.
struct IslandLaserPicture: Equatable, Sendable {
    var look: IslandLaserLook
    var base: Int
    var accent: Int
    var litGroup = 0
}

/// What the director asks of the beams.
enum IslandLaserCue: Equatable, Sendable {
    /// Cut to this picture: a new look, or the look coming out of the dark.
    case show(IslandLaserPicture)
    /// A low hit inside the look: longer and brighter at once, as far as
    /// the hit was hard, and back.
    case push(IslandLaserPicture, strength: Double)
    /// A snare or a clap: white at once, and then the picture, whose two
    /// colors have changed places.
    case flash(IslandLaserPicture)
    /// A hat: a small flicker of the whole picture.
    case shimmer(Double)
    /// A quiet look moves once: one breath, or one wave across the fan.
    case stir(IslandLaserPicture)
    /// No beams: the bass is gone, or nothing plays.
    case dark
    /// The drop: every beam of the picture at full length in white, lit
    /// from the middle outward.
    case burst(IslandLaserPicture)
}

/// Runs a song's show (D56). It sits between the analyzer and the beams
/// and owns the look and the colors. A hit only moves what the look
/// already shows: brightness, length and shimmer. The look changes on a
/// phrase, and the colors on a drop or after four phrases.
///
/// A plain value fed frames and a clock: the same frames at the same
/// times give the same cues.
struct IslandLaserDirector: Equatable, Sendable {
    enum Section: Equatable, Sendable {
        /// Nothing plays.
        case idle
        /// The song is going: the groove's looks.
        case groove
        /// The bass went and the rest carried on: darkness, since then.
        case blackout(since: TimeInterval)
        /// The bass is back with everything else: the burst, until then.
        case burst(until: TimeInterval)
        /// The bass stayed away: the quiet looks.
        case lull
    }

    let program: IslandLaserProgram
    /// How often it may flash. The stage sets it from the system's "Dim
    /// flashing lights".
    var flashRule = IslandFlashRule.followsHits

    private(set) var section = Section.idle
    /// Where in the program's groove the show is.
    private(set) var lookIndex = 0
    private(set) var lullIndex = 0
    private(set) var paletteIndex = 0
    /// True while a snare has the base and the accent changed over.
    private(set) var isSwapped = false
    private(set) var litGroup = 0
    /// Phrases since the colors last changed.
    private(set) var phrases = 0
    private(set) var blackouts = 0
    private(set) var drops = 0

    private var gate = IslandLaserGate()
    private var lookBegan: TimeInterval = 0
    private var liftEnds: TimeInterval = -.infinity
    private var stirEnds: TimeInterval = -.infinity
    private var lastDrop: TimeInterval = -.infinity
    /// When the flashes of the last second were, oldest first.
    private(set) var flashLog: [TimeInterval]

    /// `flashLog` is what was flashed just before this show began, by the
    /// show of the song before it or by the other mode: the limit on
    /// flashes counts across the change.
    init(program: IslandLaserProgram, flashLog: [TimeInterval] = []) {
        self.program = program
        self.flashLog = flashLog.sorted()
    }

    /// Adds flashes that something else made to the ones this show counts.
    mutating func carry(flashes: [TimeInterval]) {
        flashLog = Array(Set(flashLog + flashes)).sorted()
    }

    /// True while the show has no beams on.
    var isDark: Bool {
        switch section {
        case .idle, .blackout: true
        case .groove, .burst, .lull: false
        }
    }

    /// What is on, or what comes on when the dark ends.
    var picture: IslandLaserPicture {
        let look: IslandLaserLook = switch section {
        case .lull: program.lulls[lullIndex % program.lulls.count]
        case .idle, .groove, .blackout, .burst: program.looks[lookIndex % program.looks.count]
        }
        let palette = program.palette(paletteIndex)
        return IslandLaserPicture(
            look: look,
            base: isSwapped ? palette.accent : palette.base,
            accent: isSwapped ? palette.base : palette.accent,
            litGroup: litGroup
        )
    }

    /// One frame of the song at `time`, in seconds on the caller's clock.
    /// Returns what the beams are to do now, in order, and nothing for a
    /// frame that changes nothing.
    mutating func follow(_ frame: IslandBeatFrame, at time: TimeInterval) -> [IslandLaserCue] {
        gate.read(frame, at: time)
        if case let .burst(until) = section {
            // Nothing interrupts the burst. When it is over the show is
            // on its largest look.
            guard time >= until else { return [] }
            section = .groove
            lookBegan = time
            return [.show(picture)]
        }
        if gate.quiet(at: time) >= IslandLaserShow.idleAfter {
            guard section != .idle else { return [] }
            section = .idle
            return [.dark]
        }
        switch section {
        case .idle:
            // Sound again: the look the show was on.
            guard gate.quiet(at: time) == 0 else { return [] }
            section = .groove
            lookBegan = time
            return [.show(picture)] + grooveHit(frame, at: time)
        case .groove:
            if gate.bassGap(at: time) >= IslandLaserShow.gapBeforeBlackout, gate.isArmed {
                section = .blackout(since: time)
                blackouts += 1
                return [.dark]
            }
            return grooveHit(frame, at: time)
        case let .blackout(since):
            if let back = bassReturn(frame, at: time) { return back }
            guard time - since >= IslandLaserShow.longestBlackout else { return [] }
            // It gave up waiting: the bass is staying away.
            section = .lull
            lookBegan = time
            stirEnds = time + IslandLaserShow.slowPeriod
            return [.show(picture)]
        case .lull:
            if let back = bassReturn(frame, at: time) { return back }
            return lullHit(frame, at: time)
        case .burst:
            return []
        }
    }

    // MARK: Hits inside a look

    /// A hit in the groove. It moves brightness, length and shimmer. The
    /// one thing more is the phrase: a strong low hit after a phrase's
    /// worth of time brings the next look in with it.
    private mutating func grooveHit(_ frame: IslandBeatFrame, at time: TimeInterval) -> [IslandLaserCue] {
        switch frame.hit {
        case .kick:
            guard mayFlash(at: time) else { return [] }
            let strength = min(max(frame.low, 0), 1)
            liftEnds = time + IslandLaserShow.pushFall
            let isStrong = strength >= IslandLaserShow.strongHit
            if IslandLaserPhrase.turns(shownFor: time - lookBegan, isStrongHit: isStrong) {
                turnPhrase(at: time)
                return [.show(picture), .push(picture, strength: strength)]
            }
            // The Odd Even lights its other group.
            if picture.look.kind == .oddEven { litGroup = 1 - litGroup }
            return [.push(picture, strength: strength)]
        case .snare:
            guard mayFlash(at: time) else { return [] }
            liftEnds = time + IslandLaserShow.flashFall
            isSwapped.toggle()
            return [.flash(picture)]
        case .hat:
            return shimmer(frame, at: time)
        case nil:
            return []
        }
    }

    /// A hit while the bass is away: one color. A quiet look moves once
    /// when it comes on and is still after that, and a snare or a clap
    /// moves it once more: nothing runs with no hit to answer. The quiet
    /// looks take turns a phrase apart.
    private mutating func lullHit(_ frame: IslandBeatFrame, at time: TimeInterval) -> [IslandLaserCue] {
        guard frame.hit == .snare else {
            return frame.hit == .hat ? shimmer(frame, at: time) : []
        }
        if time - lookBegan >= IslandLaserShow.phrase {
            lullIndex = (lullIndex + 1) % program.lulls.count
            lookBegan = time
            stirEnds = time + IslandLaserShow.slowPeriod
            return [.show(picture)]
        }
        // One at a time: a hit during the motion leaves it to finish.
        guard time >= stirEnds else { return [] }
        stirEnds = time + IslandLaserShow.slowPeriod
        return [.stir(picture)]
    }

    private mutating func shimmer(_ frame: IslandBeatFrame, at time: TimeInterval) -> [IslandLaserCue] {
        // Nothing while a push or a flash is fading: it would cut it short.
        guard time >= liftEnds else { return [] }
        return [.shimmer(min(max(frame.high, 0), 1))]
    }

    private mutating func turnPhrase(at time: TimeInterval) {
        lookIndex = (lookIndex + 1) % program.looks.count
        lookBegan = time
        litGroup = 0
        phrases += 1
        if phrases >= IslandLaserShow.phrasesAPalette { changePalette() }
    }

    private mutating func changePalette() {
        paletteIndex += 1
        phrases = 0
        isSwapped = false
    }

    // MARK: The bass gate

    /// The bass coming back, and nil while it is still away. With a hard
    /// low hit and the other bands loud at once, it is the drop: the
    /// burst, the largest look and new colors. Any other way back is only
    /// the groove again. A drop needs the beams to have been dark a
    /// moment, comes once a phrase at most, and is a flash like any
    /// other: when the flash rule has no room for it, there is none.
    private mutating func bassReturn(_ frame: IslandBeatFrame, at time: TimeInterval) -> [IslandLaserCue]? {
        let isHit = frame.hit == .kick
        guard isHit || (frame.low.isFinite && frame.low >= IslandLaserShow.fullBass) else { return nil }
        let wasLull = section == .lull
        var wasDarkEnough = wasLull
        if case let .blackout(since) = section { wasDarkEnough = time - since >= IslandLaserShow.leastDark }
        let isDrop = isHit && frame.low >= IslandLaserShow.dropPunch
            && max(frame.mid, frame.high) >= IslandLaserShow.dropBody
            && wasDarkEnough
            && time - lastDrop >= IslandLaserShow.phrase
            && mayFlash(at: time)
        if isDrop {
            drops += 1
            lastDrop = time
            changePalette()
            lookIndex = program.biggest
            litGroup = 0
            section = .burst(until: time + IslandLaserShow.burstLength)
            return [.burst(picture)]
        }
        // The groove again. After a lull it is on its next look, when
        // the last one had its time.
        if wasLull, time - lookBegan >= IslandLaserShow.leastHold {
            lookIndex = (lookIndex + 1) % program.looks.count
            litGroup = 0
        }
        section = .groove
        lookBegan = time
        return [.show(picture)] + grooveHit(frame, at: time)
    }

    private mutating func mayFlash(at time: TimeInterval) -> Bool {
        flashLog.removeAll { time - $0 >= 1 || time < $0 }
        guard flashRule.allows(at: time, after: flashLog) else { return false }
        flashLog.append(time)
        return true
    }
}
