import Foundation
import Testing
@testable import OpenIslandApp

// MARK: - Strings

@Suite struct NookDesignStringsTests {
    /// `Tests/OpenIslandAppTests/<this file>` sits three levels below the root.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static let languages = ["en", "zh-Hans", "zh-Hant"]

    private static func table(_ language: String) throws -> [String: String] {
        let url = repoRoot.appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
        return try #require(NSDictionary(contentsOf: url) as? [String: String], "\(language) did not load")
    }

    /// Every "nook.design." key written out in the design kit's source
    /// files and in the tray card and its tiles, plus the ones built from an
    /// enum.
    private static func usedKeys() throws -> Set<String> {
        let sources = repoRoot.appendingPathComponent("Sources/OpenIslandApp/Nook/Widgets")
        let design = try FileManager.default.contentsOfDirectory(
            at: sources.appendingPathComponent("Design"), includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }
        let files = design + ["Tray/NookTrayCard.swift", "Tray/NookTrayTile.swift"].map(sources.appendingPathComponent)
        let pattern = try NSRegularExpression(pattern: "\"(nook\\.design\\.[A-Za-z0-9.]+)\"")
        var keys = Set<String>()
        for file in files {
            // A search anchor names a settings entry, not a string to show.
            let source = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.contains(".settingsAnchor(") && !$0.contains("SettingsIndex.entry(") }
                .joined(separator: "\n")
            let range = NSRange(source.startIndex..., in: source)
            for match in pattern.matches(in: source, range: range) {
                guard let keyRange = Range(match.range(at: 1), in: source) else { continue }
                keys.insert(String(source[keyRange]))
            }
        }
        // Settings keys and the decoder's user info key are not strings to show.
        keys.subtract([
            NookDesignKit.tabKey, NookDesignKit.formatKey, NookDesignKit.savesPicksKey,
            NookDesignKit.keepsPickingKey,
            NookDesignHotkeyController.comboKey, NookDesignSkipCounter.key.rawValue,
        ])
        keys.insert("nook.design.title")
        keys.formUnion(NookDesignTab.allCases.map(\.titleKey))
        keys.formUnion(NookDesignColorFormat.allCases.map(\.titleKey))
        return keys
    }

    @Test func everyDesignKitStringExistsInEveryLanguageAndHasNoDash() throws {
        let keys = try Self.usedKeys()
        #expect(keys.count > 100)

        for language in Self.languages {
            let table = try Self.table(language)
            for key in keys.sorted() {
                let value = table[key] ?? ""
                #expect(!value.isEmpty, "\(language) is missing \(key)")
                #expect(!value.contains("\u{2014}") && !value.contains("\u{2013}"), "\(language) \(key) has a dash")
            }
        }
    }

    @Test func theStringTablesHoldNoDesignKitKeyThatIsNotUsed() throws {
        let used = try Self.usedKeys()
        for language in Self.languages {
            let unused = try Self.table(language).keys.filter { $0.hasPrefix("nook.design.") && !used.contains($0) }
            #expect(unused.isEmpty, "\(language) has unused keys: \(unused.sorted())")
        }
    }

    @Test func theSameArgumentsAreAskedForInEveryLanguage() throws {
        let keys = try Self.usedKeys()
        let english = try Self.table("en")
        let pattern = try NSRegularExpression(pattern: "%(lld|@)")
        func arguments(_ text: String) -> [String] {
            pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
                Range($0.range, in: text).map { String(text[$0]) }
            }
        }
        for language in Self.languages.dropFirst() {
            let table = try Self.table(language)
            for key in keys.sorted() {
                #expect(arguments(table[key] ?? "") == arguments(english[key] ?? ""), "\(language) \(key)")
            }
        }
    }

    @Test func theEnglishStringsFollowTheHouseWording() throws {
        let english = try Self.table("en")
        let word = try NSRegularExpression(pattern: "\\bso\\b", options: [.caseInsensitive])
        for key in try Self.usedKeys().sorted() {
            let value = english[key] ?? ""
            let range = NSRange(value.startIndex..., in: value)
            #expect(word.firstMatch(in: value, range: range) == nil, "\(key) uses a word the house rules leave out")
        }
    }

    @Test func theWidgetAndItsTabsHaveNames() {
        #expect(NookWidgetKind.design.title == LanguageManager.shared.t("nook.design.title"))
        #expect(NookWidgetKind.design.title != "nook.design.title")
        for tab in NookDesignTab.allCases {
            #expect(LanguageManager.shared.t(tab.titleKey) != tab.titleKey)
        }
    }
}
