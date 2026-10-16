import Foundation
import Testing
@testable import OpenIslandApp

// The key guesser on sound made in memory: chords with a bass note under
// them in three keys, the same a little out of tune, and the things it must
// say nothing about: noise, silence, and a clip too short to read.

@Suite struct NookLinkAudioKeyGuessTests {
    private typealias Synth = NookLinkAudioSynth
    private static let rate = Synth.rate

    private static let cMajor = Synth.cMajor()
    private static let aMinor = Synth.aMinor()
    private static let fSharpMinor = Synth.fSharpMinor()

    private func guess(_ samples: [Float]) -> NookLinkAudioKeyGuess? {
        NookLinkAudioKeyGuesser.guess(samples: samples, sampleRate: Self.rate)
    }

    // MARK: The right key

    @Test func aCMajorProgressionWithALowBassIsCMajor() throws {
        let found = try #require(guess(Self.cMajor))
        #expect(found.key == NookMusicalKey(tonic: 0, mode: .major))
        #expect(found.confidence >= NookLinkAudioKeyGuesser.minimumMargin)
    }

    @Test func anAMinorProgressionWithABassOnTheLowestNoteIsAMinor() throws {
        // The bass sits on A1, 55 Hz, the bottom of what the guesser reads.
        let found = try #require(guess(Self.aMinor))
        #expect(found.key == NookMusicalKey(tonic: 9, mode: .minor))
    }

    @Test func anFSharpMinorProgressionIsFSharpMinor() throws {
        // The bass sits on F#1, 46 Hz, below the range: its partials carry the note.
        let found = try #require(guess(Self.fSharpMinor))
        #expect(found.key == NookMusicalKey(tonic: 6, mode: .minor))
    }

    @Test(arguments: [-30.0, -15.0, 25.0])
    func aTrackThatIsOutOfTuneIsStillReadRight(cents: Double) throws {
        let found = try #require(guess(Synth.cMajor(cents: cents)))
        #expect(found.key == NookMusicalKey(tonic: 0, mode: .major), "\(cents) cents")
    }

    @Test func theLoudnessOfTheTrackDoesNotChangeTheKey() throws {
        let quiet = Self.aMinor.map { $0 * 0.02 }
        let loud = Self.aMinor.map { $0 * 3 }
        #expect(guess(quiet)?.key == NookMusicalKey(tonic: 9, mode: .minor))
        #expect(guess(loud)?.key == NookMusicalKey(tonic: 9, mode: .minor))
    }

    @Test func aLongPauseOfSilenceInTheMiddleDoesNotMuddleTheKey() throws {
        let track = Self.cMajor + Synth.silence(seconds: 20) + Self.cMajor
        #expect(guess(track)?.key == NookMusicalKey(tonic: 0, mode: .major))
    }

    @Test func noiseOnTopOfTheChordsIsTolerated() throws {
        let noise = Synth.whiteNoise(seconds: 24, seed: 3, amplitude: 0.05)
        let track = zip(Self.cMajor, noise).map { $0 + $1 }
        #expect(guess(track)?.key == NookMusicalKey(tonic: 0, mode: .major))
    }

    // MARK: Nothing to say

    @Test(arguments: [1, 2, 3, 4, 5, 6])
    func whiteNoiseHasNoKey(seed: UInt64) {
        let noise = Synth.whiteNoise(seconds: 30, seed: seed)
        #expect(guess(noise) == nil)
    }

    @Test func silenceHasNoKey() {
        #expect(guess(Synth.silence(seconds: 30)) == nil)
        #expect(NookLinkAudioKeyGuesser.scores(samples: Synth.silence(seconds: 30), sampleRate: Self.rate) == nil)
    }

    @Test func aClipShorterThanOneFrameHasNoKey() {
        let short = Array(Self.cMajor.prefix(NookLinkAudioKeyGuesser.frameSize - 1))
        #expect(guess(short) == nil)
        #expect(guess([]) == nil)
    }

    @Test func aClipTooShortToTrustHasNoKey() {
        // Four frames of a chord are fewer than the guesser asks for.
        let short = Array(Self.cMajor.prefix(NookLinkAudioKeyGuesser.frameSize * 3))
        #expect(NookLinkAudioKeyGuesser.scores(samples: short, sampleRate: Self.rate) != nil)
        #expect(guess(short) == nil)
    }

    @Test func aSampleRateThatIsNotPositiveHasNoKey() {
        #expect(NookLinkAudioKeyGuesser.guess(samples: Self.cMajor, sampleRate: 0) == nil)
        #expect(NookLinkAudioKeyGuesser.guess(samples: Self.cMajor, sampleRate: -44_100) == nil)
    }

    @Test func aBestKeyThatDoesNotClearlyWinIsLeftUnsaid() throws {
        let scores = try #require(NookLinkAudioKeyGuesser.scores(samples: Self.cMajor, sampleRate: Self.rate))
        #expect(NookLinkAudioKeyGuesser.guess(samples: Self.cMajor, sampleRate: Self.rate, minimumMargin: scores.margin + 0.01) == nil)
        #expect(NookLinkAudioKeyGuesser.guess(samples: Self.cMajor, sampleRate: Self.rate, minimumMargin: scores.margin - 0.01) != nil)
    }

