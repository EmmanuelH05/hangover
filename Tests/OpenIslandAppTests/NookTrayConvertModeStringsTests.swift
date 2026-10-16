import Foundation
import Testing
@testable import OpenIslandApp

/// The words of the tray's Convert mode: every key exists in all three
/// languages, the keys sit in one block just before the Notes blocks (which
/// have to stay last), and no line has a dash or the word "so".
@Suite struct NookTrayConvertModeStringsTests {
    private static let languages = ["en", "zh-Hans", "zh-Hant"]
    private static let marker = "/* Tray Convert mode */"
    private static let notesMarker = "/* Notes redesign (D70) */"

    private static let newKeys = [
        "nook.tray.convert.chip",
        "nook.tray.convert.chip.picking",
        "nook.tray.convert.strip.title",
        "nook.tray.convert.strip.explain",
    ]

    private static func url(_ language: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
    }

    private static func table(_ language: String) throws -> [String: String] {
        try #require(NSDictionary(contentsOf: url(language)) as? [String: String], "\(language) did not load")
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
    }

    @Test(arguments: languages)
    func everyNewKeyExistsAndHasNoDash(language: String) throws {
        let table = try Self.table(language)
        for key in Self.newKeys {
            let value = table[key] ?? ""
            #expect(!value.isEmpty, "\(language) is missing \(key)")
            #expect(!value.contains("\u{2014}") && !value.contains("\u{2013}"), "\(language) \(key) has a dash")
        }
    }

    @Test func noEnglishLineUsesTheWordSo() throws {
        let table = try Self.table("en")
        for key in Self.newKeys + ["onboarding.more.convert.text"] {
            #expect(!Self.words(table[key] ?? "").contains("so"), "\(key) uses the word so")
        }
    }

    @Test(arguments: languages)
    func theBlockHoldsExactlyTheNewKeysAndSitsRightBeforeTheNotesBlock(language: String) throws {
        let text = try String(contentsOf: Self.url(language), encoding: .utf8)
        let start = try #require(text.range(of: Self.marker), "\(language) has no \(Self.marker) block")
        let notes = try #require(text.range(of: Self.notesMarker), "\(language) lost the Notes block")
        #expect(start.upperBound <= notes.lowerBound, "\(language): the Convert block must come before the Notes blocks")
        let block = text[start.upperBound..<notes.lowerBound]
        #expect(!block.contains("/*"), "\(language): another block sits between them")
        let keys = block.split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix("\"") else { return nil }
            return line.dropFirst().prefix(while: { $0 != "\"" }).description
        }
        #expect(keys == Self.newKeys)
    }

    @Test(arguments: languages)
    func theStripTitleTakesTheFileName(language: String) throws {
        let title = try #require(Self.table(language)["nook.tray.convert.strip.title"])
        #expect(title.contains("%@"))
        #expect(LanguageManager.shared.t("nook.tray.convert.strip.title", "photo.png").contains("photo.png"))
    }

    @Test func theEnglishLinesAreTheOnesTheDesignAsksFor() throws {
        let table = try Self.table("en")
        #expect(table["nook.tray.convert.chip"] == "Convert")
        #expect(table["nook.tray.convert.chip.picking"] == "Pick a file")
        #expect(table["nook.tray.convert.strip.title"] == "Convert %@")
        #expect(table["nook.tray.convert.strip.explain"]
            == "Pick what it should become. The new file appears in the tray next to it.")
    }

    // MARK: The tour tip

    @Test func theTourTipSaysToPressConvertNextToFilesAndClickAFile() throws {
        let english = try #require(Self.table("en")["onboarding.more.convert.text"])
        for phrase in ["Press Convert next to Files", "click a file", "looping GIF", "Command-click", "one PDF"] {
            #expect(english.contains(phrase), "en: the tip should say \(phrase)")
        }
        #expect(!english.contains("Convert menu"), "the right click menu is no longer the way in")

        let hans = try #require(Self.table("zh-Hans")["onboarding.more.convert.text"])
        for phrase in ["「文件」旁", "「转换」", "点一个文件", "GIF", "Command", "PDF"] {
            #expect(hans.contains(phrase), "zh-Hans: the tip should say \(phrase)")
        }

        let hant = try #require(Self.table("zh-Hant")["onboarding.more.convert.text"])
        for phrase in ["「檔案」旁", "「轉換」", "點一個檔案", "GIF", "Command", "PDF"] {
            #expect(hant.contains(phrase), "zh-Hant: the tip should say \(phrase)")
        }
    }

    /// How long each line was before it was reworded.
    private static let tourTipLengthBefore = ["en": 289, "zh-Hans": 122, "zh-Hant": 122]

    @Test(arguments: languages)
    func theTourTipIsAboutAsLongAsItWas(language: String) throws {
        let text = try #require(Self.table(language)["onboarding.more.convert.text"])
        let before = try #require(Self.tourTipLengthBefore[language])
        #expect(text.count >= before * 85 / 100 && text.count <= before * 115 / 100,
                "\(language): \(text.count) characters, it was \(before)")
    }

    @Test func theChineseLinesCallTheTrayWhatTheTrayStringsCallIt() throws {
        #expect(try Self.table("zh-Hans")["nook.tray.convert.strip.explain"]?.contains("托盘") == true)
        #expect(try Self.table("zh-Hant")["nook.tray.convert.strip.explain"]?.contains("托盤") == true)
    }
}
