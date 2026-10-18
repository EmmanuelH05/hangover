import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// The search's matching (S3) and its results pane (S4). The entries are
/// built here from keys that exist in the string tables, so the tests do not
/// depend on how far the real index is filled. The English words are the
/// ones the tests search for.
@MainActor
struct SettingsSearchTests {
    private let lang = LanguageManager.shared

    private let launch = SettingsEntry(
        "general.launchAtLogin", tab: .general, title: "settings.general.launchAtLogin"
    )
    private let install = SettingsEntry(
        "about.installAutomatically", tab: .about,
        title: "settings.about.installAutomatically",
        description: "settings.about.installAutomatically.description"
    )
    private let trigger = SettingsEntry(
        "general.openTrigger", tab: .general, title: "settings.general.openTrigger"
    )

    private func search(_ query: String, _ entries: [SettingsEntry], agents: Bool = true) -> [SettingsSearchGroup] {
        SettingsSearch.results(for: query, entries: entries, agentsEnabled: agents, lang: lang)
    }

    // MARK: - Matching

    @Test
    func aBlankQueryGivesNothing() {
        #expect(search("", [launch, install]).isEmpty)
        #expect(search("   \n", [launch, install]).isEmpty)
    }

    @Test
    func titleMatchesComeBeforeDescriptionOnlyMatchesInAGroup() throws {
        // "island" is in the first entry's description and the second's title.
        let descriptionOnly = SettingsEntry(
            "general.launchAtLogin", tab: .general,
            title: "settings.general.launchAtLogin",
            description: "settings.about.installAutomatically.description"
        )
        let groups = search("island", [descriptionOnly, trigger])
        let group = try #require(groups.first)
        #expect(groups.count == 1)
        #expect(group.hits.map(\.id) == ["general.openTrigger", "general.launchAtLogin"])
        #expect(group.hits[0].titleRanges.count == 1)
        #expect(group.hits[1].titleRanges.isEmpty)
        #expect(group.hits[1].descriptionRanges.count == 1)
    }

    @Test
    func caseAndDiacriticsAreIgnored() {
        #expect(search("LAUNCH", [launch]).first?.hits.count == 1)
        #expect(search("láunch at", [launch]).first?.hits.count == 1)
        #expect(search("  launch  ", [launch]).first?.hits.count == 1)
        #expect(search("zzzz", [launch]).isEmpty)
    }

    @Test
    func everyRangeOfARepeatedWordIsFound() throws {
        let hit = try #require(search("it", [install]).first?.hits.first)
        let description = try #require(hit.description)
        #expect(hit.descriptionRanges.count >= 2)
        for range in hit.descriptionRanges {
            #expect(description[range].lowercased() == "it")
        }
    }

    // MARK: - Grouping

    @Test
    func groupsFollowTheTabOrderAndNameTheSubpage() throws {
        let accent = SettingsEntry(
            "appearance.accent", tab: .appearance, subpage: "settings.appearance.accent.title",
            title: "settings.general.launchAtLogin"
        )
        let plain = SettingsEntry(
            "appearance.plain", tab: .appearance, title: "settings.general.launchAtLogin"
        )
        // Given in the wrong order on purpose.
        let groups = search("launch", [install.withTitleMatching(), accent, plain, launch])
        #expect(groups.map(\.tab) == [.general, .appearance, .appearance, .about])
        #expect(groups[1].subpage == nil)
        #expect(groups[1].name == SettingsTab.appearance.label(lang))
        #expect(groups[2].name == "\(SettingsTab.appearance.label(lang)) · \(lang.t("settings.appearance.accent.title"))")
    }

    @Test
    func agentsOnlyTabsAreLeftOutWhenAgentsAreOff() {
        let setup = SettingsEntry("setup.x", tab: .setup, title: "settings.general.launchAtLogin")
        #expect(search("launch", [setup, launch], agents: true).map(\.tab) == [.general, .setup])
        #expect(search("launch", [setup, launch], agents: false).map(\.tab) == [.general])
    }

    // MARK: - The count line

