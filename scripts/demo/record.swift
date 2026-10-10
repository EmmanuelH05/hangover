// Records only the windows of one app, for a number of seconds, to a movie.
// Nothing else on the screen can end up in the file: not the desktop, not a
// notification, not the lock screen.
// usage: record <pid> <seconds> <out.mov>
import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var started = false
    private(set) var frames = 0

    init(url: URL, width: Int, height: Int) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 30_000_000,
                AVVideoMaxKeyFrameIntervalKey: 30,
            ],
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        writer.add(input)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete else { return }
        if !started {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: buffer.presentationTimeStamp)
            started = true
        }
        if input.isReadyForMoreMediaData, input.append(buffer) { frames += 1 }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        FileHandle.standardError.write(Data("stream stopped: \(error)\n".utf8))
    }

    func finish() async {
        guard started else { return }
        input.markAsFinished()
        await writer.finishWriting()
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 4, let pid = pid_t(arguments[1]), let seconds = Double(arguments[2]) else {
    FileHandle.standardError.write(Data("usage: record <pid> <seconds> <out.mov>\n".utf8))
    exit(64)
}
let output = URL(fileURLWithPath: arguments[3])
try? FileManager.default.removeItem(at: output)

let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
guard let app = content.applications.first(where: { $0.processID == pid }) else {
    FileHandle.standardError.write(Data("no app with pid \(pid)\n".utf8))
    exit(2)
}
let mainID = CGMainDisplayID()
guard let display = content.displays.first(where: { $0.displayID == mainID }) ?? content.displays.first else {
    FileHandle.standardError.write(Data("no display\n".utf8))
    exit(3)
}

let scale = 2
let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
let configuration = SCStreamConfiguration()
configuration.width = display.width * scale
configuration.height = display.height * scale
configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
configuration.showsCursor = false
configuration.pixelFormat = kCVPixelFormatType_32BGRA
configuration.queueDepth = 6

let recorder = try Recorder(url: output, width: configuration.width, height: configuration.height)
let stream = SCStream(filter: filter, configuration: configuration, delegate: recorder)
try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: DispatchQueue(label: "record"))
try await stream.startCapture()
print("recording \(configuration.width)x\(configuration.height) for \(seconds) s")
try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
try await stream.stopCapture()
await recorder.finish()
print("frames \(recorder.frames)")
