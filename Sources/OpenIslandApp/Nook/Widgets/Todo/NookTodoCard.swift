import SwiftUI

struct NookTodoCard: View {
    var nook: NookModel

    static let height: CGFloat = 140

    /// Height at each size. Small rows always use the grid’s shared height.
    static func height(for size: NookWidgetSize) -> CGFloat {
        switch size {
        case .small: NookWidgetLayout.smallHeight
        case .medium: height
        case .large: 220
        }
    }

    /// Open items shown at each size.
    static func maxRows(for size: NookWidgetSize) -> Int {
        switch size {
        case .small: 3
        case .medium: 4
        case .large: 8
        }
    }
    private static let maxHeaderNameLength = 24
    private static let fadeDuration: Duration = .milliseconds(250)

    @Environment(\.nookWidgetSize) private var size

    @State var draft = ""
    @State var fading: Set<String> = []
    /// Small size only: the add field has taken the list's place.
    @State var isAdding = false
    @FocusState var isAddFocused: Bool
    /// The task whose notes page is showing, if any.
    @State private var openItemID: String?
    @State private var notesDraft = ""
    /// The source's notes when the draft last matched them. A different
    /// value at save time means someone else edited the task.
    @State private var notesBase: String?

    private var source: any NookTodoSource { nook.todo.source(reminders: nook.reminders) }

