import AppKit
import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

// The widgets page lists every widget, Record, the design kit and Link to MP3
// last, with the same row and switch. The three start off and the footnote names
// them, the switch is Settings' own door for them, a layout picked after one is on
// keeps it, and the rows fit the window (the last one scrolls in the dev copy).
// Nothing here shows a window or writes the real settings.

// MARK: - A model as the running app has it

/// An app model whose Nook reads the same display profile the app does. The
/// app wires that when it starts, and the tour only runs after that.
@MainActor
private func runningAppModel() -> AppModel {
    let nook = NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
    let model = AppModel(agentsDefaults: MemoryDefaults(), defaults: MemoryDefaults(), nookModel: nook)
    nook.activeProfile = { [weak model] in model?.activeAppearanceProfile ?? .topBar }
    return model
}

// MARK: - The list and its footnote

struct OnboardingWidgetsListTests {
    @Test func theListIsTheEightOfBeforeThenRecordThenTheKitThenLinkToMP3() {
        let all = NookWidgetKind.allCases
        #expect(all.count == 11)
        #expect(all.prefix(8) == [.media, .calendar, .todo, .notes, .tray, .timer, .mirror, .weather])
        #expect(all[8] == .record && all[9] == .design && all[10] == .linkAudio)
    }

    @Test func fiveWidgetsStartSwitchedOffAndTheThreeNewOnesAreAmongThem() {
        #expect(NookWidgetKind.startsOff == [.mirror, .weather, .record, .design, .linkAudio])
        #expect(!NookWidgetKind.defaultEnabled.contains(.record))
        #expect(!NookWidgetKind.defaultEnabled.contains(.design))
        #expect(!NookWidgetKind.defaultEnabled.contains(.linkAudio))
        let fresh = OnboardingState()
        #expect(!fresh.showsWidget(.record) && !fresh.showsWidget(.design) && !fresh.showsWidget(.linkAudio))
    }

    /// Every widget that starts off is named in the footnote, in each language,
    /// by the name its row has.
    @Test(arguments: HangoverBrandTests.languages)
    func theFootnoteNamesEveryWidgetThatStartsOff(language: String) throws {
        let table = try HangoverBrandTests.table(language)
        let note = try #require(table["onboarding.widgets.note"])
        for kind in NookWidgetKind.startsOff {
            let name = try #require(table["onboarding.nook.widget.\(kind.rawValue)"])
            #expect(note.contains(name), "\(language): the footnote does not name \(name)")
        }
        for kind in NookWidgetKind.allCases where NookWidgetKind.defaultEnabled.contains(kind) {
            let name = try #require(table["onboarding.nook.widget.\(kind.rawValue)"])
            #expect(!note.contains(name), "\(language): the footnote names \(name), which starts on")
        }
    }

    @Test func everyRowHasItsNameAndItsLineInEveryLanguage() throws {
        for language in HangoverBrandTests.languages {
            let table = try HangoverBrandTests.table(language)
            for kind in NookWidgetKind.allCases {
                for key in ["onboarding.nook.widget.\(kind.rawValue)", "onboarding.widgets.\(kind.rawValue)"] {
                    #expect(!(table[key] ?? "").isEmpty, "\(language) is missing \(key)")
                }
            }
        }
    }

    // MARK: The walk, with a tool already on

    /// A kit or Link to MP3 that is already on shows its Turn it on step
    /// ticked the moment the step comes up: the tick is read from the model.
    @MainActor
    @Test func aToolAlreadyOnHasItsStepTickedOnArrival() {
        var state = OnboardingState()
        state.features.design = OnboardingDesignReading(isOn: true, isReady: true)
        state.features.linkAudio = OnboardingLinkAudioReading(isOn: true, missingNoteKey: nil)
        let tour = OnboardingTour(startingAt: .features, state: { state })
        tour.syncIsland()

        let done = tour.state.featureProgress.done
        #expect(done.contains(.designOn) && done.contains(.linkAudioOn))
        #expect(tour.state.isDone(.designOn) && tour.state.isDone(.linkAudioOn))

        var off = OnboardingState()
        off.features.design = OnboardingDesignReading(isOn: false)
        let untouched = OnboardingTour(startingAt: .features, state: { off })
        untouched.syncIsland()
        #expect(!untouched.state.featureProgress.done.contains(.designOn))
        #expect(!untouched.state.featureProgress.done.contains(.linkAudioOn))
    }
}

