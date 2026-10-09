import Foundation

/// Turning a switch on, off, or over.
enum IslandSwitchChange: String, Equatable, Sendable {
    case on
    case off
    case toggle

    func applied(to isOn: Bool) -> Bool {
        switch self {
        case .on: true
        case .off: false
        case .toggle: !isOn
        }
    }
}

/// What another app can ask the island to do with a `hangover://` link:
/// Shortcuts ("Open URL"), Raycast, a script. This list is all there is. A
/// link is read into one of these cases or thrown away, and nothing in a
/// link is ever run, opened or passed along.
///
///     hangover://nook                     open the island on the Nook page
///     hangover://agents                   open it on the agents page
///     hangover://timer/start              start the timer at its saved length
///     hangover://timer/start?minutes=25   start a timer of 25 minutes
///     hangover://timer/pomodoro           start a pomodoro
///     hangover://timer/stop               stop whatever is counting down
///     hangover://mirror/on                also off and toggle
///     hangover://ringlight/on             also off and toggle
///
/// The same links written `openisland://`, the upstream project's scheme,
/// read the same way under the same rules.
enum IslandURLAction: Equatable, Sendable {
    case openNook
    case openAgents
    /// Nil starts the timer at its saved length.
    case startTimer(minutes: Int?)
    case startPomodoro
    case stopTimer
    case setMirror(IslandSwitchChange)
    case setRingLight(IslandSwitchChange)

    /// Hangover's own scheme, the one the release bundle registers.
    static let scheme = "hangover"
    /// The upstream project's scheme. The parser still reads it, which
    /// keeps links written for it working, and only the dev bundle still
    /// registers it.
    static let upstreamScheme = "openisland"
    /// Every scheme the parser reads. The rules are the same for each.
    static let acceptedSchemes: Set<String> = [scheme, upstreamScheme]
    /// A minute to a day, the same span the timer card takes when typed.
    static let minutesRange = 1...(24 * 60)
    /// Longer than any real link. Anything past it is not read at all.
    static let maxLength = 200

    /// Whether the action shows the island. The ones that do not leave the
    /// keyboard with the app the user was in.
    var opensIsland: Bool {
        switch self {
        case .openNook, .openAgents: true
        case .setMirror(let change): change != .off
        case .startTimer, .startPomodoro, .stopTimer, .setRingLight: false
        }
    }

    /// Reads a link. Strict on purpose: a wrong scheme, an unknown word, a
    /// part too many, or minutes that are not a whole number in range all
    /// fail, and the caller ignores the link.
    static func parse(_ url: URL) -> Result<IslandURLAction, IslandURLActionError> {
        guard url.absoluteString.count <= maxLength else { return .failure(.malformed) }
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let linkScheme = parts.scheme?.lowercased(),
              acceptedSchemes.contains(linkScheme) else {
            return .failure(.wrongScheme)
        }
        guard parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil else {
            return .failure(.malformed)
        }
        // "hangover://timer/start" and "hangover:/timer/start" read the same.
        let words = ([parts.host ?? ""] + parts.path.split(separator: "/").map(String.init))
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
        let query = parts.queryItems ?? []

        if words == ["timer", "start"] {
            return minutes(from: query).map { .startTimer(minutes: $0) }
        }
        // Only a timer start takes anything after the question mark.
        guard query.isEmpty else { return .failure(.malformed) }

        switch words.count {
        case 1:
            switch words[0] {
            case "nook": return .success(.openNook)
            case "agents": return .success(.openAgents)
            default: return .failure(.unknownAction(label(words)))
            }
        case 2:
            switch (words[0], words[1]) {
            case ("timer", "pomodoro"): return .success(.startPomodoro)
            case ("timer", "stop"): return .success(.stopTimer)
            case ("mirror", let word):
                guard let change = IslandSwitchChange(rawValue: word) else { break }
                return .success(.setMirror(change))
            case ("ringlight", let word):
                guard let change = IslandSwitchChange(rawValue: word) else { break }
                return .success(.setRingLight(change))
            default: break
            }
            return .failure(.unknownAction(label(words)))
        default:
            return .failure(.unknownAction(label(words)))
        }
    }

    /// No query starts the saved length. Otherwise exactly one `minutes`
    /// made of digits, inside `minutesRange`.
    private static func minutes(from query: [URLQueryItem]) -> Result<Int?, IslandURLActionError> {
        guard !query.isEmpty else { return .success(nil) }
        guard query.count == 1, query[0].name == "minutes", let text = query[0].value else {
            return .failure(.malformed)
        }
        guard !text.isEmpty, text.count <= 4, text.allSatisfy({ ("0"..."9").contains($0) }),
              let value = Int(text), minutesRange.contains(value) else {
            return .failure(.badMinutes)
        }
        return .success(value)
    }

    /// The words of a link that was not understood, cleaned and cut short
    /// for the log.
    private static func label(_ words: [String]) -> String {
        IslandLinkLog.clean(words.joined(separator: "/"), limit: 40)
    }
}

/// Link text on its way to the log. A link is written by someone else, and
/// a percent-encoded line break or NUL in it must not reach the log as
/// one.
enum IslandLinkLog {
    /// Longer than any real link's readable part.
    static let limit = 120

    /// The text with every control and formatting character taken out, cut
    /// to `limit` characters.
    static func clean(_ text: String, limit: Int = IslandLinkLog.limit) -> String {
        let kept = text.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .privateUse, .unassigned:
                false
            default:
                true
            }
        }
        return String(String(kept).prefix(limit))
    }

    /// The line for a link whose text is not a URL at all.
    static func unreadableLine(for text: String?) -> String {
        guard let text, !text.isEmpty else { return "no link text" }
        return "not a URL \"\(clean(text, limit: 40))\""
    }
}

enum IslandURLActionError: Error, Equatable, Sendable {
    case wrongScheme
    case malformed
    case badMinutes
    case unknownAction(String)

    /// One line for the log.
    var logLine: String {
        switch self {
        case .wrongScheme: "not a hangover link"
        case .malformed: "malformed link"
        case .badMinutes: "minutes must be a whole number from 1 to 1440"
        case .unknownAction(let words): "unknown action \"\(words)\""
        }
    }
}

/// What a page action does given what the island is showing. Pure; the app
/// model gathers the facts and acts on the answer.
enum IslandURLPageMove: Equatable, Sendable {
    /// The island is closed: open it on the page.
    case open
    /// It is open on a list or the Nook: turn to the page and keep it open.
    case turn
    /// A card is up, or an approval or a question is on screen in the open
    /// list. Neither is ever pushed aside.
    case refuse

    /// `showsWaitingRequest` is true while the open island shows an
    /// approval or a question in a row of its list. A card is told by the
    /// open reason alone.
    static func resolve(
        status: NotchStatus,
        reason: NotchOpenReason?,
        showsWaitingRequest: Bool
    ) -> IslandURLPageMove {
        guard status == .opened else { return .open }
        return reason == .notification || showsWaitingRequest ? .refuse : .turn
    }

    /// Whether turning the page also pins the island open, the way a click
    /// inside it would. A hover-opened island would close when the pointer
    /// leaves, and the boot animation closes what it opened a moment later.
    /// A link asked for the page, and it stays until a click outside.
    static func pinsOnTurn(reason: NotchOpenReason?) -> Bool {
        reason == .hover || reason == .boot
    }
}
