import CoreGraphics
import Foundation

/// The pointer as a demo run sees it (D65): before a step's door runs it
/// carries out the step's gesture. The runner asks first how long that
/// takes, which lets the motion fit inside the step's pause.
@MainActor
protocol DemoPointing: AnyObject {
    /// The seconds from now until the door should run, for the target where
    /// it is now. Zero when there is nothing to do.
    func lead(for gesture: DemoGesture) -> TimeInterval
    /// Carries the gesture out and returns when the door should run. A
    /// target that is not on screen is written to the log, and this
    /// returns at once.
    func perform(_ gesture: DemoGesture, step: String) async
    /// Called right after each door. A long press lets go of the button
    /// here, once the door it held for has run.
    func doorRan()
}

/// What draws the pointer. The app's is `DemoPointerWindow`; a test passes
/// a recorder.
@MainActor
protocol DemoPointerDrawing: AnyObject {
    /// Puts the pointer at a point, at once.
    func show(at point: CGPoint)
    /// Moves it through `points`, evenly timed over `duration` seconds.
    func glide(through points: [CGPoint], duration: TimeInterval)
    /// The button goes down.
    func press(at point: CGPoint)
    /// The button comes up. A click shows its ring, a long press does not.
    func release(at point: CGPoint, showsRing: Bool)
}

/// Works out each gesture from where the pointer is and where the target
/// is, and hands the drawing the motion. Points are in AppKit's screen
/// space, the origin at the bottom left of the main display.
@MainActor
final class DemoPointerDriver: DemoPointing {
    let registry: DemoTargetRegistry
    let drawing: any DemoPointerDrawing
    private(set) var position: CGPoint
    /// Where the button is held down by a long press, until its door runs.
    private(set) var heldAt: CGPoint?
    var sleep: (TimeInterval) async -> Void
    var log: (String) -> Void
    /// The open island's frame and its screen's, nil while it is closed.
    var openIsland: () -> (island: CGRect, screen: CGRect)?

    init(
        registry: DemoTargetRegistry,
        drawing: any DemoPointerDrawing,
        start: CGPoint,
        sleep: @escaping (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(for: .seconds(seconds))
        },
        log: @escaping (String) -> Void = { line in
            print(line)
            fflush(stdout)
        },
        openIsland: @escaping () -> (island: CGRect, screen: CGRect)? = { nil }
    ) {
        self.registry = registry
        self.drawing = drawing
        position = start
        self.sleep = sleep
        self.log = log
        self.openIsland = openIsland
        drawing.show(at: start)
    }

    /// Where the gesture takes the pointer, nil when it goes nowhere.
    func destination(for gesture: DemoGesture) -> CGPoint? {
        switch gesture {
        case .none:
            nil
        case .leave:
            openIsland().map { DemoGlide.leavePoint(from: position, island: $0.island, screen: $0.screen) }
        case .click(let target), .hold(let target), .enter(let target):
            registry.point(of: target)
        }
    }

    func lead(for gesture: DemoGesture) -> TimeInterval {
        guard let end = destination(for: gesture) else { return 0 }
        return DemoGlide.lead(for: gesture, glide: DemoGlide.duration(from: position, to: end))
    }

    func perform(_ gesture: DemoGesture, step: String) async {
        guard let end = destination(for: gesture) else {
            if let target = gesture.target {
                log("DEMO no target on screen for \(step): \(target)")
            }
            return
        }
        let glide = DemoGlide.duration(from: position, to: end)
        drawing.glide(through: DemoGlide.frames(from: position, to: end), duration: glide)
        position = end
        await sleep(glide)
        switch gesture {
        case .click:
            await sleep(DemoGlide.settle)
            drawing.press(at: end)
            await sleep(DemoGlide.pressDown)
            drawing.release(at: end, showsRing: true)
            await sleep(DemoGlide.pressUp)
        case .hold:
            await sleep(DemoGlide.settle)
            drawing.press(at: end)
            heldAt = end
            await sleep(DemoGlide.hold)
        case .enter:
            await sleep(DemoGlide.hover)
        case .leave, .none:
            break
        }
    }

    func doorRan() {
        guard let point = heldAt else { return }
        heldAt = nil
        drawing.release(at: point, showsRing: false)
    }
}
