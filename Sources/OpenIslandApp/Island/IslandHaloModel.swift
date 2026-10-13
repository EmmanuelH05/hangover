import AppKit
import SwiftUI

/// An sRGB color in 0...1 that can cross actors and be compared, for the
/// halo pipeline (SwiftUI `Color` is neither reliably Equatable nor cheap to
/// convert on every render).
struct IslandHaloRGB: Equatable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    static func rgb255(_ red: Int, _ green: Int, _ blue: Int) -> IslandHaloRGB {
        IslandHaloRGB(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }

    /// "RRGGBB" or "#RRGGBB"; nil for anything else.
    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, digits.allSatisfy({ $0.isASCII && $0.isHexDigit }),
              let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// The sRGB components of a SwiftUI color; nil when it cannot be
    /// converted (pattern or catalog colors with no sRGB form).
    init?(_ color: Color) {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(red: Double(srgb.redComponent), green: Double(srgb.greenComponent), blue: Double(srgb.blueComponent))
    }

    /// 0xRRGGBB, for tables of colors written in code.
    init(rgb value: UInt32) {
        self = .rgb255(Int((value >> 16) & 0xFF), Int((value >> 8) & 0xFF), Int(value & 0xFF))
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

    /// "RRGGBB". Components outside 0...1 are clamped.
    var hex: String {
        func byte(_ component: Double) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    /// The nearest color that "RRGGBB" can hold. A color picked in a color
    /// well is rounded to this before it is kept, which makes the color in
    /// memory and the color read back after a relaunch the same.
    var quantized: IslandHaloRGB {
        IslandHaloRGB(hex: hex) ?? self
    }

    // The standard status colors, from IslandDesignPalette. Approval uses
    // the aggregate orange, not the palette's pink, which reads better as a
    // glow. The user's own colors live in `IslandHaloPalette`.
    static let approval = rgb255(231, 167, 98)
    static let question = rgb255(255, 213, 138)
    static let completed = rgb255(111, 185, 130)
    static let running = rgb255(110, 167, 255)
}

/// How strong the halo is on one display. Stored per display profile.
enum IslandHaloStyle: String, CaseIterable, Identifiable, Sendable {
    case off
    case subtle
    case vivid

    var id: String { rawValue }
}

/// What the system allows the halo to do right now.
struct IslandMotionPolicy: Equatable, Sendable {
    /// False turns breathing and drift into a steady glow and the flash into
    /// a single fade (Reduce Motion).
    var animates: Bool
    /// The long-running glows: agent running and music.
    var allowsAmbient: Bool
    /// Only a steady glow while an agent waits (critical thermal state).
    var waitingOnly: Bool
    /// Blur effects in transitions.
    var allowsBlur: Bool

    static let full = IslandMotionPolicy(animates: true, allowsAmbient: true, waitingOnly: false, allowsBlur: true)
    /// Reduce Motion on.
    static let reduced = IslandMotionPolicy(animates: false, allowsAmbient: true, waitingOnly: false, allowsBlur: false)
    /// Low Power Mode or a serious thermal state.
    static let conserving = IslandMotionPolicy(animates: false, allowsAmbient: false, waitingOnly: false, allowsBlur: false)
    /// Critical thermal state.
    static let minimal = IslandMotionPolicy(animates: false, allowsAmbient: false, waitingOnly: true, allowsBlur: false)

    /// Thermal critical gives `.minimal`; Low Power Mode or thermal serious
    /// gives `.conserving`; Reduce Motion gives `.reduced`; otherwise `.full`.
    static func resolve(reduceMotion: Bool, lowPower: Bool, thermal: ProcessInfo.ThermalState) -> IslandMotionPolicy {
        if thermal == .critical { return .minimal }
        if lowPower || thermal == .serious { return .conserving }
        if reduceMotion { return .reduced }
        return .full
    }

    /// `OPEN_ISLAND_MOTION_POLICY=full|reduced|conserving|minimal`, for
    /// harness runs. Nil when unset or not one of those four.
    static func override(from environment: [String: String]) -> IslandMotionPolicy? {
        guard let raw = environment["OPEN_ISLAND_MOTION_POLICY"] else { return nil }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "full": return .full
        case "reduced": return .reduced
        case "conserving": return .conserving
        case "minimal": return .minimal
        default: return nil
        }
    }
}

/// Which moment the halo is showing.
enum IslandHaloSource: String, Equatable, Sendable {
    case approval
    case question
    case completed
    case notice
    case music
    case running
}

/// How the halo moves.
enum IslandHaloMotion: Equatable, Sendable {
    case none
    case steady
    /// Opacity breathes between `low` and `high` of the state's color.
    case breathing(period: TimeInterval, low: Double, high: Double)
    /// One rise to `peak` and fade out. A new token restarts it.
    case flash(token: UInt64, peak: Double, duration: TimeInterval)
    /// A very slow, shallow opacity drift around `restOpacity`.
    case drift(period: TimeInterval)
    /// Follows the song's bass and steps its color on the beat (D56).
    case pulse(IslandHaloPulse)
}

/// What a pulsing glow moves between (D56).
struct IslandHaloPulse: Equatable, Sendable {
    /// The opacity with no bass at all.
    var low: Double
    /// The opacity at the top of a beat.
    var high: Double
    /// The colors the beat steps through, in order. Never empty.
    var hues: [IslandHaloRGB]
    /// How far the peak goes out, 0 to 1 (`IslandBeatReach`).
    var reach = IslandBeatReach.standard
    /// How the beat is drawn: the glow itself, or beams over a faint glow.
    var look = IslandBeatLook.glow
    /// How far the lasers reach, 0 to 1 (`IslandLaserReach`). The lasers
    /// have their own: their range is far longer than the glow's.
    var laserReach = IslandLaserReach.standard
    /// How many beams the lasers have (`IslandLaserCount`).
    var laserCount = IslandLaserCount.standard
    /// How the lasers follow the song: each hit for itself, or a show.
    var laserMode = IslandLaserMode.reactive
    /// The number the song's show is made from. It is 0 unless the
    /// lasers run a show: nothing else is to change with the track.
    var laserSeed: UInt64 = 0
    /// The music color the hues were spread around, nil for art with none.
    /// The lasers spread their own colors around the same one.
    var tint: IslandHaloRGB?
}

/// Everything the halo renderer needs. One color at a time.
struct IslandHaloState: Equatable, Sendable {
    var source: IslandHaloSource?
    var color: IslandHaloRGB
    var motion: IslandHaloMotion
    /// Opacity the layer stores at rest (and shows in screenshots).
    var restOpacity: Double
    var radius: CGFloat
    /// How far the glow sits below the pill.
    var drop: CGFloat

