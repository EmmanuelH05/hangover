import Foundation

/// Where a quick note is saved.
enum NookNotesDestination: String, CaseIterable, Identifiable, Sendable {
    /// A line in a Markdown file. The default.
    case file
    /// A line in one note in the Apple Notes app.
    case appleNotes

    var id: String { rawValue }
}

/// Why Apple Notes did not take a line.
enum NookAppleNotesError: Error, Equatable, Sendable {
    /// macOS has not let the app control Notes (error -1743).
    case notPermitted
    /// Notes refused, or the script could not be run.
    case failed
}

/// Adds lines to a note in Apple Notes. The app runs a script; tests use a stub.
protocol NookAppleNotesWriting: Sendable {
    /// Adds one line to the note with this title in the default folder,
    /// making the note when there is none.
    func append(lineHTML: String, toNoteTitled title: String) async throws
}

/// One line of a note, as the HTML Apple Notes keeps.
enum NookAppleNotesLine {
    /// The note the app writes to.
    static let noteTitle = "Quick Notes"

    static func html(text: String, stamp: String) -> String {
        "<div><b>\(escape(stamp))</b> \(escape(text))</div>"
    }

    /// Keeps typed text from being read as markup.
    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// Talks to Notes with AppleScript, run by `osascript`. Apple Notes has no
/// other way in. macOS asks the user once whether Hangover may control Notes.
///
/// The text travels as an argument and is never pasted into the script,
/// which keeps a note from being run as code.
struct NookAppleNotesScriptWriter: NookAppleNotesWriting {
    /// Looks only in the default folder, which keeps a note that sits in
    /// Recently Deleted from taking lines nobody would see. Notes has no
    /// "add a line": the whole body is set again with the line on the end.
    /// A new note is given a body and no name: Notes names a note after its
    /// first line, and giving both would show the title twice.
    static let appendScript = """
    on run argv
        set noteTitle to item 1 of argv
        set titleHTML to item 2 of argv
        set lineHTML to item 3 of argv
        tell application "Notes"
            set home to default folder of default account
            set found to (every note of home whose name is noteTitle)
            if (count of found) is 0 then
                make new note at home with properties {body:"<div><h1>" & titleHTML & "</h1></div>" & lineHTML}
            else
                set target to item 1 of found
                set body of target to (body of target) & lineHTML
            end if
        end tell
    end run
    """

    /// What `osascript` prints when macOS has not allowed the app to control Notes.
    static let notPermittedCode = "-1743"

    func append(lineHTML: String, toNoteTitled title: String) async throws {
        let arguments = ["-e", Self.appendScript, title, NookAppleNotesLine.escape(title), lineHTML]
        let outcome = await Self.runOsascript(arguments)
        guard outcome.status == 0 else {
            throw Self.error(forStandardError: outcome.standardError)
        }
    }

    static func error(forStandardError text: String) -> NookAppleNotesError {
        text.contains(notPermittedCode) ? .notPermitted : .failed
    }

    private static func runOsascript(_ arguments: [String]) async -> (status: Int32, standardError: String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = arguments
            let errors = Pipe()
            process.standardError = errors
            process.standardOutput = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                continuation.resume(returning: (-1, ""))
                return
            }
            // Read while the script runs. A script that printed more than
            // the pipe holds, and was only read after it ended, would wait
            // on the pipe and never end.
            DispatchQueue.global(qos: .utility).async {
                let data = errors.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: (process.terminationStatus, String(decoding: data, as: UTF8.self)))
            }
        }
    }
}
