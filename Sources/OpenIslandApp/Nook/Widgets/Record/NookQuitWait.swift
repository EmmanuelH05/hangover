import Foundation
import OSLog

private let quitLog = Logger(subsystem: "app.openisland", category: "quit")

/// One thing the app waits for before it quits, and the longest it may wait.
struct NookQuitJob: Sendable {
    let name: String
    let limit: Duration
    /// Hops to the main actor itself where it needs to.
    let work: @Sendable () async -> Void
}

/// Waits for the work a quit has to finish, with a deadline that holds.
///
/// A task group waits for every child, and cancelling a child only asks it to
/// stop: a flush stuck inside `stopCapture`, `stopRunning` or `finishWriting`
/// never looks at the request, so the quit hung for good. Each job runs in a
/// task of its own that sets a flag when it ends. The wait polls the flags
/// against the clock and gives up on a job once its limit has passed, whether
/// or not the job ever ends.
enum NookQuitWait {
    /// A recording gets time to close its file. The fragments in it make a
    /// file that was cut short play anyway.
    static let recordingLimit: Duration = .seconds(10)
    /// The design kit's pending writes.
    static let writesLimit: Duration = .seconds(3)

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        var isDone: Bool { lock.withLock { done } }
        func finish() { lock.withLock { done = true } }
    }

    /// Runs `jobs` side by side and returns once each is done or past its own
    /// limit. Answers the names of the jobs the deadline ended.
    ///
    /// Neither the wait nor the jobs are tied to the main actor. A job that needs it
    /// hops there on its own, and a main actor that is busy cannot make the
    /// deadline late.
    static func run(_ jobs: [NookQuitJob], pollEvery: Duration = .milliseconds(50)) async -> [String] {
        guard !jobs.isEmpty else { return [] }
        let clock = ContinuousClock()
        let start = clock.now
        let flags = jobs.map { _ in Flag() }
        let tasks = zip(jobs, flags).map { job, flag in
            Task {
                await job.work()
                flag.finish()
            }
        }

        var pastLimit: [Int] = []
        waiting: while true {
            let elapsed = start.duration(to: clock.now)
            var isWaitingOnAny = false
            for (index, job) in jobs.enumerated() where !flags[index].isDone && !pastLimit.contains(index) {
                if elapsed >= job.limit {
                    pastLimit.append(index)
                    quitLog.error("quit: gave up on \(job.name, privacy: .public) after \(job.limit.components.seconds, privacy: .public) s")
                } else {
                    isWaitingOnAny = true
                }
            }
            guard isWaitingOnAny else { break waiting }
            do {
                try await Task.sleep(for: pollEvery)
            } catch {
                // The quit itself was cancelled. Nothing is left to wait for.
                pastLimit = jobs.indices.filter { !flags[$0].isDone }
                break waiting
            }
        }

        // Ask the stragglers to stop. Nothing waits for them.
        for index in pastLimit { tasks[index].cancel() }
        return pastLimit.map { jobs[$0].name }
    }
}
