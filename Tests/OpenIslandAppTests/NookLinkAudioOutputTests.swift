import Foundation
import Testing
@testable import OpenIslandApp

// Reading yt-dlp's lines: progress, the title, the finished file and its
// errors. A line that is not one of those changes nothing.

@Suite struct NookLinkAudioOutputTests {
    private let progress = NookLinkAudioArguments.progressMarker
    private let title = NookLinkAudioArguments.titleMarker
    private let file = NookLinkAudioArguments.fileMarker

    private func j(_ text: String) -> String { LinkAudioFixture.json(text) }

    // MARK: Progress

    @Test func aDownloadThatIsPartWayHasAFraction() {
        let line = "\(progress) downloading 2500 10000 NA \(j("/music/Song.webm"))"
        #expect(NookLinkAudioOutput.parse(line) == .progress(fraction: 0.25, isDownloadDone: false, fileName: "/music/Song.webm"))
    }

    @Test func theEstimateStandsInWhenTheTotalIsNotKnown() {
        let line = "\(progress) downloading 500 NA 2000.0 \(j("/music/Song.webm"))"
        #expect(NookLinkAudioOutput.parse(line) == .progress(fraction: 0.25, isDownloadDone: false, fileName: "/music/Song.webm"))
    }

    @Test func theTotalIsPreferredOverTheEstimate() {
        let line = "\(progress) downloading 500 1000 4000 \(j("/music/Song.webm"))"
        #expect(NookLinkAudioOutput.parse(line) == .progress(fraction: 0.5, isDownloadDone: false, fileName: "/music/Song.webm"))
    }

    @Test func noSizeAtAllMeansNoFractionYet() {
        let line = "\(progress) downloading 500 NA NA \(j("/music/Song.webm"))"
        #expect(NookLinkAudioOutput.parse(line) == .progress(fraction: nil, isDownloadDone: false, fileName: "/music/Song.webm"))
        let none = "\(progress) downloading NA NA NA NA"
        #expect(NookLinkAudioOutput.parse(none) == .progress(fraction: nil, isDownloadDone: false, fileName: nil))
    }

    @Test func aFractionStaysBetweenZeroAndOne() {
        let over = "\(progress) downloading 5000 1000 NA \(j("/music/a.webm"))"
        #expect(NookLinkAudioOutput.parse(over) == .progress(fraction: 1, isDownloadDone: false, fileName: "/music/a.webm"))
        let zero = "\(progress) downloading 0 1000 NA \(j("/music/a.webm"))"
        #expect(NookLinkAudioOutput.parse(zero) == .progress(fraction: 0, isDownloadDone: false, fileName: "/music/a.webm"))
        let zeroTotal = "\(progress) downloading 10 0 0 \(j("/music/a.webm"))"
        #expect(NookLinkAudioOutput.parse(zeroTotal) == .progress(fraction: nil, isDownloadDone: false, fileName: "/music/a.webm"))
    }

    @Test func theFinishedLineClosesTheDownload() {
        let line = "\(progress) finished 4096 4096 NA \(j("/music/Song.webm"))"
        #expect(NookLinkAudioOutput.parse(line) == .progress(fraction: 1, isDownloadDone: true, fileName: "/music/Song.webm"))
    }

    @Test func aFileNameWithSpacesAndOddCharactersComesBackWhole() {
        let name = "/Users/me/Music/Hangover/Artist - Song (live) [HD]  two  spaces.webm"
        let line = "\(progress) downloading 1 2 NA \(j(name))"
        #expect(NookLinkAudioOutput.parse(line) == .progress(fraction: 0.5, isDownloadDone: false, fileName: name))
        let unicode = "/music/日本語の曲 🎵.m4a"
        #expect(NookLinkAudioOutput.parse("\(progress) downloading 1 4 NA \(j(unicode))") == .progress(fraction: 0.25, isDownloadDone: false, fileName: unicode))
    }

    @Test(arguments: [
        "\(NookLinkAudioArguments.progressMarker)",
        "\(NookLinkAudioArguments.progressMarker) ",
        "\(NookLinkAudioArguments.progressMarker) downloading",
        "\(NookLinkAudioArguments.progressMarker) downloading 1 2",
        "\(NookLinkAudioArguments.progressMarker) error 1 2 NA /music/a.webm",
        "\(NookLinkAudioArguments.progressMarker) started 1 2 NA /music/a.webm",
        "\(NookLinkAudioArguments.progressMarker)downloading 1 2 NA /music/a.webm",
        "[download]  42.0% of 3.00MiB at 1.00MiB/s ETA 00:01",
        "[download] Destination: /music/a.webm",
        "",
        "   ",
    ])
    func aLineThatIsCutShortOrNotOurOwnChangesNothing(_ line: String) {
        #expect(NookLinkAudioOutput.parse(line) == .other)
    }

