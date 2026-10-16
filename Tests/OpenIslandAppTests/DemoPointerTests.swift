import AppKit
import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

// The drawn pointer and the tags that tell it where controls are (D65), as
// plain values and against recorders. Nothing here shows a window, moves
// the real pointer or touches the real clipboard.

// MARK: - The glide

struct DemoGlideTests {
    @Test func aGlideTakesLongerTheFartherItGoesBetweenItsTwoBounds() {
        #expect(DemoGlide.shortest == 0.35 && DemoGlide.longest == 0.9)
        #expect(DemoGlide.duration(distance: 0) == DemoGlide.shortest)
        #expect(DemoGlide.duration(distance: DemoGlide.farDistance) == DemoGlide.longest)
        #expect(DemoGlide.duration(distance: 5000) == DemoGlide.longest)
        var last = 0.0
        for distance in stride(from: 0, through: 2000, by: 25) {
            let time = DemoGlide.duration(distance: CGFloat(distance))
            #expect(time >= last, "\(distance) points")
            #expect(time >= 0.35 && time <= 0.9)
            last = time
        }
        // From the parked corner to the notch of a laptop screen, and a hop
        // between two buttons side by side.
        let across = DemoGlide.duration(from: CGPoint(x: 1506, y: 6), to: CGPoint(x: 756, y: 966))
        #expect(across > 0.75 && across <= 0.9)
        #expect(DemoGlide.duration(from: .zero, to: CGPoint(x: 30, y: 0)) < 0.5)
    }

    @Test func aGlideStartsAndEndsExactlyAndBendsToOneSide() {
        let start = CGPoint(x: 100, y: 100)
        let end = CGPoint(x: 500, y: 100)
        let frames = DemoGlide.frames(from: start, to: end)

        #expect(frames.count == DemoGlide.frameCount + 1)
        #expect(frames.first == start)
        #expect(frames.last == end)
        // Halfway along, the curve sits off the straight line by half the
        // bend of the distance, square to the line.
        let middle = DemoGlide.point(along: 0.5, from: start, to: end)
        #expect(abs(middle.x - 300) < 1e-9)
        #expect(abs(middle.y - (100 + 400 * DemoGlide.bend / 2)) < 1e-9)
        // The same glide backward leans the other way.
        let back = DemoGlide.point(along: 0.5, from: end, to: start)
        #expect(abs(back.y - (100 - 400 * DemoGlide.bend / 2)) < 1e-9)
        // A glide to where the pointer already is goes nowhere.
        #expect(DemoGlide.frames(from: start, to: start).allSatisfy { DemoGlide.distance($0, start) < 1e-9 })
    }

    @Test func theGlideIsQuickOffTheMarkAndSlowsAsItLands() {
        #expect(DemoGlide.progress(at: 0) == 0)
        #expect(DemoGlide.progress(at: 1) == 1)
        #expect(DemoGlide.progress(at: -1) == 0 && DemoGlide.progress(at: 2) == 1)
        #expect(abs(DemoGlide.progress(at: 0.5) - 0.5) < 1e-12)
        #expect(DemoGlide.progress(at: 0.1) < 0.1)
        #expect(DemoGlide.progress(at: 0.9) > 0.9)
        for step in 1...100 {
            let time = Double(step) / 100
            #expect(DemoGlide.progress(at: time) >= DemoGlide.progress(at: time - 0.01))
            #expect(abs(DemoGlide.progress(at: time) + DemoGlide.progress(at: 1 - time) - 1) < 1e-12)
        }
        // Evenly timed frames: the pointer covers the most ground mid-glide.
        let frames = DemoGlide.frames(from: .zero, to: CGPoint(x: 1000, y: 0))
        let steps = zip(frames, frames.dropFirst()).map { DemoGlide.distance($0, $1) }
        let middle = steps[steps.count / 2]
        #expect(steps[0] < middle / 4)
        #expect(steps[steps.count - 1] < middle / 4)
    }

    @Test func leavingGoesBelowTheIslandAndStaysOnTheScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let island = CGRect(x: 532, y: 400, width: 448, height: 582)
        let start = CGPoint(x: 700, y: 600)

