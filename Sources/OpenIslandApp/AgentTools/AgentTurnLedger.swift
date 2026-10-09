import Foundation
import OpenIslandCore

/// What one session did since the user's last prompt.
struct AgentTurnRecord: Equatable, Sendable {
    /// When the prompt was handed over.
    var startedAt: Date
    /// When the session last reported it had finished. Nil while it works.
    var endedAt: Date?
    /// Tool calls a hook saw through to their end, in order. A tool that
    /// was only asked for, was denied or failed is never in here.
    var finishedTools: [AgentToolFinish] = []
    /// Finished tool calls past the limit. They are counted and not kept.
    var unkeptFinishedTools = 0
    var permissionRequests = 0

    init(
        startedAt: Date,
        endedAt: Date? = nil,
        finishedTools: [AgentToolFinish] = [],
        unkeptFinishedTools: Int = 0,
        permissionRequests: Int = 0
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.finishedTools = finishedTools
        self.unkeptFinishedTools = unkeptFinishedTools
        self.permissionRequests = permissionRequests
    }
}

/// Keeps, for every session, what it did since the user's last prompt. It
/// is fed the same events the island is and holds nothing it was not told:
/// a session whose prompt the app never saw has no record at all.
struct AgentTurnLedger: Equatable, Sendable {
    /// Finished tool calls kept per prompt. Past this they are only counted.
    static let finishedToolLimit = 500

    private(set) var turns: [String: AgentTurnRecord] = [:]

    func turn(for sessionID: String) -> AgentTurnRecord? {
        turns[sessionID]
    }

    mutating func record(_ event: AgentEvent) {
        switch event {
        case let .activityUpdated(payload):
            if payload.startsTurn == true {
                turns[payload.sessionID] = AgentTurnRecord(startedAt: payload.timestamp)
                return
            }
            if payload.phase == .completed {
                close(payload.sessionID, at: payload.timestamp)
            } else {
                reopen(payload.sessionID)
            }
            if let finish = payload.finishedTool {
                noteFinishedTool(finish, sessionID: payload.sessionID)
            }

        case let .sessionCompleted(payload):
            // An agent that quits in the middle of its work did not finish.
            if payload.isSessionEnd == true, turns[payload.sessionID]?.endedAt == nil {
                turns[payload.sessionID] = nil
                return
            }
            close(payload.sessionID, at: payload.timestamp)

        case let .permissionRequested(payload):
            reopen(payload.sessionID)
            turns[payload.sessionID]?.permissionRequests += 1

        case let .questionAsked(payload):
            reopen(payload.sessionID)

        case let .actionableStateResolved(payload):
            reopen(payload.sessionID)

        // The metadata events name the tool a session is in right now. That
        // is a tool being asked for, which may still be denied or fail, and
        // the name is not sent again for a second identical call. Nothing
        // is counted from them.
        case .sessionStarted, .jumpTargetUpdated, .sessionHeartbeat,
             .sessionMetadataUpdated, .claudeSessionMetadataUpdated, .openCodeSessionMetadataUpdated,
             .cursorSessionMetadataUpdated, .piSessionMetadataUpdated, .geminiSessionMetadataUpdated:
            break
        }
    }

    /// Forgets sessions the app no longer tracks.
    mutating func prune(keeping sessionIDs: Set<String>) {
        guard turns.keys.contains(where: { !sessionIDs.contains($0) }) else { return }
        turns = turns.filter { sessionIDs.contains($0.key) }
    }

    /// The first report of having finished ends the work. Later ones (an
    /// idle notice a minute on) do not move it.
    private mutating func close(_ sessionID: String, at timestamp: Date) {
        guard var turn = turns[sessionID], turn.endedAt == nil else { return }
        turn.endedAt = max(timestamp, turn.startedAt)
        turns[sessionID] = turn
    }

    /// Work after a finish with no new prompt between still answers the
    /// same prompt: an agent that carries on after a denied tool, or one
    /// woken by a background task.
    private mutating func reopen(_ sessionID: String) {
        guard turns[sessionID]?.endedAt != nil else { return }
        turns[sessionID]?.endedAt = nil
    }

    /// One tool call a hook saw finish. Each such hook fires once per call,
    /// which makes two identical calls two entries and two calls running
    /// side by side two entries.
    private mutating func noteFinishedTool(_ finish: AgentToolFinish, sessionID: String) {
        guard var turn = turns[sessionID] else { return }
        if turn.finishedTools.count < Self.finishedToolLimit {
            turn.finishedTools.append(finish)
        } else {
            turn.unkeptFinishedTools += 1
        }
        turns[sessionID] = turn
    }
}

