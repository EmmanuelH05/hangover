import AppKit
import SwiftUI

// The Nook page as the preview stage draws it: a setup's real grid (order,
// sizes, calendar look) filled with sample cards. The real cards read live
// services, which a template that is not applied cannot give them, and a
// preview should look the same whether or not music happens to be playing.
// Nothing here takes a click.

// MARK: - Sample content

/// The album art of the sample track. One image for the whole app, because
/// the closed island compares artwork by identity.
@MainActor
enum PreviewSampleArt {
    static let image = NSImage(size: NSSize(width: 120, height: 120), flipped: false) { rect in
        let gradient = NSGradient(colors: [
            NSColor(srgbRed: 1.0, green: 0.36, blue: 0.48, alpha: 1),
            NSColor(srgbRed: 0.52, green: 0.28, blue: 0.92, alpha: 1),
        ])
        gradient?.draw(in: rect, angle: -45)
        NSColor.white.withAlphaComponent(0.2).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.3, dy: rect.height * 0.3)).fill()
        return true
    }
}

private enum NookSampleContent {
    static let track = "Midnight Drive"
    static let artist = "Neon Coast"
    static let album = "Afterglow"
    static let timerText = "24:59"

    struct Event: Identifiable {
        let id: Int
        let title: String
        let time: String
        let color: Color
    }

    static let events = [
        Event(id: 0, title: "Standup", time: "in 20 min", color: .blue),
        Event(id: 1, title: "Design review", time: "2:00 PM", color: .purple),
        Event(id: 2, title: "Gym", time: "6:30 PM", color: .green),
    ]

    /// What the large calendar lists under its look: the days after today.
    static let laterEvents = [
        Event(id: 10, title: "Office hours", time: "Fri 10:00 AM", color: .orange),
        Event(id: 11, title: "Dentist", time: "Mon 9:30 AM", color: .green),
        Event(id: 12, title: "Midterm review", time: "Tue 4:00 PM", color: .purple),
    ]

    static let tasks = [
        "Finish problem set 3", "Email the TA", "Review the pull request", "Book flights",
        "Renew library books", "Plan the weekend", "Call home", "Water the plants",
    ]

    struct Note: Identifiable {
        let id: Int
        let time: String
        let text: String
    }

    static let notes = [
        Note(id: 0, time: "9:12", text: "Try the new cache key"),
        Note(id: 1, time: "10:40", text: "Ask about the midterm room"),
        Note(id: 2, time: "1:05", text: "Idea: widget presets"),
        Note(id: 3, time: "2:30", text: "Send the slides tonight"),
        Note(id: 4, time: "3:15", text: "Lab partner is free Friday"),
        Note(id: 5, time: "4:02", text: "Read chapter 6"),
        Note(id: 6, time: "5:48", text: "Groceries on the way back"),
    ]

    struct File: Identifiable {
        let id: Int
        let symbol: String
        let name: String
    }

    static let files = [
        File(id: 0, symbol: "doc.richtext.fill", name: "notes.pdf"),
        File(id: 1, symbol: "photo.fill", name: "mock.png"),
        File(id: 2, symbol: "swift", name: "main.swift"),
        File(id: 3, symbol: "tablecells.fill", name: "data.csv"),
        File(id: 4, symbol: "doc.zipper", name: "build.zip"),
        File(id: 5, symbol: "music.note", name: "demo.mp3"),
        File(id: 6, symbol: "doc.text.fill", name: "todo.txt"),
        File(id: 7, symbol: "film.fill", name: "clip.mov"),
    ]
}

// MARK: - Panel

/// The opened island on its Nook page: the surface, a header with the
/// island's buttons, the agents bar when the setup shows it, and the grid.
struct PreviewNookPanel: View {
    let placements: [NookWidgetPlacement]
    let calendarStyle: NookCalendarStyle
    let profile: IslandAppearanceDisplayProfile
    /// The display's opened look: how wide the panel is drawn and what its
    /// corners look like.
    var look: IslandOpenedLook = .standard
    let showsAgentsBar: Bool
    let emptyTitle: String

    static let headHeight: CGFloat = 42
    static let footHeight: CGFloat = 10
    private static let emptyHeight: CGFloat = 96
    /// The widest the panel is drawn. The stage lays its scene out this
    /// wide, and the widest look would run past it.
    static let maxWidth: CGFloat = 702