        let point = DemoGlide.leavePoint(from: start, island: island, screen: screen)
        #expect(point.y < island.minY)
        #expect(point.x > start.x)
        #expect(screen.insetBy(dx: DemoGlide.screenMargin - 1, dy: DemoGlide.screenMargin - 1).contains(point))

        // An island down to the screen's bottom, the pointer at its edge:
        // the point stays inside the screen.
        let tall = CGRect(x: 532, y: 10, width: 448, height: 972)
        let low = DemoGlide.leavePoint(from: CGPoint(x: 1490, y: 500), island: tall, screen: screen)
        #expect(low.y == screen.minY + DemoGlide.screenMargin)
        #expect(low.x == screen.maxX - DemoGlide.screenMargin)
    }

    @Test func eachGestureLeadsItsDoorByItsGlideAndItsPress() {
        let glide = 0.5
        #expect(DemoGlide.lead(for: .none, glide: glide) == 0)
        #expect(DemoGlide.lead(for: .click(.playPause), glide: glide)
            == glide + DemoGlide.settle + DemoGlide.pressDown + DemoGlide.pressUp)
        #expect(DemoGlide.lead(for: .hold(.widgetPage), glide: glide) == glide + DemoGlide.settle + DemoGlide.hold)
        #expect(DemoGlide.hold > 0.4, "longer than the long press that begins edit mode")
        #expect(DemoGlide.lead(for: .enter(.notch), glide: glide) == glide + DemoGlide.hover)
        #expect(DemoGlide.lead(for: .leave, glide: glide) == glide)
    }
}

// MARK: - Test doubles

/// A drawing that writes down what it was asked to draw.
@MainActor
final class RecordingPointerDrawing: DemoPointerDrawing {
    enum Event: Equatable {
        case show(CGPoint)
        case glide(to: CGPoint, duration: TimeInterval)
        case press(CGPoint)
        case release(CGPoint, ring: Bool)
    }

    private(set) var events: [Event] = []
    private let journal: DemoJournal?

    init(journal: DemoJournal? = nil) {
        self.journal = journal
    }

    var glides: [Event] {
        events.filter { if case .glide = $0 { true } else { false } }
    }

    func show(at point: CGPoint) { record(.show(point)) }
    func glide(through points: [CGPoint], duration: TimeInterval) {
        record(.glide(to: points.last ?? .zero, duration: duration))
    }
    func press(at point: CGPoint) { record(.press(point)) }
    func release(at point: CGPoint, showsRing: Bool) { record(.release(point, ring: showsRing)) }

    private func record(_ event: Event) {
        events.append(event)
        journal?.lines.append("draw \(event)")
    }
}

/// One list for the pointer and the doors, which shows their order.
@MainActor
final class DemoJournal {
    var lines: [String] = []
}

/// Doors that write into a shared journal.
@MainActor
final class JournalDoors: DemoDoors {
    let journal: DemoJournal

    init(journal: DemoJournal) {
        self.journal = journal
    }

    func perform(_ action: DemoAction) { journal.lines.append("door \(action.name)") }
    func type(_ text: String, into field: DemoTypingField) { journal.lines.append("key \(text)") }
    func submit(_ field: DemoTypingField) { journal.lines.append("return \(field.rawValue)") }
}

/// A control at a fixed place on screen.
@MainActor
final class FixedFrame: DemoTargetFrameSource {
    var demoScreenFrame: CGRect?

    init(_ frame: CGRect?) {
        demoScreenFrame = frame
    }
}

// MARK: - The registry

