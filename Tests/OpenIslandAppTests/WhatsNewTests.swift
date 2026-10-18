import Foundation
import Testing
@testable import OpenIslandApp

/// The What's new words (D82): the bundled JSON, the versions it covers,
/// and that it still says what `design/update-flow/WHATS-NEW.md` says.
struct WhatsNewTests {
    @Test
    func versionsCompareNumberByNumber() {
        #expect(AppVersion.compare("1.0.14", "1.0.9") == .orderedDescending)
        #expect(AppVersion.compare("1.0.9", "1.0.14") == .orderedAscending)
        #expect(AppVersion.compare("1.0", "1.0.0") == .orderedSame)
        #expect(AppVersion.compare("1.1", "1.0.99") == .orderedDescending)
        #expect(AppVersion.compare("2", "1.9.9") == .orderedDescending)
    }

    @Test
    func theBundledCatalogParsesAndNamesTheNextVersion() throws {
        let catalog = WhatsNewCatalog.bundled()
        #expect(!catalog.releases.isEmpty, "WhatsNew.json is in the bundle")
        let newest = try #require(catalog.releases.first)
        for release in catalog.releases {
            #expect(!release.items.isEmpty, "a version with nothing to show has no entry")
            for item in release.items {
                #expect(!item.title.isEmpty)
                #expect(item.title.split(separator: " ").count <= 5, "a title is at most five words: \(item.title)")
            }
        }
        #expect(catalog.releases == catalog.releases.sorted {
            AppVersion.compare($0.version, $1.version) == .orderedDescending
        }, "newest first")
        #expect(newest.version == "1.0.14")
    }

    @Test
    func skippedVersionsAreTheOnesAfterTheLastSeenUpToTheCurrent() {
        let catalog = WhatsNewCatalog(releases: [
            WhatsNewRelease(version: "1.0.12", items: [WhatsNewItem(title: "Twelve")]),
            WhatsNewRelease(version: "1.0.14", items: [WhatsNewItem(title: "Fourteen")]),
            WhatsNewRelease(version: "1.0.13", items: []),
            WhatsNewRelease(version: "1.0.15", items: [WhatsNewItem(title: "Fifteen")]),
        ])
        let skipped = catalog.releases(after: "1.0.11", upTo: "1.0.14")
        #expect(skipped.map(\.version) == ["1.0.14", "1.0.12"])
        #expect(catalog.releases(after: "1.0.14", upTo: "1.0.14").isEmpty)
        #expect(catalog.releases(after: "1.0.14", upTo: "1.0.15").map(\.version) == ["1.0.15"])
    }

    @Test
    func theCardShowsThreePerVersionAndCountsThemAll() {
        let pending = WhatsNewPending(releases: [
            WhatsNewRelease(version: "1.0.14", items: (1...4).map { WhatsNewItem(title: "Item \($0)") }),
            WhatsNewRelease(version: "1.0.13", items: [WhatsNewItem(title: "Older")]),
        ])
        #expect(pending.version == "1.0.14")
        #expect(pending.totalCount == 5)
        #expect(pending.shown.map(\.title) == ["Item 1", "Item 2", "Item 3", "Older"])
        #expect(pending.hasMore)

        // A long gap never makes a card taller than the island can hold.
        let longGap = WhatsNewPending(releases: (10...14).reversed().map { minor in
            WhatsNewRelease(version: "1.0.\(minor)", items: (1...3).map { WhatsNewItem(title: "\(minor).\($0)") })
        })
        #expect(longGap.shown.count == WhatsNewCatalog.maxShown)
        #expect(longGap.totalCount == 15)
        #expect(longGap.shown.first?.title == "14.1")
    }

    @Test
    func parsingTakesTheOptionalFields() throws {
        let data = Data("""
        {"releases":[{"version":"1.0.14","items":[{"title":"A"},{"title":"B","detail":"b","symbol":"star"}]}]}
        """.utf8)
        let catalog = try WhatsNewCatalog.parse(data)
        #expect(catalog.releases[0].items[0] == WhatsNewItem(title: "A", detail: nil, symbol: nil))
        #expect(catalog.releases[0].items[1] == WhatsNewItem(title: "B", detail: "b", symbol: "star"))
    }

    /// The JSON is written from the Markdown by `scripts/whats-new.ts`.
    /// This reads the Markdown the same way and fails when the two drift,
    /// which means the script was not run after an edit.
    @Test
    func theBundledJSONSaysWhatTheMarkdownSays() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let markdownURL = root.appendingPathComponent("design/update-flow/WHATS-NEW.md")
        guard let markdown = try? String(contentsOf: markdownURL, encoding: .utf8) else {
            // A checkout without the design folder (a public copy) has
            // nothing to compare against.
            return
        }
        let fromMarkdown = Self.parse(markdown)
        let bundled = WhatsNewCatalog.bundled()
        #expect(bundled.releases == fromMarkdown, "run `bun scripts/whats-new.ts` after editing WHATS-NEW.md")
    }

    /// `scripts/whats-new.ts`, in Swift.
    static func parse(_ markdown: String) -> [WhatsNewRelease] {
        var releases: [WhatsNewRelease] = []
        var item: WhatsNewItem?
        func closeItem() {
            if let open = item, !releases.isEmpty { releases[releases.count - 1].items.append(open) }
            item = nil
        }
        for raw in markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if let version = Self.match(raw, #"^##\s+(\d+(?:\.\d+)*)\s*$"#) {
                closeItem()
                releases.append(WhatsNewRelease(version: version, items: []))
                continue
            }
            guard !releases.isEmpty else { continue }
            if let title = Self.match(raw, #"^\d+\.\s+\*\*(.+?)\*\*\s*$"#) {
                closeItem()
                item = WhatsNewItem(title: title.trimmingCharacters(in: .whitespaces))
                continue
            }
            if let line = Self.match(raw, #"^\s+(\S.*)$"#), item != nil {
                let text = line.trimmingCharacters(in: .whitespaces)
                if let symbol = Self.match(text, #"^symbol:\s*(\S+)$"#) {
                    item?.symbol = symbol
                } else if item?.detail == nil {
                    item?.detail = text
                }
                continue
            }
            if raw.trimmingCharacters(in: .whitespaces).isEmpty || !raw.hasPrefix(" ") { closeItem() }
        }
        closeItem()
        return releases
            .filter { !$0.items.isEmpty }
            .sorted { AppVersion.compare($0.version, $1.version) == .orderedDescending }
    }

    private static func match(_ text: String, _ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              result.numberOfRanges > 1,
              let range = Range(result.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
