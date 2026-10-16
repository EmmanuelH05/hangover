import Foundation
import Testing
@testable import OpenIslandApp

// The service handing a saved download to the analyzer: what it passes on,
// when the row learns the answer, how the file is renamed, what happens when
// the new name is taken, and the setting that turns it all off. The analyzer
// and the folder are fakes. Nothing is decoded and nothing is written.

@MainActor
@Suite struct NookLinkAudioKeyServiceTests {
    private typealias Fixture = LinkAudioFixture

    private let song = "/Users/tester/Music/Hangover/Song [a1b2].mp3"
    private let cSharpMinor = NookMusicalKey(tonic: 1, mode: .minor)

    private func both(guess: Bool = false) -> NookLinkAudioFindings {
        NookLinkAudioFindings(
            key: NookLinkAudioFound(value: cSharpMinor, isGuess: guess),
            bpm: NookLinkAudioFound(value: 127, isGuess: guess)
        )
    }

    /// A fixture with the file the job will save "on the disk".
    private func fixture(present: [String] = ["/Users/tester/Music/Hangover/Song [a1b2].mp3"]) -> Fixture {
        let fixture = Fixture()
        fixture.files.present = Set(present)
        return fixture
    }

    private func job(_ fixture: Fixture, _ id: UUID) -> NookLinkAudioJob? {
        fixture.service.queue.job(id)
    }

    // MARK: What the analyzer is given

    @Test func theTitleAndTheDescriptionGoToTheAnalyzerWithTheFile() async throws {
        let fixture = fixture()
        let run = try { () throws -> FakeLinkAudioRunner.Run in
            fixture.submit(1)
            return try #require(fixture.runner.last)
        }()
        run.say(Fixture.titleLine("Song"))
        run.say(Fixture.descriptionLine("Key: C# minor\nBPM: 127"))
        run.say(Fixture.fileLine(song))
        run.end()
        await fixture.service.finishAnalyses()

        let call = try #require(fixture.analyzer.calls.first)
        #expect(fixture.analyzer.calls.count == 1)
        #expect(call.file.path == song)
        #expect(call.title == "Song")
        #expect(call.description == "Key: C# minor\nBPM: 127")
    }

    @Test func theWholeTitleGoesNotTheOneCutForTheRow() async throws {
        let fixture = fixture()
        fixture.submit(1)
        let longTitle = String(repeating: "x", count: 300) + " Key: Em"
        fixture.runner.last?.say(Fixture.titleLine(longTitle))
        fixture.runner.last?.say(Fixture.fileLine(song))
        fixture.runner.last?.end()
        await fixture.service.finishAnalyses()
        #expect(fixture.analyzer.calls.first?.title == longTitle)
        #expect(fixture.service.jobs.first?.title?.count == NookLinkAudioService.maxTitleLength)
    }

    @Test func aVideoWithNoDescriptionStillGoesToTheAnalyzer() async throws {
        let fixture = fixture()
        fixture.submit(1)
        let run = try #require(fixture.runner.last)
        run.say(Fixture.titleLine("Song"))
        run.say("\(NookLinkAudioArguments.descriptionMarker) NA")
        run.say(Fixture.fileLine(song))
        run.end()
        await fixture.service.finishAnalyses()
        #expect(fixture.analyzer.calls.count == 1)
        #expect(fixture.analyzer.calls.first?.description == nil)
    }

    @Test func aDownloadThatFailedOrWasCancelledIsNotAnalyzed() async throws {
        let fixture = fixture()
        let ids = fixture.submit(2)
        fixture.runner.last?.say(Fixture.fileLine(song))
        fixture.runner.last?.say("ERROR: Video unavailable")
        fixture.runner.last?.end(status: 1)

        let second = try #require(fixture.runner.last)
        second.endsWhenCancelled = true
        fixture.service.cancel(ids[1])
        await fixture.service.finishAnalyses()
        #expect(fixture.analyzer.calls.isEmpty)
    }

