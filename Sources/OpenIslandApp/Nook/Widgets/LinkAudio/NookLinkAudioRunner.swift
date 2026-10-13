import Foundation

/// A program to start: the file, its arguments as an array, the environment
/// it runs in and the folder it runs from. Never a string for a shell.
struct NookLinkAudioLaunch: Equatable, Sendable {
    var executable: URL
    var arguments: [String]
    var environment: [String: String]
    /// The working directory. A config file in the folder the app happens to
    /// run from is then never read.
    var currentDirectory: URL?
}

/// How the program ended.
struct NookLinkAudioExit: Equatable, Sendable {
    var status: Int32
    /// True when a signal ended it and it did not exit by itself.
    var wasSignalled: Bool

    var isSuccess: Bool { status == 0 && !wasSignalled }
}

/// Starts programs for the widget. The app uses `NookLinkAudioProcessRunner`.
/// A test hands in a fake, which keeps every test off real processes.
///
/// Both callbacks run on the main actor. `onLine` is called for each line
/// the program writes to its output or its error output, in the order
/// they arrived, and `onExit` once, after the last of them.
@MainActor
protocol NookLinkAudioRunner: AnyObject {
    func run(
        _ launch: NookLinkAudioLaunch,
        onLine: @escaping @MainActor @Sendable (String) -> Void,
        onExit: @escaping @MainActor @Sendable (NookLinkAudioExit) -> Void
    ) throws -> any NookLinkAudioRun
}

/// A program that was started.
@MainActor
protocol NookLinkAudioRun: AnyObject {
    /// Asks the program to stop. `onExit` follows when it has.
    func cancel()

    /// Stops the program and waits for it, for a quit: nothing is left to
    /// hear `onExit` then. It is asked to stop, ended if it does not listen
    /// within a moment, and killed after that.
    func stopForQuit()
}

/// A runner that starts nothing, for a model on a store of its own.
@MainActor
final class NookLinkAudioRefusingRunner: NookLinkAudioRunner {
    struct Refused: Error {}

    func run(
        _ launch: NookLinkAudioLaunch,
        onLine: @escaping @MainActor @Sendable (String) -> Void,
        onExit: @escaping @MainActor @Sendable (NookLinkAudioExit) -> Void
    ) throws -> any NookLinkAudioRun {
        throw Refused()
    }
}

/// Cuts a program's output into lines. A chunk can end in the middle of a
/// line, and the rest comes with the next one. A bare carriage return ends
/// a line too, which is how a progress bar that was not asked for
/// newlines writes.
///
/// A line longer than `maxLineBytes` is dropped whole, up to its end. It is
/// not cut in two: the second half would start a line of its own, and a title
/// of the site's making could be written to make it start with a marker.
struct NookLinkAudioLineBuffer: Sendable {
    static let maxLineBytes = 64 * 1024

    private var pending: [UInt8] = []
    /// True while the rest of a line that was too long is being skipped.
    private var isSkipping = false

    /// The lines that `data` completed. Blank lines are left out.
    mutating func append(_ data: Data) -> [String] {
        var lines: [String] = []
        for byte in data {
            if byte == 0x0A || byte == 0x0D {
                if isSkipping {
                    isSkipping = false
                } else if let line = take() {
                    lines.append(line)
                }
            } else if !isSkipping {
                pending.append(byte)
                if pending.count > Self.maxLineBytes {
                    pending.removeAll(keepingCapacity: true)
                    isSkipping = true
                }
            }
        }
        return lines
    }

    /// The unfinished last line, when the output ends without a newline.
    mutating func flush() -> String? {
        if isSkipping {
            isSkipping = false
            return nil
        }
        return take()
    }

    private mutating func take() -> String? {
        guard !pending.isEmpty else { return nil }
        defer { pending.removeAll(keepingCapacity: true) }
        return String(decoding: pending, as: UTF8.self)
    }
}
