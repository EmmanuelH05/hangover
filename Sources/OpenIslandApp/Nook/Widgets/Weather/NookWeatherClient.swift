import Foundation
import OSLog

/// Log lines here name failures and fields. They never carry a request URL
/// or an answer's values, which keeps the city and its coordinates out.
private let weatherClientLog = Logger(subsystem: "app.openisland", category: "nook.weather")

/// Sends one GET request. The app uses `URLSession`; tests use a stub.
protocol NookWeatherTransport: Sendable {
    /// The body and the HTTP status.
    func get(_ url: URL) async throws -> (Data, Int)
}

struct NookWeatherURLSessionTransport: NookWeatherTransport {
    static let requestTimeout: TimeInterval = 15

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = Self.requestTimeout * 2
        configuration.waitsForConnectivity = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func get(_ url: URL) async throws -> (Data, Int) {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw NookWeatherError.malformed }
        return (data, http.statusCode)
    }
}

/// Every way a weather request can fail, sorted into the cases the tile
/// words differently.
enum NookWeatherError: Error, Equatable, Sendable {
    /// The Mac has no connection, or lost it.
    case offline
    /// The Mac is online and the service could not be reached: a name
    /// lookup, a secure connection or a timeout failed.
    case unreachable
    /// The service answered with an error status.
    case server(status: Int)
    /// The answer was not the shape this app reads.
    case malformed
    case cancelled
}

/// Reads the two Open-Meteo answers this app uses. Pure: bytes in, values
/// out, which is what the tests feed saved answers to.
enum NookWeatherParser {
    private struct Forecast: Decodable {
        struct Current: Decodable {
            let time: Double
            let temperature_2m: Double
            let apparent_temperature: Double?
            let weather_code: Int
            let is_day: Int?
        }

        struct Hourly: Decodable {
            let time: [Double]
            let temperature_2m: [Double?]
            let weather_code: [Int?]
            let is_day: [Int?]?
            let precipitation_probability: [Int?]?
        }

        struct Daily: Decodable {
            let time: [Double]
            let temperature_2m_max: [Double?]
            let temperature_2m_min: [Double?]
            let weather_code: [Int?]?
            let precipitation_probability_max: [Int?]?
        }

        let utc_offset_seconds: Int?
        let timezone: String?
        let current: Current
        let hourly: Hourly?
        let daily: Daily?
    }

    private struct Search: Decodable {
        struct Result: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let admin1: String?
            let country: String?
        }

        let results: [Result]?
    }

    /// A forecast answer with temperatures in Celsius and times in unix
    /// seconds, which is what `NookWeatherClient.forecastURL` asks for.
    static func report(from data: Data, fetchedAt: Date) throws -> NookWeatherReport {
        let forecast: Forecast
        do {
            forecast = try JSONDecoder().decode(Forecast.self, from: data)
        } catch {
            weatherClientLog.warning("forecast answer not read: \(describe(error), privacy: .public)")
            throw NookWeatherError.malformed
        }
        let current = NookWeatherReport.Moment(
            time: Date(timeIntervalSince1970: forecast.current.time),
            temperature: forecast.current.temperature_2m,
            code: forecast.current.weather_code,
            isDay: (forecast.current.is_day ?? 1) != 0,
            precipitationChance: nil
        )
        return NookWeatherReport(
            fetchedAt: fetchedAt,
            utcOffsetSeconds: forecast.utc_offset_seconds ?? 0,
            timeZoneIdentifier: forecast.timezone,
            current: current,
            feelsLike: forecast.current.apparent_temperature,
            hours: hours(forecast.hourly),
            days: days(forecast.daily)
        )
    }

    /// Hours with a gap in their numbers are left out.
    private static func hours(_ hourly: Forecast.Hourly?) -> [NookWeatherReport.Moment] {
        guard let hourly else { return [] }
        return hourly.time.indices.compactMap { index in
            guard index < hourly.temperature_2m.count, index < hourly.weather_code.count,
                  let temperature = hourly.temperature_2m[index],
                  let code = hourly.weather_code[index]
            else { return nil }
            let isDay = hourly.is_day.flatMap { index < $0.count ? $0[index] : nil } ?? 1
            let chance = hourly.precipitation_probability.flatMap { index < $0.count ? $0[index] : nil }
            return NookWeatherReport.Moment(
                time: Date(timeIntervalSince1970: hourly.time[index]),
                temperature: temperature,
                code: code,
                isDay: isDay != 0,
                precipitationChance: chance
            )
        }
    }

    private static func days(_ daily: Forecast.Daily?) -> [NookWeatherReport.Day] {
        guard let daily else { return [] }
        return daily.time.indices.compactMap { index in
            guard index < daily.temperature_2m_max.count, index < daily.temperature_2m_min.count,
                  let high = daily.temperature_2m_max[index],
                  let low = daily.temperature_2m_min[index]
            else { return nil }
            return NookWeatherReport.Day(
                start: Date(timeIntervalSince1970: daily.time[index]),
                high: high,
                low: low,
                code: daily.weather_code.flatMap { index < $0.count ? $0[index] : nil },
                precipitationChance: daily.precipitation_probability_max.flatMap { index < $0.count ? $0[index] : nil }
            )
        }
    }

    /// A place search answer. No match comes back as an answer with no
    /// `results`, which reads as an empty list.
    static func places(from data: Data) throws -> [NookWeatherPlace] {
        let search: Search
        do {
            search = try JSONDecoder().decode(Search.self, from: data)
        } catch {
            weatherClientLog.warning("place search answer not read: \(describe(error), privacy: .public)")
            throw NookWeatherError.malformed
        }
        return (search.results ?? []).map {
            NookWeatherPlace(
                name: $0.name,
                region: $0.admin1,
                country: $0.country,
                latitude: $0.latitude,
                longitude: $0.longitude
            )
        }
    }
}

