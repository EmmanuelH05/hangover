import AppKit
import Foundation
import Testing
@testable import OpenIslandApp

// What the program says is the site's to write, and what the user's own
// yt-dlp settings say is not the widget's to follow. A title or a path that
// tries to pass for a line of yt-dlp's, a file outside the folder, a config
// file, a playlist, a dollar sign in the folder, and a quit in the middle of
// a download. All through the fake runner.

@MainActor
@Suite struct NookLinkAudioForgedLineTests {
    private typealias Fixture = LinkAudioFixture

    private func phase(_ fixture: Fixture, _ id: UUID) -> NookLinkAudioJob.Phase? {
        fixture.service.queue.job(id)?.phase
    }

    private func end(_ fixture: Fixture, saying path: String) throws -> UUID {
        let id = try #require(fixture.submit(1).first)
        let run = try #require(fixture.runner.last)
        run.say(Fixture.fileLine(path))
        run.end()
        return id
    }

    // MARK: A finished file has to be in the job's folder

    @Test(arguments: [
        "/System/Applications/Calculator.app",
        "/Applications/Safari.app/Contents/MacOS/Safari",
        "/Users/tester/Music/Hangover/../../../../System/Applications/Calculator.app",
        "/Users/tester/Music/Hangover/../Secret.mp3",
        "/Users/tester/Music/Hangover/sub/Song.mp3",
        "/Users/tester/Music/Hangover",
        "/Users/tester/Music/Hangover/",
        "/Users/tester/Music/Hangover/.",
        "/Users/tester/Music/Hangover/..",
        "/Users/tester/Music",
        "/Users/tester/Music/HangoverX/Song.mp3",
        "/Users/tester/Music/Hangover.app",
        "/tmp/Song.mp3",
        "Song.mp3",
        "./Song.mp3",
        "../Song.mp3",
        "~/Music/Hangover/Song.mp3",
        "file:///System/Applications/Calculator.app",
        "/Users/tester/Music/Hangover/a\u{0}b.mp3",
        "/",
    ])
    func aFinishedFileOutsideTheFolderIsNotBelieved(_ path: String) throws {
        let fixture = Fixture()
        let id = try end(fixture, saying: path)
        #expect(phase(fixture, id) == .done(nil), "\(path.debugDescription)")
        fixture.service.showInFinder(id)
        #expect(fixture.shown.map(\.path) == ["/Users/tester/Music/Hangover"], "the folder is shown, never the path that was said")
    }

    @Test(arguments: [
        "/Users/tester/Music/Hangover/Song [a1b2].mp3",
        "/Users/tester/Music/Hangover//Song.mp3",
        "/Users/tester/Music/Hangover/./Song.mp3",
        "/Users/tester/Music/Hangover/sub/../Song.mp3",
        "/Users/tester/Music/Hangover/日本語の曲 🎵 [x9].mp3",
        "/Users/tester/Music/Hangover/Calculator.app",
    ])
    func aFileRightInTheFolderIsBelieved(_ path: String) throws {
        let fixture = Fixture()
        let id = try end(fixture, saying: path)
        guard case let .done(file)? = phase(fixture, id), let file else { Issue.record("no file for \(path)"); return }
        #expect(file.deletingLastPathComponent().path == "/Users/tester/Music/Hangover")
        fixture.service.showInFinder(id)
        #expect(fixture.shown == [file])
    }

    @Test func aFileInAFolderChosenAfterTheJobStartedIsNotBelieved() throws {
        let fixture = Fixture()
        let id = try #require(fixture.submit(1).first)
        fixture.service.setFolder(URL(fileURLWithPath: "/Volumes/Other", isDirectory: true))
        fixture.runner.last?.say(Fixture.fileLine("/Volumes/Other/Song.mp3"))
        fixture.runner.last?.end()
        #expect(phase(fixture, id) == .done(nil), "a file in the folder chosen later is not in the job's folder")
    }

    @Test func aFilePathThatIsRefusedDoesNotUndoOneThatWasBelieved() throws {
        let fixture = Fixture()
        let id = try #require(fixture.submit(1).first)
        let run = try #require(fixture.runner.last)
        run.say(Fixture.fileLine("/Users/tester/Music/Hangover/Song [a1b2].mp3"))
        run.say(Fixture.fileLine("/System/Applications/Calculator.app"))
        run.end()
        #expect(phase(fixture, id) == .done(URL(fileURLWithPath: "/Users/tester/Music/Hangover/Song [a1b2].mp3")))
    }