    @Test func numbersThatAreNotNumbersAreNoFraction() {
        #expect(NookLinkAudioOutput.parse("\(progress) downloading x y z \(j("/a"))") == .progress(fraction: nil, isDownloadDone: false, fileName: "/a"))
        #expect(NookLinkAudioOutput.parse("\(progress) downloading -5 100 NA \(j("/a"))") == .progress(fraction: nil, isDownloadDone: false, fileName: "/a"))
        #expect(NookLinkAudioOutput.parse("\(progress) downloading inf 100 NA \(j("/a"))") == .progress(fraction: nil, isDownloadDone: false, fileName: "/a"))
        #expect(NookLinkAudioOutput.parse("\(progress) downloading nan 100 NA \(j("/a"))") == .progress(fraction: nil, isDownloadDone: false, fileName: "/a"))
    }

    // MARK: Title and file

    @Test func theTitleIsTheJSONStringOnTheLine() {
        #expect(NookLinkAudioOutput.parse("\(title) \(j("Never Gonna Give You Up"))") == .title("Never Gonna Give You Up"))
        #expect(NookLinkAudioOutput.parse("\(title)   \(j("Padded title"))  ") == .title("Padded title"))
        #expect(NookLinkAudioOutput.parse("\(title) \(j("日本語の曲 🎵"))") == .title("日本語の曲 🎵"))
        #expect(NookLinkAudioOutput.parse("\(title) \(j("a hangover-title b"))") == .title("a hangover-title b"))
        // Non-ASCII as yt-dlp writes JSON by default: escapes, a pair of them for an emoji.
        #expect(NookLinkAudioOutput.parse(#"hangover-title "日本 🎵""#) == .title("日本 🎵"))
    }

    @Test func aTitleThatIsNotAJSONStringIsNoTitle() {
        #expect(NookLinkAudioOutput.parse("\(title) NA") == .other)
        #expect(NookLinkAudioOutput.parse("\(title) null") == .other)
        #expect(NookLinkAudioOutput.parse("\(title) 42") == .other)
        #expect(NookLinkAudioOutput.parse("\(title) Never Gonna Give You Up") == .other, "the old raw form is no longer read")
        #expect(NookLinkAudioOutput.parse(#"hangover-title "unfinished"#) == .other)
        #expect(NookLinkAudioOutput.parse("\(title) \(j(""))") == .other)
        #expect(NookLinkAudioOutput.parse("\(title) \(j("   "))") == .other)
        #expect(NookLinkAudioOutput.parse("\(title) ") == .other)
        #expect(NookLinkAudioOutput.parse("\(title)") == .other)
    }

    @Test func aTitleIsOneLineWhateverItHolds() {
        #expect(NookLinkAudioOutput.parse("\(title) \(j("First\nSecond"))") == .title("First Second"))
        #expect(NookLinkAudioOutput.parse("\(title) \(j("A\r\n\tB\u{2028}C"))") == .title("A   B C"))
        #expect(NookLinkAudioOutput.parse("\(title) \(j("\n\n"))") == .other)
    }

    @Test func theFinishedFileIsTheJSONStringOnTheLine() {
        #expect(NookLinkAudioOutput.parse("\(file) \(j("/Users/me/Music/Hangover/Song.mp3"))") == .file("/Users/me/Music/Hangover/Song.mp3"))
        #expect(NookLinkAudioOutput.parse("\(file) \(j("/Users/me/Music/A  B.mp3"))") == .file("/Users/me/Music/A  B.mp3"))
        #expect(NookLinkAudioOutput.parse("\(file) NA") == .other)
        #expect(NookLinkAudioOutput.parse("\(file) null") == .other)
        #expect(NookLinkAudioOutput.parse("\(file) /Users/me/Music/Hangover/Song.mp3") == .other, "the old raw form is no longer read")
        #expect(NookLinkAudioOutput.parse("\(file) \(j(""))") == .other)
        #expect(NookLinkAudioOutput.parse("\(file) ") == .other)
    }

    @Test func aLineEndingCarriesNoWeight() {
        #expect(NookLinkAudioOutput.parse("\(title) \(j("Song"))\r\n") == .title("Song"))
        #expect(NookLinkAudioOutput.parse("\(file) \(j("/a/b.mp3"))\r") == .file("/a/b.mp3"))
    }

    // MARK: A title written to forge a line

    /// What a site's title does to the output: the line `yt-dlp` prints for it, cut into lines the way the runner cuts them, and each read.
    private func lines(printing text: String, as marker: String, chunk: Int? = nil) -> [NookLinkAudioLine] {
        var buffer = NookLinkAudioLineBuffer()
        let data = Data("\(marker) \(j(text))\n".utf8)
        var cut: [String] = []
        if let chunk {
            var at = 0
            while at < data.count {
                cut += buffer.append(data[at..<min(at + chunk, data.count)])
                at += chunk
            }
        } else {
            cut = buffer.append(data)
        }
        cut += buffer.flush().map { [$0] } ?? []
        return cut.map(NookLinkAudioOutput.parse)
    }