// MARK: - The switch is Settings' own door

@MainActor
struct OnboardingWidgetsSwitchTests {
    private static func model() -> AppModel { runningAppModel() }

    /// The tour's switch for a tool leaves the models in the state Settings'
    /// switch does: the widget enabled, and taken off the hidden list.
    @Test(arguments: NookWidgetKind.tools)
    func theToolsSwitchIsTheSettingsSwitch(kind: NookWidgetKind) {
        let viaTour = Self.model()
        let viaSettings = Self.model()
        for model in [viaTour, viaSettings] {
            let profile = model.activeAppearanceProfile
            model.nook.updateDisplayPreferences(for: profile) { $0.hiddenWidgets.insert(kind) }
        }

        viaTour.setTourWidget(kind, enabled: true)
        viaSettings.nook.setWidgetFromSettings(kind, enabled: true)

        let profile = viaTour.activeAppearanceProfile
        #expect(viaTour.nook.isWidgetEnabled(kind) && viaSettings.nook.isWidgetEnabled(kind))
        #expect(viaTour.nook.displayPreferences(for: profile) == viaSettings.nook.displayPreferences(for: profile))
        #expect(viaTour.nook.widgetPlacements(for: profile).contains { $0.kind == kind })
    }

    @Test(arguments: NookWidgetKind.tools)
    func offAgainInTheTourMeansOff(kind: NookWidgetKind) {
        let model = Self.model()
        model.setTourWidget(kind, enabled: true)
        #expect(model.onboardingState.shownPlacements.contains { $0.kind == kind })

        model.setTourWidget(kind, enabled: false)

        #expect(!model.nook.isWidgetEnabled(kind))
        #expect(!model.nook.widgetPlacements(for: model.activeAppearanceProfile).contains { $0.kind == kind })
        #expect(!model.onboardingState.shownPlacements.contains { $0.kind == kind })
    }

    /// Off in the tour is off for what runs behind it too, the way it is in
    /// Settings: the download that was running is cancelled, none waits.
    @Test func offAgainInTheTourStopsWhatLinkToMP3WasRunning() throws {
        let fixture = LinkAudioFixture()
        let nook = NookModel(linkAudio: fixture.service, defaults: MemoryDefaults(), looksForImportedGIF: false)
        let model = AppModel(agentsDefaults: MemoryDefaults(), defaults: MemoryDefaults(), nookModel: nook)
        nook.activeProfile = { [weak model] in model?.activeAppearanceProfile ?? .topBar }
        model.setTourWidget(.linkAudio, enabled: true)
        fixture.submit(2)
        let run = try #require(fixture.runner.last)

        model.setTourWidget(.linkAudio, enabled: false)

        #expect(run.cancelCount == 1)
        #expect(fixture.service.queue.waiting.isEmpty)
    }

    @Test func theOtherWidgetsKeepTheTourSwitchTheyHad() {
        let model = Self.model()
        model.setTourWidget(.weather, enabled: true)
        #expect(model.nook.isWidgetEnabled(.weather))
        model.setTourWidget(.weather, enabled: false)
        #expect(!model.nook.isWidgetEnabled(.weather))
    }

    /// Through the page's own action, a switch writes the model, and the
    /// reading the walk's step uses follows it.
    @Test func thePagesSwitchTurnsTheKitOnAndOffInTheModel() {
        let model = Self.model()
        let tour = model.makeWelcomeTour(startingAt: .widgets)

        tour.actions.setWidget(.design, true)
        #expect(model.nook.isWidgetEnabled(.design))
        #expect(model.onboardingState.showsWidget(.design))

        tour.actions.setWidget(.design, false)
        #expect(!model.nook.isWidgetEnabled(.design))
        #expect(!model.onboardingState.showsWidget(.design))
    }
}

// MARK: - A layout keeps what the user switched on

@MainActor
struct OnboardingLayoutKeepsToolsTests {
    private static func model() -> AppModel { runningAppModel() }

    private static func page(_ model: AppModel) -> [NookWidgetKind] {
        model.nook.widgetPlacements(for: model.activeAppearanceProfile).map(\.kind)
    }

