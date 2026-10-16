import Foundation
import Testing
@testable import OpenIslandApp

// The Good to know cards for the features no other page teaches: the mirror,
// its photo booth, the weather and the accent color. A card only tells. It
// never starts the camera and never asks macOS for anything, shows whether
// the widget is on or off, and the widget's switch on it switches the widget
// and nothing else. Every claim stands on code (`OnboardingMoreProofTests`).

@MainActor
struct OnboardingMoreCardsTests {
    private static func rig() -> (AppModel, NookModel) {
        let defaults = MemoryDefaults()
        let nook = NookModel(defaults: defaults, looksForImportedGIF: false)
        let model = AppModel(agentsDefaults: MemoryDefaults(), defaults: defaults, nookModel: nook)
        nook.activeProfile = { [weak model] in model?.activeAppearanceProfile ?? .topBar }
        return (model, nook)
    }

    /// The cards are on the long tour whether or not the widget is on the
    /// widgets page: that is the case a user hit, a mirror that was off and
    /// then never explained.
    @Test func theCardsAreOnTheLongTourWhateverTheWidgetsPageSays() {
        for hasWeather in [true, false] {
            let pages = OnboardingPage.shown(length: .long, agentsEnabled: true, hasWeatherWidget: hasWeather)
            for page in [OnboardingPage.mirror, .booth, .weatherCard, .record, .convert, .accent] {
                #expect(pages.contains(page), "\(page)")
            }
            #expect(pages.contains(.weather) == hasWeather, "the weather page is for a weather widget that is on")
        }
        for length in [OnboardingLength.short, .medium] {
            let pages = OnboardingPage.shown(length: length, agentsEnabled: true)
            for page in [OnboardingPage.mirror, .booth, .weatherCard, .record, .convert, .accent] {
                #expect(!pages.contains(page))
            }
        }
        let order = OnboardingPage.shown(length: .long, agentsEnabled: true).compactMap(\.more)
        #expect(
            order.prefix(7) == [.mirror, .booth, .weather, .record, .convert, .lights, .accent],
            "the widgets first, then converting in the tray, then the lights and looks"
        )
        #expect(order.suffix(2) == [.startup, .updates], "the system last")
    }

    /// The widgets start off, and the card reads that. Its switch turns the
    /// widget on and the widget only.
    @Test func theMirrorCardsSwitchTurnsOnTheWidgetAndNeverTheCamera() {
        let (model, nook) = Self.rig()
        #expect(!model.onboardingState.more.isOn(.mirrorWidget))
        #expect(!nook.isWidgetEnabled(.mirror) && !nook.isMirrorOn)

        model.setTourMore(.mirrorWidget, enabled: true)

        #expect(nook.isWidgetEnabled(.mirror))
        #expect(model.onboardingState.more.isOn(.mirrorWidget))
        #expect(!nook.isMirrorOn, "the camera is off until the mirror's own button")
        #expect(!nook.isRingLightOn)
        #expect(!nook.photoBooth.isShowing)

        model.setTourMore(.mirrorWidget, enabled: false)
        #expect(!nook.isWidgetEnabled(.mirror))
        #expect(!model.onboardingState.more.isOn(.mirrorWidget))
    }

    @Test func theBoothCardCarriesTheSameWidgetSwitchAndTheWeatherCardItsOwn() {
        let (model, nook) = Self.rig()
        let tour = model.makeWelcomeTour(startingAt: .booth)
        tour.actions.setMore(.mirrorWidget, true)
        tour.actions.setMore(.weatherWidget, true)
        #expect(nook.isWidgetEnabled(.mirror) && nook.isWidgetEnabled(.weather))
        #expect(tour.state.moreSwitchedOn == [.mirrorWidget, .weatherWidget])
        #expect(!nook.isMirrorOn, "the booth card never starts the camera either")
    }

    /// A layout hides what it does not list. A widget switched on from its card
    /// comes back after a layout, the way the design kit does.
    @Test func aWidgetSwitchedOnFromItsCardComesBackAfterALayout() {
        let (model, nook) = Self.rig()
        let tour = model.makeWelcomeTour(startingAt: .booth)
        tour.actions.setMore(.mirrorWidget, true)

        tour.actions.applyTemplate(PersonalizationTemplate.all[0])

        #expect(nook.isWidgetEnabled(.mirror))
        #expect(nook.widgetPlacements(for: model.activeAppearanceProfile).map(\.kind).contains(.mirror))
    }

    /// Switched off again on the widgets page, in Settings or on the island,
    /// it is no longer the user's pick: a layout leaves it off and the
    /// summary does not list it.
    @Test func aCardWidgetSwitchedOffSinceIsNotPutBackByALayout() {
        let (model, nook) = Self.rig()
        let tour = model.makeWelcomeTour(startingAt: .booth)
        tour.actions.setMore(.mirrorWidget, true)
        tour.actions.setMore(.weatherWidget, true)

        // Off through the tour's own widgets page, and off behind its back.
        tour.actions.setWidget(.mirror, false)
        #expect(tour.state.moreSwitchedOn == [.weatherWidget])
        nook.setWidget(.weather, enabled: false)
        tour.actions.applyTemplate(PersonalizationTemplate.all[0])

        #expect(!nook.isWidgetEnabled(.mirror))
        #expect(!nook.isWidgetEnabled(.weather))
        #expect(tour.state.moreSwitchedOn.isEmpty)
    }

    @Test func nothingIsSwitchedOnByWalkingTheCards() {
        let (model, nook) = Self.rig()
        let tour = model.makeWelcomeTour()
        tour.answerQuestion(.long)
        tour.go(to: .mirror)
        #expect(tour.page == .mirror, "the walk starts on a Good to know page")
        let before = (nook.enabledWidgets, nook.isMirrorOn, model.onboardingState.more)
        for _ in 0..<4 { tour.next() }
        for _ in 0..<4 { tour.back() }
        tour.skip()
        #expect(nook.enabledWidgets == before.0 && nook.isMirrorOn == before.1 && model.onboardingState.more == before.2)
    }

    // MARK: What the cards say, and what stands behind it

    @Test(arguments: HangoverBrandTests.languages)
    func everyCardHasItsWordsInEveryLanguage(language: String) throws {
        let table = try HangoverBrandTests.table(language)
        for more in [OnboardingMore.mirror, .booth, .weather, .accent] {
            for key in [more.titleKey, more.textKey, more.whereKey] { #expect(!(table[key] ?? "").isEmpty, "\(language) \(key)") }
            #expect(!(table[more.noteKey] ?? "").isEmpty == more.hasNote, "\(language) \(more.noteKey)")
        }
    }

    /// The numbers the cards say are the numbers in the code: four shots, three
    /// layouts, sixteen themes.
    @Test func theBoothCardsNumbersAreTheCodesNumbers() throws {
        let english = try HangoverBrandTests.table("en")
        let text = try #require(english[OnboardingMore.booth.textKey])
        #expect(text.contains("4 pictures"))
        let booth = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Nook/Widgets/Mirror/PhotoBooth/NookPhotoBoothModel.swift")
        #expect(booth.contains("NookPhotoBoothPlan(shots: layout.shots"))
        #expect(NookPhotoStripLayout.Kind.allCases.allSatisfy { NookPhotoStripLayout.layout($0).shots == 4 })
        let feature = try #require(english[OnboardingAbility.mirrorLooks.textKey])
        #expect(feature.contains("\(NookPhotoStripLayout.Kind.allCases.count) layouts"))
        #expect(feature.contains("\(NookPhotoStripTheme.all.count) themes"))
    }

    @Test func theMirrorCardSaysWhenMacOSAsksForTheCameraAndNeverEarlier() throws {
        let english = try HangoverBrandTests.table("en")
        let note = try #require(english[OnboardingMore.mirror.noteKey])
        #expect(note.contains("camera stays off until you turn the mirror on"))
        #expect(note.contains("first time you do"))
        let card = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Nook/Widgets/Mirror/NookMirrorCard.swift")
        #expect(card.contains("(for: .video) { @Sendable _ in"), "the request lives in the mirror card, not in the tour")
        let line = try #require(english[OnboardingMoreSwitch.mirrorWidget.lineKey])
        #expect(line.contains("camera stays off"))
    }

    /// The cards never touch the camera: no tour file starts a capture session
    /// or turns the mirror on, and the widget cards ask macOS for nothing.
    @Test func noTourFileStartsTheCameraOrTurnsTheMirrorOn() throws {
        let folder = HangoverBrandTests.repoRoot.appendingPathComponent("Sources/OpenIslandApp/Onboarding")
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!source.contains("AVCaptureSession"), "\(file.lastPathComponent)")
            #expect(!source.contains("startRunning"), "\(file.lastPathComponent)")
        }
        let tour = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/AppModel+Onboarding.swift")
        #expect(tour.contains("case .mirrorWidget: setTourWidget(.mirror, enabled: enabled)"))
        #expect(!OnboardingMoreSwitch.allCases.filter(\.asksMacOS).contains(.mirrorWidget))
    }

    @Test func theWeatherCardSaysWhatIsSentAndTheAccentCardSendsTheUserToItsTab() throws {
        let english = try HangoverBrandTests.table("en")
        let note = try #require(english[OnboardingMore.weather.noteKey])
        #expect(note.contains("Open-Meteo") && note.contains("nothing is sent while the widget is off"))
        #expect(OnboardingMore.accent.settingsTab == .appearance)
        #expect(english[OnboardingMore.accent.whereKey]?.contains("Personalization tab") == true)
        #expect(english["settings.tab.appearance"] == "Personalization")
    }

    /// When the mirror's Try it steps show: on the features page of the medium
    /// and long tours, while the widget is on the page in use. The cards above
    /// do not depend on that.
    @Test func theMirrorTryItStepsShowOnlyWhileTheMirrorIsOnThePage() {
        var state = OnboardingState()
        state.length = .long
        state.enabledWidgets = Set(NookWidgetKind.defaultEnabled)
        state.nookPlacements = NookDisplayPreferences().placements(enabled: Array(state.enabledWidgets))
        #expect(!state.featureWalk.kinds.contains(.mirror), "off: no steps, and nothing explains it there")
        #expect(OnboardingPage.shown(length: .long, agentsEnabled: true).contains(.mirror), "the card does")

        state.enabledWidgets.insert(.mirror)
        state.nookPlacements = NookDisplayPreferences().placements(enabled: Array(state.enabledWidgets))
        #expect(state.featureWalk.kinds.contains(.mirror))
        #expect(OnboardingTry.mirrorOn.widget == .mirror && OnboardingTry.photoBooth.widget == .mirror)

        state.nookPlacements = state.nookPlacements?.filter { $0.kind != .mirror }
        #expect(!state.featureWalk.kinds.contains(.mirror), "hidden on this display's page")
        #expect(!OnboardingPage.shown(length: .short, agentsEnabled: true).contains(.features))
    }
}