    private var metrics: IslandOpenedMetrics {
        IslandOpenedMetrics.resolve(look: look, profile: profile)
    }

    var body: some View {
        let inset = metrics.sideInset
        ZStack(alignment: .top) {
            surfaceShape
                .fill(V6Palette.ink)
                .shadow(color: .black.opacity(0.36), radius: 22, y: 12)

            VStack(spacing: 0) {
                head
                if showsAgentsBar {
                    NookSampleAgentsBar()
                        .padding(.horizontal, inset)
                        .padding(.top, 8)
                }
                page
                    .padding(.horizontal, inset)
                    .padding(.vertical, NookPanelView.verticalPadding)
                Color.clear.frame(height: Self.footHeight)
            }
            .clipShape(surfaceShape)
        }
        .frame(width: min(metrics.panelWidth, Self.maxWidth))
        .fixedSize(horizontal: false, vertical: true)
    }

    private var surfaceShape: OpenedIslandSurfaceShape {
        OpenedIslandSurfaceShape(
            topProfile: profile == .notch ? .notch : .topBar,
            topCornerRadius: metrics.topRadius,
            bottomCornerRadius: metrics.bottomRadius
        )
    }

    private var head: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            ForEach(["terminal.fill", "speaker.wave.2.fill", "gearshape.fill", "power"], id: \.self) { symbol in
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.08), in: Circle())
            }
        }
        .padding(.horizontal, metrics.headerInset)
        .frame(height: Self.headHeight)
    }

    @ViewBuilder
    private var page: some View {
        if placements.isEmpty {
            Text(emptyTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: Self.emptyHeight)
        } else {
            VStack(spacing: NookWidgetLayout.rowSpacing) {
                ForEach(NookWidgetLayout.rows(placements)) { row in
                    HStack(spacing: NookWidgetLayout.columnSpacing) {
                        ForEach(row.placements) { placement in
                            NookSampleCard(kind: placement.kind, size: placement.size, calendarStyle: calendarStyle)
                        }
                        // A lone small widget keeps its half of the row.
                        if row.isSmallRow, row.placements.count == 1 {
                            Color.clear
                        }
                    }
                    .frame(height: rowHeight(row))
                }
            }
        }
    }

    private func rowHeight(_ row: NookWidgetRow) -> CGFloat {
        row.isSmallRow
            ? NookWidgetLayout.smallHeight
            : NookPanelView.cardHeight(row.placements[0], calendarStyle: calendarStyle)
    }
}

// MARK: - Bars

/// The agent summary row above the Nook widgets, with quiet sample agents.
struct NookSampleAgentsBar: View {
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(0..<PreviewSamples.agentCount, id: \.self) { _ in
                    Circle()
                        .fill(IslandDesignPalette.Status.idle)
                        .frame(width: 6, height: 6)
                }
            }
            Text(NookAgentsBar.summary(total: PreviewSamples.agentCount, running: 0, waiting: 0))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
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
        .frame(height: NookAgentsBar.height)
        .background(NookCardBackground())
    }
}

/// The now-playing row under the agent list, with the sample track.
struct NookSampleCompactBar: View {
    var body: some View {
        HStack(spacing: 10) {
            NookAlbumArtView(image: PreviewSampleArt.image, size: 26, cornerRadius: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(NookSampleContent.track)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Text(NookSampleContent.artist)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            NookSampleTransport(iconSize: 10, playSize: 12, spacing: 14)
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1, height: 18)
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NookSampleContent.events[0].color)
                Text("\(NookSampleContent.events[0].title) · \(NookSampleContent.events[0].time)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: NookCompactBar.height)
        .background(NookCardBackground())
    }
}

private struct NookSampleTransport: View {
    var iconSize: CGFloat
    var playSize: CGFloat
    var spacing: CGFloat

    var body: some View {
        HStack(spacing: spacing) {
            Image(systemName: "backward.fill").font(.system(size: iconSize, weight: .bold))
            Image(systemName: "pause.fill").font(.system(size: playSize, weight: .bold))
            Image(systemName: "forward.fill").font(.system(size: iconSize, weight: .bold))
        }
        .foregroundStyle(.white.opacity(0.85))
    }
}

private struct NookSampleProgress: View {
    var fraction: CGFloat = 0.4

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.15))
            .frame(height: 3)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: geometry.size.width * fraction)
                }
            }
    }
}

