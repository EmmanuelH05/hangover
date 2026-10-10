import Foundation

// The weather page asks where the user is (D43, D44). What it draws is a
// function of this plain value, read from `NookWeatherService` by the app.
// A snapshot and a test hand in a fixed one.

/// What the weather page needs to know. The typed city is not part of it:
/// the text lives in the page's own field.
struct OnboardingWeatherSetup: Equatable, Sendable {
    /// The saved place, set here or before the tour.
    var place: NookWeatherPlace?
    var unit: NookTemperatureUnit = .fahrenheit
    /// What the last search found, as the service holds it.
    var results: [NookWeatherPlace] = []
    var search: NookWeatherService.SearchStatus = .idle
    /// Where the weather card's request for the saved place stands.
    var forecast: NookWeatherService.Status = .idle
    /// The service holds a report for the saved place, which is what the
    /// card on the real island draws.
    var hasReport = false

    init() {}

    init(
        place: NookWeatherPlace?,
        unit: NookTemperatureUnit = .fahrenheit,
        results: [NookWeatherPlace] = [],
        search: NookWeatherService.SearchStatus = .idle,
        forecast: NookWeatherService.Status = .idle,
        hasReport: Bool = false
    ) {
        self.place = place
        self.unit = unit
        self.results = results
        self.search = search
        self.forecast = forecast
        self.hasReport = hasReport
    }

    /// What the weather service says now: the app reads the page's state
    /// from here, on every draw.
    @MainActor
    init(reading service: NookWeatherService) {
        self.init(
            place: service.place,
            unit: service.unit,
            results: service.searchResults,
            search: service.searchStatus,
            forecast: service.status,
            hasReport: service.report != nil
        )
    }

    /// True while a search is running.
    var isSearching: Bool { search == .searching }

    /// The string key of the plain line under the tick, from what the card
    /// on the real island is doing. Nil while no place is saved.
    var forecastKey: String? {
        guard place != nil else { return nil }
        if hasReport { return "onboarding.weather.filled" }
        switch forecast {
        case .failed(.offline): return "nook.weather.failed.offline"
        case .failed: return "nook.weather.failed.server"
        case .idle, .loading: return "onboarding.weather.filling"
        }
    }

    /// The string key of the sentence a search that did not find places
    /// gets. Nil for a search that is idle, running or found some.
    var searchProblemKey: String? {
        switch search {
        case .noMatch: "nook.weather.settings.noMatch"
        case .failed(.offline): "onboarding.weather.search.offline"
        case .failed: "onboarding.weather.search.server"
        case .idle, .searching: nil
        }
    }
}
