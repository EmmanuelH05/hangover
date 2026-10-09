import SwiftUI

/// The list under the chosen look when the calendar is large: the next
/// events that the look above does not already name.
struct NookCalendarUpNextView: View {
    var nook: NookModel
    var style: NookCalendarStyle

    static let maxRows = 3
    private static let topGap: CGFloat = 10
    private static let headerHeight: CGFloat = 14
    private static let headerGap: CGFloat = 6
    private static let rowHeight: CGFloat = 20
    private static let rowGap: CGFloat = 2

    private static var rowsHeight: CGFloat {
        CGFloat(maxRows) * rowHeight + CGFloat(maxRows - 1) * rowGap
    }

    /// Everything this section needs, including the gap above it. The card
    /// adds it to the look's height so nothing clips.
    static let height: CGFloat = topGap + headerHeight + headerGap + rowsHeight

    var body: some View {
        VStack(alignment: .leading, spacing: Self.headerGap) {
            NookCardHeader(title: "Up next", systemImage: "clock")
                .frame(height: Self.headerHeight)
            // Re-evaluate every 30s so "in N min" and ended events stay current.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                rows(now: context.date)
            }
        }
        .padding(.top, Self.topGap)
        .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .topLeading)
    }

    private func rows(now: Date) -> some View {
        let tasks = style == .strip ? nook.tasksDue(on: now).count : 0
        let events = Self.events(from: nook.upcomingEvents, style: style, tasksToday: tasks, now: now)
        return VStack(alignment: .leading, spacing: Self.rowGap) {
            if events.isEmpty {
                Text("Nothing else coming up")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
                    .frame(height: Self.rowHeight)
            } else {
                ForEach(events) { event in
                    NookCalendarRow(event: event, now: now) { nook.startNote(for: event) } onJoin: { nook.joinMeeting(event) }
                        .frame(height: Self.rowHeight)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.rowsHeight, maxHeight: Self.rowsHeight, alignment: .topLeading)
    }

    /// Up to `maxRows` unfinished events the look does not already show.
    static func events(
        from all: [NookCalendarEvent],
        style: NookCalendarStyle,
        tasksToday: Int,
        now: Date
    ) -> [NookCalendarEvent] {
        let shown = namedByLook(style, in: all, tasksToday: tasksToday, now: now)
        return Array(
            all
                .filter { $0.end > now && !shown.contains($0.id) }
                .sorted { $0.start < $1.start }
                .prefix(maxRows)
        )
    }

    /// Ids of the events a look puts on screen by title when it opens on today.
    /// The row limits mirror the strip and month looks (two rows of a day);
    /// guessing low only repeats an event, guessing high would hide one.
    private static func namedByLook(
        _ style: NookCalendarStyle,
        in all: [NookCalendarEvent],
        tasksToday: Int,
        now: Date
    ) -> Set<String> {
        switch style {
        case .agenda:
            return Set(NookCalendarCard.visibleEvents(all, now: now).map(\.id))
        case .hero:
            guard let featured = NookCalendarHeroLogic.featured(from: all, now: now) else { return [] }
            var ids: Set<String> = [featured.id]
            if let following = NookCalendarHeroLogic.following(featured, in: all, now: now) {
                ids.insert(following.id)
            }
            return ids
        case .timeline:
            // The bar has no titles: only the current event and the all-day line are named.
            let today = todaysEvents(all, now: now)
            let current = today.filter { !$0.isAllDay && $0.start <= now && $0.end > now }
            let allDay = today.filter(\.isAllDay)
            return Set((current + allDay).map(\.id))
        case .strip:
            let today = todaysEvents(all, now: now)
            let rows = today.count + tasksToday <= 2 ? today.count : 1
            return Set(today.prefix(rows).map(\.id))
        case .month:
            return Set(todaysEvents(all, now: now).prefix(2).map(\.id))
        }
    }

    /// Every event that touches today, ended ones included, soonest first.
    private static func todaysEvents(_ all: [NookCalendarEvent], now: Date) -> [NookCalendarEvent] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        return all
            .filter { $0.start < dayEnd && $0.end > dayStart }
            .sorted { $0.start < $1.start }
    }
}
