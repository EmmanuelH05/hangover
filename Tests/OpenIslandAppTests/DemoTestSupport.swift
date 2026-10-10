import Foundation
@testable import OpenIslandApp

// Shared by the demo mode's tests (D51). Nothing here shows a window, moves
// the pointer or reads the real settings, clipboard or calendar.

/// A demo session built for a test: the panel is never put on screen and
/// every file goes into a folder of its own under the temporary directory.
@MainActor
struct DemoFixture {
    /// A fixed moment, 2027-01-15 08:00:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let environment = [DemoMode.switchKey: "1"]

    let session: DemoSession
    let root: URL

    var model: AppModel { session.model }
    var nook: NookModel { session.model.nook }

    init(
        script: String? = nil,
        now: Date = DemoFixture.now,
        weatherTransport: any NookWeatherTransport = DemoWeatherTransport()
    ) {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hangover-demo-tests-\(UUID().uuidString)", isDirectory: true)
        var environment = Self.environment
        if let script { environment[DemoMode.scriptKey] = script }
        session = DemoSession(
            environment: environment,
            now: now,
            temporary: root,
            putsPanelOnScreen: false,
            weatherTransport: weatherTransport
        )
    }

    /// Starts the services that hold sample content, one by one. The
    /// model's whole `start()` also listens to the sound hardware and the
    /// battery, which a test leaves alone.
    func startSampleServices() {
        nook.media.start()
        nook.calendar.start(nook: nook)
        nook.reminders.start(nook: nook)
        nook.notes.start(nook: nook)
        nook.tray.start(nook: nook)
        nook.weather.start(nook: nook)
    }

    func remove() {
        nook.timer.reset()
        try? FileManager.default.removeItem(at: root)
    }
}

/// A door that writes down what it was asked to do.
@MainActor
final class RecordingDoors: DemoDoors {
    private(set) var actions: [DemoAction] = []

    func perform(_ action: DemoAction) {
        actions.append(action)
    }
}

/// A clock that does not wait. Sleeping adds to the time and writes it down.
@MainActor
final class InstantClock {
    private(set) var now: Date
    private(set) var sleeps: [TimeInterval] = []
    private(set) var lines: [String] = []
    private(set) var quitCount = 0

    init(start: Date = DemoFixture.now) {
        now = start
    }

    var runner: DemoRunner {
        DemoRunner(
            now: { self.now },
            sleep: { seconds in
                self.sleeps.append(seconds)
                self.now = self.now.addingTimeInterval(seconds)
            },
            log: { self.lines.append($0) },
            quit: { self.quitCount += 1 }
        )
    }
}
