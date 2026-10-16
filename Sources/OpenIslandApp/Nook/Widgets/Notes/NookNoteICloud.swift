import Foundation

/// What the notes ask of iCloud (N3, N17): whether a file is on this Mac, and
/// to bring it. A file iCloud has not downloaded makes a read wait for the
/// download, which can hold the app up. Tests pass their own.
struct NookNoteICloud: Sendable {
    /// True for a file iCloud has not downloaded.
    var isNotDownloaded: @Sendable (URL) -> Bool
    /// Asks iCloud to download a file. It throws for a file that is not in iCloud.
    var startDownload: @Sendable (URL) throws -> Void

    static let live = NookNoteICloud(
        isNotDownloaded: { url in
            do {
                let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                return values.ubiquitousItemDownloadingStatus == .notDownloaded
            } catch let error as CocoaError where [.fileReadNoSuchFile, .fileNoSuchFile].contains(error.code) {
                // Not there at all, which is not a file waiting for a download.
                return false
            } catch {
                // A file that cannot be asked about is read like any other.
                NookNotesLog.failure("ask iCloud whether a file is downloaded", path: url.path, error: error)
                return false
            }
        },
        startDownload: { url in try FileManager.default.startDownloadingUbiquitousItem(at: url) }
    )

    /// The hidden file older systems leave in place of one that is not
    /// downloaded: ".Name.md.icloud".
    static func standIn(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
    }
}