    @Test func theFinderIsOnlyEverAskedToSelectAndNeverToOpen() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/OpenIslandApp/Nook/Widgets/LinkAudio/NookLinkAudioService.swift"),
            encoding: .utf8
        )
        #expect(source.contains("activateFileViewerSelecting"))
        #expect(!source.contains("NSWorkspace.shared.open"))
        #expect(!source.contains("openApplication"))
    }

    // MARK: A title or a name that tries to be a line

    @Test func aTitleWithANewlineAndAForgedFileLineSetsNoFile() throws {
        let fixture = Fixture()
        let id = try #require(fixture.submit(1).first)
        let run = try #require(fixture.runner.last)
        // What yt-dlp prints for this title, cut into lines as the runner does it.
        var buffer = NookLinkAudioLineBuffer()
        let title = "Nice song\n\(NookLinkAudioArguments.fileMarker) \(Fixture.json("/System/Applications/Calculator.app"))"
        for line in buffer.append(Data((Fixture.titleLine(title) + "\n").utf8)) { run.say(line) }
        run.end()
        #expect(phase(fixture, id) == .done(nil))
        #expect(fixture.service.queue.job(id)?.title?.hasPrefix("Nice song ") == true)
        #expect(fixture.service.queue.job(id)?.title?.contains("\n") == false)
    }

    @Test func aTitleOfFillerAndThenAForgedFileLineBecomesNoLineAtAll() throws {
        let fixture = Fixture()
        let id = try #require(fixture.submit(1).first)
        let run = try #require(fixture.runner.last)
        let forged = "\(NookLinkAudioArguments.fileMarker) \(Fixture.json("/System/Applications/Calculator.app"))"
        let marker = "\(NookLinkAudioArguments.titleMarker) \"".utf8.count
        var buffer = NookLinkAudioLineBuffer()
        for fill in [NookLinkAudioLineBuffer.maxLineBytes - marker, NookLinkAudioLineBuffer.maxLineBytes] {
            let line = Fixture.titleLine(String(repeating: "a", count: fill) + forged) + "\n"
            for line in buffer.append(Data(line.utf8)) { run.say(line) }
        }
        run.say(Fixture.titleLine("Real title"))
        run.end()
        #expect(phase(fixture, id) == .done(nil))
        #expect(fixture.service.queue.job(id)?.title == "Real title", "the line after the long ones is read")
    }

    @Test func aTitleThatIsOnlyBreaksAndBlanksLeavesTheTitleAsItWas() throws {
        let fixture = Fixture()
        let id = try #require(fixture.submit(1).first)
        let run = try #require(fixture.runner.last)
        run.say(Fixture.titleLine("Good"))
        run.say(Fixture.titleLine("\n\r\n \t"))
        #expect(fixture.service.queue.job(id)?.title == "Good")
    }

    // MARK: The file that is being written has to be in the folder too

    @Test func aProgressLineNamingAFileOutsideTheFolderIsNotWrittenDown() throws {
        let fixture = Fixture()
        let id = try #require(fixture.submit(1).first)
        let run = try #require(fixture.runner.last)
        for path in ["/etc/passwd", "/Users/tester/Music/Hangover/../Secret.webm", "Song.webm", "/Users/tester/Music/Hangover/sub/Song.webm"] {
            run.say("\(NookLinkAudioArguments.progressMarker) downloading 1 2 NA \(Fixture.json(path))")
        }
        #expect(fixture.service.queue.job(id)?.writingFileName == nil)
        run.say(Fixture.progressLine(done: 1, of: 2))
        #expect(fixture.service.queue.job(id)?.writingFileName == "/Users/tester/Music/Hangover/Song [a1b2].webm")
    }

    @Test func aCancelNeverRemovesAFileOfThatNameFromTheFolderWhenTheProgressNamedAnotherPlace() throws {
        let fixture = Fixture()
        let id = try #require(fixture.submit(1).first)
        let run = try #require(fixture.runner.last)
        run.say("\(NookLinkAudioArguments.progressMarker) downloading 1 2 NA \(Fixture.json("/etc/Important.mp3"))")
        fixture.files.entries = ["Important.mp3": Fixture.start.addingTimeInterval(5)]
        fixture.service.cancel(id)
        run.end(status: 130, wasSignalled: true)
        #expect(fixture.files.removed.isEmpty)
        #expect(fixture.files.entries.count == 1)
    }

    @Test func aCancelRemovesFromTheFolderTheJobStartedInAndNotTheOneChosenSince() throws {
        let fixture = Fixture()
        let id = try #require(fixture.submit(1).first)
        let run = try #require(fixture.runner.last)
        run.say(Fixture.progressLine(done: 1, of: 2))
        fixture.service.setFolder(URL(fileURLWithPath: "/Volumes/Other", isDirectory: true))
        fixture.files.entries = ["Song [a1b2].webm.part": Fixture.start.addingTimeInterval(5)]
        fixture.service.cancel(id)
        run.end(status: 130, wasSignalled: true)
        #expect(fixture.files.listedFolders.map(\.path) == ["/Users/tester/Music/Hangover"])
        #expect(fixture.files.removed.map(\.path) == ["/Users/tester/Music/Hangover/Song [a1b2].webm.part"])
    }
}

