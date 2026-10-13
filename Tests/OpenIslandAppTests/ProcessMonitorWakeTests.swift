import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// The monitor loop runs its full pass (ps, lsof, the terminal probes) only
/// when something asks for one, and sleeps otherwise (D55). These drive the
/// real loop with a stand-in for `ps`, which keeps the tests off the real
/// process list.
@MainActor
@Suite(.timeLimit(.minutes(5)))
struct ProcessMonitorWakeTests {
    /// Counts the passes by counting the calls that would run `ps`.
    private final class PassCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private var times: [Date] = []
        var passes: Int { lock.withLock { count } }
        var passTimes: [Date] { lock.withLock { times } }
        func note() { lock.withLock { count += 1; times.append(Date()) } }
    }

    /// What the stand-in `ps` answers, changed by the test as its process
    /// comes and goes.
    private final class ProcessListing: @unchecked Sendable {
        private let lock = NSLock()
        private var line: String?
        init(line: String?) { self.line = line }
        var current: String? {
            get { lock.withLock { line } }
            set { lock.withLock { line = newValue } }
        }
    }

    private func makeCoordinator() -> (ProcessMonitoringCoordinator, PassCounter) {
        let counter = PassCounter()
        let discovery = ActiveAgentProcessDiscovery { executable, _ in
            if executable == "/bin/ps" { counter.note() }
            return nil
        }
        let coordinator = ProcessMonitoringCoordinator(discovery: discovery)
        coordinator.stateAccessor = { SessionState() }
        coordinator.stateUpdater = { _ in }
        coordinator.isResolvingInitialLiveSessions = false
        return (coordinator, counter)
    }

    private func settle(_ milliseconds: Int = 300) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    /// Waits until the condition holds, up to a deadline. The full test run
    /// blocks the main actor for twenty seconds at a stretch, and the
    /// watcher, the loop and this poll all need it, which is why a count is
    /// waited for with a long deadline and never read after a fixed pause.
    private func waitUntil(_ condition: () -> Bool, within seconds: TimeInterval = 90) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    @Test
    func theLoopRunsOnePassAtStartAndThenSleeps() async {
        let (coordinator, counter) = makeCoordinator()
        defer { coordinator.stopMonitoring() }
        coordinator.startMonitoringIfNeeded()
        #expect(await waitUntil { counter.passes == 1 })
        await settle(1_500)
        #expect(counter.passes == 1)
    }

    /// A request right after a pass waits for the floor, and several such
    /// requests merge into the one pass that runs there.
    @Test
    func requestsCloserThanTheFloorMergeIntoOnePassAtTheFloor() async {
        let (coordinator, counter) = makeCoordinator()
        defer { coordinator.stopMonitoring() }
        coordinator.startMonitoringIfNeeded()
        #expect(await waitUntil { counter.passes == 1 })

        coordinator.requestReconcile()
        coordinator.requestReconcile()
        coordinator.requestReconcile()
        await settle(1_000)
        #expect(counter.passes == 1)
        #expect(await waitUntil { counter.passes == 2 })
        let times = counter.passTimes
        #expect(times.count == 2)
        if times.count == 2 {
            #expect(times[1].timeIntervalSince(times[0]) >= ProcessMonitoringCoordinator.requestFloorInterval - 0.5)
        }

        await settle(1_000)
        #expect(counter.passes == 2)
    }

    /// The whole path: `ps` lists an agent process, the pass watches its
    /// pid, the process ends, the watcher runs one more pass, and that pass
    /// no longer lists it. The watcher is installed by the loop itself, not
    /// by the test, because a pass drops any watcher for a process its `ps`
    /// does not list, and a test that installed one by hand raced the first
    /// pass under the full suite.
    @Test
    func aWatchedProcessEndingWakesTheLoop() async throws {
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        // Long enough to outlive the test on a busy machine. At 30 seconds
        // it ended by itself while the full suite was still getting here,
        // and the loop then made a pass every five seconds for a process
        // `ps` still listed. The test ends it, here or in the `defer`.
        sleeper.arguments = ["600"]
        try sleeper.run()
        defer { if sleeper.isRunning { sleeper.terminate() } }
        let pid = sleeper.processIdentifier

        let counter = PassCounter()
        // A Gemini process: the pass watches its pid and makes no session of
        // it, which keeps the terminal probes, and with them AppleScript,
        // out of the test. A Claude process would get a synthetic session.
        let listing = ProcessListing(line: "\(pid) 1 ttys009 /usr/local/bin/gemini")
        let discovery = ActiveAgentProcessDiscovery { executable, _ in
            guard executable == "/bin/ps" else { return nil }
            counter.note()
            return listing.current
        }
        let coordinator = ProcessMonitoringCoordinator(discovery: discovery)
        defer { coordinator.stopMonitoring() }
        coordinator.stateAccessor = { SessionState() }
        coordinator.stateUpdater = { _ in }
        coordinator.isResolvingInitialLiveSessions = false
        coordinator.startMonitoringIfNeeded()

        #expect(await waitUntil { counter.passes == 1 })
        #expect(await waitUntil { coordinator.watchedProcessIDs == [pid] })
        await settle(500)
        #expect(counter.passes == 1)

        listing.current = nil
        sleeper.terminate()
        sleeper.waitUntilExit()
        #expect(await waitUntil { counter.passes == 2 })
        #expect(await waitUntil { coordinator.watchedProcessIDs.isEmpty })
    }

    @Test
    func aProcessAlreadyGoneAsksForAPassInsteadOfAWatcher() async {
        let (coordinator, counter) = makeCoordinator()
        defer { coordinator.stopMonitoring() }
        coordinator.startMonitoringIfNeeded()
        #expect(await waitUntil { counter.passes == 1 })

        coordinator.watchExits(of: [
            ActiveAgentProcessDiscovery.ProcessSnapshot(
                tool: .claudeCode,
                sessionID: nil,
                workingDirectory: "/tmp",
                terminalTTY: "/dev/ttys009",
                pid: Int32.max - 7
            )
        ])
        #expect(coordinator.watchedProcessIDs.isEmpty)
        #expect(await waitUntil { counter.passes == 2 })
    }

    @Test
    func stoppingEndsTheLoopAndLetsGoOfTheWatchers() async throws {
        let (coordinator, counter) = makeCoordinator()
        coordinator.startMonitoringIfNeeded()
        #expect(await waitUntil { counter.passes == 1 })

        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["600"]
        try sleeper.run()
        defer { if sleeper.isRunning { sleeper.terminate() } }
        coordinator.watchExits(of: [
            ActiveAgentProcessDiscovery.ProcessSnapshot(
                tool: .claudeCode,
                sessionID: nil,
                workingDirectory: "/tmp",
                terminalTTY: "/dev/ttys009",
                pid: sleeper.processIdentifier
            )
        ])

        coordinator.stopMonitoring()
        #expect(!coordinator.isMonitoring)
        #expect(coordinator.watchedProcessIDs.isEmpty)
        let passes = counter.passes
        coordinator.requestReconcile()
        sleeper.terminate()
        sleeper.waitUntilExit()
        await settle(500)
        #expect(counter.passes == passes)
    }

    /// A fire before the wait is kept, and a fire during the wait ends it.
    /// The waits are long enough that a lost fire shows as the time limit,
    /// never as a close call under a starved main actor.
    @Test
    func theWakeReturnsWhenFiredBeforeOrDuringTheWait() async {
        let wake = ProcessMonitorWake()
        wake.fire()
        await wake.wait(for: 120)

        let waiter = Task { @MainActor in await wake.wait(for: 120) }
        try? await Task.sleep(for: .milliseconds(100))
        wake.fire()
        await waiter.value
    }
}
