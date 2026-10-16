import AVFoundation
import Foundation

/// Why the face cam bubble is not showing a picture. The bubble used to draw
/// a "no video" symbol for any of these, and the recording captured the
/// symbol. Now the bubble closes and the island says which one it was.
enum NookFaceCamProblem: Equatable, Sendable {
    /// Camera access was denied or is restricted.
    case noAccess
    /// There is no camera to open.
    case noCamera
    /// The camera would not open, or would not start.
    case cameraFailed
    /// The camera stopped on its own: unplugged, or taken by another app.
    case stopped

    var noticeKey: String {
        switch self {
        case .noAccess: "nook.record.facecam.problem.noAccess"
        case .noCamera: "nook.record.facecam.problem.noCamera"
        case .cameraFailed: "nook.record.facecam.problem.failed"
        case .stopped: "nook.record.facecam.problem.stopped"
        }
    }
}

enum NookFaceCamRules {
    /// What a camera authorization status means for the bubble. Nil when the
    /// camera may be opened, or macOS has yet to be asked.
    static func problem(for status: AVAuthorizationStatus) -> NookFaceCamProblem? {
        switch status {
        case .authorized, .notDetermined: nil
        case .denied, .restricted: .noAccess
        @unknown default: .noAccess
        }
    }
}
