import CoreGraphics
import Foundation
import OpenIslandCore

struct IslandDebugSnapshot {
    let title: String
    let summary: String
    let previewHeight: CGFloat
    let notchStatus: NotchStatus
    let notchOpenReason: NotchOpenReason?
    let islandSurface: IslandSurface
    let sessions: [AgentSession]
    let selectedSessionID: String?
}

enum IslandDebugScenario: String, CaseIterable, Identifiable {
    case closed
    case sessionList
    case approvalCard
    case questionCard
    case completionCard
    case longCompletionCard
    case closedApproval
    case closedQuestion
    case closedRunning
    case closedIdle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .closed:
            "Closed Notch"
        case .sessionList:
            "Session List"
        case .approvalCard:
            "Approval Card"
        case .questionCard:
            "Question Card"
        case .completionCard:
            "Completion Card"
        case .longCompletionCard:
            "Long Completion Card"
        case .closedApproval:
            "Closed Notch, Approval"
        case .closedQuestion:
            "Closed Notch, Question"
        case .closedRunning:
            "Closed Notch, Running"
        case .closedIdle:
            "Closed Notch, Idle"
        }
    }

    var summary: String {
        switch self {
        case .closed:
            "Collapsed idle/running notch with live count and attention affordance."
        case .sessionList:
            "Manual expanded list with running, active, and inactive session rows."
        case .approvalCard:
            "Auto-expanded permission surface with approve and deny actions."
        case .questionCard:
            "Auto-expanded question surface with selectable answer buttons."
        case .completionCard:
            "Auto-expanded finished-task reminder surface after a turn completes."
        case .longCompletionCard:
            "Long finished-task reply stays inside the card and scrolls internally."
        case .closedApproval:
            "Collapsed notch while one session waits for approval (orange status glow)."
        case .closedQuestion:
            "Collapsed notch while one session waits for an answer (yellow status glow)."
        case .closedRunning:
            "Collapsed notch while a session is running (faint blue status glow)."
        case .closedIdle:
            "Collapsed notch with sessions but none running or waiting (no status glow)."
        }
    }

    func snapshot(at now: Date = .now) -> IslandDebugSnapshot {
        switch self {
        case .closed:
            let sessions = DebugSessionFactory.listSessions(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 78,
                notchStatus: .closed,
                notchOpenReason: nil,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: sessions.first?.id
            )

        case .sessionList:
            let sessions = DebugSessionFactory.listSessions(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 430,
                notchStatus: .opened,
                notchOpenReason: .click,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: sessions.first?.id
            )

        case .approvalCard:
            let session = DebugSessionFactory.approvalSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 330,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .questionCard:
            let session = DebugSessionFactory.questionSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 270,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .completionCard:
            let session = DebugSessionFactory.completionSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 250,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .longCompletionCard:
            let session = DebugSessionFactory.longCompletionSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 290,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .closedApproval:
            let session = DebugSessionFactory.approvalSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 78,
                notchStatus: .closed,
                notchOpenReason: nil,
                islandSurface: .sessionList(),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .closedQuestion:
            let session = DebugSessionFactory.questionSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 78,
                notchStatus: .closed,
                notchOpenReason: nil,
                islandSurface: .sessionList(),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .closedRunning:
            let sessions = DebugSessionFactory.listSessions(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 78,
                notchStatus: .closed,
                notchOpenReason: nil,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: sessions.first?.id
            )

        case .closedIdle:
            let sessions = DebugSessionFactory.listSessions(now: now).filter { $0.phase == .completed }
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 78,
                notchStatus: .closed,
                notchOpenReason: nil,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: sessions.first?.id
            )
        }
    }
}