    @Test func aNewlineInATitleCannotStartALineOfItsOwn() {
        let forged = "Song\n\(file) \(j("/System/Applications/Calculator.app"))\n\(progress) finished 1 1 NA \(j("/x"))"
        let parsed = lines(printing: forged, as: title)
        #expect(parsed.count == 1, "one line for one title")
        #expect(parsed == [.title("Song \(file) \(j("/System/Applications/Calculator.app")) \(progress) finished 1 1 NA \(j("/x"))")])
    }

    @Test func aCarriageReturnInATitleCannotEndTheLineEither() {
        let parsed = lines(printing: "Song\r\(file) \(j("/System/Applications/Calculator.app"))", as: title)
        #expect(parsed.count == 1)
        guard case .title = parsed[0] else { Issue.record("not a title: \(parsed[0])"); return }
    }

    @Test func aTitleOfFillerLongerThanALineIsDroppedAndNothingOfItBecomesALine() {
        let marker = "\(title) \"".utf8.count
        // The filler runs to the byte where the limit would have cut the line, and the forged line follows.
        let forged = "\(file) \(j("/System/Applications/Calculator.app"))"
        for fill in [NookLinkAudioLineBuffer.maxLineBytes - marker, NookLinkAudioLineBuffer.maxLineBytes, NookLinkAudioLineBuffer.maxLineBytes * 2] {
            let text = String(repeating: "a", count: fill) + forged
            for chunk in [nil, 4_096, 1] as [Int?] {
                let parsed = lines(printing: text, as: title, chunk: chunk)
                #expect(parsed.isEmpty, "fill \(fill), chunk \(String(describing: chunk)): \(parsed)")
            }
        }
    }

    @Test func aFileNameInAProgressLineIsOneLineToo() {
        var buffer = NookLinkAudioLineBuffer()
        let name = "/Users/me/Music/Hangover/a\n\(file) \(j("/System/Applications/Calculator.app"))\nb.webm"
        let parsed = buffer.append(Data("\(progress) downloading 1 2 NA \(j(name))\n".utf8)).map(NookLinkAudioOutput.parse)
        #expect(parsed == [.progress(fraction: 0.5, isDownloadDone: false, fileName: name)])
    }

    @Test func aLineThatWasNotJSONIsNotReadAsAFile() {
        // What the old raw form would have let through when a title held a newline.
        #expect(NookLinkAudioOutput.parse("\(file) /System/Applications/Calculator.app") == .other)
        #expect(NookLinkAudioOutput.parse("\(file) \"/System/Applications/Calculator.app") == .other)
    }

    // MARK: Errors

    @Test func anErrorLineIsKeptWithoutItsMark() {
        #expect(NookLinkAudioOutput.parse("ERROR: [youtube] abc: Video unavailable") == .error("[youtube] abc: Video unavailable"))
        #expect(NookLinkAudioOutput.parse("ERROR:   spaced") == .error("spaced"))
        #expect(NookLinkAudioOutput.parse("ERROR:") == .other)
        #expect(NookLinkAudioOutput.parse("WARNING: something") == .other)
    }

    @Test(arguments: [
        ("ERROR: Unsupported URL: https://example.com/x", NookLinkAudioFailure.unsupportedSite),
        ("[youtube] abc: Video unavailable", .unavailable),
        ("[youtube] abc: Private video. Sign in if you've been granted access", .needsAccount),
        ("Sign in to confirm you're not a bot", .needsAccount),
        ("This video is only available for registered users", .needsAccount),
        ("Join this channel to get access to members-only content", .needsAccount),
        ("Sign in to confirm your age", .needsAccount),
        ("The uploader has not made this video available in your country", .notInYourCountry),
        ("Unable to download webpage: HTTP Error 404: Not Found", .unavailable),
        ("Unable to download webpage: <urlopen error [Errno 8] nodename nor servname provided, or not known>", .offline),
        ("Unable to download webpage: <urlopen error [Errno 60] Operation timed out>", .offline),
        ("HTTP Error 429: Too Many Requests", .blocked),
        ("unable to download video data: HTTP Error 403: Forbidden", .blocked),
        ("ffprobe and ffmpeg not found. Please install or provide the path using --ffmpeg-location", .ffmpeg),
        ("Postprocessing: ffmpeg exited with code 1", .ffmpeg),
        ("This video is DRM protected", .drm),
        ("[Errno 28] No space left on device", .diskFull),
        ("unable to open for writing: [Errno 13] Permission denied: '/x/y.webm.part'", .cannotWrite),
        ("unable to open for writing: [Errno 63] File name too long", .nameTooLong),
        ("Something nobody planned for", .other),
        ("", .other),
    ])
    func anErrorLineBecomesAReasonInPlainWords(_ line: String, _ expected: NookLinkAudioFailure) {
        #expect(NookLinkAudioFailure.reason(forErrorLine: line) == expected)
    }

