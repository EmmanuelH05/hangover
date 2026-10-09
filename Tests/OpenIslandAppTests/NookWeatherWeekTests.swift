import Foundation
import Testing
@testable import OpenIslandApp

/// The 7 day row: what is read, which days count, and what is remembered.
/// No test here makes a request: the service gets a transport that only
/// replays saved answers.
@Suite struct NookWeatherWeekTests {
    private typealias Fixtures = NookWeatherFixtures

    private static let day: TimeInterval = 86400

    // MARK: Reading the week

    @Test func anAnswerWithTheDailyPartReadsIntoSevenDaysWithTheirSky() throws {
        let report = try Fixtures.weekReport()

        let count: Int = 7
        #expect(report.days.count == count)
        let codes: [Int?] = [3, 51, 61, 53, 51, 0, 0]
        let highs: [Double] = [29.6, 25.6, 25.6, 19.6, 21.6, 24.1, 28.4]
        let lows: [Double] = [18.1, 17.9, 17.8, 16.5, 16.8, 18.4, 20.1]
        let chances: [Int?] = [1, 8, 47, 69, 29, 1, 0]
        let skies: [NookWeatherCondition?] = [.cloudy, .drizzle, .rain, .drizzle, .drizzle, .clear, .clear]
        #expect(report.days.map(\.code) == codes)
        #expect(report.days.map(\.high) == highs)
        #expect(report.days.map(\.low) == lows)
        #expect(report.days.map(\.precipitationChance) == chances)
        #expect(report.days.map(\.condition) == skies)
        // Midnight in Los Angeles on the day it was fetched.
        #expect(report.days.first?.start == Date(timeIntervalSince1970: 1_791_529_200))
    }

    @Test func theHoursComeFromTheCurrentOneAndCoverTwoDays() throws {
        let report = try Fixtures.weekReport()

        let count: Int = 48
        #expect(report.hours.count == count)
        #expect(report.hours.first?.time == Date(timeIntervalSince1970: 1_791_540_000))
        let next: Int = 7
        #expect(report.upcomingHours(after: Fixtures.weekFetchedAt, count: 7).count == next)
        // Today's high and low still come from the days.
        let high: Double = 29.6
        #expect(report.day(at: Fixtures.weekFetchedAt)?.high == high)
    }

