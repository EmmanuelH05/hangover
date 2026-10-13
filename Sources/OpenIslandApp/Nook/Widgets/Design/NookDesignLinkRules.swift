import Foundation

/// Why a piece of text was not taken as a link.
enum NookDesignLinkRefusal: Error, Equatable, Sendable {
    /// Nothing, or only blanks.
    case empty
    /// More than `NookDesignLinkRules.maxLength` characters.
    case tooLong
    /// Not an `http` or `https` link with a host: another scheme such as
    /// `javascript:`, `file:`, `data:` or `mailto:`, a scheme with no host,
    /// a host with a space in it, or text that is no web address at all.
    case notAWebLink
    /// A user name or a password stands in front of the host.
    case hasCredentials

    /// The line the card shows.
    var noticeKey: String {
        switch self {
        case .empty: "nook.design.notice.linkEmpty"
        case .tooLong: "nook.design.notice.linkTooLong"
        case .notAWebLink: "nook.design.notice.linkNotWeb"
        case .hasCredentials: "nook.design.notice.linkCredentials"
        }
    }
}

/// A web address that passed the rules, in the parts the kit needs.
struct NookDesignLinkAddress: Equatable, Sendable {
    /// The whole address as it is saved and opened. Exactly what was typed
    /// after the blanks around it were trimmed, with `https://` in front
    /// when it came without a scheme. Nothing in it is changed, dropped or
    /// put in another order, the query and the fragment included: a Figma
    /// link to one frame lives in them.
    let url: String
    /// The host as written. Its case is kept.
    let host: String
    /// The path as written, up to the query or the fragment. Empty when the
    /// address has none.
    let path: String
}

/// The kinds of Figma link the card names in plain words.
enum NookDesignFigmaKind: String, CaseIterable, Sendable {
    case design, file, board, proto, slides, make

    /// The path starts with this word between slashes: `/design/`.
    var pathPrefix: String { "/\(rawValue)/" }

    var titleKey: String {
        switch self {
        case .design: "nook.design.links.figma.design"
        case .file: "nook.design.links.figma.file"
        case .board: "nook.design.links.figma.board"
        case .proto: "nook.design.links.figma.proto"
        case .slides: "nook.design.links.figma.slides"
        case .make: "nook.design.links.figma.make"
        }
    }
}

/// A link on `figma.com` or a subdomain of it. `kind` is nil when the path
/// is none of the known ones.
struct NookDesignFigmaLink: Equatable, Sendable {
    var kind: NookDesignFigmaKind?
}

/// Pure rules for the Links tab: what counts as a link, what it is called,
/// and the order the card lists it in. A plain enum on purpose, called by
/// the store, the views and the tests alike.
enum NookDesignLinkRules {
    /// A link longer than this is refused. Counted in Unicode scalars, as
    /// it is saved (the blanks around it trimmed, `https://` in front when
    /// it came without a scheme), which keeps a pile of combining marks
    /// from passing as one short character.
    static let maxLength = 2_048
    /// Text longer than this many bytes is refused before it is looked at,
    /// which keeps a huge clipboard from being scanned.
    static let maxInputBytes = 65_536
    static let maxLinks = 200
    static let maxCollections = 24
    static let maxNameLength = 80

    // MARK: What counts as a link

