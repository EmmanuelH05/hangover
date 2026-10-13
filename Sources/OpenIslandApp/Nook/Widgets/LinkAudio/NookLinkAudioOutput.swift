import Foundation

/// What one line of `yt-dlp`'s output says.
enum NookLinkAudioLine: Equatable, Sendable {
    /// The download moved. `fraction` is nil while no size is known.
    /// `isDownloadDone` is true for the line that closes the download, after
    /// which `ffmpeg` makes the MP3. `fileName` is the file being written.
    case progress(fraction: Double?, isDownloadDone: Bool, fileName: String?)
    case title(String)
    /// The finished file's path.
    case file(String)
    /// One of `yt-dlp`'s own error lines, without its `ERROR:` mark.
    case error(String)
    case other
}

/// Reads the lines `NookLinkAudioArguments` asks `yt-dlp` for. A line that
/// is not one of them, or one that is cut short, is `.other` and changes
/// nothing: a template `yt-dlp` read differently must not break a job.
///
/// The title and the paths come as JSON strings. A title is the site's to
/// write, and a newline in it would otherwise end the line and let the rest
/// pass for a line of `yt-dlp`'s own. In JSON it is the two characters `\n`.
/// A value that is not a JSON string is read as nothing.
enum NookLinkAudioOutput {
    static func parse(_ rawLine: String) -> NookLinkAudioLine {
        let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
        if let rest = value(of: line, after: NookLinkAudioArguments.progressMarker) {
            return progress(rest)
        }
        if let rest = value(of: line, after: NookLinkAudioArguments.titleMarker) {
            guard let title = text(fromJSON: rest) else { return .other }
            let shown = oneLine(title)
            return shown.isEmpty ? .other : .title(shown)
        }
        if let rest = value(of: line, after: NookLinkAudioArguments.fileMarker) {
            guard let path = text(fromJSON: rest), !path.isEmpty else { return .other }
            return .file(path)
        }
        if line.hasPrefix(errorMark) {
            let message = line.dropFirst(errorMark.count).trimmingCharacters(in: .whitespaces)
            return message.isEmpty ? .other : .error(message)
        }
        return .other
    }

    private static let errorMark = "ERROR:"

    /// The text after `marker` and one space, when the line starts with it.
    private static func value(of line: String, after marker: String) -> String? {
        guard line.hasPrefix(marker + " ") else { return nil }
        return String(line.dropFirst(marker.count + 1))
    }

    /// The string a JSON string stands for. Nil for anything else, `null`
    /// (what `yt-dlp` prints for a value it does not have) included.
    private static func text(fromJSON json: some StringProtocol) -> String? {
        let trimmed = json.trimmingCharacters(in: .whitespaces)
        return try? JSONDecoder().decode(String.self, from: Data(trimmed.utf8))
    }

    /// A title as one line for a row: a line break or another control
    /// character becomes a space, and the blanks around it go.
    static func oneLine(_ title: String) -> String {
        var cleaned = String.UnicodeScalarView()
        for scalar in title.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator: cleaned.append(" ")
            default: cleaned.append(scalar)
            }
        }
        return String(cleaned).trimmingCharacters(in: .whitespaces)
    }

    /// `status downloaded total estimate file name`.
    private static func progress(_ rest: String) -> NookLinkAudioLine {
        let parts = rest.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
        guard parts.count >= 4 else { return .other }
        let status = String(parts[0])
        let isDone = status == "finished"
        let fileName = parts.count == 5 ? text(fromJSON: parts[4]).flatMap { $0.isEmpty ? nil : $0 } : nil
        guard status == "downloading" || isDone else { return .other }
        let done = number(parts[1])
        let total = number(parts[2]).flatMap { $0 > 0 ? $0 : nil } ?? number(parts[3]).flatMap { $0 > 0 ? $0 : nil }
        let fraction: Double? = if isDone {
            1
        } else if let done, let total {
            min(max(done / total, 0), 1)
        } else {
            nil
        }
        return .progress(fraction: fraction, isDownloadDone: isDone, fileName: fileName)
    }

    private static func number(_ text: Substring) -> Double? {
        guard let value = Double(text), value.isFinite, value >= 0 else { return nil }
        return value
    }
}

/// Why a job did not end in a file, in the words the card shows.
enum NookLinkAudioFailure: Equatable, Sendable {
    case couldNotStart
    case couldNotMakeFolder
    /// The folder has a dollar sign in its path (see `NookLinkAudioFolderRule`).
    case folderHasDollar
    case unsupportedSite
    case unavailable
    case needsAccount
    case notInYourCountry
    case offline
    case blocked
    case drm
    case ffmpeg
    case diskFull
    case cannotWrite
    case nameTooLong
    case other

    var messageKey: String {
        switch self {
        case .couldNotStart: "nook.linkAudio.failed.couldNotStart"
        case .couldNotMakeFolder: "nook.linkAudio.failed.folder"
        case .folderHasDollar: "nook.linkAudio.failed.folderDollar"
        case .unsupportedSite: "nook.linkAudio.failed.unsupported"
        case .unavailable: "nook.linkAudio.failed.unavailable"
        case .needsAccount: "nook.linkAudio.failed.account"
        case .notInYourCountry: "nook.linkAudio.failed.country"
        case .offline: "nook.linkAudio.failed.offline"
        case .blocked: "nook.linkAudio.failed.blocked"
        case .drm: "nook.linkAudio.failed.drm"
        case .ffmpeg: "nook.linkAudio.failed.ffmpeg"
        case .diskFull: "nook.linkAudio.failed.diskFull"
        case .cannotWrite: "nook.linkAudio.failed.cannotWrite"
        case .nameTooLong: "nook.linkAudio.failed.nameTooLong"
        case .other: "nook.linkAudio.failed.other"
        }
    }

    /// Reads the last error line `yt-dlp` wrote. The most specific cause is
    /// asked first: a missing page is also "unable to download".
    static func reason(forErrorLine line: String?) -> NookLinkAudioFailure {
        guard let text = line?.lowercased(), !text.isEmpty else { return .other }
        let causes: [(NookLinkAudioFailure, [String])] = [
            (.unsupportedSite, ["unsupported url"]),
            (.drm, ["drm"]),
            (.diskFull, ["no space left"]),
            (.nameTooLong, ["file name too long", "filename too long"]),
            (.cannotWrite, ["permission denied", "operation not permitted", "read-only file system"]),
            (.ffmpeg, ["ffmpeg", "ffprobe"]),
            (.notInYourCountry, ["your country", "geo restrict", "geo-restrict", "geoblock"]),
            (.needsAccount, [
                "sign in", "log in", "login", "private video", "members-only", "members only",
                "confirm your age", "age-restricted", "age restricted", "registered users",
            ]),
            (.unavailable, [
                "video unavailable", "not available", "has been removed", "no longer available",
                "does not exist", "http error 404", "http error 410", "not found", "been terminated",
            ]),
            (.blocked, ["http error 429", "http error 403", "too many requests", "forbidden"]),
            (.offline, [
                "unable to download", "getaddrinfo", "network is unreachable", "timed out",
                "nodename nor servname", "name or service not known", "connection", "urlopen error",
            ]),
        ]
        return causes.first { _, words in words.contains { text.contains($0) } }?.0 ?? .other
    }
}
