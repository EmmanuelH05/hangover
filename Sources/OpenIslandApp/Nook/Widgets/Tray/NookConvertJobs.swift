import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import PDFKit

/// The file work behind the tray's Convert menu (D68). Plain functions with
/// no state: they run off the main thread and are called straight from
/// tests. None of them touches the file it is given, and each writes only
/// to the place it is told to.
enum NookConvertJobs {
    /// A "smaller file" picture: JPEG at this quality, no longer than this
    /// on its longest side.
    static let smallerImageQuality = 0.7
    static let smallerImageLongSide = 2560

    /// Pages come out at twice their size in the PDF, which keeps text
    /// sharp.
    static let pageScale: CGFloat = 2
    static let pageImageQuality = 0.9

    // MARK: - Pictures

    /// Another format, and optionally a smaller or lower quality copy. See
    /// `NookTrayFileActions.convertImage`.
    static func convertImage(
        at source: URL,
        to destination: URL,
        target: NookImageTarget,
        quality: Double? = nil,
        maxLongSide: Int? = nil
    ) throws {
        try NookTrayFileActions.convertImage(
            at: source,
            to: destination,
            target: target,
            quality: quality,
            maxLongSide: maxLongSide
        )
    }

    /// The same kind of picture at a smaller size. Never bigger than the
    /// original.
    static func resize(at source: URL, to destination: URL, resize: NookResize) throws {
        guard let size = NookTrayFileActions.pixelSize(ofFileAt: source) else {
            throw NookTrayFileActionError.unreadable
        }
        let longSide = max(size.width, size.height)
        let wanted = resize.targetLongSide(from: longSide)
        let target = NookImageTarget.of(extension: source.pathExtension) ?? .png
        try NookTrayFileActions.convertImage(
            at: source,
            to: destination,
            target: target,
            maxLongSide: min(longSide, max(1, wanted))
        )
    }

    /// A JPEG that takes less room: lower quality, and nothing over 2560
    /// pixels on its longest side.
    static func smallerImage(at source: URL, to destination: URL) throws {
        try NookTrayFileActions.convertImage(
            at: source,
            to: destination,
            target: .jpeg,
            quality: smallerImageQuality,
            maxLongSide: smallerImageLongSide
        )
    }

    /// Checks that a "smaller" copy takes less room than the file it came
    /// from. A copy that does not is removed and `notSmaller` is thrown,
    /// which the tray says as "already about as small as it gets". A size
    /// that cannot be read counts as unreadable: a result nobody could
    /// measure is not reported as done.
    static func requireSmaller(_ result: URL, than source: URL) throws {
        guard let before = fileSize(of: source), let after = fileSize(of: result) else {
            NookTrayLog.logger.error("Smaller: the size of the file or of its copy could not be read")
            try? FileManager.default.removeItem(at: result)
            throw NookTrayFileActionError.unreadable
        }
        guard after < before else {
            NookTrayLog.logger.notice("Smaller: the copy took \(after, privacy: .public) bytes, the file \(before, privacy: .public)")
            try? FileManager.default.removeItem(at: result)
            throw NookTrayFileActionError.notSmaller
        }
    }

    /// Bytes on disk for a file, nil when they cannot be read.
    static func fileSize(of url: URL) -> Int? {
        try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }

    // MARK: - Video

    /// What one video action asks the export session for.
    private struct ExportPlan {
        let preset: String
        let fileType: AVFileType
    }

    /// Writes a video in another container, a smaller one, or only its
    /// sound. `progress` gets 0 to 1 a few times a second. A cancelled task
    /// cancels the export and removes the partly written file.
    static func exportVideo(
        at source: URL,
        to destination: URL,
        action: NookConvertAction,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: source)
        try await requireExportable(asset)
        if action == .soundOnly {
            try await requireSound { try await asset.loadTracks(withMediaType: .audio).count }
        }
        guard let plan = await exportPlan(for: action, asset: asset) else {
            NookTrayLog.logger.error("Export: no preset fits this action")
            throw NookTrayFileActionError.unreadable
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: plan.preset) else {
            NookTrayLog.logger.error("Export: no session could be made for preset \(plan.preset, privacy: .public)")
            throw NookTrayFileActionError.unreadable
        }
        // The session refuses to write over a file.
        try? FileManager.default.removeItem(at: destination)
        let box = ExportBox(session)
        do {
            try await box.run(to: destination, as: plan.fileType, progress: progress)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
        if Task.isCancelled {
            try? FileManager.default.removeItem(at: destination)
            throw CancellationError()
        }
    }

