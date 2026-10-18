import SwiftUI

extension View {
    /// The row a search result opens, named by its entry's id (S2). A
    /// row whose id is not in the index gets no anchor, and
    /// `SettingsIndexTests` reports the id, which keeps the index and the
    /// anchors together.
    @ViewBuilder
    func settingsAnchor(_ id: String) -> some View {
        if let entry = SettingsIndex.entry(id) {
            settingsAnchor(entry)
        } else {
            self
        }
    }
}
