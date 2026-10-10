import AppKit
import AVFoundation
import SwiftUI

/// Wraps the capture session so it can cross to the session queue.
/// Only touched on `NookMirrorController.sessionQueue` after creation.
private final class SessionBox: @unchecked Sendable {
    let session = AVCaptureSession()
}

/// Owns the one capture session for the mirror. SwiftUI can rebuild the
/// mirror view while the page reflows, which is why the session lives here
/// and not in the view. A view attaches on appear and detaches on disappear; the camera
/// stops shortly after the last one detaches, which lets a view that is
/// rebuilt in the same pass keep it running.
@MainActor @Observable
final class NookMirrorController {
    static let shared = NookMirrorController()

    /// How long the session outlives its last view.
    private static let stopDelay: Duration = .milliseconds(400)

    private(set) var authorization: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    private(set) var hasCamera = true
    /// Width over height of the camera's picture. The mirror is cut to this
    /// shape, which lets it show the whole picture with nothing cropped.
    private(set) var aspectRatio: CGFloat = NookMirrorLayout.defaultAspectRatio {
        didSet { if aspectRatio != oldValue { onAspectRatioChange?() } }
    }
    /// Lets the app model resize the island when the camera's shape is known.
    @ObservationIgnored var onAspectRatioChange: (() -> Void)?

    @ObservationIgnored private let box = SessionBox()
    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "nook.mirror.session")
    @ObservationIgnored private var attachedCards = 0
    @ObservationIgnored private var isSessionRequested = false
    @ObservationIgnored private var isRequestingAccess = false
    @ObservationIgnored private var pendingStop: Task<Void, Never>?
    /// True from the moment the mirror is switched on until `stopNow`. A
    /// start that arrives while it is false, such as the answer to the
    /// camera prompt after the mirror went off, does not run.
    @ObservationIgnored private var isMirrorWanted = false

    var session: AVCaptureSession { box.session }

    private init() {}

    /// Whether the camera may start now: access is granted, a card is
    /// attached to show it, and the mirror is still wanted.
    nonisolated static func shouldStart(isAuthorized: Bool, attachedCards: Int, isMirrorWanted: Bool) -> Bool {
        isAuthorized && attachedCards > 0 && isMirrorWanted
    }

    /// The camera list in System Settings, Privacy & Security: where a
    /// refusal is changed. The mirror's message and the welcome tour both
    /// open it here.
    static func openCameraSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
        NSWorkspace.shared.open(url)
    }

    func attach() {
        attachedCards += 1
        pendingStop?.cancel()
        pendingStop = nil
        authorization = AVCaptureDevice.authorizationStatus(for: .video)
        guard !isSessionRequested else { return }
        switch authorization {
        case .authorized:
            startIfWanted()
        case .notDetermined:
            requestAccess()
        default:
            break
        }
    }

    func detach() {
        attachedCards = max(0, attachedCards - 1)
        guard attachedCards == 0 else { return }
        pendingStop?.cancel()
        pendingStop = Task {
            try? await Task.sleep(for: Self.stopDelay)
            guard !Task.isCancelled else { return }
            stopSession()
        }
    }

    /// Stops the camera at once, whatever is still attached. Turning the
    /// mirror off must not leave the camera light on while the view fades.
    func stopNow() {
        pendingStop?.cancel()
        pendingStop = nil
        // Marks the mirror as no longer wanted, which also cancels a start
        // still on its way: the camera prompt may be answered after this.
        isMirrorWanted = false
        isSessionRequested = false
        let box = box
        sessionQueue.async {
            if box.session.isRunning { box.session.stopRunning() }
        }
    }

    /// Starts the camera again for a view that is still attached. Turning
    /// the mirror off and on quickly can reuse the view, and a reused view
    /// never calls `attach` a second time.
    func resumeIfAttached() {
        isMirrorWanted = true
        guard attachedCards > 0, !isSessionRequested else { return }
        authorization = AVCaptureDevice.authorizationStatus(for: .video)
        startIfWanted()
    }

    /// Hands the capture session to work that must run on its queue. The
    /// photo booth adds its still output and takes its pictures this way,
    /// which keeps the mirror the only owner of the camera.
    nonisolated func onSessionQueue(_ work: @escaping @Sendable (AVCaptureSession) -> Void) {
        let box = box
        sessionQueue.async { work(box.session) }
    }

    /// Reads the camera's shape again. The photo booth calls this after it
    /// adds its still output, which can make the session pick another
    /// format than the one the mirror was sized for.
    nonisolated func refreshAspectRatio() {
        let box = box
        sessionQueue.async {
            guard let device = (box.session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
            let size = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            let ratio = NookMirrorLayout.aspectRatio(width: Int(size.width), height: Int(size.height))
            Task { @MainActor [weak self] in self?.aspectRatio = ratio }
        }
    }

    private func requestAccess() {
        guard !isRequestingAccess else { return }
        isRequestingAccess = true
        AVCaptureDevice.requestAccess(for: .video) { @Sendable _ in
            Task { @MainActor in
                self.isRequestingAccess = false
                self.authorization = AVCaptureDevice.authorizationStatus(for: .video)
                if !self.isSessionRequested { self.startIfWanted() }
            }
        }
    }

    /// Starts the camera when `shouldStart` allows it.
    private func startIfWanted() {
        guard Self.shouldStart(
            isAuthorized: authorization == .authorized,
            attachedCards: attachedCards,
            isMirrorWanted: isMirrorWanted
        ) else { return }
        configureAndRun()
    }

    private func stopSession() {
        pendingStop = nil
        guard attachedCards == 0 else { return }
        isSessionRequested = false
        let box = box
        sessionQueue.async {
            if box.session.isRunning { box.session.stopRunning() }
        }
    }

    private func configureAndRun() {
        let device = NookMirrorDevices.selectedDevice()
        hasCamera = device != nil
        guard let device else { return }
        isSessionRequested = true
        let deviceID = device.uniqueID
        let box = box
        sessionQueue.async {
            let session = box.session
            guard let device = AVCaptureDevice(uniqueID: deviceID) else { return }
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            if let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()
            if !session.isRunning { session.startRunning() }
            // The session may have picked another format than the device
            // started with, which is why the shape is read after it runs.
            let size = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            let ratio = NookMirrorLayout.aspectRatio(width: Int(size.width), height: Int(size.height))
            Task { @MainActor [weak self] in self?.aspectRatio = ratio }
        }
    }
}