    @Test
    func theCountLineSaysOneOrMany() {
        #expect(SettingsSearch.countLine(1, query: " glow ", lang: lang) == lang.t("settings.search.count.one", "glow"))
        #expect(SettingsSearch.countLine(4, query: "glow", lang: lang) == lang.t("settings.search.count.other", 4, "glow"))
        #expect(SettingsSearch.countLine(1, query: "glow", lang: lang) != SettingsSearch.countLine(2, query: "glow", lang: lang))
        #expect(!SettingsSearch.countLine(4, query: "glow", lang: lang).contains("%"))
    }

    // MARK: - Selection

    @Test
    func selectionMovesAndStopsAtTheEnds() {
        let groups = search("launch", [launch, install.withTitleMatching(), trigger.withTitleMatching()])
        let ids = SettingsSearchSelection.flat(groups).map(\.id)
        #expect(ids.count == 3)

        #expect(SettingsSearchSelection.first(in: groups) == ids[0])
        #expect(SettingsSearchSelection.next(after: ids[0], in: groups) == ids[1])
        #expect(SettingsSearchSelection.next(after: ids[1], in: groups) == ids[2])
        #expect(SettingsSearchSelection.next(after: ids[2], in: groups) == ids[2], "never wraps")
        #expect(SettingsSearchSelection.previous(before: ids[1], in: groups) == ids[0])
        #expect(SettingsSearchSelection.previous(before: ids[0], in: groups) == ids[0], "never wraps")
        #expect(SettingsSearchSelection.next(after: nil, in: groups) == ids[0])
        #expect(SettingsSearchSelection.first(in: []) == nil)
        #expect(SettingsSearchSelection.next(after: "x", in: []) == nil)
    }

    // MARK: - Render

    /// A Personalization section's number is the page's, not the setting's.
    @Test
    func aSectionNumberIsLeftOffTheTitle() {
        #expect(SettingsSearch.withoutSectionNumber("05 · Status glow") == "Status glow")
        #expect(SettingsSearch.withoutSectionNumber("Status glow") == "Status glow")
        #expect(SettingsSearch.withoutSectionNumber("5 · x") == "5 · x")
        #expect(SettingsSearch.withoutSectionNumber("05 ·") == "05 ·")
    }

    /// The pictures are of the shipped index, which is what the frames
    /// are compared with: "glow" as the frame searched, and "island".
    @Test
    func theResultsAndTheNoMatchPaneRender() throws {
        let entries = SettingsIndex.entries
        let glow = search("glow", entries)
        #expect(!glow.isEmpty, "the shipped index has glow settings")
        let results = try Self.render("search-results") {
            SettingsSearchResultsPane(
                query: "glow", groups: glow,
                selectedID: SettingsSearchSelection.first(in: glow),
                onOpen: { _ in }, onFeedback: { _ in }
            ).content
        }
        let island = search("island", entries)
        _ = try Self.render("search-results-island") {
            SettingsSearchResultsPane(
                query: "island", groups: island,
                selectedID: SettingsSearchSelection.first(in: island),
                onOpen: { _ in }, onFeedback: { _ in }
            ).content
        }
        let none = try Self.render("search-none") {
            SettingsSearchResultsPane(
                query: "spotify volume", groups: [], selectedID: nil,
                onOpen: { _ in }, onFeedback: { _ in }
            ).content
        }
        #expect(results != none)
    }

    private static func render<Content: View>(_ name: String, @ViewBuilder content: () -> Content) throws -> Data {
        let framed = content()
            .frame(width: 560, height: 420, alignment: .topLeading)
            .background(V6Palette.ink)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        let image = try #require(renderer.cgImage, "ImageRenderer returned no image for \(name)")
        let png = try #require(
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
            "PNG encoding failed for \(name)"
        )
        if ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_SNAPSHOTS"] == "1" {
            let directory = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("output/render/feedback-search", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return png
    }
}

private extension SettingsEntry {
    /// The same entry with a title that contains "launch", so a test can
    /// make several entries match one query.
    func withTitleMatching() -> SettingsEntry {
        SettingsEntry(id, tab: tab, subpage: subpage, title: "settings.general.launchAtLogin")
    }
}
