import AppKit
import SwiftUI

/// Sizes and counts for the weather tile. A plain enum and not part of a
/// view, which keeps them callable from tests without the main actor.
enum NookWeatherLayout {
    static let mediumHeight: CGFloat = 96
    static let largeHeight: CGFloat = 176
    /// How often the tile on screen checks whether a new report is due.
    static let visibleCheck: Duration = .seconds(60)

    static func height(for size: NookWidgetSize) -> CGFloat {
        switch size {
        case .small: NookWidgetLayout.smallHeight
        case .medium: mediumHeight
        case .large: largeHeight
        }
    }

    /// Hours of forecast each size has room for. The small tile has none.
    static func hourCount(for size: NookWidgetSize) -> Int {
        switch size {
        case .small: 0
        case .medium: 5
        case .large: 7
        }
    }

    /// Days of forecast each size has room for. The small tile has none.
    static func dayCount(for size: NookWidgetSize) -> Int {
        size == .small ? 0 : NookWeatherReport.weekLength
    }

    /// A chance of rain below this is not worth a line.
    static let shownPrecipitationChance = 20

    /// The medium tile draws its week beside the current weather, where the
    /// room changes with the island's width: a day's column is never
    /// narrower than the first and grows up to the second.
    static let dayColumnMin: CGFloat = 30
    static let dayColumnMax: CGFloat = 44
    /// The most the medium tile's current weather takes: the temperature
    /// over a line such as "Partly cloudy · H 102°  L 78°".
    static let mediumCurrentWidth: CGFloat = 160
    /// The medium tile's own padding, a side.
    static let cardPadding: CGFloat = 14
    /// The gaps on both sides of the spacer between the current weather
    /// and the forecast in the medium tile.
    static let mediumGaps: CGFloat = 24

    /// Room left for the week in a medium tile this wide, once the current
    /// weather has all it can ask for.
    static func mediumWeekWidth(cardWidth: CGFloat) -> CGFloat {
        cardWidth - 2 * cardPadding - mediumCurrentWidth - mediumGaps
    }

    /// The least the medium tile's week can be drawn in.
    static func minimumWeekWidth(days: Int = NookWeatherReport.weekLength) -> CGFloat {
        CGFloat(days) * dayColumnMin
    }
}

/// The weather as the tile draws it, with no card around it: the Settings
/// preview draws the same view with sample numbers.
struct NookWeatherContent: View {
    let place: NookWeatherPlace
    let report: NookWeatherReport
    let unit: NookTemperatureUnit
    let size: NookWidgetSize
    let now: Date
    /// Says how old the numbers are, next to the city.
    var showsAge = false
    /// False draws the credit as plain text, for previews that take no clicks.
    var isInteractive = true
    /// What the forecast row shows. A report with no week shows its hours
    /// whatever this says.
    var mode: NookWeatherForecastMode = .hours
    /// Called when the switch in the header is clicked. Nil draws the
    /// switch as plain text.
    var onModeChange: ((NookWeatherForecastMode) -> Void)? = nil

    private var lang: LanguageManager { .shared }

    var body: some View {
        let moment = report.conditions(at: now)
        switch size {
        case .small: small(moment)
        case .medium: medium(moment)
        case .large: large(moment)
        }
    }

    /// The days the week row would draw at this size. Empty at the small
    /// size and for a report that carries no week.
    private var weekDays: [NookWeatherReport.Day] {
        report.week(from: now, count: NookWeatherLayout.dayCount(for: size))
    }

    /// The mode on screen: the week only when there is one to draw.
    private var shownMode: NookWeatherForecastMode {
        mode == .week && !weekDays.isEmpty ? .week : .hours
    }

    // MARK: Sizes

