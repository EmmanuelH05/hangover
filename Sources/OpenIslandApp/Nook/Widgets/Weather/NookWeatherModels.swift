import Foundation

/// A city the weather is for, as the place search returns it.
struct NookWeatherPlace: Equatable, Codable, Identifiable, Sendable {
    var name: String
    /// State or province, when the search gives one.
    var region: String?
    var country: String?
    var latitude: Double
    var longitude: Double

    var id: String { "\(latitude),\(longitude)" }

    /// "Los Angeles, California, United States", without the parts that
    /// are missing or repeat the name.
    var label: String {
        var parts = [name]
        for part in [region, country] {
            if let part, !part.isEmpty, !parts.contains(part) { parts.append(part) }
        }
        return parts.joined(separator: ", ")
    }
}

enum NookTemperatureUnit: String, CaseIterable, Identifiable, Sendable {
    case fahrenheit
    case celsius

    var id: String { rawValue }

    /// Reports are kept in Celsius. Switching units needs no new request.
    func value(celsius: Double) -> Double {
        switch self {
        case .celsius: celsius
        case .fahrenheit: celsius * 9 / 5 + 32
        }
    }

    /// "72°". The unit letter is left to the settings.
    func text(celsius: Double) -> String {
        let rounded = value(celsius: celsius).rounded()
        // Keeps "-0°" from showing just below zero.
        return "\(Int(rounded == 0 ? 0 : rounded))°"
    }
}

/// The sky, grouped from the WMO weather codes the forecast uses.
enum NookWeatherCondition: String, CaseIterable, Sendable {
    case clear
    case mostlyClear
    case partlyCloudy
    case cloudy
    case fog
    case drizzle
    case rain
    case heavyRain
    case freezingRain
    case snow
    case thunderstorm
    case unknown

    init(code: Int) {
        switch code {
        case 0: self = .clear
        case 1: self = .mostlyClear
        case 2: self = .partlyCloudy
        case 3: self = .cloudy
        case 45, 48: self = .fog
        case 51, 53, 55: self = .drizzle
        case 61, 63, 80, 81: self = .rain
        case 65, 82: self = .heavyRain
        case 56, 57, 66, 67: self = .freezingRain
        case 71, 73, 75, 77, 85, 86: self = .snow
        case 95, 96, 99: self = .thunderstorm
        default: self = .unknown
        }
    }

    var titleKey: String { "nook.weather.condition.\(rawValue)" }

    func symbol(isDay: Bool) -> String {
        switch self {
        case .clear, .mostlyClear: isDay ? "sun.max.fill" : "moon.stars.fill"
        case .partlyCloudy: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .cloudy: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .drizzle: "cloud.drizzle.fill"
        case .rain: "cloud.rain.fill"
        case .heavyRain: "cloud.heavyrain.fill"
        case .freezingRain: "cloud.sleet.fill"
        case .snow: "cloud.snow.fill"
        case .thunderstorm: "cloud.bolt.rain.fill"
        case .unknown: "thermometer.medium"
        }
    }
}

/// One answer from the forecast, kept in Celsius. Saved between launches,
/// which lets the tile show something before the first request returns.
struct NookWeatherReport: Equatable, Codable, Sendable {
    struct Moment: Equatable, Codable, Sendable {
        var time: Date
        var temperature: Double
        var code: Int
        var isDay: Bool
        /// Chance of rain or snow in percent, when the forecast gives it.
        var precipitationChance: Int?

        var condition: NookWeatherCondition { NookWeatherCondition(code: code) }
    }

    struct Day: Equatable, Codable, Sendable {
        /// Midnight in the place's own time zone.
        var start: Date
        var high: Double
        var low: Double
        /// The day's weather code. Nil in a report saved before the week
        /// was kept, which had the high and the low only.
        var code: Int? = nil
        /// The day's highest chance of rain or snow in percent, when the
        /// forecast gives it.
        var precipitationChance: Int? = nil

        var condition: NookWeatherCondition? { code.map(NookWeatherCondition.init(code:)) }
    }

    static let hourLength: TimeInterval = 3600
    /// Days in the week row, today included.
    static let weekLength = 7

    var fetchedAt: Date
    /// The place's offset from UTC when the report was made. Used when the
    /// report names no time zone.
    var utcOffsetSeconds: Int
    /// The place's time zone, such as "America/Los_Angeles". Nil in a report
    /// saved before this was kept.
    var timeZoneIdentifier: String? = nil
    var current: Moment
    var feelsLike: Double?
    var hours: [Moment]
    var days: [Day]

    /// The place's time zone, for the hour labels and the day's bounds. The
    /// named zone knows the days the clocks change; the bare offset is the
    /// fallback and is an hour out for part of such a day.
    var timeZone: TimeZone {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? TimeZone(secondsFromGMT: utcOffsetSeconds)
            ?? .gmt
    }

    /// What it is like now. A report older than an hour answers from its
    /// own hourly forecast, which keeps a saved tile close to the truth.
    func conditions(at now: Date) -> Moment {
        guard now.timeIntervalSince(fetchedAt) >= Self.hourLength else { return current }
        return hours.last { $0.time <= now && now.timeIntervalSince($0.time) < Self.hourLength } ?? current
    }

    /// The next hours after `now`, soonest first.
    func upcomingHours(after now: Date, count: Int) -> [Moment] {
        Array(hours.filter { $0.time > now }.prefix(max(0, count)))
    }

    /// The high and low of the day `now` falls in, or nil once the report
    /// no longer covers that day. Days are the place's calendar days, which
    /// are 23 or 25 hours long when its clocks change.
    func day(at now: Date) -> Day? {
        days.first { placeCalendar.isDate($0.start, inSameDayAs: now) }
    }

    /// The days of the week row: the place's own today and the days after
    /// it, soonest first. Only a day that carries its sky counts, which
    /// leaves a report saved before the week was kept with no week at all.
    func week(from now: Date, count: Int = weekLength) -> [Day] {
        let calendar = placeCalendar
        let upcoming = days.filter { day in
            day.code != nil && calendar.compare(day.start, to: now, toGranularity: .day) != .orderedAscending
        }
        return Array(upcoming.sorted { $0.start < $1.start }.prefix(max(0, count)))
    }

    /// True when a day is the place's own today.
    func isToday(_ day: Day, at now: Date) -> Bool {
        placeCalendar.isDate(day.start, inSameDayAs: now)
    }

    /// The calendar the place's days are counted in.
    private var placeCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

/// What the tile's forecast row shows: the next hours, or the week.
enum NookWeatherForecastMode: String, CaseIterable, Identifiable, Sendable {
    case hours
    case week

    var id: String { rawValue }

    var titleKey: String { "nook.weather.mode.\(rawValue)" }
}