    var body: some View {
        let source = source
        let openItem = Self.openItem(openItemID, in: source)
        VStack(alignment: .leading, spacing: 6) {
            if let openItem {
                detail(openItem, source: source)
            } else {
                list(source)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NookCardBackground())
        // Picks up access granted in System Settings while the island was
        // closed, and reloads a remote source when the island opens.
        .onAppear {
            source.refresh()
            // Reminders access is asked for here, the first time the tile
            // is in the user's view, and not at launch.
            nook.widgetsCameIntoView()
        }
        // Closing the island with the notes page open still saves the draft.
        .onDisappear {
            leaveNotesPage()
            isAdding = false
        }
        .onChange(of: size) { _, _ in isAdding = false }
        .task(id: nook.todo.selectedKind) { await autoRefresh() }
        .onChange(of: nook.todo.selectedKind) { _, _ in leaveNotesPage() }
        .onChange(of: openItem?.notes) { old, new in
            followRemoteNotes(from: old, to: new, source: source)
        }
        .onChange(of: openItem == nil) { _, isGone in
            // The task was completed or removed elsewhere: back to the list.
            if isGone { leaveNotesPage() }
        }
    }

    /// The task behind the open notes page, while the source still has it.
    static func openItem(_ id: String?, in source: any NookTodoSource) -> NookTodoItem? {
        guard let id, source.connection == .ready else { return nil }
        return source.items.first { $0.id == id }
    }

    // MARK: Notes page

    private func detail(_ item: NookTodoItem, source: any NookTodoSource) -> some View {
        let isDirty = notesDraft != (item.notes ?? "")
        return NookTodoDetailPage(
            item: item,
            canEdit: source.canEditNotes,
            footnote: Self.footnote(source: source, hasConflict: isDirty && item.notes != notesBase),
            hasUnsavedChanges: isDirty,
            draft: $notesDraft,
            // Save is the explicit choice, also when the task changed elsewhere.
            onSave: { saveNotes(overwritingRemoteChanges: true) },
            onBack: leaveNotesPage
        )
    }

    private static func footnote(source: any NookTodoSource, hasConflict: Bool) -> String? {
        guard source.canEditNotes else { return source.notesUnavailableReason }
        if let error = source.errorMessage { return error }
        return hasConflict ? LanguageManager.shared.t("nook.todo.notes.conflict") : nil
    }

    private func open(_ item: NookTodoItem) {
        // Text that did not save last time comes back before the saved notes.
        notesDraft = nook.todo.noteDrafts[item.id] ?? item.notes ?? ""
        notesBase = item.notes
        openItemID = item.id
    }

    /// Writes the draft back when it differs from what the source holds.
    /// Whatever cannot be written is kept in `noteDrafts`, never dropped:
    /// a read-only source, a task that changed elsewhere, a task that left
    /// the list. A failed write hands its text back the same way.
    private func saveNotes(overwritingRemoteChanges: Bool) {
        guard let id = openItemID else { return }
        let source = source
        let hub = nook.todo
        guard let item = Self.openItem(id, in: source) else {
            if notesDraft != (notesBase ?? "") { hub.noteDrafts[id] = notesDraft }
            return
        }
        guard notesDraft != (item.notes ?? "") else {
            hub.noteDrafts[id] = nil
            return
        }
        hub.noteDrafts[id] = notesDraft
        let changedElsewhere = item.notes != notesBase
        guard source.canEditNotes, overwritingRemoteChanges || !changedElsewhere else { return }
        source.setNotes(notesDraft, for: id)
        // A source that writes at once shows the new text already. One that
        // writes in the background reports back through the hub.
        if (Self.openItem(id, in: source)?.notes ?? "") == notesDraft {
            hub.noteDrafts[id] = nil
        }
    }

    /// Back, Escape, the island closing, the task leaving the list, or the
    /// source changing.
    private func leaveNotesPage() {
        guard openItemID != nil else { return }
        saveNotes(overwritingRemoteChanges: false)
        openItemID = nil
    }

    /// Notes changed at the source while the page is open.
    private func followRemoteNotes(from old: String?, to new: String?, source: any NookTodoSource) {
        guard Self.openItem(openItemID, in: source) != nil else { return }
        if (new ?? "") == notesDraft {
            // The draft was saved, or the other edit matches it.
            notesBase = new
        } else if source.errorMessage != nil {
            // A failed save put the old notes back. The draft stays for
            // another try.
            notesBase = new
        } else if notesDraft == (old ?? "") {
            // An untouched draft follows the source.
            notesDraft = new ?? ""
            notesBase = new
        }
        // Otherwise the draft is being edited and the task changed
        // elsewhere: the base stays behind, which marks the conflict.
    }

    // MARK: List

    @ViewBuilder
    private func list(_ source: any NookTodoSource) -> some View {
        if size == .small {
            smallList(source)
        } else {
            NookCardHeader(title: "Todo", systemImage: "checklist", trailing: Self.headerTrailing(source))
            switch source.connection {
            case .ready:
                content(source)
            case .unavailable(let message):
                unavailable(message)
            }
        }
    }

    /// Medium and large: the add field on top, then the rows.
    @ViewBuilder
    private func content(_ source: any NookTodoSource) -> some View {
        let notice = source.errorMessage
        addField(source)
            .onSubmit {
                guard source.canAdd else { return }
                source.add(draft)
                draft = ""
            }
        if source.items.isEmpty {
            allClear
        } else {
            VStack(alignment: .leading, spacing: 3) {
                // The notice takes the place of the last row.
                ForEach(source.items.prefix(Self.rowLimit(for: size, hasNotice: notice != nil))) { item in
                    row(item, source: source)
                }
            }
            Spacer(minLength: 0)
        }
        if let notice {
            noticeLabel(notice)
        }
    }

    static func rowLimit(for size: NookWidgetSize, hasNotice: Bool) -> Int {
        maxRows(for: size) - (hasNotice ? 1 : 0)
    }

    func addField(_ source: any NookTodoSource) -> some View {
        TextField(source.addPlaceholder, text: $draft)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.08)))
            .disabled(!source.canAdd)
    }

    @ViewBuilder
    func unavailable(_ message: String) -> some View {
        Spacer(minLength: 0)
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.35))
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .frame(maxWidth: .infinity)
        Spacer(minLength: 0)
    }

    @ViewBuilder
    var allClear: some View {
        Spacer(minLength: 0)
        Text("All clear")
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.35))
            .frame(maxWidth: .infinity)
        Spacer(minLength: 0)
    }

    func noticeLabel(_ notice: String) -> some View {
        Label(notice, systemImage: "exclamationmark.triangle")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.orange.opacity(0.9))
            .lineLimit(1)
    }

    /// Repeats while the card is on screen, for sources that need polling.
    private func autoRefresh() async {
        guard let interval = source.autoRefreshInterval else { return }
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
            source.refreshOnTimer()
        }
    }

    static func headerTrailing(_ source: any NookTodoSource) -> String {
        var name = source.displayName
        if name.count > maxHeaderNameLength {
            name = name.prefix(maxHeaderNameLength - 1) + "…"
        }
        guard source.isShowingCachedItems else { return name }
        return name + " · " + LanguageManager.shared.t("nook.todo.offline")
    }

    /// One task. The small size passes `showsDue: false` when the label
    /// would not fit beside the title.
    func row(_ item: NookTodoItem, source: any NookTodoSource, showsDue: Bool = true) -> some View {
        let isFading = fading.contains(item.id)
        return HStack(spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.25)) { _ = fading.insert(item.id) }
                Task { @MainActor in
                    try? await Task.sleep(for: Self.fadeDuration)
                    source.complete(item.id)
                    fading.remove(item.id)
                }
            } label: {
                Image(systemName: isFading ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .disabled(!source.canComplete)
            // Everything right of the circle opens the task's notes page.
            Button {
                open(item)
            } label: {
                HStack(spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    if nook.todo.noteDrafts[item.id] != nil {
                        // A note for this task is waiting to be saved.
                        Image(systemName: "note.text")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.orange.opacity(0.9))
                    } else if item.notes?.isEmpty == false {
                        Image(systemName: "note.text")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    Spacer(minLength: 4)
                    if showsDue, let due = item.dueDate {
                        Text(Self.dueLabel(due))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Self.isOverdue(due) ? Color.red : .white.opacity(0.35))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .opacity(isFading ? 0 : 1)
    }
}
