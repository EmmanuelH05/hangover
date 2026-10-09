import AVFoundation

/// Camera lookup shared by the card and the settings picker.
enum NookMirrorDevices {
    static let deviceIDKey = "nook.mirror.deviceID"

    struct Option: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
    }

    private static func discovery() -> AVCaptureDevice.DiscoverySession {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
    }

    static func available() -> [Option] {
        discovery().devices.map { Option(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// The saved device if it is still connected, else the system default.
    static func selectedDevice() -> AVCaptureDevice? {
        if let id = UserDefaults.standard.string(forKey: deviceIDKey),
           let device = AVCaptureDevice(uniqueID: id) {
            return device
        }
        return AVCaptureDevice.default(for: .video) ?? discovery().devices.first
    }
}
