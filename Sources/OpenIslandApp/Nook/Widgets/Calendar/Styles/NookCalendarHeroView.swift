import AppKit
import SwiftUI

/// Style D: the next event, large, with a countdown and a join button.
struct NookCalendarHeroView: View {
    var nook: NookModel
    /// Opens the card's add-event form on a day.
    var onAdd: (Date) -> Void = { _ in }

    static let height: CGFloat = 116

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let events = nook.upcomingEvents
        if let event = NookCalendarHeroLogic.featured(from: events, now: now) {
            let inProgress = !event.isAllDay && event.start <= now
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    NookCardHeader(title: inProgress ? "Now" : "Next up", systemImage: "calendar")
                    NookCalendarAddButton(isInline: true) { onAdd(Date()) }
                }
                featuredRow(event, now: now)
                if let next = NookCalendarHeroLogic.following(event, in: events, now: now) {
                    NookCalendarRow(event: next, now: now) { nook.startNote(for: next) } onJoin: { nook.joinMeeting(next) }
                        .opacity(0.6)
                }
                Spacer(minLength: 0)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    NookCardHeader(title: "Next up", systemImage: "calendar")
                    NookCalendarAddButton(isInline: true) { onAdd(Date()) }
                }
                Spacer(minLength: 0)
                Text("Nothing coming up")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
        }
    }

    private func featuredRow(_ event: NookCalendarEvent, now: Date) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(event.calendarColor)
                .frame(width: 4, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Text(NookCalendarHeroLogic.subtitle(
                    start: event.start, end: event.end, isAllDay: event.isAllDay, location: event.location
                ))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text(NookCalendarHeroLogic.countdown(
                    start: event.start, end: event.end, isAllDay: event.isAllDay, now: now
                ))
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Text(NookCalendarHeroLogic.detail(
                    start: event.start, end: event.end, isAllDay: event.isAllDay, now: now
                ))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
            }
            if event.meetingURL != nil {
                Button {
                    // Through the model, which also puts the Join bar away.
                    nook.joinMeeting(event)
                } label: {
                    Text("Join")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(red: 0.95, green: 0.93, blue: 0.87))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { nook.startNote(for: event) }
    }
}

/// Pure text and selection logic for the hero style. Plain values in, plain
/// values out, so tests can drive it with a fixed `now`.
enum NookCalendarHeroLogic {
    /// The first unfinished timed event; failing that the first all-day event
    /// that covers today.
    static func featured(from events: [NookCalendarEvent], now: Date) -> NookCalendarEvent? {
        let unfinished = events.filter { $0.end > now }.sorted { $0.start < $1.start }
        if let timed = unfinished.first(where: { !$0.isAllDay }) { return timed }
        return unfinished.first { $0.isAllDay && $0.start <= endOfDay(now) }
    }

    /// The unfinished event after the featured one, if any.
    static func following(
        _ featured: NookCalendarEvent, in events: [NookCalendarEvent], now: Date
    ) -> NookCalendarEvent? {
        events
            .filter { $0.end > now && $0.id != featured.id }
            .sorted { $0.start < $1.start }
            .first
    }

    static func countdown(start: Date, end: Date, isAllDay: Bool, now: Date) -> String {
        if isAllDay { return "today" }
        if start <= now { return "now" }
        let cal = Calendar.current
        if !cal.isDate(start, inSameDayAs: now) {
            return start.formatted(.dateTime.weekday(.abbreviated))
        }
        let minutes = max(1, Int((start.timeIntervalSince(now) / 60).rounded(.up)))
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    /// The small line under the countdown.
    static func detail(start: Date, end: Date, isAllDay: Bool, now: Date) -> String {
        if isAllDay { return "all day" }
        if start <= now { return "ends " + end.formatted(date: .omitted, time: .shortened) }
        return start.formatted(date: .omitted, time: .shortened)
    }

    /// "10:00 to 11:15 AM", plus " · location" when the location is not a URL.
    static func subtitle(start: Date, end: Date, isAllDay: Bool, location: String?) -> String {
        var text = isAllDay ? "All day" : timeRange(start: start, end: end)
        if let place = location?.trimmingCharacters(in: .whitespacesAndNewlines),
           !place.isEmpty, !looksLikeURL(place) {
            text += " · " + place
        }
        return text
    }

    static func timeRange(start: Date, end: Date) -> String {
        let from = start.formatted(date: .omitted, time: .shortened)
        let to = end.formatted(date: .omitted, time: .shortened)
        if let space = from.lastIndex(where: { $0 == " " || $0 == "\u{202F}" || $0 == "\u{00A0}" }), to.hasSuffix(from[space...]) {
            return "\(from[..<space]) to \(to)"
        }
        return "\(from) to \(to)"
    }

    static func looksLikeURL(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("://") || lower.hasPrefix("www.")
    }

    private static func endOfDay(_ date: Date) -> Date {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        return cal.date(byAdding: .day, value: 1, to: startOfDay) ?? date
    }
}
