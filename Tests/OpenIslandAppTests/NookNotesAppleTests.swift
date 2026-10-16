import Foundation
import Testing
@testable import OpenIslandApp

/// Notes sent to Apple Notes (D70): kept in Hangover's own record, or in
/// files and the Notes app both. The Notes app is a fake; no AppleScript runs.
@MainActor
@Suite struct NookNotesAppleTests {
    // MARK: The note as HTML

    @Test func theFirstLineIsTheTitleAndEachLineIsItsOwnDiv() {
        let html = NookAppleNotesBody.html(from: "Groceries\nmilk\n\neggs")

        #expect(html == "<div><h1>Groceries</h1></div><div>milk</div><div><br></div><div>eggs</div>")
    }

    @Test func blankLinesAboveTheTitleAreLeftOut() {
        #expect(NookAppleNotesBody.html(from: "\n\n  Title  \nbody") == "<div><h1>Title</h1></div><div>body</div>")
    }

    @Test func typedTextIsNeverReadAsMarkup() {
        let html = NookAppleNotesBody.html(from: "a <b>bold</b> & <script>x</script>\nline <i>2</i>")

        #expect(html == "<div><h1>a &lt;b&gt;bold&lt;/b&gt; &amp; &lt;script&gt;x&lt;/script&gt;</h1></div><div>line &lt;i&gt;2&lt;/i&gt;</div>")
    }

    @Test func windowsLineEndingsAreOneBreak() {
        #expect(NookAppleNotesBody.html(from: "A\r\nB") == "<div><h1>A</h1></div><div>B</div>")
    }

    // MARK: The scripts

    @Test func theScriptsTakeEverythingTypedAsAnArgument() {
        for script in [NookAppleNotesScripts.create, NookAppleNotesScripts.update, NookAppleNotesScripts.delete] {
            #expect(script.contains("item 1 of argv"))
            // Nothing typed is ever pasted into a script's own text.
            #expect(!script.contains("\\("))
        }
        #expect(NookAppleNotesScripts.create.contains("item 2 of argv"))
        #expect(NookAppleNotesScripts.update.contains("item 2 of argv"))
    }

    @Test func theNotesGoInAFolderCalledHangover() {
        #expect(NookAppleNotesBody.folderName == "Hangover")
        #expect(NookAppleNotesScripts.create.contains("make new folder"))
        #expect(NookAppleNotesScripts.create.contains("make new note at theFolder"))
        #expect(NookAppleNotesScripts.create.contains("return id of newNote"))
    }

    @Test func aRefusalByMacOSIsToldApartFromOtherFailures() {
        let denied = "execution error: Not authorized to send Apple events to Notes. (-1743)"

        #expect(NookAppleNotesScriptBridge.error(forStandardError: denied) == .notPermitted)
        #expect(NookAppleNotesScriptBridge.error(forStandardError: "execution error: Notes got an error (-10000)") == .failed)
        #expect(NookAppleNotesScriptBridge.error(forStandardError: "") == .failed)
    }

    // MARK: Apple Notes only