    /// Reads typed or pasted text as a web address, or says why not.
    ///
    /// Taken: `http` and `https` (in any case) with a host, and text with no
    /// scheme that reads as a host with a dot, which gets `https://` in
    /// front. The host may be a name, a unicode name, an IPv4 address or an
    /// IPv6 address in brackets, with an optional port and a trailing dot.
    ///
    /// Refused: empty text, any other scheme, a scheme with no host, a user
    /// name or password, a blank or a control character anywhere, a host
    /// with a character a host cannot have (a percent sign included), and
    /// anything over `maxLength`. A path with a space in it is refused too,
    /// because the address is opened exactly as saved and the system would
    /// have to change it to open it.
    static func address(from text: String) -> Result<NookDesignLinkAddress, NookDesignLinkRefusal> {
        guard text.utf8.count <= maxInputBytes else { return .failure(.tooLong) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard trimmed.unicodeScalars.count <= maxLength else { return .failure(.tooLong) }
        guard !trimmed.unicodeScalars.contains(where: isInvisibleOrBlank) else { return .failure(.notAWebLink) }

        // Every part is found by scalar. A combining mark after a slash, an at
        // sign or a colon would join it into one Character and hide it.
        let scalars = Array(trimmed.unicodeScalars)
        let hasScheme: Bool
        let rest: ArraySlice<Unicode.Scalar>
        switch splitScheme(scalars) {
        case let .web(afterSlashes):
            hasScheme = true
            rest = afterSlashes
        case .none:
            hasScheme = false
            rest = scalars[...]
        case .other:
            return .failure(.notAWebLink)
        }

        let end = rest.firstIndex { $0 == "/" || $0 == "?" || $0 == "#" } ?? rest.endIndex
        let authority = rest[..<end]
        let remainder = rest[end...]
        guard !authority.isEmpty else { return .failure(.notAWebLink) }
        if authority.contains("@") {
            return .failure(hasScheme ? .hasCredentials : .notAWebLink)
        }
        guard let host = host(in: authority, requiresDot: !hasScheme) else { return .failure(.notAWebLink) }

        let url = hasScheme ? trimmed : "https://" + trimmed
        // The limit is on the link as it is saved, `https://` included.
        guard url.unicodeScalars.count <= maxLength else { return .failure(.tooLong) }
        guard URL(string: url) != nil else { return .failure(.notAWebLink) }
        let pathEnd = remainder.firstIndex { $0 == "?" || $0 == "#" } ?? remainder.endIndex
        return .success(NookDesignLinkAddress(url: url, host: host, path: string(remainder[..<pathEnd])))
    }

    /// True for an address that is already a whole, valid link as saved:
    /// nothing to trim, a scheme in place. What is read from a file or
    /// opened goes through this, and an address that fails it is left out.
    static func isStorable(_ url: String) -> Bool {
        if case let .success(address) = address(from: url) { return address.url == url }
        return false
    }

    /// The address to hand to the opener. It is made from the saved text
    /// as it is. Nil for a text that is not a link.
    static func openableURL(for saved: String) -> URL? {
        isStorable(saved) ? URL(string: saved) : nil
    }

    private typealias Scalars = ArraySlice<Unicode.Scalar>

    private static func string(_ scalars: Scalars) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    private enum SchemeSplit {
        /// `http://` or `https://`, in any case, and what follows it.
        case web(Scalars)
        /// Another scheme, or a scheme with no `//`.
        case other
        /// No scheme: a host written bare, with or without a port.
        case none
    }

    /// Tells a scheme from a host with a port. `localhost:3000` and
    /// `example.com:8080/x` have a colon too, and a number after it.
    private static func splitScheme(_ text: [Unicode.Scalar]) -> SchemeSplit {
        guard let colon = text.firstIndex(of: ":") else { return .none }
        let name = text[..<colon]
        guard let first = name.first, first.isASCII, first.properties.isAlphabetic, name.allSatisfy(isSchemeScalar) else {
            return .none
        }
        let afterColon = text[(colon + 1)...]
        if afterColon.starts(with: ["/", "/"]) {
            let lowered = string(name).lowercased()
            return lowered == "http" || lowered == "https" ? .web(afterColon.dropFirst(2)) : .other
        }
        // A port: digits, then the end or the start of the path.
        let digits = afterColon.prefix { isDigit($0) }
        let after = afterColon.dropFirst(digits.count)
        if !digits.isEmpty, after.isEmpty || after.first == "/" || after.first == "?" || after.first == "#" { return .none }
        return .other
    }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        ("0"..."9").contains(scalar)
    }

