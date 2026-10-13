import Foundation
import Testing
@testable import OpenIslandApp

// Cancel: a job in line is simply taken out. The running one is asked to
// stop, and what it wrote is removed once it has. Only files made since the
// job started ever go.

@MainActor
@Suite struct NookLinkAudioCancelTests {
    private typealias Fixture = LinkAudioFixture

    /// A job that has downloaded some of `Song [a1b2].webm`.
    private func downloading(_ fixture: Fixture) throws -> (id: UUID, run: FakeLinkAudioRunner.Run) {
        let id = try #require(fixture.submit(1).first)
        let run = try #require(fixture.runner.last)
        run.say(Fixture.titleLine("Song"))
        run.say(Fixture.progressLine(done: 40, of: 100, file: "Song [a1b2].webm"))
        return (id, run)
    }

    private func after(_ seconds: TimeInterval) -> Date { Fixture.start.addingTimeInterval(seconds) }

    // MARK: A job in line

    @Test func aJobInLineLeavesAndNeverStarts() {
        let fixture = Fixture()
        let ids = fixture.submit(4)
        fixture.service.cancel(ids[2])
        #expect(fixture.service.jobs.map(\.id) == [ids[0], ids[1], ids[3]])

        fixture.finishRunningJob()
        fixture.finishRunningJob()
        #expect(fixture.runner.runs.map(\.link) == [Fixture.link(1), Fixture.link(2), Fixture.link(4)])
        #expect(fixture.files.removed.isEmpty)
    }

    @Test func cancellingAJobInLineLeavesTheRunningOneAlone() throws {
        let fixture = Fixture()
        let ids = fixture.submit(2)
        fixture.service.cancel(ids[1])
        #expect(fixture.runner.last?.cancelCount == 0)
        #expect(fixture.service.queue.running?.id == ids[0])
    }

    // MARK: The running job

    @Test func theRunningJobIsAskedToStopOnceAndShowsItIsStopping() throws {
        let fixture = Fixture()
        let (id, run) = try downloading(fixture)
        fixture.service.cancel(id)
        fixture.service.cancel(id)
        #expect(run.cancelCount == 1)
        #expect(fixture.service.queue.job(id)?.phase == .cancelling)
        #expect(fixture.service.queue.running?.id == id, "it is running until the process has ended")
    }

    @Test func whatItWroteIsRemovedOnlyOnceTheProcessHasEnded() throws {
        let fixture = Fixture()
        fixture.now = after(0)
        let (id, run) = try downloading(fixture)
        fixture.files.entries = ["Song [a1b2].webm.part": after(5), "Song [a1b2].webm.ytdl": after(5)]

        fixture.service.cancel(id)
        #expect(fixture.files.removed.isEmpty)

        run.end(status: 130, wasSignalled: true)
        #expect(fixture.files.removed.map(\.lastPathComponent).sorted() == ["Song [a1b2].webm.part", "Song [a1b2].webm.ytdl"])
        #expect(fixture.files.removed.allSatisfy { $0.deletingLastPathComponent().path == "/Users/tester/Music/Hangover" })
        #expect(fixture.files.entries.isEmpty)
    }

    @Test func aCancelledJobIsNotKeptAmongTheFinished() throws {
        let fixture = Fixture()
        let (id, run) = try downloading(fixture)
        fixture.service.cancel(id)
        run.end(status: 130, wasSignalled: true)
        #expect(fixture.service.queue.job(id) == nil)
        #expect(fixture.service.jobs.isEmpty)
        #expect(fixture.service.queue.running == nil)
    }

    @Test func theNextJobStartsOnceTheCancelledOneHasEnded() throws {
        let fixture = Fixture()
        let ids = fixture.submit(2)
        let first = try #require(fixture.runner.last)
        fixture.service.cancel(ids[0])
        #expect(fixture.runner.runs.count == 1, "not before the process has ended")
        first.end(status: 130, wasSignalled: true)
        #expect(fixture.runner.runs.count == 2)
        #expect(fixture.service.queue.running?.id == ids[1])
    }

