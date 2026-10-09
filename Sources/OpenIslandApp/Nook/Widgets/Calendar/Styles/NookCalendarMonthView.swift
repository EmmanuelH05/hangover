import SwiftUI

/// Style E: a month grid with the picked day's events below.
struct NookCalendarMonthView: View {
    var nook: NookModel
    /// Opens the card's add-event form on a day.
    var onAdd: (Date) -> Void = { _ in }

    static let height: CGFloat = 292

    private static let cellHeight: CGFloat = 26
    private static let gridDays = 42
    private static let maxDayRows = 2

    @State private var visibleMonth = Date()
    @State private var pickedDay = Date()

    // MARK: Date math (pure, testable)

    /// First day of the month containing `date`.
    static func monthStart(of date: Date, calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: parts) ?? calendar.startOfDay(for: date)
    }

    /// The first cell of the 6 by 7 grid for the month containing `month`:
    /// the latest day on or before the 1st that falls on `calendar.firstWeekday`.
    static func gridStart(for month: Date, calendar: Calendar) -> Date {
        let first = monthStart(of: month, calendar: calendar)
        let weekday = calendar.component(.weekday, from: first)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: first) ?? first
    }

    /// The 42 consecutive days of the grid, each at start of day.
    static func gridDates(start: Date, calendar: Calendar) -> [Date] {
        (0..<gridDays).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// Longest run of days one event may mark; guards against bad data.
    private static let maxEventSpanDays = 62

    /// Events keyed by the start of every day they cover, so a trip or a
    /// late-night event shows on each of its days.
    static func group(_ events: [NookCalendarEvent], calendar: Calendar) -> [Date: [NookCalendarEvent]] {
        var byDay: [Date: [NookCalendarEvent]] = [:]
        for event in events {
            var day = calendar.startOfDay(for: event.start)
            var steps = 0
            repeat {
                byDay[day, default: []].append(event)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
                steps += 1
            } while day < event.end && steps < maxEventSpanDays
        }
        return byDay
    }

    /// Weekday initials starting at `calendar.firstWeekday`.
    static func weekdayInitials(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return [] }
        let shift = calendar.firstWeekday - 1
        return (0..<7).map { symbols[($0 + shift) % 7] }
    }

    // MARK: Body

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let cal = Calendar.current
        let start = Self.gridStart(for: visibleMonth, calendar: cal)
        let dates = Self.gridDates(start: start, calendar: cal)
        let end = cal.date(byAdding: .day, value: Self.gridDays, to: start) ?? start
        let grouped = Self.group(nook.calendarEvents(from: start, to: end), calendar: cal)
        let hasTasks = !nook.todo.source(reminders: nook.reminders).items.isEmpty
        return VStack(alignment: .leading, spacing: 4) {
            header(now: now, calendar: cal)
            weekdayRow(calendar: cal)
            grid(dates: dates, grouped: grouped, hasTasks: hasTasks, now: now, calendar: cal)
            Spacer(minLength: 0)
                .frame(maxHeight: 2)
            dayRows(grouped: grouped, now: now, calendar: cal)
            Spacer(minLength: 0)
        }
    }

    private func header(now: Date, calendar: Calendar) -> some View {
        HStack(spacing: 6) {
            Text(visibleMonth.formatted(.dateTime.month(.wide).year()).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.5))
            Spacer(minLength: 0)
            navButton(systemImage: "chevron.left") { shiftMonth(by: -1, calendar: calendar) }
            Button {
                visibleMonth = now
                pickedDay = now
            } label: {
                Text("Today")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(chipBackground)
            }
            .buttonStyle(.plain)
            navButton(systemImage: "chevron.right") { shiftMonth(by: 1, calendar: calendar) }
            NookCalendarAddButton { onAdd(pickedDay) }
        }
        .frame(height: 22)
    }

    private var chipBackground: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.07))
    }

    private func navButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 22, height: 22)
                .background(chipBackground)
        }
        .buttonStyle(.plain)
    }

    private func weekdayRow(calendar: Calendar) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.weekdayInitials(calendar: calendar).enumerated()), id: \.offset) { _, initial in
                Text(initial)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 12)
    }

    private func grid(
        dates: [Date],
        grouped: [Date: [NookCalendarEvent]],
        hasTasks: Bool,
        now: Date,
        calendar: Calendar
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        let index = row * 7 + column
                        if dates.indices.contains(index) {
                            cell(
                                date: dates[index],
                                events: grouped[dates[index]] ?? [],
                                hasTasks: hasTasks,
                                now: now,
                                calendar: calendar
                            )
                        } else {
                            Color.clear.frame(maxWidth: .infinity, minHeight: Self.cellHeight, maxHeight: Self.cellHeight)
                        }
                    }
                }
            }
        }
    }

    private func cell(
        date: Date,
        events: [NookCalendarEvent],
        hasTasks: Bool,
        now: Date,
        calendar: Calendar
    ) -> some View {
        let inMonth = calendar.isDate(date, equalTo: visibleMonth, toGranularity: .month)
        let isToday = calendar.isDate(date, inSameDayAs: now)
        let isPicked = calendar.isDate(date, inSameDayAs: pickedDay)
        let dayNumber = calendar.component(.day, from: date)
        let hasTask = events.isEmpty && hasTasks && !nook.tasksDue(on: date).isEmpty
        return Button {
            pickedDay = date
            if !inMonth { visibleMonth = date }
        } label: {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isPicked ? Color.white.opacity(0.12) : Color.clear)
                Text("\(dayNumber)")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(isToday ? Color.orange : Color.white.opacity(0.85))
                    .frame(maxHeight: .infinity)
                if let first = events.first {
                    Circle().fill(first.calendarColor).frame(width: 4, height: 4).padding(.bottom, 2)
                } else if hasTask {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
                        .frame(width: 4, height: 4)
                        .padding(.bottom, 2)
                }
            }
            .opacity(inMonth ? 1 : 0.35)
            .frame(maxWidth: .infinity, minHeight: Self.cellHeight, maxHeight: Self.cellHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func dayRows(grouped: [Date: [NookCalendarEvent]], now: Date, calendar: Calendar) -> some View {
        let events = (grouped[calendar.startOfDay(for: pickedDay)] ?? []).sorted { $0.start < $1.start }
        let tasks = nook.todo.source(reminders: nook.reminders).items.isEmpty ? [] : nook.tasksDue(on: pickedDay)
        let total = events.count + tasks.count
        let hidden = NookCalendarExpansion.hiddenRows(total: total, shownWhenCollapsed: Self.maxDayRows)
        // "+N more" grows the card by N rows, which the grid and the window
        // then make room for.
        let isExpanded = nook.calendarExtraRows > 0
        let limit = isExpanded ? total : Self.maxDayRows
        VStack(alignment: .leading, spacing: NookCalendarExpansion.rowSpacing) {
            if total == 0 {
                Text("Nothing on this day")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
            } else {
                ForEach(events.prefix(limit)) { event in
                    NookCalendarRow(event: event, now: now, showsWeekday: false) { nook.startNote(for: event) } onJoin: { nook.joinMeeting(event) }
                        .frame(height: NookCalendarExpansion.rowHeight)
                }
                ForEach(tasks.prefix(max(0, limit - events.count))) { task in
                    NookCalendarTaskRow(task: task)
                        .frame(height: NookCalendarExpansion.rowHeight)
                }
                if hidden > 0 {
                    NookCalendarMoreButton(hidden: hidden, isExpanded: isExpanded) {
                        withMotion(Motion.reflow) { nook.calendarExtraRows = isExpanded ? 0 : hidden }
                    }
                }
            }
        }
        // Another day has another list: start short again.
        .onChange(of: pickedDay) { nook.calendarExtraRows = 0 }
        // An event added or removed while the list is open changes its length.
        .onChange(of: hidden) { _, count in
            if nook.calendarExtraRows > 0 { nook.calendarExtraRows = count }
        }
    }

    private func shiftMonth(by value: Int, calendar: Calendar) {
        let base = Self.monthStart(of: visibleMonth, calendar: calendar)
        visibleMonth = calendar.date(byAdding: .month, value: value, to: base) ?? visibleMonth
    }
}
