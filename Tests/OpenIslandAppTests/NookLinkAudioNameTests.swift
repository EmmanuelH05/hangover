import Foundation
import Testing
@testable import OpenIslandApp

// The file name a download gets once its key and tempo are known, and the
// words the finished row shows for them.

@Suite struct NookLinkAudioNameTests {
    private func found<Value>(_ value: Value, guess: Bool = false) -> NookLinkAudioFound<Value> {
        NookLinkAudioFound(value: value, isGuess: guess)
    }

    private let cSharpMinor = NookMusicalKey(tonic: 1, mode: .minor)

    private func findings(key: Bool = true, bpm: Bool = true, guessKey: Bool = false, guessBPM: Bool = false) -> NookLinkAudioFindings {
        NookLinkAudioFindings(
            key: key ? found(cSharpMinor, guess: guessKey) : nil,
            bpm: bpm ? found(127, guess: guessBPM) : nil
        )
    }

    // MARK: The tag

    @Test func keyAndTempoGoInOneBracketKeyFirst() {
        #expect(findings().fileNameTag == "C# minor, 127 BPM")
    }

    @Test func aGuessGetsATildeAndAWrittenValueDoesNot() {
        #expect(findings(guessKey: true, guessBPM: true).fileNameTag == "~C# minor, ~127 BPM")
        #expect(findings(guessKey: false, guessBPM: true).fileNameTag == "C# minor, ~127 BPM")
        #expect(findings(guessKey: true, guessBPM: false).fileNameTag == "~C# minor, 127 BPM")
    }

    @Test func oneOfTheTwoIsEnough() {
        #expect(findings(bpm: false).fileNameTag == "C# minor")
        #expect(findings(key: false).fileNameTag == "127 BPM")
        #expect(findings(key: false, bpm: false).fileNameTag == nil)
        #expect(findings(key: false, bpm: false).isEmpty)
        #expect(!findings(bpm: false).isEmpty)
    }

    @Test func theTagIsEnglishWhateverTheLanguageOfTheApp() {
        // The same song fetched twice must get the same name. The row speaks
        // the app's language and the file does not.
        let tag = findings().fileNameTag ?? ""
        #expect(tag.allSatisfy { $0.isASCII })
        #expect(NookMusicalKey(tonic: 3, mode: .major).englishName == "Eb major")
    }

    // MARK: The new name

    @Test func theTagGoesBeforeTheIdThatYtDlpPutsLast() {
        #expect(NookLinkAudioName.renamed("Wake Up [abc123].mp3", with: findings()) == "Wake Up [C# minor, 127 BPM] [abc123].mp3")
        #expect(NookLinkAudioName.renamed("Wake Up [abc123].mp3", with: findings(bpm: false)) == "Wake Up [C# minor] [abc123].mp3")
        #expect(NookLinkAudioName.renamed("Wake Up [abc123].mp3", with: findings(key: false)) == "Wake Up [127 BPM] [abc123].mp3")
        #expect(NookLinkAudioName.renamed("Wake Up [abc123].mp3", with: findings(guessKey: true, guessBPM: true)) == "Wake Up [~C# minor, ~127 BPM] [abc123].mp3")
    }

    @Test func nothingFoundIsNoNewName() {
        #expect(NookLinkAudioName.renamed("Wake Up [abc123].mp3", with: NookLinkAudioFindings()) == nil)
    }

    @Test func aTitleWithBracketsOfItsOwnKeepsThem() {
        #expect(
            NookLinkAudioName.renamed("[FREE] Drake Type Beat [Official Video] [x9_-Y].mp3", with: findings())
                == "[FREE] Drake Type Beat [Official Video] [C# minor, 127 BPM] [x9_-Y].mp3"
        )
    }

    @Test func aNameWithoutAnIdGetsTheTagBeforeTheExtension() {
        #expect(NookLinkAudioName.renamed("Song.mp3", with: findings()) == "Song [C# minor, 127 BPM].mp3")
        #expect(NookLinkAudioName.renamed("Song", with: findings()) == "Song [C# minor, 127 BPM]")
    }

    @Test func aTitleWithDotsAndNonLatinLettersIsKept() {
        #expect(NookLinkAudioName.renamed("Song v2.0 [id].mp3", with: findings()) == "Song v2.0 [C# minor, 127 BPM] [id].mp3")
        #expect(NookLinkAudioName.renamed("日本語の曲 🎵 [id].mp3", with: findings()) == "日本語の曲 🎵 [C# minor, 127 BPM] [id].mp3")
    }

    @Test func aNameThatAlreadyHasTheTagIsLeftAlone() {
        #expect(NookLinkAudioName.renamed("Wake Up [C# minor, 127 BPM] [abc123].mp3", with: findings()) == nil)
    }

    @Test func aNameThatWouldBeTooLongForTheDiskIsLeftAlone() {
        let long = String(repeating: "a", count: 230)
        #expect(NookLinkAudioName.renamed("\(long) [id].mp3", with: findings()) == nil)
        let fits = String(repeating: "a", count: 150)
        #expect(NookLinkAudioName.renamed("\(fits) [id].mp3", with: findings()) != nil)
    }

    @Test func aFileStaysInItsFolder() {
        let file = URL(fileURLWithPath: "/Users/tester/Music/Hangover/Wake Up [abc123].mp3")
        let renamed = NookLinkAudioName.renamed(file, with: findings())
        #expect(renamed?.path == "/Users/tester/Music/Hangover/Wake Up [C# minor, 127 BPM] [abc123].mp3")
        #expect(NookLinkAudioName.renamed(file, with: NookLinkAudioFindings()) == nil)
    }

    @Test func theNewNameHasNoSlashAndNoColon() throws {
        for key in NookMusicalKey.all {
            let name = try #require(NookLinkAudioName.renamed("Song [id].mp3", with: NookLinkAudioFindings(key: found(key, guess: true), bpm: found(90))))
            #expect(!name.dropLast(4).contains("/") && !name.contains(":"), "\(name)")
        }
    }

    // MARK: The row

    @Test func theRowShowsTheKeyInTheAppsWordsAndAGuessWithATilde() {
        let text = findings(guessKey: true, guessBPM: true).shownText ?? ""
        #expect(text.hasPrefix("~"))
        #expect(text.contains("C#"))
        #expect(text.hasSuffix(", ~127 BPM"))
        let exact = findings().shownText ?? ""
        #expect(!exact.contains("~"))
        #expect(exact.hasSuffix(", 127 BPM"))
        #expect(findings(key: false, bpm: false).shownText == nil)
    }

    @Test func aGuessIsSaidToBeOneForVoiceOver() throws {
        let spoken = try #require(findings(guessKey: true, guessBPM: true).spokenText)
        #expect(!spoken.contains("~"))
        let plain = try #require(findings().spokenText)
        #expect(!plain.contains("~"))
        #expect(spoken != plain)
        #expect(findings(key: false, bpm: false).spokenText == nil)
    }

    @Test func everyKeyHasAWordInEveryLanguageAndTheNoteStaysALetter() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let url = root.appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
            let major = try #require(table["nook.linkAudio.key.major"])
            let minor = try #require(table["nook.linkAudio.key.minor"])
            #expect(major.contains("%@") && minor.contains("%@"), "\(language)")
            #expect(major != minor, "\(language)")
            for name in NookMusicalKey.noteNames {
                #expect(String(format: major, name).contains(name) && String(format: minor, name).contains(name))
            }
        }
    }
}