    private func small(_ moment: NookWeatherReport.Moment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            HStack(spacing: 8) {
                symbol(moment, size: 22)
                temperature(moment, size: 28)
            }
            Text(lang.t(moment.condition.titleKey))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
            if let range = rangeText {
                Text(range)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ moment: NookWeatherReport.Moment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        symbol(moment, size: 22)
                        temperature(moment, size: 28)
                    }
                    Text([lang.t(moment.condition.titleKey), rangeText].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                // Beside a week the current weather takes what it needs
                // first, and the week shares out what is left.
                .layoutPriority(shownMode == .week ? 2 : 0)
                Spacer(minLength: 4)
                if shownMode == .week {
                    week(compact: true)
                        .layoutPriority(1)
                } else {
                    hours(columnWidth: 38, symbolSize: 13, showsChance: false)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func large(_ moment: NookWeatherReport.Moment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(alignment: .center, spacing: 12) {
                symbol(moment, size: 32)
                temperature(moment, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.t(moment.condition.titleKey))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                    if let feelsLike = report.feelsLike, moment == report.current {
                        Text(lang.t("nook.weather.feelsLike", unit.text(celsius: feelsLike)))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if let day = report.day(at: now) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(lang.t("nook.weather.high", unit.text(celsius: day.high)))
                        Text(lang.t("nook.weather.low", unit.text(celsius: day.low)))
                    }
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                }
            }
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
            if shownMode == .week {
                week(compact: false)
            } else {
                hours(columnWidth: nil, symbolSize: 16, showsChance: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Parts

    /// The city, how old the numbers are when that matters, and the credit
    /// Open-Meteo's license asks for next to its data.
    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "location.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Text(place.name.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
            if showsAge {
                Text(ageText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.8))
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 4)
            if !weekDays.isEmpty {
                modeSwitch
            }
            credit
        }
    }

    /// Hours or the week, as two words in a pill. Taller than the header's
    /// text, and laid out at the text's height, which keeps the rows under
    /// it where they were.
    private var modeSwitch: some View {
        HStack(spacing: 0) {
            ForEach(NookWeatherForecastMode.allCases) { option in
                modeLabel(option)
            }
        }
        .padding(1)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .fixedSize()
        .frame(height: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(lang.t("nook.weather.mode.label"))
    }

    @ViewBuilder
    private func modeLabel(_ option: NookWeatherForecastMode) -> some View {
        let isSelected = option == shownMode
        let label = Text(lang.t(option.titleKey))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white.opacity(isSelected ? 0.9 : 0.45))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(height: 15)
            .background(Capsule().fill(Color.white.opacity(isSelected ? 0.16 : 0)))
        if isInteractive, let onModeChange {
            Button {
                onModeChange(option)
            } label: {
                label.contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            label
        }
    }

    @ViewBuilder
    private var credit: some View {
        let label = Text("Open-Meteo")
            .font(.system(size: 9, weight: .medium))
            .underline()
            .foregroundStyle(.white.opacity(0.35))
            .fixedSize()
        if isInteractive {
            Button {
                NSWorkspace.shared.open(NookWeatherClient.creditURL)
            } label: {
                label.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(lang.t("nook.weather.credit"))
            .accessibilityLabel(lang.t("nook.weather.credit"))
        } else {
            label
        }
    }

    private func symbol(_ moment: NookWeatherReport.Moment, size: CGFloat) -> some View {
        Image(systemName: moment.condition.symbol(isDay: moment.isDay))
            .symbolRenderingMode(.multicolor)
            .font(.system(size: size))
            .foregroundStyle(.white.opacity(0.9))
            .frame(minWidth: size * 1.2)
    }

    private func temperature(_ moment: NookWeatherReport.Moment, size: CGFloat) -> some View {
        Text(unit.text(celsius: moment.temperature))
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.95))
            .lineLimit(1)
            .fixedSize()
            .contentTransition(.numericText())
    }

    /// The next hours. A nil width shares the row evenly.
    private func hours(columnWidth: CGFloat?, symbolSize: CGFloat, showsChance: Bool) -> some View {
        let upcoming = report.upcomingHours(after: now, count: NookWeatherLayout.hourCount(for: size))
        return HStack(alignment: .top, spacing: 0) {
            ForEach(upcoming, id: \.time) { hour in
                VStack(spacing: 3) {
                    Text(hourLabel(hour.time))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .fixedSize()
                    Image(systemName: hour.condition.symbol(isDay: hour.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: symbolSize))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(height: symbolSize + 3)
                    Text(unit.text(celsius: hour.temperature))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    if showsChance, let chance = hour.precipitationChance,
                       chance >= NookWeatherLayout.shownPrecipitationChance {
                        Text("\(chance)%")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color(red: 0.45, green: 0.75, blue: 1))
                            .lineLimit(1)
                    }
                }
                .frame(width: columnWidth)
                .frame(maxWidth: columnWidth == nil ? .infinity : nil)
            }
        }
    }

    /// "3 PM" in the place's own time zone, worded for the app's language.
    private func hourLabel(_ time: Date) -> String {
        time.formatted(placeStyle.hour(.defaultDigits(amPM: .abbreviated)))
    }

    /// Dates as the place's own clock reads them, in the app's language.
    private var placeStyle: Date.FormatStyle {
        var style = Date.FormatStyle(timeZone: report.timeZone)
        if lang.language != .system {
            style.locale = Locale(identifier: lang.language.resolvedCode)
        }
        return style
    }

    /// The week, today first. The compact row sits beside the current
    /// weather in the medium tile and stacks the high over the low, which
    /// keeps a column narrow. The wide row has the large tile's full width
    /// and is as tall as its hours.
    private func week(compact: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(weekDays, id: \.start) { day in
                VStack(spacing: compact ? 1 : 3) {
                    Text(dayLabel(day))
                        .font(.system(size: compact ? 9 : 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(report.isToday(day, at: now) ? 0.8 : 0.5))
                        .lineLimit(1)
                        .fixedSize()
                    Image(systemName: (day.condition ?? .unknown).symbol(isDay: true))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: compact ? 12 : 16))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(height: compact ? 13 : 19)
                    if compact {
                        dayHigh(day, size: 10.5)
                        dayLow(day, size: 9.5)
                    } else {
                        HStack(spacing: 4) {
                            dayHigh(day, size: 11)
                            dayLow(day, size: 11)
                        }
                        if let chance = day.precipitationChance,
                           chance >= NookWeatherLayout.shownPrecipitationChance {
                            Text("\(chance)%")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color(red: 0.45, green: 0.75, blue: 1))
                                .lineLimit(1)
                        }
                    }
                }
                .frame(
                    minWidth: compact ? NookWeatherLayout.dayColumnMin : nil,
                    maxWidth: compact ? NookWeatherLayout.dayColumnMax : .infinity
                )
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func dayHigh(_ day: NookWeatherReport.Day, size: CGFloat) -> some View {
        Text(unit.text(celsius: day.high))
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.85))
            .lineLimit(1)
            .fixedSize()
    }

    private func dayLow(_ day: NookWeatherReport.Day, size: CGFloat) -> some View {
        Text(unit.text(celsius: day.low))
            .font(.system(size: size, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.5))
            .lineLimit(1)
            .fixedSize()
    }

    /// "Today" for the place's own today, and the short weekday name in
    /// the app's language for the days after it.
    private func dayLabel(_ day: NookWeatherReport.Day) -> String {
        if report.isToday(day, at: now) { return lang.t("nook.weather.today") }
        return day.start.formatted(placeStyle.weekday(.abbreviated))
    }

    private var rangeText: String? {
        guard let day = report.day(at: now) else { return nil }
        return lang.t("nook.weather.high", unit.text(celsius: day.high))
            + "  " + lang.t("nook.weather.low", unit.text(celsius: day.low))
    }

    private var ageText: String {
        switch NookWeatherAge(fetchedAt: report.fetchedAt, now: now) {
        case let .minutes(count): lang.t("nook.weather.age.minutes", count)
        case let .hours(count): lang.t("nook.weather.age.hours", count)
        case let .days(count): lang.t("nook.weather.age.days", count)
        }
    }
}