extension NookWeatherParser {
    /// Which part of an answer could not be read, for the log: the kind of
    /// failure and the field it was at. Never a value.
    static func describe(_ error: Error) -> String {
        guard let error = error as? DecodingError else {
            let other = error as NSError
            return "not a decoding failure (\(other.domain) \(other.code))"
        }
        func place(_ context: DecodingError.Context) -> String {
            let path = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }
            return path.isEmpty ? "the top level" : path.joined(separator: ".")
        }
        switch error {
        case let .keyNotFound(key, context): return "no \(key.stringValue) at \(place(context))"
        case let .valueNotFound(type, context): return "no \(type) at \(place(context))"
        case let .typeMismatch(type, context): return "not a \(type) at \(place(context))"
        case let .dataCorrupted(context): return "unreadable data at \(place(context))"
        @unknown default: return "a decoding failure of an unknown kind"
        }
    }
}

/// The two Open-Meteo endpoints the weather tile needs. Open-Meteo asks for
/// no key. Its free service is for non-commercial use and its data is
/// CC BY 4.0, which is why the tile and the settings carry its credit.
struct NookWeatherClient: Sendable {
    static let forecastHost = "api.open-meteo.com"
    static let searchHost = "geocoding-api.open-meteo.com"
    static let creditURL = URL(string: "https://open-meteo.com/")!
    static let maxSearchResults = 5
    /// A week of days, today included, for the 7 day row.
    static let forecastDays = NookWeatherReport.weekLength
    /// Two days of hours from the current one, which always leaves a full
    /// evening ahead. Asked for by the hour, which keeps a week of days
    /// from bringing a week of hours with it.
    static let forecastHours = 48

    let transport: any NookWeatherTransport

    /// Coordinates go out rounded to two places, about a kilometer. A city
    /// needs no more.
    static func forecastURL(latitude: Double, longitude: Double) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = forecastHost
        components.path = "/v1/forecast"
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day,precipitation_probability"),
            URLQueryItem(
                name: "daily",
                value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"
            ),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: String(forecastDays)),
            URLQueryItem(name: "forecast_hours", value: String(forecastHours)),
        ]
        return components.url!
    }

    /// The place search knows two-letter language codes only. Given
    /// "zh-Hans" or "zh-Hant" it answers in English; given "zh" it answers
    /// in Chinese.
    static func searchLanguage(_ language: String) -> String {
        let code = language.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map { $0.lowercased() } ?? ""
        return code.count == 2 ? code : "en"
    }

    static func searchURL(name: String, language: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = searchHost
        components.path = "/v1/search"
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "count", value: String(maxSearchResults)),
            URLQueryItem(name: "language", value: searchLanguage(language)),
            URLQueryItem(name: "format", value: "json"),
        ]
        return components.url!
    }

    func forecast(for place: NookWeatherPlace, now: Date) async throws -> NookWeatherReport {
        let data = try await fetch(Self.forecastURL(latitude: place.latitude, longitude: place.longitude))
        return try NookWeatherParser.report(from: data, fetchedAt: now)
    }

    func search(_ name: String, language: String) async throws -> [NookWeatherPlace] {
        let data = try await fetch(Self.searchURL(name: name, language: language))
        return try NookWeatherParser.places(from: data)
    }

    private func fetch(_ url: URL) async throws -> Data {
        let data: Data
        let status: Int
        do {
            (data, status) = try await transport.get(url)
        } catch let error as NookWeatherError {
            throw error
        } catch is CancellationError {
            throw NookWeatherError.cancelled
        } catch {
            let sorted = Self.transportFailure(error)
            if sorted != .cancelled {
                // The domain and the code only. The error's own text can
                // carry the request URL.
                let failure = error as NSError
                weatherClientLog.warning("request to \(url.host ?? "?", privacy: .public) failed: \(failure.domain, privacy: .public) \(failure.code, privacy: .public)")
            }
            throw sorted
        }
        guard (200..<300).contains(status) else { throw NookWeatherError.server(status: status) }
        return data
    }

    /// The codes that mean this Mac has no connection. Everything else a
    /// request can fail with means the service was not reached.
    static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
    ]

    /// Sorts a failed request into the cases the tile words differently.
    static func transportFailure(_ error: Error) -> NookWeatherError {
        guard let error = error as? URLError else { return .unreachable }
        if error.code == .cancelled { return .cancelled }
        return offlineCodes.contains(error.code) ? .offline : .unreachable
    }
}
