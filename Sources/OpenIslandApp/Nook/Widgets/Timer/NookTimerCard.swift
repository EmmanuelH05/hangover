import SwiftUI

struct NookTimerCard: View {
    var nook: NookModel

    static let height: CGFloat = 96

    /// Height at each size. Small rows always use the grid’s shared height.
    static func height(for size: NookWidgetSize) -> CGFloat {
        switch size {
        case .small: NookWidgetLayout.smallHeight
        case .medium: height
        case .large: 160
        }
    }
    private static let chips = [15, 25, 50]
    private static let entryHint = "Type minutes or 1:30 · Return"
    private static let idleHint = "Type a number to set your own"

    @Environment(\.nookWidgetSize) private var size
    @State private var entry = NookTimerEntryState()
    @State private var keyMonitor = NookTimerKeyMonitor()

    private var timer: NookFocusTimer { nook.timer }

    var body: some View {
        Group {
            switch size {
            case .small: smallLayout
            case .medium: mediumLayout
            case .large: largeLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(NookCardBackground())
        .background(NookTimerWindowReader { keyMonitor.window = $0 })
        .onAppear(perform: installKeys)
        .onDisappear {
            keyMonitor.remove()
            entry.cancel()
        }
        .onChange(of: timer.isActive) { _, isActive in
            if isActive { entry.cancel() }
        }
    }

    // MARK: Layouts

    /// Time, progress and two icon buttons. No chips or until-event button.
    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                timeDisplay(fontSize: 26)
                Spacer(minLength: 0)
                if let round = timer.pomodoro {
                    // No room for words at this size: the round's number
                    // in a circle, or a cup for a break.
                    Image(systemName: NookPomodoroLook.symbol(for: round))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(NookPomodoroLook.tint(for: round))
                        .accessibilityLabel(NookPomodoroLook.label(for: round, rounds: timer.pomodoroPlan.rounds))
                }
            }
            Group {
                if entry.isActive {
                    hint(Self.entryHint)
                } else {
                    progressLine
                }
            }
            .frame(height: 12)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Button(action: toggle) {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                }
                .buttonStyle(NookTimerButtonStyle(prominent: true, width: nil))
                .accessibilityLabel(timer.isRunning ? "Pause" : "Start")
                Button(action: reset) {
                    Image(systemName: timer.pomodoro == nil ? "arrow.counterclockwise" : "stop.fill")
                }
                .buttonStyle(NookTimerButtonStyle(prominent: false, width: 40))
                .accessibilityLabel(resetTitle)
                if timer.pomodoro != nil {
                    Button(action: skip) {
                        Image(systemName: "forward.end.fill")
                    }
                    .buttonStyle(NookTimerButtonStyle(prominent: false, width: 40))
                    .help(lang.t("nook.timer.pomodoro.skip"))
                    .accessibilityLabel(lang.t("nook.timer.pomodoro.skip"))
                } else if !timer.isActive {
                    Button(action: startPomodoro) {
                        Image(systemName: "repeat")
                    }
                    .buttonStyle(NookTimerButtonStyle(prominent: false, width: 40))
                    .help(lang.t("nook.timer.pomodoro.help"))
                    .accessibilityLabel(lang.t("nook.timer.pomodoro"))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var mediumLayout: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                timeDisplay(fontSize: 28)
                progressLine
            }
            .frame(width: 96, alignment: .leading)

            VStack(spacing: 4) {
                if entry.isActive {
                    hint(Self.entryHint)
                } else if let round = timer.pomodoro {
                    roundStatus(round)
                } else {
                    chipRow
                    untilEventControl
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 6) {
                textControls
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                timeDisplay(fontSize: 40)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    textControls
                }
            }
            progressLine
            HStack(spacing: 8) {
                if let round = timer.pomodoro {
                    roundStatus(round)
                } else {
                    chipRow
                    untilEventControl
                }
                Spacer(minLength: 0)
            }
            hint(entry.isActive ? Self.entryHint : Self.idleHint)
                .opacity(entry.isActive || !timer.isActive ? 1 : 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: Time and entry

    /// The big time. While idle, clicking it opens the entry field.
    private func timeDisplay(fontSize: CGFloat) -> some View {
        timeContent(fontSize: fontSize)
            // Fixed height so the rows below stay put while the text scales.
            .frame(height: (fontSize * 1.3).rounded(.up), alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !timer.isActive, !entry.isActive else { return }
                // A focused text field would keep every key the caret asks for.
                keyMonitor.window?.makeFirstResponder(nil)
                entry.begin()
            }
    }

    @ViewBuilder
    private func timeContent(fontSize: CGFloat) -> some View {
        if let typed = entry.text {
            entryField(typed, fontSize: fontSize)
        } else {
            Text(NookFocusTimer.format(timer.remaining))
                .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
    }

    /// What was typed with an orange caret. Empty shows the current length
    /// dimmed. Red after a Return that could not be read.
    private func entryField(_ typed: String, fontSize: CGFloat) -> some View {
        let caret = Rectangle()
            .fill(Color.orange)
            .frame(width: 2, height: fontSize * 0.8)
        let shown = typed.isEmpty ? NookFocusTimer.format(timer.remaining) : typed
        let tint: Color = entry.isInvalid
            ? .red.opacity(typed.isEmpty ? 0.6 : 0.95)
            : .white.opacity(typed.isEmpty ? 0.35 : 0.85)
        return HStack(spacing: 2) {
            if typed.isEmpty { caret }
            Text(shown)
                .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            if !typed.isEmpty { caret }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.35))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    // MARK: Actions

    private func installKeys() {
        let timer = nook.timer
        let entry = entry
        let nook = nook
        keyMonitor.install(
            isEnabled: { !timer.isActive && !nook.isEditingLayout },
            isEntryActive: { entry.isActive },
            perform: { Self.apply($0, to: entry, timer: timer) }
        )
    }

    private static func apply(_ action: NookTimerKeyAction, to entry: NookTimerEntryState, timer: NookFocusTimer) {
        switch action {
        case .insert(let character):
            if entry.isActive { entry.append(character) } else { entry.begin(with: String(character)) }
        case .backspace:
            entry.deleteLast()
        case .submit:
            commit(entry, to: timer)
        case .cancel:
            entry.cancel()
        }
    }

    /// Valid input becomes the preset and starts. Invalid input stays red.
    private static func commit(_ entry: NookTimerEntryState, to timer: NookFocusTimer) {
        guard let length = entry.submit() else { return }
        timer.set(preset: length)
        timer.start()
    }

    /// Start runs what the clock shows: typed text if there is any.
    private func toggle() {
        if timer.isRunning {
            timer.pause()
            return
        }
        if entry.isActive, entry.text?.isEmpty == false {
            Self.commit(entry, to: timer)
            return
        }
        entry.cancel()
        timer.start()
    }

    private func reset() {
        entry.cancel()
        timer.reset()
    }

    private func startPomodoro() {
        guard !timer.isActive else { return }
        entry.cancel()
        timer.startPomodoro()
    }

    private func skip() {
        timer.skipPomodoroPhase()
    }

    private var lang: LanguageManager { .shared }

    /// Reset puts a plain countdown back to its length. A pomodoro has no
    /// length to go back to, which makes the same button Stop.
    private var resetTitle: String {
        timer.pomodoro == nil ? "Reset" : lang.t("nook.timer.pomodoro.stop")
    }

    // MARK: Controls

    @ViewBuilder
    private var textControls: some View {
        Button(timer.isRunning ? "Pause" : "Start", action: toggle)
            .buttonStyle(NookTimerButtonStyle(prominent: true, width: 56))
        Button(resetTitle, action: reset)
            .buttonStyle(NookTimerButtonStyle(prominent: false, width: 56))
    }

    private var chipRow: some View {
        HStack(spacing: 6) {
            ForEach(Self.chips, id: \.self) { minutes in
                chip(minutes)
            }
            pomodoroChip
        }
    }

    /// Starts a pomodoro run. Like the length chips it only acts while
    /// nothing is counting down.
    private var pomodoroChip: some View {
        Button(action: startPomodoro) {
            HStack(spacing: 4) {
                Image(systemName: "repeat")
                    .font(.system(size: 9, weight: .bold))
                Text(lang.t("nook.timer.pomodoro"))
                    .lineLimit(1)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(Color.white.opacity(0.07)))
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(.plain)
        .opacity(timer.isActive ? 0.4 : 1)
        .help(lang.t("nook.timer.pomodoro.help"))
    }

    /// What a pomodoro run is on: "Focus 2/4" or the break, a dot per
    /// round of the set, and Skip.
    private func roundStatus(_ round: NookPomodoroState) -> some View {
        let rounds = max(timer.pomodoroPlan.rounds, round.round)
        let tint = NookPomodoroLook.tint(for: round)
        return HStack(spacing: 8) {
            Text(NookPomodoroLook.label(for: round, rounds: rounds))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .fixedSize()
            HStack(spacing: 3) {
                ForEach(1...rounds, id: \.self) { index in
                    Circle()
                        .fill(Self.dotFill(index: index, round: round, tint: tint))
                        .frame(width: 5, height: 5)
                }
            }
            .accessibilityHidden(true)
            Button(lang.t("nook.timer.pomodoro.skip"), action: skip)
                .buttonStyle(NookTimerButtonStyle(prominent: false, width: 48))
        }
    }

    /// Finished rounds are solid, the round being worked on takes the
    /// tint, and the ones still ahead are dim.
    private static func dotFill(index: Int, round: NookPomodoroState, tint: Color) -> Color {
        let isDone = index < round.round || (index == round.round && round.phase.isBreak)
        if isDone { return .white.opacity(0.7) }
        return index == round.round ? tint : .white.opacity(0.15)
    }

    @ViewBuilder
    private var untilEventControl: some View {
        if !timer.isActive {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if let event = NookFocusTimer.nextEventTarget(events: nook.upcomingEvents, now: context.date) {
                    Button {
                        entry.cancel()
                        timer.start(until: event.start)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                            Text(Self.untilLabel(event, now: context.date))
                                .lineLimit(1)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(height: 20)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private static func untilLabel(_ event: NookCalendarEvent, now: Date) -> String {
        let title = event.title.count > 14 ? String(event.title.prefix(14)) + "…" : event.title
        let minutes = max(1, Int((event.start.timeIntervalSince(now) / 60).rounded(.up)))
        let span = minutes >= 60
            ? (minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m")
            : "\(minutes) min"
        return "Until \(title) · \(span)"
    }

    private var progressLine: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(NookPomodoroLook.tint(for: timer.pomodoro))
                    .frame(width: proxy.size.width * timer.progress)
            }
        }
        .frame(height: 3)
    }

    private func chip(_ minutes: Int) -> some View {
        let selected = timer.preset == TimeInterval(minutes * 60)
        return Button("\(minutes)") {
            guard !timer.isActive else { return }
            entry.cancel()
            timer.set(preset: TimeInterval(minutes * 60))
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .foregroundStyle(.white.opacity(selected ? 0.85 : 0.6))
        .frame(width: 34, height: 24)
        .background(Capsule().fill(Color.white.opacity(selected ? 0.18 : 0.07)))
        .opacity(timer.isActive && !selected ? 0.4 : 1)
    }
}

/// A 24pt capsule button. `width` nil fills the space it is given.
private struct NookTimerButtonStyle: ButtonStyle {
    let prominent: Bool
    let width: CGFloat?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(prominent ? Color.black.opacity(0.85) : .white.opacity(0.6))
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(width: width, height: 24)
            .background(
                Capsule().fill(prominent ? Color.orange : Color.white.opacity(0.09))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