    @Test func aDayWithAGapInItsHighOrLowIsLeftOutAndOneWithNoSkyIsKept() throws {
        let json = #"""
        {"utc_offset_seconds":0,"timezone":"GMT","current":{"time":1000,"temperature_2m":10,"weather_code":0},
         "daily":{"time":[0,86400,172800],"weather_code":[1,null,3],
                  "temperature_2m_max":[20,21,null],"temperature_2m_min":[10,11,12],
                  "precipitation_probability_max":[null,40,50]}}
        """#
        let report = try NookWeatherParser.report(from: Data(json.utf8), fetchedAt: Date(timeIntervalSince1970: 1000))

        let starts: [TimeInterval] = [0, 86400]
        let codes: [Int?] = [1, nil]
        let chances: [Int?] = [nil, 40]
        let inWeek: [Int?] = [1]
        #expect(report.days.map(\.start.timeIntervalSince1970) == starts)
        #expect(report.days.map(\.code) == codes)
        #expect(report.days.map(\.precipitationChance) == chances)
        // Only the day that carries its sky is part of the week.
        #expect(report.week(from: Date(timeIntervalSince1970: 1000)).map(\.code) == inWeek)
    }

    // MARK: Which days count

    @Test func theWeekStartsOnThePlacesOwnTodayAndRunsSoonestFirst() throws {
        let report = try Fixtures.weekReport()

        let week = report.week(from: Fixtures.weekFetchedAt)
        #expect(week == report.days)
        #expect(week.first.map { report.isToday($0, at: Fixtures.weekFetchedAt) } == true)
        #expect(week.dropFirst().allSatisfy { !report.isToday($0, at: Fixtures.weekFetchedAt) })

        #expect(report.week(from: Fixtures.weekFetchedAt, count: 3) == Array(report.days.prefix(3)))
        #expect(report.week(from: Fixtures.weekFetchedAt, count: 0).isEmpty)
    }

    @Test func aDayThatHasPassedLeavesTheWeekAndAnOldReportRunsOut() throws {
        let report = try Fixtures.weekReport()

        let twoDaysOn = Fixtures.weekFetchedAt.addingTimeInterval(2 * Self.day)
        #expect(report.week(from: twoDaysOn) == Array(report.days.dropFirst(2)))
        let last: Int = 1
        #expect(report.week(from: Fixtures.weekFetchedAt.addingTimeInterval(6 * Self.day)).count == last)
        #expect(report.week(from: Fixtures.weekFetchedAt.addingTimeInterval(8 * Self.day)).isEmpty)
    }

    /// Kiritimati is fourteen hours ahead of UTC and Pago Pago eleven
    /// behind: at one instant it is already tomorrow in the first and still
    /// yesterday in the second, wherever this Mac is.
    @Test(arguments: ["Pacific/Kiritimati", "Pacific/Pago_Pago", "Asia/Kolkata"])
    func todayIsThePlacesOwnDayFarFromThisMac(zoneName: String) throws {
        let zone = try #require(TimeZone(identifier: zoneName))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        // Noon UTC on 9 October 2026.
        let now = Date(timeIntervalSince1970: 1_791_547_200)
        let today = calendar.startOfDay(for: now)
        let starts = try (-1...6).map { offset in
            try #require(calendar.date(byAdding: .day, value: offset, to: today))
        }
        var report = try Fixtures.weekReport()
        report.timeZoneIdentifier = zoneName
        report.utcOffsetSeconds = zone.secondsFromGMT(for: now)
        report.days = starts.enumerated().map { index, start in
            NookWeatherReport.Day(start: start, high: Double(20 + index), low: 10, code: index)
        }

        let week = report.week(from: now)
        // Yesterday is dropped, and seven days from the place's today stay.
        #expect(week.map(\.start) == Array(starts.dropFirst().prefix(7)))
        #expect(week.first.map { report.isToday($0, at: now) } == true)
        // One minute before the place's midnight it is still the same today,
        // and one minute after it the week has moved on a day.
        let tomorrow = starts[2]
        #expect(report.week(from: tomorrow.addingTimeInterval(-60)).first?.start == starts[1])
        #expect(report.week(from: tomorrow.addingTimeInterval(60)).first?.start == starts[2])
    }

    @Test func theWeekFollowsThePlacesCalendarOnTheDayTheClocksChange() throws {
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        // The clocks go back on 1 November 2026: that day is 25 hours long.
        let longDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        let next = try #require(calendar.date(byAdding: .day, value: 1, to: longDay))
        var report = try Fixtures.weekReport()
        report.days = [
            NookWeatherReport.Day(start: longDay, high: 20, low: 10, code: 0),
            NookWeatherReport.Day(start: next, high: 30, low: 15, code: 1),
        ]

        // 24.5 hours into the long day is still that day.
        let late = longDay.addingTimeInterval(24.5 * 3600)
        #expect(report.week(from: late).map(\.start) == [longDay, next])
        #expect(report.week(from: next.addingTimeInterval(60)).map(\.start) == [next])
    }

    // MARK: Data from before the week

    @Test func anAnswerFromBeforeTheWeekStillReadsAndShowsNoWeek() throws {
        let report = try Fixtures.report()

        let count: Int = 2
        #expect(report.days.count == count)
        #expect(report.days.allSatisfy { $0.code == nil && $0.precipitationChance == nil })
        #expect(report.week(from: Fixtures.fetchedAt).isEmpty)
        // The high and the low it did keep are still there.
        let high: Double = 34.3
        #expect(report.day(at: Fixtures.fetchedAt)?.high == high)
    }

    @Test func aReportSavedBeforeTheWeekWasKeptStillLoads() throws {
        let report = try Fixtures.weekReport()
        let saved = try JSONEncoder().encode(report)
        var fields = try #require(try JSONSerialization.jsonObject(with: saved) as? [String: Any])
        let days = try #require(fields["days"] as? [[String: Any]])
        fields["days"] = days.map { day in
            day.filter { $0.key != "code" && $0.key != "precipitationChance" }
        }
        let older = try JSONSerialization.data(withJSONObject: fields)

        let read = try JSONDecoder().decode(NookWeatherReport.self, from: older)
        #expect(read.days.map(\.high) == report.days.map(\.high))
        #expect(read.days.map(\.low) == report.days.map(\.low))
        #expect(read.days.allSatisfy { $0.code == nil })
        #expect(read.week(from: Fixtures.weekFetchedAt).isEmpty)
        #expect(read.hours == report.hours)
    }

    @Test func aReportWithNoDaysAtAllShowsNoWeek() throws {
        let json = #"{"current":{"time":1000,"temperature_2m":10,"weather_code":0}}"#
        let report = try NookWeatherParser.report(from: Data(json.utf8), fetchedAt: Date(timeIntervalSince1970: 1000))

        #expect(report.days.isEmpty)
        #expect(report.week(from: Date(timeIntervalSince1970: 1000)).isEmpty)
    }

    // MARK: What goes out

    @Test func theDaysAndTheHoursAreAskedForInOneRequest() throws {
        let url = NookWeatherClient.forecastURL(latitude: 34.05223, longitude: -118.24368)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        let daily = Set((items["daily"] ?? "").split(separator: ",").map(String.init))
        #expect(daily == ["weather_code", "temperature_2m_max", "temperature_2m_min", "precipitation_probability_max"])
        #expect(items["forecast_days"] == String(NookWeatherReport.weekLength))
        // The hours are still part of the same request.
        #expect(items["hourly"]?.contains("temperature_2m") == true)
        #expect(items["current"]?.contains("temperature_2m") == true)
    }

    // MARK: The tile's numbers

    @Test func theWeekHasSevenDaysWhereThereIsRoomAndNoneInTheSmallTile() {
        let none: Int = 0
        let week: Int = 7
        #expect(NookWeatherLayout.dayCount(for: .small) == none)
        #expect(NookWeatherLayout.dayCount(for: .medium) == week)
        #expect(NookWeatherLayout.dayCount(for: .large) == week)
        #expect(NookWeatherReport.weekLength == week)
    }

    /// The medium tile draws the week beside the current weather. On the
    /// narrowest page, the notch display's, seven columns must still have
    /// their minimum width after the current weather takes all it asks for.
    @Test func sevenDaysFitBesideTheCurrentWeatherOnTheNarrowestPage() {
        for profile in [IslandAppearanceDisplayProfile.notch, .topBar] {
            let cardWidth = NookLayoutEditor.pageWidth(for: profile)
            let room = NookWeatherLayout.mediumWeekWidth(cardWidth: cardWidth)
            #expect(room >= NookWeatherLayout.minimumWeekWidth(), "\(profile)")
        }
        // A wider island gives the columns more room, up to their cap.
        let narrow = NookWeatherLayout.mediumWeekWidth(cardWidth: 448)
        let wide = NookWeatherLayout.mediumWeekWidth(cardWidth: 648)
        #expect(wide > narrow)
        #expect(NookWeatherLayout.dayColumnMax > NookWeatherLayout.dayColumnMin)
    }
}

/// The remembered choice, and what it must never cause.
@MainActor
@Suite struct NookWeatherForecastModeTests {
    private typealias Fixtures = NookWeatherFixtures

    @MainActor private final class Rig {
        let transport = StubWeatherTransport { _ in .body(NookWeatherFixtures.forecastWeek, status: 200) }
        let store = TestDefaults("weather-week")
        let clock = ManualClock(NookWeatherFixtures.weekFetchedAt)

        func service() -> NookWeatherService {
            let clock = clock
            let service = NookWeatherService(transport: transport, defaults: store.defaults, now: { clock.now })
            service.isSwitchedOn = { true }
            return service
        }
    }

    @Test func theRowShowsHoursUntilChangedAndTheChoiceIsRemembered() {
        let rig = Rig()
        let first = rig.service()
        #expect(first.forecastMode == .hours)
        #expect(rig.store.ownValues[NookWeatherService.forecastModeKey] == nil)

        first.forecastMode = .week
        #expect(rig.store.ownValues[NookWeatherService.forecastModeKey] as? String == "week")
        #expect(rig.service().forecastMode == .week)

        first.forecastMode = .hours
        #expect(rig.service().forecastMode == .hours)
    }

    @Test func aSavedChoiceThisBuildDoesNotKnowFallsBackToHours() {
        let rig = Rig()
        rig.store.defaults.set("fortnight", forKey: NookWeatherService.forecastModeKey)

        #expect(rig.service().forecastMode == .hours)
    }

    @Test func oneRefreshIsOneRequestAndItBringsTheWeek() async throws {
        let rig = Rig()
        let service = rig.service()

        service.setPlace(Fixtures.losAngeles)
        await service.waitForRefresh()

        let one: Int = 1
        #expect(rig.transport.requests.count == one)
        let url = try #require(rig.transport.requests.first)
        #expect(url.host == NookWeatherClient.forecastHost)
        #expect(url.query?.contains("daily=weather_code") == true)
        let week: Int = 7
        #expect(service.report?.week(from: rig.clock.now).count == week)
    }

    @Test func switchingTheRowAsksForNothing() async {
        let rig = Rig()
        let service = rig.service()
        service.setPlace(Fixtures.losAngeles)
        await service.waitForRefresh()
        let before = rig.transport.requests.count

        service.forecastMode = .week
        service.refreshIfDue()
        await service.waitForRefresh()
        service.forecastMode = .hours
        service.refreshIfDue()
        await service.waitForRefresh()

        #expect(rig.transport.requests.count == before)
    }

    @Test func theSavedWeekComesBackOnTheNextLaunchWithNoRequest() async {
        let rig = Rig()
        let first = rig.service()
        first.setPlace(Fixtures.losAngeles)
        await first.waitForRefresh()
        first.forecastMode = .week
        let before = rig.transport.requests.count

        let second = rig.service()
        let week: Int = 7
        #expect(second.forecastMode == .week)
        #expect(second.report?.week(from: rig.clock.now).count == week)
        #expect(rig.transport.requests.count == before)
    }

    @Test func theModeNamesExistInEveryLanguage() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let keys = NookWeatherForecastMode.allCases.map(\.titleKey) + ["nook.weather.mode.label", "nook.weather.today"]
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let url = root.appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
            let text = try String(contentsOf: url, encoding: .utf8)
            for key in keys {
                #expect(text.contains("\"\(key)\" = \""), "\(language) is missing \(key)")
            }
        }
    }
}
