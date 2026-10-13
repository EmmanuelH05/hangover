import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import OpenIslandApp

private typealias Samples = NookDesignSamples

private func text(_ key: String, _ arguments: any CVarArg...) -> String {
    let format = LanguageManager.shared.t(key)
    return arguments.isEmpty ? format : String(format: format, arguments: arguments)
}

// MARK: - C14: a name question holds the island

@MainActor
@Suite(.serialized, .noNewWindows)
struct NookDesignNameQuestionTests {
    private func model(_ kit: NookDesignKit) -> AppModel {
        let nook = NookModel(design: kit, defaults: MemoryDefaults(), looksForImportedGIF: false)
        let model = AppModel(defaults: MemoryDefaults(), nookModel: nook)
        model.disablesOverlayEventMonitoringDuringHarness = true
        return model
    }

    private func kit(_ label: String = "name") throws -> NookDesignKit {
        NookDesignKit(folder: try Samples.temporaryFolder(label), defaults: MemoryDefaults())
    }

    @Test func anOpenNameQuestionHoldsAHoverOpenedIslandOnTheNookPage() throws {
        guard !NSScreen.screens.isEmpty else { return }
        let kit = try kit()
        let model = model(kit)
        model.showNookPage()
        model.notchOpen(reason: .hover)
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave, "without a question the island follows the pointer")

        kit.beginNaming(.newCollection(forLink: UUID()))
        #expect(kit.isAskingForName)
        #expect(!model.overlay.shouldAutoCollapseOnMouseLeave)
        kit.cancelNaming()
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave)

        kit.beginRenamingReference(UUID())
        #expect(kit.isAskingForName)
        #expect(!model.overlay.shouldAutoCollapseOnMouseLeave)
        kit.renamingReferenceID = nil
        #expect(!kit.isAskingForName)
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave)
        model.notchClose()
    }

    @Test func returnAndEscapeEndTheQuestionAndHoldNothing() async throws {
        let root = try Samples.temporaryFolder("name")
        defer { try? FileManager.default.removeItem(at: root) }
        let kit = NookDesignKit(folder: root, defaults: MemoryDefaults())
        kit.setLive(true)
        await kit.load()
        guard case let .added(link) = kit.addLink(text: "https://example.com/x") else { return }

        kit.beginNaming(.renamingLink(link.id))
        #expect(kit.isAskingForName)
        kit.commitNaming("Renamed")
        #expect(!kit.isAskingForName)

        kit.beginNaming(.renamingLink(link.id))
        kit.cancelNaming()
        #expect(!kit.isAskingForName)

        // A name that was refused keeps the question up, which is what Return on a bad name does.
        let gone = UUID()
        kit.beginNaming(.renamingCollection(gone))
        #expect(!kit.commitNaming("x"))
        #expect(kit.linkNaming == .renamingCollection(gone))
        #expect(kit.isAskingForName)
    }

    @Test func everyWayTheIslandClosesOrTurnsAwayPutsTheQuestionAway() throws {
        guard !NSScreen.screens.isEmpty else { return }
        let kit = try kit()
        let model = model(kit)
        model.showNookPage()

        model.notchOpen(reason: .hover)
        kit.beginNaming(.newCollection(forLink: UUID()))
        model.notchClose()
        #expect(!kit.isAskingForName, "a closed island holds no question")

        model.showNookPage()
        model.notchOpen(reason: .click)
        kit.beginRenamingReference(UUID())
        model.showAgentsPage()
        #expect(!kit.isAskingForName, "the Nook page left, and its question with it")
        model.notchClose()

        // An island that opens again starts with no question, even if one was left behind.
        kit.beginNaming(.newCollection(forLink: UUID()))
        model.notchOpen(reason: .hover)
        #expect(!kit.isAskingForName)
        model.notchClose()
    }

    @Test func openingAQuestionMakesThePanelTheKeyWindow() throws {
        let kit = try kit()
        let model = model(kit)
        model.wireDesignKit()
        let controller = model.overlay.overlayPanelController
        let before = controller.keyRequestCount

        kit.beginNaming(.newCollection(forLink: UUID()))
        #expect(controller.keyRequestCount == before + 1)
        kit.beginRenamingReference(UUID())
        #expect(controller.keyRequestCount == before + 2)
        // Moving on to another question asks again, and closing one asks nothing.
        kit.cancelNaming()
        #expect(controller.keyRequestCount == before + 2)
    }
}

