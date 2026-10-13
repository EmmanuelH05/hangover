import Accelerate
import Foundation

/// The working memory of the sound queue (D56): made once, never grown and
/// used again for every buffer. Nothing is allocated while sound arrives.
///
/// Every block starts with two samples of history, which is the shape
/// `vDSP_deq22` wants, followed by room for `capacity` samples.
final class IslandBeatScratch {
    /// The most frames one pass takes. A larger buffer goes through in
    /// pieces of this size.
    static let capacity = 4_096

    /// The mono mix.
    let input: UnsafeMutablePointer<Float>
    /// The three bands, and a block for the mid band's filters to work in.
    let low: UnsafeMutablePointer<Float>
    let mid: UnsafeMutablePointer<Float>
    let midWork: UnsafeMutablePointer<Float>
    let high: UnsafeMutablePointer<Float>

    /// Where one pass's mono samples go.
    var samples: UnsafeMutablePointer<Float> { input + 2 }

    init() {
        func block() -> UnsafeMutablePointer<Float> {
            let block = UnsafeMutablePointer<Float>.allocate(capacity: Self.capacity + 2)
            block.initialize(repeating: 0, count: Self.capacity + 2)
            return block
        }
        input = block()
        low = block()
        mid = block()
        midWork = block()
        high = block()
    }

    deinit {
        input.deallocate()
        low.deallocate()
        mid.deallocate()
        midWork.deallocate()
        high.deallocate()
    }
}

/// One second order filter in the five numbers `vDSP_deq22` takes, with
/// the two samples that carry it from one pass to the next.
struct IslandBiquad: Sendable {
    let numbers: (Float, Float, Float, Float, Float)
    /// The last two samples this filter put out.
    private(set) var last: (Float, Float) = (0, 0)

    /// A Butterworth low-pass: flat below the cutoff, 12 dB an octave above.
    static func lowPass(_ cutoff: Double, rate: Double) -> IslandBiquad {
        make(cutoff, rate: rate) { cosine in ((1 - cosine) / 2, 1 - cosine, (1 - cosine) / 2) }
    }

    /// A Butterworth high-pass: flat above the cutoff, 12 dB an octave below.
    static func highPass(_ cutoff: Double, rate: Double) -> IslandBiquad {
        make(cutoff, rate: rate) { cosine in ((1 + cosine) / 2, -(1 + cosine), (1 + cosine) / 2) }
    }

    private static func make(
        _ cutoff: Double, rate: Double, feedForward: (Double) -> (Double, Double, Double)
    ) -> IslandBiquad {
        // A cutoff the rate cannot carry is held under it.
        let turn = 2 * Double.pi * min(cutoff, rate * 0.45) / rate
        let alpha = sin(turn) / 2.0.squareRoot()
        let scale = 1 / (1 + alpha)
        let forward = feedForward(cos(turn))
        return IslandBiquad(numbers: (
            Float(forward.0 * scale), Float(forward.1 * scale), Float(forward.2 * scale),
            Float(-2 * cos(turn) * scale), Float((1 - alpha) * scale)
        ))
    }

    /// Runs the filter over `count` samples. Both blocks start with two
    /// samples of history. The input's are the caller's to set: the mix's
    /// own for a first stage, and for a second stage they are the first
    /// stage's, which is what it left there.
    mutating func run(_ input: UnsafePointer<Float>, into output: UnsafeMutablePointer<Float>, count: Int) {
        output[0] = last.0
        output[1] = last.1
        withUnsafePointer(to: numbers) { pointer in
            pointer.withMemoryRebound(to: Float.self, capacity: 5) {
                vDSP_deq22(input, 1, $0, output, 1, vDSP_Length(count))
            }
        }
        last = (output[count], output[count + 1])
        // One sample that is no number would stay in the filter for good
        // and every sample after it would be none either. It is dropped
        // here, and the buffer after this one is read as it should be.
        if !last.0.isFinite || !last.1.isFinite { last = (0, 0) }
    }
}