    @Test func aFinishWithNoFileNamedIsNotAnalyzed() async throws {
        let fixture = fixture()
        fixture.submit(1)
        fixture.runner.last?.end()
        await fixture.service.finishAnalyses()
        #expect(fixture.analyzer.calls.isEmpty)
    }

    @Test func aFileLineOutsideTheFolderIsNotAnalyzed() async throws {
        let fixture = fixture()
        fixture.submit(1)
        fixture.runner.last?.say(Fixture.fileLine("/System/Applications/Calculator.app/Contents/MacOS/Calculator"))
        fixture.runner.last?.end()
        await fixture.service.finishAnalyses()
        #expect(fixture.analyzer.calls.isEmpty)
    }

    // MARK: The row learns it later

    @Test func theRowIsDoneAtOnceAndTheAnswerComesLater() async throws {
        let fixture = fixture()
        fixture.analyzer.answer(with: both(guess: true), holding: true)
        let id = try #require(fixture.submit(1).first)
        fixture.finishRunningJob(title: "Song")

        // Done, with the file as it was saved, and nothing found yet.
        #expect(job(fixture, id)?.phase == .done(URL(fileURLWithPath: song)))
        #expect(job(fixture, id)?.findings == nil)
        #expect(fixture.files.moves.isEmpty)

        // The line is free: the next job may start while the answer is out.
        fixture.submit(1, from: 2)
        #expect(fixture.runner.runs.count == 2)

        #expect(await fixture.waitForHeldAnalysis(), "the search is out")
        fixture.analyzer.release()
        await fixture.service.finishAnalyses()

        let renamed = URL(fileURLWithPath: "/Users/tester/Music/Hangover/Song [~C# minor, ~127 BPM] [a1b2].mp3")
        #expect(job(fixture, id)?.findings == both(guess: true))
        #expect(job(fixture, id)?.phase == .done(renamed))
        #expect(fixture.files.moves.map(\.to) == [renamed])
        #expect(fixture.files.present.contains(renamed.path) && !fixture.files.present.contains(song))
    }

    @Test func showInFinderPointsAtTheRenamedFile() async throws {
        let fixture = fixture()
        fixture.analyzer.answer(with: both())
        let id = try #require(fixture.submit(1).first)
        fixture.finishRunningJob(title: "Song")
        await fixture.service.finishAnalyses()
        fixture.service.showInFinder(id)
        #expect(fixture.shown.map(\.path) == ["/Users/tester/Music/Hangover/Song [C# minor, 127 BPM] [a1b2].mp3"])
    }

    @Test func aWrittenKeyAndTempoGoInTheNameWithNoTilde() async throws {
        let fixture = fixture()
        fixture.analyzer.answer(with: both(guess: false))
        fixture.submit(1)
        fixture.finishRunningJob(title: "Song")
        await fixture.service.finishAnalyses()
        #expect(fixture.files.moves.map(\.to.lastPathComponent) == ["Song [C# minor, 127 BPM] [a1b2].mp3"])
    }

    @Test func onlyAKeyOrOnlyATempoNamesOnlyThat() async throws {
        let keyOnly = fixture()
        keyOnly.analyzer.answer(with: NookLinkAudioFindings(key: NookLinkAudioFound(value: cSharpMinor, isGuess: true), bpm: nil))
        keyOnly.submit(1)
        keyOnly.finishRunningJob(title: "Song")
        await keyOnly.service.finishAnalyses()
        #expect(keyOnly.files.moves.map(\.to.lastPathComponent) == ["Song [~C# minor] [a1b2].mp3"])

        let tempoOnly = fixture()
        tempoOnly.analyzer.answer(with: NookLinkAudioFindings(key: nil, bpm: NookLinkAudioFound(value: 90, isGuess: false)))
        tempoOnly.submit(1)
        tempoOnly.finishRunningJob(title: "Song")
        await tempoOnly.service.finishAnalyses()
        #expect(tempoOnly.files.moves.map(\.to.lastPathComponent) == ["Song [90 BPM] [a1b2].mp3"])
    }