    static let off = IslandHaloState(source: nil, color: .running, motion: .none, restOpacity: 0, radius: 0, drop: 0)

    var isVisible: Bool { source != nil && motion != .none }
}

enum IslandWaitingKind: Equatable, Sendable {
    case approval
    case question
}

/// The facts the resolver chooses from.
struct IslandHaloInputs: Equatable, Sendable {
    var style: IslandHaloStyle
    var policy: IslandMotionPolicy
    var isOpened: Bool
    var waiting: IslandWaitingKind?
    var flashToken: UInt64?
    var noticeTint: IslandHaloRGB?
    /// The album art's color while the music glow is wanted. Nil when the
    /// art has no clear color, and when no music glow is wanted.
    var musicTint: IslandHaloRGB?
    var isRunning: Bool
    /// The color for each moment (D31).
    var palette = IslandHaloPalette.standard
    /// The music glow is wanted even when the art gave no color: the
    /// palette's own music color can stand in for it.
    var isMusicPlaying = false
    /// The listener is running, which makes the music glow a pulse (D56).
    var pulsesWithBeat = false
    /// How far the pulse goes out, 0 to 1.
    var pulseReach = IslandBeatReach.standard
    /// The look the user chose for the pulse.
    var pulseLook = IslandBeatLook.glow
    /// How far the lasers reach, 0 to 1.
    var pulseLaserReach = IslandLaserReach.standard
    /// How many beams the lasers have.
    var pulseLaserCount = IslandLaserCount.standard
    /// How the lasers follow the song, and the song's seed for a show.
    var pulseLaserMode = IslandLaserMode.reactive
    var pulseLaserSeed: UInt64 = 0
}

/// Sizes and opacities per style.
struct IslandHaloMetrics: Equatable, Sendable {
    var radius: CGFloat
    var drop: CGFloat
    var breathingLow: Double
    var breathingHigh: Double
    var flashPeak: Double
    var noticeOpacity: Double
    var musicOpacity: Double
    var runningOpacity: Double
    /// What a pulsing music glow moves between (D56). Zero where it never
    /// pulses.
    var pulseLow: Double = 0
    var pulseHigh: Double = 0

