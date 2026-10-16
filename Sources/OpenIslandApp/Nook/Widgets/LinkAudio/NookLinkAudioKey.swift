import Foundation

/// A musical key: a tonic and major or minor. The tonic is a pitch class,
/// 0 for C up to 11 for B, which makes C# and Db the same key.
struct NookMusicalKey: Hashable, Sendable {
    enum Mode: Hashable, Sendable {
        case major
        case minor
    }

    let tonic: Int
    let mode: Mode

    init(tonic: Int, mode: Mode) {
        self.tonic = ((tonic % 12) + 12) % 12
        self.mode = mode
    }

    /// How a tonic is spelled in a file name and on the row: sharps for C#
    /// and F#, flats for Eb, Ab and Bb. The same in every language.
    static let noteNames = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]

    var noteName: String { Self.noteNames[tonic] }

    /// `C# minor`. This is the form a file name carries, and it does not
    /// change with the app's language: the same song fetched again must get
    /// the same name, or the copy that is already there would not be found.
    var englishName: String {
        "\(noteName) \(mode == .major ? "major" : "minor")"
    }

    /// The name for the row, in the app's language.
    var localizedName: String {
        let lang = LanguageManager.shared
        return switch mode {
        case .major: lang.t("nook.linkAudio.key.major", noteName)
        case .minor: lang.t("nook.linkAudio.key.minor", noteName)
        }
    }

    /// The key with the same notes and the other mode: A minor for C major.
    var relative: NookMusicalKey {
        switch mode {
        case .major: NookMusicalKey(tonic: tonic + 9, mode: .minor)
        case .minor: NookMusicalKey(tonic: tonic + 3, mode: .major)
        }
    }

    /// All 24 keys, major keys first, each in tonic order.
    static let all: [NookMusicalKey] = [Mode.major, Mode.minor].flatMap { mode in
        (0..<12).map { NookMusicalKey(tonic: $0, mode: mode) }
    }
}

/// One thing found out about a song, and where it came from.
struct NookLinkAudioFound<Value: Hashable & Sendable>: Hashable, Sendable {
    var value: Value
    /// True when it was worked out from the sound. False when the uploader
    /// wrote it, which is taken as exact.
    var isGuess: Bool
}

/// The key and the tempo of one download, either of which may be missing.
struct NookLinkAudioFindings: Equatable, Sendable {
    var key: NookLinkAudioFound<NookMusicalKey>?
    var bpm: NookLinkAudioFound<Int>?

    var isEmpty: Bool { key == nil && bpm == nil }

    /// The text that goes in a file name between brackets: `C# minor, 127 BPM`,
    /// with a `~` in front of each value that is a guess. Always in English.
    /// Nil when nothing was found.
    var fileNameTag: String? {
        let parts = [
            key.map { Self.mark($0.isGuess) + $0.value.englishName },
            bpm.map { Self.mark($0.isGuess) + "\($0.value) BPM" },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// The same for the row, with the key named in the app's language.
    var shownText: String? {
        let parts = [
            key.map { Self.mark($0.isGuess) + $0.value.localizedName },
            bpm.map { Self.mark($0.isGuess) + "\($0.value) BPM" },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// What VoiceOver reads for the row: a guess is said to be one, since a
    /// tilde is not read aloud reliably.
    var spokenText: String? {
        let lang = LanguageManager.shared
        let parts = [
            key.map { $0.isGuess ? lang.t("nook.linkAudio.found.guess", $0.value.localizedName) : $0.value.localizedName },
            bpm.map { $0.isGuess ? lang.t("nook.linkAudio.found.guess", "\($0.value) BPM") : "\($0.value) BPM" },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func mark(_ isGuess: Bool) -> String { isGuess ? "~" : "" }
}
