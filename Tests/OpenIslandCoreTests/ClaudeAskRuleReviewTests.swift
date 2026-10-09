import Foundation
import Testing
@testable import OpenIslandCore

/// What a review of the ask rule reader found: commands it read past,
/// text it must go on leaving alone, a command built to stall it, and
/// settings files it read wrongly. Every file here is in a temporary
/// folder. The real `~/.claude` is never looked at.
struct ClaudeAskRuleReviewTests {
    /// The shapes of the list this was built for.
    private static let rules = [
        "Bash(rm -rf *)", "Bash(rm -rf:*)", "Bash(git reset --hard *)", "Bash(git clean:*)",
        "Bash(launchctl *)", "Bash(sudo:*)", "Bash(chmod -R *)", "Bash(gh release *)",
    ].compactMap { ClaudeAskRule($0) }

    private static func bash(_ command: String) -> ClaudeHookJSONValue {
        .object(["command": .string(command)])
    }

    private static func matchingRule(_ command: String) -> ClaudeAskRule? {
        rules.first { ClaudeAskRuleMatcher.matches($0, toolName: "Bash", toolInput: bash(command)) }
    }

    // MARK: Commands the reader read past

    @Test(arguments: [
        // An assignment whose value holds spaces inside `$( )` or backticks.
        "GH_TOKEN=$(gh auth token) gh release create v1.0.0",
        "GH_TOKEN=$(gh-token) gh release create v1.0.0",
        "TOKEN=`cat .token file` gh release list",
        "DIR=\"$(dirname \"$0\")\" sudo ls",
        "TS=$(date +%s) rm -rf build",
        "MSG=\"a b\" rm -rf build",
        "OUT=${TMPDIR:-/tmp dir} sudo ls",
        // `$'...'`, where a backslash escapes the quote.
        "echo $'it\\'s done'; git reset --hard HEAD~1",
        "echo $'it\\'s'; rm -rf build",
        "git commit -m $'don\\'t'; sudo make install",
        // `<<` inside arithmetic shifts a number and starts no heredoc.
        "n=$((1<<3))\ngit clean -fd",
        "x=$((1<<2))\nrm -rf build",
        "echo $((1<<4)); echo ok\nsudo ls",
        "(( x = 1 << 3 ))\nlaunchctl list",
        // The arm of a `case`.
        "case \"$1\" in clean) git clean -fd;; esac",
        "case $x in a) rm -rf build;; esac",
        "case $x in\n  a)\n    rm -rf build\n    ;;\nesac",
        "case $x in (a) rm -rf build;; esac",
        "case $x in a|b) sudo ls;; esac",
        // The body of a function and of a group.
        "cleanup() { rm -rf build; }; cleanup",
        "f() { rm -rf build; }; f",
        "function f { rm -rf build; }; f",
        "f () ( sudo ls )",
        "{ rm -rf build; }",
        // A line end written as a carriage return and a line feed.
        "echo start\r\nlaunchctl list",
        "echo a\r\nrm -rf build",
        // A quote with a combining mark after it.
        "echo 'a'\u{0301}; sudo ls",
    ])
    func aCommandThatRunsARuleCommandIsCaught(command: String) {
        #expect(Self.matchingRule(command) != nil, "missed: \(command.debugDescription)")
    }

    // MARK: Text that only mentions a rule command

