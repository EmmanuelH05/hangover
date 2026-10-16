import SwiftUI

/// Sizes of the Convert strip, in a plain enum and not the View: a closure
/// in a View static traps when a nonisolated test reads it.
///
/// The strip has one fixed height, because the window is sized from it
/// (`NookPageExtras`). It holds the title row, the line that explains, and
/// room for the rows of buttons. A picture in a card this narrow wraps its
/// format row and its size row onto two lines each (more so in Chinese,
/// where the button titles are longer), which is the tallest case, and a
/// video with its three rows of one line is the next.
enum NookConvertStripLayout {
    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 12
    static let titleRowHeight: CGFloat = 18
    static let explainHeight: CGFloat = 14
    /// The gap between the explain line and the first row.
    static let headerGap: CGFloat = 8
    static let buttonHeight: CGFloat = 22
    /// Between buttons, and between the lines of a row that wraps.
    static let buttonSpacing: CGFloat = 6
    /// Between one group's row and the next.
    static let groupSpacing: CGFloat = 8
    /// The width kept for a row's name, which sits left of its buttons.
    static let groupLabelWidth: CGFloat = 48
    static let groupLabelGap: CGFloat = 8
    /// A file has at most this many groups, and the rows together are
    /// sized for this many lines of buttons.
    static let maxGroupRows = 3
    static let maxButtonLines = 4

    /// Room for the rows: the most lines of buttons, with a group gap
    /// between the rows and a button gap between wrapped lines.
    static var rowsHeight: CGFloat {
        let lines = CGFloat(maxButtonLines)
        let groupGaps = CGFloat(maxGroupRows - 1)
        let wrapGaps = CGFloat(max(0, maxButtonLines - maxGroupRows))
        return lines * buttonHeight + groupGaps * groupSpacing + wrapGaps * buttonSpacing
    }

    /// What the content inside the padding may take.
    static var contentHeight: CGFloat {
        titleRowHeight + explainHeight + headerGap + rowsHeight
    }

    static var height: CGFloat { contentHeight + verticalPadding * 2 }

    static var pageHeight: CGFloat { height + NookWidgetLayout.rowSpacing }
}

/// One row of the strip: a group and what the file can become in it.
struct NookConvertStripGroup: Equatable, Identifiable {
    let group: NookConvertGroup
    let actions: [NookConvertAction]

    var id: NookConvertGroup { group }
}

enum NookConvertStripRules {
    /// The rows for a file's actions, in the order of the Convert menu and
    /// leaving out a group with nothing in it.
    static func groups(for actions: [NookConvertAction]) -> [NookConvertStripGroup] {
        NookConvertGroup.allCases.compactMap { group in
            let inGroup = actions.filter { $0.group == group }
            return inGroup.isEmpty ? nil : NookConvertStripGroup(group: group, actions: inGroup)
        }
    }
}

extension NookConvertAction {
    /// The words on this action's button in the Convert strip and its line
    /// in a file's right click menu.
    var menuTitle: String { menuTitle(in: LanguageManager.shared.bundle) }

    /// The same words from another language's strings, for the tests that
    /// check every language without switching the app's.
    func menuTitle(in bundle: Bundle) -> String {
        let format = bundle.localizedString(forKey: titleKey, value: titleKey, table: nil)
        guard let titleArgument else { return format }
        return String(format: format, titleArgument)
    }
}

/// The tray's Convert choices for one file, shown above the cards at the
/// page's full width the way the GIF options are (`NookGIFStrip`). A tray
/// card at any size is too short for them.
struct NookConvertStrip: View {
    let tray: NookTrayStore
    let source: NookTrayItem

    var body: some View {
        let url = tray.storedURL(for: source)
        NookConvertStripContent(
            sourceName: source.originalName,
            actions: NookConvertRules.actions(forFileNamed: source.originalName, at: url),
            usesFirstFrame: NookConvertRules.isAnimatedGIF(at: url),
            waitingOn: tray.convertBlocker?.originalName,
            bundle: LanguageManager.shared.bundle,
            onChoose: { tray.chooseConversion($0, for: source) },
            onCancel: { tray.cancelConvertStrip() }
        )
        .padding(.horizontal, NookConvertStripLayout.horizontalPadding)
        .padding(.vertical, NookConvertStripLayout.verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NookCardBackground())
    }
}

