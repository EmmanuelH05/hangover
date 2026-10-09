import Foundation
import Observation
import OSLog

private let weatherLog = Logger(subsystem: "app.openisland", category: "nook.weather")

/// Decides when the weather may be asked for again. Pure value type: the
/// service owns one and feeds it the clock, which keeps the rule testable.
struct NookWeatherRefreshRule: Equatable, Sendable {
    /// A good answer is kept this long before the next request.
    static let minimumSpacing: TimeInterval = 15 * 60
    /// From this age on the tile says how old its numbers are.
    static let staleAfter: TimeInterval = 30 * 60
    /// After a failure: one minute, then two, four and upward to the cap.
    static let retryBase: TimeInterval = 60
    static let retryCap: TimeInterval = minimumSpacing

    private(set) var lastSuccess: Date?
    private(set) var lastAttempt: Date?
    private(set) var failures = 0

    init(lastSuccess: Date? = nil) {
        self.lastSuccess = lastSuccess
    }

    func shouldRefresh(now: Date) -> Bool {
        if let lastSuccess, now.timeIntervalSince(lastSuccess) < Self.minimumSpacing { return false }
        if failures > 0, let lastAttempt {
            return now.timeIntervalSince(lastAttempt) >= Self.retryDelay(afterFailures: failures)
        }
        return true
    }

    mutating func recordAttempt(now: Date) {
        lastAttempt = now
    }

    mutating func recordSuccess(now: Date) {
        lastSuccess = now
        failures = 0
    }

    mutating func recordFailure() {
        failures += 1
    }

    static func retryDelay(afterFailures count: Int) -> TimeInterval {
        guard count > 0 else { return 0 }
        return min(retryBase * pow(2, Double(min(count - 1, 16))), retryCap)
    }

    static func isStale(fetchedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(fetchedAt) >= staleAfter
    }
}

/// How old a report is, in the unit the tile words it in.
enum NookWeatherAge: Equatable, Sendable {
    case minutes(Int)
    case hours(Int)
    case days(Int)

    init(fetchedAt: Date, now: Date) {
        let minutes = max(0, Int(now.timeIntervalSince(fetchedAt) / 60))
        if minutes < 60 {
            self = .minutes(minutes)
        } else if minutes < 60 * 24 {
            self = .hours(minutes / 60)
        } else {
            self = .days(minutes / (60 * 24))
        }
    }
}

/// The weather tile's data: the chosen city, the last report and the place
/// search in Settings.
///
/// Nothing here reaches the network unless the Weather widget is switched
/// on, and it asks only when the tile is on screen or the city changes.
/// What goes out is the city name typed into the search, and that city's
/// coordinates rounded to about a kilometer.
@MainActor
@Observable
final class NookWeatherService {
    static let placeKey = "nook.weather.place"
    static let reportKey = "nook.weather.report"
    static let unitKey = "nook.weather.unit"
    static let forecastModeKey = "nook.weather.forecastMode"

    enum Status: Equatable, Sendable {
        case idle
        case loading
        case failed(NookWeatherError)
    }

    enum SearchStatus: Equatable, Sendable {
        case idle
        case searching
        /// The search worked and found no such place.
        case noMatch
        case failed(NookWeatherError)
    }

    private(set) var place: NookWeatherPlace?
    private(set) var report: NookWeatherReport?
    private(set) var status: Status = .idle
    private(set) var searchResults: [NookWeatherPlace] = []
    private(set) var searchStatus: SearchStatus = .idle

    var unit: NookTemperatureUnit {
        didSet { if unit != oldValue { defaults.set(unit.rawValue, forKey: Self.unitKey) } }
    }

    /// Hours or the week in the tile's forecast row. Remembered, and a
    /// choice of what to draw only: both come in the same report.
    var forecastMode: NookWeatherForecastMode {
        didSet {
            if forecastMode != oldValue { defaults.set(forecastMode.rawValue, forKey: Self.forecastModeKey) }
        }
    }

    /// Whether the Weather widget is switched on. `start` installs the real
    /// answer; a bare service stays off the network.
    @ObservationIgnored var isSwitchedOn: () -> Bool = { false }

    @ObservationIgnored private let client: NookWeatherClient
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var rule: NookWeatherRefreshRule
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(
        transport: any NookWeatherTransport = NookWeatherURLSessionTransport(),
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        client = NookWeatherClient(transport: transport)
        self.defaults = defaults
        self.now = now
        unit = defaults.string(forKey: Self.unitKey).flatMap(NookTemperatureUnit.init(rawValue:)) ?? .fahrenheit
        forecastMode = defaults.string(forKey: Self.forecastModeKey)
            .flatMap(NookWeatherForecastMode.init(rawValue:)) ?? .hours
        let savedPlace = Self.decode(NookWeatherPlace.self, from: defaults, key: Self.placeKey)
        let savedReport = Self.decode(NookWeatherReport.self, from: defaults, key: Self.reportKey)
        // A saved report is only good for the saved city.
        let cached = savedPlace == nil ? nil : savedReport
        place = savedPlace
        report = cached
        rule = NookWeatherRefreshRule(lastSuccess: cached?.fetchedAt)
    }

