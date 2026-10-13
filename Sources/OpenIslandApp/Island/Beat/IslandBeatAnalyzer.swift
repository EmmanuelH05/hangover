import Accelerate
import Foundation

/// The limits the beat glow keeps (D56). None is a setting.
enum IslandBeatLimits {
    /// The least time between two full flashes. Flashes follow the hits,
    /// kicks, snares and claps alike, and this gap is only long enough
    /// that a fast roll reads as hits and not as a smear.
    static let flashGap: TimeInterval = 0.07
    /// For a user who asked macOS to dim flashing lights: the most full
    /// flashes in any one second, and the least time between two of them.
    static let dimmedFlashesPerSecond = 3
    static let dimmedFlashGap: TimeInterval = 0.25
    /// The least time between two punches of the reach.
    static let punchGap: TimeInterval = 0.09
    /// The least time between two shimmers.
    static let shimmerGap: TimeInterval = 0.05
    /// A shimmer moves the brightness by at most this share of its range.
    /// It is a flicker on top of the glow and never a flash.
    static let shimmerCeiling: Float = 0.15
    /// The most times a second the main actor may ever hear a level. A hit
    /// does not wait for its turn.
    static let framesPerSecond: Double = 30
    /// The least time between two level frames, whatever is asked for.
    static let frameInterval: TimeInterval = 1 / framesPerSecond
    /// How often a level is handed over in practice. Core Animation draws
    /// the frames between two of them, which is why half the limit is
    /// enough.
    static let levelFramesPerSecond: Double = 15
    static let levelInterval: TimeInterval = 1 / levelFramesPerSecond
}

/// A hit, named for what the light does with it (D56).
enum IslandBeatHit: Equatable, Sendable {
    /// A low hit, a kick or an 808 starting: the light punches out in its
    /// next color and comes all the way back. The frame's `low` says how
    /// hard it was.
    case kick
    /// A snare or a clap: a flash, and the next color unless a punch is
    /// still on its way back.
    case snare
    /// A small shimmer.
    case hat
}

/// What one chunk of sound came to.
struct IslandBeatSummary: Equatable, Sendable {
    /// The highest level of each band inside the chunk, 0 to 1.
    var low: Float = 0
    var mid: Float = 0
    var high: Float = 0
    /// How many hits of each kind fell inside the chunk.
    var snares = 0
    var kicks = 0
    var hats = 0
    /// True when every sample of the chunk was exactly zero.
    var isSilent = true
    /// How hard the hardest low hit inside the chunk was, 0 to 1, and
    /// zero when there was none.
    var punch: Float = 0

    /// The one hit the light is told about: a punch before a flash, and a
    /// flash before a shimmer. A kick with a clap on it is the kick.
    var hit: IslandBeatHit? {
        if kicks > 0 { return .kick }
        if snares > 0 { return .snare }
        return hats > 0 ? .hat : nil
    }

    /// This chunk and the one after it as one.
    func followed(by next: IslandBeatSummary) -> IslandBeatSummary {
        IslandBeatSummary(
            low: max(low, next.low),
            mid: max(mid, next.mid),
            high: max(high, next.high),
            snares: snares + next.snares,
            kicks: kicks + next.kicks,
            hats: hats + next.hats,
            isSilent: isSilent && next.isSilent,
            punch: max(punch, next.punch)
        )
    }
}

