import AppKit
import Foundation

/// What a demo script calls. The app's implementation is `AppDemoDoors`; a
/// test passes a recorder.
@MainActor
protocol DemoDoors: AnyObject {
    func perform(_ action: DemoAction)
    /// One key press in a field: `text` is what the field holds after it
    /// (D65).
    func type(_ text: String, into field: DemoTypingField)
    /// Return in a field.
    func submit(_ field: DemoTypingField)
}

/// Runs one demo script (D51): waits each step's pause, prints one line
/// and calls the door. A typing step then types its text one key at a
/// time. After the last step it waits two seconds and quits. The clock,
/// the waiting, the printing, the pointer and the quitting are handed in,
/// which lets a test run a script with no waiting.
@MainActor
struct DemoRunner {
    var now: () -> Date = Date.init
    var sleep: (TimeInterval) async -> Void = { seconds in
        try? await Task.sleep(for: .seconds(seconds))
    }
    var log: (String) -> Void = { line in
        print(line)
        fflush(stdout)
    }
    var quit: () -> Void = { NSApp.terminate(nil) }
    /// The drawn pointer (D65). Nil runs the steps with no pointer.
    var pointer: (any DemoPointing)?

    func run(_ script: DemoScript, doors: any DemoDoors, launchedAt: Date) async {
        for step in script.steps {
            await reach(step)
            log(Self.line(since: launchedAt, now: now(), name: step.name))
            doors.perform(step.action)
            pointer?.doorRan()
            if let typing = step.action.typing {
                await type(typing, doors: doors)
            }
        }
        await sleep(DemoScript.endPause)
        quit()
    }

    /// The step's pause, with the pointer's motion at the end of it: the
    /// pointer leaves in time to press the control when the pause is up.
    /// A target that is not on screen takes no time, and the door still
    /// runs.
    ///
    /// The pause is waited in two parts. The first is what no glide of this
    /// gesture can need, and only after it is the target looked up: a
    /// control the last door brought on screen has no place until the
    /// views have drawn.
    private func reach(_ step: DemoStep) async {
        let gesture = step.action.gesture
        guard let pointer, gesture != .none else {
            await sleep(step.pause)
            return
        }
        let budget = min(step.pause, DemoGlide.lead(for: gesture, glide: DemoGlide.longest))
        await sleep(step.pause - budget)
        let lead = min(budget, pointer.lead(for: gesture))
        await sleep(budget - lead)
        await pointer.perform(gesture, step: step.name)
    }

    /// One key at a time, at a person's pace, then Return when the step
    /// asks for it.
    private func type(_ typing: DemoTypingRun, doors: any DemoDoors) async {
        let gaps = typing.gaps
        for (index, text) in typing.prefixes.enumerated() {
            await sleep(gaps[index])
            doors.type(text, into: typing.field)
        }
        guard typing.pressesReturn, let last = gaps.last else { return }
        await sleep(last)
        doors.submit(typing.field)
    }

    /// `DEMO 12.40 open-island`: the seconds since launch, then the name.
    static func line(since launchedAt: Date, now: Date, name: String) -> String {
        String(format: "DEMO %.2f %@", now.timeIntervalSince(launchedAt), name)
    }
}
