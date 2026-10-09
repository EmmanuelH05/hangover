import Foundation

/// Reads the text of a shell command into the commands it runs, the way
/// Claude Code's deny and ask rules look at it: each side of `&&`, `||`,
/// `;`, `|`, `|&`, `&` and a newline, the inside of a subshell, a command
/// substitution and backticks, and the body of a loop or a condition.
///
/// This is a reading of the text, not a shell. Where it is unsure it
/// returns more text to test, never less: a caller that matches rules
/// against the result may see a match Claude Code would not, and should
/// not miss one it would.
public enum ClaudeBashCommandParts {
    /// Text past this length is not read apart. It is the longest command
    /// Claude Code documents reading.
    static let longestParsedCommand = 10_000
    /// Levels of `( )`, `$( )` and backticks inside each other that are
    /// followed. Real commands stay far below it, and a cap is what keeps
    /// a hostile command from costing the bridge its queue.
    static let deepestNesting = 48

    /// What reading a command gave.
    public enum Reading: Equatable, Sendable {
        /// The whole command first, then every command found inside it.
        case commands([String])
        /// Too long or too deeply nested to read apart. A caller that
        /// matches rules must take it as a match: a wrong match costs one
        /// approval made in the terminal, and a miss sends an approval
        /// Claude Code ignores.
        case unreadable
    }

    /// Reads a command once. A caller with several rules to test keeps the
    /// result and never reads the same command again.
    public static func reading(of command: String) -> Reading {
        let whole = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !whole.isEmpty else { return .commands([]) }
        guard whole.unicodeScalars.count <= longestParsedCommand, let found = parts(of: whole) else {
            return .unreadable
        }

        // Each stripped word copies the rest of the text. A part that opens
        // with a long run of them is not read at all.
        guard !found.contains(where: stripsTooManyWords) else { return .unreadable }

        var seen: Set<String> = [whole]
        var result = [whole]
        for part in found {
            for form in forms(of: unwrapped(part)) where seen.insert(form).inserted {
                result.append(form)
            }
        }
        return .commands(result)
    }

    /// The whole command first, then every command found inside it, each
    /// also without the wrappers and leading assignments Claude Code looks
    /// past. No text is listed twice. A command that cannot be read apart
    /// gives only itself: use `reading(of:)` to tell the two apart.
    public static func candidates(in command: String) -> [String] {
        switch reading(of: command) {
        case let .commands(commands):
            return commands
        case .unreadable:
            return [command.trimmingCharacters(in: .whitespacesAndNewlines)]
        }
    }

    /// The text one Unicode scalar at a time. A `Character` can hold more
    /// than one: a line end written as a carriage return and a line feed is
    /// a single one, and a quote takes a combining mark after it into
    /// itself. Read that way, a line end and a closing quote go unseen.
    static func scalars(of text: String) -> [Character] {
        text.unicodeScalars.map(Character.init)
    }

    // MARK: - Splitting

    private enum Quote {
        /// `ansiC` is `$'...'`, where a backslash escapes the quote.
        case none, single, double, ansiC
    }

    /// One level of the command: the top, or the inside of `( )`, `$( )`
    /// or backticks. Each has its own quotes, and a separator only cuts
    /// the innermost level.
    private struct Frame {
        var buffer = ""
        var quote = Quote.none
        var closer: Character?
        /// A plain `( )`. A word after one starts a new command: the arm
        /// of a `case` written `(a) cmd`, or the body of `name() cmd`.
        var isSubshell = false
        /// Inside `$(( ))` or `(( ))`, where `<<` shifts a number and
        /// starts no heredoc.
        var isArithmetic = false
    }

    private struct Heredoc {
        var delimiter: String
        var stripsTabs: Bool
    }

