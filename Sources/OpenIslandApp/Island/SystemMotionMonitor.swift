import AppKit
import Foundation
import Observation

/// Watches Reduce Motion, Low Power Mode and the thermal state and exposes
/// the resulting `IslandMotionPolicy`. `OPEN_ISLAND_MOTION_POLICY` overrides
/// `policy` for harness runs; the observed values stay the real ones.
@MainActor
@Observable
final class SystemMotionMonitor {
    static let shared = SystemMotionMonitor()

    private(set) var reduceMotion = false
    private(set) var lowPower = false
    private(set) var thermal: ProcessInfo.ThermalState = .nominal

    @ObservationIgnored private let policyOverride: IslandMotionPolicy?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var hasStarted = false

    /// How many system notifications `start()` is listening to. Zero before
    /// `start()`, and unchanged by calling it again.
    var observerCount: Int { observers.count }

    var policy: IslandMotionPolicy {
        policyOverride ?? IslandMotionPolicy.resolve(reduceMotion: reduceMotion, lowPower: lowPower, thermal: thermal)
    }

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        policyOverride = IslandMotionPolicy.override(from: environment)
    }

    /// Called once from AppModel at launch. Reads the current values and then
    /// follows changes. Calling it again does nothing.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        refresh()
        // Reduce Motion is announced on the workspace's own center, not the
        // default one.
        observe(NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, on: NSWorkspace.shared.notificationCenter)
        observe(.NSProcessInfoPowerStateDidChange, on: .default)
        observe(ProcessInfo.thermalStateDidChangeNotification, on: .default)
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter) {
        // `queue: .main` delivers on the main thread, so the handler can
        // assume main-actor isolation.
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        observers.append(token)
    }

    private func refresh() {
        let processInfo = ProcessInfo.processInfo
        let newReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let newLowPower = processInfo.isLowPowerModeEnabled
        let newThermal = processInfo.thermalState
        // Only write what changed so observers of the policy are not woken
        // by repeated notifications.
        if reduceMotion != newReduceMotion { reduceMotion = newReduceMotion }
        if lowPower != newLowPower { lowPower = newLowPower }
        if thermal != newThermal { thermal = newThermal }
    }
}