/// What is known about the files an agent's edit tools wrote.
enum AgentFileEdits: Equatable, Sendable {
    /// Not known in full: this agent's hooks do not report finished edits,
    /// part of the work was handed to a subagent or was not kept, or an
    /// edit did not name its file. Nothing is said about files.
    case unknown
    /// Every finished edit named its file. One entry per file, in order of
    /// first edit. Empty when no edit tool finished.
    case files([String])
}

/// The "what it did" card: what a session did between the user's last
/// prompt and its finish. Every field comes from a hook that fired after
/// the work it reports. A field the hooks cannot back is nil or empty and
/// its line is left out. No total of tool runs is given: a hook that never
/// arrived would leave it short.
struct AgentTurnSummary: Equatable, Sendable {
    /// From the prompt to the finish.
    var duration: TimeInterval
    var endedAt: Date
    var fileEdits: AgentFileEdits
    /// The shell commands that ran to their end, whole and in order. Empty
    /// when none did, and when the list would not be the whole of them.
    var commands: [String]
    /// The finished shell commands that start a test runner the app knows.
    /// An empty list says nothing: tests may have run some other way.
    var testCommands: [String]
    /// How often the session asked for permission. Nil for an agent whose
    /// requests can reach the app twice.
    var permissionRequests: Int?

    /// The summary of a finished record. Nil while the session still works.
    static func make(from record: AgentTurnRecord, tool: AgentTool) -> AgentTurnSummary? {
        guard let endedAt = record.endedAt else { return nil }

        let evidence = AgentTurnRules.finishEvidence(for: tool)
        let finished = evidence == .none ? [] : record.finishedTools
        // Work the record does not hold in full: calls past the limit, and
        // whatever a subagent did, whose own hooks the bridge drops.
        let holdsEverything = record.unkeptFinishedTools == 0
            && !finished.contains { AgentTurnRules.isDelegatingTool($0.toolName) }

        let shellRuns = finished.filter { AgentTurnRules.isShellTool($0.toolName) }
        // A command handed to the background was started, not seen to end.
        let endedCommands = shellRuns.compactMap { run -> String? in
            guard run.ranInBackground != true else { return nil }
            let command = run.command?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return command.isEmpty ? nil : command
        }
        let commandsAreWhole = holdsEverything && endedCommands.count == shellRuns.count

        let fileEdits: AgentFileEdits
        if evidence == .everyTool, holdsEverything {
            let paths = finished
                .filter { AgentTurnRules.isEditTool($0.toolName) }
                .map { AgentTurnRules.filePath(from: $0.filePath) }
            if paths.contains(nil) {
                fileEdits = .unknown
            } else {
                var seen = Set<String>()
                fileEdits = .files(paths.compactMap { $0 }.filter { seen.insert($0).inserted })
            }
        } else {
            fileEdits = .unknown
        }

        return AgentTurnSummary(
            duration: max(0, endedAt.timeIntervalSince(record.startedAt)),
            endedAt: endedAt,
            fileEdits: fileEdits,
            commands: commandsAreWhole ? endedCommands : [],
            testCommands: endedCommands.filter(AgentTestCommands.startsTestRunner),
            permissionRequests: AgentTurnRules.countsPermissionRequests(tool) ? record.permissionRequests : nil
        )
    }
}

/// Which finished tool calls an agent's hooks tell the app about.
enum AgentFinishEvidence: Equatable, Sendable {
    /// A hook fires after every tool that ran, with the tool's own input.
    case everyTool
    /// A hook fires after shell commands only.
    case shellOnly
    /// No hook the app can rely on for a finished tool.
    case none
}

/// Pure rules behind the "what it did" card.
enum AgentTurnRules {
    private static let shellTools: Set<String> = [
        "bash", "exec_command", "shell", "local_shell", "run_terminal_cmd", "run_shell_command", "execute_command",
    ]

    private static let editTools: Set<String> = [
        "edit", "write", "multiedit", "notebookedit", "apply_patch", "patch",
        "str_replace_editor", "create_file", "write_file", "replace",
    ]

    /// Tools that hand work to a subagent. The bridge drops a subagent's
    /// own hooks, which leaves its edits and commands unseen.
    private static let delegatingTools: Set<String> = ["agent", "task"]

