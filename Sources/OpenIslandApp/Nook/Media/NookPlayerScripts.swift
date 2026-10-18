import Foundation
import OSLog

private let scriptLog = Logger(subsystem: "app.openisland", category: "nook.media.modes")

/// Shuffle and repeat of one player.
struct NookPlayerModes: Equatable, Sendable {
    var shuffle: NowPlayingShuffle
    var repeating: NowPlayingRepeat
    /// False while the player itself has the two switched off for what is
    /// playing. Spotify does that for a station and for the songs it adds
    /// after a list ends: its own two buttons are greyed out then.
    var isAvailable = true
}

/// A player that does not report shuffle and repeat with the rest of what is
/// playing, and answers an Apple Event about them. Spotify sends neither key
/// (read from its stream on 2026-10-12).
enum NookScriptedPlayer: String, CaseIterable, Sendable {
    case spotify = "com.spotify.client"
    case music = "com.apple.Music"

    enum Action: Sendable {
        case read, toggleShuffle, cycleRepeat
    }

    /// One script per press: it makes the change and says where the player
    /// stands, as `true,all,true`. The mode a press changed is reported as
    /// what the press asked for, not read back: Spotify answers a read right
    /// after a set with the old value for about a second (seen on 2026-10-18,
    /// playing a playlist), which made every press look like a no-op and,
    /// with `set shuffling to not shuffling`, sent the next press the wrong
    /// way. With the player's last report in hand (`known`) the script sets
    /// the value outright and reads nothing the set could have made stale;
    /// a quick second press inside that second still goes the right way.
    /// Without one it reads first. The mode a press leaves alone is read
    /// before the change, while the answer is fresh. It names the player by
    /// its identifier and nothing else. `tell` would open a player that is
    /// not running, which is why the script looks first: a player that quit
    /// a moment ago stays quit.
    func script(_ action: Action, knowing known: NookPlayerModes? = nil) -> String {
        let change: String
        let report: String
        switch self {
        case .spotify:
            // Spotify knows repeat as on or off, with no "one song".
            // Spotify's dictionary gives "shuffling enabled" the code of
            // "repeating enabled", which leaves one of the two to ask for.
            switch action {
            case .read:
                change = ""
                report = """
                set r to "off"
                if repeating then set r to "all"
                return (shuffling as text) & "," & r & "," & (repeating enabled as text)
                """
            case .toggleShuffle:
                if let known {
                    let target = known.shuffle == .off
                    change = """
                    set r to "off"
                    if repeating then set r to "all"
                    set shuffling to \(target)
                    """
                    report = """
                    return "\(target)" & "," & r & "," & (repeating enabled as text)
                    """
                } else {
                    change = """
                    set wasShuffling to shuffling
                    set r to "off"
                    if repeating then set r to "all"
                    set shuffling to not wasShuffling
                    """
                    report = """
                    return ((not wasShuffling) as text) & "," & r & "," & (repeating enabled as text)
                    """
                }
            case .cycleRepeat:
                if let known {
                    let target = known.repeating == .off
                    change = """
                    set s to (shuffling as text)
                    set repeating to \(target)
                    """
                    report = """
                    return s & ",\(target ? "all" : "off")," & (repeating enabled as text)
                    """
                } else {
                    change = """
                    set wasRepeating to repeating
                    set s to (shuffling as text)
                    set repeating to not wasRepeating
                    """
                    report = """
                    set r to "off"
                    if not wasRepeating then set r to "all"
                    return s & "," & r & "," & (repeating enabled as text)
                    """
                }
            }
        case .music:
            switch action {
            case .read:
                change = ""
                report = """
                set r to "off"
                if song repeat is one then set r to "one"
                if song repeat is all then set r to "all"
                return (shuffle enabled as text) & "," & r & ",true"
                """
            case .toggleShuffle:
                if let known {
                    let target = known.shuffle == .off
                    change = """
                    set r to "off"
                    if song repeat is one then set r to "one"
                    if song repeat is all then set r to "all"
                    set shuffle enabled to \(target)
                    """
                    report = """
                    return "\(target)" & "," & r & ",true"
                    """
                } else {
                    change = """
                    set wasShuffling to shuffle enabled
                    set r to "off"
                    if song repeat is one then set r to "one"
                    if song repeat is all then set r to "all"
                    set shuffle enabled to not wasShuffling
                    """
                    report = """
                    return ((not wasShuffling) as text) & "," & r & ",true"
                    """
                }
            case .cycleRepeat:
                if let known {
                    // Off, all, one, and round again.
                    let next: String
                    switch known.repeating {
                    case .off: next = "all"
                    case .playlist: next = "one"
                    case .track: next = "off"
                    }
                    change = """
                    set s to (shuffle enabled as text)
                    set song repeat to \(next)
                    """
                    report = """
                    return s & ",\(next),true"
                    """
                } else {
                    change = """
                    set s to (shuffle enabled as text)
                    set r to "off"
                    if song repeat is off then
                    set song repeat to all
                    set r to "all"
                    else if song repeat is all then
                    set song repeat to one
                    set r to "one"
                    else
                    set song repeat to off
                    end if
                    """
                    report = """
                    return s & "," & r & ",true"
                    """
                }
            }
        }
        return [
            "if application id \"\(rawValue)\" is running then",
            "tell application id \"\(rawValue)\"", change, report, "end tell",
            "else", "error \"not running\"", "end if",
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    /// What a script said, or nil for anything else.
    static func modes(fromReply reply: String) -> NookPlayerModes? {
        let parts = reply.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",")
        guard parts.count == 3, let isAvailable = Bool(String(parts[2])) else { return nil }
        let shuffle: NowPlayingShuffle
        switch parts[0] {
        case "true": shuffle = .tracks
        case "false": shuffle = .off
        default: return nil
        }
        let repeating: NowPlayingRepeat
        switch parts[1] {
        case "off": repeating = .off
        case "one": repeating = .track
        case "all": repeating = .playlist
        default: return nil
        }
        return NookPlayerModes(shuffle: shuffle, repeating: repeating, isAvailable: isAvailable)
    }
}

/// What came back from one script.
enum NookPlayerScriptReply: Equatable, Sendable {
    case said(String)
    /// macOS did not let Hangover talk to the player.
    case refused
    case failed
}

/// Asks Spotify and Music about shuffle and repeat, and switches them.
///
/// macOS asks the user once per player before the first Apple Event goes
/// through. That question only ever follows a press of one of the two
/// buttons: until a player has been pressed for, nothing is sent to it, and
/// its buttons stay plain.
@MainActor
@Observable
final class NookPlayerScripts {
    typealias Runner = @Sendable (String) async -> NookPlayerScriptReply

