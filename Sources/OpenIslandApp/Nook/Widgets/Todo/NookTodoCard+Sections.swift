import SwiftUI

/// The lines the card draws while two or more apps are on (T13, B7), worked
/// out without any view so a test can drive it. Each app is a header line
/// followed by its rows, or by one dim line with its message while it is not
/// ready. Headers count as lines toward the card's budget.
struct NookTodoCardSections: Equatable {
    /// One app as the card reads it.
    struct Entry: Equatable {
        let kind: NookTodoSourceKind
        let connection: NookTodoConnection
        let items: [NookTodoItem]
    }

    enum Line: Equatable, Identifiable {
        case header(NookTodoSourceKind)
        case row(NookTodoSourceKind, NookTodoItem)
        case unavailable(NookTodoSourceKind, message: String)
        /// The last line of a cut medium or large card: how many rows are not shown.
        case more(Int)

        /// Stable across cuts and completions, which keeps a row's view
        /// state (its fade) on that row when the lines above it change.
        var id: String {
            switch self {
            case .header(let kind): "header.\(kind.rawValue)"
            case .row(_, let item): "row.\(item.id)"
            case .unavailable(let kind, _): "unavailable.\(kind.rawValue)"
            case .more: "more"
            }
        }
    }

    /// What to draw, top to bottom.
    let lines: [Line]
    /// Open rows that did not fit.
    let hidden: Int
    /// Open rows across the apps that are ready, shown or not.
    let openCount: Int

    /// `budget` is the number of lines the card has, headers included. When
    /// the lines do not fit, the medium and large cards give the last line
    /// of the budget to "+N more" and the small card simply stops. A header
    /// left with nothing under it by the cut is not drawn.
    ///
    /// The apps come in order of urgency (T15): the one holding the
    /// earliest due task first, which is what a small budget must show;
    /// undated tasks count as last, and ties keep the Settings order.
    init(entries: [Entry], budget: Int, size: NookWidgetSize) {
        var all: [Line] = []
        var open = 0
        for entry in Self.byUrgency(entries) {
            all.append(.header(entry.kind))
            switch entry.connection {
            case .ready:
                open += entry.items.count
                all += entry.items.map { .row(entry.kind, $0) }
            case .unavailable(let message):
                all.append(.unavailable(entry.kind, message: message))
            }
        }
        openCount = open
        let budget = max(budget, 0)
        guard all.count > budget else {
            lines = all
            hidden = 0
            return
        }
        let keep = size == .small ? budget : max(budget - 1, 0)
        var shown = Self.trimmed(Array(all.prefix(keep)))
        let shownRows = Self.rowCount(shown)
        hidden = open - shownRows
        if size != .small, hidden > 0 {
            shown.append(.more(hidden))
        } else if size != .small {
            // Only an app's message fell past the cut: the whole budget is
            // used and nothing says "+0 more".
            shown = Self.trimmed(Array(all.prefix(budget)))
        }
        lines = shown
    }

    /// The lines without a header left with nothing under it.
    private static func trimmed(_ lines: [Line]) -> [Line] {
        var result = lines
        while case .header? = result.last { result.removeLast() }
        return result
    }

    private static func rowCount(_ lines: [Line]) -> Int {
        lines.filter { if case .row = $0 { true } else { false } }.count
    }

    /// The apps ordered by their most urgent open task (T15). An app that
    /// is not ready, or has nothing dated, keeps its place after the dated
    /// ones; among those the Settings order holds.
    static func byUrgency(_ entries: [Entry]) -> [Entry] {
        let indexed = entries.enumerated().map { (index: $0.offset, entry: $0.element, due: earliestDue($0.element)) }
        return indexed.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.index < b.index
            }
        }.map(\.entry)
    }

    /// The earliest due date among an app's open tasks, nil when none has
    /// one or the app cannot show them.
    static func earliestDue(_ entry: Entry) -> Date? {
        guard entry.connection == .ready else { return nil }
        return entry.items.filter { !$0.isCompleted }.compactMap(\.dueDate).min()
    }

    /// The same, from the hub's sections.
    @MainActor
    init(sections: [NookTodoSection], budget: Int, size: NookWidgetSize) {
        self.init(
            entries: sections.map { Entry(kind: $0.kind, connection: $0.source.connection, items: $0.source.items) },
            budget: budget,
            size: size
        )
    }
}