@MainActor
struct DemoTargetRegistryTests {
    @Test func theNewestTaggedViewThatShowsWins() {
        let registry = DemoTargetRegistry()
        let island = FixedFrame(CGRect(x: 100, y: 100, width: 30, height: 30))
        let settings = FixedFrame(nil)
        registry.add(island, for: .playPause)
        registry.add(settings, for: .playPause)

        // The newer one is not on screen, which leaves the island's.
        #expect(registry.frame(of: .playPause) == island.demoScreenFrame)
        #expect(registry.point(of: .playPause) == CGPoint(x: 115, y: 115))
        settings.demoScreenFrame = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(registry.point(of: .playPause) == CGPoint(x: 5, y: 5))
        registry.remove(settings, for: .playPause)
        #expect(registry.point(of: .playPause) == CGPoint(x: 115, y: 115))
        // An empty frame counts as not on screen.
        island.demoScreenFrame = CGRect(x: 4, y: 4, width: 0, height: 10)
        #expect(registry.frame(of: .playPause) == nil)
        #expect(registry.frame(of: .nextTrack) == nil)
    }

    @Test func aViewThatIsGoneIsForgotten() {
        let registry = DemoTargetRegistry()
        var source: FixedFrame? = FixedFrame(CGRect(x: 0, y: 0, width: 20, height: 20))
        registry.add(source!, for: .todoField)
        #expect(registry.frame(of: .todoField) != nil)
        source = nil
        #expect(registry.frame(of: .todoField) == nil)
    }

    @Test func aFrameTheAppWorksOutTakesThePlaceOfATaggedView() {
        let registry = DemoTargetRegistry()
        var notch: CGRect? = nil
        registry.provide(.notch) { notch }
        #expect(registry.point(of: .notch) == nil, "no panel yet")
        notch = CGRect(x: 656, y: 950, width: 200, height: 32)
        #expect(registry.point(of: .notch) == CGPoint(x: 756, y: 966))
    }
}

// MARK: - The tag outside the demo mode

@MainActor
@Suite(.noNewWindows)
struct DemoTagOutsideTheModeTests {
    private static func probes(in view: NSView) -> [DemoTargetProbeView] {
        (view as? DemoTargetProbeView).map { [$0] } ?? view.subviews.flatMap(probes(in:))
    }

    @Test func outsideTheDemoModeThereIsNoRegistryAndNoTypist() {
        #expect(!DemoMode.isActive)
        #expect(DemoTargetRegistry.current == nil)
        #expect(DemoTypist.current == nil)
    }

    @Test func outsideTheDemoModeTheTagNeverWorksOutItsTarget() {
        var asked = 0
        let idle = DemoTargetTag(registry: nil) {
            asked += 1
            return .playPause
        }
        #expect(idle.target == nil)
        #expect(asked == 0, "the row's place in the list is never looked up")

        let live = DemoTargetTag(registry: DemoTargetRegistry()) {
            asked += 1
            return .playPause
        }
        #expect(live.target == .playPause)
        #expect(asked == 1)
    }

    @Test func outsideTheDemoModeTheTagAddsNoView() {
        let size = CGRect(x: 0, y: 0, width: 60, height: 30)
        let idle = NSHostingView(rootView: Color.clear.frame(width: 60, height: 30).demoTarget(.playPause))
        idle.frame = size
        idle.layoutSubtreeIfNeeded()
        #expect(Self.probes(in: idle).isEmpty)

        // The same view with a registry has its probe, which shows the
        // search above can find one.
        let registry = DemoTargetRegistry()
        let live = NSHostingView(
            rootView: Color.clear.frame(width: 60, height: 30)
                .modifier(DemoTargetTag(registry: registry) { .playPause })
        )
        live.frame = size
        live.layoutSubtreeIfNeeded()
        #expect(Self.probes(in: live).map(\.target) == [.playPause])
        // Out of any window it is not on screen, and reports nothing.
        #expect(registry.frame(of: .playPause) == nil)
    }

    @Test func outsideTheDemoModeTheTypingHookHasNoTypist() {
        let hook = DemoTypingHook(field: .note, text: .constant(""), focus: nil, typist: DemoTypist.current) {}
        #expect(hook.typist == nil)
    }
}

// MARK: - The pointer in a run

@MainActor
@Suite(.noNewWindows)
struct DemoPointerRunTests {
    private static let parked = CGPoint(x: 1506, y: 6)

