import SwiftUI

/// The page a task opens to inside the todo card: its title, due date and
/// notes. The card owns the draft and decides when to save.
struct NookTodoDetailPage: View {
    let item: NookTodoItem
    let canEdit: Bool
    /// Shown under the notes: a failed save, or why notes are read-only.
    let footnote: String?
    let hasUnsavedChanges: Bool
    @Binding var draft: String
    var onSave: () -> Void
    var onBack: () -> Void

    private static let editorInset: CGFloat = 5
    private static let cornerRadius: CGFloat = 8

    @FocusState private var isEditing: Bool

    private var lang: LanguageManager { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            notes
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: Self.cornerRadius).fill(.white.opacity(0.06)))
            if let footnote {
                Label(footnote, systemImage: canEdit ? "exclamationmark.triangle" : "lock")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(canEdit ? Color.orange.opacity(0.9) : .white.opacity(0.35))
                    .lineLimit(1)
            }
        }
        .onExitCommand(perform: onBack)
        .onAppear { isEditing = canEdit }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(lang.t("nook.todo.notes.back"))
            .accessibilityLabel(lang.t("nook.todo.notes.back"))
            Text(item.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if hasUnsavedChanges, canEdit {
                Button(lang.t("nook.todo.notes.save"), action: onSave)
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            if let due = item.dueDate {
                Text(NookTodoCard.dueLabel(due))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NookTodoCard.isOverdue(due) ? Color.red : .white.opacity(0.35))
            }
        }
    }

    @ViewBuilder
    private var notes: some View {
        if canEdit {
            TextEditor(text: $draft)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
                .scrollContentBackground(.hidden)
                .focused($isEditing)
                .padding(.vertical, 4)
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty {
                        placeholder(lang.t("nook.todo.notes.placeholder"))
                            .padding(.leading, Self.editorInset)
                            .padding(.top, 4)
                    }
                }
        } else if !draft.isEmpty {
            // The draft, not the saved notes: after editing turns off, what
            // was typed stays readable and can be copied.
            ScrollView {
                Text(draft)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Self.editorInset)
                    .padding(.vertical, 4)
            }
        } else {
            placeholder(lang.t("nook.todo.notes.empty"))
                .padding(.horizontal, Self.editorInset)
                .padding(.vertical, 4)
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.35))
            .allowsHitTesting(false)
    }
}
