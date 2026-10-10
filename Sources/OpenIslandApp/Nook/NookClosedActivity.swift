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
    }

    enum Trailing: Equatable {
        case media(NookClosedMediaActivity)
        case text(String)
        /// A level from 0 to 100, drawn as a ring with the number in it.
        case level(percent: Int, tint: Color)
    }

    var leading: Leading
    /// Nil leaves the right side to the agents' own slot.
    var trailing: Trailing?
    var yieldsToAgents: Bool

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
        }
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
        guard connection == .ready else { return nil }
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
        if case let .agentSlot(slot) = content {
            return max(size, V6RightSlotView.intrinsicWidth(of: slot))
        }
        return size
    }

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