// MARK: - C15: the paste buttons and macOS's "paste from other apps"

@MainActor
@Suite struct NookDesignPasteAccessTests {
    private func started() async throws -> (fixture: NookDesignFixture, nook: NookModel) {
        let fixture = try await NookDesignFixture("paste")
        let nook = NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
        nook.setWidget(.design, enabled: true)
        fixture.kit.start(nook: nook)
        fixture.clipboard.nook = nook
        return (fixture, nook)
    }

    @Test func aRefusedPasteSaysPasteIsNotAllowedAndReadsNothing() async throws {
        let (fixture, _) = try await started()
        defer { fixture.cleanUp() }
        fixture.clipboard.access = .denied
        fixture.clipboard.text = "https://example.com/x"

        #expect(fixture.kit.pasteLink() == .notAllowed)
        #expect(fixture.kit.notice?.text == text("nook.design.notice.pasteNotAllowed"))
        #expect(fixture.kit.notice?.text != text("nook.design.notice.linkNoText"))
        #expect(fixture.clipboard.textReads == 0)

        #expect(fixture.kit.pasteReference().isEmpty)
        #expect(fixture.kit.notice?.text == text("nook.design.notice.pasteNotAllowed"))
        #expect(fixture.clipboard.reads == 0)
        #expect(fixture.kit.links.links.isEmpty)
    }

    @Test func aPasteThatMayRaiseTheAlertIsCountedAsASystemPromptWhileItReads() async throws {
        let (fixture, nook) = try await started()
        defer { fixture.cleanUp() }
        fixture.clipboard.access = .asks
        fixture.clipboard.text = "https://example.com/x"

        guard case .added = fixture.kit.pasteLink() else {
            Issue.record("not added")
            return
        }

        #expect(fixture.clipboard.promptWasUpDuringRead, "the island was not stepped down for the alert")
        #expect(!nook.isSystemPromptUp, "the count was not let go")

        fixture.clipboard.pictures = .none
        _ = fixture.kit.pasteReference()
        #expect(fixture.clipboard.promptWasUpDuringRead)
        #expect(!nook.isSystemPromptUp)
    }

    @Test func aPasteThatFindsNothingAfterAnAlertDoesNotSayTheClipboardIsEmpty() async throws {
        let (fixture, _) = try await started()
        defer { fixture.cleanUp() }
        fixture.clipboard.access = .asks
        fixture.clipboard.text = nil

        #expect(fixture.kit.pasteLink() == .nothingToPaste)
        #expect(fixture.kit.notice?.text == text("nook.design.notice.pasteMaybeRefused"))
        #expect(fixture.kit.notice?.text != text("nook.design.notice.linkNoText"))

        _ = fixture.kit.pasteReference()
        #expect(fixture.kit.notice?.text == text("nook.design.notice.pasteMaybeRefused"))
    }

    @Test func aPasteThatIsAllowedRaisesNoPromptAndSaysTheClipboardIsEmptyWhenItIs() async throws {
        let (fixture, _) = try await started()
        defer { fixture.cleanUp() }
        fixture.clipboard.access = .allowed
        fixture.clipboard.text = nil

        #expect(fixture.kit.pasteLink() == .nothingToPaste)
        #expect(!fixture.clipboard.promptWasUpDuringRead)
        #expect(fixture.kit.notice?.text == text("nook.design.notice.linkNoText"))
    }

    @Test func theFileThatCountsThePromptIsOneOfTheKnownPlaces() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent("Sources/OpenIslandApp/Nook/Widgets/Design/NookDesignKit+Clipboard.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        #expect(source.components(separatedBy: ".systemPromptBegan()").count == 2)
        #expect(source.components(separatedBy: ".systemPromptEnded()").count == 2)
    }
}