    /// What the bridge can prove about finished tools, per agent. Claude
    /// Code and the tools built on it fire PostToolUse after every tool
    /// that ran, with the tool's input, and a separate hook for a failure.
    /// Codex fires it after shell commands only. OpenCode sends its tool
    /// input cut to 200 characters and Pi as one JSON text, and neither
    /// says whether the tool failed. Cursor, Gemini and Grok report nothing
    /// the app keeps. For those the card shows no files and no commands.
    static func finishEvidence(for tool: AgentTool) -> AgentFinishEvidence {
        if tool.isClaudeCodeFork { return .everyTool }
        if tool == .codex { return .shellOnly }
        return .none
    }

    /// Whether each request for permission reaches the app exactly once.
    /// Claude Code and OpenCode ask through one held hook. A Codex request
    /// can arrive from its hook and from the Codex app server both.
    static func countsPermissionRequests(_ tool: AgentTool) -> Bool {
        tool.isClaudeCodeFork || tool == .openCode
    }

    static func isShellTool(_ name: String) -> Bool {
        shellTools.contains(name.lowercased())
    }

    static func isEditTool(_ name: String) -> Bool {
        editTools.contains(name.lowercased())
    }

    static func isDelegatingTool(_ name: String) -> Bool {
        delegatingTools.contains(name.lowercased())
    }

    /// The file an edit tool named: an absolute path, whole. A text that
    /// ends in the ellipsis the hooks put on a clipped preview is never a
    /// path, whatever it starts with.
    static func filePath(from detail: String?) -> String? {
        guard let detail = detail?.trimmingCharacters(in: .whitespaces),
              detail.hasPrefix("/") || detail.hasPrefix("~/"),
              !detail.hasSuffix("…"), !detail.hasSuffix("...") else {
            return nil
        }
        return detail
    }

    /// The name to show for a file: its last path component.
    static func fileName(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }

    /// One line for a command that may span several.
    static func oneLine(_ command: String) -> String {
        command.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// "38s", "4m 12s", "1h 5m".
    static func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds / 3_600)h \((seconds % 3_600) / 60)m"
    }
}

/// Recognizes a shell command that starts a test runner.
enum AgentTestCommands {
    /// The words a test run starts with.
    private static let runners: [[String]] = [
        ["swift", "test"], ["bun", "test"], ["bun", "run", "test"], ["deno", "test"],
        ["npm", "test"], ["npm", "t"], ["npm", "run", "test"],
        ["pnpm", "test"], ["pnpm", "run", "test"], ["yarn", "test"], ["yarn", "run", "test"],
        ["pytest"], ["py.test"], ["tox"], ["nox"],
        ["python", "-m", "pytest"], ["python3", "-m", "pytest"],
        ["python", "-m", "unittest"], ["python3", "-m", "unittest"],
        ["cargo", "test"], ["cargo", "nextest"], ["go", "test"],
        ["jest"], ["vitest"], ["mocha"], ["playwright", "test"],
        ["rspec"], ["rake", "test"], ["rails", "test"], ["phpunit"],
        ["gradle", "test"], ["gradlew", "test"], ["mvn", "test"], ["dotnet", "test"],
        ["ctest"], ["make", "test"], ["make", "check"], ["just", "test"],
        ["mix", "test"], ["flutter", "test"], ["dart", "test"],
    ]

    /// Words that may stand in front of the runner.
    private static let wrappers: Set<String> = [
        "sudo", "time", "env", "command", "exec", "nice", "caffeinate", "xcrun",
        "npx", "bunx", "pnpx", "uv", "poetry", "pipenv", "bundle", "run",
    ]

    /// Flags that make a runner do something other than run tests: build
    /// only, list, or print help.
    private static let notARun: Set<String> = [
        "--no-run", "--list", "--list-tests", "-list", "--collect-only", "--co", "--listtests",
        "--help", "-h", "--version",
    ]

    /// Whether any command on the line starts a test runner. Text inside
    /// single or double quotes, in a comment or in a here-document never
    /// starts a command: a runner named in an `echo` or a commit message
    /// does not count. Neither does one after `||`, which runs only when
    /// the command before it failed.
    static func startsTestRunner(_ command: String) -> Bool {
        AgentShellWords.commands(in: command).contains { !$0.followsOr && startsTestRunner($0.words) }
    }