/// Finds what a song is doing in a stream of mono samples (D56). A plain
/// value: it keeps no sound, only a few running numbers, and equal input
/// gives equal output.
///
/// The mix is split into three bands: low (up to 200 Hz, the kick and the
/// 808), mid (250 Hz to 2.5 kHz, the snare and the clap) and high (5 kHz
/// and up, the hats). Each hop, one device buffer of about 11 ms, gives
/// one loudness for each band, and two things are read from it.
///
/// The level is the band's envelope against its own recent peak, which
/// fades over about four seconds. A held 808 holds the low level up: it
/// does not sag while the sound stays loud.
///
/// The hit is an onset: the hop where the band jumps over the hops just
/// before it. It is judged against the band's own usual jumps and its
/// recent peak, never against a slow mean of its energy, which a long bass
/// note would pull up until the kicks under it were lost.
///
/// What moves what: a low hit, a kick or an 808 starting, is a punch of
/// the light and its next color, a mid hit is a flash, and a hat is a
/// small shimmer. The levels are what a hit is judged against. By the
/// owner's decision they hold nothing out: a long 808 is one punch at its
/// start.
///
/// The sums over samples are Accelerate's. No loop here runs once a sample,
/// which is what keeps a debug build as cheap as a release one.
struct IslandBeatAnalyzer: Sendable {
    /// The edges of the three bands, in Hz. The low band's edge is one
    /// filter deep, which leaves a kick's punch in it: the first moments
    /// of a kick sit above the note of a long 808, and they are what lets
    /// the kick be told from it. The mid band's edges are two filters
    /// deep, 24 dB an octave, which keeps a kick's body out of the middle.
    static let lowEdge: Double = 200
    static let midEdges: (Double, Double) = (250, 2_500)
    static let highEdge: Double = 5_000
    /// The length of one loudness reading when the device's buffer cannot
    /// be the hop: 512 frames at 48 kHz.
    static let hop: TimeInterval = 512.0 / 48_000
    /// A device buffer this size is one hop. Outside it the usual hop is used.
    static let hopSizes = 64...1_024
    /// How long a band's envelope takes to fall.
    static let fall: TimeInterval = 0.25
    /// How long a band's recent peak takes to fade.
    static let peakFall: TimeInterval = 4
    /// How long the long peak takes to fade: the floor for a quiet passage.
    static let longFall: TimeInterval = 30
    /// How far the usual jump may move in one second, as a share of the peak.
    static let usualDrift: Double = 0.2
    /// How hard a band must be hit: the jump as a share of the band's
    /// recent peak, and as a share of what it was just playing. A kick's
    /// numbers are low on purpose: under a long 808 a kick adds little to
    /// the bass, and it must still be caught. How far the light goes for
    /// it is the bass level's to say, which keeps a small one small.
    static let punch: (share: Float, rise: Float) = (0.08, 0.15)
    static let flash: (share: Float, rise: Float) = (0.3, 0.5)
    static let shimmer: (share: Float, rise: Float) = (0.15, 0.3)
    /// How far a punch goes for the weakest low hit that counts, and how
    /// fast that grows with the hit. A hit a third of the band's peak or
    /// more goes all the way.
    static let leastPunch: Float = 0.55
    static let punchGrowth: Float = 1.5
    /// The rate assumed when the device reports none.
    static let fallbackSampleRate: Double = 48_000

    let sampleRate: Double
    /// Samples in one hop.
    let hopSize: Int
    /// Hops that must pass between two flashes, two punches, two shimmers.
    let flashGapHops: Int
    let punchGapHops: Int
    let shimmerGapHops: Int

    private var lowPass: IslandBiquad
    private var midHighPass: IslandBiquad
    private var midHighPassAgain: IslandBiquad
    private var midLowPass: IslandBiquad
    private var midLowPassAgain: IslandBiquad
    private var highPass: IslandBiquad
    private let lowTuning: IslandBeatBand.Tuning
    private let midTuning: IslandBeatBand.Tuning
    private let highTuning: IslandBeatBand.Tuning
    private let mixPeakFall: Float

    /// The last two samples of the mix, which carry the filters from one
    /// pass to the next.
    private var lastInput: (Float, Float) = (0, 0)
    private var energy: (mix: Float, low: Float, mid: Float, high: Float) = (0, 0, 0, 0)
    private var hopFill = 0
    private var mixPeak: Float = 0
    private var hopsSinceFlash: Int
    private var hopsSincePunch: Int
    private var hopsSinceShimmer: Int

    private(set) var low = IslandBeatBand()
    private(set) var mid = IslandBeatBand()
    private(set) var high = IslandBeatBand()

    /// The low band's level after the last finished hop, 0 to 1.
    var level: Float { low.level }

