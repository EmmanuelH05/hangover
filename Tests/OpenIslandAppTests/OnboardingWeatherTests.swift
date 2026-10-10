import Foundation
import Testing
@testable import OpenIslandApp

// The tour's weather page (D43, D44): where the user is. The weather service
// gets a transport that replays saved answers and a `TestDefaults`, so no
// test here reaches the network, the real settings or a window.

@MainActor
struct OnboardingWeatherTests {
    private typealias Fixtures = NookWeatherFixtures

    /// A service as the app starts it, with the widget switched on.
    @MainActor private final class Rig {
        let transport = StubWeatherTransport { url in
            url.host == NookWeatherClient.searchHost
                ? .body(NookWeatherFixtures.search, status: 200)
                : .body(NookWeatherFixtures.forecast, status: 200)
        }
        let store = TestDefaults("tour-weather")
        let clock = ManualClock(NookWeatherFixtures.fetchedAt)

        func service() -> NookWeatherService {
            let clock = clock
            let service = NookWeatherService(transport: transport, defaults: store.defaults, now: { clock.now })
            service.isSwitchedOn = { true }
            return service
        }

        /// The page's actions, wired to `service` the way
        /// `AppModel.onboardingActions` wires them.
        func actions(_ service: NookWeatherService) -> OnboardingActions {
            OnboardingActions(
                searchWeather: { service.search($0, language: "en") },
                chooseWeatherPlace: { service.setPlace($0) },
                setWeatherUnit: { service.unit = $0 }
            )
        }
    }

    // MARK: The page follows the widget

    @Test func theWeatherPageIsLeftOutWhileTheWeatherWidgetIsOff() {
        let with = OnboardingPage.shown(agentsEnabled: true, hasWeatherWidget: true)
        let without = OnboardingPage.shown(agentsEnabled: true, hasWeatherWidget: false)

        #expect(with == OnboardingPage.allCases)
        #expect(without == OnboardingPage.allCases.filter { $0 != .weather })
        #expect(OnboardingPage.allCases.filter(\.needsWeatherWidget) == [.weather])
        #expect(OnboardingPage.weather.isLive)
        #expect(OnboardingPage.weather.chapter == .yours)
        // It sits right after the notes page.
        #expect(OnboardingPage.notes.next == .weather)
        #expect(OnboardingPage.weather.next == .opened)
        #expect(OnboardingPage.landing(.weather, in: without) == .notes)
    }

