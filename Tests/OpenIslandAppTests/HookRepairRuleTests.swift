import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// Startup repair re-runs an install. It may only do that for an agent the
/// user asked to have, which is what the welcome tour tells them.
struct HookRepairRuleTests {
    @Test func anAgentTheUserAskedForIsRepaired() {
        #expect(HookInstallationCoordinator.mayRepair(intent: .installed, hasRepairableIssues: true))
    }

    @Test func anAgentNobodyChoseIsLeftAlone() {
        #expect(HookInstallationCoordinator.mayRepair(intent: .untouched, hasRepairableIssues: true) == false)
    }

    @Test func anAgentTheUserRemovedIsNeverPutBack() {
        #expect(HookInstallationCoordinator.mayRepair(intent: .uninstalled, hasRepairableIssues: true) == false)
    }

    @Test func aHealthyAgentIsNotTouched() {
        for intent in AgentHookIntent.allCases {
            #expect(HookInstallationCoordinator.mayRepair(intent: intent, hasRepairableIssues: false) == false)
        }
    }
}
