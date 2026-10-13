import Foundation

/// The two programs the widget runs. The app ships neither and fetches
/// neither: they are the ones the user already has.
enum NookLinkAudioToolName: String, CaseIterable, Sendable {
    case ytDlp = "yt-dlp"
    case ffmpeg
}

/// Where both programs were found.
struct NookLinkAudioTools: Equatable, Sendable {
    let ytDlp: URL
    let ffmpeg: URL

    /// The folder `--ffmpeg-location` is given.
    var ffmpegDirectory: URL { ffmpeg.deletingLastPathComponent() }
}

/// What the search found: where each program is, or nil.
struct NookLinkAudioToolStatus: Equatable, Sendable {
    var ytDlp: URL?
    var ffmpeg: URL?

    /// Both, or nil when either is missing.
    var tools: NookLinkAudioTools? {
        guard let ytDlp, let ffmpeg else { return nil }
        return NookLinkAudioTools(ytDlp: ytDlp, ffmpeg: ffmpeg)
    }

    func path(of name: NookLinkAudioToolName) -> URL? {
        switch name {
        case .ytDlp: ytDlp
        case .ffmpeg: ffmpeg
        }
    }

    var missing: [NookLinkAudioToolName] {
        NookLinkAudioToolName.allCases.filter { path(of: $0) == nil }
    }

    /// The card's one line naming what is missing and how to get it. Nil
    /// when nothing is.
    var missingLineKey: String? {
        switch missing {
        case []: nil
        case [.ytDlp]: "nook.linkAudio.missing.ytDlp"
        case [.ffmpeg]: "nook.linkAudio.missing.ffmpeg"
        default: "nook.linkAudio.missing.both"
        }
    }
}

/// Looks for the programs in the usual homes of a Homebrew or system install.
enum NookLinkAudioToolSearch {
    /// Searched in this order. The first folder that holds the program wins.
    static let directories = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]

    /// The program's place, or nil. `isExecutable` answers for a path; the
    /// app hands in the file manager's and a test hands in a made-up one.
    static func find(_ name: NookLinkAudioToolName, isExecutable: (String) -> Bool) -> URL? {
        for directory in directories {
            let path = "\(directory)/\(name.rawValue)"
            if isExecutable(path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    static func status(isExecutable: (String) -> Bool) -> NookLinkAudioToolStatus {
        NookLinkAudioToolStatus(
            ytDlp: find(.ytDlp, isExecutable: isExecutable),
            ffmpeg: find(.ffmpeg, isExecutable: isExecutable)
        )
    }

    /// The `PATH` the program runs with. An app started from Finder has a
    /// short one, and `yt-dlp` looks for helpers it needs on it.
    static var runPath: String {
        (directories + ["/bin", "/usr/sbin", "/sbin"]).joined(separator: ":")
    }
}