    @Test func nothingFoundMeansNoRenameAndNothingOnTheRow() async throws {
        let fixture = fixture()
        let id = try #require(fixture.submit(1).first)
        fixture.finishRunningJob(title: "Song")
        await fixture.service.finishAnalyses()
        #expect(fixture.files.moves.isEmpty && fixture.files.trashed.isEmpty)
        #expect(job(fixture, id)?.findings == nil)
        #expect(job(fixture, id)?.phase == .done(URL(fileURLWithPath: song)))
    }

    // MARK: A name that is taken

    @Test func theSameLinkFetchedAgainSendsTheFreshCopyToTheTrash() async throws {
        let taken = "/Users/tester/Music/Hangover/Song [C# minor, 127 BPM] [a1b2].mp3"
        let fixture = fixture(present: [song, taken])
        fixture.analyzer.answer(with: both())
        let id = try #require(fixture.submit(1).first)
        fixture.finishRunningJob(title: "Song")
        await fixture.service.finishAnalyses()

        #expect(fixture.files.trashed.map(\.path) == [song])
        #expect(fixture.files.moves.isEmpty, "nothing is replaced")
        #expect(fixture.files.present == [taken], "the one that was there is untouched")
        #expect(job(fixture, id)?.phase == .done(URL(fileURLWithPath: taken)))
        #expect(job(fixture, id)?.findings == both())
        #expect(fixture.files.removed.isEmpty, "the Trash and not a delete")
    }

    @Test func aCopyThatCannotGoToTheTrashStaysWhereItIs() async throws {
        let taken = "/Users/tester/Music/Hangover/Song [C# minor, 127 BPM] [a1b2].mp3"
        let fixture = fixture(present: [song, taken])
        fixture.files.failsToTrash = true
        fixture.analyzer.answer(with: both())
        let id = try #require(fixture.submit(1).first)
        fixture.finishRunningJob(title: "Song")
        await fixture.service.finishAnalyses()

        #expect(fixture.files.present == [song, taken])
        #expect(job(fixture, id)?.phase == .done(URL(fileURLWithPath: song)), "the row keeps pointing at the copy that is there")
        #expect(job(fixture, id)?.findings == both(), "and still says what was found")
    }

    @Test func aFileThatCannotBeMovedStaysAndTheRowStillShowsTheFindings() async throws {
        let fixture = fixture()
        fixture.files.failsToMove = true
        fixture.analyzer.answer(with: both(guess: true))
        let id = try #require(fixture.submit(1).first)
        fixture.finishRunningJob(title: "Song")
        await fixture.service.finishAnalyses()

        #expect(fixture.files.present == [song])
        #expect(job(fixture, id)?.phase == .done(URL(fileURLWithPath: song)))
        #expect(job(fixture, id)?.findings == both(guess: true))
    }

    @Test func aFileThatIsGoneIsNotMovedOrTrashed() async throws {
        let fixture = fixture(present: [])
        fixture.analyzer.answer(with: both())
        let id = try #require(fixture.submit(1).first)
        fixture.finishRunningJob(title: "Song")
        await fixture.service.finishAnalyses()
        #expect(fixture.files.moves.isEmpty && fixture.files.trashed.isEmpty)
        #expect(job(fixture, id)?.findings == both())
    }

    @Test func aFileAnotherJobRenamedFirstIsFollowedToItsNewPlace() async throws {
        // Two jobs for the same link: the second finds the first one's file.
        let taken = "/Users/tester/Music/Hangover/Song [C# minor, 127 BPM] [a1b2].mp3"
        let fixture = fixture(present: [taken])
        fixture.analyzer.answer(with: both())
        let id = try #require(fixture.submit(1).first)
        fixture.finishRunningJob(title: "Song")
        await fixture.service.finishAnalyses()
        #expect(job(fixture, id)?.phase == .done(URL(fileURLWithPath: taken)))
        #expect(fixture.files.moves.isEmpty && fixture.files.trashed.isEmpty)
    }