    @Test func noLineIsOther() {
        #expect(NookLinkAudioFailure.reason(forErrorLine: nil) == .other)
    }

    @Test func everyReasonHasItsOwnPlainLineInEveryLanguage() throws {
        let all: [NookLinkAudioFailure] = [
            .couldNotStart, .couldNotMakeFolder, .folderHasDollar, .unsupportedSite, .unavailable, .needsAccount, .notInYourCountry,
            .offline, .blocked, .drm, .ffmpeg, .diskFull, .cannotWrite, .nameTooLong, .other,
        ]
        #expect(Set(all.map(\.messageKey)).count == all.count)
        for failure in all {
            let line = LanguageManager.shared.t(failure.messageKey)
            #expect(line != failure.messageKey)
            #expect(!line.isEmpty)
        }
    }
}

// MARK: - The line buffer

@Suite struct NookLinkAudioLineBufferTests {
    private func data(_ text: String) -> Data { Data(text.utf8) }

    @Test func wholeLinesComeOutAtOnce() {
        var buffer = NookLinkAudioLineBuffer()
        #expect(buffer.append(data("one\ntwo\nthree\n")) == ["one", "two", "three"])
        #expect(buffer.flush() == nil)
    }

    @Test func aLineCutBetweenChunksIsJoined() {
        var buffer = NookLinkAudioLineBuffer()
        #expect(buffer.append(data("hang")) == [])
        #expect(buffer.append(data("over-title Son")) == [])
        #expect(buffer.append(data("g\nnext")) == ["hangover-title Song"])
        #expect(buffer.flush() == "next")
        #expect(buffer.flush() == nil)
    }

    @Test func aCarriageReturnEndsALineToo() {
        var buffer = NookLinkAudioLineBuffer()
        #expect(buffer.append(data("10%\r20%\r30%\r\nend\n")) == ["10%", "20%", "30%", "end"])
    }

    @Test func blankLinesAreLeftOut() {
        var buffer = NookLinkAudioLineBuffer()
        #expect(buffer.append(data("\n\none\n\n\ntwo\n")) == ["one", "two"])
    }

    @Test func aCharacterCutInTwoByTheChunkComesOutWhole() {
        var buffer = NookLinkAudioLineBuffer()
        let bytes = Array("日本語\n".utf8)
        #expect(buffer.append(Data(bytes[0..<4])) == [])
        #expect(buffer.append(Data(bytes[4...])) == ["日本語"])
    }

    @Test func aLineExactlyAtTheLimitIsKept() {
        var buffer = NookLinkAudioLineBuffer()
        let line = String(repeating: "a", count: NookLinkAudioLineBuffer.maxLineBytes)
        #expect(buffer.append(data(line + "\n")) == [line])
    }

    @Test func aLineOverTheLimitIsDroppedWholeAndTheNextLineIsRead() {
        var buffer = NookLinkAudioLineBuffer()
        let long = String(repeating: "a", count: NookLinkAudioLineBuffer.maxLineBytes * 2 + 10)
        #expect(buffer.append(data(long)) == [])
        #expect(buffer.append(data(long)) == [], "still the same line")
        #expect(buffer.append(data("tail\nnext\n")) == ["next"], "the rest of the long line goes with it")
        #expect(buffer.flush() == nil)
    }

    @Test func aLongLineEndingInACarriageReturnEndsTheSkipToo() {
        var buffer = NookLinkAudioLineBuffer()
        let long = String(repeating: "a", count: NookLinkAudioLineBuffer.maxLineBytes + 1)
        #expect(buffer.append(data(long + "\r\nnext\n")) == ["next"])
    }

    @Test func aLongLineThatNeverEndsLeavesNothingBehind() {
        var buffer = NookLinkAudioLineBuffer()
        _ = buffer.append(data(String(repeating: "a", count: NookLinkAudioLineBuffer.maxLineBytes + 5)))
        #expect(buffer.flush() == nil)
        #expect(buffer.append(data("fresh\n")) == ["fresh"])
    }

    @Test func bytesThatAreNotUTF8DoNotStopTheStream() {
        var buffer = NookLinkAudioLineBuffer()
        let lines = buffer.append(Data([0x61, 0xFF, 0x62, 0x0A, 0x63, 0x0A]))
        #expect(lines.count == 2)
        #expect(lines[1] == "c")
        #expect(lines[0].hasPrefix("a") && lines[0].hasSuffix("b"))
    }
}