    @Test func aStepWhoseTargetIsMissingStillRunsItsDoorAndWaitsNoLonger() async {
        let drawing = RecordingPointerDrawing()
        var lines: [String] = []
        var pointerSleeps: [TimeInterval] = []
        let driver = DemoPointerDriver(
            registry: DemoTargetRegistry(), drawing: drawing, start: Self.parked,
            sleep: { pointerSleeps.append($0) }, log: { lines.append($0) }
        )
        let doors = RecordingDoors()
        let clock = InstantClock()
        var runner = clock.runner
        runner.pointer = driver

        await runner.run(DemoScripts.use, doors: doors, launchedAt: DemoFixture.now)

        #expect(doors.actions == DemoScripts.use.steps.map(\.action), "every door ran, in order")
        #expect(drawing.events == [.show(Self.parked)], "nothing was on screen to glide to")
        #expect(pointerSleeps.isEmpty)
        #expect(driver.position == Self.parked)
        let missed = DemoScripts.use.steps.filter { $0.action.gesture.target != nil }
        #expect(lines.count == missed.count, "one line for each missing target")
        #expect(lines.first == "DEMO no target on screen for open-island: notch")
        #expect(abs(clock.sleeps.reduce(0, +) - DemoScripts.use.duration) < 1e-9, "the run took its usual time")
        #expect(clock.quitCount == 1)
    }

