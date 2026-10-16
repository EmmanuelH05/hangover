import Foundation
import Testing
@testable import OpenIslandApp

// The tour's notes page (D40, D44, D70): where notes are saved. Nothing here
// opens a window or a panel, runs `osascript`, or writes outside a temporary
// folder. The store gets a `MemoryDefaults`, a fake for Notes and folders in
// the temporary folder.

@MainActor
struct OnboardingNotesTests {
    // MARK: The page follows the widget

    @Test func theNotesPageIsLeftOutWhileTheNotesWidgetIsOff() {
        let with = OnboardingPage.shown(agentsEnabled: true, hasNotesWidget: true)
        let without = OnboardingPage.shown(agentsEnabled: true, hasNotesWidget: false)

        #expect(with == OnboardingPage.mainTour)
        #expect(without == OnboardingPage.mainTour.filter { $0 != .notes })
        #expect(OnboardingPage.allCases.filter(\.needsNotesWidget) == [.notes])
        #expect(OnboardingPage.notes.isLive)
        #expect(OnboardingPage.notes.chapter == .yours)
        // It sits right after the to-dos page.
        #expect(OnboardingPage.todos.next == .notes)
        #expect(OnboardingPage.landing(.notes, in: without) == .todos)
    }

    @Test func theTourWalksPastTheNotesPageWhileTheWidgetIsOffThePage() {
        var widgets = Set(NookWidgetKind.defaultEnabled)
        let tour = OnboardingTour(startingAt: .todos, state: { OnboardingState(enabledWidgets: widgets) })
        tour.next()
        #expect(tour.page == .notes)

        tour.back()
        widgets.remove(.notes)
        #expect(!tour.pages.contains(.notes))
        tour.next()
        #expect(tour.page == .opened)
    }

    // MARK: The pick

    @Test func thePageOffersTheThreeChoicesInOrder() {
        #expect(NookNotesSaveTo.allCases == [.folder, .appleNotes, .both])
        #expect(NookNotesSaveTo.allCases.map(\.rawValue) == ["folder", "appleNotes", "both"])
    }

    @Test func aPickWritesThePreferenceSettingsWrites() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        #expect(store.saveTo == .folder)
        #expect(harness.defaults.string(forKey: NookNotesStore.saveToKey) == nil)

        // What the tour's door does with the pick (`setNotesSaveTo`).
        store.setSaveTo(.both)
        #expect(harness.defaults.string(forKey: NookNotesStore.saveToKey) == "both")
        #expect(harness.makeStore(start: false).saveTo == .both)

