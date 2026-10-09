import SwiftUI

/// Size of the Join bar. A plain enum and not part of a view, which keeps
/// it callable from tests without the main actor.
enum NookJoinBarLayout {
    static let height: CGFloat = 36

    /// Height the bar adds above the grid: itself and one row gap.
    static var pageHeight: CGFloat { height + NookWidgetLayout.rowSpacing }
}

/// Words for the Join bar. Pure, which lets tests drive them with a fixed
/// `now`.
enum NookJoinText {
    /// "in 4 min" before the start, "now" in its first minute, then
    /// "started 3 min ago".
    static func when(start: Date, now: Date, lang: LanguageManager = .shared) -> String {
        let minutes = NookMeetingPrompt.minutesUntilStart(start, now: now)
        if minutes > 0 { return lang.t("nook.calendar.join.in", minutes) }
        if minutes == 0 { return lang.t("nook.calendar.join.now") }
        return lang.t("nook.calendar.join.ago", -minutes)
    }
}

/// The Join control: a small green capsule. Shared by the Join bar and the
/// row under the agent list.
struct NookJoinButton: View {
    let action: () -> Void

    private static let tint = Color(red: 111 / 255, green: 185 / 255, blue: 130 / 255)

    var body: some View {
        Button(action: action) {
            Text(LanguageManager.shared.t("nook.calendar.join"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.black.opacity(0.85))
                .padding(.horizontal, 12)
                .frame(height: 22)
                .background(Capsule().fill(Self.tint))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(LanguageManager.shared.t("nook.calendar.join.help"))
    }
}

/// The small camera on an event's row: a click joins its meeting. No
/// taller than the row's text, which keeps the row heights the cards
/// count on.
struct NookJoinMark: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "video.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 16, height: 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(LanguageManager.shared.t("nook.calendar.join.help"))
        .accessibilityLabel(LanguageManager.shared.t("nook.calendar.join"))
    }
}

/// One line at the top of the Nook page while a meeting is about to start
/// or has just started: what it is, when, and a Join button. The "event
/// soon" notice in the closed island cannot take a click, which makes this
/// the control it points at: open the island and Join is the first thing
/// there.
struct NookJoinBar: View {
    var nook: NookModel
    let event: NookCalendarEvent

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "video.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(event.calendarColor)
            Text(event.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            // The calendar ticks once a minute; the countdown keeps its own
            // clock, which stops "in 2 min" from running a minute behind.
            TimelineView(.periodic(from: .now, by: 20)) { context in
                Text(NookJoinText.when(start: event.start, now: context.date))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 6)
            NookJoinButton { nook.joinMeeting(event) }
            Button {
                withMotion(Motion.reflow) { nook.dismissMeetingPrompt(for: event) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(LanguageManager.shared.t("nook.calendar.join.hide"))
            .accessibilityLabel(LanguageManager.shared.t("nook.calendar.join.hide"))
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NookCardBackground())
    }
}
