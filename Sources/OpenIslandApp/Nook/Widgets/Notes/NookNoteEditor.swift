import SwiftUI

/// The text of the open note (D70): as many lines as the note has, Return
/// makes a new line, and there is no save button. The store saves a moment
/// after the last key, and when the editor closes.
///
/// The view keeps the text it shows in its own state. The store does not
/// publish its copy, which keeps a keystroke from drawing the page again.
struct NookNoteEditor: View {
    var store: NookNotesStore
    /// Draws the text as plain text, for the render tests, which cannot draw
    /// a text editor.
    var isStill = false
    @Environment(\.hangoverAccent) private var accent

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        if isStill { stillText } else { editor }
    }

    private var editor: some View {
        TextEditor(text: $text)
            .tint(accent.controlTint)
            .font(.system(size: 12))
            .lineSpacing(2)
            .foregroundStyle(.white.opacity(0.9))
            .scrollContentBackground(.hidden)
            .focused($isFocused)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.08)))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(LanguageManager.shared.t("nook.notes.editor.placeholder"))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel(LanguageManager.shared.t("nook.notes.editor.label"))
            .onAppear {
                text = store.editorText
                isFocused = true
            }
            // A note opened, or a file changed under an editor with nothing
            // unsaved in it.
            .onChange(of: store.editorRevision) { _, _ in text = store.editorText }
            .onChange(of: store.focusRequest) { _, _ in isFocused = true }
            .onChange(of: text) { _, typed in store.edit(typed) }
            .onKeyPress(.escape) {
                withMotion(Motion.reflow) { store.closeEditor() }
                return .handled
            }
            .onExitCommand { withMotion(Motion.reflow) { store.closeEditor() } }
            .onDisappear { store.flush() }
            .demoTarget(.notesField)
            .demoTyping(.note, text: $text) { _ = store.flush() }
    }

    private var stillText: some View {
        let shown = store.editorText.isEmpty
            ? LanguageManager.shared.t("nook.notes.editor.placeholder")
            : store.editorText
        return Text(shown)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(store.editorText.isEmpty ? 0.35 : 0.9))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.08)))
    }
}

/// The editor pinned above the grid when the Notes widget is not on the
/// page (D70): a card of its own with a title row and a close button. The
/// island shows it the way it shows the event editor.
struct NookPinnedNoteEditor: View {
    var nook: NookModel
    var isStill = false

    var body: some View {
        let store = nook.notes
        VStack(alignment: .leading, spacing: 6) {
            NookNoteEditorHeader(store: store)
            NookNoteEditor(store: store, isStill: isStill)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NookCardBackground())
    }
}

/// The title row over an open note: what the card is, and the close button.
struct NookNoteEditorHeader: View {
    var store: NookNotesStore

    var body: some View {
        let lang = LanguageManager.shared
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Text(lang.t("nook.notes.title").uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 0)
                Button {
                    withMotion(Motion.reflow) { store.closeEditor() }
                } label: {
                    Text(lang.t("nook.notes.done"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 8)
                        .frame(height: 18)
                        .background(Capsule().fill(.white.opacity(0.1)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(lang.t("nook.notes.done.help"))
            }
            // Why Done and the shortcut do nothing, in a place that is open.
            if let problem = store.shownProblem {
                NookNotesProblemLine(store: store, notice: problem)
            }
        }
    }
}