// MARK: - Drawing the sections

extension NookTodoCard {
    /// Width kept at the add field's trailing edge for the chip.
    static let chipRoom: CGFloat = 92

    /// The first problem line among the sources, the add target's first.
    private func groupedNotice(_ sections: [NookTodoSection]) -> String? {
        nook.todo.source(reminders: nook.reminders).errorMessage
            ?? sections.lazy.compactMap { $0.source.errorMessage }.first
    }

    /// Medium and large: header with the total, the add field with its chip,
    /// then the sections. The small card has its own layout.
    @ViewBuilder
    func groupedList(_ sections: [NookTodoSection]) -> some View {
        let add = nook.todo.source(reminders: nook.reminders)
        let notice = groupedNotice(sections)
        let layout = NookTodoCardSections(
            sections: sections, budget: Self.rowLimit(for: size, hasNotice: notice != nil), size: size
        )
        if size == .small {
            groupedSmallList(sections, add: add, layout: layout, notice: notice)
        } else {
            NookCardHeader(title: "Todo", systemImage: "checklist", trailing: "\(layout.openCount)")
            HStack(spacing: 6) {
                addField(add)
                    .onSubmit { if add.canAdd { sendTyped(add, whenAdded: {}) } }
                    .demoTyping(.todo, text: $draft) { if add.canAdd { sendTyped(add, whenAdded: {}) } }
                dueControl(add)
            }
            groupedBody(sections, layout: layout, notice: notice, fitsDue: false)
        }
    }

    /// The lines, or "All clear" when every app is ready and has nothing
    /// open, then the notice line.
    @ViewBuilder
    func groupedBody(
        _ sections: [NookTodoSection], layout: NookTodoCardSections, notice: String?, fitsDue: Bool
    ) -> some View {
        let everyoneReady = sections.allSatisfy { $0.source.connection == .ready }
        if layout.openCount == 0, everyoneReady {
            allClear
        } else {
            groupedLines(sections, layout: layout, fitsDue: fitsDue)
            Spacer(minLength: 0)
        }
        if let notice {
            noticeLabel(notice)
        }
    }

    private func groupedLines(
        _ sections: [NookTodoSection], layout: NookTodoCardSections, fitsDue: Bool
    ) -> some View {
        let merged = nook.todo.items(reminders: nook.reminders)
        let sourceByKind = Dictionary(uniqueKeysWithValues: sections.map { ($0.kind, $0.source) })
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(layout.lines.enumerated()), id: \.element.id) { index, line in
                switch line {
                case .header(let kind):
                    sectionHeader(kind)
                        .padding(.top, index == 0 ? 0 : 4)
                case .row(let kind, let item):
                    if let source = sourceByKind[kind] {
                        let position = merged.firstIndex { $0.id == item.id }
                        if fitsDue {
                            // The due label stays only when title and label both fit.
                            ViewThatFits(in: .horizontal) {
                                row(item, source: source, showsDue: true, position: position)
                                row(item, source: source, showsDue: false, position: position)
                            }
                        } else {
                            row(item, source: source, position: position)
                        }
                    }
                case .unavailable(_, let message):
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(2)
                case .more(let count):
                    Text(LanguageManager.shared.t("nook.todo.more", count))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    /// A 6 pt dot in the app's color and its name, uppercased.
    private func sectionHeader(_ kind: NookTodoSourceKind) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(kind.dotColor)
                .frame(width: 6, height: 6)
            Text(LanguageManager.shared.t(kind.nameKey).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
        }
    }
}
