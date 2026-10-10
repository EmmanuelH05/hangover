import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// An answer that arrives after its request is over, from a device or a
/// card that is closing, must not record a decision nobody could make.
@MainActor
@Suite struct LateApprovalAnswerTests {
    private static func session(_ phase: SessionPhase) -> AgentSession {
        AgentSession(
            id: "late-answer",
            title: "Claude · app",
            tool: .claudeCode,
            attachmentState: .attached,
            phase: phase,
            summary: "Working",
            updatedAt: .now
        )
    }

    @Test func aDenialForASessionThatIsNoLongerWaitingChangesNothing() {
        let model = AppModel(defaults: MemoryDefaults())
        model.nook.presentRingLight = { _ in }
        model.state = SessionState(sessions: [Self.session(.running)])

        model.approvePermission(for: "late-answer", approved: false)
        model.approvePermission(for: "late-answer", action: .deny)

        #expect(model.state.session(id: "late-answer")?.phase == .running)
        #expect(model.state.session(id: "late-answer")?.summary == "Working")
    }

    @Test func anApprovalForASessionThatIsNoLongerWaitingChangesNothing() {
        let model = AppModel(defaults: MemoryDefaults())
        model.nook.presentRingLight = { _ in }
        model.state = SessionState(sessions: [Self.session(.completed)])

        model.approvePermission(for: "late-answer", approved: true)
        model.approvePermission(for: "late-answer", action: .allowOnce)

        #expect(model.state.session(id: "late-answer")?.phase == .completed)
        #expect(model.state.session(id: "late-answer")?.summary == "Working")
    }
}
