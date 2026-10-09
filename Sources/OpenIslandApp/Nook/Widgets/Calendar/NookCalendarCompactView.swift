import SwiftUI

/// The calendar at small size: today's date, then the next two events.
/// Used whatever look the display picked; the card still owns the
/// background and padding, and the grid fixes the height.
struct NookCalendarCompactView: View {
    var nook: NookModel
    /// Opens the card's add-event form on a day.
    var onAdd: (Date) -> Void = { _ in }

    private static let maxEvents = 2
    private static let rowHeight: CGFloat = 22

    var body: some View {
        // Re-evaluate every 30s so "now", the date and ended events stay current.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let upcoming = Self.nextEvents(nook.upcomingEvents, now: now)
        return VStack(alignment: .leading, spacing: 4) {
            dateRow(now: now)
            if upcoming.isEmpty {
                Text("Nothing coming up")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
            } else {
                ForEach(upcoming) { event in
                    row(event, now: now)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func dateRow(now: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(now.formatted(.dateTime.weekday(.wide)).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
            Text(now.formatted(.dateTime.day()))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.orange)
            Spacer(minLength: 0)
            NookCalendarAddButton(isInline: true) { onAdd(now) }
        }
    }

    /// A click on the row starts a note. An event with a meeting link also
    /// carries the join mark, beside the row and not inside its button.
    private func row(_ event: NookCalendarEvent, now: Date) -> some View {
        HStack(spacing: 4) {
            noteButton(event, now: now)
            if event.meetingURL != nil {
                NookJoinMark { nook.joinMeeting(event) }
            }
        }
    }

    private func noteButton(_ event: NookCalendarEvent, now: Date) -> some View {
        Button {
            nook.startNote(for: event)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(event.calendarColor)
                    .frame(width: 7, height: 7)
                Text(event.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(Self.timeText(for: event, now: now))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The next unfinished events, soonest first.
    static func nextEvents(_ events: [NookCalendarEvent], now: Date) -> [NookCalendarEvent] {
        Array(events.filter { $0.end > now }.sorted { $0.start < $1.start }.prefix(maxEvents))
    }

    /// "now", a start time, or the weekday for an event on a later day.
    static func timeText(for event: NookCalendarEvent, now: Date) -> String {
        let cal = Calendar.current
        let sameDay = cal.isDate(event.start, inSameDayAs: now)
        let weekday = event.start.formatted(.dateTime.weekday(.abbreviated))
        if event.isAllDay {
            return sameDay || event.start <= now ? "All day" : weekday
        }
        if event.start <= now { return "now" }
        let time = event.start.formatted(date: .omitted, time: .shortened)
        return sameDay ? time : "\(weekday) \(time)"
    }
}
