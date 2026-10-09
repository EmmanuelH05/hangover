import SwiftUI

/// The small layout of the todo card: a header with a plus button, up to
/// three rows, and an add field that takes the list's place on request.
/// Medium and large share the original layout in `NookTodoCard.swift`.
extension NookTodoCard {
    /// Hit area of the plus button; also the header height.
    private static let headerButtonSize: CGFloat = 22
    /// The plus icon sits this far inside its hit area, so the icon lines
    /// up with the right edge of the rows below.
    private static let headerButtonInset: CGFloat = 6

    @ViewBuilder
    func smallList(_ source: any NookTodoSource) -> some View {
        smallHeader(source)
        switch source.connection {
        case .ready:
            if isAdding, source.canAdd {
                smallAddField(source)
            } else {
                smallRows(source)
            }
        case .unavailable(let message):
            unavailable(message)
        }
    }

    // MARK: Header

    private func smallHeader(_ source: any NookTodoSource) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checklist")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Text("Todo".uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 0)
            // The source name gives way first when the header is tight.
            Text(Self.headerTrailing(source))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
                .lineLimit(1)
                .truncationMode(.tail)
            if source.connection == .ready, source.canAdd {
                addToggle
            }
        }
        .frame(height: Self.headerButtonSize)
    }

    /// Plus opens the add field; the same spot closes it again.
    private var addToggle: some View {
        let label = isAdding ? "Cancel" : "Add a task"
        return Button {
            if isAdding {
                closeAdd()
            } else {
                isAdding = true
            }
        } label: {
            Image(systemName: isAdding ? "xmark" : "plus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: Self.headerButtonSize, height: Self.headerButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, -Self.headerButtonInset)
        .help(label)
        .accessibilityLabel(label)
    }

    // MARK: Rows

    @ViewBuilder
    private func smallRows(_ source: any NookTodoSource) -> some View {
        let notice = source.errorMessage
        if source.items.isEmpty {
            allClear
        } else {
            VStack(alignment: .leading, spacing: 3) {
                // The notice takes the place of the last row.
                ForEach(source.items.prefix(Self.rowLimit(for: .small, hasNotice: notice != nil))) { item in
                    // The due label stays only when title and label both fit.
                    ViewThatFits(in: .horizontal) {
                        row(item, source: source, showsDue: true)
                        row(item, source: source, showsDue: false)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        if let notice {
            noticeLabel(notice)
        }
    }

    // MARK: Add field

    @ViewBuilder
    private func smallAddField(_ source: any NookTodoSource) -> some View {
        addField(source)
            .focused($isAddFocused)
            .onSubmit { submitAdd(source) }
            .onExitCommand(perform: closeAdd)
            .onAppear { isAddFocused = true }
        Text("Return adds, Esc cancels")
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.35))
        Spacer(minLength: 0)
    }

    /// Return: adds a non-empty title and goes back to the list.
    private func submitAdd(_ source: any NookTodoSource) {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.canAdd, !title.isEmpty {
            source.add(draft)
        }
        closeAdd()
    }

    /// Escape, the close button, or after an add: back to the list.
    private func closeAdd() {
        draft = ""
        isAdding = false
        isAddFocused = false
    }
}