    @Test func notesNoMoreUnevenThanChanceAreLeftUnsaidWhateverTheMargin() throws {
        let scores = try #require(NookLinkAudioKeyGuesser.scores(samples: Self.cMajor, sampleRate: Self.rate))
        #expect(NookLinkAudioKeyGuesser.guess(
            samples: Self.cMajor, sampleRate: Self.rate, minimumMargin: 0, minimumSignificance: scores.significance + 1
        ) == nil)
    }

    // MARK: The scores

    @Test func theScoresListAll24KeysBestFirst() throws {
        let scores = try #require(NookLinkAudioKeyGuesser.scores(samples: Self.aMinor, sampleRate: Self.rate))
        #expect(scores.ranked.count == 24)
        #expect(Set(scores.ranked.map(\.key)).count == 24)
        #expect(scores.ranked == scores.ranked.sorted { $0.correlation > $1.correlation })
        #expect(scores.best.key == NookMusicalKey(tonic: 9, mode: .minor))
        #expect(scores.margin == scores.ranked[0].correlation - scores.ranked[1].correlation)
        #expect(scores.frameCount > 8)
        #expect(scores.ranked.allSatisfy { abs($0.correlation) <= 1.000_001 })
    }

    @Test func noiseIsAsUnevenAsChanceAndMusicIsNot() throws {
        let noise = try #require(NookLinkAudioKeyGuesser.scores(samples: Synth.whiteNoise(seconds: 30), sampleRate: Self.rate))
        let music = try #require(NookLinkAudioKeyGuesser.scores(samples: Self.cMajor, sampleRate: Self.rate))
        #expect(noise.significance < NookLinkAudioKeyGuesser.minimumSignificance)
        #expect(music.significance > 2 * NookLinkAudioKeyGuesser.minimumSignificance)
    }

    // MARK: The profile

    @Test func theProfileIsAParameter() throws {
        // A profile turned by seven semitones puts its heaviest note five
        // semitones above its tonic, which makes the C of a C major track the
        // fourth degree of the key it finds: G major.
        let kk = NookKeyProfile.krumhanslKessler
        let turned = NookKeyProfile(
            major: (0..<12).map { kk.major[($0 + 7) % 12] },
            minor: (0..<12).map { kk.minor[($0 + 7) % 12] }
        )
        let standard = NookLinkAudioKeyGuesser.scores(samples: Self.cMajor, sampleRate: Self.rate, profile: kk)
        let other = NookLinkAudioKeyGuesser.scores(samples: Self.cMajor, sampleRate: Self.rate, profile: turned)
        #expect(standard?.best.key == NookMusicalKey(tonic: 0, mode: .major))
        #expect(other?.best.key == NookMusicalKey(tonic: 7, mode: .major))
    }

    @Test func theKrumhanslKesslerProfileIsThePublishedOne() {
        let profile = NookKeyProfile.krumhanslKessler
        #expect(profile.major.count == 12 && profile.minor.count == 12)
        #expect(profile.major[0] == 6.35 && profile.major[7] == 5.19)
        #expect(profile.minor[0] == 6.33 && profile.minor[3] == 5.38)
        // The tonic is the heaviest note of each.
        #expect(profile.major.max() == profile.major[0])
        #expect(profile.minor.max() == profile.minor[0])
    }

    @Test func aKeysWeightsAreTheProfileTurnedToItsTonic() {
        let profile = NookKeyProfile.krumhanslKessler
        let dMinor = profile.weights(for: NookMusicalKey(tonic: 2, mode: .minor))
        #expect(dMinor[2] == profile.minor[0])
        #expect(dMinor[5] == profile.minor[3])
        #expect(dMinor[1] == profile.minor[11])
    }

    // MARK: The math

    @Test func correlationIsOneForTheSameShapeMinusOneForTheOpposite() {
        let shape = [1.0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
        #expect(abs(NookLinkAudioKeyGuesser.correlation(shape, shape.map { $0 * 3 + 5 }) - 1) < 1e-12)
        #expect(abs(NookLinkAudioKeyGuesser.correlation(shape, shape.map { -$0 }) + 1) < 1e-12)
        #expect(NookLinkAudioKeyGuesser.correlation(shape, [Double](repeating: 4, count: 12)) == 0)
    }
}

// MARK: - The key's own type

@Suite struct NookMusicalKeyTests {
    @Test func theTwelveTonicsAreSpelledTheWayTheFileNamesWantThem() {
        #expect(NookMusicalKey.noteNames == ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"])
        #expect(NookMusicalKey(tonic: 1, mode: .minor).englishName == "C# minor")
        #expect(NookMusicalKey(tonic: 10, mode: .major).englishName == "Bb major")
    }

    @Test func aTonicWrapsAroundTheOctave() {
        #expect(NookMusicalKey(tonic: 12, mode: .major) == NookMusicalKey(tonic: 0, mode: .major))
        #expect(NookMusicalKey(tonic: -1, mode: .minor) == NookMusicalKey(tonic: 11, mode: .minor))
        #expect(NookMusicalKey(tonic: 27, mode: .minor).tonic == 3)
    }

    @Test func thereAre24KeysAndEveryRelativePairComesBack() {
        #expect(NookMusicalKey.all.count == 24)
        #expect(Set(NookMusicalKey.all).count == 24)
        for key in NookMusicalKey.all {
            #expect(key.relative != key)
            #expect(key.relative.mode != key.mode)
            #expect(key.relative.relative == key)
        }
        #expect(NookMusicalKey(tonic: 0, mode: .major).relative == NookMusicalKey(tonic: 9, mode: .minor))
        #expect(NookMusicalKey(tonic: 1, mode: .minor).relative == NookMusicalKey(tonic: 4, mode: .major))
    }

    @Test func theLocalizedNameUsesTheModeWordOfTheLanguage() {
        let key = NookMusicalKey(tonic: 1, mode: .minor)
        let name = key.localizedName
        // The tests run in one language at a time; the name carries the note either way.
        #expect(name.contains("C#"))
        #expect(name != key.noteName)
    }
}
