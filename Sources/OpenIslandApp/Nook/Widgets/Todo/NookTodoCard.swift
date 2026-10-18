import SwiftUI

struct NookTodoCard: View {
    var nook: NookModel
    @Environment(\.hangoverAccent) var accent

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

    @Environment(\.nookWidgetSize) var size

    @State var draft = ""
    /// Medium and large: the day picked for the next task, if any (D69).
    @State var dueDraft: DateComponents?
    /// The date picker's popover is up.
    @State var isPickingDate = false
    /// A typed task was handed to the source, which has not answered yet.
    @State var isSending = false
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

    /// The source a typed task goes to (B7). With one app on it is the
    /// card's only source.
    private var source: any NookTodoSource { nook.todo.source(reminders: nook.reminders) }

    /// Two or more apps are on: sections, dots and the add chip (T12).
    var isGrouped: Bool { nook.todo.hasManyEnabled }

    /// The source that holds a task, for the notes page. With several apps
    /// on it is the one the task came from, not the add target.
    private func notesSource(holding id: String?) -> any NookTodoSource {
        let add = source
        guard isGrouped, let id, let held = nook.todo.source(holding: id, reminders: nook.reminders) else { return add }
        return held
    }

    var body: some View {
        let source = source
        let notesSource = notesSource(holding: openItemID)
        let openItem = Self.openItem(openItemID, in: notesSource)
        VStack(alignment: .leading, spacing: 6) {
            if let openItem {
                detail(openItem, source: notesSource)
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
            if isGrouped {
                for section in nook.todo.sections(reminders: nook.reminders) { section.source.refresh() }
            } else {
                source.refresh()
            }
            // Reminders access is asked for here, the first time the tile
            // is in the user's view, and not at launch.
            nook.widgetsCameIntoView()
        }
        // Closing the island with the notes page open still saves the draft.
        .onDisappear {
            leaveNotesPage()
            isAdding = false
            // A popover that went with the card must not keep the island from closing (D7).
            nook.todo.isPickingDate = false
        }
        .onChange(of: size) { _, _ in isAdding = false }
        .task(id: nook.todo.enabledKinds) { await autoRefresh() }
        .onChange(of: nook.todo.selectedKind) { old, new in
            leaveNotesPage()
            // A day picked for one source is not carried to another (D3).
            dueDraft = NookTodoAdding.pickedDay(dueDraft, afterSourceChangedFrom: old, to: new)
        }
        .onChange(of: openItem?.notes) { old, new in
            followRemoteNotes(from: old, to: new, source: notesSource)
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
        let source = notesSource(holding: id)
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
        let followed = Self.followingRemoteNotes(
            from: old, to: new, draft: notesDraft, base: notesBase, source: source
        )
        notesDraft = followed.draft
        notesBase = followed.base
    }

    /// The draft and the base the notes page holds once the source's notes
    /// moved from `old` to `new` while the page is open.
    static func followingRemoteNotes(
        from old: String?, to new: String?, draft: String, base: String?, source: any NookTodoSource
    ) -> (draft: String, base: String?) {
        if (new ?? "") == draft {
            // The draft was saved, or the other edit matches it.
            return (draft, new)
        }
        if source.notesSaveFailed {
            // A failed save put the old notes back. The draft stays for
            // another try. Any other problem on the source says nothing
            // about the notes, and the page follows as it would with none.
            return (draft, new)
        }
        if draft == (old ?? "") {
            // An untouched draft follows the source.
            return (new ?? "", new)
        }
        // Otherwise the draft is being edited and the task changed
        // elsewhere: the base stays behind, which marks the conflict.
        return (draft, base)
    }

    // MARK: List

    @ViewBuilder
    private func list(_ source: any NookTodoSource) -> some View {
        if isGrouped {
            groupedList(nook.todo.sections(reminders: nook.reminders))
        } else if size == .small {
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
        HStack(spacing: 6) {
            addField(source)
                .onSubmit { addTyped(source) }
                .demoTyping(.todo, text: $draft) { addTyped(source) }
            dueControl(source)
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

    /// Return in the add field of the medium and large cards.
    private func addTyped(_ source: any NookTodoSource) {
        guard source.canAdd else { return }
        sendTyped(source, whenAdded: {})
    }

    /// Hands the typed task and the picked day to the source. The title and
    /// the day stay in the field until the source says it took the task. A
    /// failed add loses neither, and the source's error line says why
    /// (D2). Only then is the field cleared and the button back to no date.
    /// A blank line adds nothing and is cleared. Return again while the
    /// source is still answering does nothing, which keeps a task from being
    /// added twice.
    func sendTyped(_ source: any NookTodoSource, whenAdded: @escaping () -> Void) {
        guard !isSending else { return }
        let sent = draft
        let sentDue = NookTodoAdding.dayToSend(picked: dueDraft, isSmall: size == .small, canSetDue: source.canSetDue)
        guard NookDraft.isUnsaved(sent) else {
            draft = ""
            return
        }
        isSending = true
        Task { @MainActor in
            let added = await NookTodoAdding.submit(draft: sent, due: sentDue, to: source)
            isSending = false
            let fields = NookTodoAdding.fields(
                afterAdding: added, sent: sent, sentDue: sentDue, draft: draft, dueDraft: dueDraft
            )
            draft = fields.draft
            dueDraft = fields.dueDraft
            if added { whenAdded() }
        }
    }

    static func rowLimit(for size: NookWidgetSize, hasNotice: Bool) -> Int {
        maxRows(for: size) - (hasNotice ? 1 : 0)
    }

    func addField(_ source: any NookTodoSource) -> some View {
        TextField(source.addPlaceholder, text: $draft)
            .textFieldStyle(.plain)
            .tint(accent.controlTint)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.leading, 8)
            // Room for the chip, which names the app a typed task goes to.
            .padding(.trailing, isGrouped ? Self.chipRoom : 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.08)))
            .overlay(alignment: .trailing) {
                if isGrouped {
                    NookTodoAddChip(hub: nook.todo)
                        .padding(.trailing, 4)
                }
            }
            .disabled(!source.canAdd)
            .onChange(of: draft) { _, text in nook.setDraft(.todo, isUnsaved: NookDraft.isUnsaved(text) || isPickingDate) }
            .onDisappear { nook.setDraft(.todo, isUnsaved: false) }
            .demoTarget(.todoField)
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
        // With several apps on, every one that polls is asked on the
        // shortest interval; each service spaces its own refreshes.
        let polling = nook.todo.sections(reminders: nook.reminders)
            .map(\.source)
            .filter { $0.autoRefreshInterval != nil }
        guard let interval = polling.compactMap(\.autoRefreshInterval).min() else { return }
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
            for source in polling { source.refreshOnTimer() }
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
    func row(
        _ item: NookTodoItem, source: any NookTodoSource, showsDue: Bool = true, position: Int? = nil
    ) -> some View {
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
                NookTodoTick(isChecked: isFading)
            }
            .buttonStyle(.plain)
            .disabled(!source.canComplete)
            .demoTarget(.todoCheck(position: position ?? source.items.firstIndex { $0.id == item.id } ?? -1))
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
                            // A date range is red once its end has passed (D9).
                            .foregroundStyle(Self.isOverdue(item.overdueDate ?? due) ? Color.red : .white.opacity(0.35))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .opacity(isFading ? 0 : 1)
    }
}

/// What Return does with the add field of the medium and large cards (D69).
@MainActor
enum NookTodoAdding {
    /// Hands the typed task to the source, with the picked day when the
    /// source can keep one, and waits for its answer. A blank title adds
    /// nothing and does not use up a picked day. True when the source
    /// took the task; false leaves the title and the day with the caller.
    static func submit(draft: String, due: DateComponents?, to source: any NookTodoSource) async -> Bool {
        guard source.canAdd, NookDraft.isUnsaved(draft) else { return false }
        let day = source.canSetDue ? NookTodoDay.normalized(due) : nil
        return await source.addConfirmed(draft, due: day)
    }

    /// The day that goes with the task: the picked one, while the card has a
    /// date button (not the small size) and the source can keep a day right
    /// now. A day the source cannot take is not sent, and it is not used up
    /// either: it stays picked for when the source can (D3).
    static func dayToSend(picked: DateComponents?, isSmall: Bool, canSetDue: Bool) -> DateComponents? {
        isSmall || !canSetDue ? nil : picked
    }

    /// The picked day after the source in use changed. A day picked for one
    /// source is dropped when another takes its place. The same source going
    /// offline or rate limited for a while, and coming back, keeps it (D3).
    static func pickedDay(
        _ picked: DateComponents?, afterSourceChangedFrom old: NookTodoSourceKind, to new: NookTodoSourceKind
    ) -> DateComponents? {
        old == new ? picked : nil
    }

    /// The add field and the date button once the source answered. A task the
    /// source refused leaves both as they are. One it took clears the title
    /// and the day that were sent, but not text typed since Return: that is
    /// the next task's.
    static func fields(
        afterAdding added: Bool,
        sent: String,
        sentDue: DateComponents?,
        draft: String,
        dueDraft: DateComponents?
    ) -> (draft: String, dueDraft: DateComponents?) {
        guard added else { return (draft, dueDraft) }
        return (draft == sent ? "" : draft, dueDraft == sentDue ? nil : dueDraft)
    }
}

/// The circle at the front of a task. A task just checked off shows a tick,
/// which takes the accent when one is set.
struct NookTodoTick: View {
    let isChecked: Bool

    @Environment(\.hangoverAccent) var accent

    var body: some View {
        Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 12))
            .foregroundStyle(isChecked ? accent.highlight(.white.opacity(0.6)) : .white.opacity(0.6))
    }
}
