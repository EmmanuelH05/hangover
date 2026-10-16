import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A picture format the tray converts to and from.
enum NookImageTarget: String, CaseIterable, Sendable {
    case png, jpeg, heic, tiff, gif, bmp

    var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .heic: "heic"
        case .tiff: "tiff"
        case .gif: "gif"
        case .bmp: "bmp"
        }
    }

    var typeIdentifier: String {
        switch self {
        case .png: UTType.png.identifier
        case .jpeg: UTType.jpeg.identifier
        case .heic: UTType.heic.identifier
        case .tiff: UTType.tiff.identifier
        case .gif: UTType.gif.identifier
        case .bmp: UTType.bmp.identifier
        }
    }

    /// JPEG and HEIC trade size for quality.
    var isLossy: Bool { self == .jpeg || self == .heic }

    /// JPEG and BMP cannot hold see-through pixels, so they get a white
    /// background where the picture has none.
    var needsOpaquePixels: Bool { self == .jpeg || self == .bmp }

    /// The format a file name is in, nil for anything else.
    static func of(extension ext: String) -> NookImageTarget? {
        switch ext.lowercased() {
        case "png": .png
        case "jpg", "jpeg": .jpeg
        case "heic", "heif": .heic
        case "tif", "tiff": .tiff
        case "gif": .gif
        case "bmp": .bmp
        default: nil
        }
    }
}

enum NookResize: Hashable, Sendable {
    case half
    case quarter
    case longSide(Int)

    static let all: [NookResize] = [.half, .quarter, .longSide(1920), .longSide(1280), .longSide(640)]

    /// The longest side this resize asks for, for a picture whose own
    /// longest side is `longSide`. Not capped: a long side above the
    /// picture's is returned as it is, and the callers decide.
    func targetLongSide(from longSide: Int) -> Int {
        switch self {
        case .half: Int((Double(longSide) / 2).rounded())
        case .quarter: Int((Double(longSide) / 4).rounded())
        case .longSide(let side): side
        }
    }

    /// True when this resize makes a picture whose longest side is
    /// `longSide` smaller. A long side at or above the picture's own would
    /// give the same picture back, and so would a half or a quarter of a
    /// picture a pixel wide.
    func shrinks(longSide: Int) -> Bool {
        max(1, targetLongSide(from: longSide)) < longSide
    }
}

enum NookVideoContainer: String, Sendable { case mp4, mov }
enum NookVideoSize: String, Sendable { case p1080, p720 }
enum NookPageImage: String, Sendable { case png, jpeg }

/// Where an action sits in a file's Convert menu.
enum NookConvertGroup: String, CaseIterable, Sendable {
    case format
    case size
    case other

    var titleKey: String { "nook.tray.convert.group.\(rawValue)" }
}

/// One thing a tray file can be turned into.
enum NookConvertAction: Hashable, Sendable {
    case image(NookImageTarget)
    case resize(NookResize)
    case smallerImage
    case video(NookVideoContainer)
    case smallerVideo(NookVideoSize)
    case makeGIF
    case soundOnly
    case pdfPages(NookPageImage)

    var group: NookConvertGroup {
        switch self {
        case .image, .video, .pdfPages: .format
        case .resize, .smallerImage, .smallerVideo: .size
        case .makeGIF, .soundOnly: .other
        }
    }

    /// The menu line. `resize(.longSide)` is a format string that takes
    /// `titleArgument`.
    var titleKey: String {
        switch self {
        case .image(let target): "nook.tray.convert.image.\(target.rawValue)"
        case .resize(.half): "nook.tray.convert.resize.half"
        case .resize(.quarter): "nook.tray.convert.resize.quarter"
        case .resize(.longSide): "nook.tray.convert.resize.longSide"
        case .smallerImage: "nook.tray.convert.smallerImage"
        case .video(let container): "nook.tray.convert.video.\(container.rawValue)"
        case .smallerVideo(let size): "nook.tray.convert.smallerVideo.\(size.rawValue)"
        case .makeGIF: "nook.tray.convert.makeGIF"
        case .soundOnly: "nook.tray.convert.soundOnly"
        case .pdfPages(let format): "nook.tray.convert.pdfPages.\(format.rawValue)"
        }
    }