    static let subtle = IslandHaloMetrics(
        radius: 12, drop: 3, breathingLow: 0.5, breathingHigh: 0.95,
        flashPeak: 1.0, noticeOpacity: 0.85, musicOpacity: 0.45, runningOpacity: 0.42,
        pulseLow: 0.25, pulseHigh: 0.85
    )
    static let vivid = IslandHaloMetrics(
        radius: 18, drop: 5, breathingLow: 0.7, breathingHigh: 1.0,
        flashPeak: 1.0, noticeOpacity: 1.0, musicOpacity: 0.65, runningOpacity: 0.6,
        pulseLow: 0.35, pulseHigh: 1.0
    )
    /// While the island is open only a flash shows, sized to fit the
    /// window's transparent insets (18pt sides, 22pt bottom).
    static let opened = IslandHaloMetrics(
        radius: 7, drop: 3, breathingLow: 0, breathingHigh: 0,
        flashPeak: 0.85, noticeOpacity: 0, musicOpacity: 0, runningOpacity: 0
    )

    static func metrics(for style: IslandHaloStyle) -> IslandHaloMetrics {
        style == .vivid ? .vivid : .subtle
    }
}

extension IslandHaloState {
    /// Chooses the one halo to show, in the D16 priority order: style off,
    /// island opened (a flash only), approval, question, completion flash,
    /// notice, music, running, idle. Colors come from the inputs' palette
    /// (D31). Pure: equal inputs give an equal state.
    static func resolve(_ inputs: IslandHaloInputs) -> IslandHaloState {
        guard inputs.style != .off else { return .off }
        if inputs.isOpened { return openedState(inputs) }

        let metrics = IslandHaloMetrics.metrics(for: inputs.style)
        let policy = inputs.policy

        let palette = inputs.palette

        if policy.waitingOnly { return waitingOnlyState(inputs.waiting, palette: palette, metrics: metrics) }
        if let waiting = inputs.waiting {
            return waitingState(waiting, palette: palette, metrics: metrics, policy: policy)
        }
        if let token = inputs.flashToken { return flashState(token: token, color: palette.completed, metrics: metrics) }
        if let tint = inputs.noticeTint {
            return IslandHaloState(
                source: .notice,
                color: palette.noticeColor(own: tint),
                motion: .steady,
                restOpacity: metrics.noticeOpacity,
                metrics: metrics
            )
        }
        // Everything below is a long-running glow; Low Power and thermal
        // pressure turn it off.
        guard policy.allowsAmbient else { return .off }
        if inputs.pulsesWithBeat, inputs.isMusicPlaying, policy.animates {
            return pulseState(
                around: palette.musicColor(artwork: inputs.musicTint),
                reach: inputs.pulseReach,
                look: inputs.pulseLook,
                laserReach: inputs.pulseLaserReach,
                laserCount: inputs.pulseLaserCount,
                laserMode: inputs.pulseLaserMode,
                laserSeed: inputs.pulseLaserSeed,
                metrics: metrics
            )
        }
        if inputs.isMusicPlaying || inputs.musicTint != nil, let tint = palette.musicColor(artwork: inputs.musicTint) {
            return ambientState(source: .music, color: tint, restOpacity: metrics.musicOpacity, metrics: metrics, policy: policy)
        }
        if inputs.isRunning {
            return ambientState(
                source: .running,
                color: palette.running,
                restOpacity: metrics.runningOpacity,
                metrics: metrics,
                policy: policy
            )
        }
        return .off
    }