    /// Every command in `text`, at every depth, as written. Nil when the
    /// text nests deeper than `deepestNesting`.
    static func parts(of text: String) -> [String]? {
        let chars = scalars(of: text)
        var stack = [Frame()]
        var parts: [String] = []
        var heredocs: [Heredoc] = []
        var index = 0
        var isTooDeep = false

        func append(_ character: Character, toInnermost: Bool = true) {
            let end = toInnermost ? stack.count : stack.count - 1
            for level in 0..<end { stack[level].buffer.append(character) }
        }

        func emit() {
            let part = stack[stack.count - 1].buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !part.isEmpty { parts.append(part) }
            stack[stack.count - 1].buffer = ""
        }

        /// A separator ends the innermost command. The levels around it
        /// keep the separator as text.
        func cut(_ length: Int) {
            for offset in 0..<length where index + offset < chars.count {
                append(chars[index + offset], toInnermost: false)
            }
            emit()
            index += length
        }

        func open(_ length: Int, closer: Character, isSubshell: Bool = false, isArithmetic: Bool = false) {
            guard stack.count <= deepestNesting else {
                isTooDeep = true
                return
            }
            for offset in 0..<length { append(chars[index + offset]) }
            let inherited = stack[stack.count - 1].isArithmetic
            stack.append(Frame(closer: closer, isSubshell: isSubshell, isArithmetic: inherited || isArithmetic))
            index += length
        }

        func close() {
            let wasSubshell = stack[stack.count - 1].isSubshell
            emit()
            stack.removeLast()
            append(chars[index])
            index += 1
            // What follows a closed `( )` on the same line is a command
            // of its own.
            if wasSubshell { emit() }
        }

        /// True for a brace that stands as a word of its own: `{ cmd; }`
        /// groups commands, and `{a,b}`, `${x}` and `{}` do not.
        func isBraceWord() -> Bool {
            let before = stack[stack.count - 1].buffer.last
            let after = index + 1 < chars.count ? chars[index + 1] : nil
            let startsWord = before == nil || before!.isWhitespace
            let endsWord = after == nil || after!.isWhitespace || after == ";" || after == ")"
            return startsWord && endsWord
        }

        func next(_ offset: Int = 1) -> Character? {
            index + offset < chars.count ? chars[index + offset] : nil
        }

        while index < chars.count, !isTooDeep {
            let character = chars[index]
            let top = stack.count - 1

            switch stack[top].quote {
            case .single:
                if character == "'" { stack[top].quote = .none }
                append(character)
                index += 1
                continue
            case .ansiC:
                if character == "\\", let escaped = next() {
                    append(character)
                    append(escaped)
                    index += 2
                } else {
                    if character == "'" { stack[top].quote = .none }
                    append(character)
                    index += 1
                }
                continue
            case .double:
                if character == "\\", let escaped = next() {
                    append(character)
                    append(escaped)
                    index += 2
                } else if character == "\"" {
                    stack[top].quote = .none
                    append(character)
                    index += 1
                } else if character == "$", next() == "(" {
                    open(2, closer: ")", isArithmetic: next(2) == "(")
                } else if character == "`" {
                    if stack[top].closer == "`" { close() } else { open(1, closer: "`") }
                } else {
                    append(character)
                    index += 1
                }
                continue
            case .none:
                break
            }

            switch character {
            case "\\":
                append(character)
                if let escaped = next() { append(escaped) }
                index += 2
            case "$" where next() == "'":
                // `$'...'`: a backslash escapes the quote inside it.
                stack[top].quote = .ansiC
                append(character)
                append("'")
                index += 2
            case "'":
                stack[top].quote = .single
                append(character)
                index += 1
            case "\"":
                stack[top].quote = .double
                append(character)
                index += 1
            case "#" where startsWord(in: stack[top].buffer):
                // A comment runs to the end of its line and is not a command.
                while index < chars.count, chars[index] != "\n" { index += 1 }
            case "$" where next() == "(":
                open(2, closer: ")", isArithmetic: next(2) == "(")
            case "<" where next() == "(", ">" where next() == "(":
                open(2, closer: ")")
            case "(":
                open(1, closer: ")", isSubshell: true, isArithmetic: next() == "(")
            case ")" where stack[top].closer == ")":
                close()
            case ")":
                // A `)` that closes nothing ends the pattern of a `case`
                // arm. The arm's command starts after it.
                cut(1)
            case "{" where isBraceWord(), "}" where isBraceWord():
                cut(1)
            case "`":
                if stack[top].closer == "`" { close() } else { open(1, closer: "`") }
            case "<" where next() == "<" && next(2) == "<":
                // `<<<` hands over one word of input. No lines follow it.
                for _ in 0..<3 {
                    append(chars[index])
                    index += 1
                }
            case "<" where next() == "<" && !stack[top].isArithmetic:
                index = readHeredoc(in: chars, at: index, into: &heredocs) { append($0) }
            case "\n":
                cut(1)
                if !heredocs.isEmpty {
                    index = skipHeredocBodies(in: chars, from: index, heredocs: heredocs) { append($0, toInnermost: false) }
                    heredocs = []
                }
            case ";":
                cut(1)
            case "&" where next() == "&":
                cut(2)
            case "|" where next() == "|" || next() == "&":
                cut(2)
            case "|":
                cut(1)
            case "&" where !isRedirection(before: stack[top].buffer, after: next()):
                cut(1)
            default:
                append(character)
                index += 1
            }
        }

        guard !isTooDeep else { return nil }

        // Whatever is still open ends with the text.
        while !stack.isEmpty {
            emit()
            stack.removeLast()
        }
        return parts
    }

