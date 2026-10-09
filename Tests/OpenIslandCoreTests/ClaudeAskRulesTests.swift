import Foundation
import Testing
@testable import OpenIslandCore

/// The reading and matching of Claude Code's ask rules. Pure: nothing here
/// touches a file.
struct ClaudeAskRulesTests {
    private static func bash(_ command: String, extra: [String: ClaudeHookJSONValue] = [:]) -> ClaudeHookJSONValue {
        var fields = extra
        fields["command"] = .string(command)
        return .object(fields)
    }

    private static func matches(_ rule: String, tool: String = "Bash", input: ClaudeHookJSONValue?) -> Bool {
        guard let parsed = ClaudeAskRule(rule) else { return false }
        return ClaudeAskRuleMatcher.matches(parsed, toolName: tool, toolInput: input)
    }

    // MARK: Reading a rule

    @Test
    func aRuleIsAToolNameWithAnOptionalSpecifier() {
        #expect(ClaudeAskRule("Bash") == ClaudeAskRule(tool: "Bash"))
        #expect(ClaudeAskRule("  WebFetch ") == ClaudeAskRule(tool: "WebFetch"))
        #expect(ClaudeAskRule("Bash(rm -rf *)") == ClaudeAskRule(tool: "Bash", specifier: "rm -rf *"))
        #expect(ClaudeAskRule("Bash(sudo:*)") == ClaudeAskRule(tool: "Bash", specifier: "sudo:*"))
        #expect(ClaudeAskRule("mcp__*") == ClaudeAskRule(tool: "mcp__*"))
    }

    @Test
    func parenthesesInsideTheSpecifierBelongToIt() {
        #expect(ClaudeAskRule("Bash(echo $(date) *)") == ClaudeAskRule(tool: "Bash", specifier: "echo $(date) *"))
        #expect(ClaudeAskRule("Edit(./Finance (2024)/**)") == ClaudeAskRule(tool: "Edit", specifier: "./Finance (2024)/**"))
    }

    @Test
    func bashWithOnlyAStarIsTheWholeTool() {
        #expect(ClaudeAskRule("Bash(*)") == ClaudeAskRule(tool: "Bash"))
        #expect(ClaudeAskRule("Bash()") == ClaudeAskRule(tool: "Bash"))
        // For another tool a lone star is a specifier of its own kind.
        #expect(ClaudeAskRule("Read(*)") == ClaudeAskRule(tool: "Read", specifier: "*"))
    }

    @Test
    func textThatIsNotARuleIsRefused() {
        #expect(ClaudeAskRule("") == nil)
        #expect(ClaudeAskRule("   ") == nil)
        #expect(ClaudeAskRule("(rm *)") == nil)
        #expect(ClaudeAskRule("Bash(rm *") == nil)
        #expect(ClaudeAskRule("Bash)") == nil)
    }

    // MARK: Bash rules

    /// The shapes in the list this was built for, each against commands it
    /// must catch and near misses it must leave alone.
    @Test(arguments: [
        // A trailing " *" also matches the bare command, and needs the space.
        ("Bash(launchctl *)", "launchctl version", true),
        ("Bash(launchctl *)", "launchctl", true),
        ("Bash(launchctl *)", "launchctlx version", false),
        ("Bash(launchctl *)", "echo launchctl version", false),
        ("Bash(rm -rf *)", "rm -rf build", true),
        ("Bash(rm -rf *)", "rm -rf", true),
        ("Bash(rm -rf *)", "rm -r build", false),
        ("Bash(rm -rf *)", "rm -rfv build", false),
        ("Bash(rm -fr *)", "rm -fr build", true),
        ("Bash(rm -fr *)", "rm -rf build", false),
        // The older "prefix:*" form is the same rule.
        ("Bash(rm -rf:*)", "rm -rf build", true),
        ("Bash(rm -rf:*)", "rm -rf", true),
        ("Bash(rm -rf:*)", "rm -r build", false),
        ("Bash(sudo:*)", "sudo ls", true),
        ("Bash(sudo:*)", "sudoku", false),
        ("Bash(sudo *)", "sudo launchctl list", true),
        ("Bash(git reset --hard *)", "git reset --hard HEAD~1", true),
        ("Bash(git reset --hard *)", "git reset --hard", true),
        ("Bash(git reset --hard *)", "git reset --soft HEAD~1", false),
        ("Bash(git reset --hard *)", "git -C . reset --hard", false),
        ("Bash(git clean *)", "git clean -fd", true),
        ("Bash(chmod -R *)", "chmod -R 755 .", true),
        ("Bash(chmod -R *)", "chmod 755 file", false),
        // No star is one exact command.
        ("Bash(npm run build)", "npm run build", true),
        ("Bash(npm run build)", "npm run build --watch", false),
        // A star anywhere stands for any text.
        ("Bash(ls*)", "lsof", true),
        ("Bash(ls*)", "ls", true),
        ("Bash(* --version)", "node --version", true),
        ("Bash(* --version)", "node -v", false),
        ("Bash(* --help *)", "npm --help x", true),
        ("Bash(* --help *)", "npm --help", false),
        ("Bash(git log * main)", "git log --oneline main", true),
        ("Bash(git log * main)", "git log main", false),
        // ":*" only counts at the end.
        ("Bash(git:* push)", "git push", false),
        // The whole tool.
        ("Bash", "anything at all", true),
        ("Bash(*)", "anything at all", true),
    ])
    func aBashRuleAgainstOneCommand(rule: String, command: String, expected: Bool) {
        #expect(Self.matches(rule, input: Self.bash(command)) == expected, "\(rule) against \(command)")
    }

