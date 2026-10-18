import AppKit
import SwiftUI

/// What the closed island's two wings show when the Nook has something to
/// say: album art plus a GIF while music plays, a symbol plus text for a
/// running timer, a charger, AirPods, or an event coming up.
///
/// `yieldsToAgents` lets the media activity hand the right wing back to the
/// agent grid while an agent waits for approval; timers and transient
/// notices keep their text regardless.
struct NookClosedActivity: Equatable {
    enum Leading {
        case artwork(NSImage?)
        case symbol(String, Color)
        /// A small spinner, for work under way (D82).
        case spinner
    }

    enum Trailing: Equatable {
        case media(NookClosedMediaActivity)
        case text(String)
        /// A level from 0 to 100, drawn as a ring with the number in it.
        case level(percent: Int, tint: Color)
        /// Two shortcut chips, for a question the pill asks (D82).
        case chips(NookClosedChips)

        /// Width the right wing needs for words or chips; nil for art and
        /// the ring, which keep the wing's own width.
        var contentWidth: CGFloat? {
            switch self {
            case .media, .level: nil
            case let .text(text): NookWingText.width(of: text)
            case let .chips(chips): chips.width
            }
        }
    }

    var leading: Leading
    /// Nil leaves the right side to the agents' own slot.
    var trailing: Trailing?
    var yieldsToAgents: Bool
    /// Words after the glyph in the left wing, for a question the pill
    /// asks (D82). Nil leaves the wing to the glyph.
    var leadingText: String? = nil

    /// True while music, not a timer or a notice, is what is showing.
    var showsArtwork: Bool {
        if case .artwork = leading { return true }
        return false
    }
}

extension NookClosedActivity.Leading: Equatable {
    /// `NSImage` has no value equality; the model hands out one decoded
    /// image per track, so identity is the right comparison.
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.artwork(a), .artwork(b)):
            return a === b
        case let (.symbol(a, ca), .symbol(b, cb)):
            return a == b && ca == cb
        case (.spinner, .spinner):
            return true
        default:
            return false
        }
    }
}

/// A short-lived notice such as "Charging · 78%" or "AirPods connected".
struct NookTransientActivity: Equatable {
    var symbol: String
    var text: String
    var tint: Color = .white
    /// A level from 0 to 100. The closed island then draws a ring with the
    /// number in it and leaves the text out, for a notice whose words do
    /// not fit beside the notch, such as the charger's.
    var level: Int? = nil
    /// True draws a spinner in place of the symbol, for work under way
    /// such as "Updating to 1.0.14…" (D82).
    var spins: Bool = false
}

/// One chip on the closed pill: the shortcut's keys, when the shortcut is
/// ready, and what pressing it does.
struct NookClosedChip: Equatable {
    var keys: String?
    var title: String
    /// The paper style for the chip that goes ahead (K5), the plain one
    /// for the chip that holds off.
    var isPrimary: Bool = false

    /// About what the chip measures: the keys box, the gap and the title.
    var width: CGFloat {
        let keysWidth = keys.map { CGFloat($0.count) * 7 + 12 } ?? 0
        return keysWidth + (keys == nil ? 0 : 5) + NookWingText.width(of: title) - 2
    }
}

/// The two chips of a question on the pill: the one that holds off first,
/// then the one that goes ahead, the agent card's order (K6).
struct NookClosedChips: Equatable {
    var deny: NookClosedChip
    var approve: NookClosedChip

    static let gap: CGFloat = 10

    var width: CGFloat { deny.width + Self.gap + approve.width }
}

/// About how wide words are in the wings' type (11.5pt rounded semibold),
/// with a little room: the pill sizes itself before SwiftUI measures.
enum NookWingText {
    static func width(of text: String) -> CGFloat {
        CGFloat(Double(text.count) * 6.6 + 8)
    }
}

// MARK: - Wing renderers

struct NookLeadingWingView: View {
    let leading: NookClosedActivity.Leading
    var size: CGFloat
    /// Agent status dot on the artwork's corner, nil to hide.
    var statusTint: Color? = nil

