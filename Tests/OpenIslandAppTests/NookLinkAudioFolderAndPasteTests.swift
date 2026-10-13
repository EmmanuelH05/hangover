import AppKit
import Foundation
import Testing
@testable import OpenIslandApp

// Where the files go (Music/Hangover by default, a chosen folder otherwise,
// made on first use), the Paste button's clipboard read, and the folder
// chooser counted as a system window (D52). No window is shown and the real
// clipboard is never read.

@MainActor
@Suite struct NookLinkAudioFolderTests {
    private typealias Fixture = LinkAudioFixture
    private let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    @Test func theDefaultIsMusicHangoverInTheHomeFolder() {
        #expect(NookLinkAudioFolderRule.defaultFolder(home: home).path == "/Users/tester/Music/Hangover")
        #expect(Fixture().folder.path == "/Users/tester/Music/Hangover")
    }

    @Test func aSavedAbsolutePathIsTheFolderAndAnythingElseIsNot() {
        #expect(NookLinkAudioFolderRule.resolve(saved: "/Volumes/Disk/Songs", home: home).path == "/Volumes/Disk/Songs")
        let fallback = NookLinkAudioFolderRule.defaultFolder(home: home)
        for saved in [nil, "", "relative/path", "~/Music", "Music", "/"] as [String?] {
            #expect(NookLinkAudioFolderRule.resolve(saved: saved, home: home) == fallback, "\(String(describing: saved))")
        }
    }

    @Test func aChosenFolderIsSavedAndUsedTheNextTime() {
        let first = Fixture()
        first.service.setFolder(URL(fileURLWithPath: "/Volumes/Disk/Songs", isDirectory: true))
        #expect(first.service.folder.path == "/Volumes/Disk/Songs")
        #expect(first.defaults.string(forKey: NookLinkAudioFolderRule.defaultsKey) == "/Volumes/Disk/Songs")

        let again = NookLinkAudioService(
            defaults: first.defaults,
            home: home,
            runner: FakeLinkAudioRunner(),
            files: FakeLinkAudioFiles(),
            clipboard: FakeLinkAudioClipboard(),
            isExecutable: { _ in false },
            showInFinder: { _ in }
        )
        #expect(again.folder.path == "/Volumes/Disk/Songs")
    }

    @Test func aFolderGivenToTheInitializerWinsOverTheSavedOne() {
        let defaults = MemoryDefaults()
        defaults.set("/Volumes/Disk/Songs", forKey: NookLinkAudioFolderRule.defaultsKey)
        let given = URL(fileURLWithPath: "/tmp/given", isDirectory: true)
        let service = NookLinkAudioService(defaults: defaults, folder: given, home: home, isExecutable: { _ in false })
        #expect(service.folder == given)
    }

    @Test func theChosenFolderIsMadeOnFirstUseAndIsWhereTheFilesGo() throws {
        let fixture = Fixture()
        fixture.service.setFolder(URL(fileURLWithPath: "/Volumes/Disk/My Songs", isDirectory: true))
        #expect(fixture.files.madeFolders.isEmpty, "choosing makes nothing")

        fixture.service.submit(Fixture.link(1))
        #expect(fixture.files.madeFolders.map(\.path) == ["/Volumes/Disk/My Songs"])
        let run = try #require(fixture.runner.last)
        let at = try #require(run.launch.arguments.firstIndex(of: "-o"))
        #expect(run.launch.arguments[at + 1] == "/Volumes/Disk/My Songs/%(title)s [%(id)s].%(ext)s")
    }

    @Test func aJobThatIsRunningKeepsTheFolderItStartedWithAndTheNextOneUsesTheNewFolder() throws {
        let fixture = Fixture()
        fixture.submit(2)
        fixture.service.setFolder(URL(fileURLWithPath: "/Volumes/Other", isDirectory: true))
        let first = try #require(fixture.runner.last)
        #expect(first.launch.arguments.contains("/Users/tester/Music/Hangover/%(title)s [%(id)s].%(ext)s"))

        first.end()
        let second = try #require(fixture.runner.last)
        #expect(second.launch.arguments.contains("/Volumes/Other/%(title)s [%(id)s].%(ext)s"))
        #expect(fixture.files.madeFolders.map(\.path) == ["/Users/tester/Music/Hangover", "/Volumes/Other"])
    }