extension NookWeatherContent {
    /// Fixed numbers for the Settings preview, which never asks a server.
    static func sample(size: NookWidgetSize, mode: NookWeatherForecastMode = .hours) -> NookWeatherContent {
        let start = Date(timeIntervalSince1970: 1_791_500_400)
        // Midnight of the sample's day in its own zone, seven hours behind UTC.
        let midnight = start.addingTimeInterval(-57600)
        let week: [(code: Int, high: Double, low: Double, chance: Int)] = [
            (1, 26.1, 16.3, 5), (2, 27.4, 17.0, 10), (61, 22.8, 15.9, 60), (63, 20.5, 14.8, 75),
            (3, 21.9, 14.2, 25), (0, 24.6, 15.1, 0), (1, 26.8, 16.6, 0),
        ]
        let days = week.enumerated().map { index, day in
            NookWeatherReport.Day(
                start: midnight.addingTimeInterval(TimeInterval(index) * 86400),
                high: day.high,
                low: day.low,
                code: day.code,
                precipitationChance: day.chance
            )
        }
        let codes = [1, 2, 2, 3, 61, 61, 2, 1]
        let hours = codes.enumerated().map { index, code in
            NookWeatherReport.Moment(
                time: start.addingTimeInterval(TimeInterval(index + 1) * NookWeatherReport.hourLength),
                temperature: 22 - Double(index) * 0.8,
                code: code,
                isDay: index < 2,
                precipitationChance: code == 61 ? 45 : 5
            )
        }
        let report = NookWeatherReport(
            fetchedAt: start,
            utcOffsetSeconds: -25200,
            current: NookWeatherReport.Moment(time: start, temperature: 22.4, code: 1, isDay: true),
            feelsLike: 23.5,
            hours: hours,
            days: days
        )
        return NookWeatherContent(
            place: NookWeatherPlace(name: "Los Angeles", region: "California", country: "United States", latitude: 34.05, longitude: -118.24),
            report: report,
            unit: .fahrenheit,
            size: size,
            now: start,
            isInteractive: false,
            mode: mode
        )
    }
}

