import Foundation
import Testing
@testable import OpenIslandApp

// The argument list handed to `Process`: an array, the link last after
// `--`, the output name `yt-dlp` fills in itself, and the flags that keep
// a file that is already there from being replaced.

@Suite struct NookLinkAudioArgumentsTests {
    private let folder = URL(fileURLWithPath: "/Users/tester/Music/Hangover", isDirectory: true)
    private let ffmpegFolder = URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true)

    private func link(_ text: String = "https://example.com/watch?v=abc") throws -> NookLinkAudioLink {
        try NookLinkAudioLink.check(text).get()
    }

    private func arguments(_ text: String = "https://example.com/watch?v=abc", folder: URL? = nil) throws -> [String] {
        NookLinkAudioArguments.make(link: try link(text), folder: folder ?? self.folder, ffmpegDirectory: ffmpegFolder)
    }

    @Test func theListIsTheOneThatWasAskedFor() throws {
        let list = try arguments()
        #expect(list == [
            "--ignore-config",
            "-x",
            "--audio-format", "mp3",
            "--audio-quality", "0",
            "--no-playlist",
            "--playlist-items", "1",
            "--no-overwrites",
            "--newline",
            "--progress",
            "--no-simulate",
            "--progress-template", NookLinkAudioArguments.progressTemplate,
            "--ffmpeg-location", "/opt/homebrew/bin",
            "-o", "/Users/tester/Music/Hangover/%(title)s [%(id)s].%(ext)s",
            "--print", "before_dl:hangover-title %(title)j",
            "--print", "before_dl:hangover-description %(description)j",
            "--print", "after_move:hangover-file %(filepath)j",
            "--",
            "https://example.com/watch?v=abc",
        ])
    }

    @Test func theArgumentsEndWithTheDoubleDashAndTheLink() throws {
        for text in [
            "https://example.com/a",
            "https://example.com/a?b=c&d=e#f",
            "https://example.com/-x",
            "https://example.com/a;b=$(c)&d=`e`",
        ] {
            let list = try arguments(text)
            #expect(Array(list.suffix(2)) == ["--", text])
            #expect(list.filter { $0 == "--" }.count == 1)
        }
    }

    @Test func theLinkIsInTheListOnceAndOnlyAfterTheDoubleDash() throws {
        let text = "https://example.com/watch?v=abc"
        let list = try arguments(text)
        let at = try #require(list.firstIndex(of: "--"))
        #expect(list[..<at].allSatisfy { !$0.contains(text) })
        #expect(list[(at + 1)...] == [text])
    }

    @Test func aLinkWithShellCharactersStaysOneArgument() throws {
        let text = "https://example.com/a;rm$(id)&&b|c`d`?e=f"
        let list = try arguments(text)
        #expect(list.last == text)
        #expect(list.count == (try arguments()).count)
    }

    @Test func everyOptionWithAValueIsTwoArguments() throws {
        let list = try arguments()
        for (name, value) in [("--audio-format", "mp3"), ("--audio-quality", "0")] {
            let at = try #require(list.firstIndex(of: name))
            #expect(list[at + 1] == value)
        }
        #expect(list.contains("-x"))
        #expect(list.contains("--no-playlist"))
        #expect(list.contains("--newline"))
        #expect(!list.contains { $0.contains("--audio-format mp3") }, "an option and its value are not one string")
    }

    @Test func ffmpegIsGivenAsTheFolderItWasFoundIn() throws {
        let list = try arguments()
        let at = try #require(list.firstIndex(of: "--ffmpeg-location"))
        #expect(list[at + 1] == "/opt/homebrew/bin")
    }

    @Test func aFileOfTheUsersIsNotTakenForTheDownloadAndTheOnesYtDlpMadeAreLeftAlone() throws {
        let list = try arguments()
        // A download whose finished .mp3 is there is not fetched again, and a
        // file of the user's with the same title has no id in its name.
        #expect(list.contains("--no-overwrites"))
        #expect(!list.contains("--force-overwrites"))
        #expect(!list.contains("-f"))
        let at = try #require(list.firstIndex(of: "-o"))
        #expect(list[at + 1] == "\(folder.path)/%(title)s [%(id)s].%(ext)s")
        // The name is the title and the id yt-dlp reads, never a name made here.
        #expect(list[at + 1].hasSuffix("/%(title)s [%(id)s].%(ext)s"))
        #expect(NookLinkAudioArguments.fileNameTemplate.contains("%(id)s"))
    }

    @Test func theOutputNameKeepsTheFolderAndAddsNoNameOfItsOwn() {
        #expect(NookLinkAudioArguments.outputTemplate(folder: folder) == "/Users/tester/Music/Hangover/%(title)s [%(id)s].%(ext)s")
        let slash = URL(fileURLWithPath: "/Users/tester/Music/", isDirectory: true)
        #expect(NookLinkAudioArguments.outputTemplate(folder: slash) == "/Users/tester/Music/%(title)s [%(id)s].%(ext)s")
        let spaces = URL(fileURLWithPath: "/Volumes/My Disk/Songs & More", isDirectory: true)
        #expect(NookLinkAudioArguments.outputTemplate(folder: spaces) == "/Volumes/My Disk/Songs & More/%(title)s [%(id)s].%(ext)s")
    }

    @Test func aPercentSignInTheFolderIsDoubledForYtDlp() {
        let odd = URL(fileURLWithPath: "/Users/tester/100%/%(title)s", isDirectory: true)
        #expect(NookLinkAudioArguments.outputTemplate(folder: odd) == "/Users/tester/100%%/%%(title)s/%(title)s [%(id)s].%(ext)s")
    }

    @Test func theProgressTemplateAsksForTheFieldsTheParserReads() {
        let template = NookLinkAudioArguments.progressTemplate
        #expect(template.hasPrefix("download:\(NookLinkAudioArguments.progressMarker) "))
        for field in ["status", "downloaded_bytes", "total_bytes", "total_bytes_estimate"] {
            #expect(template.contains("%(progress.\(field))s"), "\(field)")
        }
        // The file name comes last, as JSON: it can hold spaces, and a newline in it must not end the line.
        #expect(template.hasSuffix("%(progress.filename)j"))
    }

    @Test func theTemplateThatIsAskedForIsTheOneTheParserReads() {
        let line = "\(NookLinkAudioArguments.progressMarker) downloading 1024 4096 NA \(LinkAudioFixture.json("/music/My Song.webm"))"
        #expect(NookLinkAudioOutput.parse(line) == .progress(fraction: 0.25, isDownloadDone: false, fileName: "/music/My Song.webm"))
    }

    @Test func theUsersOwnYtDlpSettingsAreIgnoredAndTheFlagComesFirst() throws {
        for text in ["https://example.com/a", "https://example.com/--ignore-config"] {
            let list = try arguments(text)
            #expect(list.first == "--ignore-config", "an option read before it would still reach the job")
            #expect(list.filter { $0 == "--ignore-config" }.count == 1)
        }
    }

    @Test func aPlaylistOrAChannelSavesItsFirstEntryOnly() throws {
        let list = try arguments("https://www.youtube.com/@channel/videos")
        let at = try #require(list.firstIndex(of: "--playlist-items"))
        #expect(list[at + 1] == "1")
        #expect(list.contains("--no-playlist"))
        let end = try #require(list.firstIndex(of: "--"))
        #expect(at < end, "before the double dash, where options are read")
    }

    @Test func theTitleTheDescriptionAndTheFinishedFileArePrintedAsJSON() throws {
        let list = try arguments()
        let prints = list.indices.filter { list[$0] == "--print" }.map { list[$0 + 1] }
        #expect(prints == [
            "before_dl:hangover-title %(title)j",
            "before_dl:hangover-description %(description)j",
            "after_move:hangover-file %(filepath)j",
        ])
    }

    @Test func theDescriptionIsAskedForBeforeTheDownloadAndAsJSONSoItsLineBreaksStayInsideTheLine() throws {
        let list = try arguments()
        let print = try #require(list.first { $0.hasPrefix("before_dl:\(NookLinkAudioArguments.descriptionMarker) ") })
        #expect(print.hasSuffix("%(description)j"))
        // The marker is its own word, not a part of the other two.
        #expect(Set([NookLinkAudioArguments.titleMarker, NookLinkAudioArguments.descriptionMarker, NookLinkAudioArguments.fileMarker, NookLinkAudioArguments.progressMarker]).count == 4)
        // Before the double dash, where options are read.
        let at = try #require(list.firstIndex(of: print))
        #expect(at < (try #require(list.firstIndex(of: "--"))))
    }

    @Test func nothingInTheListIsAShellAndNoCommandStringIsBuilt() throws {
        let list = try arguments()
        #expect(!list.contains("-c"))
        #expect(!list.contains("sh"))
        #expect(!list.contains("/bin/sh"))
        #expect(!list.contains("/bin/zsh"))
        let source = try String(contentsOf: Self.sourceFile("NookLinkAudioProcessRunner.swift"), encoding: .utf8)
        #expect(!source.contains("/bin/sh"))
        #expect(!source.contains("/bin/zsh"))
        #expect(!source.contains("\"-c\""))
    }

    private static func sourceFile(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/OpenIslandApp/Nook/Widgets/LinkAudio/\(name)")
    }
}
