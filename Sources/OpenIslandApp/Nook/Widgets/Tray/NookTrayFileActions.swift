import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum NookTrayFileActionError: Error, Equatable {
    /// The file is gone, or is not a picture that can be read.
    case unreadable
    case writeFailed
    /// The picture has more pixels than the tray converts.
    case tooLarge
    /// A video that has no sound track cannot become a sound file.
    case noSound
    /// A "smaller" copy that came out no smaller than the file it came from.
    /// Nothing went wrong, and the copy is not kept.
    case notSmaller
    /// `detail` is what the zip tool said on its error output, cut short.
    case zipFailed(status: Int32, detail: String)

    /// The notice for a failure that has its own, nil for the action's
    /// general one.
    var noticeKey: String? {
        switch self {
        case .tooLarge: "nook.tray.notice.convertTooLarge"
        case .noSound: "nook.tray.convert.notice.noSound"
        case .notSmaller: "nook.tray.convert.notice.alreadySmall"
        case .unreadable, .writeFailed, .zipFailed: nil
        }
    }

    /// What goes to the log besides the tool's own words.
    var logSummary: String {
        switch self {
        case .unreadable: "the file is gone or cannot be read"
        case .writeFailed: "the new file could not be written"
        case .tooLarge: "the picture is over the pixel limit"
        case .noSound: "the video has no sound track"
        case .notSmaller: "the smaller copy was not smaller than the file"
        case .zipFailed(let status, _): "the zip tool exited with status \(status)"
        }
    }

    /// The zip tool's error output. It can name files, which keeps it out
    /// of the public part of a log line.
    var logDetail: String {
        if case .zipFailed(_, let detail) = self { return detail }
        return ""
    }
}

/// The file work behind the tray's quick actions. Plain functions with no
/// state: they run off the main thread and are called straight from tests.
/// None of them touches the file it is given.
enum NookTrayFileActions {
    static let jpegQuality = 0.9
    static let zipToolPath = "/usr/bin/ditto"
    /// How much of the zip tool's error output is kept for the log.
    static let zipErrorLimit = 400

    /// The most pixels a picture may have and still be converted. A
    /// conversion holds the whole picture in memory at 4 bytes a pixel,
    /// and going to JPEG can hold a second copy for the white background.
    /// 64 million pixels is 256 MB a copy. That is above a 48 megapixel
    /// phone photo and a 61 megapixel full frame one, and far under what a
    /// small file can claim in its header (a 30000 by 30000 PNG asks for
    /// 3.6 GB a copy).
    static let maxConvertPixels = 64_000_000

    /// False for a picture over `limit`, or one whose size does not fit
    /// in a number at all.
    static func isWithinConvertLimit(width: Int, height: Int, limit: Int = maxConvertPixels) -> Bool {
        guard width > 0, height > 0 else { return false }
        let (pixels, overflowed) = width.multipliedReportingOverflow(by: height)
        return !overflowed && pixels <= limit
    }

    /// The extension stays, as it does when Finder compresses one file:
    /// "notes.txt" becomes "notes.txt.zip".
    static func zipName(for name: String) -> String {
        name + ".zip"
    }

    /// Arguments for `ditto`. A folder keeps its own name as the top entry
    /// of the archive. A single file sits at the top by itself. Mac-only
    /// extras are left out, which keeps the archive clean on other systems.
    static func zipArguments(source: URL, destination: URL, isDirectory: Bool) -> [String] {
        var arguments = ["-c", "-k", "--norsrc", "--noextattr", "--noqtn"]
        if isDirectory { arguments.append("--keepParent") }
        return arguments + [source.path, destination.path]
    }