    @Test func aModelOnAStoreOfItsOwnGetsAFolderUnderTheTemporaryFolder() {
        let service = NookLinkAudioService.isolated(defaults: MemoryDefaults())
        let other = NookLinkAudioService.isolated(defaults: MemoryDefaults())
        #expect(service.folder.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        #expect(service.folder != other.folder)
        #expect(!service.folder.path.contains("/Music/"))
        #expect(!FileManager.default.fileExists(atPath: service.folder.path), "nothing is made until a job runs")
    }

    // MARK: The environment

    @Test func theRunEnvironmentKeepsTheAppsOwnAndSetsTheFewThingsItNeeds() {
        let environment = NookLinkAudioService.environment(from: ["HOME": "/h", "PATH": "/nope", "X": "y"])
        #expect(environment["HOME"] == "/h")
        #expect(environment["X"] == "y")
        #expect(environment["PATH"] == NookLinkAudioToolSearch.runPath)
        #expect(environment["PYTHONUNBUFFERED"] == "1")
        #expect(environment["PYTHONIOENCODING"] == "utf-8")
    }
}

// MARK: - Paste

@MainActor
@Suite struct NookLinkAudioPasteTests {
    private typealias Fixture = LinkAudioFixture

    private func nook(_ fixture: Fixture) -> NookModel {
        let nook = NookModel(linkAudio: fixture.service, defaults: MemoryDefaults(), looksForImportedGIF: false)
        fixture.service.start(nook: nook)
        return nook
    }

    @Test func aLinkOnTheClipboardIsSavedAtOnce() {
        let fixture = Fixture()
        fixture.clipboard.text = "  \(Fixture.link(1))\n"
        let result = fixture.service.pasteAndSave()
        guard case .submitted(.queued) = result else { Issue.record("not queued: \(result)"); return }
        #expect(fixture.runner.runs.count == 1)
        #expect(fixture.runner.last?.link == Fixture.link(1))
        #expect(fixture.clipboard.readCount == 1)
    }

    @Test func textThatIsNotALinkIsRefusedWithAReason() {
        let fixture = Fixture()
        fixture.clipboard.text = "--exec=touch /tmp/x"
        let result = fixture.service.pasteAndSave()
        #expect(result == .submitted(.refused(.notAWebLink)))
        #expect(fixture.service.problem == .refused(.notAWebLink))
        #expect(fixture.runner.runs.isEmpty)
    }

    @Test func anEmptyClipboardSaysSo() {
        let fixture = Fixture()
        fixture.clipboard.text = nil
        #expect(fixture.service.pasteAndSave() == .nothing)
        #expect(fixture.service.problem == .pasteNothing)
        #expect(fixture.runner.runs.isEmpty)
    }

    @Test func aClipboardMacOSRefusesIsNeverRead() {
        let fixture = Fixture()
        fixture.clipboard.access = .denied
        fixture.clipboard.text = Fixture.link(1)
        #expect(fixture.service.pasteAndSave() == .notAllowed)
        #expect(fixture.service.problem == .pasteNotAllowed)
        #expect(fixture.clipboard.readCount == 0)
        #expect(fixture.runner.runs.isEmpty)
    }

    @Test func aReadThatMakesMacOSAskIsASystemWindowWhileItWaits() {
        let fixture = Fixture()
        let nook = nook(fixture)
        var told: [Bool] = []
        nook.onSystemPromptChange = { told.append($0) }
        fixture.clipboard.access = .asks
        fixture.clipboard.text = Fixture.link(1)

        let result = fixture.service.pasteAndSave()

        guard case .submitted(.queued) = result else { Issue.record("not queued: \(result)"); return }
        #expect(told == [true, false])
        #expect(!nook.isSystemPromptUp)
        #expect(fixture.clipboard.readCount == 1)
    }

