import AVFoundation
import Foundation
import Testing
@testable import OpenIslandApp

// The rule for what is written down and what is worked out, and the real
// analyzer on a sound file written to a temporary folder.

@Suite struct NookLinkAudioAnalyzerTests {
    private typealias Synth = NookLinkAudioSynth
    private static let rate = Synth.rate

    private static let cMajor = Synth.cMajor()
    private static let drums = Synth.beat(bpm: 140)

    private func tags(key: NookMusicalKey? = nil, bpm: Int? = nil) -> NookLinkAudioTagReading {
        NookLinkAudioTagReading(key: key, bpm: bpm)
    }

    // MARK: The rule

    @Test func whatTheUploaderWroteIsTakenAsExactAndNeverDecoded() {
        var asked = 0
        let key = NookMusicalKey(tonic: 4, mode: .minor)
        let found = NookLinkAudioAnalysis.findings(tags: tags(key: key, bpm: 139), sampleRate: Self.rate) {
            asked += 1
            return Self.cMajor
        }
        #expect(asked == 0, "both given: the file is never read")
        #expect(found.key == NookLinkAudioFound(value: key, isGuess: false))
        #expect(found.bpm == NookLinkAudioFound(value: 139, isGuess: false))
    }

    /// The app guesses no key from the sound (D66): only a tempo. A video
    /// that gives its tempo is then never decoded.
    @Test func theAppGuessesTheTempoButNotTheKey() throws {
        #expect(NookLinkAudioAnalysis.guessesKeyFromSound == false)
        let mix = zip(Self.cMajor, Self.drums).map { $0 + $1 }
        let found = NookLinkAudioAnalysis.findings(tags: tags(), sampleRate: Self.rate) { mix }
        #expect(found.key == nil)
        let bpm = try #require(found.bpm)
        #expect(bpm.isGuess)
        var asked = 0
        let withTempo = NookLinkAudioAnalysis.findings(tags: tags(bpm: 90), sampleRate: Self.rate) {
            asked += 1
            return mix
        }
        #expect(asked == 0, "nothing is left to guess")
        #expect(withTempo == NookLinkAudioFindings(key: nil, bpm: NookLinkAudioFound(value: 90, isGuess: false)))
    }

    @Test func whatIsLeftOutIsGuessedAndSaysSo() throws {
        let found = NookLinkAudioAnalysis.findings(tags: tags(), sampleRate: Self.rate, guessesKey: true) { Self.cMajor }
        let key = try #require(found.key)
        #expect(key.isGuess)
        #expect(key.value == NookMusicalKey(tonic: 0, mode: .major))
        let beat = NookLinkAudioAnalysis.findings(tags: tags(), sampleRate: Self.rate) { Self.drums }
        let bpm = try #require(beat.bpm)
        #expect(bpm.isGuess)
        #expect(abs(bpm.value - 140) <= 1)
    }

    @Test func aWrittenKeyIsKeptWhileOnlyTheTempoIsGuessed() throws {
        let written = NookMusicalKey(tonic: 1, mode: .minor)
        let mix = zip(Self.cMajor, Self.drums).map { $0 + $1 }
        let found = NookLinkAudioAnalysis.findings(tags: tags(key: written), sampleRate: Self.rate) { mix }
        #expect(found.key == NookLinkAudioFound(value: written, isGuess: false), "the guess is not allowed to overrule it")
        let bpm = try #require(found.bpm)
        #expect(bpm.isGuess)
    }

    @Test func aWrittenTempoIsKeptWhileOnlyTheKeyIsGuessed() throws {
        let mix = zip(Self.cMajor, Self.drums).map { $0 + $1 }
        let found = NookLinkAudioAnalysis.findings(tags: tags(bpm: 90), sampleRate: Self.rate, guessesKey: true) { mix }
        #expect(found.bpm == NookLinkAudioFound(value: 90, isGuess: false))
        #expect(found.key?.isGuess == true)
    }

    @Test func aSoundThatCannotBeReadLeavesTheTagsAlone() {
        let found = NookLinkAudioAnalysis.findings(tags: tags(bpm: 90), sampleRate: Self.rate) { nil }
        #expect(found == NookLinkAudioFindings(key: nil, bpm: NookLinkAudioFound(value: 90, isGuess: false)))
        #expect(NookLinkAudioAnalysis.findings(tags: tags(), sampleRate: Self.rate) { nil }.isEmpty)
    }