    @Test func thePageListAndTheStepCountCountTheWeatherPage() {
        #expect(OnboardingPage.shown(agentsEnabled: true).count == 18)
        #expect(OnboardingPage.shown(agentsEnabled: true, hasWeatherWidget: false).count == 17)
        // Everything optional off: welcome to the widgets, layout and
        // arrange, then the opened island and the last chapter.
        #expect(OnboardingPage.shown(
            agentsEnabled: false, hasTodoWidget: false, hasNotesWidget: false, hasWeatherWidget: false
        ) == [
            .welcome, .purpose, .opening, .closed, .widgets, .features, .layout, .arrange, .opened, .look,
            .permissions, .integrations, .tips, .done,
        ])
    }

    @Test func theTourWalksTheWeatherPageOnlyWhileTheWidgetIsOnThePage() {
        var widgets = Set(NookWidgetKind.defaultEnabled)
        let tour = OnboardingTour(startingAt: .notes, state: { OnboardingState(enabledWidgets: widgets) })
        tour.next()
        #expect(tour.page == .opened, "weather starts switched off, so its page is not walked")

        widgets.insert(.weather)
        tour.back()
        #expect(tour.page == .weather)
        #expect(tour.pages.contains(.weather))
        tour.next()
        #expect(tour.page == .opened)

        tour.back()
        widgets.remove(.weather)
        #expect(tour.page == .notes, "a page taken out while it is up gives way to the one before it")
    }

    // MARK: The search

    @Test func aSearchThatFindsPlacesListsThemAllAndSaysNothingElse() async {
        let rig = Rig()
        defer { rig.store.remove() }
        let service = rig.service()

        rig.actions(service).searchWeather("Los Angeles")
        #expect(OnboardingWeatherSetup(reading: service).isSearching)
        await service.waitForSearch()

        let setup = OnboardingWeatherSetup(reading: service)
        #expect(setup.results.map(\.label) == [
            "Los Angeles, California, United States", "Los Ángeles, Biobio, Chile", "Los Ángeles, Panama",
        ])
        #expect(setup.searchProblemKey == nil)
        #expect(setup.place == nil)
        #expect(setup.forecastKey == nil)
        #expect(rig.transport.requests.count == 1)
    }

    @Test func aSearchThatFindsNothingGetsTheSettingsSentence() async throws {
        let rig = Rig()
        defer { rig.store.remove() }
        rig.transport.setResponder { _ in .body(Fixtures.noMatch, status: 200) }
        let service = rig.service()

        rig.actions(service).searchWeather("Qwxzv")
        await service.waitForSearch()

        let setup = OnboardingWeatherSetup(reading: service)
        #expect(setup.results.isEmpty)
        #expect(setup.search == .noMatch)
        let key = try #require(setup.searchProblemKey)
        #expect(key == "nook.weather.settings.noMatch")
        #expect(try HangoverBrandTests.table("en")[key] == "No place by that name.")
    }

    @Test func aSearchThatFailsBecauseTheMacIsOfflineSaysSo() async throws {
        let rig = Rig()
        defer { rig.store.remove() }
        rig.transport.setResponder { _ in .offline }
        let service = rig.service()

        rig.actions(service).searchWeather("Tokyo")
        await service.waitForSearch()

        let setup = OnboardingWeatherSetup(reading: service)
        #expect(setup.search == .failed(.offline))
        let key = try #require(setup.searchProblemKey)
        #expect(try HangoverBrandTests.table("en")[key] == "You are offline. Connect to the internet, then search again.")
    }

    @Test func aSearchTheServiceDidNotAnswerGetsItsOwnSentence() async throws {
        let rig = Rig()
        defer { rig.store.remove() }
        rig.transport.setResponder { _ in .body("{}", status: 500) }
        let service = rig.service()

        rig.actions(service).searchWeather("Tokyo")
        await service.waitForSearch()

        let key = try #require(OnboardingWeatherSetup(reading: service).searchProblemKey)
        #expect(key == "onboarding.weather.search.server")
    }

    // MARK: The pick

    @Test func aPickSavesWhatSettingsSavesAndTheCardStartsLoading() async throws {
        let rig = Rig()
        defer { rig.store.remove() }
        let service = rig.service()
        let actions = rig.actions(service)
        actions.searchWeather("Los Angeles")
        await service.waitForSearch()

        actions.chooseWeatherPlace(Fixtures.losAngeles)

        // The same value `setPlace` keeps for Settings.
        let saved = try #require(rig.store.defaults.data(forKey: NookWeatherService.placeKey))
        #expect(try JSONDecoder().decode(NookWeatherPlace.self, from: saved) == Fixtures.losAngeles)
        var setup = OnboardingWeatherSetup(reading: service)
        #expect(setup.place == Fixtures.losAngeles)
        #expect(setup.results.isEmpty, "the list goes once a place is picked")
        #expect(setup.forecast == .loading)
        #expect(setup.forecastKey == "onboarding.weather.filling")

        await service.waitForRefresh()
        setup = OnboardingWeatherSetup(reading: service)
        #expect(setup.hasReport)
        #expect(setup.forecastKey == "onboarding.weather.filled")
        #expect(rig.transport.requests.filter { $0.host == NookWeatherClient.forecastHost }.count == 1)
    }

    @Test func aFailedForecastIsWordedAsTheCardWordsIt() async {
        let rig = Rig()
        defer { rig.store.remove() }
        rig.transport.setResponder { url in
            url.host == NookWeatherClient.searchHost ? .body(Fixtures.search, status: 200) : .offline
        }
        let service = rig.service()

        service.setPlace(Fixtures.tokyo)
        await service.waitForRefresh()

        #expect(OnboardingWeatherSetup(reading: service).forecastKey == "nook.weather.failed.offline")
    }

    @Test func theUnitChoiceWritesTheUnitSettingsWrites() {
        let rig = Rig()
        defer { rig.store.remove() }
        let service = rig.service()
        #expect(OnboardingWeatherSetup(reading: service).unit == .fahrenheit)

        rig.actions(service).setWeatherUnit(.celsius)

        #expect(rig.store.defaults.string(forKey: NookWeatherService.unitKey) == "celsius")
        #expect(OnboardingWeatherSetup(reading: service).unit == .celsius)
        rig.actions(service).setWeatherUnit(.fahrenheit)
        #expect(rig.store.defaults.string(forKey: NookWeatherService.unitKey) == "fahrenheit")
    }

    @Test func aPlaceSetBeforeTheTourShowsAsSet() async throws {
        let rig = Rig()
        defer { rig.store.remove() }
        let before = rig.service()
        before.setPlace(Fixtures.losAngeles)
        await before.waitForRefresh()

        // The app starts again with the place and its report on disk.
        let later = rig.service()
        let setup = OnboardingWeatherSetup(reading: later)

        #expect(setup.place == Fixtures.losAngeles)
        #expect(setup.hasReport)
        #expect(setup.forecastKey == "onboarding.weather.filled")
    }

    @Test func theToursActionsReachTheAppOnce() {
        var searches: [String] = []
        var picks: [NookWeatherPlace] = []
        var units: [NookTemperatureUnit] = []
        let tour = OnboardingTour(
            startingAt: .weather,
            state: { OnboardingState() },
            actions: OnboardingActions(
                searchWeather: { searches.append($0) },
                chooseWeatherPlace: { picks.append($0) },
                setWeatherUnit: { units.append($0) }
            )
        )
        tour.actions.searchWeather("Tokyo")
        tour.actions.chooseWeatherPlace(Fixtures.tokyo)
        tour.actions.setWeatherUnit(.celsius)

        #expect(searches == ["Tokyo"])
        #expect(picks == [Fixtures.tokyo])
        #expect(units == [.celsius])
    }

    @Test func theAppWiresThePageToTheCallsSettingsMakes() throws {
        let source = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/AppModel+Onboarding.swift")
        let settings = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Nook/Widgets/Weather/NookWeatherSettings.swift")
        #expect(source.contains("nook.weather.search(text, language: lang.language.resolvedCode)"))
        #expect(source.contains("chooseWeatherPlace: { [weak self] in self?.nook.weather.setPlace($0) }"))
        #expect(source.contains("setWeatherUnit: { [weak self] in self?.nook.weather.unit = $0 }"))
        #expect(source.contains("OnboardingWeatherSetup(reading: nook.weather)"))
        #expect(settings.contains("weather.setPlace(place)"))
        #expect(settings.contains("set: { weather.unit = $0 }"))
        #expect(settings.contains("nook.weather.search(query, language: lang.language.resolvedCode)"))
    }

    // MARK: The recap and the words

    @Test func theRecapNamesThePlaceOnlyWhileTheWeatherWidgetIsOn() {
        #expect(OnboardingRecapRow.shown(agentsEnabled: true).contains(.weather))
        #expect(OnboardingRecapRow.shown(agentsEnabled: true, hasWeatherWidget: false)
            == OnboardingRecapRow.allCases.filter { $0 != .weather })
        // Right after the notes row.
        let rows = OnboardingRecapRow.shown(agentsEnabled: true)
        #expect(rows.firstIndex(of: .weather) == (rows.firstIndex(of: .notes) ?? -2) + 1)
    }

    @Test func everyLanguageHasTheWeatherWords() throws {
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let table = try HangoverBrandTests.table(language)
            for key in [
                "onboarding.weather.title", "onboarding.weather.body", "onboarding.weather.note",
                "onboarding.weather.unset", "onboarding.weather.set", "onboarding.weather.change",
                "onboarding.weather.keep", "onboarding.weather.filling", "onboarding.weather.filled",
                "onboarding.weather.unit", "onboarding.weather.search.offline", "onboarding.weather.search.server",
                "onboarding.done.recap.weather", "onboarding.done.recap.weather.none",
            ] {
                #expect(table[key] != nil, "\(language) is missing \(key)")
            }
        }
        let english = try HangoverBrandTests.table("en")
        #expect(english["onboarding.weather.title"] == "Where are you?")
        #expect(english["onboarding.weather.set"] == "Your place is set")
    }

    @Test func theTourOffersNoCurrentLocationBecauseSettingsHasNone() throws {
        let folder = HangoverBrandTests.repoRoot.appendingPathComponent("Sources/OpenIslandApp")
        let files = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
        for case let file as URL in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("import CoreLocation"), "\(file.lastPathComponent) uses CoreLocation")
        }
    }
}
