import Foundation
import Testing
@testable import OpenIslandApp

/// A piece of work that never ends and ignores a request to stop, like a
/// flush stuck inside `finishWriting`. `release` lets the test end it.
final class QuitStuckWork: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var isReleased = false

    func run() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow = lock.withLock { () -> Bool in
                if isReleased { return true }
                self.continuation = continuation
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func release() {
        let held = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            isReleased = true
            defer { continuation = nil }
            return continuation
        }
        held?.resume()
    }
}

/// Which parts of a quit finished, from any task.
final class QuitProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []
    var finished: [String] { lock.withLock { names } }
    func finish(_ name: String) { lock.withLock { names.append(name) } }
}

/// Runs the wait and gives up on the test, not on the wait, if it has not
/// come back after a long time. A wait that regressed to waiting for a stuck
/// job would otherwise hang the whole run. The timer is a dispatch timer: in a
/// full run thousands of tests keep the task pool busy, and a timer that needed
/// the pool would be as late as everything else.
private func waitResult(
    for jobs: [NookQuitJob], pollEvery: Duration = .milliseconds(10), giveUpAfter seconds: Double = 120
) async -> [String]? {
    await withCheckedContinuation { (continuation: CheckedContinuation<[String]?, Never>) in
        let lock = NSLock()
        nonisolated(unsafe) var isResumed = false
        let resumeOnce: @Sendable ([String]?) -> Void = { result in
            let first = lock.withLock { () -> Bool in
                defer { isResumed = true }
                return !isResumed
            }
            if first { continuation.resume(returning: result) }
        }
        Task { resumeOnce(await NookQuitWait.run(jobs, pollEvery: pollEvery)) }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { resumeOnce(nil) }
    }
}

// Not on the main actor: other suites keep it busy for seconds at a time in a
// full run, and the helper under test does not need it to keep time.
@Suite struct NookRecordQuitTests {
    @Test func aJobThatNeverEndsIsGivenUpOnAtItsLimit() async {
        let stuck = QuitStuckWork()
        defer { stuck.release() }
        let clock = ContinuousClock()
        let start = clock.now

        // A task group would still be waiting for the job. The limit holds.
        let gaveUp = await waitResult(for: [NookQuitJob(name: "stuck", limit: .milliseconds(300)) { await stuck.run() }])

        #expect(gaveUp == ["stuck"])
        #expect(start.duration(to: clock.now) >= .milliseconds(300))
    }

    @Test func aJobThatFinishesIsNotGivenUpOn() async {
        let progress = QuitProgress()

        let gaveUp = await waitResult(for: [NookQuitJob(name: "quick", limit: .seconds(30)) { progress.finish("quick") }])

        #expect(gaveUp == [])
        #expect(progress.finished == ["quick"])
    }

    @Test func noJobsReturnAtOnce() async {
        #expect(await NookQuitWait.run([]).isEmpty)
    }

    @Test func aSlowJobWithALongerLimitOutlivesAStuckOneWithAShorterLimit() async {
        let stuck = QuitStuckWork()
        defer { stuck.release() }
        let progress = QuitProgress()

        let gaveUp = await waitResult(for: [
            NookQuitJob(name: "stuck", limit: .milliseconds(100)) { await stuck.run() },
            NookQuitJob(name: "slow", limit: .seconds(60)) {
                try? await Task.sleep(for: .milliseconds(400))
                progress.finish("slow")
            },
        ])

        #expect(gaveUp == ["stuck"])
        #expect(progress.finished == ["slow"])
    }

    @Test func aRecordingGetsLongerThanTheDesignKitsWrites() {
        #expect(NookQuitWait.recordingLimit == .seconds(10))
        #expect(NookQuitWait.writesLimit == .seconds(3))
        #expect(NookQuitWait.recordingLimit > NookQuitWait.writesLimit)
    }
}