    /// `bufferFrames` is the size of the device's buffers. When it is a
    /// usual size, one buffer is one hop, and a hit is known the moment
    /// the buffer that holds it has been read.
    init(sampleRate: Double, bufferFrames: Int? = nil) {
        let rate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : Self.fallbackSampleRate
        self.sampleRate = rate
        if let bufferFrames, Self.hopSizes.contains(bufferFrames) {
            hopSize = bufferFrames
        } else {
            hopSize = max(1, Int((rate * Self.hop).rounded()))
        }
        let hopTime = Double(hopSize) / rate
        // Rounded up: a gap is never shorter than its limit.
        func hops(_ time: TimeInterval) -> Int { max(1, Int((time / hopTime).rounded(.up))) }
        flashGapHops = hops(IslandBeatLimits.flashGap)
        punchGapHops = hops(IslandBeatLimits.punchGap)
        shimmerGapHops = hops(IslandBeatLimits.shimmerGap)
        hopsSinceFlash = flashGapHops
        hopsSincePunch = punchGapHops
        hopsSinceShimmer = shimmerGapHops

        lowPass = .lowPass(Self.lowEdge, rate: rate)
        midHighPass = .highPass(Self.midEdges.0, rate: rate)
        midHighPassAgain = .highPass(Self.midEdges.0, rate: rate)
        midLowPass = .lowPass(Self.midEdges.1, rate: rate)
        midLowPassAgain = .lowPass(Self.midEdges.1, rate: rate)
        highPass = .highPass(Self.highEdge, rate: rate)

        func remains(after time: TimeInterval) -> Float { Float(exp(-hopTime / time)) }
        func tuning(mixShare: Float, ownShare: Float, hitShare: Float) -> IslandBeatBand.Tuning {
            IslandBeatBand.Tuning(
                fall: remains(after: Self.fall),
                peakFall: remains(after: Self.peakFall),
                longFall: remains(after: Self.longFall),
                usualStep: Float(Self.usualDrift * hopTime),
                mixShare: mixShare,
                ownShare: ownShare,
                hitShare: hitShare
            )
        }
        lowTuning = tuning(mixShare: 0.25, ownShare: 0.15, hitShare: 0.1)
        midTuning = tuning(mixShare: 0.25, ownShare: 0.1, hitShare: 0.08)
        // The hats are a small part of any mix. They are judged among
        // themselves, and what they move is small.
        highTuning = tuning(mixShare: 0.05, ownShare: 0, hitShare: 0.02)
        mixPeakFall = remains(after: Self.peakFall)
    }

    /// Takes the next `frames` mono samples, which the caller has put at
    /// `scratch.samples`, and says what they came to. At most
    /// `IslandBeatScratch.capacity` frames are read.
    mutating func process(frames: Int, in scratch: IslandBeatScratch) -> IslandBeatSummary {
        let count = min(max(frames, 0), IslandBeatScratch.capacity)
        guard count > 0 else { return IslandBeatSummary() }
        var loudest: Float = 0
        vDSP_maxmgv(scratch.samples, 1, &loudest, vDSP_Length(count))

        scratch.input[0] = lastInput.0
        scratch.input[1] = lastInput.1
        lowPass.run(scratch.input, into: scratch.low, count: count)
        // The mid band's four filters take turns in its two blocks. Each
        // filter keeps its own last two samples, and sets them at the
        // front of the block it writes before it runs.
        midHighPass.run(scratch.input, into: scratch.midWork, count: count)
        midHighPassAgain.run(scratch.midWork, into: scratch.mid, count: count)
        midLowPass.run(scratch.mid, into: scratch.midWork, count: count)
        midLowPassAgain.run(scratch.midWork, into: scratch.mid, count: count)
        highPass.run(scratch.input, into: scratch.high, count: count)
        lastInput = (scratch.input[count], scratch.input[count + 1])
        if !lastInput.0.isFinite || !lastInput.1.isFinite { lastInput = (0, 0) }

        // One pass over the hops inside this chunk: with one buffer a hop
        // that is a single turn.
        var summary = IslandBeatSummary(isSilent: loudest == 0)
        var offset = 0
        while offset < count {
            let taken = min(hopSize - hopFill, count - offset)
            let length = vDSP_Length(taken)
            var sum: Float = 0
            vDSP_svesq(scratch.samples + offset, 1, &sum, length)
            energy.mix += sum
            vDSP_svesq(scratch.low + 2 + offset, 1, &sum, length)
            energy.low += sum
            vDSP_svesq(scratch.mid + 2 + offset, 1, &sum, length)
            energy.mid += sum
            vDSP_svesq(scratch.high + 2 + offset, 1, &sum, length)
            energy.high += sum
            hopFill += taken
            offset += taken
            if hopFill == hopSize {
                finishHop(into: &summary)
                energy = (0, 0, 0, 0)
                hopFill = 0
            }
        }
        return summary
    }

