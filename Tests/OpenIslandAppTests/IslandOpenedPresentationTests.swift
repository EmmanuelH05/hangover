import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// The close snapshot keeps a copy of the notification card's session, so the
/// card does not change identity or turn into the list while it fades out.
@MainActor
@Suite(.serialized)
struct IslandOpenedPresentationTests {
    private func approvalSession(id: String = "session-1") -> AgentSession {
        var session = AgentSession(
            id: id,
            title: "Claude · project",
            tool: .claudeCode,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Approve edit",
            updatedAt: .now,
            permissionRequest: PermissionRequest(
                title: "Edit",
                summary: "file.swift",
                affectedPath: "/tmp/file.swift"
            )
        )
        session.isProcessAlive = true
        return session
    }

    /// An open island showing the approval card for `session-1`.
    private func openNotificationModel() -> AppModel {
        let model = AppModel()
        model.state = SessionState(sessions: [approvalSession()])
        model.notchStatus = .opened
        model.notchOpenReason = .notification
        model.islandSurface = .sessionList(actionableSessionID: "session-1")
        return model
    }

    @Test
    func livePresentationCarriesTheCardSession() {
        let model = openNotificationModel()

        let session = model.openedPresentation.session

        #expect(session?.id == "session-1")
        #expect(session?.phase == .waitingForApproval)
        #expect(session?.permissionRequest != nil)
    }

    @Test
    func livePresentationFollowsTheSessionWhileOpen() {
        let model = openNotificationModel()

        model.state.resolvePermission(sessionID: "session-1", resolution: .allowOnce())

        // Open, so the presentation is live and shows the new state.
        #expect(model.openedPresentation.session?.phase == .running)
        #expect(model.openedPresentation.session?.permissionRequest == nil)
    }

    @Test
    func presentationHasNoSessionWhenTheSurfaceHasNone() {
        let model = openNotificationModel()
        model.islandSurface = .sessionList()
        model.notchOpenReason = .click

        #expect(model.openedPresentation.session == nil)
    }

    @Test
    func closingCardKeepsItsSessionWhenApprovalIsDenied() {
        let model = openNotificationModel()

        // Closes the card, then resolves the permission in the same turn.
        model.approvePermission(for: "session-1", action: .deny)

        #expect(model.notchStatus == .closed)
        // The live session moved on (denied, so completed with no request).
        #expect(model.state.session(id: "session-1")?.phase == .completed)
        #expect(model.state.session(id: "session-1")?.permissionRequest == nil)
        // The fading card still has the approval it was showing.
        let shown = model.openedPresentation.session
        #expect(model.openedPresentation.isNotificationMode)
        #expect(shown?.id == "session-1")
        #expect(shown?.phase == .waitingForApproval)
        #expect(shown?.permissionRequest != nil)
    }

    @Test
    func closingCardKeepsItsSessionWhenTheSessionIsDismissed() {
        let model = openNotificationModel()

        // Dismissing closes the card before the session is ended.
        model.dismissSession("session-1")

        #expect(model.notchStatus == .closed)
        #expect(model.state.session(id: "session-1")?.isSessionEnded == true)
        let shown = model.openedPresentation.session
        #expect(model.openedPresentation.isNotificationMode)
        #expect(shown?.id == "session-1")
        #expect(shown?.phase == .waitingForApproval)
        #expect(shown?.isSessionEnded == false)
    }

    @Test
    func closingCardKeepsItsSessionWhenTheSessionIsRemoved() {
        let model = openNotificationModel()

        model.notchClose()
        model.state = SessionState(sessions: [])

        #expect(model.state.session(id: "session-1") == nil)
        #expect(model.openedPresentation.isNotificationMode)
        #expect(model.openedPresentation.session?.id == "session-1")
        #expect(model.openedPresentation.session?.phase == .waitingForApproval)
    }

    @Test
    func aSecondCloseKeepsTheFirstSessionCopy() {
        let model = openNotificationModel()

        model.notchClose()
        model.state.resolvePermission(sessionID: "session-1", resolution: .allowOnce())
        model.notchClose()

        #expect(model.openedPresentation.session?.phase == .waitingForApproval)
    }

    @Test
    func openingAgainDropsTheSessionCopy() {
        let model = openNotificationModel()
        model.notchClose()
        #expect(model.openedPresentation.session != nil)

        model.notchOpen(reason: .click)

        // Live again: the plain list has no card session.
        #expect(model.notchStatus == .opened)
        #expect(model.openedPresentation.session == nil)
    }

    @Test
    func presentationsWithDifferentSessionsAreNotEqual() {
        let model = openNotificationModel()
        let before = model.openedPresentation

        model.state.resolvePermission(sessionID: "session-1", resolution: .allowOnce())

        #expect(model.openedPresentation != before)
        #expect(model.openedPresentation.surface == before.surface)
    }
}