    @Test func aControlOnScreenGetsAGlideAndAClickBeforeItsDoor() async {
        let journal = DemoJournal()
        let drawing = RecordingPointerDrawing(journal: journal)
        let registry = DemoTargetRegistry()
        let play = FixedFrame(CGRect(x: 600, y: 700, width: 30, height: 30))
        registry.add(play, for: .playPause)
        var pointerSleeps: [TimeInterval] = []
        var lines: [String] = []
        let driver = DemoPointerDriver(
            registry: registry, drawing: drawing, start: Self.parked,
            sleep: { pointerSleeps.append($0) }, log: { lines.append($0) }
        )
        let clock = InstantClock()
        var runner = clock.runner
        runner.pointer = driver
        let script = DemoScript(
            name: "tiny", startsPlaying: false,
            steps: [DemoStep(2, .playOrPause), DemoStep(1.5, .nextTrack)]
        )

        await runner.run(script, doors: JournalDoors(journal: journal), launchedAt: DemoFixture.now)

        let center = CGPoint(x: 615, y: 715)
        let glide = DemoGlide.duration(from: Self.parked, to: center)
        #expect(journal.lines == [
            "draw \(RecordingPointerDrawing.Event.show(Self.parked))",
            "draw \(RecordingPointerDrawing.Event.glide(to: center, duration: glide))",
            "draw \(RecordingPointerDrawing.Event.press(center))",
            "draw \(RecordingPointerDrawing.Event.release(center, ring: true))",
            "door play-pause",
            "door next-track",
        ])
        #expect(driver.position == center)
        #expect(pointerSleeps == [glide, DemoGlide.settle, DemoGlide.pressDown, DemoGlide.pressUp])
        // The glide fits inside the pause: the part no glide needs, then the
        // rest of the budget, then the motion, add up to the pause.
        let budget = DemoGlide.lead(for: .click(.playPause), glide: DemoGlide.longest)
        let lead = DemoGlide.lead(for: .click(.playPause), glide: glide)
        #expect(abs(clock.sleeps[0] - (2 - budget)) < 1e-9)
        #expect(abs(clock.sleeps[1] - (budget - lead)) < 1e-9)
        #expect(lines == ["DEMO no target on screen for next-track: nextTrack"])
    }

    @Test func theIslandOpensUnderThePointerAndLeavingOnlyMovesItWhileTheIslandIsOpen() async {
        let drawing = RecordingPointerDrawing()
        let registry = DemoTargetRegistry()
        registry.provide(.notch) { CGRect(x: 656, y: 950, width: 200, height: 32) }
        var lines: [String] = []
        let driver = DemoPointerDriver(
            registry: registry, drawing: drawing, start: Self.parked, sleep: { _ in }, log: { lines.append($0) }
        )

        // Closed: leaving has nowhere to go and says nothing.
        await driver.perform(.leave, step: "close-island")
        #expect(drawing.glides.isEmpty)
        #expect(lines.isEmpty)

        await driver.perform(.enter(.notch), step: "open-island")
        let notch = CGPoint(x: 756, y: 966)
        #expect(driver.position == notch)
        #expect(!drawing.events.contains { if case .press = $0 { true } else { false } }, "the island opens on a hover")

        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let island = CGRect(x: 532, y: 400, width: 448, height: 582)
        driver.openIsland = { (island, screen) }
        await driver.perform(.leave, step: "close-island")
        #expect(driver.position == DemoGlide.leavePoint(from: notch, island: island, screen: screen))
        #expect(driver.position.y < island.minY)
        #expect(drawing.glides.count == 2)
    }

    @Test func theLongPressHoldsLongerThanEditModeAsksAndLeavesNoRing() async {
        let drawing = RecordingPointerDrawing()
        let registry = DemoTargetRegistry()
        let page = FixedFrame(CGRect(x: 532, y: 400, width: 448, height: 500))
        registry.add(page, for: .widgetPage)
        var sleeps: [TimeInterval] = []
        let driver = DemoPointerDriver(registry: registry, drawing: drawing, start: Self.parked, sleep: { sleeps.append($0) })

        await driver.perform(.hold(.widgetPage), step: "editing-begin")

        let center = CGPoint(x: 756, y: 650)
        #expect(drawing.events.last == .press(center), "still held when the door runs")
        #expect(driver.heldAt == center)
        #expect(sleeps.last == DemoGlide.hold)

        driver.doorRan()
        #expect(drawing.events.last == .release(center, ring: false))
        #expect(driver.heldAt == nil)
        driver.doorRan()
        #expect(drawing.events.filter { if case .release = $0 { true } else { false } }.count == 1)
    }

    /// A control the last door brought on screen has no place until the views
    /// draw, which happens while the pause runs. The pointer looks for it
    /// only after the part of the pause no glide needs.
    @Test func aControlThatComesOnScreenDuringThePauseIsStillPressedOnTime() async {
        let drawing = RecordingPointerDrawing()
        let registry = DemoTargetRegistry()
        let play = FixedFrame(CGRect(x: 600, y: 700, width: 30, height: 30))
        var lines: [String] = []
        let driver = DemoPointerDriver(
            registry: registry, drawing: drawing, start: Self.parked, sleep: { _ in }, log: { lines.append($0) }
        )
        var sleeps: [TimeInterval] = []
        let doors = RecordingDoors()
        var runner = DemoRunner(
            now: { DemoFixture.now },
            sleep: { seconds in
                // The control mounts during the first wait of the pause.
                if sleeps.isEmpty { registry.add(play, for: .playPause) }
                sleeps.append(seconds)
            },
            log: { _ in },
            quit: {}
        )
        runner.pointer = driver
        let script = DemoScript(name: "tiny", startsPlaying: false, steps: [DemoStep(2, .playOrPause)])

        await runner.run(script, doors: doors, launchedAt: DemoFixture.now)

        let center = CGPoint(x: 615, y: 715)
        #expect(driver.position == center)
        #expect(drawing.glides.count == 1)
        #expect(lines.isEmpty, "the control was found")
        #expect(doors.actions == [.playOrPause])
        // The runner's waits and the motion add up to the pause.
        let motion = DemoGlide.lead(for: .click(.playPause), glide: DemoGlide.duration(from: Self.parked, to: center))
        #expect(abs(sleeps.dropLast().reduce(0, +) + motion - 2) < 1e-9)
    }
}

// MARK: - The scripts' targets

@MainActor
struct DemoScriptTargetTests {
    @Test func everyStepsTargetIsInTheListOfTargets() {
        let all = Set(DemoTarget.all)
        #expect(all.count == DemoTarget.all.count, "no target twice")
        for script in DemoScripts.all {
            for step in script.steps {
                guard let target = step.action.gesture.target else { continue }
                #expect(all.contains(target), "\(script.name): \(step.name) presses \(target)")
            }
        }
        #expect(DemoTarget.todoPositions.count == NookTodoCard.maxRows(for: .large))
    }

