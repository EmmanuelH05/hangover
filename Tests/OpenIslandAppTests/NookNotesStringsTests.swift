import Foundation
import Testing
@testable import OpenIslandApp

/// The words of the notes redesign (D70): every key exists in all three
/// languages, the new ones sit in one block at the end of each file, and the
/// English lines have no dash and never the word "so".
@Suite struct NookNotesStringsTests {
    private static let languages = ["en", "zh-Hans", "zh-Hant"]
    private static let marker = "/* Notes redesign (D70) */"
    private static let fixesMarker = "/* Notes fixes (D70) */"

    /// The keys a block added: from its marker to the next block, or the end
    /// of the file.
    private static func blockKeys(_ language: String, marker: String = marker) throws -> [String] {
        let text = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
        let start = try #require(text.range(of: marker), "\(language) has no \(marker) block")
        let rest = text[start.upperBound...]
        let block = rest.range(of: "/*").map { rest[..<$0.lowerBound] } ?? rest
        return block
            .split(separator: "\n")
            .compactMap { line -> String? in
                guard line.hasPrefix("\"") else { return nil }
                return line.dropFirst().prefix(while: { $0 != "\"" }).description
            }
    }

    /// Existing keys the redesign reworded in place.
    private static let rewordedKeys = [
        "onboarding.widgets.notes", "onboarding.notes.title", "onboarding.notes.body", "onboarding.notes.note",
        "onboarding.notes.folder.title", "onboarding.notes.folder.text",
        "onboarding.notes.appleNotes.title", "onboarding.notes.appleNotes.text",
        "onboarding.notes.both.title", "onboarding.notes.both.text",
        "onboarding.notes.folder.where", "onboarding.notes.folder.choose", "onboarding.notes.folder.panelPrompt",
        "onboarding.notes.folder.any", "onboarding.notes.appleNotes.where", "onboarding.notes.appleNotes.ask",
        "onboarding.notes.try", "onboarding.notes.try.done", "onboarding.notes.show.folder",
        "onboarding.notes.show.appleNotes", "onboarding.tips.quickNotes.text", "onboarding.done.recap.notes",
        "onboarding.feature.notesAdd", "onboarding.feature.notesRecent", "onboarding.feature.notesDelete",
        "onboarding.feature.notesWhere", "onboarding.integrations.appleNotes.text",
    ]

    /// Keys that were renamed, so the old ones must be gone.
    private static let removedKeys = [
        "onboarding.notes.file.title", "onboarding.notes.file.text", "onboarding.notes.file.where",
        "onboarding.notes.file.choose", "onboarding.notes.file.panelPrompt", "onboarding.notes.file.any",
        "onboarding.notes.show.file",
    ]

    /// The keys the fixes added (Notes fixes (D70)), which sit in a block of their own.
    private static var fixWords: [String] {
        var keys = [
            "nook.notes.action.chooseFolder", "nook.notes.row.unreadable", "nook.notes.action.openAutomation",
            NookNoteListRules.EmptyLine.settings.key, "nook.notes.row.downloading",
        ]
            + NookNotesNotice.Action.allCases.map(\.titleKey)
        keys += allNotices.flatMap { [$0.textKey, $0.problemKey] }
        var seen = Set<String>()
        return keys.filter { !redesignNoticeKeys.contains($0) && seen.insert($0).inserted }
    }

    /// The notice texts the redesign block holds, reworded in place to a few words.
    private static let redesignNoticeKeys: Set<String> = [
        "nook.notes.notice.notSaved", "nook.notes.notice.notDeleted", "nook.notes.notice.notImported",
        "nook.notes.notice.appleOff.folder", "nook.notes.notice.appleOff.hangover",
        "nook.notes.notice.appleFailed.folder", "nook.notes.notice.appleFailed.hangover",
    ]

    /// One of each kind of notice.
    private static let allNotices: [NookNotesNotice] = [
        .notSaved, .notSavedInFolder("Notes"), .notDeleted, .notImported, .restored,
        .appleNotesOff(keptIn: .folder), .appleNotesOff(keptIn: .hangover),
        .appleNotesFailed(keptIn: .folder), .appleNotesFailed(keptIn: .hangover),
        .appleNotesListSetAside("apple-notes.unreadable-1.json"), .appleNotesListUnreadable,
        .savedAsCopy("Plan (Hangover).md"), .noteUnreadable("Plan"), .noteDownloading("Plan"),
        .cantReadFolder("Notes"), .folderGone("Notes"),
    ]

