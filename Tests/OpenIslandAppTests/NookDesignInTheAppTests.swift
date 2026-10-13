import AppKit
import Foundation
import OpenIslandCore
import SwiftUI
import Testing
@testable import OpenIslandApp

private typealias Samples = NookDesignSamples

// MARK: - The kit in today's app: tour, templates, permissions

@MainActor
@Suite struct NookDesignInTheAppTests {
    private static let everyWidget = NookWidgetKind.allCases.map { NookWidgetPlacement(kind: $0, size: .medium) }

    private func state(withDesign: Bool) -> OnboardingState {
        var state = OnboardingState()
        let kinds = withDesign ? NookWidgetKind.allCases : NookWidgetKind.allCases.filter { $0 != .design }
        state.enabledWidgets = Set(kinds)
        state.nookPlacements = kinds.map { NookWidgetPlacement(kind: $0, size: .medium) }
        return state
    }

    /// The tour offers the kit with the other widgets and draws it once it is
    /// on the page. Its step ends the widget walk whether it is on or not,
    /// and comes up once.
    @Test func theTourDrawsTheKitOnceItIsOnThePageAndWalksItLast() {
        let on = state(withDesign: true)
        let off = state(withDesign: false)

        #expect(on.shownPlacements.contains { $0.kind == .design })
        #expect(on.showsWidget(.design))
        #expect(!off.shownPlacements.contains { $0.kind == .design })
        #expect(!off.showsWidget(.design))
        #expect(on.featureWalk.kinds == NookWidgetKind.allCases)
        #expect(on.featureWalk.kinds.filter { $0 == .design }.count == 1, "the kit comes up once")
        #expect(off.featureWalk.kinds == on.featureWalk.kinds)
    }

    /// A layout lists no tool. Drawn from a template with no page of the
    /// user's, the tour shows the template's own widgets, and the page of
    /// "Keep mine" is the user's own, which holds the kit.
    @Test func aPageDrawnFromATemplateHoldsNoKitAndKeepMineHoldsIt() {
        var on = state(withDesign: true)
        on.nookPlacements = nil
        on.appliedTemplate = .everything
        on.ownPlacements = Self.everyWidget

        #expect(!on.shownPlacements.contains { $0.kind == .design })
        #expect(on.ownLayoutPlacements.contains { $0.kind == .design })

        on.appliedTemplate = nil
        on.pickedTemplate = nil
        #expect(on.ownLayoutPlacements.contains { $0.kind == .design } == on.shownPlacements.contains { $0.kind == .design })
    }

    @Test func theFeatureWalkLandsOnAnotherWidgetWhenAskedForOneItDoesNotHold() {
        let held = NookWidgetKind.allCases.filter { $0 != .design }
        let walk = OnboardingFeatureWalk(kinds: held, current: .design)
        #expect(walk.current == held.first)
        #expect(OnboardingFeatureWalk(kinds: held, current: .linkAudio).isAtEnd)
    }

    @Test func theTourHasWordsForTheKitInEveryLanguage() throws {
        #expect((4...7).contains(OnboardingAbility.lines(for: .design).count))
        #expect(OnboardingTry.tries(for: .design) == [.designOn, .designPick])
        for language in HangoverBrandTests.languages {
            let table = try HangoverBrandTests.table(language)
            var keys = ["onboarding.nook.widget.design", "onboarding.widgets.design", "onboarding.features.needsDesign"]
            keys += OnboardingAbility.lines(for: .design).map(\.textKey)
            keys += OnboardingTry.tries(for: .design).map(\.titleKey)
            keys.append(OnboardingTry.designPick.titleKey + ".note")
            for key in keys {
                #expect(!(table[key] ?? "").isEmpty, "\(language) is missing \(key)")
            }
        }
    }

    /// With the kit on the page the pages that draw the page show it, and the
    /// walk, which holds it either way, does not change.
    @Test func thePagesThatDrawThePageShowTheKitWhenItIsOnIt() throws {
        for page in [OnboardingPage.widgets, .layout, .arrange, .done] {
            let with = try render(page, state(withDesign: true))
            let without = try render(page, state(withDesign: false))
            #expect(with != without, "\(page) drew nothing for the design kit")
        }
        let with = try render(.features, state(withDesign: true))
        let without = try render(.features, state(withDesign: false))
        #expect(with == without, "the walk holds the kit whether or not it is on the page")
    }