    // MARK: A file the job did not write

    // `--no-overwrites` skips the download when the plain MP3 is already in
    // the folder, and `yt-dlp` still names that file when it ends. It prints no
    // progress line then, which is how the app knows the job wrote nothing.

    private let tagged = "/Users/tester/Music/Hangover/Song [C# minor, 127 BPM] [a1b2].mp3"

    /// A run that ends with the file named and no progress line.
    private func skippedRun(_ fixture: Fixture) {
        let run = fixture.runner.last
        run?.say(Fixture.titleLine("Song"))
        run?.say(Fixture.fileLine(song))
        run?.end()
    }

    @Test func aSkippedDownloadWithBothNamesThereTrashesNothingAndMovesNothing() async throws {
        let fixture = fixture(present: [song, tagged])
        fixture.analyzer.answer(with: both())
        let id = try #require(fixture.submit(1).first)
        skippedRun(fixture)
        await fixture.service.finishAnalyses()

        #expect(fixture.files.trashed.isEmpty && fixture.files.moves.isEmpty && fixture.files.removed.isEmpty)
        #expect(fixture.files.present == [song, tagged], "the file the user kept is untouched")
        #expect(job(fixture, id)?.phase == .done(URL(fileURLWithPath: tagged)), "the row points at the tagged file")
        #expect(job(fixture, id)?.findings == both())
    }

    @Test func aSkippedDownloadWithOnlyThePlainNameRenamesNothing() async throws {
        let fixture = fixture(present: [song])
        fixture.analyzer.answer(with: both(guess: true))
        let id = try #require(fixture.submit(1).first)
        skippedRun(fixture)
        await fixture.service.finishAnalyses()

        #expect(fixture.files.trashed.isEmpty && fixture.files.moves.isEmpty && fixture.files.removed.isEmpty)
        #expect(fixture.files.present == [song])
        #expect(job(fixture, id)?.phase == .done(URL(fileURLWithPath: song)), "the name is left as it is")
        #expect(job(fixture, id)?.findings == both(guess: true), "and the row still says what was found")
    }

    @Test func aDownloadThatDidHappenStillRenamesAndStillTrashesTheFreshCopy() async throws {
        let renamed = fixture(present: [song])
        renamed.analyzer.answer(with: both())
        renamed.submit(1)
        renamed.finishRunningJob(title: "Song")
        await renamed.service.finishAnalyses()
        #expect(renamed.files.moves.map(\.to.path) == [tagged])

        let again = fixture(present: [song, tagged])
        again.analyzer.answer(with: both())
        again.submit(1)
        again.finishRunningJob(title: "Song")
        await again.service.finishAnalyses()
        #expect(again.files.trashed.map(\.path) == [song])
    }

    @Test func aProgressLineForAFileOutsideTheFolderIsNotADownload() async throws {
        let fixture = fixture(present: [song, tagged])
        fixture.analyzer.answer(with: both())
        fixture.submit(1)
        let outside = "\(NookLinkAudioArguments.progressMarker) downloading 50 100 NA \(Fixture.json("/tmp/elsewhere/Song [a1b2].webm"))"
        fixture.runner.last?.say(outside)
        fixture.runner.last?.say(Fixture.fileLine(song))
        fixture.runner.last?.end()
        await fixture.service.finishAnalyses()

        #expect(fixture.files.trashed.isEmpty && fixture.files.moves.isEmpty)
        #expect(fixture.files.present == [song, tagged])
    }

    // MARK: The setting

    @Test func theSettingIsOnUntilTheUserTurnsItOff() {
        let fixture = Fixture()
        #expect(fixture.service.findsKeyAndTempo)
        #expect(fixture.defaults.object(forKey: NookLinkAudioService.findsKeyDefaultsKey) == nil, "on by default writes nothing")
    }

