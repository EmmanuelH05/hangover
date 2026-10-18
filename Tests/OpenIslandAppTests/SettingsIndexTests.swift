import Foundation
import Testing
@testable import OpenIslandApp

/// The settings index and the rows that anchor it stay together (D84, S2):
/// a new setting joins by declaring one entry and anchoring its row, and
/// these tests fail when one of the two is missing.
///
/// The anchor forms the source scan reads: the string form the panes use,
/// `.settingsAnchor("general.launchAtLogin")`, and
/// `.settingsAnchor(SettingsIndex.entry("general.launchAtLogin")!)`. The
/// id is a string literal in both. Any other
/// argument is counted as an anchor but cannot be tied to an id by reading
/// text, so only this form is checked against the index.
struct SettingsIndexTests {
    static let languages = HangoverBrandTests.languages

    // MARK: Reading the sources

    /// The `.swift` files under `Sources/`, minus the file that defines the
    /// modifier, whose comments name the call.
    static func sourceFiles() -> [URL] {
        let root = HangoverBrandTests.repoRoot.appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "SettingsIndex.swift" }
    }

    /// The lines of a file that are code, not comments.
    static func codeLines(_ url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    struct AnchorUse {
        let file: String
        /// The id named by `SettingsIndex.entry("<id>")`, nil for any other argument.
        let id: String?
    }

    static func anchorUses() -> [AnchorUse] {
        let call = "\\.settingsAnchor\\("
        let named = try! NSRegularExpression(pattern: call + "\\s*(?:SettingsIndex\\.entry\\(\\s*)?\"([^\"]+)\"")
        let any = try! NSRegularExpression(pattern: call)
        var uses: [AnchorUse] = []
        for url in sourceFiles() {
            for line in codeLines(url) {
                let range = NSRange(line.startIndex..., in: line)
                let total = any.numberOfMatches(in: line, range: range)
                guard total > 0 else { continue }
                var namedCount = 0
                for match in named.matches(in: line, range: range) {
                    if let idRange = Range(match.range(at: 1), in: line) {
                        uses.append(AnchorUse(file: url.lastPathComponent, id: String(line[idRange])))
                        namedCount += 1
                    }
                }
                for _ in namedCount..<total {
                    uses.append(AnchorUse(file: url.lastPathComponent, id: nil))
                }
            }
        }
        return uses
    }

    /// Wave 2 adds the anchors; until one exists the coverage test waits.
    static let hasAnchors = !anchorUses().isEmpty

    // MARK: The index

    /// One setting, one result: no two entries say the same words.
    @Test func noTwoEntriesShareTheirWords() {
        var seen: [String: String] = [:]
        for entry in SettingsIndex.all {
            let words = entry.titleKey + "|" + (entry.descriptionKey ?? "")
            #expect(seen[words] == nil, "\(entry.id) says what \(seen[words] ?? "") says")
            seen[words] = entry.id
        }
    }

    /// A description belongs to its title: the two keys come from the same
    /// setting, which their first component and the start of their second
    /// show (`setup.permissionsTitle` and `setup.permissionsDesc`). The
    /// swipe row is the one exception: its caption is the tour's own tip.
    @Test func aDescriptionBelongsToItsTitle() {
        let captionedByTheTour: Set<String> = ["general.swipeGestures"]
        for entry in SettingsIndex.all where !captionedByTheTour.contains(entry.id) {
            guard let description = entry.descriptionKey else { continue }
            let title = entry.titleKey.split(separator: ".").map(String.init)
            let note = description.split(separator: ".").map(String.init)
            let sameSetting = title.first == note.first
                && (title.count < 2 || note.count < 2 || title[1].commonPrefix(with: note[1]).count >= 4)
            #expect(
                description.hasPrefix(entry.titleKey) || sameSetting,
                "\(entry.id): \(description) does not belong to \(entry.titleKey)"
            )
        }
    }

    /// A row that is not always on screen names the row that holds it.
    @Test func everyFallbackNamesAnEntryThatIsNotItself() {
        let ids = Set(SettingsIndex.all.map(\.id))
        for (id, fallback) in SettingsIndex.fallbacks {
            #expect(ids.contains(id), "fallback for an unknown entry \(id)")
            #expect(ids.contains(fallback), "\(id) falls back to an unknown entry \(fallback)")
            #expect(id != fallback)
            #expect(SettingsIndex.fallbacks[fallback] != id, "\(id) and \(fallback) fall back to each other")
        }
    }

    @Test func idsAreUnique() {
        let ids = SettingsIndex.entries.map(\.id)
        let repeated = Dictionary(grouping: ids, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
        let none: [String] = []
        #expect(repeated == none, "ids used twice: \(repeated)")
    }

    @Test func idsAreDottedAndStartWithTheirTab() {
        let shape = try! NSRegularExpression(pattern: "^[a-z][A-Za-z0-9]*(\\.[A-Za-z0-9]+)+$")
        for entry in SettingsIndex.entries {
            let range = NSRange(entry.id.startIndex..., in: entry.id)
            #expect(shape.firstMatch(in: entry.id, range: range) != nil, "\(entry.id) is not dotted camelCase")
            #expect(entry.id.hasPrefix(entry.tab.rawValue + "."), "\(entry.id) does not start with its tab \(entry.tab.rawValue)")
        }
    }

    @Test func everyEntryIsOnARealTabAndItsSubpageExists() throws {
        let en = try HangoverBrandTests.table("en")
        for entry in SettingsIndex.entries {
            #expect(SettingsTab.allCases.contains(entry.tab), "\(entry.id) is on no tab")
            if let subpage = entry.subpage {
                #expect(en[subpage] != nil, "\(entry.id) names the sub-page \(subpage), which en.lproj lacks")
            }
        }
    }

    @Test func everyKeyThatExistsInEnglishExistsInTheChineseTables() throws {
        let en = try HangoverBrandTests.table("en")
        let others = try ["zh-Hans", "zh-Hant"].map { ($0, try HangoverBrandTests.table($0)) }
        for entry in SettingsIndex.entries {
            let keys = [entry.titleKey] + (entry.descriptionKey.map { [$0] } ?? [])
            for key in keys where en[key] != nil {
                for (language, table) in others {
                    #expect(table[key] != nil, "\(entry.id): \(key) is missing from \(language)")
                }
            }
        }
    }

    @Test
    func everyTitleKeyExistsInEnglish() throws {
        let en = try HangoverBrandTests.table("en")
        let missing = SettingsIndex.entries.filter { en[$0.titleKey] == nil }.map { "\($0.id): \($0.titleKey)" }
        let none: [String] = []
        #expect(missing == none)
    }

    // MARK: The anchors

    @Test func everyAnchorNamesAnExistingEntry() {
        let known = Set(SettingsIndex.entries.map(\.id))
        for use in Self.anchorUses() {
            guard let id = use.id else { continue }
            #expect(known.contains(id), "\(use.file) anchors \(id), which the index does not declare")
        }
    }

    @Test(.enabled(if: SettingsIndexTests.hasAnchors, "waits for the first .settingsAnchor( under Sources/"))
    func everyEntryHasAnAnchor() {
        let anchored = Set(Self.anchorUses().compactMap(\.id))
        let bare = SettingsIndex.entries.map(\.id).filter { !anchored.contains($0) }
        let none: [String] = []
        #expect(bare == none, "entries with no row anchoring them: \(bare)")
    }

    // MARK: The agents switch

    @Test @MainActor
    func entriesThatNeedAgentsVanishFromTheResultsWithAgentsOff() throws {
        let lang = LanguageManager.shared
        let gated = SettingsIndex.entries.filter(\.needsAgents)
        #expect(!gated.isEmpty)
        for entry in gated {
            let query = SettingsSearch.withoutSectionNumber(lang.t(entry.titleKey))
            let on = SettingsSearch.results(for: query, entries: SettingsIndex.entries, agentsEnabled: true, lang: lang)
            let off = SettingsSearch.results(for: query, entries: SettingsIndex.entries, agentsEnabled: false, lang: lang)
            #expect(SettingsSearchSelection.flat(on).contains { $0.id == entry.id }, "\(entry.id) is missing with agents on")
            #expect(!SettingsSearchSelection.flat(off).contains { $0.id == entry.id }, "\(entry.id) shows with agents off")
        }
    }
}
