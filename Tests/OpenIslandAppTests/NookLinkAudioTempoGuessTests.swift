import Foundation
import Testing
@testable import OpenIslandApp

// The tempo guesser on drum patterns made in memory at several tempos, and
// on what has no beat: noise, silence, a held chord, kicks at random times.

@Suite struct NookLinkAudioTempoGuessTests {
    private typealias Synth = NookLinkAudioSynth
    private static let rate = Synth.rate

    private static let at140 = Synth.beat(bpm: 140)
    private static let at90 = Synth.beat(bpm: 90)

    private func guess(_ samples: [Float]) -> NookLinkAudioTempoGuess? {
        NookLinkAudioTempoGuesser.guess(samples: samples, sampleRate: Self.rate)
    }

    // MARK: The right tempo

    @Test func aBeatAt140IsFoundAt140() throws {
        let found = try #require(guess(Self.at140))
        #expect(abs(found.bpm - 140) <= 1, "\(found.bpm)")
        #expect(found.clarity >= NookLinkAudioTempoGuesser.minimumClarity)
    }

    @Test func aBeatAt90IsFoundAt90() throws {
        let found = try #require(guess(Self.at90))
        #expect(abs(found.bpm - 90) <= 1, "\(found.bpm)")
    }

    @Test(arguments: [82.0, 100.0, 120.0, 128.0, 150.0])
    func beatsAcrossTheRangeAreFoundWithinOne(bpm: Double) throws {
        let found = try #require(guess(Synth.beat(bpm: bpm)))
        #expect(abs(Double(found.bpm) - bpm) <= 1, "wanted \(bpm), found \(found.bpm)")
    }

    @Test func aKickOnlyEveryOtherBeatStillGivesTheBeat() throws {
        // Kicks on the first and third, a snare on the second and fourth, no hats.
        let found = try #require(guess(Synth.beat(bpm: 128, kicksEvery: 2, hats: false)))
        #expect(abs(found.bpm - 128) <= 1, "\(found.bpm)")
    }

    @Test func aBeatOutsideTheRangeIsFoldedIntoIt() throws {
        // 70 and 175 are the half and the double of 140 and 87.5.
        let slow = try #require(guess(Synth.beat(bpm: 70)))
        #expect(abs(slow.bpm - 140) <= 1, "70 comes out as \(slow.bpm)")
        let fast = try #require(guess(Synth.beat(bpm: 174)))
        #expect(abs(fast.bpm - 87) <= 1, "174 comes out as \(fast.bpm)")
    }

    @Test func theRangeIsAParameter() throws {
        let reading = NookLinkAudioTempoGuesser.reading(samples: Self.at140, sampleRate: Self.rate, range: 60.0..<120.0)
        let found = try #require(reading)
        #expect(abs(found.bpm - 70) <= 1, "140 folded into 60 to 120 is \(found.bpm)")
    }

    @Test func theLoudnessOfTheBeatDoesNotChangeTheTempo() throws {
        let quiet = try #require(guess(Self.at140.map { $0 * 0.01 }))
        let loud = try #require(guess(Self.at140.map { $0 * 1.2 }))
        #expect(abs(quiet.bpm - 140) <= 1)
        #expect(abs(loud.bpm - 140) <= 1)
    }

    @Test func aBeatWithNoiseOnTopIsStillFound() throws {
        let noise = Synth.whiteNoise(seconds: 30, seed: 9, amplitude: 0.05)
        let found = try #require(guess(zip(Self.at90, noise).map { $0 + $1 }))
        #expect(abs(found.bpm - 90) <= 1, "\(found.bpm)")
    }

    // MARK: Nothing to say

    @Test(arguments: [1, 2, 3, 4, 5, 6])
    func whiteNoiseHasNoTempo(seed: UInt64) {
        #expect(guess(Synth.whiteNoise(seconds: 30, seed: seed)) == nil)
    }

    @Test func silenceHasNoTempo() {
        #expect(guess(Synth.silence(seconds: 30)) == nil)
    }

    /// One chord for the whole clip: nothing starts after the first moment.
    private static let heldChord: [Float] = {
        let chord = [60, 64, 67].map { Synth.note(Synth.hertz($0), seconds: 30, amplitude: 0.2, decay: 1_000) }
        return (0..<chord[0].count).map { index in chord.reduce(Float(0)) { $0 + $1[index] } }
    }()

    @Test func aHeldChordHasNoTempo() {
        #expect(guess(Self.heldChord) == nil)
    }