    /// The number a title's format string takes, nil for a title with none.
    var titleArgument: Int? {
        if case .resize(.longSide(let side)) = self { return side }
        return nil
    }

    /// Video work waits its turn, one at a time. Pictures and pages go
    /// straight away.
    var isQueued: Bool {
        switch self {
        case .video, .smallerVideo, .soundOnly, .makeGIF: true
        case .image, .resize, .smallerImage, .pdfPages: false
        }
    }
}

/// What several chosen files can be made into together.
enum NookCombineAction: Hashable, Sendable {
    case picturesToPDF
    case joinPDFs

    var titleKey: String {
        switch self {
        case .picturesToPDF: "nook.tray.convert.combine.picturesToPDF"
        case .joinPDFs: "nook.tray.convert.combine.joinPDFs"
        }
    }
}

/// Which conversions a tray file is offered, and what the result is called (D68).
enum NookConvertRules {
    static let maxPDFPages = 200

    /// What a file of this name is offered, before anything is known about
    /// the picture inside it.
    static func actions(forFileNamed name: String) -> [NookConvertAction] {
        actions(forFileNamed: name, pixelLongSide: nil)
    }

    /// What the file in `url` is offered. For a picture the size comes from
    /// its header, which costs nothing to read, so a resize that would give
    /// the picture back unchanged is not on the menu.
    static func actions(forFileNamed name: String, at url: URL) -> [NookConvertAction] {
        var longSide: Int?
        if NookImageTarget.of(extension: (name as NSString).pathExtension) != nil,
           let size = NookTrayFileActions.pixelSize(ofFileAt: url) {
            longSide = max(size.width, size.height)
        }
        return actions(forFileNamed: name, pixelLongSide: longSide)
    }

    /// `pixelLongSide` is the longest side of a picture, nil when it is not
    /// known. Only a resize that makes the picture smaller is offered.
    static func actions(forFileNamed name: String, pixelLongSide: Int?) -> [NookConvertAction] {
        let ns = name as NSString
        let ext = ns.pathExtension.lowercased()
        guard !ns.deletingPathExtension.isEmpty else { return [] }
        if let own = NookImageTarget.of(extension: ext) {
            let formats = NookImageTarget.allCases.filter { $0 != own }.map(NookConvertAction.image)
            let resizes = NookResize.all
                .filter { resize in pixelLongSide.map { resize.shrinks(longSide: $0) } ?? true }
                .map(NookConvertAction.resize)
            return formats + resizes + [.smallerImage]
        }
        switch ext {
        case "mov": return [.video(.mp4), .smallerVideo(.p1080), .smallerVideo(.p720), .makeGIF, .soundOnly]
        case "mp4": return [.video(.mov), .smallerVideo(.p1080), .smallerVideo(.p720), .makeGIF, .soundOnly]
        case "m4v": return [.video(.mp4), .video(.mov), .smallerVideo(.p1080), .smallerVideo(.p720), .makeGIF, .soundOnly]
        case "pdf": return [.pdfPages(.png), .pdfPages(.jpeg)]
        default: return []
        }
    }

    static func combineActions(forFilesNamed names: [String]) -> [NookCombineAction] {
        guard names.count >= 2 else { return [] }
        let exts = names.map { ($0 as NSString).pathExtension.lowercased() }
        if exts.allSatisfy({ NookImageTarget.of(extension: $0) != nil }) { return [.picturesToPDF] }
        if exts.allSatisfy({ $0 == "pdf" }) { return [.joinPDFs] }
        return []
    }

