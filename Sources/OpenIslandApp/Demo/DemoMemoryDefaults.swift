import Foundation

/// Settings that live in memory only (D51). The demo mode runs on this
/// store, which starts from the app's defaults and writes nothing anywhere:
/// every typed read and write goes through `object`, `set` and
/// `removeObject`, and nothing reaches `super`.
final class DemoMemoryDefaults: UserDefaults {
    private let lock = NSLock()
    private var values: [String: Any] = [:]
    /// What `register(defaults:)` was given. Read after `values`.
    private var registered: [String: Any] = [:]

    init() {
        // The name is only what `super` asks for. It is never written to.
        super.init(suiteName: "open-island-demo.memory")!
    }

    /// A store that already holds `values`.
    convenience init(holding values: [String: Any]) {
        self.init()
        for (key, value) in values { set(value, forKey: key) }
    }

    var all: [String: Any] { lock.withLock { values } }

    override func object(forKey defaultName: String) -> Any? {
        lock.withLock { values[defaultName] ?? registered[defaultName] }
    }

    override func register(defaults registrationDictionary: [String: Any]) {
        lock.withLock { registered.merge(registrationDictionary) { current, _ in current } }
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        lock.withLock { values[defaultName] = value }
    }

    override func removeObject(forKey defaultName: String) {
        lock.withLock { values[defaultName] = nil }
    }

    override func persistentDomain(forName domainName: String) -> [String: Any]? {
        let own = all
        return own.isEmpty ? nil : own
    }

    override func removePersistentDomain(forName domainName: String) {
        lock.withLock { values.removeAll() }
    }

    override func dictionaryRepresentation() -> [String: Any] { all }
}