    @Test func aProcessThatEndsOnTheSignalItselfIsHandledToo() throws {
        let fixture = Fixture()
        let ids = fixture.submit(2)
        let first = try #require(fixture.runner.last)
        first.endsWhenCancelled = true
        first.say(Fixture.progressLine(done: 1, of: 2, file: "A.webm"))
        fixture.files.entries = ["A.webm.part": Fixture.start.addingTimeInterval(2)]

        fixture.service.cancel(ids[0])

        #expect(first.cancelCount == 1)
        #expect(fixture.files.removed.map(\.lastPathComponent) == ["A.webm.part"])
        #expect(fixture.service.queue.job(ids[0]) == nil)
        #expect(fixture.service.queue.running?.id == ids[1])
        #expect(fixture.runner.runs.count == 2)
    }

    @Test func aProcessThatEndsWellAfterTheCancelIsStillCancelled() throws {
        let fixture = Fixture()
        let (id, run) = try downloading(fixture)
        run.say(Fixture.fileLine("/Users/tester/Music/Hangover/Song [a1b2].mp3"))
        fixture.service.cancel(id)
        run.end(status: 0)
        #expect(fixture.service.queue.job(id) == nil)
        #expect(fixture.service.queue.finished.isEmpty)
    }

    @Test func wordFromTheProcessAfterTheCancelChangesNothing() throws {
        let fixture = Fixture()
        let (id, run) = try downloading(fixture)
        fixture.service.cancel(id)
        run.say(Fixture.progressLine(done: 90, of: 100))
        run.say(Fixture.titleLine("Changed"))
        #expect(fixture.service.queue.job(id)?.phase == .cancelling)
        #expect(fixture.service.queue.job(id)?.title == "Song")
    }

    @Test func aCancelBeforeAnyFileWasNamedRemovesNothing() throws {
        let fixture = Fixture()
        let id = try #require(fixture.submit(1).first)
        let run = try #require(fixture.runner.last)
        fixture.files.entries = ["Other.mp3": after(30), "Other.webm.part": after(30)]
        fixture.service.cancel(id)
        run.end(status: 130, wasSignalled: true)
        #expect(fixture.files.removed.isEmpty)
        #expect(fixture.files.entries.count == 2)
    }

    @Test func aCancelWhileTheMP3IsBeingMadeRemovesTheHalfMadeFileToo() throws {
        let fixture = Fixture()
        let (id, run) = try downloading(fixture)
        run.say(Fixture.downloadDoneLine(file: "Song [a1b2].webm"))
        fixture.files.entries = ["Song [a1b2].webm": after(10), "Song [a1b2].mp3": after(12), "Song [a1b2].temp.mp3": after(12)]
        fixture.service.cancel(id)
        run.end(status: 130, wasSignalled: true)
        #expect(fixture.files.removed.map(\.lastPathComponent).sorted() == ["Song [a1b2].mp3", "Song [a1b2].temp.mp3", "Song [a1b2].webm"])
    }

    @Test func aFileTheUserAlreadyHadUnderTheSameNameStays() throws {
        let fixture = Fixture()
        let (id, run) = try downloading(fixture)
        fixture.files.entries = [
            "Song [a1b2].mp3": after(-86_400),
            "Song [a1b2].webm": after(-86_400),
            "Song [a1b2].webm.part": after(3),
            "Notes.txt": after(3),
            "Song 2.mp3": after(3),
        ]
        fixture.service.cancel(id)
        run.end(status: 130, wasSignalled: true)
        #expect(fixture.files.removed.map(\.lastPathComponent) == ["Song [a1b2].webm.part"])
        #expect(Set(fixture.files.entries.keys) == ["Song [a1b2].mp3", "Song [a1b2].webm", "Notes.txt", "Song 2.mp3"])
    }