    @Test func eachNoteIsItsOwnAppleNoteAndIsUpdatedNotRemade() async {
        let harness = NookNotesHarness()
        let store = harness.makeStore(saveTo: .appleNotes)

        store.beginNewNote()
        store.edit("Call mom")
        store.flush()
        await harness.settle(store)
        store.edit("Call mom\nat six")
        store.flush()
        await harness.settle(store)

        #expect(harness.bridge.calls == [
            .create(html: "<div><h1>Call mom</h1></div>"),
            .update(id: "apple-1", html: "<div><h1>Call mom</h1></div><div>at six</div>"),
        ])
        #expect(harness.fileNames().isEmpty, "nothing goes to a folder")
    }

    @Test func twoNotesAreTwoAppleNotes() async {
        let harness = NookNotesHarness()
        let store = harness.makeStore(saveTo: .appleNotes)

        store.beginNewNote()
        store.edit("One")
        store.flush()
        harness.date = harness.date.addingTimeInterval(60)
        store.beginNewNote()
        store.edit("Two")
        store.flush()
        await harness.settle(store)

        #expect(harness.bridge.createCount == 2)
        #expect(store.notes.map(\.title) == ["Two", "One"])
    }

    @Test func theListComesFromHangoversOwnRecordAndSurvivesARestart() async {
        let harness = NookNotesHarness()
        let first = harness.makeStore(saveTo: .appleNotes)
        first.beginNewNote()
        first.edit("Kept in the record")
        first.flush()
        await harness.settle(first)

        let second = harness.makeStore()

        #expect(second.notes.map(\.title) == ["Kept in the record"])
        // And the Apple note is found again: this is an update.
        second.open(second.notes[0].id)
        second.edit("Kept in the record\nmore")
        second.flush()
        await harness.settle(second)
        #expect(harness.bridge.createCount == 1)
        #expect(harness.bridge.calls.count == 2)
    }

    @Test func editsMadeInAppleNotesDoNotComeBack() async {
        let harness = NookNotesHarness()
        let store = harness.makeStore(saveTo: .appleNotes)
        store.beginNewNote()
        store.edit("Mine")
        store.flush()
        await harness.settle(store)

        store.reload()

        // The record is the list; the fake has no way to hand text back.
        #expect(store.notes.map(\.text) == ["Mine"])
    }

    @Test func aNoteDeletedInHangoverIsDeletedInAppleNotes() async {
        let harness = NookNotesHarness()
        let store = harness.makeStore(saveTo: .appleNotes)
        store.beginNewNote()
        store.edit("Short lived")
        store.closeEditor()
        await harness.settle(store)

        store.delete(store.notes[0].id)
        await harness.settle(store)

        #expect(store.notes.isEmpty)
        #expect(harness.bridge.calls.last == .delete(id: "apple-1"))
    }

    @Test func aNoteDeletedBeforeItsAppleNoteWasMadeLeavesNothingBehind() async {
        let harness = NookNotesHarness()
        harness.bridge.slowDown()
        let store = harness.makeStore(saveTo: .appleNotes)
        store.beginNewNote()
        store.edit("Quick come and gone")
        store.closeEditor()

        // The send for the first save is still on its way.
        store.delete(store.notes[0].id)
        await harness.settle(store)

        #expect(harness.bridge.calls == [
            .create(html: "<div><h1>Quick come and gone</h1></div>"),
            .delete(id: "apple-1"),
        ])
    }

    @Test func anAppleNoteTheUserDeletedInNotesIsMadeAgain() async {
        let harness = NookNotesHarness()
        let store = harness.makeStore(saveTo: .appleNotes)
        store.beginNewNote()
        store.edit("Gone in Notes")
        store.flush()
        await harness.settle(store)
        harness.bridge.forget("apple-1")

        store.edit("Gone in Notes\nback again")
        store.flush()
        await harness.settle(store)

        #expect(harness.bridge.createCount == 2)
    }

    @Test func sendsGoOutOneAtATimeAndInOrder() async {
        let harness = NookNotesHarness()
        harness.bridge.slowDown()
        let store = harness.makeStore(saveTo: .appleNotes)
        store.beginNewNote()

        for text in ["First", "First\nSecond", "First\nSecond\nThird"] {
            store.edit(text)
            store.flush()
        }
        await harness.settle(store)

        #expect(harness.bridge.mostAtOnce == 1)
        #expect(harness.bridge.calls.count == 3)
        #expect(harness.bridge.createCount == 1, "one Apple note, updated twice")
    }

    // MARK: A refusal

    @Test func aRefusalLeavesTheNoteInTheRecordAndSaysWhyOnce() async {
        let harness = NookNotesHarness()
        harness.bridge.fail(with: .notPermitted)
        let store = harness.makeStore(saveTo: .appleNotes)

        store.beginNewNote()
        store.edit("Refused")
        store.flush()
        await harness.settle(store)
        store.edit("Refused again")
        store.flush()
        await harness.settle(store)

        #expect(store.notes.map(\.title) == ["Refused again"])
        #expect(harness.notices == [.appleNotesOff(keptIn: .hangover)], "said once")
    }

    @Test func aRefusalInBothStillSavesTheFile() async {
        let harness = NookNotesHarness()
        harness.bridge.fail(with: .notPermitted)
        let store = harness.makeStore(saveTo: .both)

        store.beginNewNote()
        store.edit("File first")
        store.flush()
        await harness.settle(store)

        #expect(harness.fileNames() == ["File first.md"])
        #expect(harness.notices == [.appleNotesOff(keptIn: .folder)])
    }

    @Test func anotherFailureHasItsOwnNotice() async {
        let harness = NookNotesHarness()
        harness.bridge.fail(with: .failed)
        let store = harness.makeStore(saveTo: .both)

        store.beginNewNote()
        store.edit("Odd failure")
        store.flush()
        await harness.settle(store)

        #expect(harness.notices == [.appleNotesFailed(keptIn: .folder)])
    }

    @Test func theNoticeComesBackAfterASendThatWorked() async {
        let harness = NookNotesHarness()
        harness.bridge.fail(with: .failed)
        let store = harness.makeStore(saveTo: .both)
        store.beginNewNote()
        store.edit("A")
        store.flush()
        await harness.settle(store)

        harness.bridge.fail(with: nil)
        store.edit("AB")
        store.flush()
        await harness.settle(store)
        harness.bridge.fail(with: .failed)
        store.edit("ABC")
        store.flush()
        await harness.settle(store)

        #expect(harness.notices.count == 2)
    }

    // MARK: The first question from macOS

    @Test func theFirstSendCountsAsAPromptAndLaterOnesDoNot() async {
        let harness = NookNotesHarness()
        let store = harness.makeStore(saveTo: .appleNotes)

        store.beginNewNote()
        store.edit("First send")
        store.flush()
        await harness.settle(store)
        #expect(harness.prompts == [true, false])
        #expect(store.hasNotesAnswer)

        store.edit("First send\nand more")
        store.flush()
        await harness.settle(store)
        #expect(harness.prompts == [true, false], "no second dip of the island")
    }

    @Test func aRefusalIsAnAnswerToo() async {
        let harness = NookNotesHarness()
        harness.bridge.fail(with: .notPermitted)
        let store = harness.makeStore(saveTo: .appleNotes)

        store.beginNewNote()
        store.edit("Refused")
        store.flush()
        await harness.settle(store)

        #expect(store.hasNotesAnswer)
        #expect(harness.prompts == [true, false])
    }

    @Test func aFailureThatIsNotARefusalIsNotAnAnswer() async {
        let harness = NookNotesHarness()
        harness.bridge.fail(with: .failed)
        let store = harness.makeStore(saveTo: .appleNotes)

        store.beginNewNote()
        store.edit("Odd")
        store.flush()
        await harness.settle(store)

        #expect(!store.hasNotesAnswer)
    }

    @Test func aFolderOnlyStoreNeverTouchesTheNotesApp() async {
        let harness = NookNotesHarness()
        let store = harness.makeStore(saveTo: .folder)

        store.beginNewNote()
        store.edit("Files only")
        store.flush()
        await harness.settle(store)

        #expect(harness.bridge.calls.isEmpty)
        #expect(harness.prompts.isEmpty)
    }

    // MARK: Both

    @Test func bothKeepsAFileAndAnAppleNote() async {
        let harness = NookNotesHarness()
        let store = harness.makeStore(saveTo: .both)

        store.beginNewNote()
        store.edit("Both places")
        store.flush()
        await harness.settle(store)

        #expect(harness.fileNames() == ["Both places.md"])
        #expect(harness.bridge.calls == [.create(html: "<div><h1>Both places</h1></div>")])
    }

    @Test func aRenamedFileKeepsItsAppleNote() async {
        let harness = NookNotesHarness()
        let store = harness.makeStore(saveTo: .both)
        store.beginNewNote()
        store.edit("Old title\nbody")
        store.flush()
        await harness.settle(store)

        store.edit("New title\nbody")
        store.flush()
        await harness.settle(store)

        #expect(harness.fileNames() == ["New title.md"])
        #expect(harness.bridge.createCount == 1, "the Apple note followed the file to its new name")
        #expect(harness.bridge.calls.last == .update(id: "apple-1", html: "<div><h1>New title</h1></div><div>body</div>"))
    }

    @Test func aRenameBeforeTheFirstSendIsDoneStillMakesOneAppleNote() async {
        let harness = NookNotesHarness()
        harness.bridge.slowDown()
        let store = harness.makeStore(saveTo: .both)
        store.beginNewNote()
        store.edit("First title")
        store.flush()
        store.edit("Second title")
        store.flush()
        await harness.settle(store)

        #expect(harness.bridge.createCount == 1)
        #expect(harness.fileNames() == ["Second title.md"])
    }

    @Test func aFileDeletedInHangoverDeletesItsAppleNote() async {
        let harness = NookNotesHarness()
        let store = harness.makeStore(saveTo: .both)
        store.beginNewNote()
        store.edit("Both and gone")
        store.closeEditor()
        await harness.settle(store)

        store.delete("Both and gone.md")
        await harness.settle(store)

        #expect(harness.trashed() == ["Both and gone.md"])
        #expect(harness.bridge.calls.last == .delete(id: "apple-1"))
    }

    @Test func twoFoldersDoNotShareAnAppleNoteForANoteOfTheSameName() async {
        let harness = NookNotesHarness()
        let store = harness.makeStore(saveTo: .both)
        store.beginNewNote()
        store.edit("Same name")
        store.closeEditor()
        await harness.settle(store)

        store.setFolder(harness.home.appendingPathComponent("Elsewhere", isDirectory: true))
        store.beginNewNote()
        store.edit("Same name")
        store.closeEditor()
        await harness.settle(store)

        #expect(harness.bridge.createCount == 2)
    }
}
