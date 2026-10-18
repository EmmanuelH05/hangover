import Foundation

/// What the sidebar's search field and the results pane share (F3, F4): the
/// query, the selected hit, the jump that opening a hit started, and
/// whether the results or the tab's own pane is showing. Pure, so the rules
/// can be tested without a window.
struct SettingsSearchState: Equatable {
    var query = ""
    var selectedID: String?
    var jump: SettingsJump?
    var showsResults = false

    /// Typing starts over: the first hit is selected, an earlier jump is
    /// forgotten and the results come back.
    mutating func queryChanged(_ query: String, groups: [SettingsSearchGroup]) {
        self.query = query
        selectedID = SettingsSearchSelection.first(in: groups)
        jump = nil
        showsResults = true
    }

    mutating func moveDown(groups: [SettingsSearchGroup]) {
        selectedID = SettingsSearchSelection.next(after: selectedID, in: groups)
    }

    mutating func moveUp(groups: [SettingsSearchGroup]) {
        selectedID = SettingsSearchSelection.previous(before: selectedID, in: groups)
    }

    /// Opening a hit leaves the results for the setting's pane. The query
    /// stays in the field so Escape can come back to the results.
    mutating func open(_ hit: SettingsSearchHit, now: Date) {
        selectedID = hit.id
        jump = SettingsJump(entry: hit.entry, at: now)
        showsResults = false
    }

    /// With a setting open, Escape goes back to the results; otherwise it
    /// clears the search.
    mutating func escape() {
        if jump != nil {
            jump = nil
            showsResults = true
        } else {
            clear()
        }
    }

    mutating func clear() {
        query = ""
        selectedID = nil
        jump = nil
        showsResults = false
    }
}