    /// The same for an array, which is what a test has. It makes working
    /// memory of its own, which the sound queue never does.
    mutating func process(_ samples: [Float]) -> IslandBeatSummary {
        let scratch = IslandBeatScratch()
        var total = IslandBeatSummary()
        var offset = 0
        while offset < samples.count {
            let count = min(IslandBeatScratch.capacity, samples.count - offset)
            samples.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                scratch.samples.update(from: base + offset, count: count)
            }
            total = total.followed(by: process(frames: count, in: scratch))
            offset += count
        }
        return total
    }

    /// One hop: a loudness for the mix and for each band, their levels and
    /// their hits.
    private mutating func finishHop(into summary: inout IslandBeatSummary) {
        if hopsSinceFlash < flashGapHops { hopsSinceFlash += 1 }
        if hopsSincePunch < punchGapHops { hopsSincePunch += 1 }
        if hopsSinceShimmer < shimmerGapHops { hopsSinceShimmer += 1 }

        // A hop with a sample that is no number is dropped whole. Read
        // into the peaks, an infinite loudness would stay in them for
        // good and every level after it would be nothing.
        guard energy.mix.isFinite, energy.low.isFinite, energy.mid.isFinite, energy.high.isFinite else { return }

        let size = Float(hopSize)
        let mix = (energy.mix / size).squareRoot()
        mixPeak = max(mix, mixPeak * mixPeakFall)
        let kick = low.read(
            loudness: (energy.low / size).squareRoot(), mixLoudness: mix, mixPeak: mixPeak, tuning: lowTuning
        )
        let snare = mid.read(
            loudness: (energy.mid / size).squareRoot(), mixLoudness: mix, mixPeak: mixPeak, tuning: midTuning
        )
        let hat = high.read(
            loudness: (energy.high / size).squareRoot(), mixLoudness: mix, mixPeak: mixPeak, tuning: highTuning
        )
        summary.low = max(summary.low, low.level)
        summary.mid = max(summary.mid, mid.level)
        summary.high = max(summary.high, high.level)

        // A low hit is a punch, as far as it was hard. A long 808 is one
        // hit, where it starts: nothing after that is a jump.
        if kick.isAtLeast(share: Self.punch.share, rise: Self.punch.rise), hopsSincePunch >= punchGapHops {
            hopsSincePunch = 0
            summary.kicks += 1
            summary.punch = max(summary.punch, min(1, Self.leastPunch + Self.punchGrowth * kick.share))
        }
        // A mid hit is a flash. A weak one is nothing.
        if snare.isAtLeast(share: Self.flash.share, rise: Self.flash.rise), hopsSinceFlash >= flashGapHops {
            hopsSinceFlash = 0
            summary.snares += 1
        }
        // A hat is a shimmer, however hard it is hit.
        if hat.isAtLeast(share: Self.shimmer.share, rise: Self.shimmer.rise), hopsSinceShimmer >= shimmerGapHops {
            hopsSinceShimmer = 0
            summary.hats += 1
        }
    }
}

/// What the light is handed each time something changes. The glow and the
/// lasers read the same four values.
struct IslandBeatFrame: Equatable, Sendable {
    /// 0 to 1. The bass level, and in a frame whose hit is a kick, how
    /// hard the kick was: that is how far its punch goes.
    var low: Double
    var mid: Double
    var high: Double
    /// Nil when only the levels moved.
    var hit: IslandBeatHit?

    init(low: Double = 0, mid: Double = 0, high: Double = 0, hit: IslandBeatHit? = nil) {
        self.low = low
        self.mid = mid
        self.high = high
        self.hit = hit
    }
}

