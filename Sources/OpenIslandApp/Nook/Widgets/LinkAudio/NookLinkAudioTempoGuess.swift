import Accelerate
import Foundation

/// A tempo that was worked out from the sound, and how clear the beat was.
struct NookLinkAudioTempoGuess: Equatable, Sendable {
    /// Whole beats a minute.
    let bpm: Int
    /// How much of the beat's pattern repeats at this tempo, from 0 to 1.
    let clarity: Double
}

/// A tempo before the gate, for a caller that wants the numbers.
struct NookLinkAudioTempoReading: Equatable, Sendable {
    let bpm: Double
    let clarity: Double
    /// How much the sound changes from frame to frame next to its own level.
    let activity: Double
}

/// Guesses the tempo of a song from its sound.
///
/// The sound is cut into short Hann windowed frames, 512 samples every 128
/// (46 ms every 12 ms at 11,025 Hz). Each frame's spectrum is log compressed
/// and compared with the frame before it: the sum of the increases is the
/// spectral flux, which jumps when something starts, a kick, a snare or a
/// note. The flux over time is the onset strength. The slow drift is taken out
/// of it and the autocorrelation is read. A tempo is scored by how much the
/// pattern repeats at one beat, two, three and four beats (a comb on the
/// autocorrelation), and only tempos inside the preferred range are tried,
/// which is what folds a half time or double time reading into one answer: a
/// 70 beat a minute pattern comes out as 140.
///
/// It says nothing when the pattern does not repeat clearly enough, or when
/// there is too little sound to see a pattern.
enum NookLinkAudioTempoGuesser {
    static let frameSize = 512
    static let hopSize = 128
    /// Scored in steps of this many beats a minute.
    static let step = 0.25
    /// The range an answer is folded into. Free beats are 80 to 100 or 130
    /// to 160 for the most part, and every tempo has just one partner an
    /// octave away inside a range that is a factor of two wide.
    static let preferredRange = 80.0..<160.0
    /// The number of beats whose repeat is added up for a tempo.
    static let beatsScored = 4
    /// Less sound than this, in seconds, has no pattern worth reading.
    static let minimumSeconds = 6.0
    /// The weakest repeat that counts as a beat. A drum loop is above 0.5, a
    /// song with a soft beat is above this, noise sits near zero.
    static let minimumClarity = 0.2
    /// The least change from frame to frame, next to the level of the sound,
    /// that is a beat and not the ripple of held notes: a held chord is at
    /// 0.002, a drum loop above 0.015.
    static let minimumActivity = 0.008
    /// The window the drift is measured over, in seconds.
    static let driftSeconds = 0.5

    /// The guess, or nil when the beat is not clear.
    static func guess(
        samples: [Float],
        sampleRate: Double,
        range: Range<Double> = preferredRange,
        minimumClarity: Double = minimumClarity
    ) -> NookLinkAudioTempoGuess? {
        guard let reading = reading(samples: samples, sampleRate: sampleRate, range: range),
              reading.clarity >= minimumClarity,
              reading.activity >= minimumActivity
        else { return nil }
        return NookLinkAudioTempoGuess(bpm: Int(reading.bpm.rounded()), clarity: reading.clarity)
    }

    /// The best tempo in `range` and how clear it is, with no gate. Nil when
    /// there is too little sound.
    static func reading(
        samples: [Float],
        sampleRate: Double,
        range: Range<Double> = preferredRange
    ) -> NookLinkAudioTempoReading? {
        guard sampleRate > 0, Double(samples.count) >= minimumSeconds * sampleRate,
              let onsets = onsetStrength(samples: samples, sampleRate: sampleRate)
        else { return nil }
        let envelope = onsets.values
        let rate = sampleRate / Double(hopSize)
        let longestLag = Int((rate * 60 / range.lowerBound * Double(beatsScored)).rounded(.up)) + 2
        guard envelope.count > 2 * longestLag else { return nil }
        let repeats = autocorrelation(of: prepared(envelope, rate: rate), upTo: longestLag)
        guard let first = repeats.first, first > 0 else { return nil }

        var bestTempo = range.lowerBound
        var bestScore = -Double.infinity
        var tempo = range.lowerBound
        while tempo < range.upperBound {
            let beat = rate * 60 / tempo
            var total = 0.0
            for multiple in 1...beatsScored {
                total += value(of: repeats, atLag: beat * Double(multiple))
            }
            let score = total / Double(beatsScored)
            if score > bestScore {
                bestScore = score
                bestTempo = tempo
            }
            tempo += step
        }
        return NookLinkAudioTempoReading(bpm: bestTempo, clarity: max(0, bestScore), activity: onsets.activity)
    }

