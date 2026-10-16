import Foundation

/// Why Apple Notes did not take a note.
enum NookAppleNotesError: Error, Equatable, Sendable {
    /// macOS has not let the app control Notes (error -1743).
    case notPermitted
    /// Notes refused, or the script could not be run.
    case failed
    /// Hangover cannot read which Apple notes it made, and sends none until it can.
    case listUnreadable
}

/// Makes, changes and deletes notes in the Notes app. The app runs a
/// script; tests use a fake and never reach the Notes app.
protocol NookAppleNotesBridge: Sendable {
    /// Makes a note in the Hangover folder and returns its id.
    func create(bodyHTML: String) async throws -> String
    /// Sets the whole text of the note. False when Notes has no note with
    /// this id any more.
    func update(id: String, bodyHTML: String) async throws -> Bool
    /// Deletes the note, which Notes keeps in Recently Deleted for a while.
    /// A note that is already gone is not an error.
    func delete(id: String) async throws
    /// The ids of the notes in the Hangover folder whose title is this one.
    /// None when there is no such note, and none when there is no folder.
    func find(title: String) async throws -> [String]
}

extension NookAppleNotesBridge {
    /// A bridge with no way to look finds nothing, and a retry makes a note.
    func find(title: String) async throws -> [String] { [] }
}

/// A note's text as the HTML the Notes app keeps.
enum NookAppleNotesBody {
    /// The folder in the Notes app that holds the notes Hangover makes.
    static let folderName = "Hangover"

    /// One `div` for each line, the first as a heading, which is the way
    /// Notes shows a title. Notes names a note after its first line, so the
    /// note is given a body and no name of its own: giving both would show
    /// the title twice.
    static func html(from text: String) -> String {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        var out = ""
        var sawTitle = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                // A blank line above the title is not part of the note.
                if sawTitle { out += "<div><br></div>" }
                continue
            }
            if sawTitle {
                out += "<div>\(escape(line))</div>"
            } else {
                sawTitle = true
                out += "<div><h1>\(escape(trimmed))</h1></div>"
            }
        }
        return out
    }

    /// The title Notes gives the note the text makes: its first line with
    /// anything on it, as `html(from:)` sets it. Empty for a text with none.
    static func title(of text: String) -> String {
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }

    /// Keeps typed text from being read as markup.
    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// The scripts. The note's text and id travel as arguments and are never
/// pasted into a script, which keeps a note from being run as code.
///
/// A note is "missing" only when Notes says there is no such object (error
/// -1728). Any other error, such as a refusal (-1743) or a Notes that is
/// busy or does not answer, is thrown out of the script and not taken for a
/// note that is gone: that would make a second Apple note for the first.
enum NookAppleNotesScripts {
    /// The error Notes gives for an id it has no note with.
    static let noSuchObjectCode = -1728

    /// Makes the Hangover folder when there is none, makes the note in it
    /// and prints the note's id.
    static let create = """
    on run argv
        set folderName to item 1 of argv
        set bodyHTML to item 2 of argv
        tell application "Notes"
            set theAccount to default account
            if not (exists folder folderName of theAccount) then
                make new folder at theAccount with properties {name:folderName}
            end if
            set theFolder to folder folderName of theAccount
            set newNote to make new note at theFolder with properties {body:bodyHTML}
            return id of newNote
        end tell
    end run
    """

    /// Sets the body of the note with this id and prints "ok", or prints
    /// "missing" when there is no such note, or when the note is not in the
    /// Hangover folder any more: a note deleted in Notes sits in Recently
    /// Deleted, where an edit would keep going.
    static let update = """
    on run argv
        set noteID to item 1 of argv
        set bodyHTML to item 2 of argv
        set folderName to item 3 of argv
        tell application "Notes"
            try
                set theNote to note id noteID
                if (name of container of theNote) is not folderName then return "missing"
            on error errorText number errorNumber
                if errorNumber is \(noSuchObjectCode) then return "missing"
                error errorText number errorNumber
            end try
            set body of theNote to bodyHTML
            return "ok"
        end tell
    end run
    """

    /// Deletes the note with this id. A note that is already gone is not an
    /// error; anything else is.
    static let delete = """
    on run argv
        set noteID to item 1 of argv
        tell application "Notes"
            try
                delete note id noteID
            on error errorText number errorNumber
                if errorNumber is not \(noSuchObjectCode) then error errorText number errorNumber
            end try
        end tell
    end run
    """

    /// Prints the ids of the notes in the Hangover folder named like this, one
    /// to a line, and nothing when there are none or the folder is not there.
    static let find = """
    on run argv
        set folderName to item 1 of argv
        set noteTitle to item 2 of argv
        tell application "Notes"
            set theAccount to default account
            if not (exists folder folderName of theAccount) then return ""
            set foundIDs to {}
            repeat with theNote in (notes of folder folderName of theAccount whose name is noteTitle)
                set end of foundIDs to id of theNote
            end repeat
            set AppleScript's text item delimiters to linefeed
            return foundIDs as text
        end tell
    end run
    """