    private static func startsTestRunner(_ command: [AgentShellWords.Word]) -> Bool {
        var words = command

        // Drop what may stand before the runner: `FOO=1`, `sudo`, `uv run`.
        while let first = words.first {
            let isAssignment = !first.startsQuoted && first.text.contains("=") && !first.text.hasPrefix("-")
            let isWrapper = !first.hasQuotes && wrappers.contains(first.text.lowercased())
            guard isAssignment || isWrapper else { break }
            words.removeFirst()
        }
        // A quoted word is an argument or a made-up name, never a runner.
        guard let first = words.first, !first.hasQuotes else { return false }

        let grouping = CharacterSet(charactersIn: "(){}")
        var names = words.map { word in
            word.hasQuotes ? "\u{0}" : word.text.lowercased().trimmingCharacters(in: grouping)
        }
        // `./node_modules/.bin/jest` runs jest.
        names[0] = (names[0] as NSString).lastPathComponent

        guard !names.contains(where: notARun.contains) else { return false }

        if names[0] == "xcodebuild" {
            return names.contains("test") || names.contains("test-without-building")
        }
        return runners.contains { runner in
            guard names.count >= runner.count else { return false }
            return zip(runner, names).enumerated().allSatisfy { index, pair in
                let (expected, word) = pair
                if word == expected { return true }
                // `npm run test:unit` is a test script too.
                return index == runner.count - 1 && expected == "test" && word.hasPrefix("test:")
            }
        }
    }
}

/// Splits a shell command line into its commands and their words, the way
/// a shell would see them. It reads quotes, backslashes, comments and
/// here-documents and nothing more: no expansion, no substitution.
enum AgentShellWords {
    struct Word: Equatable, Sendable {
        var text: String
        /// Any part of the word was inside quotes.
        var hasQuotes = false
        /// The word begins with a quote.
        var startsQuoted = false
    }

    struct Command: Equatable, Sendable {
        var words: [Word]
        /// The command stands after `||`.
        var followsOr = false
    }

    /// The commands on the line, each as its words. Commands are parted by
    /// `;`, `|`, `&` and line ends that stand outside quotes.
    static func commands(in line: String) -> [Command] {
        var scanner = Scanner(characters: Array(line))
        return scanner.run()
    }

    private struct HereDocument {
        /// The line that ends the document.
        var end: String
        /// `<<-`: leading tabs do not count.
        var stripsTabs: Bool
    }

    private struct Scanner {
        let characters: [Character]
        var index = 0
        var commands: [Command] = []
        var words: [Word] = []
        var current: Word?
        var currentFollowsOr = false
        /// Here-documents that begin on this line. Their text starts after
        /// the line ends.
        var hereDocuments: [HereDocument] = []

        var peek: Character? {
            index < characters.count ? characters[index] : nil
        }

        func next(ahead offset: Int) -> Character? {
            index + offset < characters.count ? characters[index + offset] : nil
        }

        mutating func run() -> [Command] {
            while let character = peek {
                switch character {
                case "\\":
                    // A backslash takes the next character as it is. At a
                    // line end it joins the two lines.
                    if let next = next(ahead: 1), next != "\n" { append(next) }
                    index += 2

                case "'":
                    // `$'...'` lets a backslash stand before a quote.
                    let isAnsi = current?.text.last == "$"
                    beginQuote()
                    index += 1
                    appendAll(skipSingleQuoted(isAnsi: isAnsi))

                case "\"":
                    beginQuote()
                    index += 1
                    appendAll(skipDoubleQuoted())

                case "#" where current == nil:
                    skipToLineEnd()

                case "<" where next(ahead: 1) == "<":
                    endWord()
                    if let document = readHereDocumentStart() { hereDocuments.append(document) }

                case "\n":
                    endCommand(nextFollowsOr: false)
                    index += 1
                    let documents = hereDocuments
                    hereDocuments = []
                    skipHereDocumentTexts(documents)

                case ";":
                    endCommand(nextFollowsOr: false)
                    index += 1

                case "&":
                    endCommand(nextFollowsOr: false)
                    index += 1
                    if peek == "&" { index += 1 }

                case "|":
                    index += 1
                    if peek == "|" {
                        index += 1
                        endCommand(nextFollowsOr: true)
                    } else {
                        if peek == "&" { index += 1 }
                        endCommand(nextFollowsOr: false)
                    }

                case _ where character.isWhitespace:
                    endWord()
                    index += 1

                default:
                    append(character)
                    index += 1
                }
            }
            endCommand(nextFollowsOr: false)
            return commands
        }

        // MARK: Words

