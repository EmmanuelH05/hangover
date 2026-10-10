import AppKit
import CoreAudio
import Foundation
import IOKit.ps
import Observation
import SwiftUI

/// Shows closed-notch notices when the charger or Bluetooth headphones
/// connect. No card.
@MainActor
@Observable
final class NookPowerMonitor {
    static let enabledKey = "nook.power.enabled"

    @ObservationIgnored private(set) weak var nook: NookModel?

    /// Battery level for the closed island's left slot. Nil on a Mac
    /// without a battery.
    private(set) var batteryPercent: Int?
    private(set) var isCharging = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var isOnAC: Bool?
    @ObservationIgnored private var lastDeviceID: AudioObjectID?
    @ObservationIgnored private var powerSource: CFRunLoopSource?
    @ObservationIgnored private var audioListener: AudioObjectPropertyListenerBlock?

    /// The IOKit callback is a C function, so it reaches the monitor
    /// through this bridge and hops to the main actor.
    private static var current: NookPowerMonitor?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var isEnabled: Bool {
        defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func start(nook: NookModel) {
        self.nook = nook
        guard !started else { return }
        started = true
        Self.current = self

        // Baseline first, so launch does not announce the current state.
        let initial = readPower()
        isOnAC = initial?.isOnAC
        batteryPercent = initial?.percent
        isCharging = initial?.isOnAC ?? false
        lastDeviceID = Self.defaultOutputDevice()

        let callback: IOPowerSourceCallbackType = { _ in
            Task { @MainActor in NookPowerMonitor.current?.powerChanged() }
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            powerSource = source
        }

        var address = Self.outputDeviceAddress
        let listener: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor in NookPowerMonitor.current?.outputDeviceChanged() }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener
        )
        if status == noErr { audioListener = listener }
    }

    // MARK: Power

    struct PowerState {
        let isOnAC: Bool
        let percent: Int
    }

    private func readPower() -> PowerState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }
            let state = desc[kIOPSPowerSourceStateKey] as? String
            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let percent = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
            return PowerState(isOnAC: state == kIOPSACPowerValue, percent: percent)
        }
        return nil
    }

    private func powerChanged() {
        guard let state = readPower() else { return }
        let previous = isOnAC
        isOnAC = state.isOnAC
        batteryPercent = state.percent
        isCharging = state.isOnAC
        guard previous != nil, previous != state.isOnAC, isEnabled else { return }
        showPower(state)
    }

    /// The notice for the charger going in or out. A real power change
    /// calls it, and the demo script does too (D51).
    func showPower(_ state: PowerState) {
        if state.isOnAC {
            nook?.showTransient(
                symbol: "bolt.fill",
                text: "Charging · \(state.percent)%",
                tint: .green,
                level: state.percent
            )
        } else {
            nook?.showTransient(
                symbol: Self.batterySymbol(for: state.percent),
                text: "On battery · \(state.percent)%",
                tint: .white,
                level: state.percent
            )
        }
    }

    private static func batterySymbol(for percent: Int) -> String {
        switch percent {
        case 88...: return "battery.100"
        case 63...: return "battery.75"
        case 38...: return "battery.50"
        default: return "battery.25"
        }
    }

    // MARK: Audio

    private static var outputDeviceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var address = outputDeviceAddress
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func isBluetooth(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else {
            return false
        }
        return transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func name(of device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
              let name
        else { return nil }
        return name.takeRetainedValue() as String
    }

    private func outputDeviceChanged() {
        let device = Self.defaultOutputDevice()
        let previous = lastDeviceID
        lastDeviceID = device
        guard let device, device != previous, isEnabled, Self.isBluetooth(device) else { return }
        let name = Self.name(of: device) ?? "Headphones"
        let isAirPods = name.localizedCaseInsensitiveContains("AirPods")
        // Closed-notch text has room for about 18 characters.
        let label = isAirPods ? "AirPods" : (name.count > 9 ? String(name.prefix(8)) + "…" : name)
        nook?.showTransient(symbol: isAirPods ? "airpodspro" : "headphones", text: "\(label) connected")
    }
}
