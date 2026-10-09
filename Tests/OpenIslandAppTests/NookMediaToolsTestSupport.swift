import Foundation
@testable import OpenIslandApp

/// Sound hardware that exists only in memory. Tests never touch the real
/// volume or the real output.
@MainActor
final class FakeAudioHardware: NookAudioHardware {
    var devices: [NookAudioOutput]
    var defaultID: UInt32?
    var systemID: UInt32?
    var volumes: [UInt32: Float] = [:]
    var mutes: [UInt32: Bool] = [:]
    /// Outputs that refuse to become the default.
    var refusedOutputs: Set<UInt32> = []
    /// Outputs that refuse a volume or mute change.
    var refusedLevels: Set<UInt32> = []
    /// Outputs whose mute can be read and not set.
    var refusedMutes: Set<UInt32> = []
    /// Outputs whose volume can be read and not set.
    var refusedVolumes: Set<UInt32> = []

    private(set) var startCount = 0
    private(set) var defaultSets: [UInt32] = []
    private(set) var systemSets: [UInt32] = []
    private var handlers: [@MainActor (NookAudioChange) -> Void] = []

    init(devices: [NookAudioOutput] = [], defaultID: UInt32? = nil, systemID: UInt32? = nil) {
        self.devices = devices
        self.defaultID = defaultID
        self.systemID = systemID
    }

    func start() { startCount += 1 }

    func addListener(_ handler: @escaping @MainActor (NookAudioChange) -> Void) {
        handlers.append(handler)
    }

    func emit(_ change: NookAudioChange) {
        for handler in handlers { handler(change) }
    }

    func outputs() -> [NookAudioOutput] { devices }
    func defaultOutputID() -> UInt32? { defaultID }
    func systemOutputID() -> UInt32? { systemID }

    func setDefaultOutput(_ id: UInt32) -> Bool {
        guard !refusedOutputs.contains(id) else { return false }
        defaultSets.append(id)
        defaultID = id
        return true
    }

    func setSystemOutput(_ id: UInt32) -> Bool {
        systemSets.append(id)
        systemID = id
        return true
    }

    func volume(of id: UInt32) -> Float? { volumes[id] }
    func isMuted(_ id: UInt32) -> Bool? { mutes[id] }

    func setVolume(_ volume: Float, of id: UInt32) -> Bool {
        guard volumes[id] != nil, !refusedLevels.contains(id), !refusedVolumes.contains(id) else { return false }
        volumes[id] = volume
        emit(.level)
        return true
    }

    func setMuted(_ muted: Bool, of id: UInt32) -> Bool {
        guard mutes[id] != nil, !refusedLevels.contains(id), !refusedMutes.contains(id) else { return false }
        mutes[id] = muted
        emit(.level)
        return true
    }
}

@MainActor
final class FakeBrightness: NookBrightnessControl {
    var value: Float?
    var refuses = false
    private(set) var sets: [Float] = []

    init(value: Float? = nil) {
        self.value = value
    }

    func brightness() -> Float? { value }

    func setBrightness(_ value: Float) -> Bool {
        guard !refuses, self.value != nil else { return false }
        sets.append(value)
        self.value = value
        return true
    }
}

@MainActor
final class FakeAccessibilityTrust: NookAccessibilityTrust {
    var trusted: Bool
    private(set) var prompts = 0

    init(trusted: Bool = false) {
        self.trusted = trusted
    }

    func isTrusted() -> Bool { trusted }
    func prompt() { prompts += 1 }
}

@MainActor
final class FakeKeyFilter: NookMediaKeyFilter {
    var refuses = false
    /// macOS switched the filter off behind the app's back.
    var isSwitchedOff = false
    private(set) var installs = 0
    private(set) var removes = 0
    private(set) var revivals = 0
    private(set) var handler: (@MainActor (NookMediaKeyEvent) -> Bool)?

    func install(handler: @escaping @MainActor (NookMediaKeyEvent) -> Bool) -> Bool {
        guard !refuses else { return false }
        installs += 1
        self.handler = handler
        return true
    }

    func remove() {
        removes += 1
        handler = nil
    }

    func revive() -> Bool {
        guard isSwitchedOff else { return false }
        isSwitchedOff = false
        revivals += 1
        return true
    }
}

