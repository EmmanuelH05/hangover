import Foundation
import Testing
@testable import OpenIslandApp

/// Saved answers from Open-Meteo, fetched once by hand. No test here makes
/// a request: the service gets a transport that only replays these.
enum NookWeatherFixtures {
    /// The forecast for Los Angeles, in Celsius, as the app asked for it
    /// before the week was kept: two days, with a high and a low and no sky.
    static let forecast = #"""
    {"latitude":34.060257,"longitude":-118.23433,"generationtime_ms":0.7420778274536133,"utc_offset_seconds":-25200,"timezone":"America/Los_Angeles","timezone_abbreviation":"GMT-7","elevation":87.0,"current_units":{"time":"unixtime","interval":"seconds","temperature_2m":"°C","apparent_temperature":"°C","weather_code":"wmo code","is_day":""},"current":{"time":1791521100,"interval":900,"temperature_2m":21.5,"apparent_temperature":24.4,"weather_code":2,"is_day":0},"hourly_units":{"time":"unixtime","temperature_2m":"°C","weather_code":"wmo code","is_day":"","precipitation_probability":"%"},"hourly":{"time":[1791442800,1791446400,1791450000,1791453600,1791457200,1791460800,1791464400,1791468000,1791471600,1791475200,1791478800,1791482400,1791486000,1791489600,1791493200,1791496800,1791500400,1791504000,1791507600,1791511200,1791514800,1791518400,1791522000,1791525600,1791529200,1791532800,1791536400,1791540000,1791543600,1791547200,1791550800,1791554400,1791558000,1791561600,1791565200,1791568800,1791572400,1791576000,1791579600,1791583200,1791586800,1791590400,1791594000,1791597600,1791601200,1791604800,1791608400,1791612000],"temperature_2m":[21.1,20.8,21.9,21.1,20.6,20.4,19.5,19.0,21.6,25.1,28.2,30.5,33.4,34.3,32.9,31.9,30.3,29.5,27.3,26.2,23.3,21.8,21.5,21.3,20.9,20.0,19.3,18.8,18.2,17.7,17.5,17.5,18.3,20.9,23.7,26.8,29.2,30.1,29.6,28.4,26.9,24.7,22.1,20.5,20.0,19.9,19.7,19.4],"weather_code":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,2,0,1,0,1,0,0,1,45,45,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],"is_day":[0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0],"precipitation_probability":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1]},"daily_units":{"time":"unixtime","temperature_2m_max":"°C","temperature_2m_min":"°C"},"daily":{"time":[1791442800,1791529200],"temperature_2m_max":[34.3,30.1],"temperature_2m_min":[19.0,17.5]}}
    """#

    /// The same request as the app sends it now, a week of days with their
    /// sky and 48 hours from the current one, fetched once by hand.
    static let forecastWeek = #"""
    {"latitude":34.060257,"longitude":-118.23433,"generationtime_ms":1.172780990600586,"utc_offset_seconds":-25200,"timezone":"America/Los_Angeles","timezone_abbreviation":"GMT-7","elevation":87,"current_units":{"time":"unixtime","interval":"seconds","temperature_2m":"°C","apparent_temperature":"°C","weather_code":"wmo code","is_day":""},"current":{"time":1791542700,"interval":900,"temperature_2m":19.5,"apparent_temperature":22.3,"weather_code":3,"is_day":0},"hourly_units":{"time":"unixtime","temperature_2m":"°C","weather_code":"wmo code","is_day":"","precipitation_probability":"%"},"hourly":{"time":[1791540000,1791543600,1791547200,1791550800,1791554400,1791558000,1791561600,1791565200,1791568800,1791572400,1791576000,1791579600,1791583200,1791586800,1791590400,1791594000,1791597600,1791601200,1791604800,1791608400,1791612000,1791615600,1791619200,1791622800,1791626400,1791630000,1791633600,1791637200,1791640800,1791644400,1791648000,1791651600,1791655200,1791658800,1791662400,1791666000,1791669600,1791673200,1791676800,1791680400,1791684000,1791687600,1791691200,1791694800,1791698400,1791702000,1791705600,1791709200],"temperature_2m":[19.7,19.4,18.9,18.6,18.1,19.3,21.9,24.3,27,29.2,29.6,29.3,28.3,27.2,25.5,22.8,20.9,20.1,19.7,19.5,19.5,19.2,18.9,18.5,17.9,18.3,18.5,18.3,18.1,19.4,20.9,21.9,22.9,25,25.6,24.6,24.5,24,22.6,22.1,21.3,20.4,21,22.5,24.3,25.6,25.5,25.4],"weather_code":[1,3,3,2,2,1,0,0,0,0,0,0,0,0,0,0,0,0,1,1,2,0,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,51,3,3,3,3,3,3],"is_day":[0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0],"precipitation_probability":[0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,2,2,3,4,4,3,3,3,3,3,3,2,2,2,8,8,8,8,8,8,25,25,25]},"daily_units":{"time":"unixtime","weather_code":"wmo code","temperature_2m_max":"°C","temperature_2m_min":"°C","precipitation_probability_max":"%"},"daily":{"time":[1791529200,1791615600,1791702000,1791788400,1791874800,1791961200,1792047600],"weather_code":[3,51,61,53,51,0,0],"temperature_2m_max":[29.6,25.6,25.6,19.6,21.6,24.1,28.4],"temperature_2m_min":[18.1,17.9,17.8,16.5,16.8,18.4,20.1],"precipitation_probability_max":[1,8,47,69,29,1,0]}}
    """#

    /// The moment the week above was fetched: 3:45 AM on Friday 9 October
    /// 2026 in Los Angeles.
    static let weekFetchedAt = Date(timeIntervalSince1970: 1_791_542_700)

    static func weekReport() throws -> NookWeatherReport {
        try NookWeatherParser.report(from: Data(forecastWeek.utf8), fetchedAt: weekFetchedAt)
    }

    /// The place search for "Los Angeles", with the fields this app reads
    /// and a few it does not.
    static let search = #"""
    {"results":[{"id":5368361,"name":"Los Angeles","latitude":34.05223,"longitude":-118.24368,"elevation":89.0,"feature_code":"PPLA2","country_code":"US","timezone":"America/Los_Angeles","population":3820914,"country":"United States","admin1":"California"},{"id":3882428,"name":"Los Ángeles","latitude":-37.46973,"longitude":-72.35366,"country_code":"CL","country":"Chile","admin1":"Biobio"},{"id":3706567,"name":"Los Ángeles","latitude":7.88463,"longitude":-80.35497,"country_code":"PA","country":"Panama"}],"generationtime_ms":0.63}
    """#

    /// What the search answers when nothing matches.
    static let noMatch = #"{"generationtime_ms":0.5286932}"#

    /// What the forecast answers to a bad request, with status 400.
    static let rejected = #"{"reason":"Latitude must be in range of -90 to 90°. Given: 999.0.","error":true}"#

    /// The moment the forecast above was fetched.
    static let fetchedAt = Date(timeIntervalSince1970: 1_791_521_100)

    static let losAngeles = NookWeatherPlace(
        name: "Los Angeles", region: "California", country: "United States", latitude: 34.05223, longitude: -118.24368
    )
    static let tokyo = NookWeatherPlace(
        name: "Tokyo", region: "Tokyo", country: "Japan", latitude: 35.6895, longitude: 139.69171
    )

    static func report() throws -> NookWeatherReport {
        try NookWeatherParser.report(from: Data(forecast.utf8), fetchedAt: fetchedAt)
    }
}

/// A small answer shape to fail on purpose, for the log wording.
private struct NookWeatherDecodingProbe: Decodable {
    struct Inner: Decodable { let value: Double }
    let inner: Inner
    let list: [Inner]

    /// How the log would word the failure to read `json`.
    static func failure(_ json: String) -> String {
        do {
            _ = try JSONDecoder().decode(NookWeatherDecodingProbe.self, from: Data(json.utf8))
            return "decoded"
        } catch {
            return NookWeatherParser.describe(error)
        }
    }
}

@Suite struct NookWeatherParsingTests {
    private typealias Fixtures = NookWeatherFixtures

    // MARK: Reading the answers

    @Test func aSavedForecastReadsIntoAReport() throws {
        let report = try Fixtures.report()

        let temperature: Double = 21.5
        let feelsLike: Double = 24.4
        #expect(report.fetchedAt == Fixtures.fetchedAt)
        #expect(report.utcOffsetSeconds == -25200)
        #expect(report.current.temperature == temperature)
        #expect(report.feelsLike == feelsLike)
        #expect(report.current.code == 2)
        #expect(report.current.condition == .partlyCloudy)
        #expect(!report.current.isDay)
        #expect(report.hours.count == 48)
        #expect(report.hours[0].time == Date(timeIntervalSince1970: 1_791_442_800))
        #expect(report.hours[36].precipitationChance == 1)
        #expect(report.hours[30].condition == .fog)
        #expect(report.hours[7].isDay)
        #expect(report.days == [
            NookWeatherReport.Day(start: Date(timeIntervalSince1970: 1_791_442_800), high: 34.3, low: 19.0),
            NookWeatherReport.Day(start: Date(timeIntervalSince1970: 1_791_529_200), high: 30.1, low: 17.5),
        ])
    }

    @Test func anHourWithAGapInItsNumbersIsLeftOut() throws {
        let body = #"""
        {"utc_offset_seconds":0,"current":{"time":100,"temperature_2m":5.0,"weather_code":3,"is_day":1},
         "hourly":{"time":[3600,7200,10800],"temperature_2m":[1.0,null,3.0],"weather_code":[0,0,null]},
         "daily":{"time":[0],"temperature_2m_max":[null],"temperature_2m_min":[1.0]}}
        """#
        let report = try NookWeatherParser.report(from: Data(body.utf8), fetchedAt: Date(timeIntervalSince1970: 100))

        #expect(report.hours.count == 1)
        #expect(report.hours[0].time == Date(timeIntervalSince1970: 3600))
        // No day flag and no rain chance in this answer.
        #expect(report.hours[0].isDay)
        #expect(report.hours[0].precipitationChance == nil)
        #expect(report.days.isEmpty)
        #expect(report.feelsLike == nil)
    }

    @Test func aForecastWithOnlyTheCurrentNumbersStillReads() throws {
        let body = #"{"current":{"time":100,"temperature_2m":-3.5,"weather_code":71}}"#
        let report = try NookWeatherParser.report(from: Data(body.utf8), fetchedAt: Date(timeIntervalSince1970: 100))

        #expect(report.current.condition == .snow)
        #expect(report.hours.isEmpty)
        #expect(report.days.isEmpty)
        #expect(report.utcOffsetSeconds == 0)
    }

    @Test func anErrorBodyOrNonsenseIsMalformed() {
        #expect(throws: NookWeatherError.malformed) {
            try NookWeatherParser.report(from: Data(Fixtures.rejected.utf8), fetchedAt: Fixtures.fetchedAt)
        }
        #expect(throws: NookWeatherError.malformed) {
            try NookWeatherParser.report(from: Data("<html>".utf8), fetchedAt: Fixtures.fetchedAt)
        }
        #expect(throws: NookWeatherError.malformed) {
            try NookWeatherParser.places(from: Data("[]".utf8))
        }
    }

    @Test func aSavedSearchReadsIntoPlacesAndNoMatchIsAnEmptyList() throws {
        let places = try NookWeatherParser.places(from: Data(Fixtures.search.utf8))

        #expect(places.count == 3)
        #expect(places[0] == Fixtures.losAngeles)
        #expect(places[0].label == "Los Angeles, California, United States")
        // No region in the answer: the label leaves it out.
        #expect(places[2].label == "Los Ángeles, Panama")
        #expect(try NookWeatherParser.places(from: Data(Fixtures.noMatch.utf8)).isEmpty)
    }

    @Test func aPlaceLabelDoesNotRepeatItself() {
        let tokyo = Fixtures.tokyo
        #expect(tokyo.label == "Tokyo, Japan")
        let bare = NookWeatherPlace(name: "Null Island", region: "", country: nil, latitude: 0, longitude: 0)
        #expect(bare.label == "Null Island")
    }

    // MARK: Conditions and units

    @Test func everyWeatherCodeTheForecastUsesHasACondition() {
        let expected: [(codes: [Int], condition: NookWeatherCondition)] = [
            ([0], .clear), ([1], .mostlyClear), ([2], .partlyCloudy), ([3], .cloudy), ([45, 48], .fog),
            ([51, 53, 55], .drizzle), ([61, 63, 80, 81], .rain), ([65, 82], .heavyRain),
            ([56, 57, 66, 67], .freezingRain), ([71, 73, 75, 77, 85, 86], .snow), ([95, 96, 99], .thunderstorm),
            ([4, 100, -1], .unknown),
        ]
        for entry in expected {
            for code in entry.codes {
                #expect(NookWeatherCondition(code: code) == entry.condition, "code \(code)")
            }
        }
    }

    @Test func aClearSkyIsASunByDayAndAMoonByNight() {
        #expect(NookWeatherCondition.clear.symbol(isDay: true) == "sun.max.fill")
        #expect(NookWeatherCondition.clear.symbol(isDay: false) == "moon.stars.fill")
        #expect(NookWeatherCondition.partlyCloudy.symbol(isDay: true) == "cloud.sun.fill")
        #expect(NookWeatherCondition.partlyCloudy.symbol(isDay: false) == "cloud.moon.fill")
        #expect(NookWeatherCondition.rain.symbol(isDay: true) == NookWeatherCondition.rain.symbol(isDay: false))
        for condition in NookWeatherCondition.allCases {
            #expect(!condition.symbol(isDay: true).isEmpty)
            #expect(condition.titleKey == "nook.weather.condition.\(condition.rawValue)")
        }
    }

    @Test func temperaturesAreKeptInCelsiusAndShownInEitherUnit() {
        #expect(NookTemperatureUnit.celsius.text(celsius: 21.5) == "22°")
        #expect(NookTemperatureUnit.fahrenheit.text(celsius: 21.5) == "71°")
        #expect(NookTemperatureUnit.fahrenheit.text(celsius: 0) == "32°")
        #expect(NookTemperatureUnit.fahrenheit.text(celsius: -40) == "-40°")
        // Just under zero rounds to a plain zero.
        #expect(NookTemperatureUnit.celsius.text(celsius: -0.2) == "0°")
        let boiling: Double = 212
        #expect(NookTemperatureUnit.fahrenheit.value(celsius: 100) == boiling)
    }

    // MARK: Reading a report at a moment

    @Test func aFreshReportAnswersFromItsCurrentNumbersAndAnOldOneFromItsHours() throws {
        let report = try Fixtures.report()

        let soon = Fixtures.fetchedAt.addingTimeInterval(10 * 60)
        #expect(report.conditions(at: soon) == report.current)

        // Two hours on, the 11 PM hour of the forecast covers the moment.
        let later = Fixtures.fetchedAt.addingTimeInterval(2 * 3600)
        let lateEvening: Double = 21.3
        #expect(report.conditions(at: later).temperature == lateEvening)
        #expect(report.conditions(at: later).time == Date(timeIntervalSince1970: 1_791_525_600))

        // Past the end of the forecast there is only the last known reading.
        let muchLater = Fixtures.fetchedAt.addingTimeInterval(10 * 86400)
        #expect(report.conditions(at: muchLater) == report.current)
    }

    @Test func theNextHoursStartAfterNow() throws {
        let report = try Fixtures.report()

        let next = report.upcomingHours(after: Fixtures.fetchedAt, count: 3)

        #expect(next.map(\.time) == [1_791_522_000, 1_791_525_600, 1_791_529_200].map { Date(timeIntervalSince1970: $0) })
        #expect(next.map(\.temperature) == [21.5, 21.3, 20.9])
        #expect(report.upcomingHours(after: Fixtures.fetchedAt, count: 0).isEmpty)
        #expect(report.upcomingHours(after: Fixtures.fetchedAt.addingTimeInterval(10 * 86400), count: 3).isEmpty)
    }

    @Test func theHighAndLowBelongToTheDayNowFallsIn() throws {
        let report = try Fixtures.report()

        let today: Double = 34.3
        let tomorrow: Double = 30.1
        #expect(report.day(at: Fixtures.fetchedAt)?.high == today)
        #expect(report.day(at: Date(timeIntervalSince1970: 1_791_529_210))?.high == tomorrow)
        #expect(report.day(at: Fixtures.fetchedAt.addingTimeInterval(10 * 86400)) == nil)
        #expect(report.timeZone.secondsFromGMT(for: Fixtures.fetchedAt) == -25200)
    }

    @Test func theReportKeepsThePlacesTimeZoneAndFallsBackToItsOffset() throws {
        var report = try Fixtures.report()
        #expect(report.timeZoneIdentifier == "America/Los_Angeles")
        #expect(report.timeZone.identifier == "America/Los_Angeles")

        // No name, or a name this Mac does not know: the offset stands in.
        report.timeZoneIdentifier = nil
        #expect(report.timeZone.secondsFromGMT(for: Fixtures.fetchedAt) == -25200)
        report.timeZoneIdentifier = "Mars/Olympus_Mons"
        #expect(report.timeZone.secondsFromGMT(for: Fixtures.fetchedAt) == -25200)
    }

    @Test func aReportSavedBeforeTheTimeZoneWasKeptStillReads() throws {
        let report = try Fixtures.report()
        let saved = try JSONEncoder().encode(report)
        var fields = try #require(try JSONSerialization.jsonObject(with: saved) as? [String: Any])
        fields.removeValue(forKey: "timeZoneIdentifier")
        let older = try JSONSerialization.data(withJSONObject: fields)

        let read = try JSONDecoder().decode(NookWeatherReport.self, from: older)
        #expect(read.timeZoneIdentifier == nil)
        #expect(read.current == report.current)
        #expect(read.days == report.days)
    }

    @Test func theDayFollowsThePlacesCalendarOnTheDaysTheClocksChange() throws {
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        func midnight(_ month: Int, _ day: Int) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day)))
        }
        let hour: TimeInterval = 3600
        var report = try Fixtures.report()
        let first: Double = 20
        let second: Double = 30

        // The clocks go back on 1 November 2026: that day is 25 hours long.
        let longDay = try midnight(11, 1)
        let afterLong = try midnight(11, 2)
        let twentyFiveHours: TimeInterval = 25 * 3600
        #expect(afterLong.timeIntervalSince(longDay) == twentyFiveHours)
        report.days = [
            NookWeatherReport.Day(start: longDay, high: first, low: 10),
            NookWeatherReport.Day(start: afterLong, high: second, low: 15),
        ]
        // Its last hour is still that day, not a gap between two days.
        #expect(report.day(at: longDay.addingTimeInterval(24.5 * hour))?.high == first)
        #expect(report.day(at: afterLong.addingTimeInterval(60))?.high == second)

        // The clocks go forward on 8 March 2026: that day is 23 hours long.
        let shortDay = try midnight(3, 8)
        let afterShort = try midnight(3, 9)
        let twentyThreeHours: TimeInterval = 23 * 3600
        #expect(afterShort.timeIntervalSince(shortDay) == twentyThreeHours)
        report.days = [
            NookWeatherReport.Day(start: shortDay, high: first, low: 10),
            NookWeatherReport.Day(start: afterShort, high: second, low: 15),
        ]
        // Half an hour into the next day is the next day, although it is
        // inside 24 hours of the short day's start.
        #expect(report.day(at: afterShort.addingTimeInterval(0.5 * hour))?.high == second)
        #expect(report.day(at: shortDay.addingTimeInterval(22.5 * hour))?.high == first)
        #expect(report.day(at: afterShort.addingTimeInterval(30 * hour)) == nil)
    }

    @Test func theLogNamesTheFieldThatFailedAndNeverItsValue() throws {
        let failure = NookWeatherDecodingProbe.failure

        #expect(failure(#"{"inner":{},"list":[]}"#) == "no value at inner")
        let wrongType = failure(#"{"inner":{"value":"Los Angeles"},"list":[]}"#)
        #expect(wrongType == "not a Double at inner.value")
        #expect(!wrongType.contains("Los Angeles"))
        #expect(failure(#"{"inner":{"value":1},"list":[{"value":1},{"value":null}]}"#) == "no Double at list.[1].value")
        #expect(failure("<html>") == "unreadable data at the top level")
        #expect(NookWeatherParser.describe(URLError(.badURL)) == "not a decoding failure (NSURLErrorDomain -1000)")
    }

    // MARK: When to ask again

    @Test func aGoodAnswerIsKeptForFifteenMinutes() {
        let start = Fixtures.fetchedAt
        var rule = NookWeatherRefreshRule()
        #expect(rule.shouldRefresh(now: start))

        rule.recordAttempt(now: start)
        rule.recordSuccess(now: start)
        #expect(!rule.shouldRefresh(now: start.addingTimeInterval(60)))
        #expect(!rule.shouldRefresh(now: start.addingTimeInterval(15 * 60 - 1)))
        #expect(rule.shouldRefresh(now: start.addingTimeInterval(15 * 60)))
    }

    @Test func aSavedReportCountsAsTheLastGoodAnswer() {
        let rule = NookWeatherRefreshRule(lastSuccess: Fixtures.fetchedAt)
        #expect(!rule.shouldRefresh(now: Fixtures.fetchedAt.addingTimeInterval(5 * 60)))
        #expect(rule.shouldRefresh(now: Fixtures.fetchedAt.addingTimeInterval(20 * 60)))
    }

    @Test func failuresWaitLongerEachTimeUpToFifteenMinutes() {
        let start = Fixtures.fetchedAt
        var rule = NookWeatherRefreshRule()
        rule.recordAttempt(now: start)
        rule.recordFailure()
        #expect(!rule.shouldRefresh(now: start.addingTimeInterval(59)))
        #expect(rule.shouldRefresh(now: start.addingTimeInterval(60)))

        let oneMinute: TimeInterval = 60
        let twoMinutes: TimeInterval = 120
        let eightMinutes: TimeInterval = 480
        let cap: TimeInterval = 900
        let none: TimeInterval = 0
        #expect(NookWeatherRefreshRule.retryDelay(afterFailures: 0) == none)
        #expect(NookWeatherRefreshRule.retryDelay(afterFailures: 1) == oneMinute)
        #expect(NookWeatherRefreshRule.retryDelay(afterFailures: 2) == twoMinutes)
        #expect(NookWeatherRefreshRule.retryDelay(afterFailures: 4) == eightMinutes)
        #expect(NookWeatherRefreshRule.retryDelay(afterFailures: 5) == cap)
        #expect(NookWeatherRefreshRule.retryDelay(afterFailures: 40) == cap)

        // A success clears the count.
        rule.recordSuccess(now: start.addingTimeInterval(60))
        #expect(rule.failures == 0)
    }

    @Test func aReportIsStaleFromHalfAnHourAndItsAgeIsWordedByItsSize() {
        let start = Fixtures.fetchedAt
        #expect(!NookWeatherRefreshRule.isStale(fetchedAt: start, now: start.addingTimeInterval(29 * 60)))
        #expect(NookWeatherRefreshRule.isStale(fetchedAt: start, now: start.addingTimeInterval(30 * 60)))

        #expect(NookWeatherAge(fetchedAt: start, now: start.addingTimeInterval(45 * 60)) == .minutes(45))
        #expect(NookWeatherAge(fetchedAt: start, now: start.addingTimeInterval(3 * 3600 + 10)) == .hours(3))
        #expect(NookWeatherAge(fetchedAt: start, now: start.addingTimeInterval(2 * 86400 + 10)) == .days(2))
        // A clock that went backwards never gives a negative age.
        #expect(NookWeatherAge(fetchedAt: start, now: start.addingTimeInterval(-500)) == .minutes(0))
    }

    // MARK: What goes out

    @Test func theForecastRequestCarriesRoundedCoordinatesAndNoKey() throws {
        let url = NookWeatherClient.forecastURL(latitude: 34.05223, longitude: -118.24368)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        #expect(components.scheme == "https")
        #expect(components.host == "api.open-meteo.com")
        #expect(components.path == "/v1/forecast")
        #expect(items["latitude"] == "34.05")
        #expect(items["longitude"] == "-118.24")
        #expect(items["timeformat"] == "unixtime")
        #expect(items["timezone"] == "auto")
        #expect(items["forecast_days"] == "7")
        #expect(items["forecast_hours"] == "48")
        // Celsius is the service's default, and there is no key to send.
        #expect(Set(items.keys) == [
            "latitude", "longitude", "current", "hourly", "daily", "timeformat", "timezone", "forecast_days",
            "forecast_hours",
        ])
    }

    @Test func theSearchRequestCarriesTheTypedNameAndNothingElseAboutTheUser() throws {
        let url = NookWeatherClient.searchURL(name: "São Paulo", language: "en")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        #expect(components.host == "geocoding-api.open-meteo.com")
        #expect(components.path == "/v1/search")
        #expect(items == ["name": "São Paulo", "count": "5", "language": "en", "format": "json"])
    }

    @Test func theSearchAsksInATwoLetterLanguageWhichIsAllThePlaceSearchKnows() throws {
        #expect(NookWeatherClient.searchLanguage("zh-Hans") == "zh")
        #expect(NookWeatherClient.searchLanguage("zh-Hant") == "zh")
        #expect(NookWeatherClient.searchLanguage("en") == "en")
        #expect(NookWeatherClient.searchLanguage("pt_BR") == "pt")
        #expect(NookWeatherClient.searchLanguage("EN-us") == "en")
        // Nothing usable falls back to English, the service's own default.
        #expect(NookWeatherClient.searchLanguage("") == "en")
        #expect(NookWeatherClient.searchLanguage("chinese") == "en")

        let url = NookWeatherClient.searchURL(name: "北京", language: "zh-Hans")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let language = components.queryItems?.first { $0.name == "language" }?.value
        #expect(language == "zh")
    }

    @Test func noConnectionIsToldApartFromAServiceThatCannotBeReached() {
        #expect(NookWeatherClient.transportFailure(URLError(.notConnectedToInternet)) == .offline)
        #expect(NookWeatherClient.transportFailure(URLError(.networkConnectionLost)) == .offline)
        #expect(NookWeatherClient.transportFailure(URLError(.dataNotAllowed)) == .offline)

        #expect(NookWeatherClient.transportFailure(URLError(.timedOut)) == .unreachable)
        #expect(NookWeatherClient.transportFailure(URLError(.cannotFindHost)) == .unreachable)
        #expect(NookWeatherClient.transportFailure(URLError(.secureConnectionFailed)) == .unreachable)
        #expect(NookWeatherClient.transportFailure(URLError(.serverCertificateUntrusted)) == .unreachable)
        #expect(NookWeatherClient.transportFailure(CocoaError(.fileNoSuchFile)) == .unreachable)

        #expect(NookWeatherClient.transportFailure(URLError(.cancelled)) == .cancelled)
    }

    // MARK: The tile

    @Test func theTileHasAHeightAtEverySizeAndHoursOnlyWhereThereIsRoom() {
        let small: CGFloat = 120
        let medium: CGFloat = 96
        let large: CGFloat = 176
        #expect(NookWeatherLayout.height(for: .small) == small)
        #expect(NookWeatherLayout.height(for: .medium) == medium)
        #expect(NookWeatherLayout.height(for: .large) == large)
        #expect(NookWeatherLayout.hourCount(for: .small) == 0)
        #expect(NookWeatherLayout.hourCount(for: .medium) == 5)
        #expect(NookWeatherLayout.hourCount(for: .large) == 7)
    }

    @Test @MainActor func thePageCountsTheWeatherTileAtItsOwnHeight() {
        for size in NookWidgetSize.allCases {
            let placement = NookWidgetPlacement(kind: .weather, size: size)
            #expect(NookPanelView.cardHeight(placement, calendarStyle: .strip) == NookWeatherLayout.height(for: size))
        }
    }

    @Test func weatherIsOffUntilSwitchedOnAndNoTemplatePlacesIt() {
        #expect(NookWidgetKind.allCases.contains(.weather))
        #expect(!NookWidgetKind.defaultEnabled.contains(.weather))
        #expect(NookWidgetKind.weather.systemImage == "cloud.sun")
        for template in PersonalizationTemplate.all {
            #expect(!template.widgetKinds.contains(.weather), "\(template.id)")
        }
    }
}

/// The weather service against a transport that replays saved answers.
@MainActor
@Suite struct NookWeatherServiceTests {
    private typealias Fixtures = NookWeatherFixtures

    @MainActor private final class Rig {
        let transport = StubWeatherTransport { url in
            url.host == NookWeatherClient.searchHost
                ? .body(NookWeatherFixtures.search, status: 200)
                : .body(NookWeatherFixtures.forecast, status: 200)
        }
        let store = TestDefaults("weather")
        let clock = ManualClock(NookWeatherFixtures.fetchedAt)
        var isOn = true

        func service() -> NookWeatherService {
            let clock = clock
            let service = NookWeatherService(transport: transport, defaults: store.defaults, now: { clock.now })
            service.isSwitchedOn = { [unowned self] in self.isOn }
            return service
        }

        var forecastRequests: [URL] {
            transport.requests.filter { $0.host == NookWeatherClient.forecastHost }
        }

        var searchRequests: [URL] {
            transport.requests.filter { $0.host == NookWeatherClient.searchHost }
        }
    }

    // MARK: Staying off the network

    @Test func aBareServiceNeverAsksForAnything() async {
        let store = TestDefaults("weather-bare")
        defer { store.remove() }
        let transport = StubWeatherTransport()
        let service = NookWeatherService(transport: transport, defaults: store.defaults)

        service.setPlace(Fixtures.losAngeles)
        service.refreshIfDue()
        service.search("Los Angeles", language: "en")
        await service.waitForRefresh()
        await service.waitForSearch()

        #expect(transport.requests.isEmpty)
        #expect(service.report == nil)
        #expect(service.searchStatus == .idle)
    }

    @Test func withTheWidgetOffNothingIsFetchedAndNothingIsSearched() async {
        let rig = Rig()
        defer { rig.store.remove() }
        rig.isOn = false
        let service = rig.service()

        service.setPlace(Fixtures.losAngeles)
        service.refreshIfDue()
        service.search("Los Angeles", language: "en")
        await service.waitForRefresh()
        await service.waitForSearch()

        #expect(rig.transport.requests.isEmpty)
        #expect(service.status == .idle)
        #expect(service.searchResults.isEmpty)
    }

    @Test func withNoCityChosenNothingIsFetched() async {
        let rig = Rig()
        defer { rig.store.remove() }
        let service = rig.service()

        service.refreshIfDue()
        await service.waitForRefresh()

        #expect(rig.transport.requests.isEmpty)
        #expect(service.place == nil)
    }

    // MARK: Fetching

    @Test func choosingACityFetchesItsWeatherAtOnceAndSavesIt() async throws {
        let rig = Rig()
        defer { rig.store.remove() }
        let service = rig.service()

        service.setPlace(Fixtures.losAngeles)
        #expect(service.status == .loading)
        await service.waitForRefresh()

        let temperature: Double = 21.5
        #expect(rig.forecastRequests.count == 1)
        #expect(rig.forecastRequests[0].absoluteString.contains("latitude=34.05&longitude=-118.24"))
        #expect(service.status == .idle)
        #expect(service.report?.current.temperature == temperature)
        #expect(service.report?.fetchedAt == Fixtures.fetchedAt)
        #expect(Set(rig.store.ownValues.keys) == [NookWeatherService.placeKey, NookWeatherService.reportKey])
    }

    @Test func theWeatherIsAskedForAtMostEveryFifteenMinutes() async {
        let rig = Rig()
        defer { rig.store.remove() }
        let service = rig.service()
        service.setPlace(Fixtures.losAngeles)
        await service.waitForRefresh()

        service.refreshIfDue()
        rig.clock.advance(14 * 60)
        service.refreshIfDue()
        await service.waitForRefresh()
        #expect(rig.forecastRequests.count == 1)

        rig.clock.advance(60)
        service.refreshIfDue()
        await service.waitForRefresh()
        #expect(rig.forecastRequests.count == 2)
        #expect(service.report?.fetchedAt == Fixtures.fetchedAt.addingTimeInterval(15 * 60))
    }

    @Test func aFailureKeepsTheLastReportAndWaitsBeforeTryingAgain() async {
        let rig = Rig()
        defer { rig.store.remove() }
        let service = rig.service()
        service.setPlace(Fixtures.losAngeles)
        await service.waitForRefresh()
        let saved = service.report

        rig.transport.setResponder { _ in .offline }
        rig.clock.advance(16 * 60)
        service.refreshIfDue()
        await service.waitForRefresh()

        #expect(service.status == .failed(.offline))
        #expect(service.report == saved)
        #expect(service.isStale(at: rig.clock.now) == false)
        #expect(rig.forecastRequests.count == 2)

        // One minute of quiet after the first failure.
        service.refreshIfDue()
        rig.clock.advance(59)
        service.refreshIfDue()
        await service.waitForRefresh()
        #expect(rig.forecastRequests.count == 2)

        rig.clock.advance(1)
        service.refreshIfDue()
        await service.waitForRefresh()
        #expect(rig.forecastRequests.count == 3)

        // Past half an hour the tile says how old its numbers are.
        rig.clock.advance(20 * 60)
        #expect(service.isStale(at: rig.clock.now))
    }

    @Test func aServerErrorAndANonsenseAnswerAreToldApart() async {
        let rig = Rig()
        defer { rig.store.remove() }
        let service = rig.service()

        rig.transport.setResponder { _ in .body(NookWeatherFixtures.rejected, status: 400) }
        service.setPlace(Fixtures.losAngeles)
        await service.waitForRefresh()
        #expect(service.status == .failed(.server(status: 400)))
        #expect(service.report == nil)

        rig.transport.setResponder { _ in .body("not json", status: 200) }
        rig.clock.advance(61)
        service.refreshIfDue()
        await service.waitForRefresh()
        #expect(service.status == .failed(.malformed))
    }

    @Test func aServiceThatCannotBeReachedIsNotCalledNoConnection() async {
        let rig = Rig()
        defer { rig.store.remove() }
        let service = rig.service()

        // Online, and the secure connection to the service fails.
        rig.transport.setResponder { _ in .failing(.secureConnectionFailed) }
        service.setPlace(Fixtures.losAngeles)
        await service.waitForRefresh()
        #expect(service.status == .failed(.unreachable))

        rig.transport.setResponder { _ in .failing(.cannotFindHost) }
        service.search("Los Angeles", language: "en")
        await service.waitForSearch()
        #expect(service.searchStatus == .failed(.unreachable))
    }

    @Test func theSavedCityAndReportComeBackOnTheNextLaunch() async {
        let rig = Rig()
        defer { rig.store.remove() }
        let first = rig.service()
        first.setPlace(Fixtures.losAngeles)
        first.unit = .celsius
        await first.waitForRefresh()

        rig.clock.advance(5 * 60)
        let second = rig.service()

        #expect(second.place == Fixtures.losAngeles)
        #expect(second.report == first.report)
        #expect(second.unit == .celsius)
        // The saved report is five minutes old: no request yet.
        second.refreshIfDue()
        await second.waitForRefresh()
        #expect(rig.forecastRequests.count == 1)

        rig.clock.advance(10 * 60)
        second.refreshIfDue()
        await second.waitForRefresh()
        #expect(rig.forecastRequests.count == 2)
    }

    @Test func changingTheCityDropsTheOldReportAndFetchesTheNewOne() async {
        let rig = Rig()
        defer { rig.store.remove() }
        let service = rig.service()
        service.setPlace(Fixtures.losAngeles)
        await service.waitForRefresh()

        service.setPlace(Fixtures.tokyo)
        #expect(service.report == nil)
        await service.waitForRefresh()

        #expect(rig.forecastRequests.count == 2)
        #expect(rig.forecastRequests[1].absoluteString.contains("latitude=35.69&longitude=139.69"))
        #expect(service.report != nil)

        // The same city again is no change and no request.
        service.setPlace(Fixtures.tokyo)
        await service.waitForRefresh()
        #expect(rig.forecastRequests.count == 2)
    }

    @Test func clearingTheCityForgetsTheReport() async {
        let rig = Rig()
        defer { rig.store.remove() }
        let service = rig.service()
        service.setPlace(Fixtures.losAngeles)
        await service.waitForRefresh()

        service.clearPlace()

        #expect(service.place == nil)
        #expect(service.report == nil)
        #expect(rig.store.ownValues.isEmpty)
    }

    @Test func theUnitIsFahrenheitUntilChangedAndIsRemembered() {
        let rig = Rig()
        defer { rig.store.remove() }
        let service = rig.service()
        #expect(service.unit == .fahrenheit)

        service.unit = .celsius

        #expect(rig.store.ownValues[NookWeatherService.unitKey] as? String == "celsius")
        #expect(rig.service().unit == .celsius)
        #expect(rig.transport.requests.isEmpty)
    }

    // MARK: Place search

    @Test func aSearchListsPlacesAndPickingOneClearsTheList() async {
        let rig = Rig()
        defer { rig.store.remove() }
        let service = rig.service()

        service.search("  Los Angeles ", language: "en")
        #expect(service.searchStatus == .searching)
        await service.waitForSearch()

        #expect(rig.searchRequests.count == 1)
        #expect(rig.searchRequests[0].absoluteString.contains("name=Los%20Angeles"))
        #expect(service.searchResults.count == 3)
        #expect(service.searchStatus == .idle)

        service.setPlace(service.searchResults[0])
        #expect(service.searchResults.isEmpty)
        #expect(service.place == Fixtures.losAngeles)
        await service.waitForRefresh()
    }

    @Test func aSearchWithNoMatchOrNoConnectionSaysWhich() async {
        let rig = Rig()
        defer { rig.store.remove() }
        let service = rig.service()

        rig.transport.setResponder { _ in .body(NookWeatherFixtures.noMatch, status: 200) }
        service.search("zzzzqqq", language: "en")
        await service.waitForSearch()
        #expect(service.searchStatus == .noMatch)
        #expect(service.searchResults.isEmpty)

        rig.transport.setResponder { _ in .offline }
        service.search("Los Angeles", language: "en")
        await service.waitForSearch()
        #expect(service.searchStatus == .failed(.offline))

        // An empty box asks nothing and clears the message.
        let before = rig.transport.requests.count
        service.search("   ", language: "en")
        #expect(service.searchStatus == .idle)
        #expect(rig.transport.requests.count == before)
    }
}

/// Every key the new code looks up exists in all three languages.
@Suite struct NookMediaToolsStringsTests {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func keys(in language: String) throws -> Set<String> {
        let url = repoRoot.appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
        let text = try String(contentsOf: url, encoding: .utf8)
        let pattern = /(?m)^"([^"]+)"\s*=/
        return Set(text.matches(of: pattern).map { String($0.1) })
    }

    /// Keys passed to `t("…")` in the folders this work added or changed.
    private static func keysUsedInCode() throws -> Set<String> {
        let folders = ["Nook/Media", "Nook/Widgets/Volume", "Nook/Widgets/Weather"]
        let files = ["Nook/Views/NookMediaControls.swift", "Nook/NookModel.swift"]
        let base = repoRoot.appendingPathComponent("Sources/OpenIslandApp")
        var urls = files.map { base.appendingPathComponent($0) }
        for folder in folders {
            urls += try FileManager.default.contentsOfDirectory(
                at: base.appendingPathComponent(folder), includingPropertiesForKeys: nil
            )
        }
        // No "\b" here: by the Unicode rules a dot between letters is not a
        // word boundary, and every lookup is written "lang.t(" or "shared.t(".
        let pattern = /\.t\("(nook\.(?:media|volume|weather)\.[^"\\]+)"/
        var used = Set<String>()
        for url in urls where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            used.formUnion(text.matches(of: pattern).map { String($0.1) })
        }
        used.formUnion(NookWeatherCondition.allCases.map(\.titleKey))
        used.formUnion(NookWeatherForecastMode.allCases.map(\.titleKey))
        return used
    }

    @Test func everyKeyTheCodeLooksUpExistsInAllThreeLanguages() throws {
        let used = try Self.keysUsedInCode()
        #expect(used.count > 40)
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let present = try Self.keys(in: language)
            let missing = used.subtracting(present)
            #expect(missing.isEmpty, "\(language) is missing \(missing.sorted())")
        }
    }

    @Test func theThreeLanguagesHoldTheSameNewKeys() throws {
        func ours(_ keys: Set<String>) -> Set<String> {
            keys.filter { $0.hasPrefix("nook.media.") || $0.hasPrefix("nook.volume.") || $0.hasPrefix("nook.weather.") }
        }
        let english = ours(try Self.keys(in: "en"))
        #expect(ours(try Self.keys(in: "zh-Hans")) == english)
        #expect(ours(try Self.keys(in: "zh-Hant")) == english)
        // Nothing is defined that the code never asks for.
        #expect(english == (try Self.keysUsedInCode()))
    }
}