/// The weather tile on the Nook page. It asks for a report when it comes on
/// screen and the last one is at least fifteen minutes old, and never
/// while the island is closed.
struct NookWeatherCard: View {
    var nook: NookModel

    @Environment(\.nookWidgetSize) private var size

    private var lang: LanguageManager { .shared }

    static func height(for size: NookWidgetSize) -> CGFloat {
        NookWeatherLayout.height(for: size)
    }

    var body: some View {
        let weather = nook.weather
        Group {
            if let place = weather.place, let report = weather.report {
                // The hours and the age move on while the island stays open.
                TimelineView(.everyMinute) { context in
                    NookWeatherContent(
                        place: place,
                        report: report,
                        unit: weather.unit,
                        size: size,
                        now: context.date,
                        showsAge: weather.isStale(at: context.date),
                        mode: weather.forecastMode,
                        onModeChange: { mode in
                            withMotion(Motion.contentSwap) { weather.forecastMode = mode }
                        }
                    )
                }
            } else {
                message(for: weather)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NookCardBackground())
        .task {
            while !Task.isCancelled {
                weather.refreshIfDue()
                try? await Task.sleep(for: NookWeatherLayout.visibleCheck)
            }
        }
    }

    /// What the tile says with no report to draw. Never blank.
    private func message(for weather: NookWeatherService) -> some View {
        let (title, note): (String, String) = {
            guard weather.place != nil else {
                return (lang.t("nook.weather.empty.title"), lang.t("nook.weather.empty.note"))
            }
            switch weather.status {
            case .failed(.offline):
                return (lang.t("nook.weather.failed.title"), lang.t("nook.weather.failed.offline"))
            case .failed:
                return (lang.t("nook.weather.failed.title"), lang.t("nook.weather.failed.server"))
            case .idle, .loading:
                return (lang.t("nook.weather.loading"), weather.place?.name ?? "")
            }
        }()
        return VStack(alignment: .leading, spacing: 6) {
            NookCardHeader(title: lang.t("nook.weather.title"), systemImage: "cloud.sun")
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            Text(note)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(size == .large ? 3 : 2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
