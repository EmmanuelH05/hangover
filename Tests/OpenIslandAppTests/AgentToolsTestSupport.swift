import Foundation
@testable import OpenIslandApp
import OpenIslandCore

/// Stands in for macOS in the shortcut tests. Nothing is registered with
/// the system, and a press only happens when a test calls `press`.
@MainActor
final class FakeHotkeyRegistrar: AgentHotkeyRegistering {
    private(set) var registered: [AgentHotkeyAction: AgentHotkeyCombo] = [:]
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0
    /// Error codes macOS answers with, by action.
    var failures: [AgentHotkeyAction: Int32] = [:]
    var system: Set<AgentHotkeyCombo> = []
    private var onPress: (@MainActor (AgentHotkeyAction, Date) -> Void)?

    func register(
        _ combos: [AgentHotkeyAction: AgentHotkeyCombo],
        onPress: @escaping @MainActor (AgentHotkeyAction, Date) -> Void
    ) -> [AgentHotkeyAction: AgentHotkeyRegistrationOutcome] {
        registerCalls += 1
        registered = [:]
        self.onPress = onPress

        var outcomes: [AgentHotkeyAction: AgentHotkeyRegistrationOutcome] = [:]
        for (action, combo) in combos {
            if let code = failures[action] {
                outcomes[action] = .failed(code: code)
            } else {
                registered[action] = combo
                outcomes[action] = .registered
            }
        }
        return outcomes
    }

    func unregisterAll() {
        unregisterCalls += 1
        registered = [:]
    }

    func systemShortcuts() -> Set<AgentHotkeyCombo> {
        system
    }

    func keyName(for keyCode: UInt16) -> String? {
        nil
    }

    /// A press of a registered shortcut at `time`. An unregistered one
    /// reaches no one, as on a real keyboard.
    func press(_ action: AgentHotkeyAction, at time: Date = .now) {
        guard registered[action] != nil else { return }
        onPress?(action, time)
    }
}

enum AgentToolsFixtures {
    static func approvalSession(
        id: String = "approval-session",
        tool: AgentTool = .claudeCode,
        request: PermissionRequest = PermissionRequest(
            title: "Allow Bash",
            summary: "Run swift test",
            affectedPath: "/tmp/project",
            primaryActionTitle: "Allow Once",
            secondaryActionTitle: "Deny",
            toolName: "Bash"
        ),
        updatedAt: Date = .now
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: "Claude · project",
            tool: tool,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Approve command",
            updatedAt: updatedAt,
            permissionRequest: request
        )
    }

    static func questionSession(
        id: String = "question-session",
        tool: AgentTool = .claudeCode,
        prompt: QuestionPrompt = QuestionPrompt(
            title: "Which database?",
            questions: [
                QuestionPromptItem(
                    question: "Which database?",
                    header: "Database",
                    options: [
                        QuestionOption(label: "SQLite"),
                        QuestionOption(label: "Other", allowsFreeform: true),
                    ]
                ),
            ]
        )
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: "Claude · project",
            tool: tool,
            attachmentState: .attached,
            phase: .waitingForAnswer,
            summary: "Question",
            updatedAt: .now,
            questionPrompt: prompt
        )
    }

    /// A private settings store for one test, held in memory, and the name
    /// its domain calls take.
    static func defaults() -> (defaults: UserDefaults, name: String) {
        (MemoryDefaults(), "agent-tools-tests")
    }
}
