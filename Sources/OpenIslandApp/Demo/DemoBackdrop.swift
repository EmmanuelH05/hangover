import AppKit

/// A window that covers a whole screen, menu bar included, with a picture
/// scaled to fill it (D51). It ignores the mouse, never becomes key and sits
/// just under the island's panel. A recording of the screen then shows the
/// island and the app's own windows on a painting and nothing of the user's
/// desktop.
@MainActor
final class DemoBackdrop {
    private final class Window: NSWindow {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }

        /// A borderless window may cover the menu bar. The default keeps
        /// it below.
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
            frameRect
        }
    }

    private let window: Window

    /// Nil when the picture cannot be read.
    init?(imagePath: String, screen: NSScreen) {
        guard let image = NSImage(contentsOfFile: imagePath) else { return nil }
        let window = Window(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = DemoWindowLevels.island
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.contents = image
        view.layer?.contentsGravity = .resizeAspectFill
        view.layer?.masksToBounds = true
        window.contentView = view
        window.setFrame(screen.frame, display: false)
        self.window = window
    }

    /// Puts the backdrop on screen under the island's panel. The panel is
    /// ordered in after this too, which keeps it in front.
    func show(below panelWindowNumber: Int?) {
        if let panelWindowNumber {
            window.order(.below, relativeTo: panelWindowNumber)
        } else {
            window.orderFront(nil)
        }
    }

    func close() {
        window.orderOut(nil)
    }
}

/// Where the pointer waits (D51): the bottom right corner of the island's
/// screen, out of the recording and off the island.
enum DemoPointer {
    /// How far in from the two edges, in points. A hot corner sits on the
    /// corner itself.
    static let inset: CGFloat = 6

    /// The corner as CoreGraphics counts it: the origin at the top left of
    /// the main display, y growing downward. `screenFrame` is in AppKit's
    /// space, the origin at the bottom left of the main display.
    static func parkPoint(screenFrame: CGRect, mainDisplayHeight: CGFloat) -> CGPoint {
        CGPoint(x: screenFrame.maxX - inset, y: mainDisplayHeight - (screenFrame.minY + inset))
    }

    /// Moves the pointer there. Warping needs no permission, and it sends
    /// no mouse event.
    @MainActor
    static func park(on screen: NSScreen) {
        guard let main = NSScreen.screens.first else { return }
        let point = parkPoint(screenFrame: screen.frame, mainDisplayHeight: main.frame.height)
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}