// MARK: - The user's own settings, a playlist and the working folder

@MainActor
@Suite struct NookLinkAudioLaunchSafetyTests {
    private typealias Fixture = LinkAudioFixture

    @Test func aJobStartsWithNoConfigFileOfTheUsersAndFromItsOwnFolder() throws {
        let fixture = Fixture()
        fixture.service.submit(Fixture.link(1))
        let launch = try #require(fixture.runner.last).launch
        #expect(launch.arguments.first == "--ignore-config")
        #expect(launch.currentDirectory?.path == "/Users/tester/Music/Hangover")
        #expect(launch.currentDirectory?.hasDirectoryPath == true)
    }

    @Test func aFolderChosenLaterIsTheWorkingFolderOfTheNextJobAndNotOfTheRunningOne() throws {
        let fixture = Fixture()
        fixture.submit(2)
        fixture.service.setFolder(URL(fileURLWithPath: "/Volumes/Other", isDirectory: true))
        #expect(fixture.runner.runs[0].launch.currentDirectory?.path == "/Users/tester/Music/Hangover")
        fixture.runner.runs[0].end()
        #expect(fixture.runner.runs[1].launch.currentDirectory?.path == "/Volumes/Other")
        #expect(fixture.runner.runs[1].launch.arguments.first == "--ignore-config")
    }

    @Test func aPlaylistOrAChannelLinkStartsOneProcessForItsFirstEntry() throws {
        let fixture = Fixture()
        fixture.service.submit("https://www.youtube.com/playlist?list=PL123")
        fixture.service.submit("https://www.youtube.com/@channel/videos")
        #expect(fixture.runner.runs.count == 1, "one job at a time, and one job for a playlist")
        let arguments = try #require(fixture.runner.last).launch.arguments
        let at = try #require(arguments.firstIndex(of: "--playlist-items"))
        #expect(arguments[at + 1] == "1")
    }
}

// MARK: - A dollar sign in the folder

@MainActor
@Suite struct NookLinkAudioFolderDollarTests {
    private typealias Fixture = LinkAudioFixture

    @Test(arguments: ["/Users/tester/$HOME/Songs", "/Users/tester/Music/$", "/Volumes/${DISK}/Songs", "/Users/tester/Mu$ic", "/$USER"])
    func aFolderWithADollarSignIsRefusedAndTheFolderThatWasSetStays(_ path: String) {
        let fixture = Fixture()
        let before = fixture.service.folder
        let result = fixture.service.setFolder(URL(fileURLWithPath: path, isDirectory: true))

        #expect(result == .hasDollar)
        #expect(fixture.service.folder == before)
        #expect(fixture.service.folderProblem == .hasDollar)
        #expect(fixture.defaults.string(forKey: NookLinkAudioFolderRule.defaultsKey) == nil, "nothing is saved")
    }

