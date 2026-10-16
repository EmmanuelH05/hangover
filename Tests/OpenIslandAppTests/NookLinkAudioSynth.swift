import Foundation

// Sound made in memory for the key and tempo tests. Nothing here plays or
// writes anything, and the noise comes from a seeded generator, which keeps
// every run the same.

enum NookLinkAudioSynth {
    /// The rate the app's decoder works at.
    static let rate = 11_025.0

    /// A small generator that gives the same numbers for the same seed.
    struct Seeded: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
        }

        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
    }

    /// The frequency of a MIDI note (69 is A4 at 440 Hz), `cents` off if asked.
    static func hertz(_ note: Int, cents: Double = 0) -> Double {
        440 * pow(2, (Double(note - 69) + cents / 100) / 12)
    }

    static func silence(seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * rate))
    }

    static func whiteNoise(seconds: Double, seed: UInt64 = 1, amplitude: Float = 0.3) -> [Float] {
        var generator = Seeded(seed: seed)
        return (0..<Int(seconds * rate)).map { _ in Float.random(in: -amplitude...amplitude, using: &generator) }
    }

    /// A note with five partials that fall off as one over the number squared,
    /// a quick attack and a slow decay: a soft pad or a struck string.
    static func note(_ frequency: Double, seconds: Double, amplitude: Double = 0.2, decay: Double = 1.5) -> [Float] {
        let count = Int(seconds * rate)
        var samples = [Float](repeating: 0, count: count)
        for partial in 1...5 {
            let partialFrequency = frequency * Double(partial)
            guard partialFrequency < rate / 2 else { break }
            let weight = amplitude / Double(partial * partial)
            let step = 2 * Double.pi * partialFrequency / rate
            for index in 0..<count {
                let time = Double(index) / rate
                let envelope = min(1, time / 0.02) * exp(-time / decay)
                samples[index] += Float(weight * envelope * sin(step * Double(index)))
            }
        }
        return samples
    }

    /// Adds `part` to `track` starting at `seconds`. What runs past the end is cut.
    static func add(_ part: [Float], to track: inout [Float], at seconds: Double) {
        let start = Int(seconds * rate)
        guard start < track.count else { return }
        for index in 0..<min(part.count, track.count - start) { track[start + index] += part[index] }
    }

    /// Chords one after another, over and over, each chord a few MIDI notes
    /// with one bass note under it, and a tune that walks up and down `scale`. `cents` tunes everything off the standard.
    static func progression(
        chords: [[Int]],
        bass: [Int],
        scale: [Int],
        chordSeconds: Double = 1.5,
        totalSeconds: Double = 24,
        cents: Double = 0
    ) -> [Float] {
        var track = silence(seconds: totalSeconds)
        // A tune that walks up the scale and back down, a note every 0.3 s.
        var tune = 0.0
        var step = 0
        let walk = scale + scale.dropFirst().dropLast().reversed()
        while tune < totalSeconds {
            add(Self.note(hertz(walk[step % walk.count], cents: cents), seconds: 0.5, amplitude: 0.1, decay: 0.3), to: &track, at: tune)
            tune += 0.3
            step += 1
        }
        var start = 0.0
        var chord = 0
        while start < totalSeconds {
            let notes = chords[chord % chords.count]
            for note in notes {
                add(Self.note(hertz(note, cents: cents), seconds: chordSeconds, amplitude: 0.12), to: &track, at: start)
            }
            add(Self.note(hertz(bass[chord % bass.count], cents: cents), seconds: chordSeconds, amplitude: 0.3, decay: 3), to: &track, at: start)
            start += chordSeconds
            chord += 1
        }
        return track
    }

    /// C F G C, the chords on the I, IV, V and I of C major, roots in the bass,
    /// and a tune in the C major scale.
    static func cMajor(cents: Double = 0) -> [Float] {
        progression(
            chords: [[60, 64, 67], [65, 69, 72], [67, 71, 74], [60, 64, 67]],
            bass: [36, 41, 43, 36],
            scale: [72, 74, 76, 77, 79, 81, 83, 84],
            cents: cents
        )
    }

    /// Am Dm E Am with a tune in the A harmonic minor scale: the E chord and the
    /// scale have a G sharp, which only A minor has.
    static func aMinor(cents: Double = 0) -> [Float] {
        progression(
            chords: [[57, 60, 64], [62, 65, 69], [64, 68, 71], [57, 60, 64]],
            bass: [33, 38, 40, 33],
            scale: [69, 71, 72, 74, 76, 77, 80, 81],
            cents: cents
        )
    }

    /// F#m Bm C# F#m with a tune in the F# harmonic minor scale: the C sharp chord
    /// has an E sharp, which is F natural.
    static func fSharpMinor(cents: Double = 0) -> [Float] {
        progression(
            chords: [[66, 69, 73], [71, 74, 78], [73, 77, 80], [66, 69, 73]],
            bass: [30, 35, 37, 30],
            scale: [66, 68, 69, 71, 73, 74, 77, 78],
            cents: cents
        )
    }

    // MARK: Drums

    /// A kick: a sine that falls from 160 Hz to 50 Hz in 80 ms and dies away.
    static func kick(amplitude: Double = 0.8) -> [Float] {
        let count = Int(0.25 * rate)
        var phase = 0.0
        return (0..<count).map { index in
            let time = Double(index) / rate
            let frequency = 50 + 110 * exp(-time / 0.03)
            phase += 2 * Double.pi * frequency / rate
            return Float(amplitude * exp(-time / 0.08) * sin(phase))
        }
    }

    /// A burst of noise that dies away in `length` seconds: a snare or a hat.
    static func burst(length: Double, amplitude: Double, seed: UInt64) -> [Float] {
        var generator = Seeded(seed: seed)
        let count = Int(length * 3 * rate)
        return (0..<count).map { index in
            let time = Double(index) / rate
            return Float(amplitude * exp(-time / length) * Double.random(in: -1...1, using: &generator))
        }
    }

    /// A drum pattern at `bpm`: a kick on every beat, a snare on the second and
    /// fourth, a hat between the beats. Set `kicksEvery` to 2 for a kick on
    /// the first and third only, `hats` false to leave the hats out.
    static func beat(bpm: Double, seconds: Double = 30, kicksEvery: Int = 1, hats: Bool = true) -> [Float] {
        var track = silence(seconds: seconds)
        let beatLength = 60 / bpm
        let kick = kick()
        let snare = burst(length: 0.06, amplitude: 0.5, seed: 7)
        let hat = burst(length: 0.015, amplitude: 0.25, seed: 11)
        var beatNumber = 0
        while Double(beatNumber) * beatLength < seconds {
            let time = Double(beatNumber) * beatLength
            if beatNumber % kicksEvery == 0 { add(kick, to: &track, at: time) }
            if beatNumber % 2 == 1 { add(snare, to: &track, at: time) }
            if hats { add(hat, to: &track, at: time + beatLength / 2) }
            beatNumber += 1
        }
        return track
    }

    /// Kicks at random times, about as many a second as a beat at 140 would
    /// have, with no pattern.
    static func scatteredKicks(seconds: Double = 30, seed: UInt64 = 5) -> [Float] {
        var generator = Seeded(seed: seed)
        var track = silence(seconds: seconds)
        let kick = kick()
        for _ in 0..<Int(seconds * 140 / 60) {
            add(kick, to: &track, at: Double.random(in: 0..<(seconds - 0.3), using: &generator))
        }
        return track
    }
}