    private static var wordsInUse: [String] {
        var keys = [
            "nook.notes.title", "nook.notes.new", "nook.notes.new.help", "nook.notes.done", "nook.notes.done.help",
            "nook.notes.delete", "nook.notes.untitled", "nook.notes.empty", "nook.notes.row.hint",
            "nook.notes.editor.placeholder", "nook.notes.editor.label",
            "nook.notes.age.now", "nook.notes.age.minutes", "nook.notes.age.hours",
            "nook.notes.settings.section", "nook.notes.settings.saveTo", "nook.notes.settings.folder",
            "nook.notes.settings.chooseFolder", "nook.notes.settings.chooseFolder.prompt",
            "nook.notes.settings.reveal", "nook.notes.settings.openNotes",
            "nook.notes.settings.hotkey", "nook.notes.settings.hotkey.note", "nook.notes.settings.hotkey.reset",
            "nook.notes.settings.hotkey.problem.taken", "onboarding.feature.notesShortcut",
        ]
        keys += NookNotesSaveTo.allCases.flatMap {
            [NookNotesSettings.titleKey(for: $0), NookNotesSettings.noteKey(for: $0)]
        }
        keys += ["folder", "appleNotes", "both"].map { "nook.notes.savesTo.\($0)" }
        keys += redesignNoticeKeys.sorted()
        keys += NookNotesSaveTo.allCases.flatMap {
            [OnboardingNotesGuide.titleKey(for: $0), OnboardingNotesGuide.textKey(for: $0), OnboardingNotesGuide.showKey(for: $0)]
        }
        return keys
    }

    @Test(arguments: languages)
    func everyKeyTheNotesUseExistsAndIsNotEmpty(language: String) throws {
        let table = try HangoverBrandTests.table(language)
        for key in Self.wordsInUse + Self.rewordedKeys + Self.fixWords {
            #expect(!(table[key] ?? "").isEmpty, "\(language) is missing \(key)")
        }
    }

    @Test(arguments: languages)
    func theKeysThatWereRenamedAreGone(language: String) throws {
        let table = try HangoverBrandTests.table(language)
        for key in Self.removedKeys {
            #expect(table[key] == nil, "\(language) still has \(key)")
        }
    }

    @Test(arguments: languages)
    func theNewKeysSitInBlocksAtTheEndOfTheFile(language: String) throws {
        // The redesign block holds the keys the redesign added.
        let inBlock = Set(try Self.blockKeys(language))
        let wanted = Set(Self.wordsInUse).subtracting(Self.rewordedKeys)
        #expect(wanted.subtracting(inBlock).isEmpty, "\(language) block misses \(wanted.subtracting(inBlock).sorted())")
        #expect(inBlock.subtracting(wanted).isEmpty, "\(language) block holds \(inBlock.subtracting(wanted).sorted())")
        // The fixes have a block of their own, and it holds only theirs.
        let inFixes = Set(try Self.blockKeys(language, marker: Self.fixesMarker))
        let wantedFixes = Set(Self.fixWords)
        #expect(wantedFixes.subtracting(inFixes).isEmpty, "\(language) fixes block misses \(wantedFixes.subtracting(inFixes).sorted())")
        #expect(inFixes.subtracting(wantedFixes).isEmpty, "\(language) fixes block holds \(inFixes.subtracting(wantedFixes).sorted())")
        // Each block is written once.
        let text = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
        #expect(text.components(separatedBy: Self.marker).count == 2)
        #expect(text.components(separatedBy: Self.fixesMarker).count == 2)
    }

    @Test func theThreeLanguagesHoldTheSameBlocks() throws {
        for marker in [Self.marker, Self.fixesMarker] {
            let english = try Self.blockKeys("en", marker: marker)
            for language in ["zh-Hans", "zh-Hant"] {
                #expect(try Self.blockKeys(language, marker: marker) == english, "\(language) block differs from English")
            }
        }
    }

    @Test(arguments: languages)
    func theNewEnglishLinesHaveNoDashAndNoSo(language: String) throws {
        // Only English is held to the rule about dashes and "so".
        guard language == "en" else { return }
        let table = try HangoverBrandTests.table(language)
        for key in Set(Self.wordsInUse + Self.rewordedKeys + Self.fixWords) {
            let value = table[key] ?? ""
            #expect(!value.contains("\u{2014}") && !value.contains("\u{2013}"), "\(key) has a dash")
            let words = value.lowercased().split(whereSeparator: { !$0.isLetter })
            #expect(!words.contains("so"), "\(key) uses the word so")
        }
    }