// MARK: - C16: switching the kit on in Settings leaves it a card

@MainActor
@Suite struct NookDesignSwitchOnTests {
    private func nook() -> NookModel {
        let nook = NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
        nook.activeProfile = { .notch }
        return nook
    }

    @Test func aLayoutThatHidAWidgetDoesNotLeaveTheKitWithoutACard() {
        let nook = nook()
        for template in PersonalizationTemplate.all.prefix(3) {
            nook.updateDisplayPreferences(for: .notch) { $0 = template.applying(to: $0) }
            #expect(nook.displayPreferences(for: .notch).hiddenWidgets.contains(.design))
        }

        nook.setWidgetFromSettings(.design, enabled: true)

        #expect(nook.isWidgetEnabled(.design))
        #expect(nook.widgetPlacements(for: .notch).map(\.kind).contains(.design), "on and hidden has no card")
    }

    @Test func switchingItOffAndOnAgainStillGivesItACard() {
        let nook = nook()
        nook.setWidgetFromSettings(.design, enabled: true)
        nook.updateDisplayPreferences(for: .notch) { $0.hiddenWidgets.insert(.design) }
        nook.setWidgetFromSettings(.design, enabled: false)
        #expect(!nook.isWidgetEnabled(.design))
        nook.setWidgetFromSettings(.design, enabled: true)
        #expect(nook.widgetPlacements(for: .notch).map(\.kind).contains(.design))
    }

    @Test func otherWidgetsAreSwitchedOnTheWayTheyAlwaysWere() {
        let nook = nook()
        nook.updateDisplayPreferences(for: .notch) { $0.hiddenWidgets.insert(.weather) }
        nook.setWidgetFromSettings(.weather, enabled: true)
        #expect(nook.isWidgetEnabled(.weather))
        #expect(nook.displayPreferences(for: .notch).hiddenWidgets.contains(.weather), "only the kit is taken off the hidden list")
    }

    @Test func theOtherDisplaysHiddenListIsLeftAlone() {
        let nook = nook()
        nook.updateDisplayPreferences(for: .topBar) { $0.hiddenWidgets.insert(.design) }
        nook.updateDisplayPreferences(for: .notch) { $0.hiddenWidgets.insert(.design) }
        nook.setWidgetFromSettings(.design, enabled: true)
        #expect(!nook.displayPreferences(for: .notch).hiddenWidgets.contains(.design))
        #expect(nook.displayPreferences(for: .topBar).hiddenWidgets.contains(.design))
    }
}

// MARK: - C17: the card takes pictures and hands the rest to the tray

@MainActor
@Suite struct NookDesignDropRoutingTests {
    private func started() async throws -> (fixture: NookDesignFixture, nook: NookModel, trayFolder: URL) {
        let fixture = try await NookDesignFixture("drops")
        let trayFolder = try Samples.temporaryFolder("drops-tray")
        let defaults = MemoryDefaults()
        let tray = NookTrayStore(folder: trayFolder, defaults: defaults)
        let nook = NookModel(tray: tray, defaults: defaults, looksForImportedGIF: false)
        nook.setWidget(.design, enabled: true)
        fixture.kit.start(nook: nook)
        return (fixture, nook, trayFolder)
    }

    @Test func aFileThatIsNotAPictureGoesToTheTrayAndNotToTheShelf() async throws {
        let (fixture, nook, trayFolder) = try await started()
        let sources = try Samples.temporaryFolder("drops-sources")
        defer {
            fixture.cleanUp()
            try? FileManager.default.removeItem(at: trayFolder)
            try? FileManager.default.removeItem(at: sources)
        }
        let words = sources.appendingPathComponent("notes.txt")
        try Data("words".utf8).write(to: words)

        #expect(fixture.kit.handlePictureDrop([NSItemProvider(object: words as NSURL)]))

        #expect(await Samples.wait { !nook.tray.items.isEmpty })
        #expect(nook.tray.items.map(\.originalName) == ["notes.txt"])
        #expect(fixture.kit.references.items.isEmpty)
        #expect(await Samples.wait { fixture.kit.notice?.text == text("nook.design.notice.droppedToTray") })
        #expect(fixture.kit.tab != .references, "nothing went to the shelf")
    }

