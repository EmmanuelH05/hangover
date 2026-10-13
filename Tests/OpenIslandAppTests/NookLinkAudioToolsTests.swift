import Foundation
import Testing
@testable import OpenIslandApp

// The search for yt-dlp and ffmpeg: three folders in a fixed order, asked
// through a made-up "file exists" function. Nothing is looked for on disk.

@Suite struct NookLinkAudioToolsTests {
    private func exists(_ paths: String...) -> (String) -> Bool {
        let set = Set(paths)
        return { set.contains($0) }
    }

    @Test func theFoldersAreSearchedInTheOrderTheyWereAskedFor() {
        #expect(NookLinkAudioToolSearch.directories == ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"])
    }

    @Test func theFirstFolderThatHoldsTheProgramWins() {
        let all = exists(
            "/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/usr/bin/yt-dlp"
        )
        #expect(NookLinkAudioToolSearch.find(.ytDlp, isExecutable: all)?.path == "/opt/homebrew/bin/yt-dlp")

        let second = exists("/usr/local/bin/yt-dlp", "/usr/bin/yt-dlp")
        #expect(NookLinkAudioToolSearch.find(.ytDlp, isExecutable: second)?.path == "/usr/local/bin/yt-dlp")

        let third = exists("/usr/bin/yt-dlp")
        #expect(NookLinkAudioToolSearch.find(.ytDlp, isExecutable: third)?.path == "/usr/bin/yt-dlp")
    }

    @Test func eachProgramIsLookedForUnderItsOwnName() {
        let only = exists("/usr/local/bin/ffmpeg")
        #expect(NookLinkAudioToolSearch.find(.ffmpeg, isExecutable: only)?.path == "/usr/local/bin/ffmpeg")
        #expect(NookLinkAudioToolSearch.find(.ytDlp, isExecutable: only) == nil)
    }

    @Test func onlyTheThreeFoldersAreAsked() {
        var asked: [String] = []
        let found = NookLinkAudioToolSearch.find(.ytDlp) { path in
            asked.append(path)
            return false
        }
        #expect(found == nil)
        #expect(asked == ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/usr/bin/yt-dlp"])
    }

    @Test func theSearchStopsAtTheFirstHit() {
        var asked: [String] = []
        _ = NookLinkAudioToolSearch.find(.ffmpeg) { path in
            asked.append(path)
            return path.hasPrefix("/opt/homebrew")
        }
        #expect(asked == ["/opt/homebrew/bin/ffmpeg"])
    }

    @Test func bothFoundIsReadyAndFfmpegsFolderIsTheOneItWasFoundIn() {
        let status = NookLinkAudioToolSearch.status(
            isExecutable: exists("/usr/local/bin/yt-dlp", "/opt/homebrew/bin/ffmpeg")
        )
        let tools = status.tools
        #expect(tools?.ytDlp.path == "/usr/local/bin/yt-dlp")
        #expect(tools?.ffmpeg.path == "/opt/homebrew/bin/ffmpeg")
        #expect(tools?.ffmpegDirectory.path == "/opt/homebrew/bin")
        #expect(status.missing.isEmpty)
        #expect(status.missingLineKey == nil)
    }

    @Test func aMissingProgramIsNamedAndTheOtherKeepsItsPath() {
        let noYtDlp = NookLinkAudioToolSearch.status(isExecutable: exists("/usr/bin/ffmpeg"))
        #expect(noYtDlp.tools == nil)
        #expect(noYtDlp.missing == [.ytDlp])
        #expect(noYtDlp.path(of: .ffmpeg)?.path == "/usr/bin/ffmpeg")
        #expect(noYtDlp.missingLineKey == "nook.linkAudio.missing.ytDlp")

        let noFfmpeg = NookLinkAudioToolSearch.status(isExecutable: exists("/opt/homebrew/bin/yt-dlp"))
        #expect(noFfmpeg.tools == nil)
        #expect(noFfmpeg.missing == [.ffmpeg])
        #expect(noFfmpeg.missingLineKey == "nook.linkAudio.missing.ffmpeg")

        let neither = NookLinkAudioToolSearch.status(isExecutable: exists())
        #expect(neither.missing == [.ytDlp, .ffmpeg])
        #expect(neither.missingLineKey == "nook.linkAudio.missing.both")
    }

    @Test func theMissingLineNamesTheProgramAndTheBrewCommand() {
        let lang = LanguageManager.shared
        for (key, name) in [
            ("nook.linkAudio.missing.ytDlp", "yt-dlp"),
            ("nook.linkAudio.missing.ffmpeg", "ffmpeg"),
            ("nook.linkAudio.missing.both", "yt-dlp"),
        ] {
            let line = lang.t(key)
            #expect(line.contains(name), "\(key)")
            #expect(line.contains("brew install yt-dlp ffmpeg"), "\(key)")
            #expect(!line.contains("\n"), "one line")
        }
    }

    @Test func theRunPathHoldsTheSearchedFoldersFirst() {
        let parts = NookLinkAudioToolSearch.runPath.split(separator: ":").map(String.init)
        #expect(Array(parts.prefix(3)) == NookLinkAudioToolSearch.directories)
        #expect(parts.contains("/bin"))
    }
}