private enum DebugSessionFactory {
    static func listSessions(now: Date) -> [AgentSession] {
        [
            runningSession(now: now),
            recentCompletedSession(now: now),
            inactiveSession(
                id: "session-claude-research",
                workspace: "claude-research",
                initialPrompt: "I care more about the fetching part. I want to show my usage live in other apps.",
                latestPrompt: "Why check Cursor's docs? What does Cursor have to do with this?",
                assistant: "I would not pick by 'oldest'. Oldest is not the lightest or the best fit for this task.",
                age: 27 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-personal",
                workspace: "Personal",
                initialPrompt: "[Image #1] I took 3 screenshots. These are the models I can use in Cursor right now.",
                latestPrompt: "[Image #1] I took 3 screenshots. These are the models I can use in Cursor right now.",
                assistant: "Strictly speaking, the models in this image are not the ones the `voice-input` app should pick…",
                age: 32 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-open-agent-sdk",
                workspace: "open-agent-sdk",
                initialPrompt: "OK, do you need to open a PR now?",
                latestPrompt: "Go ahead and open the PR.",
                assistant: "The PR is up:",
                age: 60 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-voice-input",
                workspace: "voice-input",
                initialPrompt: "Look at the voice-input repo, with a focus on model choice.",
                latestPrompt: "Strictly speaking, which model should it use?",
                assistant: "If the goal is light and real time, I would not map it straight onto an existing Cursor plan.",
                age: 78 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-agents",
                workspace: "agents",
                initialPrompt: "Give me your branch and worktree.",
                latestPrompt: "Are you restarting first?",
                assistant: "Restarted. The new dev process is running now.",
                age: 92 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-claude",
                workspace: "claude-code",
                initialPrompt: "Let's make the whole notch background pure black first.",
                latestPrompt: "Remove the empty space at the bottom.",
                assistant: "The opened height now fits its content.",
                age: 118 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-hooks",
                workspace: "hooks",
                initialPrompt: "If I want to watch Claude Code usage live, how should I do it?",
                latestPrompt: "What about showing it in another app?",
                assistant: "The code already has a few more direct paths.",
                age: 130 * 60,
                now: now
            ),
        ]
    }

    static func notificationSessions(lead: AgentSession, now: Date) -> [AgentSession] {
        var sessions = listSessions(now: now)
        if sessions.isEmpty {
            return [lead]
        }
        sessions[0] = lead
        return sessions
    }

