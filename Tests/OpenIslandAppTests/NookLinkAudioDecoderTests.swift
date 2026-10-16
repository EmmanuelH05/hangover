import AVFoundation
import Foundation
import Testing
@testable import OpenIslandApp

// The decoder on sound files written to a temporary folder with
// `AVAudioFile`. Nothing is played, no audio device is opened.

@Suite struct NookLinkAudioDecoderTests {
    /// A folder of its own for one test, removed after.
    private final class Folder {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HangoverDecoderTests-\(UUID().uuidString)", isDirectory: true)

        init() throws {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: url)
        }

        func file(_ name: String) -> URL { url.appendingPathComponent(name) }
    }

    /// Writes a sine wave to `url`. Each channel has its own amplitude.
    private func writeSine(
        _ url: URL,
        frequency: Double = 440,
        seconds: Double = 2,
        rate: Double = 44_100,
        amplitudes: [Float] = [0.5, 0.5],
        settings: [String: Any]? = nil
    ) throws {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: AVAudioChannelCount(amplitudes.count), interleaved: false))
        let frames = AVAudioFrameCount(seconds * rate)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for channel in 0..<amplitudes.count {
            let data = try #require(buffer.floatChannelData)[channel]
            for frame in 0..<Int(frames) {
                data[frame] = amplitudes[channel] * Float(sin(2 * Double.pi * frequency * Double(frame) / rate))
            }
        }
        let fileSettings = settings ?? [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: amplitudes.count,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: fileSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }

    private func rms(_ samples: [Float]) -> Double {
        (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(samples.count, 1))).squareRoot()
    }

    // MARK: A good file

    @Test func aStereoFileComesOutMonoAtTheLowRate() throws {
        let folder = try Folder()
        let url = folder.file("tone.wav")
        try writeSine(url, seconds: 2, rate: 44_100)

        let samples = try NookLinkAudioDecoder.decode(url)

        // Two seconds at 11,025 Hz, within the converter's own slack.
        #expect(abs(samples.count - 22_050) < 300, "\(samples.count)")
        // A sine of 0.5 has an RMS of 0.354 and survives the change of rate.
        #expect(abs(rms(samples) - 0.354) < 0.03, "\(rms(samples))")
    }

    @Test func theSoundIsStillTheSameNote() throws {
        let folder = try Folder()
        let url = folder.file("a.wav")
        try writeSine(url, frequency: 440, seconds: 3, rate: 44_100)

        let samples = try NookLinkAudioDecoder.decode(url)

        let scores = NookLinkAudioKeyGuesser.chroma(samples: samples, sampleRate: NookLinkAudioDecoder.sampleRate)
        let chroma = try #require(scores).chroma
        #expect(chroma.indices.max { chroma[$0] < chroma[$1] } == 9, "A is pitch class 9: \(chroma)")
    }

    @Test func theChannelsAreAveraged() throws {
        let folder = try Folder()
        let url = folder.file("left.wav")
        // Left at 0.8, right silent: the average is a sine of 0.4.
        try writeSine(url, seconds: 2, amplitudes: [0.8, 0])

        let samples = try NookLinkAudioDecoder.decode(url)
        #expect(abs(rms(samples) - 0.4 / 2.0.squareRoot()) < 0.03, "\(rms(samples))")
    }

    @Test func aMonoFileAtALowRateIsHandedOnAsItIs() throws {
        let folder = try Folder()
        let url = folder.file("mono.wav")
        try writeSine(url, seconds: 2, rate: 11_025, amplitudes: [0.5])

        let samples = try NookLinkAudioDecoder.decode(url)
        #expect(abs(samples.count - 22_050) < 300)
        #expect(abs(rms(samples) - 0.354) < 0.03)
    }

    @Test func aFileInAnotherFormatIsReadToo() throws {
        let folder = try Folder()
        let url = folder.file("tone.caf")
        try writeSine(url, seconds: 2, rate: 22_050, amplitudes: [0.5, 0.5], settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 22_050,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ])

        let samples = try NookLinkAudioDecoder.decode(url)
        #expect(abs(samples.count - 22_050) < 300, "\(samples.count)")
        #expect(abs(rms(samples) - 0.354) < 0.03)
    }

    @Test func theSoundIsCutAtTheLimit() throws {
        let folder = try Folder()
        let url = folder.file("long.wav")
        try writeSine(url, seconds: 6, rate: 11_025, amplitudes: [0.5])

        let samples = try NookLinkAudioDecoder.decode(url, maxSeconds: 2)
        #expect(samples.count == 22_050)
    }

    // MARK: A bad file

    @Test func aFileThatIsNotThereCannotBeOpened() throws {
        let folder = try Folder()
        #expect(throws: NookLinkAudioDecodeError.cannotOpen) {
            try NookLinkAudioDecoder.decode(folder.file("missing.mp3"))
        }
    }

    @Test func aFileThatIsNotSoundCannotBeOpened() throws {
        let folder = try Folder()
        let url = folder.file("fake.mp3")
        try Data("This is not an MP3, just some words in a file.".utf8).write(to: url)
        #expect(throws: NookLinkAudioDecodeError.cannotOpen) {
            try NookLinkAudioDecoder.decode(url)
        }
    }

    @Test func aFolderCannotBeOpened() throws {
        let folder = try Folder()
        #expect(throws: NookLinkAudioDecodeError.self) {
            try NookLinkAudioDecoder.decode(folder.url)
        }
    }

    @Test func aFileWithNoSoundInItIsAnError() throws {
        let folder = try Folder()
        let url = folder.file("empty.wav")
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: false))
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        _ = file
        #expect(throws: NookLinkAudioDecodeError.self) {
            try NookLinkAudioDecoder.decode(url)
        }
    }

    // MARK: Cancelling

    @Test func aCancelledTaskStopsTheDecode() async throws {
        let folder = try Folder()
        let url = folder.file("song.wav")
        try writeSine(url, seconds: 6, rate: 11_025, amplitudes: [0.5])

        // The task cancels itself first, which leaves no race with the decode.
        let thrown = await Task.detached { () -> NookLinkAudioDecodeError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try NookLinkAudioDecoder.decode(url)
                return nil
            } catch {
                return error as? NookLinkAudioDecodeError
            }
        }.value
        #expect(thrown == .cancelled)

        // The same file, read by a task that is not cancelled, decodes.
        #expect(try NookLinkAudioDecoder.decode(url).count > 0)
    }
}