    /// Throws `unreadable` for a video that cannot be exported, and logs
    /// whether the session said so or could not be asked.
    private static func requireExportable(_ asset: AVAsset) async throws {
        let isExportable: Bool
        do {
            isExportable = try await asset.load(.isExportable)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            NookTrayLog.logger.error("Export: asking whether the video can be exported failed (\(NookTrayLog.cause(error), privacy: .public))")
            throw NookTrayFileActionError.unreadable
        }
        guard isExportable else {
            NookTrayLog.logger.error("Export: the video says it cannot be exported")
            throw NookTrayFileActionError.unreadable
        }
    }

    /// Throws `noSound` only when the sound tracks loaded and there were
    /// none. A load that failed says `unreadable`, and logs why, because a
    /// video that could not be read is not a video with no sound.
    /// `countTracks` is the load, which a test replaces to make it fail.
    static func requireSound(countingWith countTracks: () async throws -> Int) async throws {
        let count: Int
        do {
            count = try await countTracks()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            NookTrayLog.logger.error("Export: loading the sound tracks failed (\(NookTrayLog.cause(error), privacy: .public))")
            throw NookTrayFileActionError.unreadable
        }
        guard count > 0 else { throw NookTrayFileActionError.noSound }
    }

    /// The preset and file type for an action. A video goes into a
    /// container without being decoded when the session can do that, and
    /// is encoded again when it cannot (a sound format the container does
    /// not hold, for one). A size preset the video is too small for falls
    /// back to the medium one, which makes a smaller file all the same.
    private static func exportPlan(for action: NookConvertAction, asset: AVAsset) async -> ExportPlan? {
        switch action {
        case .video(let container):
            let fileType: AVFileType = container == .mp4 ? .mp4 : .mov
            if await isCompatible(AVAssetExportPresetPassthrough, asset: asset, fileType: fileType) {
                return ExportPlan(preset: AVAssetExportPresetPassthrough, fileType: fileType)
            }
            return ExportPlan(preset: AVAssetExportPresetHighestQuality, fileType: fileType)
        case .smallerVideo(let size):
            let preset = size == .p1080 ? AVAssetExportPreset1920x1080 : AVAssetExportPreset1280x720
            if await isCompatible(preset, asset: asset, fileType: .mp4) {
                return ExportPlan(preset: preset, fileType: .mp4)
            }
            return ExportPlan(preset: AVAssetExportPresetMediumQuality, fileType: .mp4)
        case .soundOnly:
            return ExportPlan(preset: AVAssetExportPresetAppleM4A, fileType: .m4a)
        case .image, .resize, .smallerImage, .makeGIF, .pdfPages:
            return nil
        }
    }

    private static func isCompatible(_ preset: String, asset: AVAsset, fileType: AVFileType) async -> Bool {
        await AVAssetExportSession.compatibility(ofExportPreset: preset, with: asset, outputFileType: fileType)
    }

    /// Runs a session the way the running macOS allows. A task cancel
    /// stops the export either way.
    private final class ExportBox: @unchecked Sendable {
        private let session: AVAssetExportSession
        private let lock = NSLock()
        private var isStarted = false
        private var isCancelRequested = false

        init(_ session: AVAssetExportSession) {
            self.session = session
        }

        func run(
            to destination: URL,
            as fileType: AVFileType,
            progress: @escaping @Sendable (Double) -> Void
        ) async throws {
            try Task.checkCancellation()
            if #available(macOS 15, *) {
                try await runStates(to: destination, as: fileType, progress: progress)
            } else {
                try await runPolling(to: destination, as: fileType, progress: progress)
            }
        }

        /// macOS 15 and later: progress comes from the session's states, and
        /// the export stops by itself when its task is cancelled. Asking the
        /// session to cancel from outside could land before it has taken its
        /// output settings, which is a crash.
        @available(macOS 15, *)
        private func runStates(
            to destination: URL,
            as fileType: AVFileType,
            progress: @escaping @Sendable (Double) -> Void
        ) async throws {
            let watcher = Task { [self] in
                for await state in session.states(updateInterval: 0.2) {
                    if case .exporting(let exportProgress) = state {
                        progress(exportProgress.fractionCompleted)
                    }
                }
            }
            defer { watcher.cancel() }
            try await session.export(to: destination, as: fileType)
        }

