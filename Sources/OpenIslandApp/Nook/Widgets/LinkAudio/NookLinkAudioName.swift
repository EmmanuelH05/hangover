import Foundation

/// The file name a download gets once its key and tempo are known.
enum NookLinkAudioName {
    /// The longest file name the disk takes, in bytes.
    static let maxBytes = 255

    /// `Wake Up [abc123].mp3` becomes `Wake Up [C# minor, 127 BPM] [abc123].mp3`:
    /// the findings go in brackets just before the ` [id]` that `yt-dlp` puts
    /// last. A name with no such ending gets them before the extension. Nil
    /// when nothing was found, when the name already carries them, and when
    /// the new name would be too long for the disk.
    static func renamed(_ name: String, with findings: NookLinkAudioFindings) -> String? {
        guard let tag = findings.fileNameTag else { return nil }
        let bracketed = " [\(tag)]"
        let extensionPart = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        guard !stem.contains(bracketed) else { return nil }

        var newStem = stem + bracketed
        if stem.hasSuffix("]"), let open = stem.range(of: " [", options: .backwards) {
            newStem = String(stem[..<open.lowerBound]) + bracketed + String(stem[open.lowerBound...])
        }
        let result = extensionPart.isEmpty ? newStem : newStem + "." + extensionPart
        return result.utf8.count <= maxBytes ? result : nil
    }

    /// The same for a file: the new place is in the same folder.
    static func renamed(_ file: URL, with findings: NookLinkAudioFindings) -> URL? {
        renamed(file.lastPathComponent, with: findings).map {
            file.deletingLastPathComponent().appendingPathComponent($0)
        }
    }
}
