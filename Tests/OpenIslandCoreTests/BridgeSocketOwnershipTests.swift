import Foundation
import Testing
@testable import OpenIslandCore

/// Binding a socket path takes it from whoever had it. These hold the rule
/// that only the app on its own path listens on the legacy path too.
@Suite struct BridgeSocketOwnershipTests {
    private let appPath = URL(fileURLWithPath: "/Users/someone/Library/Application Support/OpenIsland/bridge.sock")
    private let legacyPath = URL(fileURLWithPath: "/tmp/open-island-501.sock")

    @Test func theAppOnItsOwnPathAlsoListensOnTheLegacyPath() {
        #expect(BridgeServer.legacyListenerURL(for: appPath, defaultURL: appPath, legacyURL: legacyPath) == legacyPath)
    }

    @Test func aServerOnAPathOfItsOwnLeavesTheLegacyPathAlone() {
        // A test, or a copy of the app started for a launch check.
        let own = BridgeSocketLocation.uniqueTestURL()

        #expect(BridgeServer.legacyListenerURL(for: own, defaultURL: appPath, legacyURL: legacyPath) == nil)
        #expect(BridgeServer.legacyListenerURL(for: own) == nil)
    }

    @Test func aServerAlreadyOnTheLegacyPathDoesNotBindItTwice() {
        #expect(BridgeServer.legacyListenerURL(for: legacyPath, defaultURL: legacyPath, legacyURL: legacyPath) == nil)
    }

    @Test func aLaunchCanNameItsOwnSocket() {
        let named = BridgeSocketLocation.currentURL(environment: ["OPEN_ISLAND_SOCKET_PATH": "/tmp/check/bridge.sock"])

        #expect(named.path == "/tmp/check/bridge.sock")
        #expect(BridgeSocketLocation.currentURL(environment: [:]) == BridgeSocketLocation.defaultURL)
        #expect(BridgeServer.legacyListenerURL(for: named) == nil)
    }

    @Test func thePackagingLaunchCheckNamesItsOwnSocket() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/package-app.sh")
        let text = try String(contentsOf: script, encoding: .utf8)

        #expect(text.contains("OPEN_ISLAND_SOCKET_PATH=\"$smoke_dir/bridge.sock\" \"$smoke_binary\" &"))
    }
}
