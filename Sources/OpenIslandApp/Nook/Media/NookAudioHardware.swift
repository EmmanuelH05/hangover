import AudioToolbox
import CoreAudio
import Foundation
import OSLog

private let audioLog = Logger(subsystem: "app.openisland", category: "nook.audio")

/// One place sound can come out of.
struct NookAudioOutput: Equatable, Identifiable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case builtIn
        case bluetooth
        case airPlay
        case display
        case usb
        case virtual
        case other
    }

    var id: UInt32
    var name: String
    var kind: Kind
}

/// What changed in the sound hardware.
enum NookAudioChange: Equatable, Sendable {
    /// An output came or went.
    case devices
    /// Sound now goes somewhere else.
    case defaultOutput
    /// The current output's volume or mute changed.
    case level
}

/// The sound hardware as the Nook uses it: the speaker picker, the volume
/// notice and the volume keys. The app talks to CoreAudio; tests pass a
/// fake, which keeps them from ever touching the real volume or output.
@MainActor
protocol NookAudioHardware: AnyObject {
    /// Starts listening for changes. Safe to call more than once.
    func start()
    func addListener(_ handler: @escaping @MainActor (NookAudioChange) -> Void)

    func outputs() -> [NookAudioOutput]
    func defaultOutputID() -> UInt32?
    /// Where alert sounds go.
    func systemOutputID() -> UInt32?
    @discardableResult func setDefaultOutput(_ id: UInt32) -> Bool
    @discardableResult func setSystemOutput(_ id: UInt32) -> Bool

    /// From 0 to 1. Nil for an output with no volume of its own, such as
    /// most displays.
    func volume(of id: UInt32) -> Float?
    func isMuted(_ id: UInt32) -> Bool?
    @discardableResult func setVolume(_ volume: Float, of id: UInt32) -> Bool
    @discardableResult func setMuted(_ muted: Bool, of id: UInt32) -> Bool
}

/// What CoreAudio hands back to `coreAudioPropertiesChanged`. It holds
/// the hardware object weakly, which keeps the two from holding each other,
/// and it is never freed: CoreAudio can still be making a call on its own
/// thread while a listener is being removed, and that call must find the
/// box alive. There is one per process.
private final class CoreAudioListenerContext: @unchecked Sendable {
    /// Set once on the main actor, before the first listener is added.
    weak var hardware: CoreAudioHardware?
}

/// Every listener the app adds is this one function with the one context
/// pointer. CoreAudio matches the listener to remove by that pair. A Swift
/// closure handed over as a block is a new block each time, which left the
/// old output's listeners in place for good.
///
/// CoreAudio calls it on a thread of its own. It copies what changed and
/// hands it to the main actor.
private func coreAudioPropertiesChanged(
    object: AudioObjectID,
    count: UInt32,
    addresses: UnsafePointer<AudioObjectPropertyAddress>,
    context: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let context else { return noErr }
    let box = Unmanaged<CoreAudioListenerContext>.fromOpaque(context).takeUnretainedValue()
    let selectors = (0..<Int(count)).map { addresses[$0].mSelector }
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            box.hardware?.propertiesChanged(on: object, selectors: selectors)
        }
    }
    return noErr
}

/// CoreAudio's public hardware API. It needs no permission.
@MainActor
final class CoreAudioHardware: NookAudioHardware {
    static let shared = CoreAudioHardware()

    private var handlers: [@MainActor (NookAudioChange) -> Void] = []
    private var started = false
    /// The output whose volume and mute are being listened to, and the
    /// properties of it that took a listener.
    private var levelDevice: AudioObjectID?
    private var levelSelectors: [AudioObjectPropertySelector] = []
    /// Retained for the life of the process, see `CoreAudioListenerContext`.
    private let context: Unmanaged<CoreAudioListenerContext>

    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private init() {
        let box = CoreAudioListenerContext()
        context = Unmanaged.passRetained(box)
        box.hardware = self
    }

    func addListener(_ handler: @escaping @MainActor (NookAudioChange) -> Void) {
        handlers.append(handler)
    }

