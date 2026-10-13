import Foundation
import MediaAccessibility

/// Whether the user asked macOS to dim flashing lights (D56). The system's
/// own is in Settings, Accessibility, Display. A test hands in a fake.
@MainActor
protocol IslandFlashingLightsSetting: AnyObject {
    var dimsFlashingLights: Bool { get }
}

/// How often the beat glow may flash, as plain values (D56).
///
/// By the owner's decision the flashes follow the hits: a kick, a snare
/// and a clap may each flash, and the only gap is the one that keeps a
/// fast roll reading as hits. A user who asked macOS to dim flashing
/// lights gets the old limit: no more than three full flashes in any one
/// second. Reduce Motion goes further and turns the pulse off altogether,
/// through the motion policy.
struct IslandFlashRule: Equatable, Sendable {
    /// The least time between two full flashes.
    var gap: TimeInterval
    /// The most full flashes in any one second, and nil for no such limit.
    var mostASecond: Int?

    static let followsHits = IslandFlashRule(gap: IslandBeatLimits.flashGap, mostASecond: nil)
    static let dimmed = IslandFlashRule(
        gap: IslandBeatLimits.dimmedFlashGap, mostASecond: IslandBeatLimits.dimmedFlashesPerSecond
    )

    static func rule(dimsFlashingLights: Bool) -> IslandFlashRule {
        dimsFlashingLights ? .dimmed : .followsHits
    }

    /// Whether a flash may be shown at `time`. `earlier` holds the times of
    /// the flashes shown in the second before, oldest first.
    func allows(at time: TimeInterval, after earlier: [TimeInterval]) -> Bool {
        if let last = earlier.last, time - last < gap { return false }
        guard let mostASecond else { return true }
        return earlier.filter { time - $0 < 1 }.count < mostASecond
    }
}

/// The system's "Dim flashing lights" setting, read once and again when
/// macOS says it changed (`MADimFlashingLightsEnabled`, macOS 13.3).
@MainActor
final class SystemFlashingLightsSetting: IslandFlashingLightsSetting {
    static let shared = SystemFlashingLightsSetting()

    private(set) var dimsFlashingLights: Bool
    private var observer: (any NSObjectProtocol)?

    private init() {
        dimsFlashingLights = MADimFlashingLightsEnabled()
        // The notice is posted to the local center, which is the one
        // `NotificationCenter.default` reads.
        observer = NotificationCenter.default.addObserver(
            forName: Notification.Name(kMADimFlashingLightsChangedNotification as String), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dimsFlashingLights = MADimFlashingLightsEnabled() }
        }
    }
}