    @Test func turningItOffIsKeptAndTurningItBackOnToo() {
        let fixture = Fixture()
        fixture.service.setFindsKeyAndTempo(false)
        #expect(!fixture.service.findsKeyAndTempo)
        #expect(fixture.defaults.object(forKey: NookLinkAudioService.findsKeyDefaultsKey) as? Bool == false)

        // A service built later on the same store reads it.
        let later = NookLinkAudioService(defaults: fixture.defaults, runner: FakeLinkAudioRunner(), files: FakeLinkAudioFiles(), isExecutable: { _ in false })
        #expect(!later.findsKeyAndTempo)

        fixture.service.setFindsKeyAndTempo(true)
        #expect(fixture.service.findsKeyAndTempo)
        #expect(fixture.defaults.object(forKey: NookLinkAudioService.findsKeyDefaultsKey) as? Bool == true)
    }

    @Test func withTheSettingOffNothingIsAnalyzedOrRenamed() async throws {
        let fixture = fixture()
        fixture.analyzer.answer(with: both())
        fixture.service.setFindsKeyAndTempo(false)
        let id = try #require(fixture.submit(1).first)
        fixture.runner.last?.say(Fixture.titleLine("Song"))
        fixture.runner.last?.say(Fixture.descriptionLine("Key: C# minor | BPM: 127"))
        fixture.runner.last?.say(Fixture.fileLine(song))
        fixture.runner.last?.end()
        await fixture.service.finishAnalyses()

        #expect(fixture.analyzer.calls.isEmpty)
        #expect(fixture.files.moves.isEmpty && fixture.files.trashed.isEmpty)
        #expect(job(fixture, id)?.findings == nil)
        #expect(job(fixture, id)?.phase == .done(URL(fileURLWithPath: song)))
    }

    // The three tests below start a search, hold its answer, stop it by the
    // route under test, let the answer come and wait for the cancelled search
    // to end. The wait for the search to be out comes first and is expected on,
    // which keeps a search that never began from passing for a stopped one.

    @Test func turningItOffWhileTheSearchIsGoingStopsItAndDropsTheAnswer() async throws {
        let fixture = fixture()
        fixture.analyzer.answer(with: both(), holding: true)
        let id = try #require(fixture.submit(1).first)
        fixture.finishRunningJob(title: "Song")
        #expect(await fixture.waitForHeldAnalysis(), "the search is out")

        fixture.service.setFindsKeyAndTempo(false)
        fixture.analyzer.release()
        await fixture.service.finishAnalyses()

        #expect(fixture.analyzer.cancelledCount == 1, "the cancel reached the search")
        #expect(fixture.files.moves.isEmpty && fixture.files.trashed.isEmpty)
        #expect(job(fixture, id)?.findings == nil)
    }

    @Test func aSearchThatWasStoppedDoesNotComeBackWhenTheSettingIsTurnedOnAgain() async throws {
        let fixture = fixture()
        fixture.analyzer.answer(with: both(), holding: true)
        let id = try #require(fixture.submit(1).first)
        fixture.finishRunningJob(title: "Song")
        #expect(await fixture.waitForHeldAnalysis(), "the search is out")

        fixture.service.setFindsKeyAndTempo(false)
        fixture.service.setFindsKeyAndTempo(true)
        fixture.analyzer.release()
        await fixture.service.finishAnalyses()

        #expect(fixture.files.moves.isEmpty && fixture.files.trashed.isEmpty)
        #expect(job(fixture, id)?.findings == nil)
        #expect(job(fixture, id)?.phase == .done(URL(fileURLWithPath: song)))
    }