    @Test func noMacOSPermissionIsEverAskedForTheKit() {
        for moment in [NookAccessMoment.launch, .shown, .turnedOn, .requested] {
            for source in NookTodoSourceKind.allCases {
                #expect(
                    NookAccessTiming.permissions(for: .design, at: moment, isEnabled: true, todoSource: source).isEmpty,
                    "\(moment) \(source)"
                )
            }
        }
        // It is the same as the widgets that need nothing.
        #expect(NookAccessTiming.permissions(for: .design, at: .shown, isEnabled: true, todoSource: .reminders)
            == NookAccessTiming.permissions(for: .tray, at: .shown, isEnabled: true, todoSource: .reminders))
    }

    @Test func noTemplateHoldsTheKitAndEveryTemplateTakesItOffThePage() {
        for template in PersonalizationTemplate.all {
            #expect(!template.widgetKinds.contains(.design), "\(template.id)")
            let applied = template.applying(to: NookDisplayPreferences())
            #expect(applied.hiddenWidgets.contains(.design), "\(template.id)")
            // The page the template makes is its own, with the kit switched on or not.
            #expect(applied.placements(enabled: NookWidgetKind.allCases) == template.widgets, "\(template.id)")
            #expect(template.widgetsSwitchedOff(enabled: NookWidgetKind.allCases).isEmpty)
            #expect(template.widgetsSwitchedOff(enabled: NookWidgetKind.defaultEnabled).filter { $0 == .design }.isEmpty)
        }
    }

    @Test func aDisplayOnATemplateStaysOnItWhenTheKitIsSwitchedOn() {
        let template = PersonalizationTemplate.all[0]
        let setup = PersonalizationSetup(appearance: template.appearance, nook: template.applying(to: NookDisplayPreferences()))
        #expect(setup.appliedTemplateID == template.id)
        #expect(template.matches(appearance: template.appearance, nook: setup.nook))
    }

    @Test func aNameIsOnlyADraftWhenItIsNewAndHasSomethingInIt() {
        let rule = NookDesignReferenceRules.isUnsavedName
        #expect(!rule("Hero", "Hero"), "the field starts with the saved name")
        #expect(!rule("  Hero  ", "Hero"), "blanks around the saved name change nothing")
        #expect(!rule("", "Hero"))
        #expect(!rule("   \n", "Hero"))
        #expect(!rule("", ""))
        #expect(rule("Hero 2", "Hero"))
        #expect(rule("x", ""))
        #expect(rule("hero", "Hero"), "a different case is a different name")
    }

    @Test func aColorOrANameTypedAndNotKeptHoldsTheIslandOpenAndAnEmptyFieldDoesNot() {
        let nook = NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
        #expect(!nook.holdsUnsavedDraft)

        nook.setDraft(.designColor, isUnsaved: NookDraft.isUnsaved("#f8"))
        #expect(nook.holdsUnsavedDraft)
        nook.setDraft(.designColor, isUnsaved: NookDraft.isUnsaved("  "))
        #expect(!nook.holdsUnsavedDraft)

        nook.setDraft(.designName, isUnsaved: NookDesignReferenceRules.isUnsavedName("New", saved: "Old"))
        nook.setDraft(.designColor, isUnsaved: true)
        #expect(nook.holdsUnsavedDraft)
        // Closing the island forgets what was typed in both.
        nook.forgetDrafts()
        #expect(!nook.holdsUnsavedDraft)
    }

    @Test func theKitHasASampleAtEverySizeAndTheSettingsPreviewDrawsIt() throws {
        for size in NookWidgetSize.allCases {
            let height = NookPanelView.cardHeight(NookWidgetPlacement(kind: .design, size: size), calendarStyle: .strip)
            #expect(height > 0)
            if size == .small { #expect(height == NookWidgetLayout.smallHeight) }
        }
        let stage = PreviewStageMetrics.areaHeight(
            setup: PersonalizationSetup(appearance: IslandAppearancePreferences(), nook: NookDisplayPreferences()),
            enabledWidgets: NookWidgetKind.allCases
        )
        #expect(stage > 0)
    }

    // MARK: Drawing

    private func render(_ page: OnboardingPage, _ state: OnboardingState) throws -> Data {
        let size = OnboardingTestSize.of(page)
        let view = OnboardingView(tour: OnboardingTour(startingAt: page, state: { state }), lang: LanguageManager.shared)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view.environment(\.nookDrawsStill, true))
        renderer.scale = 1
        let image = try #require(renderer.cgImage, "ImageRenderer returned no image")
        return try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }
}

