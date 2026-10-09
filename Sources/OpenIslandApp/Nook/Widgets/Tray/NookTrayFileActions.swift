import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A picture format the tray converts to.
enum NookTrayImageFormat: String, Equatable, Sendable {
    case jpeg
    case png

    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        }
    }

    var typeIdentifier: String {
        switch self {
        case .jpeg: UTType.jpeg.identifier
        case .png: UTType.png.identifier
        }
    }

    /// Localizable key for the menu item that converts to this format.
    var actionTitleKey: String { "nook.tray.action.convert.\(rawValue)" }
}

enum NookTrayFileActionError: Error, Equatable {
    /// The file is gone, or is not a picture that can be read.
    case unreadable
    case writeFailed
    /// The picture has more pixels than the tray converts.
    case tooLarge
    /// `detail` is what the zip tool said on its error output, cut short.
    case zipFailed(status: Int32, detail: String)

    /// The notice for a failure that has its own, nil for the action's
    /// general one.
    var noticeKey: String? {
        switch self {
        case .tooLarge: "nook.tray.notice.convertTooLarge"
        case .unreadable, .writeFailed, .zipFailed: nil
        }
    }

    /// What goes to the log besides the tool's own words.
    var logSummary: String {
        switch self {
        case .unreadable: "the file is gone or cannot be read"
        case .writeFailed: "the new file could not be written"
        case .tooLarge: "the picture is over the pixel limit"
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

    /// What a picture with this file name converts to, or nil when the
    /// tray has no conversion for it.
    static func conversionTarget(forFileNamed name: String) -> NookTrayImageFormat? {
        switch (name as NSString).pathExtension.lowercased() {
        case "png": .jpeg
        case "jpg", "jpeg": .png
        case "heic", "heif": .jpeg
        default: nil
        }
    }

    /// "photo.heic" becomes "photo.jpg".
    static func convertedName(for name: String, to format: NookTrayImageFormat) -> String {
        let base = (name as NSString).deletingPathExtension
        return (base.isEmpty ? name : base) + "." + format.fileExtension
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
    /// camera data. A see-through picture going to JPEG gets a white
    /// background, because JPEG has no transparency. A picture with more
    /// than `maxPixels` pixels is refused before any of it is decoded.
    static func convertImage(
        at source: URL,
        to destination: URL,
        format: NookTrayImageFormat,
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
        guard let image = uprightImage(from: imageSource) else {
            throw NookTrayFileActionError.unreadable
        }
        // A file with no stated size is measured once it is opened, which
        // still comes before its pixels are drawn.
        guard isWithinConvertLimit(width: image.width, height: image.height, limit: maxPixels) else {
            throw NookTrayFileActionError.tooLarge
        }
        let output = format == .jpeg ? flattenedOnWhite(image) ?? image : image
        guard let imageDestination = CGImageDestinationCreateWithURL(
            destination as CFURL,
            format.typeIdentifier as CFString,
            1,
            nil
        ) else {
            throw NookTrayFileActionError.writeFailed
        }
        var options: [CFString: Any] = [:]
        if format == .jpeg {
            options[kCGImageDestinationLossyCompressionQuality] = jpegQuality
        }
        CGImageDestinationAddImage(imageDestination, output, options as CFDictionary)
        guard CGImageDestinationFinalize(imageDestination) else {
            throw NookTrayFileActionError.writeFailed
        }
    }

    // MARK: - Private

    /// The whole picture with its rotation tag applied to the pixels. PNG
    /// has no rotation tag most viewers read, which would leave a phone
    /// photo on its side.
    private static func uprightImage(from source: CGImageSource) -> CGImage? {
        guard let size = pixelSize(of: source) else {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
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