    private static func isSchemeScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII && (scalar.properties.isAlphabetic || isDigit(scalar) || scalar == "+" || scalar == "-" || scalar == ".")
    }

    /// A blank, a control character or an invisible format character such
    /// as a zero width space, anywhere in the text.
    private static func isInvisibleOrBlank(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.isWhitespace { return true }
        switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator, .spaceSeparator, .unassigned, .privateUse, .surrogate:
            return true
        default:
            return false
        }
    }

    /// The host of an authority (`host`, `host:port`, `[v6]` or
    /// `[v6]:port`), or nil when it is not one a link can have.
    private static func host(in authority: Scalars, requiresDot: Bool) -> String? {
        var hostPart = authority
        var port: Scalars?
        if authority.first == "[" {
            guard let close = authority.firstIndex(of: "]") else { return nil }
            let inside = authority[(authority.startIndex + 1)..<close]
            guard isIPv6(inside) else { return nil }
            let after = authority[(close + 1)...]
            if !after.isEmpty {
                guard after.first == ":" else { return nil }
                port = after.dropFirst()
            }
            if requiresDot, !inside.contains(".") { return nil }
            return isPort(port) ? string(authority[...close]) : nil
        }
        if let colon = authority.lastIndex(of: ":") {
            hostPart = authority[..<colon]
            port = authority[(colon + 1)...]
        }
        guard isPort(port), isHostName(hostPart, requiresDot: requiresDot) else { return nil }
        return string(hostPart)
    }

    /// No port at all is fine. A port is one to five digits, 65535 at most.
    private static func isPort(_ port: Scalars?) -> Bool {
        guard let port else { return true }
        guard !port.isEmpty, port.count <= 5, port.allSatisfy(isDigit),
              let value = Int(string(port)) else { return false }
        return (0...65_535).contains(value)
    }

    private static func isIPv6(_ text: Scalars) -> Bool {
        guard text.filter({ $0 == ":" }).count >= 2 else { return false }
        return text.allSatisfy { $0 == ":" || $0 == "." || ($0.isASCII && $0.properties.isASCIIHexDigit) }
    }

    /// A name of non-empty labels joined by dots, with one dot allowed at
    /// the end. Letters and numbers of any script, hyphens and underscores
    /// are fine. A host of numbers only must be a whole IPv4 address.
    private static func isHostName(_ text: Scalars, requiresDot: Bool) -> Bool {
        var name = text
        if name.last == "." { name = name.dropLast() }
        guard !name.isEmpty, name.count <= 253 else { return false }
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ !$0.isEmpty && $0.count <= 63 && $0.allSatisfy(isHostScalar) }) else { return false }
        if requiresDot, labels.count < 2 { return false }
        if labels.allSatisfy({ $0.allSatisfy(isDigit) }) {
            return labels.count == 4 && labels.allSatisfy { (Int(string($0)) ?? 256) <= 255 }
        }
        return true
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

    // MARK: Names

    /// A name as it is kept: the kit's own name cleaning, at 80 characters.
    static func cleanName(_ name: String) -> String {
        NookDesignNames.clean(name, limit: maxNameLength)
    }

    /// What a new link is called: the host, then a slash and the last part
    /// of the path when there is one. Made from the address alone. Nothing
    /// is fetched, which means no page title is ever known.
    static func defaultName(for address: NookDesignLinkAddress) -> String {
        let last = address.path.unicodeScalars.split(separator: "/").last.map { String(String.UnicodeScalarView($0)) }
        return cleanName(last.map { "\(address.host)/\($0)" } ?? address.host)
    }

    // MARK: Figma

    /// Whether the link is on `figma.com` or a subdomain of it, and which
    /// kind of Figma link its path says. `notfigma.com` and
    /// `figma.com.example.org` are not Figma.
    static func figma(for address: NookDesignLinkAddress) -> NookDesignFigmaLink? {
        var host = address.host.lowercased()
        if host.hasSuffix(".") { host.removeLast() }
        guard host == "figma.com" || host.hasSuffix(".figma.com") else { return nil }
        let kind = NookDesignFigmaKind.allCases.first { address.path.unicodeScalars.starts(with: $0.pathPrefix.unicodeScalars) }
        return NookDesignFigmaLink(kind: kind)
    }

    // MARK: Order

    /// The order the card lists the links in: favorites first, then the
    /// rest. Each group goes by the latest of when a link was opened and
    /// when it was added, newest first. Two links with the same moment go
    /// by when they were added, newest first, and then by their place in
    /// `links`. A favorite that is opened moves up among the favorites.
    static func ordered(_ links: [NookDesignLink]) -> [NookDesignLink] {
        links.enumerated().sorted { first, second in
            let (a, b) = (first.element, second.element)
            if a.isFavorite != b.isFavorite { return a.isFavorite }
            if a.recency != b.recency { return a.recency > b.recency }
            if a.addedAt != b.addedAt { return a.addedAt > b.addedAt }
            return first.offset < second.offset
        }.map(\.element)
    }
}