    @Test(arguments: [
        "git commit -m \"docs: explain sudo and rm -rf * rules\"",
        "git commit -m \"$(cat <<'EOF'\nfix: card for launchctl\n\nsudo is asked in the terminal\nrm -rf build is too\nEOF\n)\"",
        "git commit -m \"fix; sudo is asked\"",
        "git commit -m \"fix\n\nsudo is asked\nlaunchctl too\"",
        "git commit -m 'fix\n\nsudo is asked'",
        "rg -n \"launchctl \" Sources",
        "rg 'sudo|launchctl' .",
        "grep -E sudo\\|launchctl file",
        "cat docs/sudo/launchctl.md",
        "echo \"run \\`sudo ls\\` first\"",
        "gh pr create --title x --body \"$(cat <<'EOF'\n## Test\n- `sudo launchctl list`\n- rm -rf build\nEOF\n)\"",
        "python3 - <<'PY'\nimport os\nos.system('sudo ls')\nPY",
        "cat > notes.md <<'EOF'\nsudo rm -rf /\nEOF",
        "which sudo launchctl",
        "command -v sudo",
        "man launchctl",
        "ls # sudo rm -rf /",
        "CMD=\"sudo ls\"; echo $CMD",
        "echo 'git reset --hard HEAD'",
        "jq '.a | .b' file | head",
        "awk '{ print $1 }; END { print \"sudo\" }' f",
        "sed -e 's/sudo//; s/x/y/' f",
        "printf '%s\\n' sudo launchctl",
        "git log --grep='rm -rf'",
        "echo \"it's\" && cat <<'EOF'\nsudo ls\nEOF",
        "curl 'https://x.test/a?b=1&sudo=2'",
        "ls",
        // Braces and parentheses that group nothing.
        "find . -name '*.o' -exec ls {} +",
        "echo {a,b}.txt ${HOME}/x",
        "echo $'sudo ls'",
        "echo $((2 << 3))",
    ])
    func textThatOnlyMentionsARuleCommandIsLeftAlone(command: String) {
        let hit = Self.matchingRule(command)
        #expect(hit == nil, "wrongly matched \(command.debugDescription) with \(String(describing: hit))")
    }

    // MARK: A command built to stall the reader

    /// Thousands of open parentheses once cost seconds a rule, on the
    /// queue every agent's hook waits on. It now reads as unreadable at
    /// once, and unreadable counts as a match.
    @Test
    func aDeeplyNestedCommandIsRefusedFastAndCountsAsAMatch() {
        let command = String(repeating: "(", count: 6_000)
        let clock = ContinuousClock()
        var hit: ClaudeAskRule?

        let elapsed = clock.measure { hit = Self.matchingRule(command) }

        #expect(hit != nil)
        #expect(elapsed < .seconds(1), "took \(elapsed)")
    }

    @Test
    func aCommandPastTheLongestOneReadIsUnreadable() {
        let longest = ClaudeBashCommandParts.longestParsedCommand
        let fits = "echo " + String(repeating: "a", count: longest - 5)
        let tooLong = fits + "a"

        #expect(ClaudeBashCommandParts.reading(of: fits) == .commands([fits]))
        #expect(ClaudeBashCommandParts.reading(of: tooLong) == .unreadable)
        // Unreadable is a match for a Bash rule and for no other tool's.
        #expect(Self.matchingRule(tooLong) != nil)
        let webRule = ClaudeAskRule(tool: "WebFetch", specifier: "domain:example.com")
        #expect(ClaudeAskRuleMatcher.matches(webRule, toolName: "Bash", toolInput: Self.bash(tooLong)) == false)
    }

    @Test
    func nestingIsFollowedToTheCapAndNoFurther() {
        let cap = ClaudeBashCommandParts.deepestNesting
        let atTheCap = String(repeating: "$(", count: cap) + "sudo ls" + String(repeating: ")", count: cap)
        let pastIt = String(repeating: "$(", count: cap + 1) + "ls" + String(repeating: ")", count: cap + 1)

        #expect(Self.matchingRule(atTheCap) == ClaudeAskRule(tool: "Bash", specifier: "sudo:*"))
        #expect(ClaudeBashCommandParts.reading(of: pastIt) == .unreadable)
    }