    /// `OPEN_ISLAND_HALO=approval|question|flash|running|notice:RRGGBB|music:RRGGBB|off`
    /// for harness screenshots. Returns nil when the variable is unset or its
    /// value is not recognized (including a bad hex color). The state goes
    /// through `resolve`, so it follows the metrics and the motion policy:
    /// Subtle metrics unless `OPEN_ISLAND_HALO_STYLE=vivid`, and
    /// `IslandMotionPolicy.full` unless `OPEN_ISLAND_MOTION_POLICY` says
    /// otherwise. The colors are the standard ones unless
    /// `OPEN_ISLAND_HALO_THEME` names a theme by its id.
    static func forced(from environment: [String: String]) -> IslandHaloState? {
        guard let raw = environment["OPEN_ISLAND_HALO"] else { return nil }
        let parts = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard let head = parts.first else { return nil }
        let key = head.trimmingCharacters(in: .whitespaces).lowercased()
        let argument = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil

        let isVivid = environment["OPEN_ISLAND_HALO_STYLE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "vivid"
        let style: IslandHaloStyle = isVivid ? .vivid : .subtle
        var inputs = IslandHaloInputs(
            style: style,
            policy: IslandMotionPolicy.override(from: environment) ?? .full,
            isOpened: false,
            waiting: nil,
            flashToken: nil,
            noticeTint: nil,
            musicTint: nil,
            isRunning: false,
            palette: environment["OPEN_ISLAND_HALO_THEME"]
                .flatMap { IslandHaloTheme.theme(id: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }?
                .palette ?? .standard
        )

        switch (key, argument) {
        case ("off", nil):
            return .off
        case ("approval", nil):
            inputs.waiting = .approval
        case ("question", nil):
            inputs.waiting = .question
        case ("running", nil):
            inputs.isRunning = true
        case ("flash", nil):
            inputs.flashToken = 1
            // A real flash fades to nothing; hold it at its peak so a
            // screenshot taken at any moment shows it.
            var held = resolve(inputs)
            if case .flash(_, let peak, _) = held.motion { held.restOpacity = peak }
            return held
        case ("notice", let hex?):
            guard let tint = IslandHaloRGB(hex: hex) else { return nil }
            inputs.noticeTint = tint
        case ("music", let hex?):
            guard let tint = IslandHaloRGB(hex: hex) else { return nil }
            inputs.musicTint = tint
        default:
            return nil
        }
        return resolve(inputs)
    }

    // MARK: Building blocks

    fileprivate init(
        source: IslandHaloSource,
        color: IslandHaloRGB,
        motion: IslandHaloMotion,
        restOpacity: Double,
        metrics: IslandHaloMetrics
    ) {
        self.init(
            source: source,
            color: color,
            motion: motion,
            restOpacity: restOpacity,
            radius: metrics.radius,
            drop: metrics.drop
        )
    }

    /// While the island is open only the completion flash shows, sized by
    /// the `.opened` metrics. Critical thermal state shows no flash.
    private static func openedState(_ inputs: IslandHaloInputs) -> IslandHaloState {
        guard !inputs.policy.waitingOnly, let token = inputs.flashToken else { return .off }
        return flashState(token: token, color: inputs.palette.completed, metrics: .opened)
    }

    /// Critical thermal state: a steady glow while an agent waits, nothing else.
    private static func waitingOnlyState(
        _ waiting: IslandWaitingKind?,
        palette: IslandHaloPalette,
        metrics: IslandHaloMetrics
    ) -> IslandHaloState {
        guard let waiting else { return .off }
        return IslandHaloState(
            source: waiting.haloSource,
            color: waiting.haloColor(in: palette),
            motion: .steady,
            restOpacity: metrics.breathingHigh,
            metrics: metrics
        )
    }

    /// Breathing between `low` and `high`; with Reduce Motion a steady glow
    /// at the midpoint.
    private static func waitingState(
        _ waiting: IslandWaitingKind,
        palette: IslandHaloPalette,
        metrics: IslandHaloMetrics,
        policy: IslandMotionPolicy
    ) -> IslandHaloState {
        let period = waiting == .approval ? Motion.Halo.approvalPeriod : Motion.Halo.questionPeriod
        let motion: IslandHaloMotion
        let restOpacity: Double
        if policy.animates {
            motion = .breathing(period: period, low: metrics.breathingLow, high: metrics.breathingHigh)
            restOpacity = metrics.breathingHigh
        } else {
            motion = .steady
            restOpacity = (metrics.breathingLow + metrics.breathingHigh) / 2
        }
        return IslandHaloState(
            source: waiting.haloSource,
            color: waiting.haloColor(in: palette),
            motion: motion,
            restOpacity: restOpacity,
            metrics: metrics
        )
    }

    /// The completion flash, green in the standard palette. It stays a
    /// flash under every policy; the renderer shortens it to one fade when
    /// motion is reduced.
    private static func flashState(token: UInt64, color: IslandHaloRGB, metrics: IslandHaloMetrics) -> IslandHaloState {
        IslandHaloState(
            source: .completed,
            color: color,
            motion: .flash(token: token, peak: metrics.flashPeak, duration: Motion.Halo.flash),
            restOpacity: 0,
            metrics: metrics
        )
    }

    /// Music while the listener runs (D56): the glow rests low, follows the
    /// bass up and steps through four colors around the art's own. Art
    /// with no color still glows, in the fixed four.
    private static func pulseState(
        around tint: IslandHaloRGB?,
        reach: Double,
        look: IslandBeatLook,
        laserReach: Double,
        laserCount: Int,
        laserMode: IslandLaserMode,
        laserSeed: UInt64,
        metrics: IslandHaloMetrics
    ) -> IslandHaloState {
        let hues = IslandBeatHues.hues(around: tint)
        let pulse = IslandHaloPulse(
            low: metrics.pulseLow, high: metrics.pulseHigh, hues: hues,
            reach: IslandBeatReach.clamped(reach), look: look,
            laserReach: IslandLaserReach.clamped(laserReach),
            laserCount: IslandLaserCount.clamped(laserCount),
            laserMode: look == .lasers ? laserMode : .reactive,
            laserSeed: look == .lasers && laserMode == .show ? laserSeed : 0, tint: tint
        )
        return IslandHaloState(
            source: .music,
            color: hues[0],
            motion: .pulse(pulse),
            restOpacity: metrics.pulseLow,
            metrics: metrics
        )
    }

    /// Music and running: a slow drift, or steady when motion is reduced.
    private static func ambientState(
        source: IslandHaloSource,
        color: IslandHaloRGB,
        restOpacity: Double,
        metrics: IslandHaloMetrics,
        policy: IslandMotionPolicy
    ) -> IslandHaloState {
        IslandHaloState(
            source: source,
            color: color,
            motion: policy.animates ? .drift(period: Motion.Halo.driftPeriod) : .steady,
            restOpacity: restOpacity,
            metrics: metrics
        )
    }
}

private extension IslandWaitingKind {
    var haloSource: IslandHaloSource {
        switch self {
        case .approval: .approval
        case .question: .question
        }
    }

    func haloColor(in palette: IslandHaloPalette) -> IslandHaloRGB {
        switch self {
        case .approval: palette.approval
        case .question: palette.question
        }
    }
}