    @Test func noiseGivesNothingAndNothingIsNotMadeUp() {
        let noise = Synth.whiteNoise(seconds: 30, seed: 2)
        #expect(NookLinkAudioAnalysis.findings(tags: tags(), sampleRate: Self.rate, guessesKey: true) { noise }.isEmpty)
    }

    // MARK: The real analyzer

    private final class Folder {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HangoverAnalyzerTests-\(UUID().uuidString)", isDirectory: true)

        init() throws {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func write(_ samples: [Float], to url: URL) throws {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.rate, channels: 1, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)))
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let data = try #require(buffer.floatChannelData)[0]
        for index in samples.indices { data[index] = samples[index] }
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }

    /// The key is left blank (D66); the tempo is guessed.
    @Test func aFileWithNoTagsIsDecodedAndTheTempoIsGuessed() async throws {
        let folder = try Folder()
        let url = folder.url.appendingPathComponent("Song [a1b2].wav")
        try write(zip(Self.cMajor, Self.drums).map { $0 + $1 }, to: url)

        let found = await NookLinkAudioSystemAnalyzer().analyze(file: url, title: "Song", description: "Prod. by nobody")

        #expect(found.key == nil)
        let bpm = try #require(found.bpm)
        #expect(bpm.isGuess)
        #expect(abs(bpm.value - 140) <= 1, "\(bpm.value)")
    }

    @Test func aDescriptionWithBothMeansTheFileIsNeverOpened() async {
        // The file does not exist. If the analyzer tried to read it, there would be no tag answer.
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("HangoverMissing-\(UUID().uuidString).mp3")
        let found = await NookLinkAudioSystemAnalyzer().analyze(
            file: missing,
            title: "Wake Up",
            description: "Key: C Sharp Minor | Bpm: 127"
        )
        #expect(found.key == NookLinkAudioFound(value: NookMusicalKey(tonic: 1, mode: .minor), isGuess: false))
        #expect(found.bpm == NookLinkAudioFound(value: 127, isGuess: false))
    }

    @Test func aFileThatCannotBeReadAndNoTagsGivesNothing() async throws {
        let folder = try Folder()
        let url = folder.url.appendingPathComponent("broken.mp3")
        try Data("not sound".utf8).write(to: url)
        let found = await NookLinkAudioSystemAnalyzer().analyze(file: url, title: nil, description: nil)
        #expect(found.isEmpty)
    }

    @Test func aFileThatCannotBeReadStillGivesTheTags() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("HangoverMissing-\(UUID().uuidString).mp3")
        let found = await NookLinkAudioSystemAnalyzer().analyze(file: missing, title: "Free beat | 90 BPM", description: nil)
        #expect(found.bpm == NookLinkAudioFound(value: 90, isGuess: false))
        #expect(found.key == nil)
    }

    @Test func aCancelledAnalysisIsNotDecodedAndFindsNothing() async throws {
        let folder = try Folder()
        let url = folder.url.appendingPathComponent("Song.wav")
        try write(zip(Self.cMajor, Self.drums).map { $0 + $1 }, to: url)
        // The task cancels itself before it asks, which leaves no race between
        // the cancel and the work.
        let found = await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return await NookLinkAudioSystemAnalyzer().analyze(file: url, title: nil, description: nil)
        }.value
        #expect(found.isEmpty)
    }

    @Test func aCancelThatComesAfterTheDecodeGuessesNothingMore() async {
        let none = NookLinkAudioTagReading(key: nil, bpm: nil)
        let found = await Task.detached {
            NookLinkAudioAnalysis.findings(tags: none, sampleRate: Self.rate, guessesKey: true) {
                withUnsafeCurrentTask { $0?.cancel() }
                return Self.cMajor
            }
        }.value
        #expect(found.isEmpty, "not even the key, which the sound would have given")

        // What the uploader wrote is not a guess, and a cancel does not take it back.
        let written = NookLinkAudioTagReading(key: nil, bpm: 90)
        let kept = await Task.detached {
            NookLinkAudioAnalysis.findings(tags: written, sampleRate: Self.rate) {
                withUnsafeCurrentTask { $0?.cancel() }
                return Self.cMajor
            }
        }.value
        #expect(kept == NookLinkAudioFindings(key: nil, bpm: NookLinkAudioFound(value: 90, isGuess: false)))
    }
}