    @Test func theLineSaysWhyInEveryLanguageAndGoesWithTheNextGoodFolder() {
        let fixture = Fixture()
        fixture.service.setFolder(URL(fileURLWithPath: "/Users/tester/$X", isDirectory: true))
        let key = NookLinkAudioFolderRefusal.hasDollar.messageKey
        let line = LanguageManager.shared.t(key)
        #expect(line != key)
        #expect(line.contains("$") || line.contains("dollar") || line.contains("美元"))

        let result = fixture.service.setFolder(URL(fileURLWithPath: "/Volumes/Disk/Songs", isDirectory: true))
        #expect(result == nil)
        #expect(fixture.service.folderProblem == nil)
        #expect(fixture.service.folder.path == "/Volumes/Disk/Songs")
    }

    @Test func otherSpecialCharactersAreFine() {
        let fixture = Fixture()
        for path in ["/Volumes/100%/Songs", "/Users/tester/Songs & More", "/Users/tester/My Songs (1)", "/Users/tester/日本語", "/Users/tester/[x]"] {
            #expect(fixture.service.setFolder(URL(fileURLWithPath: path, isDirectory: true)) == nil, "\(path)")
        }
    }

    @Test func aSavedFolderWithADollarSignIsNotUsedAndTheDefaultStandsIn() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        #expect(NookLinkAudioFolderRule.resolve(saved: "/Users/tester/$HOME", home: home).path == "/Users/tester/Music/Hangover")
        #expect(NookLinkAudioFolderRule.resolve(saved: "/Users/tester/Fine", home: home).path == "/Users/tester/Fine")
        #expect(NookLinkAudioFolderRule.refusal(for: URL(fileURLWithPath: "/a/b")) == nil)
        #expect(NookLinkAudioFolderRule.refusal(for: URL(fileURLWithPath: "/a/$b")) == .hasDollar)
    }

    @Test func aFolderWithADollarSignThatGotInAnyWayFailsTheJobAndStartsNothing() throws {
        let fixture = Fixture(folder: URL(fileURLWithPath: "/Users/tester/$HOME/Songs", isDirectory: true))
        guard case let .queued(id) = fixture.service.submit(Fixture.link(1)) else { Issue.record("not queued"); return }
        #expect(fixture.runner.runs.isEmpty)
        #expect(fixture.files.madeFolders.isEmpty)
        #expect(fixture.service.queue.job(id)?.phase == .failed(.folderHasDollar))
        #expect(LanguageManager.shared.t(NookLinkAudioFailure.folderHasDollar.messageKey) != NookLinkAudioFailure.folderHasDollar.messageKey)
    }

    @Test func theTemplateStillHoldsNoDollarForTheFoldersThatAreAllowed() {
        let template = NookLinkAudioArguments.outputTemplate(folder: URL(fileURLWithPath: "/Users/tester/Music/Hangover", isDirectory: true))
        #expect(!template.contains("$"))
    }
}

// MARK: - A quit in the middle of a download

@MainActor
@Suite struct NookLinkAudioQuitTests {
    private typealias Fixture = LinkAudioFixture

    private func started(_ fixture: Fixture) -> NookModel {
        let nook = NookModel(linkAudio: fixture.service, defaults: MemoryDefaults(), looksForImportedGIF: false)
        fixture.service.start(nook: nook)
        return nook
    }

    private func quit(_ fixture: Fixture) {
        fixture.notifications.post(name: NSApplication.willTerminateNotification, object: nil)
    }

    /// A job that has downloaded some of `Song [a1b2].webm`, with its parts on the disk.
    private func downloading(_ fixture: Fixture) throws -> (id: UUID, run: FakeLinkAudioRunner.Run) {
        let id = try #require(fixture.submit(1).first)
        let run = try #require(fixture.runner.last)
        run.say(Fixture.titleLine("Song"))
        run.say(Fixture.progressLine(done: 40, of: 100))
        fixture.files.entries = [
            "Song [a1b2].webm.part": Fixture.start.addingTimeInterval(5),
            "Song [a1b2].webm.ytdl": Fixture.start.addingTimeInterval(5),
            "Mine.mp3": Fixture.start.addingTimeInterval(-9_999),
        ]
        return (id, run)
    }

    @Test func aQuitStopsTheRunningProcessAndRemovesWhatItWrote() throws {
        let fixture = Fixture()
        _ = started(fixture)
        let (id, run) = try downloading(fixture)

        quit(fixture)

        #expect(run.quitStopCount == 1)
        #expect(fixture.files.removed.map(\.lastPathComponent).sorted() == ["Song [a1b2].webm.part", "Song [a1b2].webm.ytdl"])
        #expect(Set(fixture.files.entries.keys) == ["Mine.mp3"])
        #expect(fixture.service.queue.job(id) == nil)
    }

