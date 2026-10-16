import Foundation
import Testing
@testable import OpenIslandApp

/// The notes page follows a change made at the source while it is open, and a
/// problem that has nothing to do with notes does not stop it (D2 of the third
/// review fixes). What the page holds when it closes is written back, which
/// means a draft that stayed behind the source would overwrite the other edit.
@MainActor
@Suite struct NookTodoNotesFollowTests {
    private func source(error: String? = nil, notesSaveFailed: Bool = false) -> NookTodoDueFakeSource {
        let source = NookTodoDueFakeSource()
        source.errorMessage = error
        source.notesSaveFailed = notesSaveFailed
        return source
    }

    private func follow(
        from old: String?, to new: String?, draft: String, base: String?, source: NookTodoDueFakeSource
    ) -> (draft: String, base: String?) {
        NookTodoCard.followingRemoteNotes(from: old, to: new, draft: draft, base: base, source: source)
    }

    // MARK: A problem that is not about notes

    @Test func aFailedAddDoesNotKeepAnUntouchedPageFromFollowingARemoteEdit() {
        let source = source(error: "Could not add the reminder")

        let page = follow(from: "old", to: "remote", draft: "old", base: "old", source: source)

        #expect(page.draft == "remote", "leaving would otherwise write the old notes over the remote ones")
        #expect(page.base == "remote")
    }

    @Test func aMissingDateWarningDoesNotKeepAnEmptyPageFromFollowingARemoteEdit() {
        let source = source(error: "Added without its date.")

        let page = follow(from: nil, to: "remote", draft: "", base: nil, source: source)

        #expect(page.draft == "remote")
        #expect(page.base == "remote")
    }

    @Test func aRemoteEditStillMarksAConflictWithATypedDraftUnderAnyOtherProblem() {
        let source = source(error: "Could not add the reminder")

        let page = follow(from: "old", to: "remote", draft: "typed", base: "old", source: source)

        #expect(page.draft == "typed")
        #expect(page.base == "old", "the base stays behind, which marks the conflict")
    }

    // MARK: A notes save that failed

    @Test func aFailedNotesSaveKeepsTheDraftForAnotherTry() {
        let source = source(error: "Could not save the notes.", notesSaveFailed: true)

        // The row had taken "typed" and put "old" back when the save failed.
        let page = follow(from: "typed", to: "old", draft: "typed", base: "typed", source: source)

        #expect(page.draft == "typed")
        #expect(page.base == "old")
    }

    // MARK: With no problem

    @Test func anUntouchedPageFollowsARemoteEdit() {
        let page = follow(from: "old", to: "remote", draft: "old", base: "old", source: source())

        #expect(page.draft == "remote")
        #expect(page.base == "remote")
    }

    @Test func aSavedDraftMovesTheBaseToWhatWasSaved() {
        let page = follow(from: "old", to: "typed", draft: "typed", base: "old", source: source())

        #expect(page.draft == "typed")
        #expect(page.base == "typed")
    }

    @Test func aTypedDraftIsNotReplacedByARemoteEdit() {
        let page = follow(from: "old", to: "remote", draft: "typed", base: "old", source: source())

        #expect(page.draft == "typed")
        #expect(page.base == "old")
    }
}