// MARK: - A model on a store of its own touches nothing of the user's

@MainActor
@Suite(.noNewWindows)
struct NookDesignSafetyTests {
    private var realFolder: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(OpenIslandStateDirectory.realFolderPath, isDirectory: true).path
    }

    private func model() -> NookModel {
        NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
    }

    @Test func aModelOnAStoreOfItsOwnKeepsTheKitsFilesOutOfTheRealFolder() {
        let first = model()
        let second = model()

        for nook in [first, second] {
            let palettes = nook.design.palettes.folderURL.path
            #expect(palettes.hasPrefix(OpenIslandStateDirectory.url.path), "\(palettes)")
            #expect(!palettes.hasPrefix(realFolder), "\(palettes)")
            #expect(nook.design.references.folderURL.path.hasPrefix(palettes), "the references sit under the same folder")
        }
        // No two models share a folder, which keeps one test from reading another's colors.
        #expect(first.design.palettes.folderURL != second.design.palettes.folderURL)
        #expect(first.design.references.folderURL != second.design.references.folderURL)
        #expect(NookDesignFiles.defaultFolder.path.hasPrefix(OpenIslandStateDirectory.url.path))
    }

    @Test func theAppModelOnAStoreOfItsOwnGetsTheSameKit() {
        let app = AppModel(defaults: MemoryDefaults())
        #expect(app.nook.design.palettes.folderURL.path.hasPrefix(OpenIslandStateDirectory.url.path))
        #expect(!app.nook.design.palettes.folderURL.path.hasPrefix(realFolder))
        #expect(!app.nook.isWidgetEnabled(.design))
        #expect(!NookWidgetKind.defaultEnabled.contains(.design))
    }

    @Test func aKitHandedToTheModelIsTheOneItUses() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("design-handed-\(UUID().uuidString)", isDirectory: true)
        let kit = NookDesignKit(folder: folder, defaults: MemoryDefaults())
        let nook = NookModel(design: kit, defaults: MemoryDefaults(), looksForImportedGIF: false)
        #expect(nook.design === kit)
        #expect(nook.design.palettes.folderURL == folder)
    }

    @Test func theKitsChoicesAreSavedInTheModelsStoreAndInNoOtherPlace() {
        let defaults = MemoryDefaults()
        let nook = NookModel(defaults: defaults, looksForImportedGIF: false)

        nook.design.copyFormat = .hsl
        nook.design.tab = .references
        nook.design.savesPicksToPalette = true

        #expect(defaults.string(forKey: NookDesignKit.formatKey) == "hsl")
        #expect(defaults.string(forKey: NookDesignKit.tabKey) == "references")
        #expect(defaults.bool(forKey: NookDesignKit.savesPicksKey))
        // The next model on the same store reads them back.
        let next = NookModel(defaults: defaults, looksForImportedGIF: false)
        #expect(next.design.copyFormat == .hsl)
        #expect(next.design.tab == .references)
    }

    @Test func aModelThatWasNeverStartedHoldsNoShortcutAndShowsNoPanelOrEditor() async {
        let nook = model()
        nook.setWidget(.design, enabled: true)
        try? await Task.sleep(for: .milliseconds(30))

        #expect(!nook.design.palettes.isLoaded)
        #expect(!nook.design.references.isLoaded)
        #expect(!nook.design.pickColor(from: .island))
        #expect(!nook.design.pickColor(from: .shortcut))
        #expect(nook.design.pasteReference().isEmpty)
        #expect(nook.design.openReference(UUID()) == nil)
        nook.design.showPaletteEditor()
        #expect(nook.design.hotkey.status == .none)
        // The Links tab reads no clipboard, opens nothing and keeps its file with the others.
        #expect(!nook.design.links.isLoaded)
        #expect(nook.design.pasteLink() == .unavailable)
        #expect(nook.design.addLink(text: "https://example.com") == .unavailable)
        #expect(!nook.design.openLink(UUID()))
    }

    @Test func aStartedModelWithTheKitOnReadsOnlyItsOwnFolderAndNeverRegistersAShortcutOrOpensAWindow() async throws {
        let defaults = MemoryDefaults()
        defaults.set(AgentHotkeyCombo(keyCode: 8, modifiers: [.control, .option]).storageValue, forKey: NookDesignHotkeyController.comboKey)
        let nook = NookModel(defaults: defaults, looksForImportedGIF: false)
        nook.setWidget(.design, enabled: true)
        var copied: [String] = []
        // The kit's copies go to a recorder here. The real clipboard is not used.
        nook.design.copyText = { copied.append($0); return true }
        let folder = nook.design.palettes.folderURL
        defer { try? FileManager.default.removeItem(at: folder) }

        nook.design.start(nook: nook)
        await nook.design.load()

        #expect(nook.design.palettes.isLoaded)
        #expect(nook.design.palettes.library == .empty)
        #expect(nook.design.references.items.isEmpty)
        // A shortcut that was saved is shown as saved, and nothing holds it.
        #expect(nook.design.hotkey.combo != nil)
        #expect(nook.design.hotkey.status == .inactive)
        #expect(!nook.design.pickColor(from: .shortcut))
        #expect(nook.design.pasteReference().isEmpty)
        nook.design.showPaletteEditor()
        #expect(nook.design.openPanels.isEmpty)

        // What it saves lands in the folder of its own.
        nook.design.addColor(Samples.orange)
        await nook.design.flush()
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(NookDesignLibraryFile.fileName).path))
        #expect(copied.isEmpty)
    }

    @Test func theLinksTabOfAStartedModelReadsNothingOfTheUsersOwnAndOpensAndPastesNothing() async throws {
        let nook = NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
        nook.setWidget(.design, enabled: true)
        var copied: [String] = []
        nook.design.copyText = { copied.append($0); return true }
        let folder = nook.design.links.folderURL
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(folder.path.hasPrefix(OpenIslandStateDirectory.url.path))
        #expect(!folder.path.hasPrefix(realFolder))

        nook.design.start(nook: nook)
        await nook.design.load()
        #expect(nook.design.links.isLoaded)
        #expect(nook.design.links.library == .empty)

        // No clipboard door and no opener were handed over: nothing is read and nothing opens.
        guard case let .added(link) = nook.design.addLink(text: "https://www.figma.com/design/KEY/Name?node-id=1-2#frame") else {
            Issue.record("not added")
            return
        }
        #expect(nook.design.pasteLink() == .unavailable)
        #expect(!nook.design.openLink(link.id))
        #expect(nook.design.links.link(link.id)?.lastOpenedAt == nil)
        #expect(nook.design.copyLink(link.id))
        #expect(copied == ["https://www.figma.com/design/KEY/Name?node-id=1-2#frame"])

        await nook.design.flush()
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(NookDesignLinkFile.fileName).path))
    }

    @Test func aCopiedLinkGoesThroughTheTraysDoorLikeAColorAndIsNeverReadBack() async throws {
        let defaults = MemoryDefaults()
        let pasteboard = NookFakePasteboard()
        let monitor = NookClipboardMonitor(pasteboard: pasteboard, defaults: defaults)
        let trayFolder = try Samples.temporaryFolder("tray-door")
        defer { try? FileManager.default.removeItem(at: trayFolder) }
        let tray = NookTrayStore(folder: trayFolder, clipboard: monitor, defaults: defaults)
        let nook = NookModel(tray: tray, defaults: defaults, looksForImportedGIF: false)
        nook.setWidget(.design, enabled: true)
        defer { monitor.setEnabled(false) }
        let folder = nook.design.links.folderURL
        defer { try? FileManager.default.removeItem(at: folder) }
        // The kit's copies go to the tray's clipboard unless it was handed another door.
        nook.design.start(nook: nook)
        await nook.design.load()
        guard case let .added(link) = nook.design.addLink(text: "https://www.figma.com/design/KEY/Name?node-id=1-2#frame") else {
            Issue.record("not added")
            return
        }

        // History off: the link lands on the pasteboard and nowhere else.
        #expect(nook.design.copyLink(link.id))
        #expect(pasteboard.content == .text(link.url))
        #expect(pasteboard.contentReads == 0)
        #expect(monitor.history.entries.isEmpty)

        // History on: the same copy is recorded from what was written, and the pasteboard is not read for it.
        monitor.setEnabled(true)
        let readsBefore = pasteboard.contentReads
        #expect(nook.design.copyLink(link.id))
        #expect(pasteboard.contentReads == readsBefore)
        #expect(monitor.history.entries.first?.content == .text(link.url))
    }

    @Test func aLinkTypedAndNotAddedHoldsTheIslandOpenAndAnEmptyFieldDoesNot() {
        let nook = NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
        nook.setDraft(.designLink, isUnsaved: NookDraft.isUnsaved("figma.co"))
        #expect(nook.holdsUnsavedDraft)
        nook.setDraft(.designLink, isUnsaved: NookDraft.isUnsaved("   "))
        #expect(!nook.holdsUnsavedDraft)
        nook.setDraft(.designLinkName, isUnsaved: NookDesignNames.isUnsaved("New", saved: "Old", limit: 80))
        #expect(nook.holdsUnsavedDraft)
        nook.forgetDrafts()
        #expect(!nook.holdsUnsavedDraft)
    }

    @Test func theAppModelWiresTheKitToTheAgentShortcutsAndHoldsTheirKeysDuringARecording() {
        let app = AppModel(defaults: MemoryDefaults())
        app.wireDesignKit()
        let hotkey = app.nook.design.hotkey

        let agents = hotkey.agentShortcuts()
        #expect(Set(agents) == [AgentHotkeySettings.defaultApprove, AgentHotkeySettings.defaultDeny])
        #expect(hotkey.setCombo(AgentHotkeySettings.defaultApprove) == .usedByAgentShortcut)
        #expect(hotkey.setCombo(AgentHotkeySettings.defaultDeny) == .usedByAgentShortcut)

        #expect(!app.agentHotkeys.isRecording)
        hotkey.beginRecording()
        #expect(app.agentHotkeys.isRecording)
        hotkey.endRecording()
        #expect(!app.agentHotkeys.isRecording)
    }

    @Test func aPickFromTheCardClosesTheOpenIslandAndAShortcutPickLeavesItAlone() async throws {
        guard !NSScreen.screens.isEmpty else { return }
        let app = AppModel(defaults: MemoryDefaults())
        app.wireDesignKit()
        let folder = try Samples.temporaryFolder("wired")
        defer { try? FileManager.default.removeItem(at: folder) }
        let kit = NookDesignKit(folder: folder, defaults: MemoryDefaults(), copyText: { _ in true })
        let sampler = FakeColorSampler()
        kit.activate(NookDesignServices(
            sampler: sampler, presenter: FakeReferencePresenter(), editor: FakeEditorPresenter(),
            pictureClipboard: FakePictureClipboard(), hotkeyRegistrar: FakeDesignHotkeyRegistrar(),
            linkOpener: FakeLinkOpener()
        ))
        kit.setLive(true)
        // The hook the app model wired on its own kit is the one used here.
        kit.willSampleFromIsland = app.nook.design.willSampleFromIsland

        app.notchOpen(reason: .click)
        #expect(app.notchStatus == .opened)
        #expect(kit.pickColor(from: .shortcut))
        #expect(app.notchStatus == .opened)
        sampler.finish(nil)

        #expect(kit.pickColor(from: .island))
        #expect(app.notchStatus == .closed)
        sampler.finish(nil)
    }
}