    static let missing = "missing"
    static let ok = "ok"
}

/// Talks to Notes with AppleScript, run by `osascript`. Apple Notes has no
/// other way in. macOS asks the user once whether Hangover may control Notes.
struct NookAppleNotesScriptBridge: NookAppleNotesBridge {
    /// What `osascript` prints when macOS has not allowed the app to control Notes.
    static let notPermittedCode = "-1743"
    /// How long a script may run. A Notes that hangs would otherwise hold up
    /// every send behind it.
    static let timeout: TimeInterval = 20
    /// How long a create may run. The Apple event reaches Notes before the
    /// script is ended, and the note is made all the same: a create that was
    /// ended at the short limit left a note nobody had the id of, and the
    /// retry made another. This is the limit AppleScript puts on an event.
    static let createTimeout: TimeInterval = 120

    static func timeout(for operation: String) -> TimeInterval {
        operation == "create" ? createTimeout : timeout
    }

    func create(bodyHTML: String) async throws -> String {
        let outcome = await Self.run(NookAppleNotesScripts.create, [NookAppleNotesBody.folderName, bodyHTML], operation: "create")
        try Self.check(outcome, operation: "create")
        let id = outcome.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw NookAppleNotesError.failed }
        return id
    }

    func update(id: String, bodyHTML: String) async throws -> Bool {
        let outcome = await Self.run(NookAppleNotesScripts.update, [id, bodyHTML, NookAppleNotesBody.folderName], operation: "update")
        try Self.check(outcome, operation: "update")
        return try Self.updateResult(fromOutput: outcome.standardOutput)
    }

    func delete(id: String) async throws {
        let outcome = await Self.run(NookAppleNotesScripts.delete, [id], operation: "delete")
        try Self.check(outcome, operation: "delete")
    }

    func find(title: String) async throws -> [String] {
        let outcome = await Self.run(NookAppleNotesScripts.find, [NookAppleNotesBody.folderName, title], operation: "find")
        try Self.check(outcome, operation: "find")
        return Self.ids(fromOutput: outcome.standardOutput)
    }

    /// The ids the find script printed, one to a line.
    static func ids(fromOutput output: String) -> [String] {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func error(forStandardError text: String) -> NookAppleNotesError {
        text.contains(notPermittedCode) ? .notPermitted : .failed
    }

    /// What the update script printed: the note was set, or it is not there.
    /// Anything else is not an answer.
    static func updateResult(fromOutput output: String) throws -> Bool {
        switch output.trimmingCharacters(in: .whitespacesAndNewlines) {
        case NookAppleNotesScripts.ok: return true
        case NookAppleNotesScripts.missing: return false
        default: throw NookAppleNotesError.failed
        }
    }

    /// What one run of `osascript` came to.
    struct Outcome: Equatable {
        var status: Int32
        var standardOutput: String
        var standardError: String
        var timedOut = false
    }

    /// Throws for a run that did not succeed, after writing it to the log
    /// with its exit status and what the script said.
    static func check(_ outcome: Outcome, operation: String) throws {
        if outcome.timedOut {
            NookNotesLog.warning("Notes did not answer the \(operation) script in time")
            throw NookAppleNotesError.failed
        }
        guard outcome.status != 0 else { return }
        NookNotesLog.scriptFailure(operation, status: outcome.status, standardError: outcome.standardError)
        throw error(forStandardError: outcome.standardError)
    }

    private static func run(_ script: String, _ arguments: [String], operation: String) async -> Outcome {
        await run(
            executable: URL(fileURLWithPath: "/usr/bin/osascript"), arguments: ["-e", script] + arguments,
            timeout: timeout(for: operation)
        )
    }

    /// Runs a program and waits for it, no longer than `timeout`. A program
    /// that is still running then is ended.
    static func run(executable: URL, arguments: [String], timeout: TimeInterval) async -> Outcome {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let output = Pipe()
            let errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            do {
                try process.run()
            } catch {
                NookNotesLog.failure("start \(executable.lastPathComponent)", error: error)
                continuation.resume(returning: Outcome(status: -1, standardOutput: "", standardError: ""))
                return
            }
            let timedOut = TimeoutFlag()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    timedOut.set()
                    process.terminate()
                }
            }
            // Read while the script runs. A script that printed more than
            // the pipe holds, and was only read after it ended, would wait
            // on the pipe and never end.
            DispatchQueue.global(qos: .utility).async {
                let group = DispatchGroup()
                nonisolated(unsafe) var outData = Data()
                nonisolated(unsafe) var errData = Data()
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    outData = output.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                errData = errors.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                continuation.resume(returning: Outcome(
                    status: process.terminationStatus,
                    standardOutput: String(decoding: outData, as: UTF8.self),
                    standardError: String(decoding: errData, as: UTF8.self),
                    timedOut: timedOut.isSet
                ))
            }
        }
    }
}

/// Set by the timer that ends a program, read when the program is over.
private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}
