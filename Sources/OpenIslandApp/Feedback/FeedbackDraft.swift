import Foundation

/// What a piece of feedback is about. The raw value keys the localized
/// title; the subject tag stays English because the developer reads it.
enum FeedbackKind: String, CaseIterable, Sendable {
    case bug
    case idea
    case other

    var titleKey: String { "feedback.kind.\(rawValue)" }

    var subjectTag: String {
        switch self {
        case .bug: "Bug"
        case .idea: "Idea"
        case .other: "Something else"
        }
    }
}

/// The app and Mac facts the details switch adds to a draft, and nothing
/// else (F7). The model is the `hw.model` identifier such as Mac15,12,
/// never a marketing name.
struct FeedbackDetails: Equatable, Sendable {
    var version: String
    var build: String
    var macOS: String
    var model: String

    /// "Version 1.0.13 (1505), macOS 26.4, Mac15,12"
    var line: String {
        "Version \(version) (\(build)), macOS \(macOS), \(model)"
    }

    static func current() -> FeedbackDetails {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osText = os.patchVersion == 0
            ? "\(os.majorVersion).\(os.minorVersion)"
            : "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        return FeedbackDetails(
            version: AppBrand.currentVersion,
            build: AppBrand.currentBuild,
            macOS: osText,
            model: macModelIdentifier()
        )
    }

    private static func macModelIdentifier() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "Unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "Unknown" }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

struct FeedbackDraft: Equatable, Sendable {
    var kind: FeedbackKind = .bug
    var text: String = ""
    var includesDetails: Bool = true

    static let subjectLineLimit = 80

    func subject(appName: String) -> String {
        let tag = "[\(appName) \(kind.subjectTag)]"
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let firstLine else { return tag }
        return "\(tag) \(String(firstLine.prefix(Self.subjectLineLimit)))"
    }

    func body(details: FeedbackDetails) -> String {
        guard includesDetails else { return text }
        return "\(text)\n\n\(details.line)"
    }

    func mailtoURL(to address: String, appName: String, details: FeedbackDetails) -> URL? {
        let subject = Self.encode(subject(appName: appName))
        let body = Self.encode(body(details: details))
        return URL(string: "mailto:\(address)?subject=\(subject)&body=\(body)")
    }

    /// RFC 6068: everything outside the unreserved characters is
    /// percent-encoded, and every line break goes out as CRLF.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    static func encode(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
        return normalized.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}