// MARK: - Cards

/// A still picture of one widget at one size, with sample content, in the
/// real card's type sizes, spacing and background.
struct NookSampleCard: View {
    let kind: NookWidgetKind
    let size: NookWidgetSize
    let calendarStyle: NookCalendarStyle

    private static let cornerRadius: CGFloat = 16

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(NookCardBackground())
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .media: media
        case .calendar: NookSampleCalendar(size: size, style: calendarStyle)
        case .todo: todo
        case .notes: notes
        case .tray: tray
        case .timer: timer
        case .mirror: mirror
        case .weather: NookWeatherContent.sample(size: size)
        }
    }

    // MARK: Now playing

    @ViewBuilder
    private var media: some View {
        switch size {
        case .small:
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    NookAlbumArtView(image: PreviewSampleArt.image, size: 48, cornerRadius: 9)
                    trackText(titleSize: 12, subtitleSize: 10, subtitle: NookSampleContent.artist)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
                NookSampleTransport(iconSize: 12, playSize: 14, spacing: 22)
            }
        case .medium:
            HStack(spacing: 14) {
                NookAlbumArtView(image: PreviewSampleArt.image, size: 64, cornerRadius: 12)
                VStack(alignment: .leading, spacing: 5) {
                    trackText(titleSize: 13, subtitleSize: 11, subtitle: albumLine)
                    NookSampleProgress()
                }
                NookSampleTransport(iconSize: 12, playSize: 16, spacing: 14)
            }
        case .large:
            HStack(spacing: 16) {
                NookAlbumArtView(image: PreviewSampleArt.image, size: 120, cornerRadius: 14)
                VStack(alignment: .leading, spacing: 0) {
                    trackText(titleSize: 15, subtitleSize: 12, subtitle: albumLine)
                    Spacer(minLength: 0)
                    NookSampleProgress()
                    HStack {
                        Text("1:24")
                        Spacer(minLength: 0)
                        Text("3:31")
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 4)
                    NookSampleTransport(iconSize: 14, playSize: 18, spacing: 26)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
        }
    }

    private var albumLine: String { "\(NookSampleContent.artist) · \(NookSampleContent.album)" }

    private func trackText(titleSize: CGFloat, subtitleSize: CGFloat, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(NookSampleContent.track)
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: subtitleSize))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
    }

    // MARK: Todo

    private var todo: some View {
        let rows = NookTodoCard.maxRows(for: size)
        return VStack(alignment: .leading, spacing: 6) {
            NookCardHeader(
                title: "Todo",
                systemImage: "checklist",
                trailing: size == .small ? nil : "\(NookSampleContent.tasks.count)"
            )
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(NookSampleContent.tasks.prefix(rows).enumerated()), id: \.offset) { _, task in
                    HStack(spacing: 8) {
                        Circle()
                            .stroke(Color.white.opacity(0.45), lineWidth: 1.5)
                            .frame(width: 12, height: 12)
                        Text(task)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                    .frame(height: 18)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Notes

    private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            NookCardHeader(title: "Notes", systemImage: "note.text", trailing: size == .small ? nil : "notes.md")
            Text(size == .small ? "Jot, return to save" : "Jot something, return to save")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.3))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 2) {
                ForEach(NookSampleContent.notes.prefix(size == .large ? 7 : 3)) { note in
                    HStack(spacing: 8) {
                        Text(note.time)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35))
                            .fixedSize()
                        Text(note.text)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: File tray

    private var tray: some View {
        VStack(alignment: .leading, spacing: 6) {
            NookCardHeader(title: "File tray", systemImage: "tray.full", trailing: "\(NookSampleContent.files.count)")
            switch size {
            case .small:
                HStack(spacing: 6) {
                    ForEach(NookSampleContent.files.prefix(3)) { file in
                        fileIcon(file, side: 36)
                    }
                    Text("+\(NookSampleContent.files.count - 3)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 36, height: 36)
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
            case .medium:
                HStack(alignment: .top, spacing: 6) {
                    ForEach(NookSampleContent.files.prefix(6)) { file in
                        fileTile(file)
                    }
                    Spacer(minLength: 0)
                }
            case .large:
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(NookSampleContent.files.prefix(6)) { file in fileTile(file) }
                        Spacer(minLength: 0)
                    }
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(NookSampleContent.files.dropFirst(6)) { file in fileTile(file) }
                        Spacer(minLength: 0)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func fileIcon(_ file: NookSampleContent.File, side: CGFloat) -> some View {
        Image(systemName: file.symbol)
            .font(.system(size: side * 0.45, weight: .medium))
            .foregroundStyle(.white.opacity(0.75))
            .frame(width: side, height: side)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.08)))
    }

    private func fileTile(_ file: NookSampleContent.File) -> some View {
        VStack(spacing: 3) {
            fileIcon(file, side: 30)
            Text(file.name)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: 60)
    }

    // MARK: Focus timer

    @ViewBuilder
    private var timer: some View {
        switch size {
        case .small:
            VStack(spacing: 6) {
                NookCardHeader(title: "Focus timer", systemImage: "timer")
                Text(NookSampleContent.timerText)
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.92))
                NookSampleProgress(fraction: 0.6)
                Spacer(minLength: 0)
            }
        case .medium:
            HStack(spacing: 14) {
                Text(NookSampleContent.timerText)
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize()
                VStack(alignment: .leading, spacing: 8) {
                    NookCardHeader(title: "Focus timer", systemImage: "timer", trailing: "25 min")
                    NookSampleProgress(fraction: 0.6)
                }
                timerButtons
            }
            .frame(maxHeight: .infinity)
        case .large:
            VStack(spacing: 8) {
                NookCardHeader(title: "Focus timer", systemImage: "timer", trailing: "25 min")
                Text(NookSampleContent.timerText)
                    .font(.system(size: 44, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.92))
                NookSampleProgress(fraction: 0.6)
                timerButtons
                Spacer(minLength: 0)
            }
        }
    }

    private var timerButtons: some View {
        HStack(spacing: 6) {
            ForEach(["pause.fill", "stop.fill"], id: \.self) { symbol in
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
        }
    }

    // MARK: Mirror

    /// The mirror's tile is a switch. The camera itself is never previewed.
    @ViewBuilder
    private var mirror: some View {
        if size == .small {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "camera")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Mirror")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Text("Camera is off")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                mirrorSwitch
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 12) {
                Image(systemName: "camera")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.07)))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mirror")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("The camera stays off until you turn it on.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                mirrorSwitch
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var mirrorSwitch: some View {
        Text("Turn on")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(Capsule().fill(Color.white.opacity(0.1)))
            .fixedSize()
    }
}