    static func runningSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-running",
            title: "Codex · open-island",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .running,
            summary: "Reading IslandPanelView.swift and AppModel.swift",
            updatedAt: now.addingTimeInterval(-45),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/Personal/open-island",
                workingDirectory: "/Users/demo/Personal/open-island",
                terminalSessionID: "ghostty-running"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "Turn DEV into a full debug page. I need to check these card UIs reliably.",
                lastUserPrompt: "Some of the earlier changes were wrong too. Redo them.",
                lastAssistantMessage: "Reading the current notch state and event routing to split the alert state out of the session list.",
                currentTool: "exec_command",
                currentCommandPreview: "sed -n '1,260p' Sources/OpenIslandApp/Views/SettingsView.swift"
            )
        )
    }

    static func recentCompletedSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-recent",
            title: "Codex · open-agent-sdk",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            summary: "The session list now matches the original island more closely.",
            updatedAt: now.addingTimeInterval(-3 * 60),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-agent-sdk",
                paneTitle: "codex ~/Personal/open-agent-sdk",
                workingDirectory: "/Users/demo/Personal/open-agent-sdk",
                terminalSessionID: "ghostty-recent"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "Read this paper https://arxiv.org/html/2603.28052",
                lastUserPrompt: "Read this paper https://arxiv.org/html/2603.28052v1 It feels close to the agent we are building.",
                lastAssistantMessage: "Done. I pulled out the key differences that relate to autoresearch."
            )
        )
    }

    static func inactiveSession(
        id: String,
        workspace: String,
        initialPrompt: String,
        latestPrompt: String,
        assistant: String,
        age: TimeInterval,
        now: Date
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: "Codex · \(workspace)",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            summary: assistant,
            updatedAt: now.addingTimeInterval(-age),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: workspace,
                paneTitle: "codex ~/Personal/\(workspace)",
                workingDirectory: "/Users/demo/Personal/\(workspace)",
                terminalSessionID: "ghostty-\(id)"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: initialPrompt,
                lastUserPrompt: latestPrompt,
                lastAssistantMessage: assistant
            )
        )
    }

    static func approvalSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-approval",
            title: "Codex · open-island",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Allow exec_command to rewrite SettingsView.swift?",
            updatedAt: now.addingTimeInterval(-20),
            permissionRequest: PermissionRequest(
                title: "Approve file rewrite",
                summary: "Allow exec_command to rewrite SettingsView.swift?",
                affectedPath: "Sources/OpenIslandApp/Views/SettingsView.swift",
                primaryActionTitle: "Allow",
                secondaryActionTitle: "Deny"
            ),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/Personal/open-island",
                workingDirectory: "/Users/demo/Personal/open-island",
                terminalSessionID: "ghostty-approval"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "Next I plan to fill in a few more features.",
                lastUserPrompt: "askUserQuestion and permission approvals, I want those in our island too.",
                lastAssistantMessage: "Ready to rewrite the DEV page. File changes need approval.",
                currentTool: "exec_command",
                currentCommandPreview: "head -5000 /Users/demo/Personal/claude-research/extracts/claude-bun-2.1.81-v3/islands/000_cli.js.txt"
            )
        )
    }

    static func questionSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-question",
            title: "Codex · open-island",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .waitingForAnswer,
            summary: "Should this alert collapse on its own?",
            updatedAt: now.addingTimeInterval(-18),
            questionPrompt: QuestionPrompt(
                title: "Which authentication method should we use?",
                questions: [
                    QuestionPromptItem(
                        question: "Which authentication method should we use?",
                        header: "Auth",
                        options: [
                            QuestionOption(label: "JWT tokens", description: "Stateless, scalable"),
                            QuestionOption(label: "Session cookies", description: "Traditional approach"),
                            QuestionOption(label: "OAuth 2.0", description: "Third-party auth"),
                            QuestionOption(label: "Other", description: "", allowsFreeform: true),
                        ]
                    )
                ]
            ),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/Personal/open-island",
                workingDirectory: "/Users/demo/Personal/open-island",
                terminalSessionID: "ghostty-question"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "The original product looks like one notch surface with several content surfaces.",
                lastUserPrompt: "How should we do it?",
                lastAssistantMessage: "I suggest splitting approvalCard, questionCard and completionCard into separate surfaces first."
            )
        )
    }

    static func completionSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-completion",
            title: "Codex · open-island",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            summary: "The DEV page now runs in mock-driven card debug mode.",
            updatedAt: now.addingTimeInterval(-15),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/Personal/open-island",
                workingDirectory: "/Users/demo/Personal/open-island",
                terminalSessionID: "ghostty-completion"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "This time I may really need some mocks to check these card UIs.",
                lastUserPrompt: "We can turn DEV into a full debug page.",
                lastAssistantMessage: "The plan file is written. How are your hooks firing?"
            )
        )
    }

    static func longCompletionSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-completion-long",
            title: "Codex · open-island",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            summary: "The README commit is done. Long replies should now scroll inside the card.",
            updatedAt: now.addingTimeInterval(-45),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/Personal/open-island",
                workingDirectory: "/Users/demo/Personal/open-island",
                terminalSessionID: "ghostty-completion-long"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "Commit this README too, then paste me the result.",
                lastUserPrompt: "Also confirm the current working tree and checks.",
                lastAssistantMessage: """
The existing changes to [README.md](/Users/demo/open-island/README.md) are committed on their own as `f196316`, message `docs: update readme tagline`.

No tests ran this round because it was only a copy change. The working tree is clean, and `main` is `ahead 6` of `origin/main`.

If you want me to keep going, I suggest moving the work to its own worktree, which keeps it clear of parallel changes on the shared `main`.

Next I will check the repo state, create a worktree and branch from `origin/main`, and fix this style issue there with full checks.
"""
            )
        )
    }
}