        /// macOS 14: the session writes on its own queue, its progress is
        /// read every fifth of a second, and a cancel is passed on once the
        /// export has started and never before.
        private func runPolling(
            to destination: URL,
            as fileType: AVFileType,
            progress: @escaping @Sendable (Double) -> Void
        ) async throws {
            session.outputURL = destination
            session.outputFileType = fileType
            let poller = Task { [self] in
                while !Task.isCancelled {
                    progress(Double(session.progress))
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            defer { poller.cancel() }
            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    let didStart = lock.withLock { () -> Bool in
                        guard !isCancelRequested else { return false }
                        session.exportAsynchronously { continuation.resume() }
                        isStarted = true
                        return true
                    }
                    if !didStart { continuation.resume() }
                }
            } onCancel: {
                lock.withLock {
                    isCancelRequested = true
                    if isStarted { session.cancelExport() }
                }
            }
            if lock.withLock({ isCancelRequested }) { throw CancellationError() }
            switch session.status {
            case .completed: return
            case .cancelled: throw CancellationError()
            default: throw session.error ?? NookTrayFileActionError.writeFailed
            }
        }
    }

    // MARK: - PDF

    /// One picture for each page of a PDF, written into `folder` as
    /// "name page 1.png". A PDF over `maxPages` is refused before any page
    /// is drawn.
    static func pdfPages(
        at source: URL,
        to folder: URL,
        format: NookPageImage,
        maxPages: Int = NookConvertRules.maxPDFPages
    ) throws {
        guard let document = PDFDocument(url: source), document.pageCount > 0 else {
            throw NookTrayFileActionError.unreadable
        }
        guard document.pageCount <= maxPages else { throw NookTrayFileActionError.tooLarge }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = source.deletingPathExtension().lastPathComponent
        let target: NookImageTarget = format == .png ? .png : .jpeg
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index), let image = renderedPage(page) else {
                throw NookTrayFileActionError.unreadable
            }
            let file = folder.appendingPathComponent("\(name) page \(index + 1).\(target.fileExtension)")
            try write(image, to: file, target: target)
        }
    }

    /// Joins PDFs into one, in the order given.
    static func joinPDFs(_ sources: [URL], to destination: URL) throws {
        let joined = PDFDocument()
        for source in sources {
            try Task.checkCancellation()
            guard let document = PDFDocument(url: source), document.pageCount > 0 else {
                throw NookTrayFileActionError.unreadable
            }
            for index in 0..<document.pageCount {
                // A page belongs to one document. The copy goes into the new one.
                guard let page = document.page(at: index)?.copy() as? PDFPage else {
                    throw NookTrayFileActionError.unreadable
                }
                joined.insert(page, at: joined.pageCount)
            }
        }
        guard joined.pageCount > 0, joined.write(to: destination) else {
            throw NookTrayFileActionError.writeFailed
        }
    }

    /// One PDF with a page for each picture, in the order given.
    static func picturesToPDF(_ sources: [URL], to destination: URL) throws {
        let document = PDFDocument()
        for source in sources {
            try Task.checkCancellation()
            let image = try NookTrayFileActions.uprightImage(at: source)
            let picture = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            guard let page = PDFPage(image: picture) else { throw NookTrayFileActionError.unreadable }
            document.insert(page, at: document.pageCount)
        }
        guard document.pageCount > 0, document.write(to: destination) else {
            throw NookTrayFileActionError.writeFailed
        }
    }

    // MARK: - Private

    /// A page drawn on white at twice its size, turned the way a viewer
    /// shows it. A page too big for the pixel limit is drawn smaller.
    private static func renderedPage(_ page: PDFPage) -> CGImage? {
        guard let reference = page.pageRef else { return nil }
        let box = reference.getBoxRect(.cropBox)
        let isSideways = reference.rotationAngle % 180 != 0
        let width = isSideways ? box.height : box.width
        let height = isSideways ? box.width : box.height
        guard width > 0, height > 0 else { return nil }
        let fitting = (Double(NookTrayFileActions.maxConvertPixels) / Double(width * height)).squareRoot()
        let scale = min(Double(pageScale), fitting)
        let pixelWidth = max(1, Int((Double(width) * scale).rounded()))
        let pixelHeight = max(1, Int((Double(height) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }
        let canvas = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(canvas)
        context.concatenate(reference.getDrawingTransform(.cropBox, rect: canvas, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(reference)
        return context.makeImage()
    }

    private static func write(_ image: CGImage, to url: URL, target: NookImageTarget) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, target.typeIdentifier as CFString, 1, nil) else {
            throw NookTrayFileActionError.writeFailed
        }
        var options: [CFString: Any] = [:]
        if target.isLossy {
            options[kCGImageDestinationLossyCompressionQuality] = pageImageQuality
        }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw NookTrayFileActionError.writeFailed }
    }
}
