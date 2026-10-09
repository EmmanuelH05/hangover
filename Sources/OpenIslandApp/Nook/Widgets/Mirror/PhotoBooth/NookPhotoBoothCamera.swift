import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

/// Why a still did not come back.
enum NookPhotoBoothCameraError: Error, Equatable {
    /// The mirror's camera is not running.
    case cameraOff
    /// The camera would not take a still output.
    case noOutput
    /// The camera answered with nothing that reads as a picture.
    case noPicture
    /// The camera never answered.
    case timedOut
}

/// A still as the camera took it: not flipped, not cut.
struct NookPhotoBoothStill: @unchecked Sendable {
    let image: CGImage
}

/// Takes one still from a camera that is already running. The booth has
/// no camera of its own and never starts one: tests hand it a fake, and
/// the app hands it the mirror's.
protocol NookPhotoBoothCamera: Sendable {
    /// True when a picture could be taken now.
    @MainActor var isReady: Bool { get }
    /// Gets ready ahead of the first picture, while the countdown runs.
    func prepare()
    func captureStill() async throws -> NookPhotoBoothStill
}

/// Stills from the mirror's running camera. Everything AVFoundation in
/// here happens on the mirror's session queue, which is also the only
/// place `output` and `waiting` are touched.
final class NookMirrorStillCamera: NSObject, NookPhotoBoothCamera, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    /// How long a still may take before the booth gives up on it.
    static let timeout: TimeInterval = 4

    private let controller: NookMirrorController
    private var output: AVCapturePhotoOutput?
    private var waiting: [Int64: StillRequest] = [:]

    @MainActor
    init(controller: NookMirrorController) {
        self.controller = controller
    }

    @MainActor var isReady: Bool {
        controller.authorization == .authorized && controller.hasCamera
    }

    func prepare() {
        controller.onSessionQueue { [self] session in
            _ = attachedOutput(to: session)
        }
    }

    func captureStill() async throws -> NookPhotoBoothStill {
        try await withCheckedThrowingContinuation { continuation in
            let request = StillRequest(continuation)
            controller.onSessionQueue { [self] session in
                guard session.isRunning else { return request.finish(.failure(.cameraOff)) }
                guard let output = attachedOutput(to: session),
                      let connection = output.connection(with: .video),
                      connection.isEnabled, connection.isActive else {
                    return request.finish(.failure(.noOutput))
                }
                // The booth flips the picture itself, the same way every time.
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = false
                }
                let settings = output.availablePhotoCodecTypes.contains(.jpeg)
                    ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                    : AVCapturePhotoSettings()
                waiting[settings.uniqueID] = request
                output.capturePhoto(with: settings, delegate: self)
            }
            // A camera that never answers must not hang the booth.
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeout) { [self] in
                request.finish(.failure(.timedOut))
                controller.onSessionQueue { [self] _ in
                    waiting = waiting.filter { !$0.value.isFinished }
                }
            }
        }
    }

    /// The still output, added to the session the first time it is wanted.
    /// A mirror that never opens the booth never gets one.
    private func attachedOutput(to session: AVCaptureSession) -> AVCapturePhotoOutput? {
        if let output, session.outputs.contains(output) { return output }
        let fresh = output ?? AVCapturePhotoOutput()
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddOutput(fresh) else { return nil }
        session.addOutput(fresh)
        output = fresh
        // A still output can make the session pick another format. This
        // runs after the change is committed, on the same queue.
        controller.refreshAspectRatio()
        return fresh
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        let id = photo.resolvedSettings.uniqueID
        let result: Result<NookPhotoBoothStill, NookPhotoBoothCameraError>
        if error == nil,
           let data = photo.fileDataRepresentation(),
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            result = .success(NookPhotoBoothStill(image: image))
        } else {
            result = .failure(.noPicture)
        }
        controller.onSessionQueue { [self] _ in
            waiting.removeValue(forKey: id)?.finish(result)
        }
    }
}

/// One still being waited for. Whoever answers first wins, the camera or
/// the timeout, and the other is ignored.
private final class StillRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<NookPhotoBoothStill, any Error>?

    init(_ continuation: CheckedContinuation<NookPhotoBoothStill, any Error>) {
        self.continuation = continuation
    }

    var isFinished: Bool { lock.withLock { continuation == nil } }

    func finish(_ result: Result<NookPhotoBoothStill, NookPhotoBoothCameraError>) {
        let pending = lock.withLock {
            let pending = continuation
            continuation = nil
            return pending
        }
        switch result {
        case let .success(still): pending?.resume(returning: still)
        case let .failure(error): pending?.resume(throwing: error)
        }
    }
}