// MARK: - Calendar looks

/// The calendar card in the setup's look. Small is the compact list at every
/// look, and large puts the up-next list under the medium look, the way the
/// real card does.
private struct NookSampleCalendar: View {
    let size: NookWidgetSize
    let style: NookCalendarStyle

    private static let verticalPadding: CGFloat = 12

    var body: some View {
        switch size {
        case .small:
            VStack(alignment: .leading, spacing: 8) {
                NookCardHeader(title: "Calendar", systemImage: "calendar")
                eventRows(NookSampleContent.events, spacing: 5)
                Spacer(minLength: 0)
            }
        case .medium:
            look
        case .large:
            VStack(alignment: .leading, spacing: 0) {
                look
                    .frame(
                        maxWidth: .infinity,
                        minHeight: NookCalendarCard.height(for: style) - 2 * Self.verticalPadding,
                        maxHeight: NookCalendarCard.height(for: style) - 2 * Self.verticalPadding,
                        alignment: .topLeading
                    )
                upNext
            }
        }
    }

    @ViewBuilder
    private var look: some View {
        switch style {
        case .agenda: agenda
        case .hero: hero
        case .timeline: timeline
        case .strip: strip
        case .month: month
        }
    }

    private func eventRows(_ events: [NookSampleContent.Event], spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(events) { event in
                HStack(spacing: 8) {
                    Circle()
                        .fill(event.color)
                        .frame(width: 7, height: 7)
                    Text(event.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(event.time)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
        }
    }

    private var todayText: String {
        Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 8) {
            NookCardHeader(title: "Calendar", systemImage: "calendar", trailing: todayText)
            eventRows(NookSampleContent.events, spacing: 5)
            Spacer(minLength: 0)
        }
    }

    private var hero: some View {
        let event = NookSampleContent.events[0]
        return VStack(alignment: .leading, spacing: 6) {
            NookCardHeader(title: "Next up", systemImage: "calendar")
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(event.color)
                    .frame(width: 4, height: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                    Text("10:00 to 10:30 AM · Zoom")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("20m")
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("until it starts")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
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
            eventRows([NookSampleContent.events[1]], spacing: 0)
                .opacity(0.6)
            Spacer(minLength: 0)
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            NookCardHeader(title: "Today", systemImage: "calendar", trailing: "Standup in 20 min")
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                    ForEach(Array(Self.blocks.enumerated()), id: \.offset) { index, block in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(NookSampleContent.events[index].color.opacity(0.75))
                            .frame(width: width * block.length, height: 20)
                            .offset(x: width * block.start)
                    }
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: 1.5)
                        .offset(x: width * 0.16)
                }
            }
            .frame(height: 26)
            HStack {
                ForEach(["9 AM", "12 PM", "3 PM", "6 PM"], id: \.self) { tick in
                    Text(tick)
                    if tick != "6 PM" { Spacer(minLength: 0) }
                }
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.white.opacity(0.35))
            Spacer(minLength: 0)
        }
    }

    /// Start and length of each sample event as a share of the bar.
    private static let blocks: [(start: CGFloat, length: CGFloat)] = [(0.2, 0.08), (0.52, 0.12), (0.86, 0.1)]

    private var strip: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        return VStack(alignment: .leading, spacing: 8) {
            NookCardHeader(title: "Calendar", systemImage: "calendar", trailing: todayText)
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    let date = calendar.date(byAdding: .day, value: index - offset, to: today) ?? today
                    let isToday = index == offset
                    VStack(spacing: 3) {
                        Text(date.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                        Text("\(calendar.component(.day, from: date))")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isToday ? Color.orange : .white.opacity(0.85))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.white.opacity(isToday ? 0.12 : 0))
                    )
                }
            }
            eventRows(NookSampleContent.events, spacing: 5)
            Spacer(minLength: 0)
        }
    }

    private var month: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let day = calendar.component(.day, from: today)
        let monthStart = calendar.date(byAdding: .day, value: 1 - day, to: today) ?? today
        let leading = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: today)?.count ?? 30
        let weeks = Int((Double(leading + dayCount) / 7).rounded(.up))
        let marked: Set<Int> = [day, min(dayCount, day + 2), min(dayCount, day + 5)]
        return VStack(alignment: .leading, spacing: 6) {
            NookCardHeader(
                title: today.formatted(.dateTime.month(.wide)),
                systemImage: "calendar",
                trailing: today.formatted(.dateTime.year())
            )
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    let date = calendar.date(byAdding: .day, value: index - leading, to: monthStart) ?? monthStart
                    Text(date.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(maxWidth: .infinity)
                }
            }
            VStack(spacing: 2) {
                ForEach(0..<weeks, id: \.self) { week in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { column in
                            monthCell(week * 7 + column - leading + 1, dayCount: dayCount, today: day, marked: marked)
                        }
                    }
                }
            }
            eventRows(Array(NookSampleContent.events.prefix(weeks > 5 ? 2 : 3)), spacing: 5)
                .padding(.top, 2)
            Spacer(minLength: 0)
        }
    }

    private func monthCell(_ number: Int, dayCount: Int, today: Int, marked: Set<Int>) -> some View {
        let isInMonth = number >= 1 && number <= dayCount
        let isToday = number == today
        return VStack(spacing: 1) {
            Text(isInMonth ? "\(number)" : "")
                .font(.system(size: 11, weight: isToday ? .bold : .medium))
                .foregroundStyle(isToday ? Color.black : .white.opacity(0.8))
                .frame(width: 20, height: 20)
                .background(Circle().fill(isToday ? Color.orange : .clear))
            Circle()
                .fill(Color.white.opacity(isInMonth && marked.contains(number) && !isToday ? 0.5 : 0))
                .frame(width: 3, height: 3)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 26)
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("UP NEXT")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.5))
                .frame(height: 14)
            eventRows(NookSampleContent.laterEvents, spacing: 6)
        }
        .padding(.top, 10)
    }
}
