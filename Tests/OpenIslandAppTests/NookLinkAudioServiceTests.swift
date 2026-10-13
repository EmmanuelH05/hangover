import Foundation
import Testing
@testable import OpenIslandApp

// The service on a fake runner: starting, the line, progress, ending well
// and badly, and the programs and folder it needs. No process is started
// and nothing is written.

@MainActor
@Suite struct NookLinkAudioServiceTests {
    private typealias Fixture = LinkAudioFixture

    private func phase(_ fixture: Fixture, _ id: UUID) -> NookLinkAudioJob.Phase? {
        fixture.service.queue.job(id)?.phase
    }

    // MARK: Starting

    @Test func aLinkStartsAtOnceWithYtDlpFromTheFolderItWasFoundIn() throws {
        let fixture = Fixture()
        let result = fixture.service.submit(Fixture.link(1))

        guard case let .queued(id) = result else { Issue.record("not queued: \(result)"); return }
        let run = try #require(fixture.runner.last)
        #expect(fixture.runner.runs.count == 1)
        #expect(run.launch.executable.path == "/opt/homebrew/bin/yt-dlp")
        #expect(Array(run.launch.arguments.suffix(2)) == ["--", Fixture.link(1)])
        #expect(fixture.service.queue.running?.id == id)
        #expect(fixture.service.queue.running?.startedAt == Fixture.start)
        #expect(fixture.service.problem == nil)
    }