    /// Every step of `use` and `kit` moves the pointer but the two that
    /// apply and undo a layout, whose controls live in Settings, which no
    /// script opens.
    @Test func useAndKitPressEveryIslandStepWithThePointer() {
        for script in [DemoScripts.use, DemoScripts.kit] {
            for step in script.steps {
                switch step.action {
                case .applyTemplate, .undoTemplate:
                    #expect(step.action.gesture == .none, "\(script.name): \(step.name)")
                default:
                    #expect(step.action.gesture != .none, "\(script.name): \(step.name)")
                }
            }
        }
        #expect(DemoAction.openIsland.gesture == .enter(.notch))
        #expect(DemoAction.closeIsland.gesture == .leave)
        #expect(DemoAction.beginEditing.gesture == .hold(.widgetPage))
        #expect(DemoAction.typeNote("x").gesture == .click(.notesField))
        #expect(DemoAction.typeTodo("x").gesture == .click(.todoField))
    }

    /// A step's pause holds the longest motion its gesture can take, which
    /// keeps the pointer from making a step run late. `closed` is left out:
    /// the island stays closed there, and no control it presses is on screen.
    @Test func everyPauseHoldsItsLongestGesture() {
        for script in DemoScripts.all where script.name != DemoScripts.closed.name {
            for step in script.steps where step.action.gesture != .none {
                let longest = DemoGlide.lead(for: step.action.gesture, glide: DemoGlide.longest)
                #expect(step.pause >= longest, "\(script.name): \(step.name) waits \(step.pause) s, its gesture can take \(longest) s")
            }
        }
    }

    /// Each target a script presses is tagged on a view in the app, by the
    /// name of its case. The closed island is the exception: its frame
    /// comes from the island's panel.
    @Test func everyTargetAScriptPressesIsTaggedInTheApp() throws {
        let folder = HangoverBrandTests.repoRoot.appendingPathComponent("Sources/OpenIslandApp")
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        let source = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        #expect(source.contains("registry.provide(.notch)"))

        let targets = Set(DemoScripts.all.flatMap { $0.steps.compactMap(\.action.gesture.target) })
        for target in targets where target != .notch {
            // `.demoTarget(.widget(` for a case with a value, `.demoTarget(.editDone)`
            // for one without, which keeps `widget` from matching `widgetPage`.
            let tag = Mirror(reflecting: target).children.first?.label.map { ".demoTarget(.\($0)(" }
                ?? ".demoTarget(.\(target))"
            #expect(source.contains(tag), "\(target) is tagged nowhere")
        }
    }
}

/// What a probe counts as the shown part of its control (D65).
struct DemoProbeShownPartTests {
    /// Inside the island's scroll view `visibleRect` gives the whole page in
    /// the control's own space. Cut to the control, it is the control.
    @Test func aPageSizedVisibleRectIsCutToTheControl() {
        let bounds = CGRect(x: 0, y: 0, width: 30, height: 30)
        let page = CGRect(x: -356, y: -713, width: 480, height: 784)
        #expect(DemoTargetProbeView.shownPart(bounds: bounds, visible: page) == bounds)
    }

    @Test func aControlHalfScrolledAwayKeepsTheHalfThatShows() {
        let bounds = CGRect(x: 0, y: 0, width: 30, height: 30)
        let shown = CGRect(x: 0, y: 15, width: 200, height: 400)
        #expect(DemoTargetProbeView.shownPart(bounds: bounds, visible: shown) == CGRect(x: 0, y: 15, width: 30, height: 15))
    }

    @Test func aControlScrolledOutOfViewHasNoPlace() {
        let bounds = CGRect(x: 0, y: 0, width: 30, height: 30)
        #expect(DemoTargetProbeView.shownPart(bounds: bounds, visible: CGRect(x: 0, y: 40, width: 200, height: 100)) == nil)
        #expect(DemoTargetProbeView.shownPart(bounds: bounds, visible: .zero) == nil)
    }
}
