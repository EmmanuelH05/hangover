import AppKit
import ApplicationServices
import Foundation
import Observation
import OSLog

private let keysLog = Logger(subsystem: "app.openisland", category: "nook.mediakeys")

/// One press or release of a media key.
struct NookMediaKeyEvent: Equatable, Sendable {
    var key: NookMediaKey
    var isDown: Bool
    var modifiers = NookMediaKeyModifiers()
    /// The event waited too long before it reached the app. macOS has
    /// handled the key by then, and acting on it would handle it twice.
    var isStale = false
}

/// The Accessibility grant, which macOS requires before an app may keep a
/// key from the rest of the system.
@MainActor
protocol NookAccessibilityTrust: AnyObject {
    func isTrusted() -> Bool
    /// Shows the system's own request for the grant.
    func prompt()
}

@MainActor
final class NookSystemAccessibilityTrust: NookAccessibilityTrust {
    func isTrusted() -> Bool { AXIsProcessTrusted() }

    func prompt() {
        // The documented value of `kAXTrustedCheckOptionPrompt`.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
}

/// Sits between the keyboard and macOS for the media keys.
@MainActor
protocol NookMediaKeyFilter: AnyObject {
    /// `handler` answers true to keep an event from macOS. Returns false
    /// when the filter could not be put in place.
    func install(handler: @escaping @MainActor (NookMediaKeyEvent) -> Bool) -> Bool
    func remove()
    /// Switches the filter back on when macOS has switched it off. True
    /// when it had to.
    @discardableResult func revive() -> Bool
}

/// Takes over the volume and brightness keys, which keeps Apple's own
/// popup away: the app moves the volume or the brightness itself and the
/// closed notch shows the result. Off until the user turns it on, because
/// it needs the Accessibility grant.
///
/// The grant is asked for once, by the switch in Settings and never at
/// launch. After that the app only checks, quietly, whether it is there:
/// it takes the keys when the grant arrives and lets go of them when the
/// grant is taken away, because a key filter left in place without the
/// grant can hold up the keyboard.
@MainActor
@Observable
final class NookMediaKeys {
    static let enabledKey = "nook.volume.takesKeys"
    static let askedKey = "nook.volume.askedAccessibility"
    static let accessCheckInterval: Duration = .seconds(2)

    enum Status: Equatable, Sendable {
        case off
        /// Switched on, and macOS has not granted Accessibility yet.
        case waitingForAccess
        case active
        /// Granted, and macOS still refused the key filter.
        case unavailable
    }

    private(set) var status: Status = .off

    /// False while the closed notch cannot show a notice (the island is
    /// open, or notices are off on this display). The keys then stay with
    /// macOS, popup included, which keeps a key press from going unseen.
    @ObservationIgnored var canShowNotice: () -> Bool = { true }
    /// Called with the new brightness after a brightness key.
    @ObservationIgnored var onBrightness: ((Float) -> Void)?
    /// Called after a volume or mute key the app kept from macOS, whether
    /// or not the level changed.
    @ObservationIgnored var onVolumeKey: (() -> Void)?
    /// True while a kept key is changing the output. The change it causes
    /// is announced through `onVolumeKey`, not as a change from outside.
    @ObservationIgnored private(set) var isApplyingKey = false

    @ObservationIgnored private let hardware: any NookAudioHardware
    @ObservationIgnored private let brightness: any NookBrightnessControl
    @ObservationIgnored private let trust: any NookAccessibilityTrust
    @ObservationIgnored private let filter: any NookMediaKeyFilter
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var accessCheck: Task<Void, Never>?
    /// Whether each key's last press was kept from macOS. Its release gets
    /// the same answer.
    @ObservationIgnored private var keptPress: [NookMediaKey: Bool] = [:]

