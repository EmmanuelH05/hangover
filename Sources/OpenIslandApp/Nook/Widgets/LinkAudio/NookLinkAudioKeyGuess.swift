import Accelerate
import Foundation

/// How much each of the 12 notes counts in a key, counted from its tonic.
/// The guesser holds a song's notes against all 24 keys made by turning
/// these. It is a parameter, which lets another set be tried.
struct NookKeyProfile: Sendable {
    /// Weights for the tonic, then each semitone above it.
    let major: [Double]
    let minor: [Double]

    /// The probe tone ratings of Krumhansl and Kessler, "Tracing the dynamic
    /// changes in perceived tonal organization in a spatial representation of
    /// musical keys", Psychological Review 89 (1982). Listeners rated how well
    /// each note fits after a key was set up; these are the published means.
    static let krumhanslKessler = NookKeyProfile(
        major: [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88],
        minor: [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
    )

    /// The 12 weights of one key, indexed by pitch class (0 for C).
    func weights(for key: NookMusicalKey) -> [Double] {
        let base = key.mode == .major ? major : minor
        return (0..<12).map { base[($0 - key.tonic + 12) % 12] }
    }
}

/// A key that was worked out from the sound, and how clearly it won.
struct NookLinkAudioKeyGuess: Equatable, Sendable {
    let key: NookMusicalKey
    /// The correlation of the best key minus the runner up's.
    let confidence: Double
}

/// All 24 keys held against a song's notes, for a caller that wants more
/// than the guess (the eval prints these).
struct NookLinkAudioKeyScores: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let key: NookMusicalKey
        let correlation: Double
    }

    /// Best first.
    let ranked: [Entry]
    /// The frames that were loud enough to count.
    let frameCount: Int
    /// How many times more uneven the 12 note weights (square rooted, as they
    /// are correlated) are than the same peaks would make them if each fell in a
    /// pitch class by chance. About one for noise, one or two for drums, three
    /// or more for music with a tune in it.
    let significance: Double

    var best: Entry { ranked[0] }
    /// The best correlation minus the next best.
    var margin: Double { ranked[0].correlation - ranked[1].correlation }
}

/// Guesses the key of a song from its sound.
///
/// The song is cut into long frames, 8192 samples at 11,025 Hz (0.74 s, 1.35 Hz
/// per bin), long enough to tell neighbouring notes apart down to about 55 Hz,
/// where 808 basses sit. A Hann window is laid on each frame and its FFT taken
/// (Accelerate). The peaks of the spectrum between 55 Hz and 1,760 Hz (five
/// octaves from A1) are the notes. A peak has to stand out from the bins around
/// it, which leaves the noise floor out. Each peak is placed on the pitch scale
/// to a fraction of a semitone, and its weight is its level below the frame's
/// loudest peak, on a decibel scale that counts 20 dB down to zero. That is the
/// log compression: a quiet note counts, a loud one does not drown it. A peak
/// under 250 Hz counts twice, since the bass line carries the tonic.
///
/// The whole song is tuned to the pitch its peaks agree on, when that is more
/// than 20 cents from the standard (a track 30 cents flat is still read right).
/// The weights are added up in 12 pitch classes, square rooted (the sum is
/// much peakier than the flat profile) and correlated with the 24 keys of the
/// profile. Frames that are nearly silent next to the loudest one are skipped.
///
/// It says nothing when it is not sure: not enough sound, notes that are no
/// more uneven than noise would make them, or a best key that does not beat the
/// runner up by enough.
enum NookLinkAudioKeyGuesser {
    static let frameSize = 8192
    static let hopSize = 4096
    /// A1 and A6: whole octaves, which keeps white noise from leaning towards
    /// the pitch classes of a part octave.
    static let lowestHz = 55.0
    static let highestHz = 1_760.0
    /// A peak this far below the frame's loudest counts for nothing.
    static let dynamicRangeDB = 20.0
    /// A peak has to be this many times the average of its neighbours.
    static let prominence = 2.5
    /// A frame quieter than this many dB below the loudest frame is silence.
    static let silenceDB = 40.0
    /// What is under this counts for `bassWeight`.
    static let bassCeilingHz = 250.0
    static let bassWeight: Float = 2
    /// A song's tuning is believed only when it is this many semitones off.
    static let minimumTuningShift: Float = 0.2
    /// The power the summed note weights are raised to.
    static let chromaPower = 0.5

    static let minimumFrames = 8
    /// The least `significance` that is music and not noise or drums.
    static let minimumSignificance = 2.0
    /// How far the best key has to be ahead of the runner up.
    static let minimumMargin = 0.08