/// Layer-backed view that shows the camera, mirrored like a real mirror.
/// The preview layer is re-fitted on every size change so the picture
/// follows the card between small, medium and large.
private final class NookCameraPreviewView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        // Fit, never fill: the whole picture shows. The mirror is sized to
        // the camera's shape, which leaves no bars around it.
        previewLayer.videoGravity = .resizeAspect
        previewLayer.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
        layer?.addSublayer(previewLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        fitPreviewLayer()
    }

    override func layout() {
        super.layout()
        fitPreviewLayer()
    }

    // Bounds and position, not frame: the layer carries the mirror transform.
    private func fitPreviewLayer() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        previewLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }
}

private struct NookCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NookCameraPreviewView {
        NookCameraPreviewView(session: session)
    }

    func updateNSView(_ view: NookCameraPreviewView, context: Context) {}
}

/// Sizing rules for the live mirror. A plain enum and not part of a view,
/// which keeps them callable from the window-sizing math and from tests
/// without the main actor.
enum NookMirrorLayout {
    /// Most Mac cameras are 16 by 9. Used until the real shape is known.
    static let defaultAspectRatio: CGFloat = 16.0 / 9.0
    /// Shapes outside this range are treated as a bad reading.
    private static let aspectRatioRange: ClosedRange<CGFloat> = 1.0...2.4
    /// Space between the card's edge and the picture.
    static let padding: CGFloat = 8

    /// Width over height for a camera format, or the default when the
    /// numbers make no sense.
    static func aspectRatio(width: Int, height: Int) -> CGFloat {
        guard width > 0, height > 0 else { return defaultAspectRatio }
        let ratio = CGFloat(width) / CGFloat(height)
        return aspectRatioRange.contains(ratio) ? ratio : defaultAspectRatio
    }

    /// Height of the live mirror on a page this wide: the whole camera
    /// picture at full width, with nothing cropped.
    static func height(pageWidth: CGFloat, aspectRatio: CGFloat) -> CGFloat {
        let pictureWidth = max(0, pageWidth - 2 * padding)
        return (pictureWidth / max(aspectRatio, 0.1)).rounded() + 2 * padding
    }

    /// True while the mirror shows on a page: it is on and the page holds
    /// the Mirror tile.
    static func isShown(isOn: Bool, placements: [NookWidgetPlacement]) -> Bool {
        isOn && placements.contains { $0.kind == .mirror }
    }

    /// True when a page that held the Mirror tile no longer does. The
    /// mirror turns off then, which keeps a tile that is put back later
    /// from starting the camera by itself.
    static func losesTile(from old: [NookWidgetPlacement], to new: [NookWidgetPlacement]) -> Bool {
        old.contains { $0.kind == .mirror } && !new.contains { $0.kind == .mirror }
    }

    /// Height the mirror adds above the grid while it is on: the mirror
    /// and one row gap under it.
    static func pageHeight(_ mirrorHeight: CGFloat?) -> CGFloat {
        guard let mirrorHeight else { return 0 }
        return mirrorHeight + NookWidgetLayout.rowSpacing
    }
}

/// The Mirror widget's tile on the Nook page. It is a switch for the camera
/// and never the camera itself: opening the Nook does not turn the camera
/// on. Clicking the tile shows `NookMirrorView` at the top of the page,
/// where it stays until it is turned off.
struct NookMirrorCard: View {
    var nook: NookModel

    static let height: CGFloat = 90

    /// Height at each size. Small rows always use the grid's shared height.
    static func height(for size: NookWidgetSize) -> CGFloat {
        switch size {
        case .small: NookWidgetLayout.smallHeight
        case .medium: height
        case .large: 110
        }
    }

