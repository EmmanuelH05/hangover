import SwiftUI

/// Style A: a week of days to step through, events for the picked day, quick add.
struct NookCalendarStripView: View {
    var nook: NookModel
    /// Opens the card's add-event form on a day.
    var onAdd: (Date) -> Void = { _ in }

    static let height: CGFloat = 176

    private static let maxRows = 2
    private static let maxMarks = 3

    @State private var weekStart: Date = Self.weekStart(of: Date())
    @State private var picked: Date = Calendar.current.startOfDay(for: Date())

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            // Re-evaluate every 30s so "today", "now" and "in N min" stay current.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                content(now: context.date)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Text(picked.formatted(.dateTime.month(.wide).year()).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.5))
            Spacer(minLength: 0)
            iconButton("chevron.left", help: "Previous week") { moveWeek(by: -1) }
            Button("Today") { goToToday() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(height: 22)
            iconButton("chevron.right", help: "Next week") { moveWeek(by: 1) }
            NookCalendarAddButton { onAdd(picked) }
        }
        .frame(height: 22)
    }

    private func iconButton(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Content

    @ViewBuilder
    private func content(now: Date) -> some View {
        let cal = Calendar.current
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
        let byDay = eventsByDay(days: days)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { day in
                    dayCell(day, now: now, events: byDay[day] ?? [])
                }
            }
            dayRows(events: byDay[cal.startOfDay(for: picked)] ?? [], now: now)
            Spacer(minLength: 0)
        }
    }

    /// One fetch for the whole week, grouped by day start.
    private func eventsByDay(days: [Date]) -> [Date: [NookCalendarEvent]] {
        let cal = Calendar.current
        guard let first = days.first, let last = days.last,
              let end = cal.date(byAdding: .day, value: 1, to: last) else { return [:] }
        let events = nook.calendarEvents(from: first, to: end)
        var result: [Date: [NookCalendarEvent]] = [:]
        for day in days {
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { continue }
            result[day] = events.filter { $0.start < next && $0.end > day }
        }
        return result
    }

    private func dayCell(_ day: Date, now: Date, events: [NookCalendarEvent]) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDate(day, inSameDayAs: now)
        let isPicked = cal.isDate(day, inSameDayAs: picked)
        let tasks = nook.tasksDue(on: day)
        let dots = Array(events.prefix(Self.maxMarks))
        let squares = max(0, min(tasks.count, Self.maxMarks - dots.count))
        return Button {
            picked = day
        } label: {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isToday ? Color.orange : Color.white.opacity(0.85))
                HStack(spacing: 3) {
                    ForEach(dots) { event in
                        Circle().fill(event.calendarColor).frame(width: 4, height: 4)
                    }
                    ForEach(0..<squares, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .stroke(Color.white.opacity(0.55), lineWidth: 1)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(isPicked ? 0.1 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(isPicked ? 0.22 : 0), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func dayRows(events: [NookCalendarEvent], now: Date) -> some View {
        let tasks = nook.tasksDue(on: picked)
        let total = events.count + tasks.count
        // When everything does not fit, one row gives way to the "+N more" line.
        let fits = total <= Self.maxRows
        let shownWhenShort = fits ? total : Self.maxRows - 1
        let hidden = NookCalendarExpansion.hiddenRows(total: total, shownWhenCollapsed: shownWhenShort)
        // "+N more" grows the card by N rows, which the grid and the window
        // then make room for.
        let isExpanded = nook.calendarExtraRows > 0
        let shown = isExpanded ? total : shownWhenShort
        VStack(alignment: .leading, spacing: NookCalendarExpansion.rowSpacing) {
            if total == 0 {
                Text("Nothing on this day")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
            } else {
                ForEach(events.prefix(shown)) { event in
                    NookCalendarRow(event: event, now: now, showsWeekday: false) {
                        nook.startNote(for: event)
                    } onJoin: {
                        nook.joinMeeting(event)
                    }
                    .frame(height: NookCalendarExpansion.rowHeight)
                }
                ForEach(tasks.prefix(max(0, shown - events.count))) { task in
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
        .onChange(of: picked) { nook.calendarExtraRows = 0 }
        // An event added or removed while the list is open changes its length.
        .onChange(of: hidden) { _, count in
            if nook.calendarExtraRows > 0 { nook.calendarExtraRows = count }
        }
    }

    // MARK: - Actions

    private func moveWeek(by weeks: Int) {
        let cal = Calendar.current
        if let next = cal.date(byAdding: .day, value: 7 * weeks, to: picked) {
            picked = next
            weekStart = Self.weekStart(of: next)
        }
    }

    private func goToToday() {
        let today = Date()
        picked = Calendar.current.startOfDay(for: today)
        weekStart = Self.weekStart(of: today)
    }

    private static func weekStart(of date: Date) -> Date {
        let cal = Calendar.current
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }
}
