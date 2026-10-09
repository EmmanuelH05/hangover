import Foundation
import OpenIslandCore

/// How an answer typed in the island reaches the agent that asked.
enum AgentQuestionReplyRoute: Equatable, Sendable {
    /// The agent's hook holds its question open and the island's answer is
    /// handed back through it, typed text included.
    case bridge
    /// Nothing carries an answer from the island to this agent. It reads
    /// its answer in the terminal.
    case terminalOnly

    /// Claude Code and the tools built on it ask through a held permission
    /// hook, and OpenCode through its plugin. Both take typed text. Codex
    /// only reports that it is waiting, which leaves the island no way to
    /// hand it an answer.
    static func route(for tool: AgentTool) -> AgentQuestionReplyRoute {
        tool.isClaudeCodeFork || tool == .openCode ? .bridge : .terminalOnly
    }

    /// The route for the question a session is asking. One Claude Code
    /// keeps in the terminal, because an ask rule matches its question
    /// tool, has no way back from the island whatever the agent.
    static func route(for session: AgentSession) -> AgentQuestionReplyRoute {
        if session.questionPrompt?.requiresTerminalAnswer == true { return .terminalOnly }
        return route(for: session.tool)
    }
}

/// What the user has picked and typed on a question card and not sent yet.
struct AgentQuestionDraft: Equatable, Sendable {
    /// Picked option labels, by question text.
    var selections: [String: Set<String>] = [:]
    /// Text typed into an option's own field, by question and option.
    var freeformTexts: [String: String] = [:]
    /// Text typed into the card's reply field.
    var typedReply = ""

    var isEmpty: Bool {
        typedReply.isEmpty
            && selections.values.allSatisfy(\.isEmpty)
            && freeformTexts.values.allSatisfy(\.isEmpty)
    }
}

/// Half-typed replies, kept outside the views. A card that goes away with
/// the island comes back with what was typed in it.
struct AgentReplyDraftStore: Equatable, Sendable {
    private struct QuestionEntry: Equatable, Sendable {
        var promptID: UUID
        var draft: AgentQuestionDraft
    }

    private var questions: [String: QuestionEntry] = [:]
    private var completions: [String: String] = [:]

    var isEmpty: Bool { questions.isEmpty && completions.isEmpty }

    /// The draft for this session's question. A draft written for an
    /// earlier question of the same session does not count.
    func questionDraft(sessionID: String, promptID: UUID) -> AgentQuestionDraft {
        guard let entry = questions[sessionID], entry.promptID == promptID else {
            return AgentQuestionDraft()
        }
        return entry.draft
    }

    mutating func setQuestionDraft(_ draft: AgentQuestionDraft, sessionID: String, promptID: UUID) {
        if draft.isEmpty {
            if questions[sessionID]?.promptID == promptID { questions[sessionID] = nil }
        } else {
            questions[sessionID] = QuestionEntry(promptID: promptID, draft: draft)
        }
    }

    /// The reply being typed to a finished session.
    func completionDraft(sessionID: String) -> String {
        completions[sessionID] ?? ""
    }

    mutating func setCompletionDraft(_ text: String, sessionID: String) {
        completions[sessionID] = text.isEmpty ? nil : text
    }

    mutating func clear(sessionID: String) {
        questions[sessionID] = nil
        completions[sessionID] = nil
    }

    /// Drops drafts that have nothing left to answer: the question was
    /// answered or replaced, the finished session started working again, or
    /// the session is gone.
    mutating func prune(to sessions: [AgentSession]) {
        guard !isEmpty else { return }
        let byID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        questions = questions.filter { sessionID, entry in
            byID[sessionID]?.questionPrompt?.id == entry.promptID
        }
        completions = completions.filter { sessionID, _ in
            byID[sessionID]?.phase == .completed
        }
    }
}