/// What the strip shows inside its padding, kept apart from the tray store
/// so a test can lay it out with any file's actions and any language.
struct NookConvertStripContent: View {
    let sourceName: String
    let actions: [NookConvertAction]
    /// True for a GIF with several pictures, of which only the first is
    /// converted.
    let usesFirstFrame: Bool
    /// The name of the file a conversion is still running on, when that is
    /// this file. The buttons wait for it and say so.
    let waitingOn: String?
    let bundle: Bundle
    let onChoose: (NookConvertAction) -> Void
    let onCancel: () -> Void

    private func word(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleRow
            Text(word("nook.tray.convert.strip.explain"))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(height: NookConvertStripLayout.explainHeight, alignment: .leading)
                .padding(.bottom, NookConvertStripLayout.headerGap)
            VStack(alignment: .leading, spacing: NookConvertStripLayout.groupSpacing) {
                ForEach(NookConvertStripRules.groups(for: actions)) { entry in
                    row(entry)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: Title

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(String(format: word("nook.tray.convert.strip.title"), sourceName))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if usesFirstFrame {
                Text(word("nook.tray.convert.firstFrameOnly"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .fixedSize()
            }
            cancelButton
        }
        .frame(height: NookConvertStripLayout.titleRowHeight)
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            Text(word("nook.tray.convert.cancel"))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(height: NookConvertStripLayout.titleRowHeight)
                .background(Capsule().fill(Color.white.opacity(0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Rows

    /// A group's name on the left, and its buttons beside it, wrapping onto
    /// more lines when they do not fit.
    private func row(_ entry: NookConvertStripGroup) -> some View {
        HStack(alignment: .top, spacing: NookConvertStripLayout.groupLabelGap) {
            Text(word(entry.group.titleKey).uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.35))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(
                    width: NookConvertStripLayout.groupLabelWidth,
                    height: NookConvertStripLayout.buttonHeight,
                    alignment: .leading
                )
            NookConvertButtonFlow(spacing: NookConvertStripLayout.buttonSpacing) {
                ForEach(entry.actions, id: \.self) { action in
                    NookConvertChoiceButton(
                        title: action.menuTitle(in: bundle),
                        waitingOn: waitingOn
                    ) { onChoose(action) }
                }
            }
        }
    }
}

/// One capsule for one thing the file can become. It goes dim while a
/// conversion still reads the file, and its help text says which one.
private struct NookConvertChoiceButton: View {
    let title: String
    let waitingOn: String?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        let isWaiting = waitingOn != nil
        let help = waitingOn.map { NookConvertRules.waitText(forBusyFileNamed: $0) } ?? ""
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(height: NookConvertStripLayout.buttonHeight)
                .background(Capsule().fill(Color.white.opacity(isHovering && !isWaiting ? 0.22 : 0.12)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isWaiting)
        .opacity(isWaiting ? 0.4 : 1)
        .help(help)
        .onHover { isHovering = $0 }
    }
}

/// Lays buttons out left to right and starts a new line when the next one
/// does not fit. Every button keeps its own width.
struct NookConvertButtonFlow: Layout {
    var spacing: CGFloat

    /// One line: the buttons on it, as indices, and the room it takes.
    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(_ subviews: Subviews, width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var current = Line()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let widthWithIt = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if widthWithIt > width, !current.indices.isEmpty {
                lines.append(current)
                current = Line(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width = widthWithIt
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { lines.append(current) }
        return lines
    }

    /// The width to wrap at: the one proposed, or one line's worth when no
    /// edge is proposed, as a stack asks to find out how wide this can be.
    private func wrapWidth(_ proposal: ProposedViewSize, _ subviews: Subviews) -> CGFloat {
        if let width = proposal.width, width.isFinite { return max(0, width) }
        let widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        return widths.reduce(0, +) + spacing * CGFloat(max(0, widths.count - 1))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = wrapWidth(proposal, subviews)
        let rows = lines(subviews, width: width)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        var y = bounds.minY
        for line in lines(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + spacing
        }
    }
}
