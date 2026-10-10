import Foundation
import Testing
@testable import OpenIslandApp

// The tour's notes page (D40, D44): where quick notes go. Nothing here opens
// a window or a panel, runs `osascript`, or writes outside a temporary folder.
// The services get a `MemoryDefaults`, a stub for Notes and a file in the
// temporary folder.

@MainActor
struct OnboardingNotesTests {
    // MARK: The page follows the widget

    @Test func theNotesPageIsLeftOutWhileTheNotesWidgetIsOff() {
        let with = OnboardingPage.shown(agentsEnabled: true, hasNotesWidget: true)
        let without = OnboardingPage.shown(agentsEnabled: true, hasNotesWidget: false)

        #expect(with == OnboardingPage.allCases)
        #expect(without == OnboardingPage.allCases.filter { $0 != .notes })
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

    @Test func aPickWritesThePreferenceSettingsWrites() {
        let harness = NookAppleNotesTests.Harness()
        let service = harness.makeService()
        #expect(service.destination == .file)
        #expect(harness.defaults.string(forKey: NookNotesService.destinationDefaultsKey) == nil)

        // What the tour's door does with the pick (`setNotesDestination`).
        service.setDestination(.appleNotes)
        #expect(harness.defaults.string(forKey: NookNotesService.destinationDefaultsKey) == "appleNotes")
        #expect(harness.makeService().destination == .appleNotes)

        service.setDestination(.file)
        #expect(harness.defaults.string(forKey: NookNotesService.destinationDefaultsKey) == "file")
    }

    @Test func theToursPickReachesTheAppOnce() {
        var picks: [NookNotesDestination] = []
        let tour = OnboardingTour(
            startingAt: .notes,
            state: { OnboardingState() },
            actions: OnboardingActions(setNotesDestination: { picks.append($0) })
        )
        tour.actions.setNotesDestination(.appleNotes)
        #expect(picks == [.appleNotes])
    }

    @Test func theAppWiresThePageToTheServicesSettingsUses() throws {
        let source = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/AppModel+Onboarding.swift")
        #expect(source.contains("setNotesDestination: { [weak self] in self?.nook.notes.setDestination($0) }"))
        #expect(source.contains("nook.notes.setFolder(folder)"))
        #expect(source.contains("await connector.allowReminders()"))
        #expect(source.contains("await connector.connect(token: token)"))
    }

    // MARK: The folder

    @Test func aFreshInstallKeepsTheDefaultFileAndStoresNoPath() {
        let defaults: UserDefaults = MemoryDefaults()
        let service = NookNotesService(defaults: defaults, appleNotes: StubAppleNotesWriter())

        #expect(service.fileURL.path.hasSuffix("/Library/Application Support/OpenIsland/Notes/Quick Notes.md"))
        #expect(service.fileURL.lastPathComponent == NookNotesService.folderFileName)
        #expect(defaults.string(forKey: NookNotesService.pathDefaultsKey) == nil)
    }

    @Test func aChosenFolderHoldsTheFileAndIsUsedForEveryNoteAfterIt() throws {
        let harness = NookAppleNotesTests.Harness()
        let service = harness.makeService()
        let vault = harness.directory.appendingPathComponent("Vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)

        service.setFolder(vault)

        let file = vault.appendingPathComponent("Quick Notes.md")
        #expect(service.fileURL == file)
        #expect(harness.defaults.string(forKey: NookNotesService.pathDefaultsKey) == file.path)
        #expect(FileManager.default.fileExists(atPath: file.path), "the file is made at once, so Finder can show it")

        service.append("buy milk")
        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(written.contains("buy milk"))
        // A service started later reads the same folder.
        let later = NookNotesService(defaults: harness.defaults, appleNotes: StubAppleNotesWriter())
        #expect(later.fileURL.path == file.path)
    }

    @Test func aFolderChosenOverNotesAlreadyThereKeepsThem() throws {
        let harness = NookAppleNotesTests.Harness()
        let service = harness.makeService()
        let vault = harness.directory.appendingPathComponent("Vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let file = vault.appendingPathComponent("Quick Notes.md")
        try "# Mine\n\nkeep this\n".write(to: file, atomically: true, encoding: .utf8)

        service.setFolder(vault)
        service.append("and this")

        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(written.hasPrefix("# Mine\n\nkeep this\n"))
        #expect(written.contains("and this"))
    }

    // MARK: Try it

    @Test func theSavedCountGrowsWhenANoteIsSavedToTheFile() {
        let harness = NookAppleNotesTests.Harness()
        let service = harness.makeService()
        #expect(service.savedCount == 0)

        service.append("one")
        service.append("two")
        service.append("   ")

        #expect(service.savedCount == 2, "a blank line saves nothing")
    }

    @Test func theSavedCountGrowsWhenAppleNotesTakesTheNoteButNotBefore() async {
        let harness = NookAppleNotesTests.Harness()
        harness.writer.slowDown()
        let service = harness.makeService()
        service.setDestination(.appleNotes)

        service.append("to notes")
        #expect(service.savedCount == 0, "the note is only on its way")
        await harness.settle(service)

        #expect(service.savedCount == 1)
    }

    @Test func aNoteNotesRefusedStillCountsOnceItIsInTheFile() async {
        let harness = NookAppleNotesTests.Harness()
        harness.writer.fail(with: .notPermitted)
        let service = harness.makeService()
        service.setDestination(.appleNotes)

        service.append("refused")
        await harness.settle(service)

        #expect(service.savedCount == 1)
        #expect(harness.fileText().contains("refused"))
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

    @Test func theNotesPageNamesTheNoteTheAppTitlesAndTheFileItMakes() throws {
        let english = try HangoverBrandTests.table("en")
        let appleNotes = try #require(english["onboarding.notes.appleNotes.where"])
        #expect(appleNotes.contains("%@"))
        #expect(NookAppleNotesLine.noteTitle == "Quick Notes")
        #expect(try #require(english["onboarding.notes.file.any"]).contains("Obsidian"))
        #expect(try #require(english["onboarding.notes.file.any"]).contains(NookNotesService.folderFileName))
        #expect(try #require(english["onboarding.notes.appleNotes.ask"]).contains("asks once"))
    }

    @Test func theRecapNamesTheChoice() throws {
        let english = try HangoverBrandTests.table("en")
        for destination in NookNotesDestination.allCases {
            #expect(english[OnboardingNotesGuide.titleKey(for: destination)] != nil)
        }
        #expect(OnboardingRecapRow.notes.rawValue == "notes")
        #expect(english["onboarding.done.recap.notes"] != nil)
    }
}
