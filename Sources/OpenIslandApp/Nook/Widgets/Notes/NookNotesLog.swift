import Foundation
import OSLog

/// The notes' log (D70). Every place a failure is caught in the store and in
/// the destinations writes here: the operation, the error underneath and
/// the path (private, because a path names a person's folders).
enum NookNotesLog {
    static let log = Logger(subsystem: "app.openisland", category: "nook.notes")

    /// A caught error: what was being done, to which file, and why it failed.
    static func failure(_ operation: String, path: String? = nil, error: Error) {
        if let path {
            log.error("\(operation, privacy: .public) failed at \(path, privacy: .private): \(String(describing: error), privacy: .public)")
        } else {
            log.error("\(operation, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// A script that Notes ran and failed: its exit status and the error
    /// number are public; what it said stays private, because it can hold a
    /// note's id.
    static func scriptFailure(_ operation: String, status: Int32, standardError: String) {
        let code = errorNumber(in: standardError) ?? "none"
        log.error("The \(operation, privacy: .public) script failed with status \(status, privacy: .public), error \(code, privacy: .public): \(standardError, privacy: .private)")
    }

    /// The number in the "(-1743)" an AppleScript error ends with: the last
    /// one, because a note's id can hold a number in brackets of its own.
    static func errorNumber(in standardError: String) -> String? {
        guard let pattern = try? NSRegularExpression(pattern: #"\(-?\d+\)"#),
              let match = pattern.matches(in: standardError, range: NSRange(standardError.startIndex..., in: standardError)).last,
              let range = Range(match.range, in: standardError) else { return nil }
        return String(standardError[range].dropFirst().dropLast())
    }

    /// Something went wrong that is not an error thrown.
    static func warning(_ message: String, path: String? = nil) {
        if let path {
            log.warning("\(message, privacy: .public) at \(path, privacy: .private)")
        } else {
            log.warning("\(message, privacy: .public)")
        }
    }
}
