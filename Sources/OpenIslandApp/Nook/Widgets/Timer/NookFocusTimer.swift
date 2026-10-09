import AppKit
import Foundation
import Observation

/// Focus countdown. Remaining time is computed from an end date so it
/// stays accurate however late the tick fires. It runs either one plain
/// countdown or a pomodoro: work and break rounds, one after the other,
/// until it is stopped (`NookPomodoroState` holds the round rules).
@MainActor
@Observable
final class NookFocusTimer {
    @ObservationIgnored private(set) weak var nook: NookModel?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var endDate: Date?
    @ObservationIgnored private let defaults: UserDefaults

    private static let presetKey = "nook.timer.preset"
    private static let soundKey = "nook.timer.soundEnabled"
    static let defaultPreset: TimeInterval = 25 * 60
    /// Typed lengths run from a second to a day (`NookTimerEntry`).
    static let minPreset: TimeInterval = NookTimerEntry.minimum
    static let maxPreset: TimeInterval = NookTimerEntry.maximum

    private(set) var remaining: TimeInterval
    private(set) var isRunning = false
    private(set) var preset: TimeInterval
    /// True once started and not yet reset or finished (running or paused).
    private(set) var isActive = false
    /// Total length of the current one-off countdown, nil for preset runs.
    private(set) var oneOffTotal: TimeInterval?
    /// Where the pomodoro run stands, nil for a plain countdown.
    private(set) var pomodoro: NookPomodoroState?
    /// The saved round and break lengths.
    private(set) var pomodoroPlan: NookPomodoroPlan

    /// True during a pomodoro break. Agent completion cards come through
    /// then, the way they do with no timer running.
    var isOnBreak: Bool { pomodoro?.phase.isBreak ?? false }

    var soundEnabled: Bool {
        get {
            access(keyPath: \.soundEnabled)
            return defaults.object(forKey: Self.soundKey) as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.soundEnabled) {
                defaults.set(newValue, forKey: Self.soundKey)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.double(forKey: Self.presetKey)
        let value = (Self.minPreset...Self.maxPreset).contains(stored) ? stored : Self.defaultPreset
        preset = value
        remaining = value
        pomodoroPlan = NookPomodoroPlan.load(from: defaults)
    }

    func start(nook: NookModel) {
        self.nook = nook
    }

    /// "24:59" while running or paused with time left, nil when idle.
    var closedText: String? {
        guard isActive, remaining > 0 else { return nil }
        return Self.format(remaining)
    }

    /// 0...1 share of the current countdown that has elapsed.
    var progress: Double {
        let total = oneOffTotal ?? preset
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / total))
    }

    /// Starts a one-off countdown ending at `date`, leaving the preset alone.
    /// Ignored when `date` is under a minute away or a countdown is active.
    func start(until date: Date) {
        guard !isActive else { return }
        let length = date.timeIntervalSinceNow
        guard length >= 60 else { return }
        oneOffTotal = length
        remaining = length
        start()
        endDate = date
    }

    /// First timed event starting more than a minute from `now` and within `maxLead`.
    static func nextEventTarget(
        events: [NookCalendarEvent],
        now: Date,
        maxLead: TimeInterval = 4 * 60 * 60
    ) -> NookCalendarEvent? {
        events
            .filter { event in
                let lead = event.start.timeIntervalSince(now)
                return !event.isAllDay && lead > 60 && lead <= maxLead
            }
            .min { $0.start < $1.start }
    }

    /// Starts a one-off countdown of `length`, in place of whatever was
    /// up, and leaves the preset alone. For a caller that names a length
    /// outright, the way a link from another app does.
    func start(length: TimeInterval) {
        let value = min(max(Self.minPreset, length), Self.maxPreset)
        reset()
        oneOffTotal = value
        remaining = value
        start()
    }

    /// Starts a pomodoro run at its first work round, in place of whatever
    /// countdown was up.
    func startPomodoro() {
        stopTicker()
        begin(.first)
    }

    /// Ends the current round early and starts the next one. Does nothing
    /// to a plain countdown.
    func skipPomodoroPhase() {
        guard let state = pomodoro else { return }
        stopTicker()
        advance(from: state, playsSound: false)
    }

    /// Saves new round and break lengths. A round already counting down
    /// keeps the length it started with.
    func set(pomodoroPlan plan: NookPomodoroPlan) {
        let value = plan.clamped
        pomodoroPlan = value
        value.save(to: defaults)
    }

    func start() {
        guard !isRunning else { return }
        if remaining <= 0 { remaining = preset }
        endDate = Date().addingTimeInterval(remaining)
        isRunning = true
        isActive = true
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func pause() {
        guard isRunning else { return }
        if let endDate { remaining = max(0, endDate.timeIntervalSinceNow) }
        stopTicker()
    }

    /// Stops whatever is counting down, a pomodoro run included.
    func reset() {
        stopTicker()
        isActive = false
        oneOffTotal = nil
        pomodoro = nil
        remaining = preset
    }

    func set(preset newPreset: TimeInterval) {
        let value = min(max(Self.minPreset, newPreset), Self.maxPreset)
        preset = value
        defaults.set(value, forKey: Self.presetKey)
        if !isActive { remaining = value }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        endDate = nil
        isRunning = false
    }

    private func tick() {
        guard isRunning, let endDate else { return }
        let left = endDate.timeIntervalSinceNow
        if left > 0 {
            remaining = left
            return
        }
        finish()
    }

    private func begin(_ state: NookPomodoroState) {
        let length = pomodoroPlan.length(of: state.phase)
        pomodoro = state
        oneOffTotal = length
        remaining = length
        start()
    }

    /// Moves a pomodoro run to its next round and says what it is in the
    /// closed island, the way a finished timer does.
    private func advance(from state: NookPomodoroState, playsSound: Bool) {
        let next = state.next(rounds: pomodoroPlan.rounds)
        begin(next)
        if playsSound, soundEnabled { nook?.playSound("Glass") }
        nook?.showTransient(
            symbol: NookPomodoroLook.symbol(for: next),
            text: NookPomodoroLook.label(for: next, rounds: pomodoroPlan.rounds),
            tint: NookPomodoroLook.tint(for: next),
            duration: .seconds(6)
        )
    }

    private func finish() {
        stopTicker()
        if let state = pomodoro {
            advance(from: state, playsSound: true)
            return
        }
        isActive = false
        oneOffTotal = nil
        remaining = preset
        if soundEnabled { nook?.playSound("Glass") }
        nook?.showTransient(symbol: "timer", text: "Timer done", tint: .orange, duration: .seconds(6))
    }

    static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