    @Test func aPictureGoesToTheShelfAndNotToTheTray() async throws {
        let (fixture, nook, trayFolder) = try await started()
        let sources = try Samples.temporaryFolder("drops-sources")
        defer {
            fixture.cleanUp()
            try? FileManager.default.removeItem(at: trayFolder)
            try? FileManager.default.removeItem(at: sources)
        }
        let picture = try Samples.writePNG(named: "shot.png", in: sources)

        #expect(fixture.kit.handlePictureDrop([NSItemProvider(object: picture as NSURL)]))

        #expect(await Samples.wait { fixture.kit.references.items.count == 1 })
        #expect(nook.tray.items.isEmpty)
    }

    @Test func aPictureWithTheWrongNameIsStillAPictureAndATextFileWithAPicturesNameIsNot() async throws {
        let (fixture, nook, trayFolder) = try await started()
        let sources = try Samples.temporaryFolder("drops-sources")
        defer {
            fixture.cleanUp()
            try? FileManager.default.removeItem(at: trayFolder)
            try? FileManager.default.removeItem(at: sources)
        }
        let disguised = sources.appendingPathComponent("really-a-picture.dat")
        try Samples.pngData(width: 30, height: 30).write(to: disguised)
        let fake = sources.appendingPathComponent("fake.png")
        try Data("text".utf8).write(to: fake)

        #expect(fixture.kit.handlePictureDrop([NSItemProvider(object: disguised as NSURL), NSItemProvider(object: fake as NSURL)]))

        #expect(await Samples.wait { fixture.kit.references.items.count == 1 && nook.tray.items.count == 1 })
        #expect(nook.tray.items.map(\.originalName) == ["fake.png"])
        let counted = [text("nook.design.batch.added", 1), text("nook.design.batch.toTray", 1)].joined(separator: ", ")
        #expect(await Samples.wait { fixture.kit.notice?.text == counted })
    }

    @Test func aMixedDropEndsInOneLineThatCountsEverything() async throws {
        let (fixture, nook, trayFolder) = try await started()
        let sources = try Samples.temporaryFolder("drops-sources")
        defer {
            fixture.cleanUp()
            try? FileManager.default.removeItem(at: trayFolder)
            try? FileManager.default.removeItem(at: sources)
        }
        var providers: [NSItemProvider] = []
        for index in 0..<2 { providers.append(NSItemProvider(object: try Samples.writePNG(named: "p\(index).png", in: sources) as NSURL)) }
        for index in 0..<3 {
            let url = sources.appendingPathComponent("f\(index).txt")
            try Data("x".utf8).write(to: url)
            providers.append(NSItemProvider(object: url as NSURL))
        }

        #expect(fixture.kit.handlePictureDrop(providers))

        let counted = [text("nook.design.batch.added", 2), text("nook.design.batch.toTray", 3)].joined(separator: ", ")
        #expect(await Samples.wait { fixture.kit.notice?.text == counted })
        #expect(nook.tray.items.count == 3)
    }
}

// MARK: - C18: the two shortcut sets know of each other

@MainActor
@Suite struct NookDesignShortcutConflictTests {
    private static let eyedropper = AgentHotkeyCombo(keyCode: 8, modifiers: [.control, .option])

    private func controller() -> AgentHotkeyController {
        AgentHotkeyController(defaults: MemoryDefaults())
    }

