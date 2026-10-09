import SwiftUI

// MARK: - Shortcut keys on an approval card

/// The line under an approval card's buttons that names the shortcut for
/// each one, in the buttons' own order and with their own titles.
struct AgentHotkeyHintLine: View {
    let hint: AgentHotkeyHint
    let approveTitle: String
    let denyTitle: String

    var body: some View {
        HStack(spacing: 12) {
            if let deny = hint.deny {
                part(keys: deny, title: denyTitle)
            }
            if let approve = hint.approve {
                part(keys: approve, title: approveTitle)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 12)
        .accessibilityElement(children: .combine)
    }

    private func part(keys: String, title: String) -> some View {
        HStack(spacing: 5) {
            Text(keys)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(V6Palette.paper.opacity(0.66))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(V6Palette.paper.opacity(0.42))
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - What it did

enum AgentTurnSummaryMetrics {
    /// Height the one-line summary adds to a finished row in the list.
    static let rowHeight: CGFloat = 23
    /// Height the folded summary and its divider add to a completion card.
    static let cardHeight: CGFloat = 33
    /// How many files and commands the unfolded card lists before it says
    /// how many more there are.
    static let fileLimit = 6
    static let commandLimit = 4
}

/// One fact of the one-line summary.
enum AgentTurnSummaryPart: Equatable, Sendable {
    case duration(String)
    case files(Int)
    case commands(Int)
    case testsRan

    /// The facts worth a place on the line, most telling first. A count of
    /// zero is left out, and a count the hooks cannot back is never made.
    static func parts(for summary: AgentTurnSummary) -> [AgentTurnSummaryPart] {
        var parts: [AgentTurnSummaryPart] = [.duration(AgentTurnRules.durationText(summary.duration))]
        if case let .files(files) = summary.fileEdits, !files.isEmpty {
            parts.append(.files(files.count))
        }
        if !summary.commands.isEmpty {
            parts.append(.commands(summary.commands.count))
        }
        if !summary.testCommands.isEmpty {
            parts.append(.testsRan)
        }
        return parts
    }

    func text(_ lang: LanguageManager) -> String {
        switch self {
        case let .duration(text): text
        case let .files(count): Self.counted("agentSummary.files", count, lang)
        case let .commands(count): Self.counted("agentSummary.commands", count, lang)
        case .testsRan: lang.t("agentSummary.testsRan")
        }
    }

    /// "1 file" and "3 files" are two strings, which lets every language
    /// word each its own way.
    static func counted(_ key: String, _ count: Int, _ lang: LanguageManager) -> String {
        count == 1 ? lang.t("\(key).one") : lang.t("\(key).other", count)
    }
}

/// What a session did since the user's last prompt. One line in a list row.
/// In a completion card the line unfolds into the files and the commands.
struct AgentTurnSummaryView: View {
    enum Style {
        case row
        case card
    }

    let summary: AgentTurnSummary
    var lang: LanguageManager
    var style: Style

    @State private var showsDetails: Bool

    /// `startsUnfolded` opens a card on its details at once, for previews
    /// and render checks. In the island a card starts folded.
    init(
        summary: AgentTurnSummary,
        lang: LanguageManager = .shared,
        style: Style,
        startsUnfolded: Bool = false
    ) {
        self.summary = summary
        self.lang = lang
        self.style = style
        _showsDetails = State(initialValue: startsUnfolded)
    }

    var body: some View {
        switch style {
        case .row:
            lineText
                .frame(maxWidth: .infinity, alignment: .leading)
        case .card:
            card
        }
    }

    private var line: String {
        AgentTurnSummaryPart.parts(for: summary).map { $0.text(lang) }.joined(separator: " · ")
    }

    /// The clock marks the line as a look back at the work, apart from the
    /// agent's own last words above it.
    private var lineText: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock")
                .font(.system(size: 9, weight: .semibold))
            Text(line)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(V6Palette.paper.opacity(0.46))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(lang.t("agentSummary.title")): \(line)")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withMotion(Motion.selection) { showsDetails.toggle() }
            } label: {
                HStack(spacing: 8) {
                    lineText
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                        .rotationEffect(.degrees(showsDetails ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .frame(height: AgentTurnSummaryMetrics.cardHeight - 1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(lang.t(showsDetails ? "agentSummary.hideDetails" : "agentSummary.showDetails"))

            if showsDetails {
                details
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang.t("agentSummary.title"))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))

            if case let .files(files) = summary.fileEdits, !files.isEmpty {
                detailBlock(lang.t("agentSummary.detail.files")) {
                    ForEach(Array(files.prefix(AgentTurnSummaryMetrics.fileLimit).enumerated()), id: \.offset) { _, path in
                        detailLine(AgentTurnRules.fileName(path), monospaced: true)
                            .help(path)
                    }
                    moreLine(files.count - AgentTurnSummaryMetrics.fileLimit)
                }
            }

            if !summary.commands.isEmpty {
                detailBlock(lang.t("agentSummary.detail.commands")) {
                    ForEach(Array(summary.commands.prefix(AgentTurnSummaryMetrics.commandLimit).enumerated()), id: \.offset) { _, command in
                        detailLine("$ \(AgentTurnRules.oneLine(command))", monospaced: true)
                    }
                    moreLine(summary.commands.count - AgentTurnSummaryMetrics.commandLimit)
                }
            }

            if !summary.testCommands.isEmpty {
                detailBlock(lang.t("agentSummary.detail.tests")) {
                    ForEach(Array(summary.testCommands.prefix(2).enumerated()), id: \.offset) { _, command in
                        detailLine("$ \(AgentTurnRules.oneLine(command))", monospaced: true)
                    }
                    moreLine(summary.testCommands.count - 2)
                }
            }

            if let asked = summary.permissionRequests, asked > 0 {
                detailLine(
                    AgentTurnSummaryPart.counted("agentSummary.permissions", asked, lang),
                    monospaced: false
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailBlock(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
            content()
        }
    }

    private func detailLine(_ text: String, monospaced: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: monospaced ? .monospaced : .default))
            .foregroundStyle(.white.opacity(0.74))
            .lineLimit(1)
            .truncationMode(.middle)
    }

    @ViewBuilder
    private func moreLine(_ hidden: Int) -> some View {
        if hidden > 0 {
            Text(lang.t("agentSummary.more", hidden))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}
