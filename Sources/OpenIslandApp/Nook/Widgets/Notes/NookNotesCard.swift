import SwiftUI

/// The Notes widget (D70): the notes, newest edit first, with a New note
/// button. A click on a note opens it in the editor, which takes the card's
/// place until it is closed. With the widget off the page the editor is
/// pinned above the grid instead (`NookPinnedNoteEditor`).
struct NookNotesCard: View {
    var nook: NookModel
    /// Swaps what `ImageRenderer` cannot draw (the scrolling list, the text
    /// editor) for plain look-alikes, for the render tests.
    var isStill = false

    static let height: CGFloat = 120

    /// Height at each size. Small rows always use the grid’s shared height.
    static func height(for size: NookWidgetSize) -> CGFloat {
        switch size {
        case .small: NookWidgetLayout.smallHeight
        case .medium: height
        case .large: 220
        }
    }

    @Environment(\.nookWidgetSize) private var size

    var body: some View {
        let store = nook.notes
        VStack(alignment: .leading, spacing: 6) {
            if store.isEditorOpen {
                NookNoteEditorHeader(store: store)
                NookNoteEditor(store: store, isStill: isStill)
            } else {
                listHeader(store)
                // The line takes the room of a row.
                let problem = store.shownProblem
                if let problem {
                    NookNotesProblemLine(store: store, notice: problem)
                }
                NookNotesList(
                    store: store,
                    rows: max(1, NookNoteListRules.rowCount(for: size) - (problem == nil ? 0 : 1)),
                    isStill: isStill
                )
                Spacer(minLength: 0)
                if size == .large {
                    Text(Self.savesToLine(store))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NookCardBackground())
        // The island opened on this page: a folder watcher that did not start
        // is tried again, and the list is read in case it missed something (N9).
        .onAppear { store.islandOpened() }
    }

    private func listHeader(_ store: NookNotesStore) -> some View {
        let lang = LanguageManager.shared
        return HStack(spacing: 6) {
            Image(systemName: "note.text")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Text(lang.t("nook.notes.title").uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.5))
            Spacer(minLength: 0)
            Button {
                withMotion(Motion.reflow) { store.beginNewNote() }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                    // Small is half the page wide: the plus alone.
                    if size != .small {
                        Text(lang.t("nook.notes.new"))
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, size == .small ? 6 : 8)
                .frame(height: 18)
                .background(Capsule().fill(.white.opacity(0.1)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(lang.t("nook.notes.new.help"))
            .accessibilityLabel(lang.t("nook.notes.new"))
            .demoTarget(.notesField)
        }
    }

    /// The line under the large card's list: where notes are saved.
    static func savesToLine(_ store: NookNotesStore) -> String {
        let lang = LanguageManager.shared
        let folder = (store.folderURL.path as NSString).abbreviatingWithTildeInPath
        switch store.saveTo {
        case .folder: return lang.t("nook.notes.savesTo.folder", folder)
        case .appleNotes: return lang.t("nook.notes.savesTo.appleNotes")
        case .both: return lang.t("nook.notes.savesTo.both", folder)
        }
    }
}

/// The notes in a list that scrolls when there are more than the card
/// shows rows.
struct NookNotesList: View {
    var store: NookNotesStore
    let rows: Int
    var isStill = false

    var body: some View {
        let lang = LanguageManager.shared
        if store.notes.isEmpty {
            if NookNoteListRules.showsEmptyState(notes: store.notes, problem: store.problem) {
                Text(Self.emptyText(store.hotkey, lang: lang))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, minHeight: NookNoteSizes.rowHeight, alignment: .leading)
            }
        } else if isStill {
            // The rows, one under another, with no scrolling around them.
            rowsView(now: Date())
        } else {
            // Ages are said in minutes, so the list is drawn again each one.
            TimelineView(.everyMinute) { context in
                ScrollView(.vertical) {
                    rowsView(now: context.date)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: Self.height(rows: rows))
            }
        }
    }

    /// What an empty list says: the shortcut only when it works (N11).
    static func emptyText(_ hotkey: NookNoteHotkeyController, lang: LanguageManager) -> String {
        switch NookNoteListRules.emptyLine(hotkey: hotkey.status) {
        case .shortcut: lang.t(NookNoteListRules.EmptyLine.shortcut.key, hotkey.displayText)
        case .settings: lang.t(NookNoteListRules.EmptyLine.settings.key)
        }
    }

    /// The height of the rows a card shows and no more.
    static func height(rows: Int) -> CGFloat {
        CGFloat(rows) * NookNoteSizes.rowHeight + CGFloat(max(0, rows - 1)) * NookNoteSizes.rowSpacing
    }

    private func rowsView(now: Date) -> some View {
        VStack(alignment: .leading, spacing: NookNoteSizes.rowSpacing) {
            ForEach(isStill ? Array(store.notes.prefix(rows)) : store.notes) { note in
                NookNoteRow(note: note, now: now) {
                    withMotion(Motion.reflow) { store.open(note.id) }
                } onDelete: {
                    store.delete(note.id)
                }
            }
        }
    }
}

/// One note in the list: its title and how long ago it was edited. A click
/// opens it; the context menu deletes it.
struct NookNoteRow: View {
    let note: NookNote
    let now: Date
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    /// What the right of a row says: how long ago, or why there is no age.
    static func ageOrState(of note: NookNote, age: String, lang: LanguageManager) -> String {
        switch note.state {
        case .readable: age
        case .unreadable: lang.t("nook.notes.row.unreadable")
        case .downloading: lang.t("nook.notes.row.downloading")
        }
    }

    var body: some View {
        let lang = LanguageManager.shared
        let title = NookNoteListRules.rowTitle(for: note, untitled: lang.t("nook.notes.untitled"))
        let age = NookNoteListRules.ageText(
            of: note.updated, now: now, calendar: .current,
            locale: Locale(identifier: lang.language.resolvedCode), string: { lang.t($0) }
        )
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Text(Self.ageOrState(of: note, age: age, lang: lang))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(note.state == .unreadable ? Color.orange : .white.opacity(note.state == .downloading ? 0.55 : 0.35))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(height: NookNoteSizes.rowHeight)
            .padding(.horizontal, NookNoteSizes.rowInset)
            .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(isHovering ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The row's text lines up with the header above it; only the
        // highlight reaches past it.
        .padding(.horizontal, -NookNoteSizes.rowInset)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(lang.t("nook.notes.delete"), role: .destructive, action: onDelete)
        }
        .accessibilityLabel(title)
        .accessibilityValue(age)
        .accessibilityHint(lang.t("nook.notes.row.hint"))
    }
}
