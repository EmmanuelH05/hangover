import AppKit
import Foundation
import SwiftUI

/// The looks the calendar card can take. Chosen per display in the
/// Personalization tab.
enum NookCalendarStyle: String, CaseIterable, Identifiable, Sendable {
    /// A week of days to step through, events for the picked day, quick add.
    case strip
    /// A short list of what is coming up.
    case agenda
    /// One bar for today with a block per event.
    case timeline
    /// The next event, large, with a countdown and a join button.
    case hero
    /// A month grid with the picked day's events below.
    case month

    var id: String { rawValue }
}

/// One of the user's calendars, for the per-display calendar picker.
struct NookCalendarInfo: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let color: Color
    /// False for calendars that cannot take a new event (subscriptions,
    /// birthdays).
    var allowsChanges = true
}

/// What a new event needs. `NookEventForm` builds one from the editor, and
/// `NookEventQuickAdd` builds one from typed text.
struct NookEventDraft: Equatable, Sendable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location = ""
    var notes = ""
    /// Nil saves to the system's default calendar.
    var calendarID: String? = nil
    var alert: NookEventAlert = .none
    var repeats: NookEventRepeat = .never
}

/// The line under a day's short list. "+3 more" grows the card to show the
/// whole day, and "Show less" puts it back.
struct NookCalendarMoreButton: View {
    /// How many rows the short list leaves out.
    let hidden: Int
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(isExpanded ? "Show less" : "+\(hidden) more")
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Show fewer events" : "Show every event on this day")
    }
}

enum NookCalendarError: Error, Equatable {
    case noAccess
    case noWritableCalendar
    case saveFailed(String)

    var message: String {
        switch self {
        case .noAccess: "Calendar access is needed to add events."
        case .noWritableCalendar: "No calendar accepts new events."
        case .saveFailed(let reason): "Could not save the event: \(reason)"
        }
    }
}

/// One event line: color dot, title, time. Shared by every calendar style.
/// A tap starts a note for the event. An event with a meeting link carries
/// a small join mark. The row opens nothing itself: the mark calls
/// `onJoin`, which every look hands to `NookModel.joinMeeting`, the one
/// place that opens a meeting and puts the Join bar away.
struct NookCalendarRow: View {
    let event: NookCalendarEvent
    let now: Date
    /// False when the row sits under a picked day and the weekday is known.
    var showsWeekday: Bool = true
    var onTap: (() -> Void)? = nil
    /// Nil leaves the join mark off the row.
    var onJoin: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(event.calendarColor)
                .frame(width: 7, height: 7)
            Text(event.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            Spacer(minLength: 6)
            if event.meetingURL != nil, let onJoin {
                NookJoinMark(action: onJoin)
            }
            Text(Self.timeText(for: event, now: now, showsWeekday: showsWeekday))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    static func timeText(for event: NookCalendarEvent, now: Date, showsWeekday: Bool = true) -> String {
        let cal = Calendar.current
        let sameDay = cal.isDate(event.start, inSameDayAs: now)
        let weekday = event.start.formatted(.dateTime.weekday(.abbreviated))
        let prefix = showsWeekday && !sameDay ? "\(weekday) " : ""
        if event.isAllDay {
            return sameDay || event.start <= now ? "All day" : "\(prefix)All day"
        }
        if event.start <= now, event.end > now { return "now" }
        if sameDay, event.start > now {
            let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
            if minutes < 60 { return "in \(minutes) min" }
        }
        return prefix + event.start.formatted(date: .omitted, time: .shortened)
    }
}

/// One task line under a picked day: square marker, title.
struct NookCalendarTaskRow: View {
    let task: NookTodoItem

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .stroke(Color.white.opacity(0.55), lineWidth: 1.5)
                .frame(width: 7, height: 7)
            Text(task.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
            Spacer(minLength: 6)
            Text("due")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}
