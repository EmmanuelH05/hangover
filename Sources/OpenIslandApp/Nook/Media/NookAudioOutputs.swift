import Foundation
import Observation
import OSLog

private let outputsLog = Logger(subsystem: "app.openisland", category: "nook.audio")

/// Pure rules for the speaker picker.
enum NookAudioOutputRules {
    /// The Mac's own speakers first, then what is worn, then the rest.
    /// Virtual devices (loopback and aggregate drivers) go last.
    static let kindOrder: [NookAudioOutput.Kind] = [.builtIn, .bluetooth, .airPlay, .display, .usb, .other, .virtual]

    static func sorted(_ outputs: [NookAudioOutput]) -> [NookAudioOutput] {
        outputs.sorted { a, b in
            let rankA = kindOrder.firstIndex(of: a.kind) ?? kindOrder.count
            let rankB = kindOrder.firstIndex(of: b.kind) ?? kindOrder.count
            if rankA != rankB { return rankA < rankB }
            let order = a.name.localizedCaseInsensitiveCompare(b.name)
            return order == .orderedSame ? a.id < b.id : order == .orderedAscending
        }
    }

    /// Words in a Bluetooth output's name that mean it is worn. CoreAudio
    /// does not say whether a Bluetooth output is a speaker or headphones.
    static let wornNameHints = ["headphone", "headset", "earphone", "earbud", "buds", "beats", "wh-", "wf-"]

    static func symbol(for output: NookAudioOutput) -> String {
        let name = output.name.lowercased()
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods") { return "airpodspro" }
        if name.contains("homepod") { return "homepod.fill" }
        switch output.kind {
        case .builtIn: return "speaker.wave.2.fill"
        case .bluetooth: return wornNameHints.contains { name.contains($0) } ? "headphones" : "hifispeaker.fill"
        case .airPlay: return "airplayaudio"
        case .display: return "display"
        case .usb, .other: return "hifispeaker.fill"
        case .virtual: return "waveform"
        }
    }

    /// Alert sounds follow the music when they came out of the same place
    /// before the switch, which is how the Sound settings behave when set
    /// to "selected sound output device".
    static func alertsFollowOutput(systemID: UInt32?, defaultID: UInt32?) -> Bool {
        guard let systemID, let defaultID else { return false }
        return systemID == defaultID
    }
}

/// The outputs the speaker picker on the now-playing card lists, and the
/// one sound goes to now. Stays current while outputs come and go.
@MainActor
@Observable
final class NookAudioOutputs {
    private(set) var devices: [NookAudioOutput] = []
    private(set) var currentID: UInt32?
    /// An output the last switch could not move to. Cleared by the next
    /// switch that works, by the output list changing, and each time the
    /// picker opens: a refusal is about that try, not about the output.
    private(set) var failedID: UInt32?

    @ObservationIgnored private let hardware: any NookAudioHardware
    @ObservationIgnored private var started = false

    init(hardware: any NookAudioHardware = CoreAudioHardware.shared) {
        self.hardware = hardware
    }

    var current: NookAudioOutput? {
        devices.first { $0.id == currentID }
    }

    func start() {
        guard !started else { return }
        started = true
        hardware.addListener { [weak self] change in
            guard let self, change != .level else { return }
            if change == .devices { self.failedID = nil }
            self.refresh()
        }
        hardware.start()
        refresh()
    }

    /// Called when the speaker picker opens: a fresh list, with no mark
    /// left over from a switch that failed the last time it was open.
    func beginPicking() {
        if failedID != nil { failedID = nil }
        refresh()
    }

    func refresh() {
        let next = NookAudioOutputRules.sorted(hardware.outputs())
        if next != devices { devices = next }
        let id = hardware.defaultOutputID()
        if id != currentID { currentID = id }
    }

    /// Sends sound to another output. Alert sounds go with it when they
    /// were following the old one.
    func select(_ id: UInt32) {
        guard id != currentID else { return }
        let alertsFollow = NookAudioOutputRules.alertsFollowOutput(
            systemID: hardware.systemOutputID(),
            defaultID: hardware.defaultOutputID()
        )
        guard hardware.setDefaultOutput(id) else {
            outputsLog.error("output \(id, privacy: .public) refused the switch")
            failedID = id
            refresh()
            return
        }
        if alertsFollow { hardware.setSystemOutput(id) }
        failedID = nil
        refresh()
    }
}