    // MARK: Onset strength

    /// The onset strength of each frame, and the mean log level of the
    /// spectrum bins it was taken from, which tells how big a flux is
    /// next to the sound it comes from.
    struct OnsetStrength {
        var values: [Float]
        /// The mean of the log levels over all frames and bins.
        var meanLevel: Float

        /// The mean flux of a frame set against the level of the sound, per
        /// bin. A held chord changes by a few thousandths of its level a frame,
        /// a beat by a few hundredths.
        var activity: Double {
            guard !values.isEmpty, meanLevel > 0 else { return 0 }
            let binCount = Double(NookLinkAudioTempoGuesser.frameSize / 2 - 1)
            return Double(values.reduce(0, +)) / Double(values.count) / binCount / Double(meanLevel)
        }
    }

    /// The spectral flux of each frame: how much louder, in log terms,
    /// the spectrum got since the frame before. Each bin is set against the
    /// loudest of itself and its two neighbours in the frame before, which
    /// keeps the ripple of a held note's window from counting as a start.
    static func onsetStrength(samples: [Float], sampleRate: Double) -> OnsetStrength? {
        guard samples.count >= frameSize + hopSize, let spectrum = NookLinkAudioSpectrum(size: frameSize) else { return nil }
        let frames = (samples.count - frameSize) / hopSize + 1
        var envelope = [Float](repeating: 0, count: frames)
        var levelSum = 0.0
        var magnitudes: [Float] = []
        var previous = [Float](repeating: 0, count: spectrum.binCount)
        var current = previous
        let scale = 1_000 / spectrum.fullScale
        for frame in 0..<frames {
            spectrum.magnitudes(of: samples, from: frame * hopSize, into: &magnitudes)
            for bin in 1..<spectrum.binCount { current[bin] = log1pf(magnitudes[bin] * scale) }
            levelSum += Double(current[1...].reduce(0, +))
            if frame > 0 {
                var flux: Float = 0
                for bin in 1..<spectrum.binCount {
                    let reference = max(previous[bin - 1], previous[bin], bin + 1 < previous.count ? previous[bin + 1] : 0)
                    let rise = current[bin] - reference
                    if rise > 0 { flux += rise }
                }
                envelope[frame] = flux
            }
            swap(&previous, &current)
        }
        return OnsetStrength(
            values: envelope,
            meanLevel: Float(levelSum / Double(frames * (spectrum.binCount - 1)))
        )
    }

    /// The envelope with its slow drift taken off, the negative part cut and
    /// the mean removed.
    private static func prepared(_ envelope: [Float], rate: Double) -> [Float] {
        let reach = max(2, Int(rate * driftSeconds / 2))
        var sums = [Double](repeating: 0, count: envelope.count + 1)
        for index in envelope.indices { sums[index + 1] = sums[index] + Double(envelope[index]) }
        var result = envelope
        for index in envelope.indices {
            let low = max(0, index - reach)
            let high = min(envelope.count, index + reach + 1)
            let drift = (sums[high] - sums[low]) / Double(high - low)
            result[index] = max(0, envelope[index] - Float(drift))
        }
        let mean = result.reduce(0, +) / Float(result.count)
        return result.map { $0 - mean }
    }

    // MARK: Repeats

    /// The autocorrelation for lags 0 to `longestLag`, each divided by the
    /// number of terms it adds up and then by lag 0: one means the pattern
    /// repeats exactly. A lag with no signal in it is zero.
    static func autocorrelation(of values: [Float], upTo longestLag: Int) -> [Double] {
        let count = values.count
        guard count > longestLag else { return [] }
        var result = [Double](repeating: 0, count: longestLag + 1)
        values.withUnsafeBufferPointer { buffer in
            let base = buffer.baseAddress!
            for lag in 0...longestLag {
                var sum: Float = 0
                vDSP_dotpr(base, 1, base + lag, 1, &sum, vDSP_Length(count - lag))
                result[lag] = Double(sum) / Double(count - lag)
            }
        }
        let zero = result[0]
        guard zero > 0 else { return [Double](repeating: 0, count: longestLag + 1) }
        return result.map { $0 / zero }
    }

    /// The autocorrelation at a lag between two whole ones.
    private static func value(of repeats: [Double], atLag lag: Double) -> Double {
        let lower = Int(lag.rounded(.down))
        guard lower >= 0, lower + 1 < repeats.count else { return 0 }
        let share = lag - Double(lower)
        return repeats[lower] * (1 - share) + repeats[lower + 1] * share
    }
}
