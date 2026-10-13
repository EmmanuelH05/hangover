import Foundation
import Testing
@testable import OpenIslandApp

/// The demo mode with the design kit on its page (D51, D53), for a
/// recording of somebody using the kit by hand. Nothing here hands the kit
/// its real services: no sampler, no panel, no clipboard and no shortcut.
@MainActor
@Suite struct DemoDesignKitTests {
    @MainActor private struct Rig {
        let session: DemoSession
        let root: URL

        init(_ extra: [String: String] = [:]) {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("hangover-demo-tests-\(UUID().uuidString)", isDirectory: true)
            var environment = DemoFixture.environment
            environment.merge(extra) { _, new in new }
            session = DemoSession(
                environment: environment, now: DemoFixture.now, temporary: root, putsPanelOnScreen: false
            )
        }

        func remove() {
            session.model.nook.timer.reset()
            try? FileManager.default.removeItem(at: root)
        }
    }

    @Test func withoutTheSwitchTheKitStaysOffInADemo() {
        let rig = Rig()
        defer { rig.remove() }

        #expect(!rig.session.showsDesignKit)
        #expect(!rig.session.model.nook.isWidgetEnabled(.design))
    }

    @Test func anyOtherValueOfTheSwitchLeavesTheKitOff() {
        let rig = Rig([DemoMode.designKey: "yes"])
        defer { rig.remove() }

        #expect(!rig.session.showsDesignKit)
        #expect(!rig.session.model.nook.isWidgetEnabled(.design))
    }

    @Test func theSwitchPutsTheKitFirstOnEveryDisplaysPageAtItsLargestSize() {
        let rig = Rig([DemoMode.designKey: "1"])
        defer { rig.remove() }
        let nook = rig.session.model.nook

        #expect(rig.session.showsDesignKit)
        #expect(nook.isWidgetEnabled(.design))
        for profile in IslandAppearanceDisplayProfile.allCases {
            let page = nook.widgetPlacements(for: profile)
            #expect(page.first?.kind == .design)
            #expect(page.first?.size == .large)
        }
    }
}
