import Foundation

/// One entry of `permissions.ask` in a Claude Code settings file: `Tool`
/// or `Tool(specifier)`.
///
/// Claude Code keeps its own prompt for a call such a rule matches. A hook
/// that answers "allow" is ignored for it, and one that answers "deny" is
/// honored. Open Island reads the rules only to know which requests it can
/// approve. It never writes them.
public struct ClaudeAskRule: Equatable, Sendable {
    /// The tool name as written. It can hold `*`.
    public var tool: String
    /// The text between the parentheses. Nil for a rule that names only a
    /// tool, which matches every call of it.
    public var specifier: String?

    public init(tool: String, specifier: String? = nil) {
        self.tool = tool
        self.specifier = specifier
    }

    /// Reads a rule as written in a settings file. Parentheses inside the
    /// specifier are part of it: it runs from the first `(` to the last `)`.
    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let open = trimmed.firstIndex(of: "("), trimmed.hasSuffix(")") else {
            guard !trimmed.contains("("), !trimmed.contains(")") else { return nil }
            self.init(tool: trimmed)
            return
        }

        let tool = trimmed[..<open].trimmingCharacters(in: .whitespaces)
        let inner = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)]
            .trimmingCharacters(in: .whitespaces)
        guard !tool.isEmpty else { return nil }

        // `Bash(*)` is `Bash`.
        let matchesEverything = inner.isEmpty || (inner == "*" && ClaudeAskRuleMatcher.shellTools.contains(tool))
        self.init(tool: tool, specifier: matchesEverything ? nil : inner)
    }
}

/// Whether an ask rule matches a tool call. Pure.
///
/// Built: a rule that names only a tool (with `*` in the name, and an MCP
/// server name for all of its tools), `Bash(...)` commands, `Tool(param:value)`
/// on a top-level input, `WebFetch(domain:...)` and `Agent(name)`.
///
/// Not built: the path patterns of `Read(...)` and `Edit(...)`. They follow
/// gitignore rules anchored at folders this app cannot tell from a hook. A
/// rule of a kind that is not built matches nothing here.
public enum ClaudeAskRuleMatcher {
    static let shellTools: Set<String> = ["Bash", "PowerShell"]
    /// Tools that take the name of a subagent as their specifier.
    private static let agentTools: Set<String> = ["Agent", "Task"]
    /// The main input of each tool. `Tool(param:value)` cannot name it.
    private static let primaryFields: Set<String> = ["command", "file_path", "path", "notebook_path", "url"]

    /// The first of `rules` that matches the call. A shell command is
    /// read apart once, however many rules there are.
    public static func firstMatch(
        in rules: [ClaudeAskRule],
        toolName: String,
        toolInput: ClaudeHookJSONValue?
    ) -> ClaudeAskRule? {
        guard !rules.isEmpty else { return nil }
        let reading = shellReading(toolName: toolName, toolInput: toolInput)
        return rules.first { matches($0, toolName: toolName, toolInput: toolInput, reading: reading) }
    }

    public static func matches(
        _ rule: ClaudeAskRule,
        toolName: String,
        toolInput: ClaudeHookJSONValue?
    ) -> Bool {
        matches(
            rule,
            toolName: toolName,
            toolInput: toolInput,
            reading: shellReading(toolName: toolName, toolInput: toolInput)
        )
    }

    /// The command of a shell call, read apart. Nil for another tool and
    /// for a call with no command.
    static func shellReading(toolName: String, toolInput: ClaudeHookJSONValue?) -> ClaudeBashCommandParts.Reading? {
        guard shellTools.contains(toolName),
              case let .object(fields)? = toolInput,
              case let .string(command)? = fields["command"] else {
            return nil
        }
        return ClaudeBashCommandParts.reading(of: command)
    }

    static func matches(
        _ rule: ClaudeAskRule,
        toolName: String,
        toolInput: ClaudeHookJSONValue?,
        reading: ClaudeBashCommandParts.Reading?
    ) -> Bool {
        guard toolNameMatches(rule.tool, toolName) else { return false }
        guard let specifier = rule.specifier else { return true }
        // Claude Code skips a rule that puts a specifier on an MCP tool.
        guard !rule.tool.hasPrefix("mcp__") else { return false }

        let input: [String: ClaudeHookJSONValue]
        if case let .object(fields)? = toolInput { input = fields } else { input = [:] }

        if let parameter = parameterMatch(specifier, input: input) { return parameter }

        if shellTools.contains(toolName) {
            guard let reading else { return false }
            return bashRule(specifier, matches: reading)
        }
        if toolName == "WebFetch" {
            guard case let .string(url)? = input["url"] else { return false }
            return webFetchRule(specifier, matchesURL: url)
        }
        if agentTools.contains(toolName) {
            guard case let .string(agent)? = input["subagent_type"] else { return false }
            return wildcard(specifier, matches: agent)
        }
        return false
    }

    // MARK: - Tool names

    /// A rule's tool name matches a whole tool name. `*` stands for any
    /// text, and the name of an MCP server covers every tool it has.
    static func toolNameMatches(_ pattern: String, _ toolName: String) -> Bool {
        if pattern == toolName { return true }
        if pattern.contains("*") { return wildcard(pattern, matches: toolName) }
        return pattern.hasPrefix("mcp__") && toolName.hasPrefix(pattern + "__")
    }