    private static let cornerRadius: CGFloat = 16

    @Environment(\.nookWidgetSize) private var size

    var body: some View {
        let isOn = nook.isMirrorOn
        Button {
            // A long press enters edit mode before the button lets go. That
            // release must not also flip the switch.
            guard !nook.isEditingLayout else { return }
            withMotion(Motion.reflow) { nook.isMirrorOn.toggle() }
        } label: {
            Group {
                if size == .small {
                    compactBody(isOn)
                } else {
                    wideBody(isOn)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NookCardBackground())
            .hoverHighlight(cornerRadius: Self.cornerRadius)
            .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .motionAnimation(Motion.selection, value: isOn)
        .accessibilityLabel(isOn ? "Turn the mirror off" : "Turn the mirror on")
    }

    private func compactBody(_ isOn: Bool) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                cameraIcon(isOn, size: 13)
                Text("Mirror")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Text(isOn ? "On, above your widgets" : "Camera is off")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            switchLabel(isOn)
        }
        .padding(.horizontal, 10)
    }

    private func wideBody(_ isOn: Bool) -> some View {
        HStack(spacing: 12) {
            cameraIcon(isOn, size: 16)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
            VStack(alignment: .leading, spacing: 3) {
                Text("Mirror")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(isOn ? "Showing above your widgets until you turn it off." : "The camera stays off until you turn it on.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(size == .large ? 2 : 1)
                    .minimumScaleFactor(0.9)
            }
            Spacer(minLength: 8)
            switchLabel(isOn)
        }
        .padding(.horizontal, 14)
    }

    private func cameraIcon(_ isOn: Bool, size: CGFloat) -> some View {
        Image(systemName: isOn ? "camera.fill" : "camera")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(isOn ? Color.green : Color.white.opacity(0.6))
            .contentTransition(.symbolEffect(.replace))
    }

    /// The tile is the button; this is the part that reads as one.
    private func switchLabel(_ isOn: Bool) -> some View {
        Text(isOn ? "Turn off" : "Turn on")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(Capsule().fill(isOn ? Color.green.opacity(0.25) : Color.white.opacity(0.1)))
            .fixedSize()
    }
}

/// The live mirror at the top of the Nook page, above the widgets. It owns
/// the camera: the session starts when this appears and stops when it goes,
/// which is when the mirror is turned off or the island leaves the Nook page.
struct NookMirrorView: View {
    var nook: NookModel

    private static let padding = NookMirrorLayout.padding
    private static let cornerRadius: CGFloat = 12
    private static let closeHitArea: CGFloat = 22

    private var controller: NookMirrorController { .shared }

    var body: some View {
        Group {
            switch controller.authorization {
            case .authorized:
                if controller.hasCamera {
                    NookCameraPreview(session: controller.session)
                        .overlay {
                            NookMirrorDecorationOverlay(decorations: nook.mirrorDecorations)
                                .allowsHitTesting(false)
                        }
                        .overlay { NookMirrorDecorationEditor(nook: nook) }
                        .overlay { NookPhotoBoothOverlay(nook: nook) }
                        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                        // Clipping cuts the drawing, not the clicks: without this a
                        // sticker handle that hangs past the picture's edge takes
                        // presses meant for what sits above the mirror.
                        .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                } else {
                    message("No camera found", showButton: false)
                }
            case .notDetermined:
                message("Waiting for camera permission", showButton: false)
            default:
                message("Camera access is off", showButton: true)
            }
        }
        .padding(Self.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NookCardBackground())
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 6) {
                NookPhotoBoothButton(nook: nook)
                NookMirrorDecorationButton(nook: nook)
                ringLightButton
                closeButton
            }
            .padding(Self.padding + 6)
        }
        .onAppear { controller.attach() }
        .onDisappear { controller.detach() }
    }

    private var closeButton: some View {
        Button {
            withMotion(Motion.reflow) { nook.isMirrorOn = false }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: Self.closeHitArea, height: Self.closeHitArea)
                .background(Circle().fill(Color.black.opacity(0.55)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Turn the mirror off")
    }

    /// Lights the edge of the screen like a vanity mirror. The choice is
    /// remembered, which brings the light back with the mirror next time.
    private var ringLightButton: some View {
        let isOn = nook.isRingLightOn
        return Button {
            nook.isRingLightOn.toggle()
        } label: {
            Image(systemName: isOn ? "lightbulb.fill" : "lightbulb")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isOn ? Color.yellow : Color.white.opacity(0.9))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.closeHitArea, height: Self.closeHitArea)
                .background(Circle().fill(Color.black.opacity(0.55)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isOn ? "Turn the ring light off" : "Light your face with the screen")
        .accessibilityLabel(isOn ? "Turn the ring light off" : "Turn the ring light on")
    }

    private func message(_ text: String, showButton: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "camera")
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.35))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
            if showButton {
                Button("Open System Settings") {
                    NookMirrorController.openCameraSettings()
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
