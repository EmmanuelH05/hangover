import Foundation

/// Why a piece of text was not taken as a link to save.
enum NookLinkAudioLinkRefusal: Error, Equatable, Sendable {
    /// Nothing, or only blanks.
    case empty
    /// More than `NookLinkAudioLink.maxLength` characters.
    case tooLong
    /// Not an `http` or `https` link with a host. A word, another scheme
    /// such as `file:` or `javascript:`, a host a host cannot be, or text
    /// that starts with a dash and could be read as an option.
    case notAWebLink
    /// A space or a control character stands inside the text.
    case hasBlankOrControl
    /// A user name or a password stands in front of the host.
    case hasCredentials

    /// The line the card shows.
    var noticeKey: String {
        switch self {
        case .empty: "nook.linkAudio.problem.empty"
        case .tooLong: "nook.linkAudio.problem.tooLong"
        case .notAWebLink: "nook.linkAudio.problem.notWeb"
        case .hasBlankOrControl: "nook.linkAudio.problem.blank"
        case .hasCredentials: "nook.linkAudio.problem.credentials"
        }
    }
}

/// A link that passed the rules. The only way to make one is `check`, and
/// the argument list takes nothing else, which keeps text that was never
/// looked at from reaching `yt-dlp`.
struct NookLinkAudioLink: Equatable, Hashable, Sendable {
    /// The most characters a link may have, counted as Unicode scalars.
    static let maxLength = 2_048
    /// Text longer than this many bytes is refused before it is looked at,
    /// which keeps a huge clipboard from being scanned.
    static let maxInputBytes = 65_536

    /// The link as it is handed on: what was typed, with the blanks around
    /// it trimmed. Nothing in it is changed.
    let text: String

    private init(text: String) {
        self.text = text
    }

    /// Reads typed or pasted text as a link to save, or says why not.
    ///
    /// Taken: `http` and `https` (in any case) with a host, up to
    /// `maxLength` characters, with no space and no control character in
    /// it, and no user name or password in front of the host.
    ///
    /// Everything else is refused, text that starts with a dash included:
    /// it has no scheme, which makes it no link at all.
    static func check(_ input: String) -> Result<NookLinkAudioLink, NookLinkAudioLinkRefusal> {
        guard input.utf8.count <= maxInputBytes else { return .failure(.tooLong) }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard trimmed.unicodeScalars.count <= maxLength else { return .failure(.tooLong) }

        // Every part is found by scalar. A combining mark after a slash or
        // an at sign would join it into one Character and hide it.
        let scalars = Array(trimmed.unicodeScalars)
        guard let afterScheme = schemeEnd(of: scalars) else { return .failure(.notAWebLink) }
        guard !scalars.contains(where: isBlankOrControl) else { return .failure(.hasBlankOrControl) }

        let rest = scalars[afterScheme...]
        let end = rest.firstIndex { $0 == "/" || $0 == "?" || $0 == "#" } ?? rest.endIndex
        let authority = rest[..<end]
        guard !authority.isEmpty else { return .failure(.notAWebLink) }
        if authority.contains("@") { return .failure(.hasCredentials) }
        guard isHostAndPort(authority) else { return .failure(.notAWebLink) }
        guard URL(string: trimmed) != nil else { return .failure(.notAWebLink) }
        return .success(NookLinkAudioLink(text: trimmed))
    }

    // MARK: Parts

    /// The index just past `http://` or `https://`, in any case, or nil.
    private static func schemeEnd(of scalars: [Unicode.Scalar]) -> Int? {
        for scheme in ["http://", "https://"] {
            let count = scheme.unicodeScalars.count
            guard scalars.count > count else { continue }
            let head = String(String.UnicodeScalarView(scalars[..<count]))
            if head.lowercased() == scheme { return count }
        }
        return nil
    }

    /// A blank, a control character or an invisible format character such
    /// as a zero width space, anywhere in the text.
    private static func isBlankOrControl(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.isWhitespace { return true }
        switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator, .spaceSeparator, .unassigned, .privateUse, .surrogate:
            return true
        default:
            return false
        }
    }

    private typealias Scalars = ArraySlice<Unicode.Scalar>

    /// `host`, `host:port`, `[v6]` or `[v6]:port`, with a host that has at
    /// least one character.
    private static func isHostAndPort(_ authority: Scalars) -> Bool {
        var host = authority
        var port: Scalars?
        if authority.first == "[" {
            guard let close = authority.firstIndex(of: "]") else { return false }
            let inside = authority[(authority.startIndex + 1)..<close]
            guard isIPv6(inside) else { return false }
            let after = authority[(close + 1)...]
            if !after.isEmpty {
                guard after.first == ":" else { return false }
                port = after.dropFirst()
            }
            return isPort(port)
        }
        if let colon = authority.lastIndex(of: ":") {
            host = authority[..<colon]
            port = authority[(colon + 1)...]
        }
        return isPort(port) && isHostName(host)
    }

    /// No port at all is fine. A port is one to five digits, 65535 at most.
    private static func isPort(_ port: Scalars?) -> Bool {
        guard let port else { return true }
        guard !port.isEmpty, port.count <= 5, port.allSatisfy(isDigit),
              let value = Int(String(String.UnicodeScalarView(port))) else { return false }
        return (0...65_535).contains(value)
    }

    private static func isIPv6(_ text: Scalars) -> Bool {
        guard text.filter({ $0 == ":" }).count >= 2 else { return false }
        return text.allSatisfy { $0 == ":" || $0 == "." || ($0.isASCII && $0.properties.isASCIIHexDigit) }
    }

    /// Labels of letters, numbers, hyphens and underscores joined by dots,
    /// one dot allowed at the end. Letters and numbers of any script count.
    private static func isHostName(_ text: Scalars) -> Bool {
        var name = text
        if name.last == "." { name = name.dropLast() }
        guard !name.isEmpty, name.count <= 253 else { return false }
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { !$0.isEmpty && $0.count <= 63 && $0.allSatisfy(isHostScalar) }
    }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        ("0"..."9").contains(scalar)
    }

    private static func isHostScalar(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.isASCII {
            return scalar.properties.isAlphabetic || isDigit(scalar) || scalar == "-" || scalar == "_"
        }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .nonspacingMark, .spacingMark, .decimalNumber:
            return true
        default:
            return false
        }
    }
}
