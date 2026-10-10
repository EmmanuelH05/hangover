import AppKit
import Foundation

/// What a demo script calls. The app's implementation is `AppDemoDoors`; a
/// test passes a recorder.
@MainActor
protocol DemoDoors: AnyObject {
    func perform(_ action: DemoAction)
}

/// Runs one demo script (D51): waits each step's pause, prints one line
/// and calls the door. After the last step it waits two seconds and quits.
/// The clock, the waiting, the printing and the quitting are handed in,
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

    func run(_ script: DemoScript, doors: any DemoDoors, launchedAt: Date) async {
        for step in script.steps {
            await sleep(step.pause)
            log(Self.line(since: launchedAt, now: now(), name: step.name))
            doors.perform(step.action)
        }
        await sleep(DemoScript.endPause)
        quit()
    }

    /// `DEMO 12.40 open-island`: the seconds since launch, then the name.
    static func line(since launchedAt: Date, now: Date, name: String) -> String {
        String(format: "DEMO %.2f %@", now.timeIntervalSince(launchedAt), name)
    }
}