    @Test func theCleanUpHappensAfterTheProcessWasWaitedFor() throws {
        let fixture = Fixture()
        _ = started(fixture)
        let (_, run) = try downloading(fixture)
        var removedWhenStopped = -1
        run.whenStoppedForQuit = { removedWhenStopped = fixture.files.removed.count }

        quit(fixture)

        #expect(removedWhenStopped == 0, "nothing is removed until the process is gone")
        #expect(fixture.files.removed.count == 2)
    }

    @Test func theLineIsEmptiedAndNothingStartsAfterTheQuit() throws {
        let fixture = Fixture()
        _ = started(fixture)
        fixture.submit(4)
        let run = try #require(fixture.runner.last)

        quit(fixture)

        #expect(fixture.service.queue.waiting.isEmpty)
        #expect(fixture.service.queue.running == nil)
        run.end(status: 130, wasSignalled: true)
        #expect(fixture.runner.runs.count == 1, "the end of the stopped process starts no other")
    }

    @Test func theEndOfTheStoppedProcessChangesNothingAfterTheQuit() throws {
        let fixture = Fixture()
        _ = started(fixture)
        let (_, run) = try downloading(fixture)
        quit(fixture)
        let after = fixture.service.queue
        let removed = fixture.files.removed.count
        run.say(Fixture.titleLine("Late"))
        run.end(status: 0)
        #expect(fixture.service.queue == after)
        #expect(fixture.files.removed.count == removed)
    }

    @Test func aQuitWithNothingRunningDoesNothing() {
        let fixture = Fixture()
        _ = started(fixture)
        fixture.submit(1)
        fixture.finishRunningJob()
        let before = fixture.service.queue
        quit(fixture)
        #expect(fixture.service.queue.running == nil)
        #expect(fixture.service.queue.finished == before.finished)
        #expect(fixture.files.removed.isEmpty)
        #expect(fixture.runner.runs.allSatisfy { $0.quitStopCount == 0 })
    }

    @Test func aJobThatIsAlreadyBeingCancelledIsStillWaitedForOnAQuit() throws {
        let fixture = Fixture()
        _ = started(fixture)
        let (id, run) = try downloading(fixture)
        fixture.service.cancel(id)
        #expect(run.cancelCount == 1)

        quit(fixture)

        #expect(run.quitStopCount == 1)
        #expect(run.cancelCount == 1, "the interrupt is not sent twice by the service")
        #expect(fixture.files.removed.count == 2)
        #expect(fixture.service.queue.job(id) == nil)
    }

    @Test func theQuitIsOnlyListenedForOnceTheServiceHasStarted() throws {
        let fixture = Fixture()
        let (_, run) = try downloading(fixture)
        quit(fixture)
        #expect(run.quitStopCount == 0, "a service nobody started has no one listening")

        _ = started(fixture)
        fixture.service.start(nook: NookModel(linkAudio: fixture.service, defaults: MemoryDefaults(), looksForImportedGIF: false))
        quit(fixture)
        #expect(run.quitStopCount == 1, "started twice, listening once")
    }

    @Test func aQuitIsNotAnythingElseThatIsPosted() throws {
        let fixture = Fixture()
        _ = started(fixture)
        let (_, run) = try downloading(fixture)
        fixture.notifications.post(name: NSApplication.didResignActiveNotification, object: nil)
        fixture.notifications.post(name: NSApplication.willResignActiveNotification, object: nil)
        #expect(run.quitStopCount == 0)
    }

    @Test func aServiceOnItsOwnCenterNeverHearsTheRealOne() throws {
        let fixture = Fixture()
        _ = started(fixture)
        let (_, run) = try downloading(fixture)
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
        #expect(run.quitStopCount == 0)
    }

    @Test func theRealRunnerWaitsForTheProcessOnAQuit() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/OpenIslandApp/Nook/Widgets/LinkAudio/NookLinkAudioProcessRunner.swift"),
            encoding: .utf8
        )
        #expect(source.contains("func stopForQuit()"))
        #expect(source.contains("process.interrupt()"))
        #expect(source.contains("currentDirectoryURL = launch.currentDirectory"))
    }
}