    @Test func theProgramGetsTheArgumentsOfTheRuleAndTheFolderItWasGiven() throws {
        let fixture = Fixture()
        fixture.service.submit(Fixture.link(1))
        let run = try #require(fixture.runner.last)
        let expected = NookLinkAudioArguments.make(
            link: try NookLinkAudioLink.check(Fixture.link(1)).get(),
            folder: URL(fileURLWithPath: "/Users/tester/Music/Hangover", isDirectory: true),
            ffmpegDirectory: URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true)
        )
        #expect(run.launch.arguments == expected)
        let at = try #require(run.launch.arguments.firstIndex(of: "-o"))
        #expect(run.launch.arguments[at + 1] == "/Users/tester/Music/Hangover/%(title)s [%(id)s].%(ext)s")
    }

    @Test func theEnvironmentHoldsTheSearchedFoldersAndKeepsTheRest() throws {
        let fixture = Fixture(environment: ["HOME": "/Users/tester", "PATH": "/usr/bin", "LANG": "en_US.UTF-8"])
        fixture.service.submit(Fixture.link(1))
        let environment = try #require(fixture.runner.last).launch.environment
        #expect(environment["HOME"] == "/Users/tester")
        #expect(environment["LANG"] == "en_US.UTF-8")
        #expect(environment["PATH"]?.hasPrefix("/opt/homebrew/bin:/usr/local/bin:/usr/bin") == true)
        #expect(environment["PYTHONUNBUFFERED"] == "1")
        #expect(environment["PYTHONIOENCODING"] == "utf-8")
    }

    @Test func theFolderIsMadeOnFirstUseAndNotBefore() {
        let fixture = Fixture()
        #expect(fixture.files.madeFolders.isEmpty)
        fixture.service.submit("-o /tmp/x")
        fixture.service.submit("nonsense")
        #expect(fixture.files.madeFolders.isEmpty, "a refused link makes nothing")
        fixture.service.submit(Fixture.link(1))
        #expect(fixture.files.madeFolders.map(\.path) == ["/Users/tester/Music/Hangover"])
    }

    @Test func aFolderThatCannotBeMadeFailsTheJobAndStartsNothing() throws {
        let fixture = Fixture()
        fixture.files.failsToMakeFolder = true
        guard case let .queued(id) = fixture.service.submit(Fixture.link(1)) else { Issue.record("not queued"); return }
        #expect(fixture.runner.runs.isEmpty)
        #expect(phase(fixture, id) == .failed(.couldNotMakeFolder))
        #expect(fixture.service.queue.running == nil)
    }

    @Test func aProgramThatCannotBeStartedFailsTheJob() {
        let fixture = Fixture()
        fixture.runner.failsToStart = true
        guard case let .queued(id) = fixture.service.submit(Fixture.link(1)) else { Issue.record("not queued"); return }
        #expect(phase(fixture, id) == .failed(.couldNotStart))
        #expect(fixture.service.queue.running == nil)
        // The line is free again.
        fixture.runner.failsToStart = false
        fixture.service.submit(Fixture.link(2))
        #expect(fixture.runner.runs.count == 1)
    }

    // MARK: A link that is refused

    @Test(arguments: [
        "-o /tmp/evil", "--exec=touch /tmp/x", "--", "-", "   ", "", "example.com", "file:///etc/passwd",
        "https://user:pass@example.com/a", "https://example.com/a b",
    ])
    func aRefusedLinkNeverReachesTheRunner(_ text: String) {
        let fixture = Fixture()
        let result = fixture.service.submit(text)
        guard case let .refused(reason) = result else { Issue.record("not refused: \(result)"); return }
        #expect(fixture.runner.runs.isEmpty)
        #expect(fixture.service.jobs.isEmpty)
        #expect(fixture.service.problem == .refused(reason))
    }

    @Test func theLineUnderTheFieldGoesWhenTheNextLinkIsTaken() {
        let fixture = Fixture()
        fixture.service.submit("nonsense")
        #expect(fixture.service.problem != nil)
        fixture.service.submit(Fixture.link(1))
        #expect(fixture.service.problem == nil)
    }

    @Test func everyProblemHasALineInEveryLanguage() {
        let problems: [NookLinkAudioProblem] = [
            .refused(.empty), .refused(.tooLong), .refused(.notAWebLink), .refused(.hasBlankOrControl),
            .refused(.hasCredentials), .lineFull, .toolsMissing, .pasteNotAllowed, .pasteNothing, .pasteMaybeRefused,
        ]
        #expect(Set(problems.map(\.messageKey)).count == problems.count)
        for problem in problems {
            #expect(LanguageManager.shared.t(problem.messageKey) != problem.messageKey)
        }
    }

    // MARK: The line

    @Test func oneRunsAtATimeAndTheOthersWaitInOrder() throws {
        let fixture = Fixture()
        let ids = fixture.submit(4)
        #expect(ids.count == 4)
        #expect(fixture.runner.runs.count == 1)
        #expect(phase(fixture, ids[0]) == .downloading(fraction: nil))
        #expect(ids[1...].allSatisfy { phase(fixture, $0) == .waiting })
        #expect(fixture.service.jobs.map(\.id) == ids)

        fixture.finishRunningJob(title: "One")
        #expect(fixture.runner.runs.count == 2)
        #expect(fixture.runner.last?.link == Fixture.link(2))
        fixture.finishRunningJob(title: "Two")
        #expect(fixture.runner.last?.link == Fixture.link(3))
        fixture.finishRunningJob(title: "Three")
        #expect(fixture.runner.last?.link == Fixture.link(4))
        #expect(fixture.runner.runs.count == 4)
        #expect(fixture.service.queue.waiting.isEmpty)
    }

    @Test func aSecondProcessNeverStartsWhileOneIsRunning() {
        let fixture = Fixture()
        fixture.submit(6)
        #expect(fixture.runner.runs.count == 1)
        fixture.runner.last?.say(Fixture.titleLine("A"))
        #expect(fixture.runner.runs.count == 1)
    }

    @Test func fiveWaitIsTheMostAndASixthIsTurnedAway() {
        let fixture = Fixture()
        let ids = fixture.submit(6)
        #expect(ids.count == 6, "one running and five waiting")
        let result = fixture.service.submit(Fixture.link(7))
        #expect(result == .lineFull)
        #expect(fixture.service.problem == .lineFull)
        #expect(fixture.service.jobs.count == 6)
        #expect(fixture.runner.runs.count == 1)
    }

    @Test func aFinishedJobMakesRoomInTheLine() {
        let fixture = Fixture()
        fixture.submit(6)
        #expect(fixture.service.submit(Fixture.link(7)) == .lineFull)
        fixture.finishRunningJob()
        guard case .queued = fixture.service.submit(Fixture.link(7)) else { Issue.record("not queued"); return }
        #expect(fixture.service.queue.waiting.count == 5)
        #expect(fixture.service.queue.waiting.last?.link.text == Fixture.link(7))
        #expect(fixture.service.problem == nil)
    }

    @Test func theLastFiveFinishedStayListedNewestFirst() {
        let fixture = Fixture()
        for number in 1...8 {
            fixture.submit(1, from: number)
            fixture.finishRunningJob(title: "Song \(number)")
        }
        let finished = fixture.service.queue.finished
        #expect(finished.count == 5)
        #expect(finished.compactMap(\.title) == ["Song 8", "Song 7", "Song 6", "Song 5", "Song 4"])
        #expect(fixture.service.jobs.count == 5)
    }

    // MARK: Progress

    @Test func theTitleAndTheProgressShowOnTheRow() throws {
        let fixture = Fixture()
        let id = try #require(fixture.submit(1).first)
        let run = try #require(fixture.runner.last)

        run.say(Fixture.titleLine("Never Gonna Give You Up"))
        #expect(fixture.service.queue.job(id)?.title == "Never Gonna Give You Up")

        run.say(Fixture.progressLine(done: 25, of: 100))
        #expect(phase(fixture, id) == .downloading(fraction: 0.25))
        run.say(Fixture.progressLine(done: 80, of: 100))
        #expect(phase(fixture, id) == .downloading(fraction: 0.8))
        #expect(fixture.service.queue.job(id)?.writingFileName == "\(Fixture.mediaFolder)/Song [a1b2].webm")
    }

    @Test func theDownloadEndingMovesTheRowToMakingTheMP3() throws {
        let fixture = Fixture()
        let id = try #require(fixture.submit(1).first)
        let run = try #require(fixture.runner.last)
        run.say(Fixture.progressLine(done: 100, of: 100))
        run.say(Fixture.downloadDoneLine())
        #expect(phase(fixture, id) == .converting)
        // A late progress line does not take it back.
        run.say(Fixture.progressLine(done: 100, of: 100))
        #expect(phase(fixture, id) == .converting)
    }

    @Test func aMoveTooSmallToSeeIsLeftOut() throws {
        let fixture = Fixture()
        let id = try #require(fixture.submit(1).first)
        let run = try #require(fixture.runner.last)
        run.say(Fixture.progressLine(done: 1_000, of: 100_000))
        #expect(phase(fixture, id) == .downloading(fraction: 0.01))
        run.say(Fixture.progressLine(done: 1_200, of: 100_000))
        #expect(phase(fixture, id) == .downloading(fraction: 0.01))
        run.say(Fixture.progressLine(done: 2_000, of: 100_000))
        #expect(phase(fixture, id) == .downloading(fraction: 0.02))
    }

    @Test func aBarDoesNotGoBackToUnknown() throws {
        let fixture = Fixture()
        let id = try #require(fixture.submit(1).first)
        let run = try #require(fixture.runner.last)
        run.say(Fixture.progressLine(done: 50, of: 100))
        run.say(Fixture.progressLine(done: 60, of: nil))
        #expect(phase(fixture, id) == .downloading(fraction: 0.5))
    }

    @Test func aLongTitleIsCutForTheRow() throws {
        let fixture = Fixture()
        let id = try #require(fixture.submit(1).first)
        fixture.runner.last?.say(Fixture.titleLine(String(repeating: "x", count: 1_000)))
        #expect(fixture.service.queue.job(id)?.title?.count == NookLinkAudioService.maxTitleLength)
    }

    @Test func linesThatAreNotOursChangeNothing() throws {
        let fixture = Fixture()
        let id = try #require(fixture.submit(1).first)
        let before = fixture.service.queue
        let run = try #require(fixture.runner.last)
        for line in ["[download] 50% of 3MiB", "WARNING: x", "", "hangover-progress downloading", "random"] {
            run.say(line)
        }
        #expect(fixture.service.queue == before)
        #expect(phase(fixture, id) == .downloading(fraction: nil))
    }

    // MARK: Ending

    @Test func aCleanEndWithTheFileLineIsDoneWithThatFile() throws {
        let fixture = Fixture()
        let id = try #require(fixture.submit(1).first)
        fixture.finishRunningJob(title: "Song", file: "/Users/tester/Music/Hangover/Song [a1b2].mp3")
        #expect(phase(fixture, id) == .done(URL(fileURLWithPath: "/Users/tester/Music/Hangover/Song [a1b2].mp3")))
        #expect(fixture.service.queue.running == nil)
    }

    @Test func aCleanEndWithNoFileLineIsDoneWithoutAPath() throws {
        let fixture = Fixture()
        let id = try #require(fixture.submit(1).first)
        fixture.runner.last?.end()
        #expect(phase(fixture, id) == .done(nil))
    }

    @Test func showInFinderShowsTheFileOrElseTheFolder() throws {
        let fixture = Fixture()
        let first = try #require(fixture.submit(1).first)
        fixture.finishRunningJob(title: "Song", file: "/Users/tester/Music/Hangover/Song [a1b2].mp3")
        let second = try #require(fixture.submit(1, from: 2).first)
        fixture.runner.last?.end()

        fixture.service.showInFinder(first)
        fixture.service.showInFinder(second)
        #expect(fixture.shown.map(\.path) == ["/Users/tester/Music/Hangover/Song [a1b2].mp3", "/Users/tester/Music/Hangover"])
        #expect(fixture.shown.last?.hasDirectoryPath == true)
    }

    @Test func showInFinderDoesNothingForAJobThatIsNotDone() throws {
        let fixture = Fixture()
        let ids = fixture.submit(2)
        fixture.service.showInFinder(ids[0])
        fixture.service.showInFinder(ids[1])
        fixture.service.showInFinder(UUID())
        #expect(fixture.shown.isEmpty)
    }

    @Test func aFailedEndSaysWhyInTheJobsOwnWords() throws {
        let fixture = Fixture()
        let id = try #require(fixture.submit(1).first)
        let run = try #require(fixture.runner.last)
        run.say("ERROR: [youtube] abc: Video unavailable")
        run.end(status: 1)
        #expect(phase(fixture, id) == .failed(.unavailable))
    }

    @Test func theLastErrorLineIsTheOneUsed() throws {
        let fixture = Fixture()
        let id = try #require(fixture.submit(1).first)
        let run = try #require(fixture.runner.last)
        run.say("ERROR: Unsupported URL: https://example.com/x")
        run.say("ERROR: [generic] HTTP Error 404: Not Found")
        run.end(status: 1)
        #expect(phase(fixture, id) == .failed(.unavailable))
    }

    @Test func aFailureWithNoErrorLineSaysItDidNotSayWhy() throws {
        let fixture = Fixture()
        let first = try #require(fixture.submit(1).first)
        fixture.runner.last?.end(status: 2)
        #expect(phase(fixture, first) == .failed(.other))

        let second = try #require(fixture.submit(1, from: 2).first)
        fixture.runner.last?.end(status: 9, wasSignalled: true)
        #expect(phase(fixture, second) == .failed(.other))
    }

    @Test func aFailedJobLetsTheNextOneStart() {
        let fixture = Fixture()
        fixture.submit(2)
        fixture.runner.last?.say("ERROR: Unsupported URL")
        fixture.runner.last?.end(status: 1)
        #expect(fixture.runner.runs.count == 2)
        #expect(fixture.service.queue.running?.link.text == Fixture.link(2))
        #expect(fixture.service.queue.finished.first?.phase == .failed(.unsupportedSite))
    }

    @Test func aProgramThatEndsBeforeRunReturnsStillEndsTheJobOnce() throws {
        let fixture = Fixture()
        fixture.runner.endsAtOnce = NookLinkAudioExit(status: 0, wasSignalled: false)
        let id = try #require(fixture.submit(1).first)
        #expect(phase(fixture, id) == .done(nil))
        #expect(fixture.service.queue.running == nil)
        #expect(fixture.service.queue.finished.count == 1)
    }

    @Test func linesFromAJobThatIsNotRunningAreIgnored() throws {
        let fixture = Fixture()
        let ids = fixture.submit(2)
        let first = try #require(fixture.runner.last)
        first.end()
        let after = fixture.service.queue
        first.say(Fixture.titleLine("Late"))
        first.say("ERROR: late")
        first.end(status: 1)
        #expect(fixture.service.queue == after)
        #expect(phase(fixture, ids[0]) == .done(nil))
    }

    // MARK: The programs

    @Test func withAProgramMissingNothingStartsAndTheLineSaysWhich() {
        let fixture = Fixture()
        fixture.executables = [Fixture.ffmpeg]
        fixture.service.refreshTools()
        #expect(!fixture.service.canSubmit)
        #expect(fixture.service.toolStatus.missingLineKey == "nook.linkAudio.missing.ytDlp")

        #expect(fixture.service.submit(Fixture.link(1)) == .toolsMissing)
        #expect(fixture.service.problem == .toolsMissing)
        #expect(fixture.runner.runs.isEmpty)
        #expect(fixture.service.jobs.isEmpty)
        #expect(fixture.files.madeFolders.isEmpty)
    }

    @Test func theProgramsInstalledWhileTheAppRunsArePickedUp() {
        let fixture = Fixture()
        fixture.executables = []
        fixture.service.refreshTools()
        #expect(!fixture.service.canSubmit)
        #expect(fixture.service.toolStatus.missingLineKey == "nook.linkAudio.missing.both")

        fixture.executables = [Fixture.ytDlp, Fixture.ffmpeg]
        guard case .queued = fixture.service.submit(Fixture.link(1)) else { Issue.record("not queued"); return }
        #expect(fixture.service.canSubmit)
        #expect(fixture.runner.runs.count == 1)
    }

    @Test func aProgramThatVanishesWhileAJobWaitsFailsThatJob() throws {
        let fixture = Fixture()
        let ids = fixture.submit(2)
        fixture.executables = []
        fixture.runner.last?.end()
        #expect(phase(fixture, ids[1]) == .failed(.couldNotStart))
        #expect(fixture.runner.runs.count == 1)
        #expect(fixture.service.queue.running == nil)
    }

    @Test func ffmpegsOwnFolderIsWhatYtDlpIsToldAbout() throws {
        let fixture = Fixture()
        fixture.executables = ["/usr/local/bin/yt-dlp", "/usr/bin/ffmpeg"]
        fixture.service.submit(Fixture.link(1))
        let run = try #require(fixture.runner.last)
        #expect(run.launch.executable.path == "/usr/local/bin/yt-dlp")
        let at = try #require(run.launch.arguments.firstIndex(of: "--ffmpeg-location"))
        #expect(run.launch.arguments[at + 1] == "/usr/bin")
    }
}