    /// The guess, or nil when the sound does not decide a key.
    static func guess(
        samples: [Float],
        sampleRate: Double,
        profile: NookKeyProfile = .krumhanslKessler,
        minimumMargin: Double = minimumMargin,
        minimumSignificance: Double = minimumSignificance
    ) -> NookLinkAudioKeyGuess? {
        guard let scores = scores(samples: samples, sampleRate: sampleRate, profile: profile),
              scores.frameCount >= minimumFrames,
              scores.significance >= minimumSignificance,
              scores.margin >= minimumMargin
        else { return nil }
        return NookLinkAudioKeyGuess(key: scores.best.key, confidence: scores.margin)
    }

    /// Every key's correlation, or nil when there is not enough sound to read.
    static func scores(
        samples: [Float],
        sampleRate: Double,
        profile: NookKeyProfile = .krumhanslKessler
    ) -> NookLinkAudioKeyScores? {
        guard let found = chroma(samples: samples, sampleRate: sampleRate) else { return nil }
        let total = found.chroma.reduce(0, +)
        guard total > 0 else { return nil }
        let notes = found.chroma.map { pow($0, chromaPower) }
        let ranked = NookMusicalKey.all
            .map { NookLinkAudioKeyScores.Entry(key: $0, correlation: correlation(notes, profile.weights(for: $0))) }
            .sorted { $0.correlation > $1.correlation }
        // The spread of the weights, set against what chance would give for
        // the same number of equal peaks: a spread of the 12 counts of N
        // peaks that fall at random is about the square root of 11 over N, in
        // proportion to their mean.
        let mean = notes.reduce(0, +) / 12
        let spread = (notes.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / 12).squareRoot()
        let significance = spread / mean * (found.effectivePeaks / 11).squareRoot()
        return NookLinkAudioKeyScores(ranked: ranked, frameCount: found.frames, significance: significance)
    }

    // MARK: Chroma

    /// What the frames add up to.
    struct Chroma {
        /// The weight of each pitch class over the whole song.
        var chroma: [Double]
        /// The frames that counted.
        var frames: Int
        /// The number of equal peaks the weights are worth: the sum of the
        /// weights squared over the sum of their squares.
        var effectivePeaks: Double
    }

    /// Nil when the sound is shorter than one frame or has no frame that counts.
    static func chroma(samples: [Float], sampleRate: Double) -> Chroma? {
        guard sampleRate > 0, samples.count >= frameSize, let spectrum = NookLinkAudioSpectrum(size: frameSize) else { return nil }
        let binHz = sampleRate / Double(frameSize)
        let lowBin = max(neighbourReach + 1, Int((lowestHz / binHz).rounded(.up)))
        let highBin = min(
            spectrum.binCount - neighbourReach - 2,
            Int((min(highestHz, sampleRate * 0.45) / binHz).rounded(.down))
        )
        guard lowBin < highBin else { return nil }

        let starts = Array(stride(from: 0, through: samples.count - frameSize, by: hopSize))
        let levels = starts.map { frameLevel(samples, from: $0) }
        let loudest = levels.max() ?? 0
        guard loudest > absoluteSilence else { return nil }
        let quietest = max(absoluteSilence, loudest * Float(pow(10, -silenceDB / 20)))

        var peaks = Peaks()
        var magnitudes: [Float] = []
        var counted = 0
        for (start, level) in zip(starts, levels) where level >= quietest {
            spectrum.magnitudes(of: samples, from: start, into: &magnitudes)
            collectPeaks(magnitudes, lowBin: lowBin, highBin: highBin, binHz: binHz, into: &peaks)
            counted += 1
        }
        guard counted > 0, !peaks.weights.isEmpty else { return nil }

        let shift = tuningShift(of: peaks)
        var chroma = [Double](repeating: 0, count: 12)
        for index in peaks.weights.indices {
            let note = Int((peaks.pitches[index] - shift).rounded())
            chroma[((note % 12) + 12) % 12] += Double(peaks.weights[index])
        }
        let sum = peaks.weights.reduce(0) { $0 + Double($1) }
        let squares = peaks.weights.reduce(0) { $0 + Double($1) * Double($1) }
        return Chroma(chroma: chroma, frames: counted, effectivePeaks: squares > 0 ? sum * sum / squares : 0)
    }