        private mutating func append(_ character: Character) {
            current = current ?? Word(text: "")
            current?.text.append(character)
        }

        private mutating func appendAll(_ text: String) {
            current = current ?? Word(text: "")
            current?.text.append(text)
        }

        private mutating func beginQuote() {
            let startsWord = current == nil
            current = current ?? Word(text: "")
            current?.hasQuotes = true
            if startsWord { current?.startsQuoted = true }
        }

        private mutating func endWord() {
            if let word = current { words.append(word) }
            current = nil
        }

        private mutating func endCommand(nextFollowsOr: Bool) {
            endWord()
            if !words.isEmpty {
                commands.append(Command(words: words, followsOr: currentFollowsOr))
            }
            words = []
            currentFollowsOr = nextFollowsOr
        }

        // MARK: Quotes

        /// Reads to the closing single quote and steps past it.
        private mutating func skipSingleQuoted(isAnsi: Bool) -> String {
            var text = ""
            while let character = peek {
                index += 1
                if character == "'" { return text }
                if isAnsi, character == "\\", let next = peek {
                    text.append(next)
                    index += 1
                    continue
                }
                text.append(character)
            }
            return text
        }

        /// Reads to the closing double quote and steps past it. A `$(...)`
        /// inside is passed over as a whole, with the quotes and
        /// here-documents it holds, which keeps a quote inside it from
        /// ending the text early.
        private mutating func skipDoubleQuoted() -> String {
            var text = ""
            while let character = peek {
                index += 1
                switch character {
                case "\"":
                    return text
                case "\\":
                    if let next = peek {
                        text.append(next)
                        index += 1
                    }
                case "$" where peek == "(":
                    index += 1
                    skipParenthesized()
                default:
                    text.append(character)
                }
            }
            return text
        }

        /// Steps past a `(...)` whose opening bracket was just read.
        private mutating func skipParenthesized() {
            var depth = 1
            var documents: [HereDocument] = []
            var startsWord = true
            while let character = peek {
                switch character {
                case "\\":
                    index += 2
                    startsWord = false
                case "'":
                    index += 1
                    _ = skipSingleQuoted(isAnsi: false)
                    startsWord = false
                case "\"":
                    index += 1
                    _ = skipDoubleQuoted()
                    startsWord = false
                case "(":
                    depth += 1
                    index += 1
                    startsWord = true
                case ")":
                    depth -= 1
                    index += 1
                    if depth == 0 { return }
                    startsWord = false
                case "#" where startsWord:
                    skipToLineEnd()
                case "<" where next(ahead: 1) == "<":
                    if let document = readHereDocumentStart() { documents.append(document) }
                    startsWord = false
                case "\n":
                    index += 1
                    skipHereDocumentTexts(documents)
                    documents = []
                    startsWord = true
                default:
                    startsWord = character.isWhitespace || ";|&".contains(character)
                    index += 1
                }
            }
        }

        // MARK: Comments and here-documents

        /// Moves to the end of the line and stops on its line end.
        private mutating func skipToLineEnd() {
            while let character = peek, character != "\n" { index += 1 }
        }

        /// Reads `<<WORD`, `<<-WORD` or `<<'WORD'` from its first bracket.
        /// Nil for `<<<`, a here-string, whose text is the next word.
        private mutating func readHereDocumentStart() -> HereDocument? {
            index += 2
            if peek == "<" {
                index += 1
                return nil
            }
            var stripsTabs = false
            if peek == "-" {
                stripsTabs = true
                index += 1
            }
            while let character = peek, character == " " || character == "\t" { index += 1 }
            var end = ""
            while let character = peek, !character.isWhitespace, !";|&<>()".contains(character) {
                if !"'\"\\".contains(character) { end.append(character) }
                index += 1
            }
            return end.isEmpty ? nil : HereDocument(end: end, stripsTabs: stripsTabs)
        }

        /// Steps past the text of each here-document, from the start of a
        /// line to the line that ends it. One that never ends takes the
        /// rest of the text with it.
        private mutating func skipHereDocumentTexts(_ documents: [HereDocument]) {
            for document in documents {
                while index < characters.count {
                    var lineEnd = index
                    while lineEnd < characters.count, characters[lineEnd] != "\n" { lineEnd += 1 }
                    var line = String(characters[index..<lineEnd])
                    if document.stripsTabs { line = String(line.drop(while: { $0 == "\t" })) }
                    index = min(lineEnd + 1, characters.count)
                    if line == document.end { break }
                }
            }
        }
    }
}
