import Foundation

extension ClaudeHookPayload {
    /// What a PostToolUse hook proves about the tool that just ran: its
    /// name and, from the tool's own input, the file it wrote or the shell
    /// command it ran. The values are taken whole from the hook payload.
    var finishedTool: AgentToolFinish? {
        guard let name = toolName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }
        var finish = AgentToolFinish(toolName: name)
        guard case let .object(input) = toolInput else { return finish }

        if case let .string(path)? = input["file_path"] ?? input["notebook_path"], !path.isEmpty {
            finish.filePath = path
        }
        if case let .string(command)? = input["command"], !command.isEmpty {
            finish.command = command
        }
        if case .boolean(true)? = input["run_in_background"] {
            finish.ranInBackground = true
        }
        return finish
    }
}

extension CodexHookPayload {
    /// What Codex's PostToolUse hook proves: the shell command that ran.
    /// Codex fires its tool hooks for shell commands only.
    var finishedTool: AgentToolFinish? {
        guard let command = commandText, !command.isEmpty else { return nil }
        let name = toolName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return AgentToolFinish(toolName: name.isEmpty ? "Bash" : name, command: command)
    }
}
