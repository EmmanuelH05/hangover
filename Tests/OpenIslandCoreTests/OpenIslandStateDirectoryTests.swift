import Foundation
import Testing
@testable import OpenIslandCore

/// Tests build agent sessions that never existed. None of them may reach
/// the folder the real app restores its sessions from (D45).
struct OpenIslandStateDirectoryTests {
    private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
    private let temporary = URL(fileURLWithPath: "/tmp/somewhere", isDirectory: true)

    @Test func theAppUsesTheRealFolder() {
        let url = OpenIslandStateDirectory.resolve(isTestRun: false, home: home, temporary: temporary, processID: 42)

        #expect(url.path == "/Users/someone/Library/Application Support/open-island")
    }

    @Test func aTestRunGetsAFolderOfItsOwn() {
        let url = OpenIslandStateDirectory.resolve(isTestRun: true, home: home, temporary: temporary, processID: 42)
        let other = OpenIslandStateDirectory.resolve(isTestRun: true, home: home, temporary: temporary, processID: 43)

        #expect(url.path == "/tmp/somewhere/open-island-tests-42")
        #expect(url != other)
    }

    @Test func aTestRunnerIsKnownByItsNameItsEnvironmentOrItsBundle() {
        #expect(OpenIslandStateDirectory.isTestRun(processName: "xctest", environment: [:], loadedBundlePaths: []))
        #expect(OpenIslandStateDirectory.isTestRun(
            processName: "swiftpm-testing-helper", environment: [:], loadedBundlePaths: []
        ))
        #expect(OpenIslandStateDirectory.isTestRun(
            processName: "other", environment: ["XCTestBundlePath": "/x"], loadedBundlePaths: []
        ))
        #expect(OpenIslandStateDirectory.isTestRun(
            processName: "other", environment: [:], loadedBundlePaths: ["/build/OpenIslandPackageTests.xctest"]
        ))
    }

    @Test func theAppItselfIsNotATestRun() {
        #expect(!OpenIslandStateDirectory.isTestRun(
            processName: "OpenIslandApp",
            environment: ["OPEN_ISLAND_SOCKET_PATH": "/tmp/x.sock", "HOME": "/Users/someone"],
            loadedBundlePaths: ["/Applications/Hangover.app", "/Applications/Hangover.app/Contents/Frameworks/Sparkle.framework"]
        ))
    }

    /// The run these tests are part of: every default path stays out of the
    /// real folder.
    @Test func thisRunKeepsOutOfTheRealFolder() {
        let real = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(OpenIslandStateDirectory.realFolderPath).path
        let defaults = [
            CodexSessionStore.defaultDirectoryURL,
            CodexSessionStore.defaultFileURL,
            ClaudeSessionRegistry.defaultDirectoryURL,
            CursorSessionRegistry.defaultDirectoryURL,
            OpenCodeSessionRegistry.defaultDirectoryURL,
        ]

        for url in defaults {
            #expect(!url.path.hasPrefix(real), "\(url.path) is in the real folder")
        }
    }
}
