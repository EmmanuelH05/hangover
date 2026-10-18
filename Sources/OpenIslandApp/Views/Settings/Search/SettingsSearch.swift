import Foundation

/// One setting that matched, with the words it matched on in the current
/// language and where in them (S3).
struct SettingsSearchHit: Identifiable, Hashable, Sendable {
    let entry: SettingsEntry
    let title: String
    let description: String?
    let titleRanges: [Range<String.Index>]
    let descriptionRanges: [Range<String.Index>]

    var id: String { entry.id }
}

/// The hits under one tab, or under one sub-page of a tab.
struct SettingsSearchGroup: Identifiable, Hashable, Sendable {
    /// "Personalization" or "Personalization · Accent".
    let name: String
    let tab: SettingsTab
    let subpage: String?
    let hits: [SettingsSearchHit]

    var id: String { "\(tab.rawValue)|\(subpage ?? "")" }
}

/// The search's matching, kept free of views so it can be tested (S3).
enum SettingsSearch {
    static func results(
        for query: String,
        entries: [SettingsEntry],
        agentsEnabled: Bool,
        lang: LanguageManager
    ) -> [SettingsSearchGroup] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }

        let shown = SettingsTab.shown(agentsEnabled: agentsEnabled)
        var groups: [SettingsSearchGroup] = []

        for tab in SettingsTab.allCases where shown.contains(tab) {
            let inTab = entries.filter { $0.tab == tab && (agentsEnabled || !$0.needsAgents) }
            // Subpages in the order they first appear in the index, the
            // tab's own pane first.
            var subpages: [String?] = [nil]
            for entry in inTab where !subpages.contains(entry.subpage) {
                subpages.append(entry.subpage)
            }

            for subpage in subpages {
                let hits = inTab
                    .filter { $0.subpage == subpage }
                    .compactMap { hit(for: $0, needle: needle, lang: lang) }
                guard !hits.isEmpty else { continue }
                // A stable partition: title matches first, index order kept.
                let ordered = hits.filter { !$0.titleRanges.isEmpty } + hits.filter { $0.titleRanges.isEmpty }
                let name = subpage.map { "\(tab.label(lang)) · \(lang.t($0))" } ?? tab.label(lang)
                groups.append(SettingsSearchGroup(name: name, tab: tab, subpage: subpage, hits: ordered))
            }
        }
        return groups
    }

    static func countLine(_ count: Int, query: String, lang: LanguageManager) -> String {
        let shown = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return count == 1
            ? lang.t("settings.search.count.one", shown)
            : lang.t("settings.search.count.other", count, shown)
    }

    /// Every non-overlapping range of the needle in the text, ignoring case
    /// and diacritics.
    static func ranges(of needle: String, in text: String) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        var from = text.startIndex
        while from < text.endIndex,
              let range = text.range(
                  of: needle,
                  options: [.caseInsensitive, .diacriticInsensitive],
                  range: from..<text.endIndex
              ) {
            found.append(range)
            from = range.upperBound
        }
        return found
    }

    /// "05 · Status glow" as "Status glow": two digits, a space, the middle
    /// dot and a space at the start are the page's own numbering.
    static func withoutSectionNumber(_ title: String) -> String {
        let scalars = Array(title.unicodeScalars)
        guard scalars.count > 5,
              scalars[0].properties.numericType != nil, scalars[1].properties.numericType != nil,
              scalars[2] == " ", scalars[3] == "\u{00B7}", scalars[4] == " " else { return title }
        return String(String.UnicodeScalarView(scalars[5...]))
    }

    private static func hit(for entry: SettingsEntry, needle: String, lang: LanguageManager) -> SettingsSearchHit? {
        // The Personalization sections number themselves ("05 · Status
        // glow"); a result names the setting, not its place on the page.
        let title = Self.withoutSectionNumber(lang.t(entry.titleKey))
        let description = entry.descriptionKey.map { lang.t($0) }
        let titleRanges = ranges(of: needle, in: title)
        let descriptionRanges = description.map { ranges(of: needle, in: $0) } ?? []
        guard !titleRanges.isEmpty || !descriptionRanges.isEmpty else { return nil }
        return SettingsSearchHit(
            entry: entry,
            title: title,
            description: description,
            titleRanges: titleRanges,
            descriptionRanges: descriptionRanges
        )
    }
}

/// Which hit the arrow keys have selected, over the flat list of hits in
/// the order the pane shows them. Moving stops at the ends (S3).
enum SettingsSearchSelection {
    static func flat(_ groups: [SettingsSearchGroup]) -> [SettingsSearchHit] {
        groups.flatMap(\.hits)
    }

    /// The hit selected whenever the results change.
    static func first(in groups: [SettingsSearchGroup]) -> String? {
        flat(groups).first?.id
    }

    static func next(after id: String?, in groups: [SettingsSearchGroup]) -> String? {
        move(from: id, by: 1, in: groups)
    }

    static func previous(before id: String?, in groups: [SettingsSearchGroup]) -> String? {
        move(from: id, by: -1, in: groups)
    }

    private static func move(from id: String?, by step: Int, in groups: [SettingsSearchGroup]) -> String? {
        let ids = flat(groups).map(\.id)
        guard !ids.isEmpty else { return nil }
        guard let id, let index = ids.firstIndex(of: id) else { return ids.first }
        return ids[min(max(index + step, 0), ids.count - 1)]
    }
}
