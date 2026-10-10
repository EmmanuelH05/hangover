import Testing
@testable import OpenIslandApp

/// The tour holds the island open only while Hangover is the active app.
/// A demo run has nobody at the Mac to bring it forward.
struct DemoPresenceTests {
    @Test func theDemoModeAlwaysCountsAsActiveAndAnythingElseFollowsTheApp() {
        #expect(DemoPresence.appIsActive(real: false, isDemo: true))
        #expect(DemoPresence.appIsActive(real: true, isDemo: true))
        #expect(DemoPresence.appIsActive(real: true, isDemo: false))
        #expect(!DemoPresence.appIsActive(real: false, isDemo: false))
    }
}