    init(
        hardware: any NookAudioHardware,
        brightness: any NookBrightnessControl,
        trust: any NookAccessibilityTrust,
        filter: any NookMediaKeyFilter,
        defaults: UserDefaults = .standard
    ) {
        self.hardware = hardware
        self.brightness = brightness
        self.trust = trust
        self.filter = filter
        self.defaults = defaults
    }

    var isEnabled: Bool {
        defaults.object(forKey: Self.enabledKey) as? Bool ?? false
    }

    /// Called at launch. Never asks for anything: it takes the keys when
    /// the grant is already there and waits quietly when it is not.
    func start() {
        guard isEnabled else { return }
        activateOrWait()
    }

    /// The switch in Settings. Turning it on without the grant asks macOS
    /// for it, the first time only.
    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey)
        guard enabled else {
            stop()
            return
        }
        if !trust.isTrusted(), !(defaults.object(forKey: Self.askedKey) as? Bool ?? false) {
            defaults.set(true, forKey: Self.askedKey)
            trust.prompt()
        }
        activateOrWait()
    }

    /// Follows the grant: takes the keys when it has arrived and lets go
    /// of them when it is gone. The quiet check calls this, and anything that
    /// knows the grant may have changed can call it too.
    func checkAccess() {
        guard isEnabled else { return }
        let trusted = trust.isTrusted()
        switch status {
        case .waitingForAccess where trusted:
            takeKeys()
        case .active where !trusted, .unavailable where !trusted:
            filter.remove()
            keptPress.removeAll()
            status = .waitingForAccess
        case .active:
            // macOS can switch a filter off without saying a word. The keys
            // then work as usual, with nothing in the notch.
            if filter.revive() { keysLog.notice("the media key filter was off and is back on") }
        default:
            break
        }
    }

    private func activateOrWait() {
        if trust.isTrusted() {
            takeKeys()
        } else {
            status = .waitingForAccess
        }
        guard accessCheck == nil else { return }
        accessCheck = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.accessCheckInterval)
                guard !Task.isCancelled, let self, self.status != .off else { return }
                self.checkAccess()
            }
        }
    }

    private func takeKeys() {
        let installed = filter.install { [weak self] event in
            self?.handle(event) ?? false
        }
        if !installed { keysLog.error("macOS refused the media key filter") }
        status = installed ? .active : .unavailable
    }

    private func stop() {
        accessCheck?.cancel()
        accessCheck = nil
        filter.remove()
        keptPress.removeAll()
        status = .off
    }

    /// Acts on one key event. True keeps it from macOS.
    func handle(_ event: NookMediaKeyEvent) -> Bool {
        guard event.isDown else {
            return keptPress.removeValue(forKey: event.key) ?? false
        }
        let kept = press(event)
        keptPress[event.key] = kept
        return kept
    }

    private func press(_ event: NookMediaKeyEvent) -> Bool {
        guard status == .active, !event.isStale, canShowNotice(),
              !NookMediaKeyRules.staysWithSystem(event.modifiers)
        else {
            return false
        }
        let fine = NookMediaKeyRules.isFine(event.modifiers)
        if event.key.isBrightness {
            guard let current = brightness.brightness() else { return false }
            let next = NookMediaKeyRules.stepped(current, up: event.key == .brightnessUp, fine: fine)
            guard brightness.setBrightness(next) else { return false }
            onBrightness?(next)
            return true
        }
        guard let device = hardware.defaultOutputID(), let isMuted = hardware.isMuted(device) else { return false }
        let reading = NookVolumeReading(deviceID: device, volume: hardware.volume(of: device), isMuted: isMuted)
        guard let change = NookMediaKeyRules.volumeChange(for: event.key, reading: reading, fine: fine) else {
            return false
        }
        isApplyingKey = true
        defer { isApplyingKey = false }
        // An output that refuses the change leaves the key with macOS. Mute
        // goes first and the volume last: a refusal can then only come
        // before the volume has moved, and macOS, which gets the key, moves
        // it once and not a second time.
        if let muted = change.isMuted, !hardware.setMuted(muted, of: device) { return false }
        if let volume = change.volume, !hardware.setVolume(volume, of: device) { return false }
        onVolumeKey?()
        return true
    }
}

