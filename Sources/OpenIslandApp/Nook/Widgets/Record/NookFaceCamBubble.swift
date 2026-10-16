import AppKit
import AVFoundation
import OSLog

private let faceCamLog = Logger(subsystem: "app.openisland", category: "record")

/// Where the bubble first appears.
enum NookFaceCamPlacement: Equatable, Sendable {
    /// Where it was left, or the bottom left corner of the screen the island is on.
    case corner
    /// Inside a drawn area, at its bottom left corner. The rectangle is in the
    /// display's points, origin at the top left, as the area picker gives it.
    case insideArea(CGDirectDisplayID, CGRect)

    static func of(_ target: NookRecordTarget) -> NookFaceCamPlacement {
        if case let .area(displayID, rect) = target { return .insideArea(displayID, rect) }
        return .corner
    }
}

/// Shows and hides the face cam bubble. The real one is a floating panel,
/// and a test gives the model a fake, which keeps it from opening a window
/// or starting the camera.
@MainActor
protocol NookFaceCamPresenting: AnyObject {
    func show(placement: NookFaceCamPlacement)
    func hide()
    /// Told when the bubble cannot show a picture, or loses it. The bubble has
    /// already closed itself by then.
    var onProblem: ((NookFaceCamProblem) -> Void)? { get set }
}

/// The three sizes in the bubble's menu. Dragging its edge gives any size
/// between the smallest and the largest.
enum NookFaceCamSize: CaseIterable, Sendable {
    case small
    case medium
    case large

    var diameter: CGFloat {
        switch self {
        case .small: NookFaceCamLayout.minimumDiameter
        case .medium: NookFaceCamLayout.defaultDiameter
        case .large: 240
        }
    }

    var titleKey: String {
        switch self {
        case .small: "nook.record.facecam.size.small"
        case .medium: "nook.record.facecam.size.medium"
        case .large: "nook.record.facecam.size.large"
        }
    }
}

/// Plain sizing rules for the bubble. An enum and not part of a view, which
/// keeps them callable from tests off the main actor.
enum NookFaceCamLayout {
    static let minimumDiameter: CGFloat = 120
    static let maximumDiameter: CGFloat = 360
    static let defaultDiameter: CGFloat = 160
    /// A press this close to the circle's edge, or past it, resizes. A press
    /// inside moves the bubble.
    static let edgeBand: CGFloat = 16
    /// Space between the bubble and the screen's corner when it first appears.
    static let margin: CGFloat = 24
    /// Space between the bubble and the corner of the area it starts in.
    static let areaInset: CGFloat = 16
    /// The smallest bubble that is made to fit a small area. Smaller than the
    /// 120 pt the person can drag it down to, on purpose: it has to fit.
    static let smallestFitted: CGFloat = 48

    static func clamped(_ diameter: CGFloat) -> CGFloat {
        min(max(diameter, minimumDiameter), maximumDiameter)
    }

    /// The diameter that puts the circle's edge under the pointer, with the
    /// center staying where it is.
    static func diameter(draggingTo point: CGPoint, center: CGPoint) -> CGFloat {
        clamped(2 * hypot(point.x - center.x, point.y - center.y))
    }

    /// Whether a point in a view of this diameter, origin at its corner, is
    /// on the edge band.
    static func isOnEdge(_ point: CGPoint, diameter: CGFloat) -> Bool {
        let radius = diameter / 2
        let distance = hypot(point.x - radius, point.y - radius)
        return distance >= radius - edgeBand
    }

    /// The frame of a bubble of this diameter with the same center.
    static func resized(_ frame: CGRect, to diameter: CGFloat) -> CGRect {
        let size = clamped(diameter)
        return CGRect(x: frame.midX - size / 2, y: frame.midY - size / 2, width: size, height: size)
    }