/// Gathers what the sound queue found and hands on one level frame every
/// `interval`, which is never shorter than `IslandBeatLimits.frameInterval`
/// (D56). A hit does not wait in that line: a flash or a punch is handed
/// on at once, and the gaps between hits keep those few. A shimmer waits
/// for the limit at most. A plain value: the caller says what time it is.
struct IslandBeatThrottle: Sendable {
    /// The least time between two level frames.
    let interval: TimeInterval

    private var lastFrameTime: TimeInterval?
    private var held = IslandBeatSummary()

    init(interval: TimeInterval = IslandBeatLimits.levelInterval) {
        self.interval = max(interval, IslandBeatLimits.frameInterval)
    }

    /// Adds a chunk's summary. Returns a frame when the chunk holds a
    /// flash or a punch, or enough time has passed since the last frame,
    /// and nil otherwise. What a nil kept is part of the next frame: its
    /// highest levels and its hit.
    mutating func take(_ summary: IslandBeatSummary, at time: TimeInterval) -> IslandBeatFrame? {
        held = held.followed(by: summary)
        // A hair of slack: times that are sums of buffer lengths land a
        // rounding error short of the interval now and then.
        let since = lastFrameTime.map { time - $0 + 0.000_001 }
        let isAtOnce = summary.snares > 0 || summary.kicks > 0
        let isDue = since.map { $0 >= (held.hats > 0 ? IslandBeatLimits.frameInterval : interval) } ?? true
        guard isDue || isAtOnce else { return nil }
        lastFrameTime = time
        let frame = IslandBeatFrame(
            low: Double(held.kicks > 0 ? held.punch : held.low),
            mid: Double(held.mid), high: Double(held.high), hit: held.hit
        )
        held = IslandBeatSummary()
        return frame
    }
}

/// How long a hit takes to reach the light, and how long to hold it when
/// the speaker is slower than that (D56).
enum IslandBeatTiming {
    /// A hit is known by the end of the second hop of it at the latest.
    static let hopsToDetect = 2
    /// A hit goes to the main actor at once.
    static let beatHandOff: TimeInterval = 0
    /// A hit is shown with no rise.
    static let beatRise: TimeInterval = 0
    /// The longest a hit is ever held for a slow speaker.
    static let longestHold: TimeInterval = 0.4
    /// A hold shorter than this is not worth a timer.
    static let shortestHold: TimeInterval = 0.02

    /// The time from a hit's first sample to the light at its peak, from
    /// the parts that add up to it.
    static func pipelineDelay(
        sampleRate: Double,
        hopSize: Int,
        hopsToDetect: Int = IslandBeatTiming.hopsToDetect,
        handOff: TimeInterval = IslandBeatTiming.beatHandOff,
        rise: TimeInterval = IslandBeatTiming.beatRise
    ) -> TimeInterval {
        guard sampleRate > 0 else { return handOff + rise }
        return Double(hopSize * hopsToDetect) / sampleRate + handOff + rise
    }

    /// The delay of the usual case: 48 kHz and buffers of 512 frames.
    static let usualPipelineDelay = pipelineDelay(sampleRate: 48_000, hopSize: 512)

    /// How long after the sound leaves the app it leaves the speaker: the
    /// device's own latency, its safety offset, its stream's latency and
    /// one buffer, all in frames of the device's rate.
    static func outputDelay(
        deviceLatency: UInt32,
        safetyOffset: UInt32,
        streamLatency: UInt32,
        bufferFrames: UInt32,
        sampleRate: Double
    ) -> TimeInterval {
        guard sampleRate > 0 else { return 0 }
        let frames = Double(deviceLatency) + Double(safetyOffset) + Double(streamLatency) + Double(bufferFrames)
        return frames / sampleRate
    }

    /// How long to hold a hit before it is shown. A speaker slower than
    /// the pipeline, which is a Bluetooth one, gets the difference, which
    /// makes the light land with the sound. Built-in and wired outputs are
    /// faster than the pipeline and get no hold.
    static func hold(
        outputDelay: TimeInterval,
        pipelineDelay: TimeInterval = IslandBeatTiming.usualPipelineDelay
    ) -> TimeInterval {
        let difference = outputDelay - pipelineDelay
        guard difference.isFinite, difference >= shortestHold else { return 0 }
        return min(difference, longestHold)
    }
}