/// The key filter the app uses: an event tap on the system-defined events
/// that carry the media keys.
@MainActor
final class NookEventTapKeyFilter: NookMediaKeyFilter {
    /// `NX_SYSDEFINED`, the event type of the media keys.
    nonisolated static let systemDefined: UInt32 = 14
    /// The subtype of a media key inside a system-defined event.
    nonisolated static let mediaKeySubtype: Int16 = 8

    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    fileprivate var handler: (@MainActor (NookMediaKeyEvent) -> Bool)?

    func install(handler: @escaping @MainActor (NookMediaKeyEvent) -> Bool) -> Bool {
        remove()
        let mask = CGEventMask(1) << CGEventMask(Self.systemDefined)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: nookMediaKeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        self.handler = handler
        return true
    }

    func remove() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        port = nil
        source = nil
        handler = nil
    }

    /// macOS switches a tap off when it is slow or the user input pauses.
    fileprivate func reenable() {
        if let port { CGEvent.tapEnable(tap: port, enable: true) }
    }

    func revive() -> Bool {
        guard let port, !CGEvent.tapIsEnabled(tap: port) else { return false }
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    /// Reads a media key out of a system-defined event. Nil for every
    /// other event, which then passes through untouched.
    static func keyEvent(from event: NSEvent) -> NookMediaKeyEvent? {
        guard event.type == .systemDefined, event.subtype.rawValue == mediaKeySubtype else { return nil }
        return keyEvent(data1: event.data1, flags: event.modifierFlags)
    }

    /// `data1` packs the key code in its high word, and the key state and
    /// the repeat flag in its low word.
    nonisolated static func keyEvent(data1: Int, flags: NSEvent.ModifierFlags) -> NookMediaKeyEvent? {
        guard let key = NookMediaKey(keyCode: (data1 & 0xFFFF_0000) >> 16) else { return nil }
        let state = (data1 & 0xFF00) >> 8
        return NookMediaKeyEvent(
            key: key,
            isDown: state == 0x0A,
            modifiers: NookMediaKeyModifiers(
                shift: flags.contains(.shift),
                option: flags.contains(.option),
                control: flags.contains(.control),
                command: flags.contains(.command)
            )
        )
    }
}

/// Runs on the main run loop, where the tap's source is installed.
private func nookMediaKeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let passed = Unmanaged.passUnretained(event)
    guard let refcon else { return passed }
    let filter = Unmanaged<NookEventTapKeyFilter>.fromOpaque(refcon).takeUnretainedValue()
    // The event never leaves this thread: the callback is already on the
    // main run loop.
    nonisolated(unsafe) let tapped = event
    let keep = MainActor.assumeIsolated { () -> Bool in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            filter.reenable()
            return false
        }
        guard type.rawValue == NookEventTapKeyFilter.systemDefined,
              let nsEvent = NSEvent(cgEvent: tapped),
              var keyEvent = NookEventTapKeyFilter.keyEvent(from: nsEvent)
        else { return false }
        // The event carries the uptime it was made at. One that sat in the
        // queue while the main thread was busy is marked, and stays with
        // macOS, which gave up waiting and handled it.
        let uptime = ProcessInfo.processInfo.systemUptime
        keyEvent.isStale = NookMediaKeyRules.isStale(eventUptime: nsEvent.timestamp, nowUptime: uptime)
        if keyEvent.isStale, keyEvent.isDown {
            let age = uptime - nsEvent.timestamp
            keysLog.notice("a media key arrived \(age, format: .fixed(precision: 2), privacy: .public)s late and was left to macOS")
        }
        return filter.handler?(keyEvent) ?? false
    }
    return keep ? nil : passed
}