    @Test(arguments: [
        ("cd /tmp && launchctl list", true),
        ("ls; launchctl list", true),
        ("true || launchctl list", true),
        ("launchctl list | grep island", true),
        ("sleep 5 & launchctl list", true),
        ("ls\nlaunchctl list", true),
        ("make 2>&1 |& launchctl list", true),
        // Inside a subshell, a substitution, backticks and a loop body.
        ("(cd /tmp && launchctl list)", true),
        ("echo \"$(launchctl list)\"", true),
        ("echo `launchctl list`", true),
        ("for s in a b; do launchctl kickstart $s; done", true),
        ("if true; then launchctl list; fi", true),
        // Past a leading assignment and the wrappers Claude Code strips.
        ("FOO=bar launchctl list", true),
        ("FOO=\"a b\" BAR=1 launchctl list", true),
        ("timeout 5 launchctl list", true),
        ("nohup nice -n 10 launchctl list", true),
        ("command launchctl list", true),
        ("ls | xargs launchctl", true),
        // Text that only mentions the command runs nothing.
        ("echo 'run launchctl list; done'", false),
        ("echo \"launchctl list\"", false),
        ("ls # ; launchctl list", false),
        ("command -v launchctl", false),
        ("ls | xargs -n1 launchctl", false),
        ("ls 2>&1", false),
    ])
    func aBashRuleLooksAtEveryCommandInTheText(command: String, expected: Bool) {
        #expect(Self.matches("Bash(launchctl *)", input: Self.bash(command)) == expected, "\(command)")
    }

    @Test
    func theTextOfAHeredocIsNotACommand() {
        let commit = """
        git commit -m "$(cat <<'EOF'
        rm -rf the old cache
        launchctl list is gone too
        EOF
        )"
        """
        #expect(!Self.matches("Bash(rm -rf *)", input: Self.bash(commit)))
        #expect(!Self.matches("Bash(launchctl *)", input: Self.bash(commit)))
        #expect(Self.matches("Bash(git commit *)", input: Self.bash(commit)))

        let script = "cat <<-END > notes.txt\n\trm -rf x\n\tEND\nrm -rf build"
        #expect(Self.matches("Bash(rm -rf *)", input: Self.bash(script)))
        #expect(ClaudeBashCommandParts.parts(of: script) == ["cat <<-END > notes.txt", "rm -rf build"])
    }

    @Test
    func aHereStringHasNoLinesAfterIt() {
        let parts = ClaudeBashCommandParts.parts(of: "grep x <<< \"text\"\nlaunchctl list")
        #expect(parts == ["grep x <<< \"text\"", "launchctl list"])
    }

    @Test
    func aCommandIsCutAtItsSeparatorsAndNotInsideQuotes() {
        #expect(ClaudeBashCommandParts.parts(of: "a && b || c; d | e") == ["a", "b", "c", "d", "e"])
        #expect(ClaudeBashCommandParts.parts(of: "make 2>&1 | tee log") == ["make 2>&1", "tee log"])
        #expect(ClaudeBashCommandParts.parts(of: "run &> out.txt") == ["run &> out.txt"])
        #expect(ClaudeBashCommandParts.parts(of: "echo 'a; b' \"c && d\"") == ["echo 'a; b' \"c && d\""])
        #expect(ClaudeBashCommandParts.parts(of: "echo a\\;b") == ["echo a\\;b"])
    }

    @Test
    func theWholeCommandComesFirstAndNothingIsListedTwice() {
        #expect(ClaudeBashCommandParts.candidates(in: "  ls -la  ") == ["ls -la"])
        #expect(ClaudeBashCommandParts.candidates(in: "") == [])
        let candidates = ClaudeBashCommandParts.candidates(in: "FOO=1 timeout 5 rm -rf x && ls")
        #expect(candidates.first == "FOO=1 timeout 5 rm -rf x && ls")
        #expect(candidates.contains("rm -rf x"))
        #expect(candidates.contains("ls"))
        #expect(Set(candidates).count == candidates.count)
    }

    // MARK: Other tools

    @Test
    func aRuleForAnotherToolDoesNotMatch() {
        let input = Self.bash("rm -rf build")
        #expect(!Self.matches("Write", input: input))
        #expect(!Self.matches("Read(./.env)", input: input))
        #expect(!Self.matches("PowerShell(rm -rf *)", input: input))
        #expect(Self.matches("Write", tool: "Write", input: .object(["file_path": .string("/tmp/a.txt")])))
    }