    /// Where the bubble starts in an area: its bottom left corner, inset. `area`
    /// is in the display's points with the origin at the top left, `screenFrame`
    /// is the display's frame in screen coordinates, origin at the bottom left.
    /// A bubble too big for the area is made smaller to fit.
    static func startFrame(insideArea area: CGRect, onScreen screenFrame: CGRect, diameter: CGFloat = defaultDiameter) -> CGRect {
        let room = min(area.width, area.height) - 2 * areaInset
        let size = min(diameter, max(smallestFitted, room))
        return CGRect(
            x: screenFrame.minX + area.minX + areaInset,
            y: screenFrame.maxY - area.maxY + areaInset,
            width: size,
            height: size
        )
    }

    /// Where the bubble first appears: the bottom left of the visible screen.
    static func startFrame(in visible: CGRect, diameter: CGFloat = defaultDiameter) -> CGRect {
        CGRect(x: visible.minX + margin, y: visible.minY + margin, width: diameter, height: diameter)
    }
}

// MARK: - Camera

private final class FaceCamSessionBox: @unchecked Sendable {
    let session = AVCaptureSession()
}

/// The bubble's own camera session, on the device the Mirror uses. The
/// Mirror is off while the bubble is up, so the camera has one owner.
@MainActor
private final class NookFaceCamCamera {
    private let box = FaceCamSessionBox()
    private let queue = DispatchQueue(label: "app.openisland.record.facecam")
    private var isStopped = false
    private var watch: NookCaptureSessionWatch?

    var session: AVCaptureSession { box.session }

    /// Starts the camera, asking macOS first if it has not been asked.
    /// `onProblem` runs when there is no camera, no access to it, it will
    /// not start, or it stops on its own later.
    func start(onProblem: @escaping @MainActor (NookFaceCamProblem) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if let problem = NookFaceCamRules.problem(for: status) {
            onProblem(problem)
            return
        }
        guard status == .notDetermined else {
            run(onProblem: onProblem)
            return
        }
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor [weak self] in
                guard let self, !isStopped else { return }
                if granted { run(onProblem: onProblem) } else { onProblem(.noAccess) }
            }
        }
    }

    func stop() {
        isStopped = true
        watch?.stop()
        watch = nil
        let box = box
        queue.async {
            if box.session.isRunning { box.session.stopRunning() }
            box.session.beginConfiguration()
            for input in box.session.inputs { box.session.removeInput(input) }
            box.session.commitConfiguration()
        }
    }

    private func run(onProblem: @escaping @MainActor (NookFaceCamProblem) -> Void) {
        guard let device = NookMirrorDevices.selectedDevice() else {
            onProblem(.noCamera)
            return
        }
        // A camera that fails after it started is reported too, so the bubble
        // closes instead of recording a frozen picture.
        watch = NookCaptureSessionWatch(session: box.session) { problem in
            faceCamLog.error("record: the face cam session reported \(String(describing: problem), privacy: .public)")
            Task { @MainActor in onProblem(.stopped) }
        }
        let deviceID = device.uniqueID
        let box = box
        queue.async {
            guard let device = AVCaptureDevice(uniqueID: deviceID) else {
                faceCamLog.error("record: the face cam device is gone")
                Task { @MainActor in onProblem(.noCamera) }
                return
            }
            let input: AVCaptureDeviceInput
            do {
                input = try AVCaptureDeviceInput(device: device)
            } catch {
                faceCamLog.error("record: the face cam could not be opened: \(NookRecordRules.describe(error), privacy: .public)")
                Task { @MainActor in onProblem(.cameraFailed) }
                return
            }
            guard box.session.canAddInput(input) else {
                faceCamLog.error("record: the face cam could not be added to its session")
                Task { @MainActor in onProblem(.cameraFailed) }
                return
            }
            box.session.beginConfiguration()
            box.session.addInput(input)
            box.session.commitConfiguration()
            box.session.startRunning()
            if !box.session.isRunning {
                faceCamLog.error("record: the face cam session did not start")
                Task { @MainActor in onProblem(.cameraFailed) }
            }
        }
    }
}

// MARK: - Panel

