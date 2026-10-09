import AppKit
import Foundation

/// Finds the video-meeting link in a calendar event and opens it.
///
/// Event text comes from whoever sent the invite, which makes it untrusted.
/// A link only counts when it is https on a known meeting service, or when
/// it is a meeting app's own link that does nothing but join a meeting.
/// Nothing else in an event is ever opened.
enum NookMeetingLink {
    /// Zoom's hosts. Its app links are held to the same list.
    static let zoomHosts = ["zoom.us", "zoomgov.com"]
    /// Teams' hosts. A Teams app link may name one of them or no host.
    static let teamsHosts = ["teams.microsoft.com", "teams.live.com"]

    /// Hosts that serve meetings. A subdomain counts ("ucla.zoom.us"); a
    /// look-alike that only starts with the name does not
    /// ("zoom.us.evil.example").
    static let hosts = zoomHosts + ["meet.google.com"] + teamsHosts + [
        "webex.com", "facetime.apple.com", "whereby.com", "meet.jit.si",
    ]

    /// Schemes that open a meeting app straight away. The scheme alone is
    /// not enough: see `isJoinLink`.
    static let appSchemes: Set<String> = ["zoommtg", "zoomus", "msteams"]

    /// The one path a Zoom app link may carry.
    static let zoomJoinPath = "/join"
    /// What a Teams app link's path must start with. Its other paths start
    /// a call or a chat with whoever the link names.
    static let teamsJoinPrefix = "/l/meetup-join/"

    /// What a real host name is made of. A percent sign is not part of it:
    /// "evil.example%2f.zoom.us" decodes to a name that ends in ".zoom.us"
    /// and still belongs to someone else.
    private static let hostCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")

    /// Built once; making a detector per event is slow on a busy calendar.
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// A meeting-app link in running text: one of `appSchemes`, a colon, and
    /// everything up to the next space, quote or angle bracket.
    private static let appLinkPattern = try? NSRegularExpression(
        pattern: "\\b(?:" + appSchemes.sorted().joined(separator: "|") + "):[^\\s<>\"']+",
        options: [.caseInsensitive]
    )

    /// The first video-meeting link found in an event's URL, location or notes.
    static func find(in candidates: [String?]) -> URL? {
        for text in candidates.compactMap({ $0 }) {
            let lower = text.lowercased()
            if hosts.contains(where: lower.contains), let url = webLink(in: text) { return url }
            if appSchemes.contains(where: { lower.contains($0 + ":") }), let url = appLink(in: text) { return url }
        }
        return nil
    }

    /// The link as it may be opened, or nil when it must not be. A plain
    /// http link to a meeting service comes back as https.
    static func safeURL(from url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(),
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil
        else { return nil }
        if appSchemes.contains(scheme) {
            return isJoinLink(scheme: scheme, parts: parts) ? url : nil
        }
        guard scheme == "https" || scheme == "http",
              hasHost(parts, among: hosts),
              // The service's front page is not a meeting.
              parts.path.count > 1 || parts.query != nil || parts.fragment != nil
        else { return nil }
        if scheme == "https" { return url }
        parts.scheme = "https"
        return parts.url
    }

    /// True when the link names one of `allowed` or a subdomain of one.
    /// The host is read as it was written, before any percent-decoding,
    /// and must be made of plain host characters only.
    private static func hasHost(_ parts: URLComponents, among allowed: [String]) -> Bool {
        guard let host = parts.encodedHost?.lowercased(), !host.isEmpty,
              host.unicodeScalars.allSatisfy(hostCharacters.contains)
        else { return false }
        return allowed.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Whether a meeting app's link only joins a meeting. The app decides
    /// what the rest of a link means, which is why the rest is pinned down
    /// here: a Zoom link must name a Zoom host and the join path, and a
    /// Teams link must be a meetup-join link. A call or chat link, another
    /// host, or a path that climbs out with ".." is refused.
    private static func isJoinLink(scheme: String, parts: URLComponents) -> Bool {
        guard parts.port == nil else { return false }
        // Paths are compared as written, which keeps a percent-encoded
        // spelling of a path from passing for the plain one.
        let path = parts.percentEncodedPath
        switch scheme {
        case "zoommtg", "zoomus":
            return hasHost(parts, among: zoomHosts) && path == zoomJoinPath
        case "msteams":
            guard path.hasPrefix(teamsJoinPrefix), path.count > teamsJoinPrefix.count,
                  !parts.path.contains("\\"),
                  !parts.path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == "." || $0 == ".." })
            else { return false }
            return (parts.encodedHost ?? "").isEmpty || hasHost(parts, among: teamsHosts)
        default:
            return false
        }
    }

    /// True for a link `safeURL` would hand back unchanged.
    static func isAllowed(_ url: URL) -> Bool {
        safeURL(from: url) == url
    }

    /// Opens a meeting link in its default handler. Anything `isAllowed`
    /// turns down is left alone, and false comes back.
    @discardableResult
    static func open(_ url: URL, using opener: (URL) -> Void = { NSWorkspace.shared.open($0) }) -> Bool {
        guard isAllowed(url) else { return false }
        opener(url)
        return true
    }

    private static func webLink(in text: String) -> URL? {
        guard let detector else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, options: [], range: range) {
            if let url = match.url.flatMap(safeURL(from:)) { return url }
        }
        return nil
    }

    private static func appLink(in text: String) -> URL? {
        guard let appLinkPattern else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in appLinkPattern.matches(in: text, options: [], range: range) {
            guard let found = Range(match.range, in: text) else { continue }
            // A link at the end of a sentence drags its punctuation along.
            let trimmed = text[found].trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}"))
            if let url = URL(string: trimmed).flatMap(safeURL(from:)) { return url }
        }
        return nil
    }
}

/// When the Join bar offers a meeting: from ten minutes before it starts
/// until fifteen minutes in, or until it ends if that comes first. After
/// that the event's own row still carries its join mark.
enum NookMeetingPrompt {
    static let lead: TimeInterval = 10 * 60
    static let lateWindow: TimeInterval = 15 * 60

    /// The meeting to offer right now: the earliest one whose window is
    /// open and that has not been joined or put away.
    static func current(
        events: [NookCalendarEvent],
        now: Date,
        dismissed: Set<String> = []
    ) -> NookCalendarEvent? {
        events
            .filter { isOpen(for: $0, now: now) && !dismissed.contains($0.id) }
            .min { $0.start < $1.start }
    }

    static func isOpen(for event: NookCalendarEvent, now: Date) -> Bool {
        guard !event.isAllDay, event.meetingURL != nil else { return false }
        let lateEdge = event.start.addingTimeInterval(lateWindow)
        // An event with no length still gets the late window.
        let closes = event.end > event.start ? min(event.end, lateEdge) : lateEdge
        return now >= event.start.addingTimeInterval(-lead) && now < closes
    }

    /// Whole minutes from `now` to the start: positive before it, zero
    /// within the first minute, negative once it is under way.
    static func minutesUntilStart(_ start: Date, now: Date) -> Int {
        let seconds = start.timeIntervalSince(now)
        return seconds > 0 ? Int((seconds / 60).rounded(.up)) : -Int((-seconds / 60).rounded(.down))
    }
}
