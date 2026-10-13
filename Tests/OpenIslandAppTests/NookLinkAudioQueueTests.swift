import Foundation
import Testing
@testable import OpenIslandApp

// The queue as pure value logic: one running, up to five waiting in the
// order they came, and the last five finished.

@Suite struct NookLinkAudioQueueTests {
    private func job(_ number: Int) throws -> NookLinkAudioJob {
        NookLinkAudioJob(id: UUID(), link: try NookLinkAudioLink.check("https://example.com/\(number)").get())
    }

    private let now = Date(timeIntervalSince1970: 1_000)

    @Test func aNewQueueIsEmpty() {
        var queue = NookLinkAudioQueue()
        #expect(queue.isEmpty)
        #expect(!queue.hasActiveJob)
        #expect(queue.all.isEmpty)
        let started = queue.startNext(now: now)
        #expect(started == nil)
    }

    @Test func theFirstInLineRunsAndTheRestKeepTheirOrder() throws {
        var queue = NookLinkAudioQueue()
        let jobs = try (1...4).map(job)
        for item in jobs { let added = queue.add(item); #expect(added) }

        let startedJob = queue.startNext(now: now)
        let started = try #require(startedJob)
        #expect(started.id == jobs[0].id)
        #expect(started.startedAt == now)
        #expect(started.phase == .downloading(fraction: nil))
        #expect(queue.running?.id == jobs[0].id)
        #expect(queue.waiting.map(\.id) == jobs[1...].map(\.id))
        #expect(queue.all.map(\.id) == jobs.map(\.id))
    }

    @Test func nothingStartsWhileOneIsRunning() throws {
        var queue = NookLinkAudioQueue()
        queue.add(try job(1))
        queue.add(try job(2))
        _ = queue.startNext(now: now)
        let started = queue.startNext(now: now)
        #expect(started == nil)
        #expect(queue.waiting.count == 1)
    }

    @Test func sixWaitingAreRefusedAndFiveAreKept() throws {
        var queue = NookLinkAudioQueue()
        let jobs = try (1...6).map(job)
        for item in jobs.prefix(5) { let added = queue.add(item); #expect(added) }
        let sixth = queue.add(jobs[5])
        #expect(!sixth)
        #expect(queue.waiting.map(\.id) == jobs.prefix(5).map(\.id))
    }

    @Test func oneRunningAndFiveWaitingIsTheFullLine() throws {
        var queue = NookLinkAudioQueue()
        let jobs = try (1...7).map(job)
        let first = queue.add(jobs[0])
        #expect(first)
        _ = queue.startNext(now: now)
        for item in jobs[1...5] { let added = queue.add(item); #expect(added) }
        let seventh = queue.add(jobs[6])
        #expect(!seventh)
        #expect(queue.all.count == 6)
    }

    @Test func aFinishedJobMakesRoomAndTheNextOneStartsInOrder() throws {
        var queue = NookLinkAudioQueue()
        let jobs = try (1...7).map(job)
        queue.add(jobs[0])
        let firstJob = queue.startNext(now: now)
        let first = try #require(firstJob)
        for item in jobs[1...5] { queue.add(item) }
        #expect(queue.waiting.count == 5)
        queue.finishRunning(first.id, as: .done(nil))
        // The service starts the next one as soon as one ends, which is what frees a place in line.
        let secondJob = queue.startNext(now: now)
        let second = try #require(secondJob)
        let added = queue.add(jobs[6])
        #expect(added)
        #expect(second.id == jobs[1].id)
        #expect(queue.waiting.map(\.id) == [jobs[2], jobs[3], jobs[4], jobs[5], jobs[6]].map(\.id))
    }

    @Test func theLastFiveFinishedStayNewestFirst() throws {
        var queue = NookLinkAudioQueue()
        let jobs = try (1...8).map(job)
        for item in jobs {
            queue.add(item)
            let runningJob = queue.startNext(now: now)
        let running = try #require(runningJob)
            queue.finishRunning(running.id, as: item.id == jobs[2].id ? .failed(.offline) : .done(nil))
        }
        #expect(queue.finished.count == 5)
        #expect(queue.finished.map(\.id) == jobs.suffix(5).reversed().map(\.id))
        #expect(queue.running == nil)
    }

    @Test func aFailedJobCountsAmongTheFinished() throws {
        var queue = NookLinkAudioQueue()
        let item = try job(1)
        queue.add(item)
        _ = queue.startNext(now: now)
        queue.finishRunning(item.id, as: .failed(.unavailable))
        #expect(queue.finished.first?.phase == .failed(.unavailable))
        #expect(queue.finished.first?.phase.isFinished == true)
    }

    @Test func theListIsRunningThenWaitingThenFinished() throws {
        var queue = NookLinkAudioQueue()
        let jobs = try (1...4).map(job)
        queue.add(jobs[0])
        _ = queue.startNext(now: now)
        queue.finishRunning(jobs[0].id, as: .done(nil))
        for item in jobs[1...] { queue.add(item) }
        _ = queue.startNext(now: now)
        #expect(queue.all.map(\.id) == [jobs[1].id, jobs[2].id, jobs[3].id, jobs[0].id])
    }

    @Test func aWaitingJobCanBeTakenOutAndTheRestKeepTheirOrder() throws {
        var queue = NookLinkAudioQueue()
        let jobs = try (1...5).map(job)
        for item in jobs { queue.add(item) }
        _ = queue.startNext(now: now)
        let removed = queue.removeWaiting(jobs[2].id)
        #expect(removed)
        #expect(queue.waiting.map(\.id) == [jobs[1], jobs[3], jobs[4]].map(\.id))
        let again = queue.removeWaiting(jobs[2].id)
        #expect(!again)
        let running = queue.removeWaiting(jobs[0].id)
        #expect(!running, "the running job is not in line")
    }

    @Test func aChangeToAJobThatIsNotRunningDoesNothing() throws {
        var queue = NookLinkAudioQueue()
        let jobs = try (1...2).map(job)
        for item in jobs { queue.add(item) }
        _ = queue.startNext(now: now)
        queue.updateRunning(jobs[1].id) { $0.title = "other" }
        #expect(queue.waiting.first?.title == nil)
        queue.finishRunning(jobs[1].id, as: .done(nil))
        #expect(queue.running?.id == jobs[0].id)
        queue.dropRunning(jobs[1].id)
        #expect(queue.running?.id == jobs[0].id)
    }

    @Test func droppingTheRunningJobKeepsNothingOfIt() throws {
        var queue = NookLinkAudioQueue()
        let item = try job(1)
        queue.add(item)
        _ = queue.startNext(now: now)
        queue.dropRunning(item.id)
        #expect(queue.isEmpty)
    }

    @Test func clearingTheFinishedKeepsTheActiveJobs() throws {
        var queue = NookLinkAudioQueue()
        let jobs = try (1...3).map(job)
        for item in jobs { queue.add(item) }
        let firstJob = queue.startNext(now: now)
        let first = try #require(firstJob)
        queue.finishRunning(first.id, as: .done(nil))
        _ = queue.startNext(now: now)
        queue.clearFinished()
        #expect(queue.finished.isEmpty)
        #expect(queue.running?.id == jobs[1].id)
        queue.removeAllWaiting()
        #expect(queue.waiting.isEmpty)
        #expect(queue.running?.id == jobs[1].id)
    }

    @Test func eachPhaseKnowsWhetherItIsRunningOrFinished() {
        #expect(NookLinkAudioJob.Phase.waiting.isFinished == false)
        #expect(NookLinkAudioJob.Phase.waiting.isRunning == false)
        #expect(NookLinkAudioJob.Phase.downloading(fraction: 0.5).isRunning)
        #expect(NookLinkAudioJob.Phase.converting.isRunning)
        #expect(NookLinkAudioJob.Phase.cancelling.isRunning)
        #expect(NookLinkAudioJob.Phase.done(nil).isFinished)
        #expect(NookLinkAudioJob.Phase.failed(.other).isFinished)
        #expect(NookLinkAudioJob.Phase.done(nil).isRunning == false)
    }
}