    /// Writes a zip of `source` at `destination`.
    static func zip(_ source: URL, to destination: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw NookTrayFileActionError.unreadable
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: zipToolPath)
        process.arguments = zipArguments(source: source, destination: destination, isDirectory: isDirectory.boolValue)
        process.standardOutput = FileHandle.nullDevice
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        // Read to the end before waiting. A tool that fills the pipe while
        // nobody reads it never exits.
        let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NookTrayFileActionError.zipFailed(
                status: process.terminationStatus,
                detail: zipErrorDetail(from: errorOutput)
            )
        }
    }

    /// The zip tool's error output as one short line for the log: its
    /// lines joined, with control characters and empty lines taken out.
    static func zipErrorDetail(from output: Data) -> String {
        let text = String(decoding: output.prefix(zipErrorLimit * 4), as: UTF8.self)
        let lines = text.split(whereSeparator: \.isNewline)
            .map { IslandLinkLog.clean(String($0), limit: zipErrorLimit).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return String(lines.joined(separator: " | ").prefix(zipErrorLimit))
    }

    /// Writes the picture at `source` to `destination` in another format.
    /// The copy is turned upright and keeps the picture only, not the
    /// camera data. A see-through picture going to JPEG or BMP gets a
    /// white background, because those have no transparency. A picture
    /// with more than `maxPixels` pixels is refused before any of it is
    /// decoded. `quality` (0 to 1) applies to JPEG and HEIC. A
    /// `maxLongSide` smaller than the picture shrinks it to that, and
    /// never makes it bigger. Only the first picture of an animated file
    /// is converted.
    static func convertImage(
        at source: URL,
        to destination: URL,
        target: NookImageTarget,
        quality: Double? = nil,
        maxLongSide: Int? = nil,
        maxPixels: Int = maxConvertPixels
    ) throws {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            throw NookTrayFileActionError.unreadable
        }
        // The size a file states in its header costs nothing to read.
        if let size = pixelSize(of: imageSource),
           !isWithinConvertLimit(width: size.width, height: size.height, limit: maxPixels) {
            throw NookTrayFileActionError.tooLarge
        }
        let image = try uprightImage(from: imageSource, maxLongSide: maxLongSide)
        // A file with no stated size is measured once it is opened, which
        // still comes before its pixels are drawn.
        guard isWithinConvertLimit(width: image.width, height: image.height, limit: maxPixels) else {
            throw NookTrayFileActionError.tooLarge
        }
        let output = target.needsOpaquePixels ? flattenedOnWhite(image) ?? image : image
        guard let imageDestination = CGImageDestinationCreateWithURL(
            destination as CFURL,
            target.typeIdentifier as CFString,
            1,
            nil
        ) else {
            throw NookTrayFileActionError.writeFailed
        }
        var options: [CFString: Any] = [:]
        if target.isLossy {
            options[kCGImageDestinationLossyCompressionQuality] = min(1, max(0, quality ?? jpegQuality))
        }
        CGImageDestinationAddImage(imageDestination, output, options as CFDictionary)
        guard CGImageDestinationFinalize(imageDestination) else {
            throw NookTrayFileActionError.writeFailed
        }
    }

    /// The size a picture file states for its first picture, read from its
    /// header. Nil when the file is not a picture or states none.
    static func pixelSize(ofFileAt url: URL) -> (width: Int, height: Int)? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { pixelSize(of: $0) }
    }

    /// The first picture of a file, turned upright, for work that puts
    /// pictures somewhere other than another picture file. Throws
    /// `unreadable` for a file that is not a picture and `tooLarge` for one
    /// over the pixel limit.
    static func uprightImage(at url: URL, maxPixels: Int = maxConvertPixels) throws -> CGImage {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw NookTrayFileActionError.unreadable
        }
        if let size = pixelSize(of: imageSource),
           !isWithinConvertLimit(width: size.width, height: size.height, limit: maxPixels) {
            throw NookTrayFileActionError.tooLarge
        }
        let image = try uprightImage(from: imageSource, maxLongSide: nil)
        guard isWithinConvertLimit(width: image.width, height: image.height, limit: maxPixels) else {
            throw NookTrayFileActionError.tooLarge
        }
        return image
    }

    /// The whole picture with its rotation tag applied to the pixels. PNG
    /// has no rotation tag most viewers read, which would leave a phone
    /// photo on its side. `maxLongSide` shrinks it while it is decoded,
    /// which keeps a big photo from being held at full size first.
    ///
    /// When ImageIO makes no thumbnail, the only picture left is the full
    /// one, unrotated. That is no answer to a `maxLongSide`, so it throws
    /// `unreadable` instead. Without one it is returned, and either way the
    /// log says it happened. `makeThumbnail` is ImageIO's call, which a test
    /// replaces to make it fail.
    static func uprightImage(
        from source: CGImageSource,
        maxLongSide: Int?,
        makeThumbnail: (CGImageSource, CFDictionary) -> CGImage? = { CGImageSourceCreateThumbnailAtIndex($0, 0, $1) }
    ) throws -> CGImage {
        guard let size = pixelSize(of: source) else {
            return try unscaledImage(from: source, maxLongSide: maxLongSide, reason: "the file states no size")
        }
        let longSide = max(size.width, size.height)
        let limit = min(longSide, maxLongSide.map { max(1, $0) } ?? longSide)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: limit,
        ]
        if let thumbnail = makeThumbnail(source, options as CFDictionary) { return thumbnail }
        return try unscaledImage(from: source, maxLongSide: maxLongSide, reason: "ImageIO made no thumbnail")
    }

    // MARK: - Private

    /// The picture as stored, which is neither turned upright nor shrunk.
    private static func unscaledImage(from source: CGImageSource, maxLongSide: Int?, reason: String) throws -> CGImage {
        let wasSizeAsked = maxLongSide != nil
        NookTrayLog.logger.error(
            "Picture: \(reason, privacy: .public), size asked for: \(wasSizeAsked, privacy: .public)"
        )
        if wasSizeAsked { throw NookTrayFileActionError.unreadable }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NookTrayFileActionError.unreadable
        }
        return image
    }

    /// The size the file states for its first picture, read from its
    /// header without decoding anything. Nil when it states none.
    private static func pixelSize(of source: CGImageSource) -> (width: Int, height: Int)? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        guard let width = properties?[kCGImagePropertyPixelWidth] as? Int,
              let height = properties?[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else {
            return nil
        }
        return (width, height)
    }

    /// Nil when the picture has no transparency and needs no background.
    private static func flattenedOnWhite(_ image: CGImage) -> CGImage? {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return nil
        default:
            break
        }
        let colorSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }
}