    @Test func theAgentRecorderRefusesKeysThatAreReserved() {
        let hotkeys = controller()
        hotkeys.reservedShortcuts = { [Self.eyedropper] }

        #expect(hotkeys.setCombo(Self.eyedropper, for: .approve) == .usedByEyedropper)
        #expect(hotkeys.setCombo(Self.eyedropper, for: .deny) == .usedByEyedropper)
        #expect(hotkeys.combo(for: .approve) == AgentHotkeySettings.defaultApprove, "the shortcut it had is kept")
        #expect(AgentHotkeyProblem.usedByEyedropper.messageKey == "settings.general.agentHotkeys.problem.eyedropper")
        // Other keys are free, and the modifier rule still comes first.
        #expect(hotkeys.setCombo(AgentHotkeyCombo(keyCode: 9, modifiers: [.control, .option]), for: .approve) == nil)
        #expect(hotkeys.setCombo(AgentHotkeyCombo(keyCode: 8, modifiers: [.control]), for: .deny) == .needsModifiers)
    }

    @Test func withTheKitOnTheAppsRecorderRefusesTheEyedroppersKeysAndWithItOffItDoesNot() async throws {
        let root = try Samples.temporaryFolder("conflict")
        defer { try? FileManager.default.removeItem(at: root) }
        let kit = NookDesignKit(folder: root, defaults: MemoryDefaults())
        let model = AppModel(defaults: MemoryDefaults(), nookModel: NookModel(design: kit, defaults: MemoryDefaults(), looksForImportedGIF: false))
        model.wireDesignKit()
        kit.hotkey.setCombo(Self.eyedropper)

        // The kit is off: the keys are not held, and the recorder may take them.
        kit.setLive(false)
        #expect(model.agentHotkeys.setCombo(Self.eyedropper, for: .approve) == nil)
        model.agentHotkeys.resetToDefaults()

        kit.setLive(true)
        #expect(model.agentHotkeys.setCombo(Self.eyedropper, for: .approve) == .usedByEyedropper)
    }

    @Test func aKitSwitchedOnWithKeysAnAgentHasSaysSoAndOffersSettings() async throws {
        let root = try Samples.temporaryFolder("conflict")
        defer { try? FileManager.default.removeItem(at: root) }
        let kit = NookDesignKit(folder: root, defaults: MemoryDefaults())
        let model = AppModel(defaults: MemoryDefaults(), nookModel: NookModel(design: kit, defaults: MemoryDefaults(), looksForImportedGIF: false))
        model.wireDesignKit()
        // The kit is off, and an agent shortcut takes the keys the eyedropper had saved.
        kit.hotkey.setCombo(Self.eyedropper)
        kit.setLive(false)
        model.agentHotkeys.setCombo(Self.eyedropper, for: .approve)

        kit.setLive(true)

        #expect(kit.hotkey.status == .invalid(.usedByAgentShortcut))
        #expect(kit.standingNotice?.text == text("nook.design.standing.agent"))
        #expect(kit.standingNotice?.opensSettings == true)
    }
}

// MARK: - C19: the tour puts the page back, the kit among the rest

@MainActor
@Suite struct NookDesignTourPutBackTests {
    @Test func theListedWidgetsGoFirstInTheirOrderAndTheRestFollowInTheirOwn() {
        // The tour put calendar before media, and the kit sat between media and the to-dos.
        let current: [NookWidgetKind] = [.calendar, .media, .design, .todo, .notes, .tray, .timer, .mirror, .weather]

        let restored = NookWidgetKind.orderRestoring([.media, .calendar, .todo], in: current)

        #expect(restored == [.media, .calendar, .todo, .design, .notes, .tray, .timer, .mirror, .weather])
    }

    /// The tour lists the kit with the others once it is on the page. The
    /// page goes back with it where the tour found it.
    @Test func aKitOnThePageIsListedAndGoesBackWhereTheTourFoundIt() {
        let current: [NookWidgetKind] = [.calendar, .media, .design, .todo, .notes, .tray, .timer, .mirror, .weather]
        let listed: [NookWidgetKind] = [.media, .design, .calendar, .todo]

        let restored = NookWidgetKind.orderRestoring(listed, in: current)

        #expect(Array(restored.prefix(4)) == listed)
        #expect(restored.firstIndex(of: .design) == 1)
    }