    @Test(arguments: PersonalizationTemplate.all)
    func aLayoutPickedAfterBothToolsAreOnKeepsThemAfterItsOwnWidgets(template: PersonalizationTemplate) {
        let model = Self.model()
        let tour = model.makeWelcomeTour(startingAt: .layout)
        tour.actions.setWidget(.design, true)
        tour.actions.setWidget(.linkAudio, true)
        #expect(Self.page(model).contains(.design) && Self.page(model).contains(.linkAudio))

        tour.actions.applyTemplate(template)

        let page = Self.page(model)
        #expect(page.contains(.design) && page.contains(.linkAudio), "\(template.id) dropped a tool")
        #expect(Array(page.suffix(2)) == [.design, .linkAudio], "the tools come after the layout's own widgets")
        #expect(!page.dropLast(2).contains(.design) && !page.dropLast(2).contains(.linkAudio))
        // The readings the walk's steps use still say on, with the card there.
        #expect(model.onboardingState.features.linkAudio.isOn)
        #expect(model.onboardingState.shownPlacements.contains { $0.kind == .linkAudio })
    }

    @Test func aToolSwitchedOffAgainIsNotPutBackByALayout() {
        let model = Self.model()
        let tour = model.makeWelcomeTour(startingAt: .layout)
        tour.actions.setWidget(.design, true)
        tour.actions.setWidget(.design, false)

        tour.actions.applyTemplate(PersonalizationTemplate.all[0])

        #expect(!Self.page(model).contains(.design))
        #expect(!model.nook.isWidgetEnabled(.design))
    }

    @Test func aToolSwitchedOnAfterALayoutStaysAndKeepMineBringsBackTheOwnPage() {
        let model = Self.model()
        let tour = model.makeWelcomeTour(startingAt: .layout)
        let before = Self.page(model)

        tour.actions.applyTemplate(PersonalizationTemplate.all[0])
        tour.actions.setWidget(.linkAudio, true)
        tour.actions.keepOwnLayout()

        let page = Self.page(model)
        #expect(Array(page.prefix(before.count)) == before, "the user's own page is back")
        #expect(page.contains(.linkAudio), "the tool switched on in the tour is still on it")
    }

    @Test func theLayoutCardsDrawTheToolsTheUserSwitchedOn() {
        var state = OnboardingState()
        let template = PersonalizationTemplate.all[0]
        state.enabledWidgets = Set(NookWidgetKind.defaultEnabled + [.design])
        state.nookPlacements = (template.widgets + [NookWidgetPlacement(kind: .design, size: .medium)])
        let page = OnboardingLayoutPage.page(of: template, keeping: state)
        #expect(page.map(\.kind).suffix(1) == [.design])
        #expect(page.prefix(template.widgets.filter { state.enabledWidgets.contains($0.kind) }.count).map(\.kind)
            == template.widgets.filter { state.enabledWidgets.contains($0.kind) }.map(\.kind))

        state.nookPlacements = template.widgets
        #expect(!OnboardingLayoutPage.page(of: template, keeping: state).contains { $0.kind == .design })
    }
}

// MARK: - The tour's note of the tools it switched on

@MainActor
struct OnboardingToolPicksTests {
    private func tour(calls: Box) -> OnboardingTour {
        var actions = OnboardingActions()
        actions.setWidget = { kind, isOn in calls.names.append("\(kind.rawValue) \(isOn)") }
        return OnboardingTour(startingAt: .widgets, state: { OnboardingState() }, actions: actions)
    }

    final class Box { var names: [String] = [] }

    @Test func aToolSwitchedOnIsAPickAndSwitchedOffIsNot() {
        let calls = Box()
        let tour = tour(calls: calls)
        #expect(tour.picks.tools.isEmpty)

        tour.actions.setWidget(.design, true)
        tour.actions.setWidget(.linkAudio, true)
        #expect(tour.picks.tools == [.design, .linkAudio])

        tour.actions.setWidget(.design, false)
        #expect(tour.picks.tools == [.linkAudio])
        #expect(calls.names == ["design true", "linkAudio true", "design false"])
    }