/// A weather transport that never touches the network. Records every URL.
final class StubWeatherTransport: NookWeatherTransport, @unchecked Sendable {
    enum Reply: Sendable {
        case body(String, status: Int)
        case offline
        /// Any other way a request can fail before an answer arrives.
        case failing(URLError.Code)
    }

    typealias Responder = @Sendable (_ url: URL) -> Reply

    private let lock = NSLock()
    private var recorded: [URL] = []
    private var responder: Responder

    init(_ responder: @escaping Responder = { _ in .body("{}", status: 200) }) {
        self.responder = responder
    }

    var requests: [URL] { lock.withLock { recorded } }

    func setResponder(_ responder: @escaping Responder) {
        lock.withLock { self.responder = responder }
    }

    func get(_ url: URL) async throws -> (Data, Int) {
        let current: Responder = lock.withLock {
            recorded.append(url)
            return responder
        }
        switch current(url) {
        case let .body(body, status): return (Data(body.utf8), status)
        case .offline: throw URLError(.notConnectedToInternet)
        case let .failing(code): throw URLError(code)
        }
    }
}

/// A clock a test moves by hand.
final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ start: Date) {
        value = start
    }

    var now: Date { lock.withLock { value } }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { value = value.addingTimeInterval(seconds) }
    }
}

/// Settings that live in memory only. A `UserDefaults(suiteName:)` leaves
/// a file in `~/Library/Preferences` for every name it is given, emptied or
/// not, which was one file per test per run. This writes nothing anywhere:
/// the typed reads and writes (`bool`, `string`, `data`, `set`) all go
/// through `object`, `set` and `removeObject` below, and nothing reaches
/// `super`.
final class MemoryDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    init() {
        // The name is only what `super` asks for. It is never written to.
        super.init(suiteName: "open-island-tests.memory")!
    }

    var all: [String: Any] { lock.withLock { values } }

    func removeAll() {
        lock.withLock { values.removeAll() }
    }

    override func object(forKey defaultName: String) -> Any? {
        lock.withLock { values[defaultName] }
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        lock.withLock { values[defaultName] = value }
    }

    override func removeObject(forKey defaultName: String) {
        lock.withLock { values[defaultName] = nil }
    }

    // The domain calls a test makes on its own suite. This store is its one
    // domain, whatever name it is asked by, and none of it is on disk.

    override func persistentDomain(forName domainName: String) -> [String: Any]? {
        let own = all
        return own.isEmpty ? nil : own
    }

    override func removePersistentDomain(forName domainName: String) {
        removeAll()
    }

    override func dictionaryRepresentation() -> [String: Any] { all }
}

/// A settings store of its own for one test, with what it holds read back
/// without the standard domain mixed in. Nothing is left on disk.
struct TestDefaults {
    let name: String
    let defaults: UserDefaults
    private let memory: MemoryDefaults

    init(_ label: String) {
        name = "open-island-tests.\(label)"
        memory = MemoryDefaults()
        defaults = memory
    }

    var ownValues: [String: Any] { memory.all }

    func remove() { memory.removeAll() }
}

enum NookMediaSamples {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// A track as the MediaRemote adapter reports it.
    static func track(
        bundle: String = "com.spotify.client",
        item: String? = "track-1",
        title: String = "Song",
        isPlaying: Bool = true,
        duration: Double? = 200,
        elapsed: Double? = 10,
        at time: Date = start
    ) -> NowPlayingState {
        var payload: [String: Any] = [
            "bundleIdentifier": bundle,
            "title": title,
            "playing": isPlaying,
            "timestamp": time.ISO8601Format(),
        ]
        if let item { payload["contentItemIdentifier"] = item }
        if let duration { payload["duration"] = duration }
        if let elapsed { payload["elapsedTime"] = elapsed }
        return NowPlayingState(payload: payload)!
    }

    static let speakers = NookAudioOutput(id: 95, name: "MacBook Pro Speakers", kind: .builtIn)
    static let airPods = NookAudioOutput(id: 134, name: "AirPods Pro", kind: .bluetooth)
    static let display = NookAudioOutput(id: 140, name: "Studio Display", kind: .display)
    static let loopback = NookAudioOutput(id: 74, name: "BlackHole 2ch", kind: .virtual)
}
