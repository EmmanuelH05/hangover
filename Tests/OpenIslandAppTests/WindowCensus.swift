import AppKit
import CoreGraphics
import Foundation
import Testing

/// How many windows this process has on screen right now, counted two ways:
/// AppKit's own list of visible windows, and the window server's list of
/// on-screen windows owned by this process id. Neither asks for a
/// permission: a process may list its own windows. A test that must not
/// show anything compares a census before its body and one after.
struct WindowCensus: Equatable, CustomStringConvertible {
    var appKitVisible: Int
    var windowServerOnScreen: Int

    var description: String {
        "AppKit visible \(appKitVisible), window server on screen \(windowServerOnScreen)"
    }

    @MainActor
    static func take() -> WindowCensus {
        let visible = (NSApp?.windows ?? []).filter(\.isVisible).count
        let pid = ProcessInfo.processInfo.processIdentifier
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let owned = infos.filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid }
        return WindowCensus(appKitVisible: visible, windowServerOnScreen: owned.count)
    }

    /// Whether `later` shows a window that `self` did not.
    func isExceeded(by later: WindowCensus) -> Bool {
        later.appKitVisible > appKitVisible || later.windowServerOnScreen > windowServerOnScreen
    }
}

/// Put on a suite or a test: each test case runs between two censuses and
/// fails if a window appeared on screen while its body ran.
struct NoNewWindowsTrait: TestTrait, SuiteTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        guard testCase != nil else {
            try await function()
            return
        }
        let before = await MainActor.run { WindowCensus.take() }
        try await function()
        let after = await MainActor.run { WindowCensus.take() }
        #expect(!before.isExceeded(by: after), "a window appeared on screen. Before: \(before). After: \(after).")
    }
}

extension Trait where Self == NoNewWindowsTrait {
    static var noNewWindows: Self { NoNewWindowsTrait() }
}
