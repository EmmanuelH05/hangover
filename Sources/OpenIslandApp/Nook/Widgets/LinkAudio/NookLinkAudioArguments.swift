import Foundation

/// The argument list `yt-dlp` runs with. A plain array handed to `Process`,
/// never a string for a shell. The link is the last thing in it, after
/// `--`, and nowhere else. Nothing in a link can be read as an option.
enum NookLinkAudioArguments {
    /// What starts each line the app asks `yt-dlp` to print for it. Every
    /// other line `yt-dlp` writes is ignored, apart from its errors.
    static let progressMarker = "hangover-progress"
    static let titleMarker = "hangover-title"
    static let descriptionMarker = "hangover-description"
    static let fileMarker = "hangover-file"

    /// The file name `yt-dlp` is given inside the folder. `yt-dlp` fills in
    /// the title, the video's id and the extension itself. The id keeps a file
    /// of the user's that has the same title from being taken for the
    /// download, converted and deleted.
    static let fileNameTemplate = "%(title)s [%(id)s].%(ext)s"

    /// One progress line: the status, the bytes done, the total, the
    /// estimated total and the file being written. A number that is not
    /// known prints as `NA`. The file name is printed as JSON (`j`), which
    /// keeps a newline in it from ending the line, and comes last.
    static let progressTemplate = "download:\(progressMarker) "
        + "%(progress.status)s %(progress.downloaded_bytes)s %(progress.total_bytes)s "
        + "%(progress.total_bytes_estimate)s %(progress.filename)j"

    /// `<folder>/%(title)s [%(id)s].%(ext)s`, with every percent sign of the
    /// folder's own path doubled. `yt-dlp` reads the whole value as a
    /// template, and a folder called `100%` would otherwise be read as a
    /// field. A dollar sign cannot be escaped: `yt-dlp` reads `$NAME` as a
    /// variable, which is why `NookLinkAudioFolderRule` refuses such a folder.
    static func outputTemplate(folder: URL) -> String {
        let path = folder.path.replacingOccurrences(of: "%", with: "%%")
        return path.hasSuffix("/") ? path + fileNameTemplate : path + "/" + fileNameTemplate
    }

    /// The whole list.
    ///
    /// - `--ignore-config`, first: the user's own `yt-dlp` settings, such as an
    ///   `--exec` or a `--skip-download`, do not reach a job.
    /// - `-x`, `--audio-format mp3`, `--audio-quality 0`: keep the sound, as
    ///   an MP3 of the best quality.
    /// - `--no-playlist`, `--playlist-items 1`: a link to a video inside a
    ///   playlist saves the video, and a link to a playlist or a channel
    ///   saves its first entry and no more.
    /// - `--no-overwrites`: a download whose finished `.mp3` (same title and
    ///   id) is already there is not fetched again, and that file is left as
    ///   it is.
    /// - `--newline`, `--progress`, `--no-simulate`: `--print` makes `yt-dlp`
    ///   quiet and a dry run, and these undo both.
    /// - `--ffmpeg-location`: the folder of the `ffmpeg` that was found.
    /// - `--print`: the title and the description once they are known, and the
    ///   finished file, all as JSON. A video with no description prints `NA`.
    static func make(link: NookLinkAudioLink, folder: URL, ffmpegDirectory: URL) -> [String] {
        [
            "--ignore-config",
            "-x",
            "--audio-format", "mp3",
            "--audio-quality", "0",
            "--no-playlist",
            "--playlist-items", "1",
            "--no-overwrites",
            "--newline",
            "--progress",
            "--no-simulate",
            "--progress-template", progressTemplate,
            "--ffmpeg-location", ffmpegDirectory.path,
            "-o", outputTemplate(folder: folder),
            "--print", "before_dl:\(titleMarker) %(title)j",
            "--print", "before_dl:\(descriptionMarker) %(description)j",
            "--print", "after_move:\(fileMarker) %(filepath)j",
            "--",
            link.text,
        ]
    }
}
