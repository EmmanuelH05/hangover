import Foundation

/// The sample weather (D51): a city and a canned report. Nothing here asks
/// a server for anything.
@MainActor
enum DemoWeather {
    static let place = NookWeatherPlace(
        name: "Los Angeles", region: "California", country: "United States",
        latitude: 34.05, longitude: -118.24
    )
    static let timeZoneIdentifier = "America/Los_Angeles"

    /// A report made at `now`: the reading now, 24 hours and 7 days.
    static func report(now: Date) -> NookWeatherReport {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        let offset = calendar.timeZone.secondsFromGMT(for: now)
        let thisHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        func isDay(_ date: Date) -> Bool {
            (7..<19).contains(calendar.component(.hour, from: date))
        }
        let skies = [1, 1, 2, 2, 2, 3, 3, 2, 1, 1, 0, 0]
        let hours = (0..<24).map { step -> NookWeatherReport.Moment in
            let time = thisHour.addingTimeInterval(TimeInterval(step) * NookWeatherReport.hourLength)
            let hourOfDay = Double(calendar.component(.hour, from: time))
            // A mild day: coolest before dawn, warmest in the afternoon.
            let temperature = 19.5 + 5.5 * sin((hourOfDay - 9) / 24 * 2 * .pi)
            return NookWeatherReport.Moment(
                time: time,
                temperature: (temperature * 10).rounded() / 10,
                code: skies[(step / 2) % skies.count],
                isDay: isDay(time),
                precipitationChance: skies[(step / 2) % skies.count] == 3 ? 10 : 0
            )
        }
        let startOfToday = calendar.startOfDay(for: now)
        let highs = [24.0, 25, 27, 26, 23, 22, 24]
        let lows = [15.0, 16, 17, 17, 15, 14, 15]
        let codes = [1, 1, 2, 0, 3, 61, 2]
        let chances = [0, 0, 5, 0, 20, 60, 10]
        let days = (0..<NookWeatherReport.weekLength).map { index in
            NookWeatherReport.Day(
                start: calendar.date(byAdding: .day, value: index, to: startOfToday) ?? startOfToday,
                high: highs[index],
                low: lows[index],
                code: codes[index],
                precipitationChance: chances[index]
            )
        }
        let current = NookWeatherReport.Moment(
            time: now, temperature: 22.2, code: 1, isDay: isDay(now), precipitationChance: 0
        )
        return NookWeatherReport(
            fetchedAt: now,
            utcOffsetSeconds: offset,
            timeZoneIdentifier: timeZoneIdentifier,
            current: current,
            feelsLike: 22.0,
            hours: hours,
            days: days
        )
    }

    /// Writes the city and the report where the service keeps its saved
    /// copy, in the store it was handed. The service then starts as an
    /// install that fetched them a moment ago.
    static func seed(_ defaults: UserDefaults, now: Date) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(place) {
            defaults.set(data, forKey: NookWeatherService.placeKey)
        }
        if let data = try? encoder.encode(report(now: now)) {
            defaults.set(data, forKey: NookWeatherService.reportKey)
        }
    }
}

/// The transport the demo's weather service gets. It answers every request
/// with "offline", and no request ever leaves the Mac.
struct DemoWeatherTransport: NookWeatherTransport {
    func get(_ url: URL) async throws -> (Data, Int) {
        throw NookWeatherError.offline
    }
}
