import SwiftUI
import OpenIslandCore

/// One-row summary of the Nook shown at the bottom of the agents page:
/// now playing with transport, plus the timer, the next event or the tray
/// count. Tapping the row switches to the full Nook page.
struct NookCompactBar: View {
    var model: AppModel

    static let height: CGFloat = 44
    /// Height including the padding `IslandPanelView` puts around it.
    static let outerHeight: CGFloat = 56

    private var nook: NookModel { model.nook }

    var body: some View {
        HStack(spacing: 10) {
            mediaSection
            if let side = sideItem {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 1, height: 18)
                HStack(spacing: 5) {
                    Image(systemName: side.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(side.tint)
                    Text(side.text)
                        .font(.system(size: 11, weight: .medium, design: side.monospaced ? .monospaced : .default))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                // Fixed width so the title and the event both keep room.
                // A meeting to join gives part of it to the Join button.
                .frame(width: nook.meetingPrompt == nil ? 170 : 118, alignment: .leading)
            }
            if let meeting = nook.meetingPrompt {
                NookJoinButton { nook.joinMeeting(meeting) }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background(NookCardBackground())
        .contentShape(Rectangle())
        .onTapGesture { model.showNookPage() }
    }

    @ViewBuilder
    private var mediaSection: some View {
        if let state = nook.nowPlaying {
            NookAlbumArtView(image: nook.artwork, size: 26, cornerRadius: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(state.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                if let artist = state.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 90, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            HStack(spacing: 0) {
                transport("backward.fill") { nook.media.previousTrack() }
                transport(state.isPlaying ? "pause.fill" : "play.fill", size: 12) { nook.media.togglePlayPause() }
                transport("forward.fill") { nook.media.nextTrack() }
            }
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))
            Text("Nothing playing")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private struct SideItem {
        let symbol: String
        let text: String
        let tint: Color
        let monospaced: Bool
    }

    /// A meeting to join wins, then the timer, then the next event, then
    /// the tray count.
    private var sideItem: SideItem? {
        if let meeting = nook.meetingPrompt {
            return SideItem(
                symbol: "video.fill",
                text: "\(meeting.title) · \(Self.relativeStart(meeting))",
                tint: meeting.calendarColor,
                monospaced: false
            )
        }
        if let timerText = nook.timer.closedText {
            let round = nook.timer.pomodoro
            return SideItem(
                symbol: NookPomodoroLook.symbol(for: round),
                text: timerText,
                tint: NookPomodoroLook.tint(for: round),
                monospaced: true
            )
        }
        if let event = nook.nextEvent {
            return SideItem(
                symbol: "calendar",
                text: "\(event.title) · \(Self.relativeStart(event))",
                tint: event.calendarColor,
                monospaced: false
            )
        }
        let count = nook.tray.items.count
        if count > 0 {
            return SideItem(symbol: "tray.full", text: "\(count)", tint: .white.opacity(0.6), monospaced: true)
        }
        return nil
    }

    static func relativeStart(_ event: NookCalendarEvent) -> String {
        let now = Date()
        if event.isAllDay { return "all day" }
        if event.start <= now { return "now" }
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes < 60 { return "in \(minutes) min" }
        if Calendar.current.isDateInToday(event.start) {
            return event.start.formatted(date: .omitted, time: .shortened)
        }
        return event.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private func transport(_ systemName: String, size: CGFloat = 10, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One-row summary of the agents shown at the top of the Nook page.
/// Tapping it switches to the agents page.
struct NookAgentsBar: View {
    var model: AppModel

    static let height: CGFloat = 34
    /// Height including the padding `IslandPanelView` puts around it.
    static let outerHeight: CGFloat = 42

    var body: some View {
        let sessions = model.surfacedSessions
        let waiting = sessions.filter { $0.phase.requiresAttention }.count
        let running = sessions.filter { $0.phase == .running }.count
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(Array(sessions.prefix(8).enumerated()), id: \.offset) { _, session in
                    Circle()
                        .fill(IslandDesignPalette.Status.tint(for: session.phase))
                        .frame(width: 6, height: 6)
                }
            }
            Text(Self.summary(total: sessions.count, running: running, waiting: waiting))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(waiting > 0 ? 0.9 : 0.6))
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "terminal.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background(NookCardBackground())
        .contentShape(Rectangle())
        .onTapGesture { model.showAgentsPage() }
    }

    static func summary(total: Int, running: Int, waiting: Int) -> String {
        var parts = ["\(total) agent\(total == 1 ? "" : "s")"]
        if running > 0 { parts.append("\(running) running") }
        if waiting > 0 { parts.append("\(waiting) waiting for you") }
        return parts.joined(separator: " · ")
    }
}