    static func resultName(for source: String, action: NookConvertAction, taken: Set<String>) -> String {
        let ns = source as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension
        let name: String = switch action {
        case .image(let target): "\(base).\(target.fileExtension)"
        case .resize(.half): "\(base) (50%).\(ext)"
        case .resize(.quarter): "\(base) (25%).\(ext)"
        case .resize(.longSide(let side)): "\(base) (\(side) px).\(ext)"
        case .smallerImage: "\(base) (smaller).jpg"
        case .video(let container): "\(base).\(container.rawValue)"
        case .smallerVideo(.p1080): "\(base) (1080p).mp4"
        case .smallerVideo(.p720): "\(base) (720p).mp4"
        case .makeGIF: "\(base).gif"
        case .soundOnly: "\(base).m4a"
        case .pdfPages: "\(base) pages"
        }
        if case .pdfPages = action { return uniqueFolderName(name, taken: taken) }
        return unique(name, taken: taken)
    }

    static func combinedName(for action: NookCombineAction, taken: Set<String>) -> String {
        unique(action == .picturesToPDF ? "Pictures.pdf" : "Joined.pdf", taken: taken)
    }

    /// True for a GIF with more than one picture in it. Only its first
    /// picture goes through a picture conversion, which the menu says.
    static func isAnimatedGIF(at url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "gif",
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return false
        }
        return CGImageSourceGetCount(source) > 1
    }

    // MARK: - Notices

    /// The notice for a conversion that failed. Each kind of work has its
    /// own sentence, and a few failures have one of their own.
    static func noticeKey(for error: Error, action: NookConvertAction) -> String {
        switch error {
        case NookTrayFileActionError.tooLarge:
            if case .pdfPages = action { return "nook.tray.convert.notice.tooManyPages" }
            return "nook.tray.notice.convertTooLarge"
        case NookTrayFileActionError.noSound:
            return "nook.tray.convert.notice.noSound"
        case NookTrayFileActionError.notSmaller:
            return "nook.tray.convert.notice.alreadySmall"
        case NookGIFError.tooLong:
            return "nook.tray.convert.notice.gifTooLong"
        case NookGIFError.decodeFailed:
            return "nook.tray.convert.notice.gifDecodeFailed"
        default:
            return failureKey(for: action)
        }
    }

    /// How a failed conversion is shown. A "smaller" copy that came out no
    /// smaller is not a failure: nothing went wrong, and nothing was made.
    static func noticeKind(for error: Error) -> NookTrayNotice.Kind {
        (error as? NookTrayFileActionError) == .notSmaller ? .info : .error
    }

    static func failureKey(for action: NookConvertAction) -> String {
        switch action {
        case .image, .resize, .smallerImage: "nook.tray.notice.convertFailed"
        case .video, .smallerVideo, .soundOnly: "nook.tray.convert.notice.videoFailed"
        case .makeGIF: "nook.tray.convert.notice.gifFailed"
        case .pdfPages: "nook.tray.convert.notice.pdfFailed"
        }
    }

    /// What a button says while it waits for a conversion to end: "Wait for
    /// the conversion on NAME to finish".
    static func waitText(forBusyFileNamed name: String) -> String {
        LanguageManager.shared.t("nook.tray.convert.wait", name)
    }

    static func noticeKey(forCombineFailure error: Error) -> String {
        if case NookTrayFileActionError.tooLarge = error { return "nook.tray.notice.convertTooLarge" }
        return "nook.tray.convert.notice.combineFailed"
    }

    // MARK: - Private

    /// A folder's name has no extension, even when it holds a dot.
    private static func uniqueFolderName(_ name: String, taken: Set<String>) -> String {
        guard taken.contains(name) else { return name }
        var number = 2
        while taken.contains("\(name) \(number)") { number += 1 }
        return "\(name) \(number)"
    }

    private static func unique(_ name: String, taken: Set<String>) -> String {
        guard taken.contains(name) else { return name }
        let ns = name as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension
        var number = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            if !taken.contains(candidate) { return candidate }
            number += 1
        }
    }
}