    @Test
    func aToolNameCanHoldAStarAndAnMCPServerCoversItsTools() {
        #expect(Self.matches("*", tool: "Bash", input: nil))
        #expect(Self.matches("mcp__*", tool: "mcp__puppeteer__navigate", input: nil))
        #expect(!Self.matches("mcp__*", tool: "Bash", input: nil))
        #expect(Self.matches("mcp__puppeteer", tool: "mcp__puppeteer__navigate", input: nil))
        #expect(Self.matches("mcp__puppeteer__*", tool: "mcp__puppeteer__navigate", input: nil))
        #expect(Self.matches("mcp__puppeteer__navigate", tool: "mcp__puppeteer__navigate", input: nil))
        #expect(!Self.matches("mcp__puppet", tool: "mcp__puppeteer__navigate", input: nil))
        #expect(!Self.matches("mcp__other", tool: "mcp__puppeteer__navigate", input: nil))
        // Claude Code skips a specifier on an MCP tool.
        #expect(!Self.matches("mcp__puppeteer__navigate(url:*)", tool: "mcp__puppeteer__navigate", input: .object(["url": .string("x")])))
    }

    @Test
    func aParameterRuleMatchesATopLevelInputThatIsSet() {
        let background = Self.bash("npm test", extra: ["run_in_background": .boolean(true)])
        #expect(Self.matches("Bash(run_in_background:true)", input: background))
        #expect(Self.matches("Bash(run_in_background : *)", input: background))
        #expect(!Self.matches("Bash(run_in_background:false)", input: background))
        // An input the call leaves out is never matched.
        #expect(!Self.matches("Bash(run_in_background:true)", input: Self.bash("npm test")))

        let agent: ClaudeHookJSONValue = .object(["subagent_type": .string("Explore"), "model": .string("opus")])
        #expect(Self.matches("Agent(model:opus)", tool: "Agent", input: agent))
        #expect(!Self.matches("Agent(model:sonnet)", tool: "Agent", input: agent))
        #expect(Self.matches("Agent(Explore)", tool: "Agent", input: agent))
        #expect(!Self.matches("Agent(Plan)", tool: "Agent", input: agent))

        // The main input of a tool cannot be named this way.
        #expect(!Self.matches("Bash(command:rm *)", input: Self.bash("rm -rf x")))
    }

    @Test(arguments: [
        ("WebFetch(domain:example.com)", "https://example.com/page", true),
        ("WebFetch(domain:example.com)", "https://EXAMPLE.com./page", true),
        ("WebFetch(domain:example.com)", "https://api.example.com/page", false),
        ("WebFetch(domain:*.example.com)", "https://api.example.com", true),
        ("WebFetch(domain:*.example.com)", "https://a.b.example.com", true),
        ("WebFetch(domain:*.example.com)", "https://example.com", false),
        ("WebFetch(domain:*)", "https://anything.test/x", true),
        ("WebFetch(domain:example.*)", "https://example.org", true),
        ("WebFetch(domain:example.*)", "https://example.evil.com", false),
        ("WebFetch(domain:example.com)", "not a url", false),
        ("WebFetch", "https://anything.test/x", true),
    ])
    func aWebFetchRuleMatchesTheHost(rule: String, url: String, expected: Bool) {
        let input: ClaudeHookJSONValue = .object(["url": .string(url), "prompt": .string("read it")])
        #expect(Self.matches(rule, tool: "WebFetch", input: input) == expected, "\(rule) against \(url)")
    }

    @Test
    func pathRulesAreNotBuiltAndMatchNothing() {
        let input: ClaudeHookJSONValue = .object(["file_path": .string("/tmp/project/.env")])
        #expect(!Self.matches("Read(./.env)", tool: "Read", input: input))
        #expect(!Self.matches("Edit(//tmp/**)", tool: "Edit", input: input))
        // The tool alone still matches.
        #expect(Self.matches("Read", tool: "Read", input: input))
    }

    // MARK: Wildcards

    @Test
    func aStarStandsForAnyRunOfCharacters() {
        #expect(ClaudeAskRuleMatcher.wildcard("a*c", matches: "abc"))
        #expect(ClaudeAskRuleMatcher.wildcard("a*c", matches: "ac"))
        #expect(ClaudeAskRuleMatcher.wildcard("a*c", matches: "a b\nc"))
        #expect(ClaudeAskRuleMatcher.wildcard("*", matches: ""))
        #expect(ClaudeAskRuleMatcher.wildcard("a*b*c", matches: "aXbXbXc"))
        #expect(!ClaudeAskRuleMatcher.wildcard("a*c", matches: "abd"))
        #expect(!ClaudeAskRuleMatcher.wildcard("abc", matches: "abcd"))
        #expect(!ClaudeAskRuleMatcher.wildcard("", matches: "a"))
    }
}