    func start() {
        guard !started else { return }
        started = true
        listen(on: Self.system, selector: kAudioHardwarePropertyDevices, scope: kAudioObjectPropertyScopeGlobal)
        listen(on: Self.system, selector: kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        followDefaultOutput()
    }

    private func emit(_ change: NookAudioChange) {
        for handler in handlers { handler(change) }
    }

    /// Sorts one call from CoreAudio into the changes the Nook follows.
    fileprivate func propertiesChanged(on object: AudioObjectID, selectors: [AudioObjectPropertySelector]) {
        if object == Self.system {
            if selectors.contains(kAudioHardwarePropertyDevices) { emit(.devices) }
            if selectors.contains(kAudioHardwarePropertyDefaultOutputDevice) {
                followDefaultOutput()
                emit(.defaultOutput)
            }
            return
        }
        // A call that was already on its way from an output the app has
        // stopped listening to is dropped.
        guard object == levelDevice, selectors.contains(where: Self.levelProperties.contains) else { return }
        emit(.level)
    }

    @discardableResult
    private func listen(
        on object: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> Bool {
        var address = Self.address(selector, scope)
        let status = AudioObjectAddPropertyListener(object, &address, coreAudioPropertiesChanged, context.toOpaque())
        guard status == noErr else {
            audioLog.warning("could not listen for \(selector, privacy: .public) on \(object, privacy: .public): \(status, privacy: .public)")
            return false
        }
        return true
    }

    private func stopListening(
        on object: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) {
        var address = Self.address(selector, scope)
        let status = AudioObjectRemovePropertyListener(object, &address, coreAudioPropertiesChanged, context.toOpaque())
        // An output that was unplugged is gone, and its listeners with it.
        // CoreAudio then answers with an error, which is the usual case.
        if status != noErr {
            audioLog.notice("could not stop listening for \(selector, privacy: .public) on \(object, privacy: .public): \(status, privacy: .public)")
        }
    }

    /// Moves the volume and mute listeners to the output sound goes to now.
    private func followDefaultOutput() {
        let device = defaultOutputID()
        guard device != levelDevice else { return }
        if let old = levelDevice {
            for selector in levelSelectors {
                stopListening(on: old, selector: selector, scope: kAudioDevicePropertyScopeOutput)
            }
        }
        levelDevice = device
        levelSelectors = []
        guard let device else { return }
        for selector in Self.levelProperties {
            var address = Self.address(selector, kAudioDevicePropertyScopeOutput)
            guard AudioObjectHasProperty(device, &address) else { continue }
            if listen(on: device, selector: selector, scope: kAudioDevicePropertyScopeOutput) {
                levelSelectors.append(selector)
            }
        }
        if levelSelectors.isEmpty {
            audioLog.notice("output \(device, privacy: .public) took no volume or mute listener: its volume changes will not be seen")
        }
    }

    private static let levelProperties: [AudioObjectPropertySelector] = [
        kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        kAudioDevicePropertyMute,
    ]

    private static func address(
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    // MARK: Outputs

    func outputs() -> [NookAudioOutput] {
        var address = Self.address(kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(Self.system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(Self.system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard Self.isUsableOutput(id), let name = Self.name(of: id) else { return nil }
            return NookAudioOutput(id: id, name: name, kind: Self.kind(of: id))
        }
    }

    /// Has output streams and may be picked as the default output.
    private static func isUsableOutput(_ device: AudioObjectID) -> Bool {
        var streams = address(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &size) == noErr, size > 0 else { return false }
        // A device that does not answer the question is taken as usable.
        return uint32(device, kAudioDevicePropertyDeviceCanBeDefaultDevice, kAudioDevicePropertyScopeOutput) != 0
    }

    private static func name(of device: AudioObjectID) -> String? {
        var address = address(kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    private static func kind(of device: AudioObjectID) -> NookAudioOutput.Kind {
        switch uint32(device, kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal) {
        case kAudioDeviceTransportTypeBuiltIn: .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: .bluetooth
        case kAudioDeviceTransportTypeAirPlay: .airPlay
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: .display
        case kAudioDeviceTransportTypeUSB: .usb
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: .virtual
        default: .other
        }
    }

    private static func uint32(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope
    ) -> UInt32? {
        var address = address(selector, scope)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    func defaultOutputID() -> UInt32? { Self.device(kAudioHardwarePropertyDefaultOutputDevice) }
    func systemOutputID() -> UInt32? { Self.device(kAudioHardwarePropertyDefaultSystemOutputDevice) }

    private static func device(_ selector: AudioObjectPropertySelector) -> UInt32? {
        guard let id = uint32(system, selector, kAudioObjectPropertyScopeGlobal), id != kAudioObjectUnknown else {
            return nil
        }
        return id
    }

    func setDefaultOutput(_ id: UInt32) -> Bool {
        Self.setDevice(kAudioHardwarePropertyDefaultOutputDevice, to: id)
    }

    func setSystemOutput(_ id: UInt32) -> Bool {
        Self.setDevice(kAudioHardwarePropertyDefaultSystemOutputDevice, to: id)
    }

    private static func setDevice(_ selector: AudioObjectPropertySelector, to id: UInt32) -> Bool {
        var address = address(selector, kAudioObjectPropertyScopeGlobal)
        var device = id
        let status = AudioObjectSetPropertyData(
            system, &address, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &device
        )
        if status != noErr {
            audioLog.error("could not switch output \(selector, privacy: .public) to \(id, privacy: .public): \(status, privacy: .public)")
        }
        return status == noErr
    }

    // MARK: Volume

    func volume(of id: UInt32) -> Float? {
        var address = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return min(max(value, 0), 1)
    }

    func isMuted(_ id: UInt32) -> Bool? {
        Self.uint32(id, kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput).map { $0 != 0 }
    }

    func setVolume(_ volume: Float, of id: UInt32) -> Bool {
        var address = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        guard Self.isSettable(id, &address) else { return false }
        var value = Float32(min(max(volume, 0), 1))
        return AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }

    func setMuted(_ muted: Bool, of id: UInt32) -> Bool {
        var address = Self.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
        guard Self.isSettable(id, &address) else { return false }
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    private static func isSettable(_ object: AudioObjectID, _ address: inout AudioObjectPropertyAddress) -> Bool {
        guard AudioObjectHasProperty(object, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(object, &address, &settable) == noErr && settable.boolValue
    }
}