/// What one band of the sound is doing (D56): how loud it is against its
/// own recent peak, and how hard it was just hit.
struct IslandBeatBand: Sendable {
    /// How a band is read. The numbers are per hop.
    struct Tuning: Sendable {
        /// What is left of the envelope after one hop.
        var fall: Float
        /// What is left of the recent peak after one hop: gone in about
        /// four seconds.
        var peakFall: Float
        /// What is left of the long peak after one hop, which is the floor
        /// a quiet passage is read against.
        var longFall: Float
        /// How far the usual jump moves in one hop, as a share of the peak.
        var usualStep: Float
        /// The band's peak counts for at least this share of the whole
        /// mix's. A band far below the mix reads as quiet, not as full.
        var mixShare: Float
        /// A hit counts only when the band is at least this share of the
        /// mix in that hop. Less than that leaked in from another band.
        var ownShare: Float
        /// A hit counts only when the band is at least this share of the
        /// mix's recent peak. Less than that is the edge of some other
        /// sound in a hop that is nearly empty.
        var hitShare: Float
    }

    /// How hard a band was hit in one hop, measured two ways. Both must be
    /// large for a hit.
    struct Jump: Equatable, Sendable {
        /// The jump as a share of the band's recent peak. A sound that is
        /// small against the song is no hit, however suddenly it comes.
        var share: Float = 0
        /// The jump as a share of what the band was just playing. Under a
        /// long loud note a hit adds little to the loudness, and it is
        /// still a hit: what counts there is that the band rose at all.
        var rise: Float = 0

        func isAtLeast(share least: Float, rise leastRise: Float) -> Bool {
            share >= least && rise >= leastRise
        }
    }

    /// The long peak counts for this share: a passage a quarter as loud as
    /// the song's loudest still reads as full.
    static let quietShare: Float = 0.25
    /// The rise is read against at least this share of the peak, which
    /// keeps a small sound after silence from reading as a huge rise.
    static let riseFloor: Float = 0.3
    /// A jump must clear this many usual jumps before it counts.
    static let usualWeight: Float = 2
    /// Quieter than this is no sound at all (about -66 dB).
    static let silenceFloor: Float = 0.0005

    /// 0 to 1: the band's envelope against its recent peak. A held note
    /// holds it up, and it does not sag while the sound stays loud.
    private(set) var level: Float = 0

    private var envelope: Float = 0
    private var peak: Float = 0
    private var longPeak: Float = 0
    /// The loudness of the four hops before this one, newest first.
    private var before: (Float, Float, Float, Float) = (0, 0, 0, 0)
    /// The median of the band's own recent jumps, followed with a step up
    /// when a jump is over it and a step down when it is under.
    private var usualJump: Float = 0

    /// Takes one hop's loudness of this band. Returns how hard the band
    /// was hit: how far the hop stands over the hops just before it, beyond
    /// what its jumps usually are. Zero when it was not hit, or is too
    /// small a part of the mix.
    ///
    /// A hit may take two hops to rise: a kick that lands on a long bass
    /// note of nearly its own pitch can cancel against it for a moment.
    /// The hop is read against the loudest of the three before it, and
    /// against the three before the last one, and the larger jump counts.
    mutating func read(loudness: Float, mixLoudness: Float, mixPeak: Float, tuning: Tuning) -> Jump {
        let loudestBefore = min(max(before.0, before.1, before.2), max(before.1, before.2, before.3))
        before = (loudness, before.0, before.1, before.2)
        envelope = max(loudness, envelope * tuning.fall)
        peak = max(loudness, peak * tuning.peakFall)
        longPeak = max(loudness, longPeak * tuning.longFall)

        let reference = max(peak, longPeak * Self.quietShare, mixPeak * tuning.mixShare)
        guard reference >= Self.silenceFloor else {
            level = 0
            usualJump = 0
            return Jump()
        }
        level = min(1, envelope / reference)

        let jump = max(0, loudness - loudestBefore)
        let clear = max(0, jump - usualJump * Self.usualWeight)
        usualJump = max(0, usualJump + (jump > usualJump ? tuning.usualStep : -tuning.usualStep) * reference)
        guard loudness >= mixLoudness * tuning.ownShare, loudness >= mixPeak * tuning.hitShare else { return Jump() }
        return Jump(share: clear / reference, rise: clear / max(loudestBefore, reference * Self.riseFloor))
    }
}
