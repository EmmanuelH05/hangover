import Foundation

/// The current output's volume as CoreAudio reports it.
struct NookVolumeReading: Equatable, Sendable {
    var deviceID: UInt32
    /// From 0 to 1. Nil for an output with no volume of its own.
    var volume: Float?
    var isMuted: Bool
}

/// What a volume notice in the closed notch says.
struct NookVolumeNoticeContent: Equatable, Sendable {
    var symbol: String
    /// Nil while muted, and for an output with no volume of its own.
    var percent: Int?
    var isMuted: Bool
}

/// Pure rules for the volume notice.
enum NookVolumeNotice {
    static func percent(_ volume: Float) -> Int {
        Int((min(max(volume, 0), 1) * 100).rounded())
    }

    static func symbol(percent: Int?, isMuted: Bool) -> String {
        guard !isMuted, let percent else { return "speaker.slash.fill" }
        switch percent {
        case ..<1: return "speaker.fill"
        case ..<34: return "speaker.wave.1.fill"
        case ..<67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    /// The notice for a change from `old` to `new`, or nil when there is
    /// nothing to say: the first reading after launch, another output
    /// taking over (the headphones notice covers that), or a change too
    /// small to show.
    static func content(from old: NookVolumeReading?, to new: NookVolumeReading) -> NookVolumeNoticeContent? {
        guard let old, old.deviceID == new.deviceID else { return nil }
        let oldPercent = old.volume.map(percent)
        let newPercent = new.volume.map(percent)
        guard oldPercent != newPercent || old.isMuted != new.isMuted else { return nil }
        return content(for: new)
    }

    /// The notice for the level as it stands, changed or not. A volume key
    /// the app kept from macOS always gets one: at the top or the bottom of
    /// the range nothing changes, and the press must still be seen.
    static func content(for reading: NookVolumeReading) -> NookVolumeNoticeContent {
        let shown = reading.isMuted ? nil : reading.volume.map(percent)
        return NookVolumeNoticeContent(
            symbol: symbol(percent: shown, isMuted: reading.isMuted),
            percent: shown,
            isMuted: reading.isMuted
        )
    }
}

/// A media key the app can take over from macOS.
enum NookMediaKey: Equatable, Sendable {
    case volumeUp
    case volumeDown
    case mute
    case brightnessUp
    case brightnessDown

    /// The key codes macOS sends in its system-defined key events.
    init?(keyCode: Int) {
        switch keyCode {
        case 0: self = .volumeUp
        case 1: self = .volumeDown
        case 7: self = .mute
        case 2: self = .brightnessUp
        case 3: self = .brightnessDown
        default: return nil
        }
    }

    var isBrightness: Bool { self == .brightnessUp || self == .brightnessDown }
}

/// The modifier keys held with a media key.
struct NookMediaKeyModifiers: Equatable, Sendable {
    var shift = false
    var option = false
    var control = false
    var command = false
}

/// Pure rules for the volume and brightness keys.
enum NookMediaKeyRules {
    /// macOS moves volume and brightness in sixteen steps, and in quarter
    /// steps with Shift and Option held.
    static let steps: Float = 16
    static let fineSteps: Float = 64

    static func isFine(_ modifiers: NookMediaKeyModifiers) -> Bool {
        modifiers.shift && modifiers.option
    }

    /// Key presses macOS gives another meaning stay with macOS: Option
    /// opens the Sound or Displays settings, Control moves an external
    /// display's brightness, and Command is never part of these keys.
    static func staysWithSystem(_ modifiers: NookMediaKeyModifiers) -> Bool {
        if modifiers.command || modifiers.control { return true }
        return modifiers.option && !modifiers.shift
    }

    /// A key event older than this was held up on its way to the app. By
    /// then macOS has stopped waiting and handled the key itself.
    static let staleAfter: TimeInterval = 0.5

    /// True for an event that waited too long to be acted on. Both times
    /// are seconds since the Mac started, which is what an event is stamped
    /// with. An event with no stamp, or one from ahead of the clock, is not
    /// stale.
    static func isStale(eventUptime: TimeInterval, nowUptime: TimeInterval) -> Bool {
        guard eventUptime > 0, nowUptime > eventUptime else { return false }
        return nowUptime - eventUptime > staleAfter
    }

    /// `value` moved one step along the grid, kept between 0 and 1.
    static func stepped(_ value: Float, up: Bool, fine: Bool) -> Float {
        let grid = fine ? fineSteps : steps
        let current = (min(max(value, 0), 1) * grid).rounded()
        return min(max(current + (up ? 1 : -1), 0), grid) / grid
    }

    /// What a volume key does to the output. Nil fields stay as they are.
    struct VolumeChange: Equatable, Sendable {
        var volume: Float?
        var isMuted: Bool?
    }

    /// The change for a volume key, or nil when the key should go to macOS:
    /// a brightness key, or an output with no volume of its own.
    static func volumeChange(
        for key: NookMediaKey,
        reading: NookVolumeReading,
        fine: Bool
    ) -> VolumeChange? {
        switch key {
        case .mute:
            return VolumeChange(volume: nil, isMuted: !reading.isMuted)
        case .volumeUp, .volumeDown:
            guard let volume = reading.volume else { return nil }
            // A volume key also ends mute, the way macOS does it.
            return VolumeChange(
                volume: stepped(volume, up: key == .volumeUp, fine: fine),
                isMuted: reading.isMuted ? false : nil
            )
        case .brightnessUp, .brightnessDown:
            return nil
        }
    }
}