    /// What each player last said, by its bundle identifier.
    private(set) var modes: [String: NookPlayerModes] = [:]
    /// The players macOS refused.
    private(set) var refused: Set<String> = []
    /// The script on its way. A test waits for it.
    @ObservationIgnored private(set) var inFlight: Task<Void, Never>?
    /// True while the script on its way only reads.
    @ObservationIgnored private var isReading = false
    /// What runs when the script on its way is back: a press that came
    /// during a read, or a read that came during anything.
    @ObservationIgnored private var waiting: (action: NookScriptedPlayer.Action, player: NookScriptedPlayer)?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let runner: Runner

    init(defaults: UserDefaults, runner: @escaping Runner = NookPlayerScripts.osascript) {
        self.defaults = defaults
        self.runner = runner
    }

    static func askedKey(_ player: NookScriptedPlayer) -> String {
        "nook.media.modes.asked.\(player.rawValue)"
    }

    /// True once this player has answered a press, with its modes or with
    /// a refusal. Either way macOS has asked the user and has an answer.
    func hasAsked(_ player: NookScriptedPlayer) -> Bool {
        defaults.bool(forKey: Self.askedKey(player))
    }

    /// A press of the shuffle or the repeat button. One script at a time. A
    /// press behind a read runs when the read is back. A press behind
    /// another press is dropped, which is what keeps presses from piling up
    /// behind the question macOS asks.
    func press(_ action: NookScriptedPlayer.Action, on player: NookScriptedPlayer) {
        guard inFlight == nil else {
            if isReading { waiting = (action, player) }
            return
        }
        start(action, on: player)
    }

    /// Reads where the player stands, when it has answered a press before.
    func refresh(_ player: NookScriptedPlayer) {
        guard hasAsked(player) else { return }
        guard inFlight == nil else {
            if waiting == nil { waiting = (.read, player) }
            return
        }
        start(.read, on: player)
    }

    private func start(_ action: NookScriptedPlayer.Action, on player: NookScriptedPlayer) {
        isReading = action == .read
        let source = player.script(action, knowing: modes[player.rawValue])
        inFlight = Task { @MainActor [weak self, runner] in
            let reply = await runner(source)
            self?.take(reply, from: player)
        }
    }

    private func take(_ reply: NookPlayerScriptReply, from player: NookScriptedPlayer) {
        inFlight = nil
        isReading = false
        defer {
            if let next = waiting {
                waiting = nil
                start(next.action, on: next.player)
            }
        }
        let id = player.rawValue
        if reply != .failed { defaults.set(true, forKey: Self.askedKey(player)) }
        switch reply {
        case .said(let text):
            // What a press came to, for the day a button looks dead: it is
            // three words and names no song.
            scriptLog.notice("\(id, privacy: .public) said \(text.trimmingCharacters(in: .whitespacesAndNewlines), privacy: .public)")
            refused.remove(id)
            if let said = NookScriptedPlayer.modes(fromReply: text) {
                if modes[id] != said { modes[id] = said }
            } else {
                scriptLog.warning("unreadable reply from \(id, privacy: .public)")
            }
        case .refused:
            refused.insert(id)
            modes[id] = nil
        case .failed:
            // The player quit, or the script could not run: what it last
            // said is no longer known to be true.
            modes[id] = nil
        }
    }

    /// Runs the script with `/usr/bin/osascript`, off the main thread: it
    /// waits for as long as the question macOS asks stays up.
    static let osascript: Runner = { source in
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                task.arguments = ["-e", source]
                let output = Pipe()
                let errors = Pipe()
                task.standardOutput = output
                task.standardError = errors
                do {
                    try task.run()
                } catch {
                    scriptLog.error("osascript did not start: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: .failed)
                    return
                }
                let said = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let complaint = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                task.waitUntilExit()
                if task.terminationStatus == 0 {
                    continuation.resume(returning: .said(said))
                } else if complaint.contains("-1743") {
                    continuation.resume(returning: .refused)
                } else {
                    scriptLog.warning("script failed: \(complaint, privacy: .public)")
                    continuation.resume(returning: .failed)
                }
            }
        }
    }
}
