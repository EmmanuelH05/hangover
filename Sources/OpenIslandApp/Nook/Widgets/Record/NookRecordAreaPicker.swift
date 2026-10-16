import AppKit
import CoreGraphics

/// Lets the person draw the part of a display to record. The real one is a
/// veil over the display, and a test gives the model a fake, which keeps it
/// from opening a window.
@MainActor
protocol NookRecordAreaPicking: AnyObject {
    /// Returns the rectangle in the display's points, origin at the top left,
    /// or nil when the person gave up.
    func pick(on displayID: CGDirectDisplayID) async -> CGRect?
}

/// Plain rules for the drawn rectangle.
enum NookRecordAreaRules {
    /// A rectangle smaller than this on either side is a slip of the hand.
    static let minimumSide: CGFloat = 16

    /// The rectangle between two corners, whichever way it was dragged.
    static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    static func isUsable(_ rect: CGRect) -> Bool {
        rect.width >= minimumSide && rect.height >= minimumSide
    }

    /// The part of `rect` inside a display of this size. Nil when none is.
    static func clamped(_ rect: CGRect, toDisplayOfSize size: CGSize) -> CGRect? {
        let inside = rect.intersection(CGRect(origin: .zero, size: size))
        return inside.isNull || !isUsable(inside) ? nil : inside
    }
}

extension NSScreen {
    /// The display this screen is, as the recorder names it.
    var nookDisplayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func nookScreen(for displayID: CGDirectDisplayID) -> NSScreen? {
        screens.first { $0.nookDisplayID == displayID }
    }
}

// MARK: - Panel and view

/// Needs the keyboard for Escape and Return, and still leaves the app being
/// recorded as the active one.
private final class NookAreaPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The dark veil with a clear hole where the rectangle is drawn. The view
/// is flipped, so a point in it is a point on the display, top left origin.
private final class NookAreaView: NSView {
    /// Told the rectangle, or nil for Escape.
    var onDone: ((CGRect?) -> Void)?
    private var anchor: CGPoint?
    private var selection: CGRect?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        let veil = NSBezierPath(rect: bounds)
        if let selection { veil.append(NSBezierPath(rect: selection)) }
        veil.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.4).setFill()
        veil.fill()

        if let selection {
            let outline = NSBezierPath(rect: selection)
            outline.lineWidth = 1.5
            NSColor.white.setStroke()
            outline.stroke()
            drawSize(of: selection)
        } else {
            drawHint()
        }
    }

    private func drawHint() {
        let text = LanguageManager.shared.t("nook.record.area.hint") as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }

    private func drawSize(of rect: CGRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        // Under the rectangle, or inside it at the bottom when it reaches the edge.
        let below = rect.maxY + 6 + size.height <= bounds.maxY
        let y = below ? rect.maxY + 6 : rect.maxY - size.height - 6
        text.draw(at: CGPoint(x: rect.minX, y: y), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        selection = NookRecordAreaRules.rect(from: anchor, to: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { anchor = nil }
        guard let selection else { return }
        // A rectangle too small to mean anything is drawn again.
        guard let usable = NookRecordAreaRules.clamped(selection, toDisplayOfSize: bounds.size) else {
            self.selection = nil
            needsDisplay = true
            return
        }
        onDone?(usable)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case AgentHotkeyKeyboard.escape:
            onDone?(nil)
        case 36, 76:
            // Return, Enter: confirm what is drawn.
            if let selection, let usable = NookRecordAreaRules.clamped(selection, toDisplayOfSize: bounds.size) {
                onDone?(usable)
            }
        default:
            super.keyDown(with: event)
        }
    }
}

// MARK: - Picker

/// The drag-out overlay over one display.
@MainActor
final class NookRecordAreaPicker: NookRecordAreaPicking {
    private var panel: NookAreaPanel?
    private var continuation: CheckedContinuation<CGRect?, Never>?

    func pick(on displayID: CGDirectDisplayID) async -> CGRect? {
        // One overlay at a time.
        guard panel == nil, let screen = NSScreen.nookScreen(for: displayID) ?? NSScreen.main else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            show(on: screen)
        }
    }

    private func show(on screen: NSScreen) {
        let panel = NookAreaPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let view = NookAreaView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onDone = { [weak self] rect in self?.finish(rect) }
        panel.contentView = view
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
        self.panel = panel
    }

    private func finish(_ rect: CGRect?) {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        let waiting = continuation
        continuation = nil
        waiting?.resume(returning: rect)
    }
}
