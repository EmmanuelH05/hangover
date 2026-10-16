import Foundation
import Testing
@testable import OpenIslandApp

/// The words the tray fixes added: each exists in every language, the
/// English ones say what the fix list asked them to, and none has a dash or
/// the word "so".
@Suite struct NookTrayFixesStringsTests {
    private static let languages = ["en", "zh-Hans", "zh-Hant"]

    private static let newKeys = [
        "nook.tray.convert.notice.alreadySmall",
        "nook.tray.convert.notice.gifDecodeFailed",
        "nook.tray.notice.recordingNotAdded",
        "nook.tray.convert.wait",
        "nook.tray.recording.smaller",
        "nook.tray.recording.showInFinder",
    ]

    private static func table(_ language: String) throws -> [String: String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
        return try #require(NSDictionary(contentsOf: url) as? [String: String], "\(language) did not load")
    }

    @Test(arguments: languages)
    func everyNewStringExistsAndHasNoDash(language: String) throws {
        let table = try Self.table(language)
        for key in Self.newKeys {
            let value = table[key] ?? ""
            #expect(!value.isEmpty, "\(language) is missing \(key)")
            #expect(!value.contains("\u{2014}") && !value.contains("\u{2013}"), "\(language) \(key) has a dash")
        }
    }

    @Test func theEnglishSentencesAreTheOnesTheFixListAsksFor() throws {
        let table = try Self.table("en")
        #expect(table["nook.tray.convert.notice.alreadySmall"] == "That file is already about as small as it gets.")
        #expect(table["nook.tray.notice.recordingNotAdded"] == "Recording saved to Movies/Hangover, but it could not be added to the tray.")
        #expect(table["nook.tray.convert.wait"] == "Wait for the conversion on %@ to finish")
        #expect(table["nook.tray.recording.showInFinder"] == "Show in Finder")
    }

    @Test func noEnglishLineUsesTheWordSo() throws {
        let table = try Self.table("en")
        for key in Self.newKeys {
            let words = (table[key] ?? "").lowercased().split(whereSeparator: { !$0.isLetter })
            #expect(!words.contains("so"), "\(key) uses the word so")
        }
    }

    @Test func theGIFSentenceSaysPartOfTheVideoCouldNotBeRead() throws {
        let text = try #require(Self.table("en")["nook.tray.convert.notice.gifDecodeFailed"])
        #expect(text.hasPrefix("Part of that video could not be read"))
        #expect(text.contains("no GIF was made"))
    }

    @Test func theWaitSentenceTakesOneName() throws {
        for language in Self.languages {
            let text = try #require(Self.table(language)["nook.tray.convert.wait"])
            #expect(text.components(separatedBy: "%@").count == 2, "\(language) must have exactly one %@")
        }
    }

    @Test func theNewKeysSitInOneBlockAtTheEndOfEveryFile() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for language in Self.languages {
            let url = root.appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
            let text = try String(contentsOf: url, encoding: .utf8)
            let marker = try #require(text.range(of: "/* Tray fixes (D68) */"), "\(language) has no Tray fixes block")
            let block = text[marker.upperBound...]
            for key in Self.newKeys {
                #expect(block.contains("\"\(key)\""), "\(language) has \(key) outside the block")
            }
        }
    }
}