    var body: some View {
        switch leading {
        case let .artwork(image):
            NookAlbumArtView(image: image, size: size)
                .overlay(alignment: .bottomTrailing) {
                    if let statusTint {
                        Circle()
                            .fill(statusTint)
                            .frame(width: 7, height: 7)
                            .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                            .offset(x: 2, y: 2)
                    }
                }
        case let .symbol(name, tint):
            Image(systemName: name)
                .font(.system(size: size * 0.7, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
        case .spinner:
            NookWingSpinner(size: size * 0.7)
                .frame(width: size, height: size)
        }
    }
}

/// A small open ring that turns, for work under way (D82). Drawn by hand
/// so the still render shows it; it stands still under Reduce Motion.
struct NookWingSpinner: View {
    var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.nookDrawsStill) private var drawsStill
    @State private var turns = false

    var body: some View {
        Circle()
            .trim(from: 0.2, to: 1)
            .stroke(V6Palette.paper, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(turns ? 360 : 0))
            .onAppear {
                guard !reduceMotion, !drawsStill else { return }
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { turns = true }
            }
            .accessibilityHidden(true)
    }
}

/// The words after the glyph in the left wing, in the wings' type.
struct NookLeadingTextView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            .foregroundStyle(V6Palette.paper)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

/// The two chips on the pill's right wing, the agent card's chips drawn
/// small: keys in a box first, the title after (K6). The chip that goes
/// ahead is paper, never amber (K5).
struct NookClosedChipsView: View {
    let chips: NookClosedChips