    @Test func cancellingAJobThatIsNotThereOrIsFinishedDoesNothing() throws {
        let fixture = Fixture()
        let id = try #require(fixture.submit(1).first)
        fixture.finishRunningJob()
        let before = fixture.service.queue
        fixture.service.cancel(id)
        fixture.service.cancel(UUID())
        #expect(fixture.service.queue == before)
        #expect(fixture.files.removed.isEmpty)
    }

    // MARK: Switching the widget off

    @Test func switchingTheWidgetOffStopsTheRunningJobAndEmptiesTheRest() throws {
        let fixture = Fixture()
        fixture.submit(3)
        fixture.finishRunningJob()
        let running = try #require(fixture.runner.last)
        running.say(Fixture.progressLine(done: 1, of: 2, file: "B.webm"))
        fixture.files.entries = ["B.webm.part": Fixture.start.addingTimeInterval(1)]
        #expect(fixture.service.queue.finished.count == 1)

        fixture.service.widgetSwitched(false)

        #expect(running.cancelCount == 1)
        #expect(fixture.service.queue.waiting.isEmpty)
        #expect(fixture.service.queue.finished.isEmpty)
        running.end(status: 130, wasSignalled: true)
        #expect(fixture.service.jobs.isEmpty)
        #expect(fixture.runner.runs.count == 2, "nothing starts after it is off")
        #expect(fixture.files.removed.map(\.lastPathComponent) == ["B.webm.part"])
    }

    @Test func switchingTheWidgetOnChangesNothing() {
        let fixture = Fixture()
        fixture.submit(2)
        let before = fixture.service.queue
        fixture.service.widgetSwitched(true)
        #expect(fixture.service.queue == before)
    }

    // MARK: What a cancel may remove

    @Test func theLeftoversAreThePartsOfTheFileBeingWrittenAndNothingElse() {
        let start = Fixture.start
        let new = start.addingTimeInterval(5)
        let entries = [
            "My Song [a1b2].webm", "My Song [a1b2].webm.part", "My Song [a1b2].webm.ytdl", "My Song [a1b2].webm.part-Frag4",
            "My Song [a1b2].mp3", "My Song [a1b2].temp.mp3",
            "My Song (2).mp3", "My Songs.webm", "My Song", "Other.mp3",
        ].map { NookLinkAudioFileEntry(name: $0, modified: new) }

        let names = NookLinkAudioLeftovers.names(in: entries, writing: "/x/My Song [a1b2].webm", since: start)
        #expect(Set(names) == [
            "My Song [a1b2].webm", "My Song [a1b2].webm.part", "My Song [a1b2].webm.ytdl", "My Song [a1b2].webm.part-Frag4",
            "My Song [a1b2].mp3", "My Song [a1b2].temp.mp3",
        ])
    }

    @Test func theLeftoversNeedAFileNameThatIsOnlyAName() {
        let new = Fixture.start.addingTimeInterval(5)
        let entries = [".", "..", "a.mp3", "x", "a"].map { NookLinkAudioFileEntry(name: $0, modified: new) }
        #expect(NookLinkAudioLeftovers.names(in: entries, writing: nil, since: Fixture.start).isEmpty)
        #expect(NookLinkAudioLeftovers.names(in: entries, writing: "", since: Fixture.start).isEmpty)
        #expect(NookLinkAudioLeftovers.names(in: entries, writing: ".", since: Fixture.start).isEmpty)
        #expect(NookLinkAudioLeftovers.names(in: entries, writing: "..", since: Fixture.start).isEmpty)
    }

    @Test func aFileChangedBeforeTheJobStartedNeverGoes() {
        let start = Fixture.start
        let entries = [
            NookLinkAudioFileEntry(name: "a.webm", modified: start.addingTimeInterval(-1)),
            NookLinkAudioFileEntry(name: "a.webm.part", modified: start),
            NookLinkAudioFileEntry(name: "a.mp3", modified: start.addingTimeInterval(-3_600)),
        ]
        #expect(NookLinkAudioLeftovers.names(in: entries, writing: "a.webm", since: start) == ["a.webm.part"])
    }
}
