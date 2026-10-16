import AVFoundation
import Foundation

/// Why a file could not be read as sound.
enum NookLinkAudioDecodeError: Error, Equatable {
    case cannotOpen
    case unsupportedFormat
    case cannotConvert
    case noSound
    /// The task that called was cancelled, and the decode stopped at the next chunk.
    case cancelled
}

/// Reads a sound file into mono samples at a low rate, which is all the key
/// and tempo guessers need. `AVAudioFile` reads the MP3 and `AVAudioConverter`
/// brings it down to 11,025 Hz, which keeps what is below 5 kHz. The channels
/// are then averaged by hand.
///
/// It plays nothing and opens no audio device. The work is plain computing and
/// belongs off the main actor, which is where the service calls it.
enum NookLinkAudioDecoder {
    /// The rate the guessers work at.
    static let sampleRate = 11_025.0
    /// Sound past this many seconds is not read. A mix this long is not one song.
    static let maxSeconds = 600.0
    fileprivate static let chunkFrames: AVAudioFrameCount = 32_768

    static func decode(
        _ file: URL,
        sampleRate: Double = sampleRate,
        maxSeconds: Double = maxSeconds
    ) throws -> [Float] {
        let source: AVAudioFile
        do {
            source = try AVAudioFile(forReading: file, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw NookLinkAudioDecodeError.cannotOpen
        }
        let inputFormat = source.processingFormat
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0,
              let outputFormat = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: sampleRate,
                  channels: inputFormat.channelCount,
                  interleaved: false
              )
        else { throw NookLinkAudioDecodeError.unsupportedFormat }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat),
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: chunkFrames),
              let outputBuffer = AVAudioPCMBuffer(
                  pcmFormat: outputFormat,
                  frameCapacity: AVAudioFrameCount(Double(chunkFrames) * sampleRate / inputFormat.sampleRate) + 4_096
              )
        else { throw NookLinkAudioDecodeError.cannotConvert }

        let limit = Int(maxSeconds * sampleRate)
        var mono: [Float] = []
        mono.reserveCapacity(min(limit, Int(Double(source.length) * sampleRate / inputFormat.sampleRate) + 1))
        let feeder = Feeder(source: source, buffer: inputBuffer)

        while mono.count < limit {
            // A song takes a while to read. A cancel stops it within a chunk.
            if Task.isCancelled { throw NookLinkAudioDecodeError.cancelled }
            var failure: NSError?
            let status = converter.convert(to: outputBuffer, error: &failure) { _, inputStatus in
                feeder.next(inputStatus)
            }
            if status == .error { throw NookLinkAudioDecodeError.cannotConvert }
            append(outputBuffer, to: &mono)
            if status == .endOfStream { break }
        }
        if mono.count > limit { mono.removeLast(mono.count - limit) }
        guard !mono.isEmpty else { throw NookLinkAudioDecodeError.noSound }
        return mono
    }

    /// Hands the file to the converter a chunk at a time. The converter asks
    /// for input on the thread that called `convert`, one call after another,
    /// which is why the state here needs no lock.
    private final class Feeder: @unchecked Sendable {
        private let source: AVAudioFile
        private let buffer: AVAudioPCMBuffer
        private var hasEnded = false

        init(source: AVAudioFile, buffer: AVAudioPCMBuffer) {
            self.source = source
            self.buffer = buffer
        }

        func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
            if !hasEnded {
                buffer.frameLength = 0
                // A read that fails ends the sound where it is.
                try? source.read(into: buffer, frameCount: NookLinkAudioDecoder.chunkFrames)
            }
            if hasEnded || buffer.frameLength == 0 {
                hasEnded = true
                status.pointee = .endOfStream
                return nil
            }
            status.pointee = .haveData
            return buffer
        }
    }

    /// Adds the buffer's frames to `mono`, the channels averaged.
    private static func append(_ buffer: AVAudioPCMBuffer, to mono: inout [Float]) {
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frames > 0, channels > 0, let data = buffer.floatChannelData else { return }
        if channels == 1 {
            mono.append(contentsOf: UnsafeBufferPointer(start: data[0], count: frames))
            return
        }
        let share = 1 / Float(channels)
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channels { sum += data[channel][frame] }
            mono.append(sum * share)
        }
    }
}