    /// The peaks of every counted frame: where each stands on the pitch scale
    /// (MIDI note numbers, 69 for A4) and how much it weighs.
    private struct Peaks {
        var pitches: [Float] = []
        var weights: [Float] = []
    }

    /// The root mean square under which a frame is digital silence.
    private static let absoluteSilence: Float = 1e-4
    /// How far a peak's bins reach on each side when its neighbours are averaged.
    private static let neighbourReach = 8
    /// The bins either side of a peak that belong to the peak (a Hann window
    /// spreads a sine over about this many) and are left out of its neighbours.
    private static let peakReach = 2

    private static func frameLevel(_ samples: [Float], from start: Int) -> Float {
        var level: Float = 0
        samples.withUnsafeBufferPointer {
            vDSP_rmsqv($0.baseAddress! + start, 1, &level, vDSP_Length(frameSize))
        }
        return level
    }

    private static func collectPeaks(
        _ magnitudes: [Float],
        lowBin: Int,
        highBin: Int,
        binHz: Double,
        into peaks: inout Peaks
    ) {
        var loudest: Float = 0
        for bin in lowBin...highBin where magnitudes[bin] > loudest { loudest = magnitudes[bin] }
        guard loudest > 0 else { return }
        // Running sums, which give the average of any run of bins in one step.
        var sums = [Double](repeating: 0, count: magnitudes.count + 1)
        for index in magnitudes.indices { sums[index + 1] = sums[index] + Double(magnitudes[index]) }
        let neighbours = Double(2 * neighbourReach + 1 - (2 * peakReach + 1))
        let dynamic = Float(dynamicRangeDB)

        for bin in lowBin...highBin {
            let level = magnitudes[bin]
            guard level > magnitudes[bin - 1], level >= magnitudes[bin + 1] else { continue }
            let wide = sums[bin + neighbourReach + 1] - sums[bin - neighbourReach]
            let near = sums[bin + peakReach + 1] - sums[bin - peakReach]
            guard Double(level) > prominence * (wide - near) / neighbours else { continue }
            let weight = (20 * log10(level / loudest) + dynamic) / dynamic
            guard weight > 0 else { continue }

            // The top of the parabola through the log magnitudes of the bin
            // and its two neighbours is where the sine really is.
            let before = log(max(magnitudes[bin - 1], 1e-12))
            let here = log(level)
            let after = log(max(magnitudes[bin + 1], 1e-12))
            let curve = before - 2 * here + after
            let offset = curve < 0 ? min(max(0.5 * (before - after) / curve, -0.5), 0.5) : 0
            let frequency = (Double(bin) + Double(offset)) * binHz
            peaks.pitches.append(Float(69 + 12 * log2(frequency / 440)))
            peaks.weights.append(frequency < bassCeilingHz ? weight * bassWeight : weight)
        }
    }

    /// How far, in semitones, the song's notes sit from the standard pitch
    /// scale: the weighted mean of the peaks' distance to the nearest semitone,
    /// taken on a circle. Zero when the peaks agree on nothing, and zero when
    /// the shift is too small to believe: the upper partials of a note are a
    /// few cents off the scale, which moves the mean a little for a track that
    /// is in tune.
    private static func tuningShift(of peaks: Peaks) -> Float {
        var sine = 0.0
        var cosine = 0.0
        var total = 0.0
        for index in peaks.weights.indices {
            let angle = 2 * Double.pi * Double(peaks.pitches[index])
            let weight = Double(peaks.weights[index])
            sine += weight * Foundation.sin(angle)
            cosine += weight * Foundation.cos(angle)
            total += weight
        }
        guard total > 0, (sine * sine + cosine * cosine).squareRoot() / total >= 0.2 else { return 0 }
        let shift = Float(atan2(sine, cosine) / (2 * Double.pi))
        return abs(shift) >= minimumTuningShift ? shift : 0
    }

    // MARK: Correlation

    /// Pearson's correlation of two equal length vectors, zero when either is flat.
    static func correlation(_ first: [Double], _ second: [Double]) -> Double {
        let count = Double(first.count)
        let meanFirst = first.reduce(0, +) / count
        let meanSecond = second.reduce(0, +) / count
        var covariance = 0.0
        var varianceFirst = 0.0
        var varianceSecond = 0.0
        for index in first.indices {
            let a = first[index] - meanFirst
            let b = second[index] - meanSecond
            covariance += a * b
            varianceFirst += a * a
            varianceSecond += b * b
        }
        let divisor = (varianceFirst * varianceSecond).squareRoot()
        return divisor > 0 ? covariance / divisor : 0
    }
}
