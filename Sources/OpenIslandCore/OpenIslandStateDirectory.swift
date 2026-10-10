import Foundation

/// The folder the app keeps what it knows about agent sessions in between
/// launches. A test run gets a folder of its own: tests build sessions
/// that never existed, and one of them, saved to the real folder, came back
/// in the running app as an agent waiting for approval (D45).
public enum OpenIslandStateDirectory {
    /// The real folder, under the user's home.
    public static let realFolderPath = "Library/Application Support/open-island"

    /// Resolved once. The answer cannot change while the process runs.
    public static let url: URL = resolve(
        isTestRun: isTestRun(
            processName: ProcessInfo.processInfo.processName,
            environment: ProcessInfo.processInfo.environment,
            loadedBundlePaths: Bundle.allBundles.map(\.bundlePath)
        ),
        home: FileManager.default.homeDirectoryForCurrentUser,
        temporary: FileManager.default.temporaryDirectory,
        processID: ProcessInfo.processInfo.processIdentifier
    )

    public static func resolve(isTestRun: Bool, home: URL, temporary: URL, processID: Int32) -> URL {
        guard isTestRun else {
            return home.appendingPathComponent(realFolderPath, isDirectory: true)
        }
        return temporary.appendingPathComponent("open-island-tests-\(processID)", isDirectory: true)
    }

    /// True inside `swift test` and Xcode's test runner. The runner's name,
    /// its environment or a loaded test bundle gives it away.
    public static func isTestRun(
        processName: String,
        environment: [String: String],
        loadedBundlePaths: [String]
    ) -> Bool {
        if testRunnerNames.contains(processName) { return true }
        if environment.keys.contains(where: { $0.hasPrefix("XCTest") }) { return true }
        return loadedBundlePaths.contains { $0.hasSuffix(".xctest") }
    }

    static let testRunnerNames: Set<String> = ["xctest", "swiftpm-testing-helper"]
}
