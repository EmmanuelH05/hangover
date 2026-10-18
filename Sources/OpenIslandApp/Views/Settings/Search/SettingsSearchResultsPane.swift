import SwiftUI

/// The pane that replaces a tab while the sidebar's field holds a query
/// (D84, F3 and F5): the count line and the hits grouped by tab, or the
/// no-match state. Arrow keys and Return are the wiring's; this is a plain
/// view that draws what it is given.
struct SettingsSearchResultsPane: View {
    let query: String
    let groups: [SettingsSearchGroup]
    let selectedID: String?
    let onOpen: (SettingsSearchHit) -> Void
    let onFeedback: (String) -> Void

    private var lang: LanguageManager { .shared }
    private var count: Int { groups.reduce(0) { $0 + $1.hits.count } }
    private var shownQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
            }
            .onChange(of: selectedID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
            }
        }
        .navigationTitle(lang.t("settings.search.results"))
    }

    /// Everything inside the scroll view. `ImageRenderer` draws a scroll
    /// view empty, so the render test draws this.
    var content: some View {
                VStack(alignment: .leading, spacing: 0) {
                    Text(lang.t("settings.search.results"))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.bottom, 6)

                    if groups.isEmpty {
                        noMatch
                    } else {
                        Text(SettingsSearch.countLine(count, query: query, lang: lang))
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.bottom, 12)
                        ForEach(groups) { group in
                            groupView(group)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Groups and hits

    private func groupView(_ group: SettingsSearchGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.name.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 8)
            ForEach(group.hits) { hit in
                card(hit)
            }
        }
        .padding(.bottom, 8)
    }

    private func card(_ hit: SettingsSearchHit) -> some View {
        let isSelected = hit.id == selectedID
        return Button {
            onOpen(hit)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.highlighted(hit.title, hit.titleRanges))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                if let description = hit.description {
                    Text(Self.highlighted(description, hit.descriptionRanges))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(V6Palette.paper, lineWidth: isSelected ? 1.5 : 0)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .id(hit.id)
    }

    /// The text with a paper-tinted background behind each matched range.
    static func highlighted(_ text: String, _ ranges: [Range<String.Index>]) -> AttributedString {
        var result = AttributedString(text)
        for range in ranges {
            guard let target = Range(range, in: result) else { continue }
            result[target].backgroundColor = V6Palette.paper.opacity(0.28)
        }
        return result
    }

    // MARK: - No match

    private var noMatch: some View {
        VStack(spacing: 6) {
            Text(lang.t("settings.search.none.title", shownQuery))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text(lang.t("settings.search.none.line"))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
            Button {
                onFeedback(shownQuery)
            } label: {
                Text(lang.t("feedback.button"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }
}
