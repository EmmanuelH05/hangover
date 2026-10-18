import Foundation
import Testing
@testable import OpenIslandApp

/// The rules of the search field's state (F3, F4), on groups built from
/// entries whose keys exist in the string tables.
@MainActor
struct SettingsSearchStateTests {
    private let lang = LanguageManager.shared
    private let now = Date(timeIntervalSince1970: 1_000)

    private let entries = [
        SettingsEntry("general.launchAtLogin", tab: .general, title: "settings.general.launchAtLogin"),
        SettingsEntry("general.showDockIcon", tab: .general, title: "settings.general.showDockIcon"),
        SettingsEntry("about.sourceCode", tab: .about, title: "settings.about.sourceCode"),
    ]

    private func groups(_ query: String) -> [SettingsSearchGroup] {
        SettingsSearch.results(for: query, entries: entries, agentsEnabled: true, lang: lang)
    }

    private func hit(_ id: String, _ query: String) throws -> SettingsSearchHit {
        try #require(SettingsSearchSelection.flat(groups(query)).first { $0.id == id })
    }

    @Test
    func startsEmptyWithNoResultsShowing() {
        let state = SettingsSearchState()
        #expect(state.query.isEmpty)
        #expect(state.selectedID == nil)
        #expect(state.jump == nil)
        #expect(!state.showsResults)
    }

    @Test
    func typingSelectsTheFirstHitAndShowsResults() {
        var state = SettingsSearchState()
        let found = groups("icon")
        state.queryChanged("icon", groups: found)
        #expect(state.query == "icon")
        #expect(state.selectedID == SettingsSearchSelection.first(in: found))
        #expect(state.selectedID == "general.showDockIcon")
        #expect(state.showsResults)
    }

    @Test
    func typingWithNoMatchSelectsNothing() {
        var state = SettingsSearchState()
        state.queryChanged("zzzz", groups: groups("zzzz"))
        #expect(state.selectedID == nil)
        #expect(state.showsResults)
    }

    @Test
    func typingDropsTheJumpAndBringsTheResultsBack() throws {
        var state = SettingsSearchState()
        state.queryChanged("icon", groups: groups("icon"))
        state.open(try hit("general.showDockIcon", "icon"), now: now)
        #expect(state.jump != nil)
        #expect(!state.showsResults)

        state.queryChanged("ico", groups: groups("ico"))
        #expect(state.jump == nil)
        #expect(state.showsResults)
    }

    @Test
    func arrowsMoveOverTheFlatListAndStopAtTheEnds() {
        var state = SettingsSearchState()
        let found = groups("o")
        let ids = SettingsSearchSelection.flat(found).map(\.id)
        #expect(ids.count >= 2)
        state.queryChanged("o", groups: found)
        state.moveUp(groups: found)
        #expect(state.selectedID == ids.first)
        state.moveDown(groups: found)
        #expect(state.selectedID == ids[1])
        for _ in ids { state.moveDown(groups: found) }
        #expect(state.selectedID == ids.last)
    }

    @Test
    func openingSetsTheJumpHidesTheResultsAndKeepsTheQuery() throws {
        var state = SettingsSearchState()
        state.queryChanged("icon", groups: groups("icon"))
        let chosen = try hit("general.showDockIcon", "icon")
        state.open(chosen, now: now)
        #expect(state.jump == SettingsJump(entry: chosen.entry, at: now))
        #expect(state.selectedID == chosen.id)
        #expect(!state.showsResults)
        #expect(state.query == "icon")
    }

    @Test
    func escapeWithAJumpGoesBackToTheResultsKeepingTheQuery() throws {
        var state = SettingsSearchState()
        state.queryChanged("icon", groups: groups("icon"))
        state.open(try hit("general.showDockIcon", "icon"), now: now)
        state.escape()
        #expect(state.jump == nil)
        #expect(state.showsResults)
        #expect(state.query == "icon")
        #expect(state.selectedID == "general.showDockIcon")
    }

    @Test
    func escapeWithoutAJumpClearsTheQueryAndSelection() {
        var state = SettingsSearchState()
        state.queryChanged("icon", groups: groups("icon"))
        state.escape()
        #expect(state.query.isEmpty)
        #expect(state.selectedID == nil)
        #expect(!state.showsResults)
    }

    @Test
    func aSecondEscapeAfterTheFirstClearsEverything() throws {
        var state = SettingsSearchState()
        state.queryChanged("icon", groups: groups("icon"))
        state.open(try hit("general.showDockIcon", "icon"), now: now)
        state.escape()
        state.escape()
        #expect(state == SettingsSearchState())
    }

    @Test
    func clearResetsEverything() throws {
        var state = SettingsSearchState()
        state.queryChanged("icon", groups: groups("icon"))
        state.open(try hit("general.showDockIcon", "icon"), now: now)
        state.clear()
        #expect(state == SettingsSearchState())
    }
}