    @Test(arguments: languages)
    func theLinesWithPlaceholdersTakeTheRightNumberOfThem(language: String) throws {
        let table = try HangoverBrandTests.table(language)
        func count(_ key: String, _ token: String) -> Int {
            (table[key] ?? "").components(separatedBy: token).count - 1
        }
        #expect(count("nook.notes.age.minutes", "%lld") == 1)
        #expect(count("nook.notes.age.hours", "%lld") == 1)
        #expect(count("nook.notes.savesTo.folder", "%@") == 1)
        #expect(count("nook.notes.savesTo.both", "%@") == 1)
        #expect(count("nook.notes.savesTo.appleNotes", "%@") == 0)
        #expect(count("nook.notes.empty", "%@") == 1)
        #expect(count("nook.notes.empty.settings", "%@") == 0)
        #expect(count("onboarding.notes.appleNotes.where", "%@") == 1)
        // A sentence has a place for what it is about only when it has something to say about.
        for notice in Self.allNotices {
            #expect(count(notice.problemKey, "%@") == (notice.subject == nil ? 0 : 1), "\(notice.problemKey)")
        }
    }

    /// N19: "do not come back" understated it. An edit made in Apple Notes is
    /// also replaced by the next edit made in Hangover.
    @Test func theSettingsSayAnEditMadeInAppleNotesIsReplaced() throws {
        let table = try HangoverBrandTests.table("en")
        let rule = "Edits made in Apple Notes do not come back, and are replaced the next time you edit that note in Hangover."
        #expect(try #require(table["nook.notes.settings.appleNotes.note"]).contains(rule))
        #expect(try #require(table["nook.notes.settings.both.note"]).contains(rule))
        #expect(try #require(table["onboarding.notes.appleNotes.where"]).contains(rule))
        #expect(try #require(table["nook.notes.settings.appleNotes.note"]).contains("Hangover folder"))
        for language in ["zh-Hans", "zh-Hant"] {
            let words = try HangoverBrandTests.table(language)
            for key in ["nook.notes.settings.appleNotes.note", "nook.notes.settings.both.note", "onboarding.notes.appleNotes.where"] {
                let text = try #require(words[key])
                #expect(text.contains("覆盖") || text.contains("覆蓋"), "\(language) \(key) does not say the edit is replaced")
            }
        }
    }

    /// The closed island's wing holds about 18 characters. The whole sentence
    /// is for the editor's header and the card.
    @Test func theClosedIslandNoticesAreAFewWords() throws {
        let table = try HangoverBrandTests.table("en")
        for notice in Self.allNotices {
            let text = try #require(table[notice.textKey])
            #expect(text.count <= 18, "\(notice.textKey) is \(text.count) characters")
            let sentence = try #require(table[notice.problemKey])
            #expect(sentence.count > text.count, "\(notice.problemKey) is not the longer text")
        }
    }

    @Test func theEnglishAgesAreShortAndLowerCase() throws {
        let table = try HangoverBrandTests.table("en")
        #expect(table["nook.notes.age.minutes"] == "%lldm ago")
        #expect(table["nook.notes.age.hours"] == "%lldh ago")
        #expect(table["nook.notes.age.now"] == "now")
    }

    /// Every localized key the notes sources ask for exists. Keys that are
    /// settings, not words, are left out.
    @Test func everyKeyTheNotesSourcesAskForIsInTheStrings() throws {
        let folder = HangoverBrandTests.repoRoot.appendingPathComponent("Sources/OpenIslandApp/Nook/Widgets/Notes")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        let english = try HangoverBrandTests.table("en")
        let pattern = try NSRegularExpression(pattern: #"\.t\("(nook\.notes\.[A-Za-z.]+)""#)
        var asked = Set<String>()
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for match in pattern.matches(in: text, range: range) {
                if let key = Range(match.range(at: 1), in: text).map({ String(text[$0]) }) { asked.insert(key) }
            }
        }
        #expect(!asked.isEmpty)
        for key in asked {
            #expect(english[key] != nil, "\(key) is asked for and missing")
        }
    }
}