    @Test func kicksAtRandomTimesHaveNoTempo() {
        #expect(guess(Synth.scatteredKicks()) == nil)
    }

    @Test func aClipTooShortToSeeAPatternHasNoTempo() {
        let short = Array(Self.at140.prefix(Int(NookLinkAudioTempoGuesser.minimumSeconds * Self.rate) - 10))
        #expect(guess(short) == nil)
        #expect(guess([]) == nil)
        #expect(NookLinkAudioTempoGuesser.reading(samples: short, sampleRate: Self.rate) == nil)
    }

    @Test func aSampleRateThatIsNotPositiveHasNoTempo() {
        #expect(NookLinkAudioTempoGuesser.guess(samples: Self.at140, sampleRate: 0) == nil)
        #expect(NookLinkAudioTempoGuesser.guess(samples: Self.at140, sampleRate: -11_025) == nil)
    }

    @Test func aBeatThatIsNotClearEnoughIsLeftUnsaid() throws {
        let reading = try #require(NookLinkAudioTempoGuesser.reading(samples: Self.at140, sampleRate: Self.rate))
        #expect(NookLinkAudioTempoGuesser.guess(samples: Self.at140, sampleRate: Self.rate, minimumClarity: reading.clarity + 0.01) == nil)
        #expect(NookLinkAudioTempoGuesser.guess(samples: Self.at140, sampleRate: Self.rate, minimumClarity: reading.clarity - 0.01) != nil)
    }

    // MARK: The parts

    @Test func theOnsetStrengthJumpsWhereTheDrumsHit() throws {
        let drums = Synth.beat(bpm: 140, hats: false)
        let onsets = try #require(NookLinkAudioTempoGuesser.onsetStrength(samples: drums, sampleRate: Self.rate))
        let envelope = onsets.values
        let hop = Double(NookLinkAudioTempoGuesser.hopSize)
        let frames = (drums.count - NookLinkAudioTempoGuesser.frameSize) / NookLinkAudioTempoGuesser.hopSize + 1
        #expect(envelope.count == frames)
        // A kick every 60 / 140 s. The frame whose window first takes it in
        // carries a jump, and the frames a half beat later carry well under it.
        func frame(atBeat beat: Double) -> Int { Int(beat * 60 / 140 * Self.rate / hop) }
        var smallestJump = Float.greatestFiniteMagnitude
        var largestQuiet: Float = 0
        for beat in 2..<20 {
            let hit = frame(atBeat: Double(beat))
            smallestJump = min(smallestJump, envelope[(hit - 4)...(hit + 1)].max() ?? 0)
            let between = frame(atBeat: Double(beat) + 0.5)
            largestQuiet = max(largestQuiet, envelope[(between - 1)...(between + 1)].max() ?? 0)
        }
        #expect(smallestJump > 1.5 * largestQuiet, "\(smallestJump) against \(largestQuiet)")
    }

    @Test func aBeatChangesTheSpectrumMoreThanAHeldChordDoes() throws {
        let beat = try #require(NookLinkAudioTempoGuesser.onsetStrength(samples: Self.at140, sampleRate: Self.rate))
        let held = try #require(NookLinkAudioTempoGuesser.onsetStrength(samples: Self.heldChord, sampleRate: Self.rate))
        #expect(beat.activity > 5 * held.activity, "\(beat.activity) against \(held.activity)")
    }

    @Test func autocorrelationIsOneAtLagZeroAndPeaksAtThePeriod() {
        // A pulse every 10 samples.
        let pulses = (0..<400).map { $0 % 10 == 0 ? Float(1) : Float(0) }
        let mean = pulses.reduce(0, +) / Float(pulses.count)
        let repeats = NookLinkAudioTempoGuesser.autocorrelation(of: pulses.map { $0 - mean }, upTo: 30)
        #expect(repeats.count == 31)
        #expect(abs(repeats[0] - 1) < 1e-9)
        #expect(repeats[10] > 0.9 && repeats[20] > 0.9 && repeats[30] > 0.9)
        #expect(repeats[5] < 0.2)
    }

    @Test func autocorrelationOfASignalWithNothingInItIsAllZero() {
        let repeats = NookLinkAudioTempoGuesser.autocorrelation(of: [Float](repeating: 0, count: 100), upTo: 10)
        #expect(repeats == [Double](repeating: 0, count: 11))
        #expect(NookLinkAudioTempoGuesser.autocorrelation(of: [1, 2, 3], upTo: 10).isEmpty)
    }
}