    /// Makes no request. The tile asks when it comes on screen.
    func start(nook: NookModel) {
        isSwitchedOn = { [weak nook] in nook?.isWidgetEnabled(.weather) ?? false }
    }

    /// Reads a saved value. One that no longer reads counts as not saved,
    /// and the log says which key and which field, never what it held.
    private static func decode<Value: Decodable>(_ type: Value.Type, from defaults: UserDefaults, key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            weatherLog.warning("saved \(key, privacy: .public) not read: \(NookWeatherParser.describe(error), privacy: .public)")
            return nil
        }
    }

    private func save<Value: Encodable>(_ value: Value?, key: String) {
        guard let value else {
            defaults.removeObject(forKey: key)
            return
        }
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            // Only a number that is not finite can do this. The key is
            // cleared, which keeps an older value from standing in.
            weatherLog.error("could not save \(key, privacy: .public): \(String(describing: type(of: error)), privacy: .public)")
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: Report

    /// True when the report is old enough that the tile should give its age.
    func isStale(at moment: Date) -> Bool {
        guard let report else { return false }
        return NookWeatherRefreshRule.isStale(fetchedAt: report.fetchedAt, now: moment)
    }

    /// Asks for a new report when the widget is on, a city is chosen and
    /// the last good answer is at least fifteen minutes old.
    func refreshIfDue() {
        guard isSwitchedOn(), let place, refreshTask == nil, rule.shouldRefresh(now: now()) else { return }
        rule.recordAttempt(now: now())
        status = .loading
        refreshTask = Task { @MainActor [weak self, client, now] in
            let result: Result<NookWeatherReport, NookWeatherError>
            do {
                result = .success(try await client.forecast(for: place, now: now()))
            } catch let error as NookWeatherError {
                result = .failure(error)
            } catch {
                result = .failure(.malformed)
            }
            self?.finishRefresh(result, for: place)
        }
    }

    private func finishRefresh(_ result: Result<NookWeatherReport, NookWeatherError>, for requested: NookWeatherPlace) {
        refreshTask = nil
        // The city changed while this was in flight: its own request is next.
        guard requested == place else {
            status = .idle
            refreshIfDue()
            return
        }
        switch result {
        case let .success(fresh):
            report = fresh
            save(fresh, key: Self.reportKey)
            rule.recordSuccess(now: fresh.fetchedAt)
            status = .idle
        case .failure(.cancelled):
            status = .idle
        case let .failure(error):
            weatherLog.warning("forecast failed: \(String(describing: error), privacy: .public)")
            rule.recordFailure()
            status = .failed(error)
        }
    }

    /// Lets a caller wait for the request in flight, if any.
    func waitForRefresh() async {
        await refreshTask?.value
    }

    func waitForSearch() async {
        await searchTask?.value
    }

    // MARK: Place

    /// Chooses the city. Its weather is asked for at once.
    func setPlace(_ newPlace: NookWeatherPlace) {
        searchResults = []
        searchStatus = .idle
        guard newPlace != place else { return }
        place = newPlace
        save(newPlace, key: Self.placeKey)
        report = nil
        save(NookWeatherReport?.none, key: Self.reportKey)
        rule = NookWeatherRefreshRule()
        status = .idle
        refreshIfDue()
    }

    func clearPlace() {
        place = nil
        report = nil
        save(NookWeatherPlace?.none, key: Self.placeKey)
        save(NookWeatherReport?.none, key: Self.reportKey)
        rule = NookWeatherRefreshRule()
        status = .idle
    }

    /// Looks a typed city up. Runs only on the Settings search, and only
    /// with the widget switched on.
    func search(_ text: String, language: String) {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        searchTask = nil
        guard isSwitchedOn(), !name.isEmpty else {
            searchResults = []
            searchStatus = .idle
            return
        }
        searchStatus = .searching
        searchTask = Task { @MainActor [weak self, client] in
            let result: Result<[NookWeatherPlace], NookWeatherError>
            do {
                result = .success(try await client.search(name, language: language))
            } catch let error as NookWeatherError {
                result = .failure(error)
            } catch {
                result = .failure(.malformed)
            }
            guard !Task.isCancelled, let self else { return }
            self.searchTask = nil
            switch result {
            case let .success(places):
                self.searchResults = places
                self.searchStatus = places.isEmpty ? .noMatch : .idle
            case .failure(.cancelled):
                self.searchStatus = .idle
            case let .failure(error):
                weatherLog.warning("place search failed: \(String(describing: error), privacy: .public)")
                self.searchResults = []
                self.searchStatus = .failed(error)
            }
        }
    }
}