    @Test func switchingTheWidgetOffStopsASearchAndDropsAnAnswerThatIsOnItsWay() async throws {
        let fixture = fixture()
        fixture.analyzer.answer(with: both(), holding: true)
        fixture.submit(1)
        fixture.finishRunningJob(title: "Song")
        #expect(await fixture.waitForHeldAnalysis(), "the search is out")

        fixture.service.widgetSwitched(false)
        fixture.analyzer.release()
        await fixture.service.finishAnalyses()

        #expect(fixture.analyzer.cancelledCount == 1, "the cancel reached the search")
        #expect(fixture.files.moves.isEmpty && fixture.files.trashed.isEmpty)
        #expect(fixture.service.jobs.isEmpty)
    }

    @Test func aQuitStopsASearchAndDropsAnAnswerThatIsOnItsWay() async throws {
        let fixture = fixture()
        fixture.analyzer.answer(with: both(), holding: true)
        fixture.submit(1)
        fixture.finishRunningJob(title: "Song")
        #expect(await fixture.waitForHeldAnalysis(), "the search is out")

        fixture.service.stopForQuit()
        fixture.analyzer.release()
        await fixture.service.finishAnalyses()

        #expect(fixture.analyzer.cancelledCount == 1, "the cancel reached the search")
        #expect(fixture.files.moves.isEmpty && fixture.files.trashed.isEmpty)
    }

    // MARK: One search at a time

    @Test func twoQuickFinishesAreSearchedOneAfterTheOther() async throws {
        let fixture = fixture(present: [song, "/Users/tester/Music/Hangover/Other [a1b2].mp3"])
        fixture.analyzer.answer(with: both(), holding: true)
        let ids = fixture.submit(2)
        fixture.finishRunningJob(title: "Song")
        fixture.finishRunningJob(title: "Other")
        #expect(await fixture.waitForHeldAnalysis(), "the first search is out")
        for _ in 0..<50 { await Task.yield() }
        #expect(fixture.analyzer.calls.map(\.file.lastPathComponent) == ["Song [a1b2].mp3"], "the second waits for the first")

        fixture.analyzer.release()
        await fixture.service.finishAnalyses()

        #expect(fixture.analyzer.calls.map(\.file.lastPathComponent) == ["Song [a1b2].mp3", "Other [a1b2].mp3"])
        #expect(fixture.analyzer.mostAtOnce == 1)
        #expect(ids.allSatisfy { job(fixture, $0)?.findings == both() })
    }

    @Test func aSearchThatWaitsForTheOneBeforeItIsStoppedToo() async throws {
        let fixture = fixture()
        fixture.analyzer.answer(with: both(), holding: true)
        fixture.submit(2)
        fixture.finishRunningJob(title: "Song")
        fixture.finishRunningJob(title: "Other")
        #expect(await fixture.waitForHeldAnalysis(), "the first search is out")

        fixture.service.widgetSwitched(false)
        fixture.analyzer.release()
        await fixture.service.finishAnalyses()

        #expect(fixture.analyzer.calls.count == 1, "the one that waited never began")
        #expect(fixture.files.moves.isEmpty && fixture.files.trashed.isEmpty)
    }

    @Test func theSettingsSectionHasTheSwitchWiredToTheService() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/OpenIslandApp/Nook/Widgets/LinkAudio/NookLinkAudioSettings.swift"),
            encoding: .utf8
        )
        #expect(source.contains("nook.linkAudio.settings.findKey"))
        #expect(source.contains("get: { service.findsKeyAndTempo }"))
        #expect(source.contains("service.setFindsKeyAndTempo($0)"))
    }

    @Test func aModelOnAStoreOfItsOwnFindsNothingAndTouchesNoFile() async throws {
        let service = NookLinkAudioService.isolated(defaults: MemoryDefaults())
        #expect(service.analyzer is NookLinkAudioRefusingAnalyzer)
        let findings = await service.analyzer.analyze(file: URL(fileURLWithPath: "/nonexistent.mp3"), title: "Key: Em", description: "BPM: 140")
        #expect(findings.isEmpty)
    }
}