    @Test func theOrderHoldsEveryWidgetOnceWhateverWasListed() {
        let current = NookWidgetKind.allCases
        for listed in [[], [NookWidgetKind.weather], [.design, .media], Array(NookWidgetKind.allCases.reversed())] {
            let restored = NookWidgetKind.orderRestoring(listed, in: current)
            #expect(Set(restored) == Set(current))
            #expect(restored.count == current.count)
        }
        // A widget listed twice, or one that is not in the page, is read once.
        let odd = NookWidgetKind.orderRestoring([.media, .media, .design], in: [.calendar, .media])
        #expect(odd == [.media, .calendar])
    }

    @Test func putItBackOnTheAppGoesBackToWhatWasListedSizesIncluded() {
        let nook = NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
        nook.activeProfile = { .notch }
        let model = AppModel(defaults: MemoryDefaults(), nookModel: nook)
        nook.setWidget(.design, enabled: true)
        nook.updateDisplayPreferences(for: .notch) { $0.widgetOrder = [.calendar, .media, .design, .todo, .notes, .tray, .timer, .mirror, .weather] }
        let start = [
            NookWidgetPlacement(kind: .media, size: .large),
            NookWidgetPlacement(kind: .design, size: .medium),
            NookWidgetPlacement(kind: .calendar, size: .small),
        ]

        model.restoreTourPlacements(start, for: .notch)

        let order = nook.displayPreferences(for: .notch).normalizedWidgetOrder
        #expect(order.prefix(3) == [.media, .design, .calendar])
        #expect(nook.displayPreferences(for: .notch).widgetSizes[.media] == .large)
        #expect(nook.displayPreferences(for: .notch).widgetSizes[.calendar] == .small)
    }
}

// MARK: - C20: the loupe is not in the way of the island

@MainActor
@Suite(.serialized, .noNewWindows)
struct NookDesignSamplingHoverTests {
    private static let far = NSPoint(x: -10_000, y: -10_000)

    @Test func hoverDoesNotOpenWhileTheLoupeIsUp() {
        #expect(IslandPointerRules.hoverOpens(trigger: .hover, isSuppressed: false, isSamplingColor: false))
        #expect(!IslandPointerRules.hoverOpens(trigger: .hover, isSuppressed: false, isSamplingColor: true))
        #expect(!IslandPointerRules.hoverOpens(trigger: .click, isSuppressed: false, isSamplingColor: false))
    }

    @Test func thePointerCrossingTheClosedIslandDuringAPickDoesNotOpenIt() async throws {
        guard !NSScreen.screens.isEmpty else { return }
        let root = try Samples.temporaryFolder("sampling")
        defer { try? FileManager.default.removeItem(at: root) }
        let kit = NookDesignKit(folder: root, defaults: MemoryDefaults())
        let sampler = FakeColorSampler()
        kit.activate(NookDesignServices(
            sampler: sampler, presenter: FakeReferencePresenter(), editor: FakeEditorPresenter(),
            pictureClipboard: FakePictureClipboard(), hotkeyRegistrar: FakeDesignHotkeyRegistrar(), linkOpener: FakeLinkOpener()
        ))
        kit.setLive(true)
        let model = AppModel(defaults: MemoryDefaults(), nookModel: NookModel(design: kit, defaults: MemoryDefaults(), looksForImportedGIF: false))
        model.disablesOverlayEventMonitoringDuringHarness = true
        model.overlay.pointerLocationProvider = { Self.far }
        model.overlay.ensureOverlayPanel()
        let controller = model.overlay.overlayPanelController
        let pill = NSPoint(x: controller.notchRect.midX, y: controller.notchRect.midY)

        #expect(kit.pickColor(from: .shortcut))
        controller.handleMouseMoved(pill)
        try await Task.sleep(for: .milliseconds(500))
        #expect(model.notchStatus == .closed, "the island opened under the loupe")

        // The pick ends. The pointer leaves and comes back, and now the island opens.
        sampler.finish(nil)
        controller.handleMouseMoved(Self.far)
        controller.handleMouseMoved(pill)
        try await Task.sleep(for: .milliseconds(500))
        #expect(model.notchStatus == .opened)
        model.notchClose()
    }
}