/// Never key and never main: a press on the bubble must not take the
/// keyboard from what the person is recording.
private final class NookFaceCamPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The round picture. A press near its edge resizes it, a press inside
/// moves it, and a right click offers the three sizes.
private final class NookFaceCamView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer
    private var isResizing = false
    /// Asked for a new diameter, in points.
    var onResize: ((CGFloat) -> Void)?

    init(session: AVCaptureSession, frame: NSRect) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor
        layer?.borderWidth = 2
        // The picture fills the circle, cut at its edge. It is not mirrored:
        // what the camera sees is what ends up in the video.
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if NookFaceCamLayout.isOnEdge(point, diameter: bounds.width) {
            isResizing = true
        } else {
            window?.performDrag(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isResizing, let window else { return }
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        onResize?(NookFaceCamLayout.diameter(draggingTo: NSEvent.mouseLocation, center: center))
    }

    override func mouseUp(with event: NSEvent) {
        isResizing = false
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        for size in NookFaceCamSize.allCases {
            let item = NSMenuItem(title: LanguageManager.shared.t(size.titleKey), action: #selector(pickSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = size.diameter
            menu.addItem(item)
        }
        return menu
    }

    @objc private func pickSize(_ item: NSMenuItem) {
        guard let diameter = item.representedObject as? CGFloat else { return }
        onResize?(diameter)
    }
}

// MARK: - Bubble

/// The face cam bubble: a round, borderless panel that floats above the
/// other windows, shows the camera and is part of what the screen records.
/// It remembers where it was and how big, for the next recording.
@MainActor
final class NookFaceCamBubble: NookFaceCamPresenting {
    private let screen: @MainActor () -> NSScreen?
    private var panel: NookFaceCamPanel?
    private var camera: NookFaceCamCamera?
    private var rememberedFrame: NSRect?

    var onProblem: ((NookFaceCamProblem) -> Void)?

    /// `screen` is the one the island is on, where the bubble first appears.
    init(screen: @escaping @MainActor () -> NSScreen?) {
        self.screen = screen
    }

    func show(placement: NookFaceCamPlacement) {
        guard panel == nil else { return }
        let frame = startFrame(for: placement)
        let camera = NookFaceCamCamera()
        let view = NookFaceCamView(session: camera.session, frame: NSRect(origin: .zero, size: frame.size))
        view.onResize = { [weak self] diameter in self?.resize(to: diameter) }

        let panel = NookFaceCamPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = view
        panel.orderFrontRegardless()

        self.panel = panel
        self.camera = camera
        camera.start { [weak self] problem in self?.closeForProblem(problem) }
    }

    func hide() {
        // A bubble already closed by a problem keeps the place it was left.
        if let frame = panel?.frame { rememberedFrame = frame }
        camera?.stop()
        camera = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    /// A picture that cannot be shown would be recorded as it is, so the
    /// bubble closes instead and the model says why.
    private func closeForProblem(_ problem: NookFaceCamProblem) {
        guard panel != nil else { return }
        faceCamLog.error("record: the face cam is off: \(String(describing: problem), privacy: .public)")
        hide()
        onProblem?(problem)
    }

    private func resize(to diameter: CGFloat) {
        guard let panel else { return }
        panel.setFrame(NookFaceCamLayout.resized(panel.frame, to: diameter), display: true)
    }

    private func startFrame(for placement: NookFaceCamPlacement) -> NSRect {
        switch placement {
        case .corner:
            return rememberedFrame ?? cornerFrame()
        case let .insideArea(displayID, area):
            // The size the person left it at, the place the area says: where it was
            // left may be outside this area.
            let target = NSScreen.nookScreen(for: displayID) ?? screen() ?? NSScreen.main
            guard let screenFrame = target?.frame else { return rememberedFrame ?? cornerFrame() }
            return NookFaceCamLayout.startFrame(
                insideArea: area, onScreen: screenFrame,
                diameter: rememberedFrame?.width ?? NookFaceCamLayout.defaultDiameter
            )
        }
    }

    private func cornerFrame() -> NSRect {
        let visible = (screen() ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        return NookFaceCamLayout.startFrame(in: visible)
    }
}
