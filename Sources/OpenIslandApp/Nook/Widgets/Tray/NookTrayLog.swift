import Foundation
import OSLog

/// The tray's log, and the one way it writes down what an error was.
enum NookTrayLog {
    static let logger = Logger(subsystem: "app.openisland", category: "nook.tray")

    /// An error's domain and code, such as "NSCocoaErrorDomain 260". Neither
    /// names a file or anything the user typed, so both go in the public part
    /// of a log line. The error's own words stay out of it: they can carry
    /// paths.
    static func cause(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code)"
    }
}