    /// The worst text the caps let through, against two hundred rules: the
    /// command is read once, not once a rule.
    @Test
    func theLongestDeepestCommandIsReadOnceForAllRules() {
        let cap = ClaudeBashCommandParts.deepestNesting
        let open = String(repeating: "(", count: cap)
        let filler = String(repeating: "a;", count: (ClaudeBashCommandParts.longestParsedCommand - cap) / 2)
        let command = open + filler
        let many = (0..<200).compactMap { ClaudeAskRule("Bash(tool\($0) *)") }
        let single = Array(many.prefix(1))
        let clock = ContinuousClock()
        var hit: ClaudeAskRule?

        // Measured against one rule and not against the clock: a slow
        // machine is slow for both, and a reader that ran once per rule
        // would take about two hundred times as long.
        let one = clock.measure {
            _ = ClaudeAskRuleMatcher.firstMatch(in: single, toolName: "Bash", toolInput: Self.bash(command))
        }
        let elapsed = clock.measure {
            hit = ClaudeAskRuleMatcher.firstMatch(in: many, toolName: "Bash", toolInput: Self.bash(command))
        }

        #expect(hit == nil)
        #expect(elapsed < one * 20 + .milliseconds(100), "one rule took \(one), two hundred took \(elapsed)")
    }

    @Test
    func noRulesMeansNoReadingAtAll() {
        let command = String(repeating: "(", count: 6_000)
        #expect(ClaudeAskRuleMatcher.firstMatch(in: [], toolName: "Bash", toolInput: Self.bash(command)) == nil)
    }

    // MARK: Settings files

    /// The size on record can be wrong, a link's above all. No more than
    /// the limit is ever read.
    @Test
    func aFileLargerThanItsRecordedSizeIsStillRefused() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeAskRuleReviewTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(count: ClaudeAskRuleSource.largestFile + 16).write(to: file)

        #expect(ClaudeAskRuleSource.read(file, size: 10) == .unreadable("the file is too large"))
        #expect(ClaudeAskRuleSource.read(file) == .unreadable("the file is too large"))
    }

    @Test
    func aLinkToSomethingThatIsNotAFileGivesNoRulesAndDoesNotHang() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeAskRuleReviewTests-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("settings.json")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/dev/zero")
        let locations = ClaudeSettingsLocations(userSettings: link, managedDirectory: nil, home: root)
        let source = ClaudeAskRuleSource(locations: { locations })

        #expect(source.outcome(for: link) == .unreadable("it is not a file"))
        #expect(source.rules(forWorkingDirectory: root.path).isEmpty)
    }

    /// A settings file that is a link is read again when the file it
    /// points to changes. The link's own date never does.
    @Test
    func aLinkedSettingsFileIsReadAgainWhenItsTargetChanges() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeAskRuleReviewTests-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let dotfiles = root.appendingPathComponent("dotfiles", isDirectory: true)
        let claude = home.appendingPathComponent(".claude", isDirectory: true)
        for folder in [dotfiles, claude] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let target = dotfiles.appendingPathComponent("claude-settings.json")
        let link = claude.appendingPathComponent("settings.json")
        try Data("{\"permissions\": {\"ask\": [\"Bash(launchctl *)\"]}}".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let locations = ClaudeSettingsLocations(userSettings: link, managedDirectory: nil, home: home)
        let source = ClaudeAskRuleSource(locations: { locations })
        let project = home.appendingPathComponent("code", isDirectory: true).path

        let before = source.matchingRule(toolName: "Bash", toolInput: Self.bash("sudo ls"), workingDirectory: project)
        try Data("{\"permissions\": {\"ask\": [\"Bash(launchctl *)\", \"Bash(sudo *)\"]}}".utf8).write(to: target)
        let after = source.matchingRule(toolName: "Bash", toolInput: Self.bash("sudo ls"), workingDirectory: project)

        #expect(before == nil)
        #expect(after == ClaudeAskRule(tool: "Bash", specifier: "sudo *"))
    }

    @Test
    func aSessionInTheRootFolderReadsNoProjectFile() {
        let locations = ClaudeSettingsLocations(
            userSettings: URL(fileURLWithPath: "/nowhere/.claude/settings.json"),
            managedDirectory: nil,
            home: URL(fileURLWithPath: "/nowhere", isDirectory: true)
        )

        #expect(locations.projectSettings(forWorkingDirectory: "/").isEmpty)
        // One folder down, its own files are read and the root's are not.
        let paths = locations.projectSettings(forWorkingDirectory: "/srv").map(\.path)
        #expect(paths == ["/srv/.claude/settings.json", "/srv/.claude/settings.local.json"])
    }
}