    var body: some View {
        HStack(spacing: NookClosedChips.gap) {
            chip(chips.deny)
            chip(chips.approve)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func chip(_ chip: NookClosedChip) -> some View {
        HStack(spacing: 5) {
            if let keys = chip.keys {
                Text(keys)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(chip.isPrimary ? V6Palette.ink : V6Palette.paper.opacity(0.66))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(chip.isPrimary ? V6Palette.paper : Color.white.opacity(0.1))
                    )
            }
            Text(chip.title)
                .font(.system(size: 11.5, weight: chip.isPrimary ? .bold : .medium, design: .rounded))
                .foregroundStyle(chip.isPrimary ? V6Palette.paper : V6Palette.paper.opacity(0.55))
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct NookTrailingWingView: View {
    let trailing: NookClosedActivity.Trailing
    var height: CGFloat
    var width: CGFloat
    /// False freezes the visualizer and the GIF while the pill is hidden.
    var isLive: Bool = true

    var body: some View {
        switch trailing {
        case let .media(activity):
            NookMediaSideView(activity: activity, height: height, width: width, isLive: isLive)
        case let .text(text):
            Text(text)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(V6Palette.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .frame(width: width, height: height, alignment: .trailing)
        case let .level(percent, tint):
            NookLevelRingView(percent: percent, tint: tint, size: min(height, NookLevelRingView.maxSize))
                .frame(width: width, height: height, alignment: .trailing)
        case let .chips(chips):
            NookClosedChipsView(chips: chips)
                .frame(width: width, height: height, alignment: .trailing)
        }
    }
}

/// A level as a ring that fills clockwise from the top, with the number
/// inside it.
struct NookLevelRingView: View {
    var percent: Int
    var tint: Color
    var size: CGFloat

    static let maxSize: CGFloat = 24
    static let lineWidth: CGFloat = 2.5
    /// The number's type size as a share of the ring's size, and how far
    /// it may shrink. The floor is what lets "100" fit an 18pt ring, the
    /// size on an external display's shorter pill.
    static let fontScale: CGFloat = 0.42
    static let minimumTextScale: CGFloat = 0.45
    private static let textInset: CGFloat = lineWidth / 2 + 1

    /// Width left for the number inside a ring of this size.
    static func textWidth(size: CGFloat) -> CGFloat {
        size - lineWidth - 2 * textInset
    }

    /// The level held to 0 through 100.
    static func clamped(_ percent: Int) -> Int { min(max(percent, 0), 100) }

    var body: some View {
        let level = Self.clamped(percent)
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: Self.lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(level) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(level)")
                .font(.system(size: size * Self.fontScale, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(V6Palette.paper)
                .lineLimit(1)
                .minimumScaleFactor(Self.minimumTextScale)
                .contentTransition(.numericText())
                .padding(.horizontal, Self.textInset)
        }
        .padding(Self.lineWidth / 2)
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(level) percent")
    }
}

// MARK: - Left slot

/// What one side of the closed island draws when the display's slot for
/// that side is set to something other than its usual content.
enum NookSideSlotContent: Equatable {
    case bars(UnifiedBars.Mode)
    /// The count badge or the agent grid, the same views the right slot uses.
    case agentSlot(IslandRightSlotContent)
    case date(Int)
    case battery(percent: Int, isCharging: Bool)
    case countdown(String)
    /// The temperature, such as "72°", over a small weather symbol.
    case weather(text: String, symbol: String)
    /// Time left on the focus timer, in the short form.
    case timer(String)
    /// How many tasks are still open.
    case todos(Int)
    /// A paper dot and a few words that stay up, such as "Update ready"
    /// or "1.0.14 · what's new" (D82). The wing widens to fit them.
    case notice(String)
    case hidden

    /// "42m", "3h" or "2d" until a moment; nil once it has passed.
    static func countdownText(to date: Date, now: Date) -> String? {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }

    /// A report older than this says nothing: the Weather widget only asks
    /// for a new one while its tile is on screen, and the pill asks for none.
    static let weatherMaxAge: TimeInterval = 6 * 3600

    /// The temperature now from the saved report, nil with no city, no
    /// report, or a report too old to trust.
    static func resolvedWeather(
        report: NookWeatherReport?,
        hasPlace: Bool,
        unit: NookTemperatureUnit,
        now: Date
    ) -> NookSideSlotContent? {
        guard hasPlace, let report, now.timeIntervalSince(report.fetchedAt) < weatherMaxAge else { return nil }
        let moment = report.conditions(at: now)
        return .weather(
            text: unit.text(celsius: moment.temperature),
            symbol: moment.condition.symbol(isDay: moment.isDay)
        )
    }

    /// "45s", "24m" or "2h" for time left on the timer, rounded up like the
    /// countdown. Nil with no timer running.
    static func timerText(remaining: TimeInterval, isActive: Bool) -> String? {
        guard isActive, remaining > 0 else { return nil }
        if remaining <= 60 { return "\(Int(remaining.rounded(.up)))s" }
        let minutes = Int((remaining / 60).rounded(.up))
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h"
    }

    /// The open-task count, nil while the source is not connected or has
    /// nothing open.
    static func resolvedTodos(items: [NookTodoItem], connection: NookTodoConnection) -> NookSideSlotContent? {
        resolvedTodos(items: items, isReady: connection == .ready)
    }

    /// The same count for the merged list of every app that is on, ready
    /// when any of them is connected.
    static func resolvedTodos(items: [NookTodoItem], isReady: Bool) -> NookSideSlotContent? {
        guard isReady else { return nil }
        let open = items.filter { !$0.isCompleted }.count
        return open > 0 ? .todos(open) : nil
    }

    static let todosCap = 99

    /// The count as drawn: "7", or "99+" past the cap.
    static func todosText(_ count: Int) -> String {
        count > todosCap ? "\(todosCap)+" : "\(count)"
    }
}

struct NookSideSlotView: View {
    let content: NookSideSlotContent
    var size: CGFloat = 24
    /// False freezes the bars and the agent grid's pulse while the pill is
    /// hidden.
    var isLive: Bool = true

    private static let lowBattery = 20

    /// Width the pill reserves; the grid and a long count can pass `size`.
    static func width(of content: NookSideSlotContent, size: CGFloat = 24) -> CGFloat {
        switch content {
        case let .agentSlot(slot):
            return max(size, V6RightSlotView.intrinsicWidth(of: slot))
        case let .notice(text):
            return Self.noticeDot + Self.noticeGap + NookWingText.width(of: text)
        default:
            return size
        }
    }

    static let noticeDot: CGFloat = 6
    static let noticeGap: CGFloat = 6

    var body: some View {
        switch content {
        case let .bars(mode):
            UnifiedBars(mode: mode, size: size, isPaused: !isLive)
        case let .agentSlot(slot):
            V6RightSlotView(content: slot, isLive: isLive)
                .frame(width: Self.width(of: content, size: size), height: size)
        case let .date(day):
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.red)
                    .frame(height: size * 0.22)
                Text("\(day)")
                    .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .contentTransition(.numericText())
                    .frame(maxHeight: .infinity)
            }
            .frame(width: size * 0.82, height: size * 0.82)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
            .frame(width: size, height: size)
        case let .battery(percent, isCharging):
            Text("\(percent)")
                .font(.system(size: size * 0.46, weight: .bold, design: .monospaced))
                .foregroundStyle(isCharging ? Color.green : (percent <= Self.lowBattery ? Color.red : V6Palette.paper))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .frame(width: size, height: size)
        case let .countdown(text):
            Text(text)
                .font(.system(size: size * 0.44, weight: .semibold, design: .monospaced))
                .foregroundStyle(V6Palette.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .frame(width: size, height: size)
        case let .weather(text, symbol):
            stackedGlyph(symbol: symbol, text: text, tint: V6Palette.paper)
        case let .timer(text):
            stackedGlyph(symbol: "timer", text: text, tint: .orange)
        case let .todos(count):
            stackedGlyph(symbol: "checkmark.circle", text: NookSideSlotContent.todosText(count), tint: V6Palette.paper)
        case let .notice(text):
            HStack(spacing: Self.noticeGap) {
                Circle()
                    .fill(V6Palette.paper)
                    .frame(width: Self.noticeDot, height: Self.noticeDot)
                Text(text)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(V6Palette.paper)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(width: Self.width(of: content, size: size), height: size, alignment: .trailing)
        case .hidden:
            Color.clear.frame(width: size, height: size)
        }
    }

    /// A small symbol over a short text, in the square the other items use.
    private func stackedGlyph(symbol: String, text: String, tint: Color) -> some View {
        VStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(V6Palette.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .frame(width: size, height: size)
    }
}