    private static func startsWord(in buffer: String) -> Bool {
        guard let last = buffer.last else { return true }
        return last.isWhitespace
    }

    /// `2>&1`, `<&3` and `&>file` carry an `&` that separates nothing.
    private static func isRedirection(before buffer: String, after next: Character?) -> Bool {
        if next == ">" { return true }
        return buffer.last == ">" || buffer.last == "<"
    }

    /// Reads `<<WORD`, `<<-WORD` and `<<'WORD'`, and notes the word that
    /// ends the text that follows on the next lines. Returns the index
    /// after the word.
    private static func readHeredoc(
        in chars: [Character],
        at start: Int,
        into heredocs: inout [Heredoc],
        append: (Character) -> Void
    ) -> Int {
        var index = start
        func take() {
            append(chars[index])
            index += 1
        }

        take()
        take()
        var stripsTabs = false
        if index < chars.count, chars[index] == "-" {
            stripsTabs = true
            take()
        }
        while index < chars.count, chars[index] == " " || chars[index] == "\t" { take() }

        var delimiter = ""
        while index < chars.count {
            let character = chars[index]
            if character.isWhitespace || ";&|()<>".contains(character) { break }
            if character != "'", character != "\"", character != "\\" { delimiter.append(character) }
            take()
        }
        if !delimiter.isEmpty {
            heredocs.append(Heredoc(delimiter: delimiter, stripsTabs: stripsTabs))
        }
        return index
    }

    /// The lines after a command with `<<WORD` are its input up to a line
    /// that is only `WORD`. They are text, never commands. Returns the
    /// index after the last ending line.
    private static func skipHeredocBodies(
        in chars: [Character],
        from start: Int,
        heredocs: [Heredoc],
        append: (Character) -> Void
    ) -> Int {
        var index = start
        for heredoc in heredocs {
            while index < chars.count {
                var line = ""
                while index < chars.count, chars[index] != "\n" {
                    line.append(chars[index])
                    append(chars[index])
                    index += 1
                }
                if index < chars.count {
                    append(chars[index])
                    index += 1
                }
                let comparable = heredoc.stripsTabs ? String(line.drop { $0 == "\t" }) : line
                if comparable == heredoc.delimiter { break }
            }
        }
        return index
    }

    // MARK: - What a part runs

    private static let leadingKeywords: Set<String> = ["do", "then", "else", "elif", "if", "while", "until", "!", "{"]

    private enum WordContext {
        case double, substitution, backtick, braces
    }

    /// Leading words the reader will strip from one command.
    static let mostStrippedWords = 64

    private static let wrapperWords: Set<String> = [
        "timeout", "time", "nice", "nohup", "stdbuf", "command", "builtin", "noglob", "xargs",
    ]