    // MARK: - Parameters

    /// `Tool(param:value)` matches a call that sets that top-level input to
    /// that value, with `*` for any text. Nil when the specifier does not
    /// name an input this call carries, which leaves it to the tool's own
    /// kind of specifier: `Bash(sudo:*)` is a command, not a parameter.
    static func parameterMatch(_ specifier: String, input: [String: ClaudeHookJSONValue]) -> Bool? {
        guard let colon = specifier.firstIndex(of: ":") else { return nil }
        let name = specifier[..<colon].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !primaryFields.contains(name), let value = input[name] else { return nil }

        let literal: String
        switch value {
        case let .string(text): literal = text
        case let .boolean(flag): literal = flag ? "true" : "false"
        case let .number(number):
            literal = number == number.rounded() && abs(number) < 1e15 ? String(Int64(number)) : String(number)
        case .object, .array, .null: return false
        }
        let pattern = specifier[specifier.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return wildcard(pattern, matches: literal)
    }

    // MARK: - Bash

    /// A Bash rule matches when it matches the whole command or any one
    /// command inside it.
    static func bashRule(_ pattern: String, matchesCommand command: String) -> Bool {
        bashRule(pattern, matches: ClaudeBashCommandParts.reading(of: command))
    }

    /// A command that could not be read apart counts as a match for every
    /// Bash rule: it may hold any command at all.
    static func bashRule(_ pattern: String, matches reading: ClaudeBashCommandParts.Reading) -> Bool {
        switch reading {
        case let .commands(commands):
            return commands.contains { bashPattern(pattern, matches: $0) }
        case .unreadable:
            return true
        }
    }

    /// One Bash rule against one command.
    /// - No `*`: the exact command.
    /// - `*` stands for any text, spaces too, anywhere in the rule.
    /// - `prefix:*` at the end is `prefix *`.
    /// - A rule that ends in ` *`, with no other `*`, also matches the bare
    ///   command: `ls *` matches `ls` and `ls -la`, and not `lsof`.
    static func bashPattern(_ rawPattern: String, matches command: String) -> Bool {
        var pattern = rawPattern.trimmingCharacters(in: .whitespaces)
        if pattern.hasSuffix(":*") {
            pattern = String(pattern.dropLast(2)) + " *"
        }
        let text = command.trimmingCharacters(in: .whitespacesAndNewlines)

        guard pattern.contains("*") else { return pattern == text }

        if pattern.hasSuffix(" *"), !pattern.dropLast(2).contains("*") {
            let prefix = String(pattern.dropLast(2))
            return text == prefix || text.hasPrefix(prefix + " ")
        }
        return wildcard(pattern, matches: text)
    }

    // MARK: - WebFetch

    /// `domain:host` against the host of the fetched URL. Case does not
    /// count and a trailing dot is dropped. A bare `*` is every host, a
    /// leading `*.` is any subdomain at any depth and not the host itself,
    /// and a `*` anywhere else stands for text between two dots.
    static func webFetchRule(_ specifier: String, matchesURL url: String) -> Bool {
        let prefix = "domain:"
        guard specifier.lowercased().hasPrefix(prefix),
              let host = URLComponents(string: url.trimmingCharacters(in: .whitespaces))?.host else {
            return false
        }
        func normalized(_ text: String) -> String {
            let lowered = text.trimmingCharacters(in: .whitespaces).lowercased()
            return lowered.hasSuffix(".") ? String(lowered.dropLast()) : lowered
        }
        let rule = normalized(String(specifier.dropFirst(prefix.count)))
        let name = normalized(host)
        guard !rule.isEmpty, !name.isEmpty else { return false }
        if rule == "*" { return true }

        var labels = rule
        var body = "^"
        if labels.hasPrefix("*.") {
            body += "(?:[^.]+\\.)+"
            labels = String(labels.dropFirst(2))
        }
        body += labels
            .split(separator: "*", omittingEmptySubsequences: false)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: "[^.]*")
        body += "$"
        return name.range(of: body, options: .regularExpression) != nil
    }

    // MARK: - Wildcards

    /// `*` stands for any run of characters, an empty one too. Everything
    /// else is itself, and the pattern covers the whole text.
    static func wildcard(_ pattern: String, matches text: String) -> Bool {
        let pattern = Array(pattern)
        let text = Array(text)
        var patternIndex = 0
        var textIndex = 0
        var starIndex: Int?
        var resumeIndex = 0

        while textIndex < text.count {
            if patternIndex < pattern.count, pattern[patternIndex] == "*" {
                starIndex = patternIndex
                resumeIndex = textIndex
                patternIndex += 1
            } else if patternIndex < pattern.count, pattern[patternIndex] == text[textIndex] {
                patternIndex += 1
                textIndex += 1
            } else if let star = starIndex {
                // Let the last `*` take one more character and try again.
                patternIndex = star + 1
                resumeIndex += 1
                textIndex = resumeIndex
            } else {
                return false
            }
        }
        while patternIndex < pattern.count, pattern[patternIndex] == "*" { patternIndex += 1 }
        return patternIndex == pattern.count
    }
}