    @Test func anAnswerOfNoAtTheAlertIsToldAsItIs() {
        let fixture = Fixture()
        let nook = nook(fixture)
        fixture.clipboard.access = .asks
        fixture.clipboard.text = nil
        #expect(fixture.service.pasteAndSave() == .nothing)
        #expect(fixture.service.problem == .pasteMaybeRefused)
        #expect(!nook.isSystemPromptUp)
    }

    @Test func aReadThatNeedsNoAlertCountsAsNoSystemWindow() {
        let fixture = Fixture()
        let nook = nook(fixture)
        var told: [Bool] = []
        nook.onSystemPromptChange = { told.append($0) }
        fixture.clipboard.text = Fixture.link(1)
        fixture.service.pasteAndSave()
        #expect(told.isEmpty)
    }

    @Test func withAProgramMissingTheClipboardIsNotRead() {
        let fixture = Fixture()
        fixture.executables = []
        fixture.clipboard.text = Fixture.link(1)
        #expect(fixture.service.pasteAndSave() == .submitted(.toolsMissing))
        #expect(fixture.clipboard.readCount == 0)
        #expect(fixture.service.problem == .toolsMissing)
        #expect(fixture.runner.runs.isEmpty)
    }
}

// MARK: - The folder chooser

@MainActor
@Suite struct NookLinkAudioFolderPickerTests {
    private typealias Fixture = LinkAudioFixture

    private func nook(_ fixture: Fixture) -> NookModel {
        NookModel(linkAudio: fixture.service, defaults: MemoryDefaults(), looksForImportedGIF: false)
    }

    @Test func theChooserIsASystemWindowWhileItIsUpAndNotAfter() {
        let fixture = Fixture()
        let nook = nook(fixture)
        var told: [Bool] = []
        nook.onSystemPromptChange = { told.append($0) }
        var wasUp = false
        var startedAt: URL?

        NookLinkAudioFolderPicker.choose(for: nook) { current in
            wasUp = nook.isSystemPromptUp
            startedAt = current
            return URL(fileURLWithPath: "/Volumes/Disk/Songs", isDirectory: true)
        }

        #expect(wasUp)
        #expect(told == [true, false])
        #expect(!nook.isSystemPromptUp)
        #expect(startedAt?.path == "/Users/tester/Music/Hangover")
        #expect(fixture.service.folder.path == "/Volumes/Disk/Songs")
    }

    @Test func aChooserThatIsCancelledKeepsTheFolderAndStillEndsItsWindow() {
        let fixture = Fixture()
        let nook = nook(fixture)
        NookLinkAudioFolderPicker.choose(for: nook) { _ in nil }
        #expect(!nook.isSystemPromptUp)
        #expect(fixture.service.folder.path == "/Users/tester/Music/Hangover")
        #expect(fixture.defaults.string(forKey: NookLinkAudioFolderRule.defaultsKey) == nil)
    }

    @Test func theFileThatRaisesTheChooserIsInTheListThePromptTestChecks() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("Sources/OpenIslandApp/Nook/Widgets/LinkAudio")
        let picker = try String(contentsOf: folder.appendingPathComponent("NookLinkAudioFolderPicker.swift"), encoding: .utf8)
        #expect(picker.components(separatedBy: ".systemPromptBegan()").count == 2)
        #expect(picker.components(separatedBy: ".systemPromptEnded()").count == 2)
        #expect(picker.contains("NSOpenPanel"))

        let list = try String(
            contentsOf: root.appendingPathComponent("Tests/OpenIslandAppTests/EdgeCaseSystemPromptTests.swift"),
            encoding: .utf8
        )
        #expect(list.contains("\"NookLinkAudioFolderPicker.swift\""))
        #expect(list.contains("\"NookLinkAudioPaste.swift\""))
    }
}