    /// True when a part opens with more strippable words than the reader
    /// follows: keywords, assignments, wrappers, their options and the
    /// values after an option. One pass over the text, with no copying.
    static func stripsTooManyWords(_ part: String) -> Bool {
        var run = 0
        var previousWasOption = false
        let words = part.split(
            maxSplits: mostStrippedWords * 4,
            omittingEmptySubsequences: true,
            whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }
        )
        for token in words {
            let word = String(token)
            let isOption = word.hasPrefix("-")
            let strippable = isOption || previousWasOption || leadingKeywords.contains(word)
                || wrapperWords.contains(word) || isAssignment(word)
            guard strippable else { return false }
            previousWasOption = isOption
            run += 1
            if run > mostStrippedWords { return true }
        }
        return false
    }

    /// A part without the shell words in front of the command it runs:
    /// `do rm -rf x` runs `rm -rf x`.
    static func unwrapped(_ part: String) -> String {
        var text = part.trimmingCharacters(in: .whitespacesAndNewlines)
        while let (word, rest) = firstWord(of: text), leadingKeywords.contains(word), !rest.isEmpty {
            text = rest
        }
        if text.hasSuffix(" }") {
            text = String(text.dropLast(2)).trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    /// The part as written, then without each leading assignment and each
    /// wrapper Claude Code looks past before it matches a rule.
    static func forms(of part: String) -> [String] {
        guard !part.isEmpty else { return [] }
        var forms = [part]
        var current = part
        for _ in 0..<8 {
            let withoutAssignments = strippingLeadingAssignments(current)
            if withoutAssignments != current {
                forms.append(withoutAssignments)
                current = withoutAssignments
            }
            guard let inner = strippingWrapper(current) else { break }
            forms.append(inner)
            current = inner
        }
        return forms
    }

    /// The first word of `text`, read with its quotes, and what follows.
    ///
    /// A word runs through whatever it opens: the space inside
    /// `TOKEN=$(gh auth token)`, inside backticks, `${x:-a b}` and
    /// `$'a b'` does not end it.
    static func firstWord(of text: String) -> (word: String, rest: String)? {
        let chars = scalars(of: text)
        var start = 0
        while start < chars.count, chars[start] == " " || chars[start] == "\t" { start += 1 }
        guard start < chars.count else { return nil }

        var contexts: [WordContext] = []
        var index = start
        func next() -> Character? { index + 1 < chars.count ? chars[index + 1] : nil }

        scan: while index < chars.count {
            let character = chars[index]

            if contexts.last == .double {
                switch character {
                case "\\": index += 1
                case "\"": contexts.removeLast()
                case "$" where next() == "(":
                    contexts.append(.substitution)
                    index += 1
                case "$" where next() == "{":
                    contexts.append(.braces)
                    index += 1
                case "`": contexts.append(.backtick)
                default: break
                }
                index += 1
                continue
            }

            switch character {
            case "\\":
                index += 1
            case "'":
                // No escapes inside single quotes.
                index += 1
                while index < chars.count, chars[index] != "'" { index += 1 }
            case "$" where next() == "'":
                index += 2
                while index < chars.count, chars[index] != "'" {
                    if chars[index] == "\\" { index += 1 }
                    index += 1
                }
            case "\"":
                contexts.append(.double)
            case "$" where next() == "(", "<" where next() == "(", ">" where next() == "(":
                contexts.append(.substitution)
                index += 1
            case "(":
                contexts.append(.substitution)
            case ")" where contexts.last == .substitution:
                contexts.removeLast()
            case "$" where next() == "{":
                contexts.append(.braces)
                index += 1
            case "}" where contexts.last == .braces:
                contexts.removeLast()
            case "`":
                if contexts.last == .backtick { contexts.removeLast() } else { contexts.append(.backtick) }
            case " ", "\t", "\n", "\r":
                if contexts.isEmpty { break scan }
            default:
                break
            }
            index += 1
        }

        let end = min(index, chars.count)
        let rest = String(chars[end...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (String(chars[start..<end]), rest)
    }

    private static func isAssignment(_ word: String) -> Bool {
        guard let equals = word.firstIndex(of: "="), equals != word.startIndex else { return false }
        var name = word[..<equals]
        if name.hasSuffix("+") { name = name.dropLast() }
        guard let first = name.first, first == "_" || first.isLetter else { return false }
        return name.allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber }
    }

    /// `FOO=bar rm -rf x` runs `rm -rf x`. An ask rule matches past any
    /// leading assignment.
    static func strippingLeadingAssignments(_ text: String) -> String {
        var current = text
        while let (word, rest) = firstWord(of: current), isAssignment(word), !rest.isEmpty {
            current = rest
        }
        return current
    }

    /// Options of a wrapper that take the word after them as their value.
    private static let wrapperValueOptions: [String: Set<String>] = [
        "timeout": ["-k", "-s", "--kill-after", "--signal"],
        "nice": ["-n", "--adjustment"],
        "stdbuf": ["-i", "-o", "-e", "--input", "--output", "--error"],
    ]

    /// The command a wrapper runs, or nil when `text` does not start with
    /// one. The wrappers are the fixed list Claude Code strips: `timeout`,
    /// `time`, `nice`, `nohup`, `stdbuf`, `command`, `builtin`, `noglob`,
    /// and `xargs` with no flags.
    static func strippingWrapper(_ text: String) -> String? {
        guard let (name, afterName) = firstWord(of: text), !afterName.isEmpty else { return nil }
        var rest = afterName

        func dropOptions(takingValues valueOptions: Set<String> = []) {
            while let (word, after) = firstWord(of: rest), word.hasPrefix("-"), !after.isEmpty {
                rest = after
                if valueOptions.contains(word), let (_, afterValue) = firstWord(of: rest), !afterValue.isEmpty {
                    rest = afterValue
                }
            }
        }

        switch name {
        case "timeout":
            dropOptions(takingValues: wrapperValueOptions["timeout"] ?? [])
            // The length of time comes before the command.
            guard let (_, afterDuration) = firstWord(of: rest), !afterDuration.isEmpty else { return nil }
            rest = afterDuration
        case "nice", "stdbuf":
            dropOptions(takingValues: wrapperValueOptions[name] ?? [])
        case "time":
            dropOptions()
        case "command":
            // `command -v name` looks a command up and runs nothing.
            if let (flag, _) = firstWord(of: rest), flag == "-v" || flag == "-V" { return nil }
            dropOptions()
        case "nohup", "builtin", "noglob":
            break
        case "xargs":
            if let (word, _) = firstWord(of: rest), word.hasPrefix("-") { return nil }
        default:
            return nil
        }
        return rest
    }
}