    @Test func theOtherWidgetsAreNotNotedAsTools() {
        let calls = Box()
        let tour = tour(calls: calls)
        for kind in NookWidgetKind.allCases where !NookWidgetKind.tools.contains(kind) {
            tour.actions.setWidget(kind, true)
        }
        #expect(tour.picks.tools.isEmpty)
    }

    /// A layout puts back what the user switched on, and only that.
    @Test func aLayoutPutsBackTheToolsStillOnAndNoOthers() {
        let calls = Box()
        let tour = tour(calls: calls)
        tour.actions.setWidget(.design, true)
        tour.actions.setWidget(.linkAudio, true)
        tour.actions.setWidget(.design, false)
        calls.names.removeAll()

        tour.actions.applyTemplate(PersonalizationTemplate.all[0])

        #expect(calls.names == ["linkAudio true"])
    }

    @Test func aLayoutPutsBackNothingWhenNoToolWasSwitchedOn() {
        let calls = Box()
        let tour = tour(calls: calls)
        tour.actions.applyTemplate(PersonalizationTemplate.all[0])
        #expect(calls.names.isEmpty)
    }
}

// MARK: - The rows fit

@MainActor
struct OnboardingWidgetsFitTests {
    private static let scale: CGFloat = 2

    private static func state(allOn: Bool, without: NookWidgetKind? = nil) -> OnboardingState {
        var state = OnboardingState()
        state.length = .short
        var enabled = allOn ? Set(NookWidgetKind.allCases) : Set(NookWidgetKind.defaultEnabled)
        if let without { enabled.remove(without) }
        state.enabledWidgets = enabled
        state.nookPlacements = NookDisplayPreferences().placements(enabled: Array(enabled))
        return state
    }

    private func render(_ name: String, _ state: OnboardingState, width: CGFloat) throws -> Data {
        let size = CGSize(width: width, height: OnboardingWindowFrame.narrowMaxHeight)
        let view = OnboardingView(tour: OnboardingTour(startingAt: .widgets, state: { state }), lang: LanguageManager.shared)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view.environment(\.nookDrawsStill, true))
        renderer.scale = Self.scale
        let image = try #require(renderer.cgImage, "ImageRenderer returned no image")
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        if ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_SNAPSHOTS"] == "1" {
            let directory = HangoverBrandTests.repoRoot.appendingPathComponent("output/render/onboarding", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return png
    }

    /// The page is live: the tour only ever draws it in the narrow window.
    /// That window scrolls the page's choices when the screen is short, and
    /// at its tallest the ten rows of the release app sit in it whole, and the
    /// dev copy's eleventh, Link to MP3, is a scroll away.
    @Test func theWidgetsPageIsLiveAndGetsTheNarrowWindowInEveryLength() {
        #expect(OnboardingPage.widgets.isLive)
        for length in OnboardingLength.allCases {
            var state = OnboardingState()
            state.length = length
            #expect(OnboardingTour.pages(for: state).contains(.widgets), "\(length) leaves the widgets page out")
        }
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let island = CGRect(x: 456, y: 700, width: 600, height: 282)
        let frame = OnboardingWindowFrame.frame(isLive: OnboardingPage.widgets.isLive, screen: screen, island: island)
        #expect(OnboardingWindowFrame.narrowWidthRange.contains(frame.width))
        #expect(frame.height == OnboardingWindowFrame.narrowMaxHeight)
    }

    /// The last row's switch is what shows whether the page reaches it: the
    /// picture differs between Link to MP3 on and off only if that row is
    /// drawn. The pictures written with OPEN_ISLAND_RENDER_SNAPSHOTS=1 show
    /// the whole page.
    @Test(arguments: OnboardingTestSize.narrowWidths)
    func theLastRowIsDrawnAtEachNarrowWidth(width: CGFloat) throws {
        let on = try render("07-widgets-eleven-on-\(Int(width))", Self.state(allOn: true), width: width)
        let withoutLast = try render(
            "07-widgets-eleven-last-off-\(Int(width))",
            Self.state(allOn: true, without: .linkAudio),
            width: width
        )
        #expect(on != withoutLast, "the last row did not draw at \(Int(width)) wide")

        let fresh = try render("07-widgets-eleven-start-\(Int(width))", Self.state(allOn: false), width: width)
        #expect(fresh != on)
    }
}