        store.setSaveTo(.appleNotes)
        #expect(harness.defaults.string(forKey: NookNotesStore.saveToKey) == "appleNotes")
    }

    @Test func theToursPickReachesTheAppOnce() {
        var picks: [NookNotesSaveTo] = []
        let tour = OnboardingTour(
            startingAt: .notes,
            state: { OnboardingState() },
            actions: OnboardingActions(setNotesSaveTo: { picks.append($0) })
        )
        tour.actions.setNotesSaveTo(.both)
        #expect(picks == [.both])
    }

    @Test func theAppWiresThePageToTheStoreSettingsUses() throws {
        let source = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/AppModel+Onboarding.swift")
        #expect(source.contains("setNotesSaveTo: { [weak self] in self?.nook.notes.setSaveTo($0) }"))
        #expect(source.contains("nook.notes.setFolder(folder)"))
        #expect(source.contains("await connector.allowReminders()"))
        #expect(source.contains("await connector.connect(token: token)"))
    }

    // MARK: The folder

    @Test func aFreshInstallKeepsNotesInAVisibleFolderAndTheTourPrintsIt() {
        let harness = NookNotesHarness(folderIsSet: false)
        let store = harness.makeStore(start: false)

        #expect(store.folderURL.path.hasSuffix("/Documents/Hangover Notes"))
        let printed = (store.folderURL.path as NSString).abbreviatingWithTildeInPath
        #expect(printed.hasSuffix("Hangover Notes"))
    }

    @Test func aChosenFolderIsUsedForEveryNoteAfterIt() throws {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        let vault = harness.home.appendingPathComponent("Vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)

        store.setFolder(vault)

        #expect(store.folderURL == vault)
        #expect(harness.defaults.string(forKey: NookNotesStore.folderKey) == vault.path)

        store.beginNewNote()
        store.edit("buy milk")
        store.closeEditor()
        #expect(try FileManager.default.contentsOfDirectory(atPath: vault.path) == ["buy milk.md"])
        // A store started later reads the same folder.
        #expect(harness.makeStore(start: false).folderURL == vault)
    }

    @Test func aFolderChosenOverNotesAlreadyThereShowsThem() throws {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        let vault = harness.home.appendingPathComponent("Vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try "# Mine\n\nkeep this\n".write(to: vault.appendingPathComponent("Mine.md"), atomically: true, encoding: .utf8)

        store.setFolder(vault)

        #expect(store.notes.map(\.title) == ["Mine"])
    }

    // MARK: Try it

    @Test func theSavedCountGrowsWhenANoteIsSaved() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        #expect(store.savedCount == 0)

        store.beginNewNote()
        store.edit("one")
        store.flush()
        store.edit("one two")
        store.flush()
        store.beginNewNote()
        store.edit("   ")
        store.closeEditor()

        #expect(store.savedCount == 2, "a blank note saves nothing")
    }

    @Test func theSavedCountGrowsWhenNotesHasTheNoteForAppleNotesOnly() async {
        let harness = NookNotesHarness()
        harness.bridge.slowDown()
        let store = harness.makeStore(saveTo: .appleNotes)

        store.beginNewNote()
        store.edit("to notes")
        store.flush()
        #expect(store.savedCount == 0, "the note is only in Hangover's record: the tour must not say Saved yet")
        await harness.settle(store)

        #expect(store.savedCount == 1, "Notes took it")
    }

    @Test func aNoteNotesRefusedStillCounts() async {
        let harness = NookNotesHarness()
        harness.bridge.fail(with: .notPermitted)
        let store = harness.makeStore(saveTo: .both)

        store.beginNewNote()
        store.edit("refused")
        store.flush()
        await harness.settle(store)

        #expect(store.savedCount == 1)
        #expect(harness.fileNames() == ["refused.md"])
    }

    @Test func theTryItStepTicksOnlyForANoteSavedWhileThePageIsUp() {
        var saved = 3
        let tour = OnboardingTour(startingAt: .opened, state: {
            var state = OnboardingState()
            state.notesSavedCount = saved
            return state
        })
        #expect(!tour.state.hasSavedNote)

        tour.back()
        #expect(tour.page == .notes)
        #expect(!tour.state.hasSavedNote, "notes saved before the page came up do not count")

        saved += 1
        #expect(tour.state.hasSavedNote)

        // Leaving and coming back starts the step over.
        tour.next()
        #expect(!tour.state.hasSavedNote)
        tour.back()
        #expect(!tour.state.hasSavedNote)
    }

    @Test func aSnapshotCanHandInATickedStep() {
        var state = OnboardingState()
        state.hasSavedNote = true
        let tour = OnboardingTour(startingAt: .notes, state: { state })
        #expect(tour.state.hasSavedNote)
    }

    // MARK: Words

    @Test func theNotesPageNamesTheFolderTheAppMakesInNotesAndTheObsidianFolder() throws {
        let english = try HangoverBrandTests.table("en")
        let appleNotes = try #require(english["onboarding.notes.appleNotes.where"])
        #expect(appleNotes.contains("%@"))
        #expect(NookAppleNotesBody.folderName == "Hangover")
        #expect(appleNotes.contains("do not come back, and are replaced"))
        #expect(try #require(english["onboarding.notes.folder.any"]).contains("Obsidian"))
        #expect(try #require(english["onboarding.notes.appleNotes.ask"]).contains("asks once"))
    }

    @Test func theFoldersChooserOpensWhereNotesAreSaved() throws {
        let source = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/AppModel+Onboarding.swift")
        #expect(source.contains("NookNoteLocations.pickerStart("))
    }

    @Test func theRecapNamesTheChoice() throws {
        let english = try HangoverBrandTests.table("en")
        for choice in NookNotesSaveTo.allCases {
            #expect(english[OnboardingNotesGuide.titleKey(for: choice)] != nil)
            #expect(english[OnboardingNotesGuide.textKey(for: choice)] != nil)
            #expect(english[OnboardingNotesGuide.showKey(for: choice)] != nil)
        }
        #expect(OnboardingRecapRow.notes.rawValue == "notes")
        #expect(english["onboarding.done.recap.notes"] != nil)
    }

    @Test func eachChoiceHasItsOwnSymbol() {
        let symbols = NookNotesSaveTo.allCases.map(OnboardingNotesGuide.symbol(for:))
        #expect(Set(symbols).count == 3)
    }
}
