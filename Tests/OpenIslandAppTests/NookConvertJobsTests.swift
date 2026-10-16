import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import OpenIslandApp

// MARK: - Fixtures

/// Small files made inside the test, in a temp folder of their own that
/// `cleanUp()` removes. Nothing here reads or writes anywhere else, and no
/// screen, camera or microphone is involved.
struct NookConvertFixtures {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NookConvertFixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A name for a new file in the folder.
    func url(_ name: String) -> URL {
        folder.appendingPathComponent(name)
    }

    /// A PNG. Blue on the left and red on the right by default, see-through on the left
    /// half when `transparent`, and full of noise when `noisy`, which is
    /// what makes a lossy copy of it smaller at a lower quality.
    func png(width: Int, height: Int, transparent: Bool = false, noisy: Bool = false) throws -> URL {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        if noisy {
            var generator = SystemRandomNumberGenerator()
            for y in stride(from: 0, to: height, by: 4) {
                for x in stride(from: 0, to: width, by: 4) {
                    context.setFillColor(CGColor(
                        red: .random(in: 0...1, using: &generator),
                        green: .random(in: 0...1, using: &generator),
                        blue: .random(in: 0...1, using: &generator),
                        alpha: 1
                    ))
                    context.fill(CGRect(x: x, y: y, width: 4, height: 4))
                }
            }
        } else {
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
            if !transparent {
                context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
            }
        }
        let image = try #require(context.makeImage())
        let file = url("\(UUID().uuidString).png")
        let destination = try #require(CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return file
    }

    /// A PDF with `pages` pages, each `width` by `height` points.
    func pdf(pages: Int, width: Int = 120, height: Int = 80) throws -> URL {
        let document = PDFDocument()
        for _ in 0..<pages {
            let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
                NSColor.systemTeal.setFill()
                rect.fill()
                return true
            }
            document.insert(try #require(PDFPage(image: image)), at: document.pageCount)
        }
        let file = url("\(UUID().uuidString).pdf")
        #expect(document.write(to: file))
        return file
    }

    /// A 64 by 64 H.264 movie of `seconds` seconds, 30 pictures a second,
    /// with a second of sound as well when `withSound`.
    func movie(seconds: Int, withSound: Bool = false) throws -> URL {
        let file = url("\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: file, fileType: .mov)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: video,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64,
            ]
        )
        writer.add(video)
        var sound: AVAssetWriterInput?
        if withSound {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: 64_000,
            ])
            writer.add(input)
            sound = input
        }
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        let framesPerSecond = 30
        for index in 0..<(seconds * framesPerSecond) {
            while !video.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), Int32(index * 2 % 256), CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            let time = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(framesPerSecond))
            #expect(adaptor.append(pixels, withPresentationTime: time))
        }
        video.markAsFinished()
        if let sound {
            while !sound.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            #expect(sound.append(try Self.tone(seconds: 1)))
            sound.markAsFinished()
        }
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()
        #expect(writer.status == .completed)
        return file
    }

    /// A second of a quiet tone: 16 bit mono at 44.1 kHz.
    static func tone(seconds: Double) throws -> CMSampleBuffer {
        let sampleRate = 44_100.0
        let frames = Int(seconds * sampleRate)
        var description = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &description, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format
        )
        let samples = (0..<frames).map { Int16(sin(Double($0) * 2 * .pi * 440 / sampleRate) * 3000) }
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: frames * 2, blockAllocator: nil,
            customBlockSource: nil, offsetToData: 0, dataLength: frames * 2,
            flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block
        )
        let data = try #require(block)
        samples.withUnsafeBytes { bytes in
            _ = CMBlockBufferReplaceDataBytes(
                with: bytes.baseAddress!, blockBuffer: data, offsetIntoDestination: 0, dataLength: frames * 2
            )
        }
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: data, formatDescription: try #require(format),
            sampleCount: frames, presentationTimeStamp: .zero, packetDescriptions: nil, sampleBufferOut: &sample
        )
        return try #require(sample)
    }

    // MARK: Reading back

    func pixelSize(_ url: URL) throws -> CGSize {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return CGSize(width: image.width, height: image.height)
    }

    /// Red, green and blue of one pixel, counted from the top left.
    func pixel(_ url: URL, x: Int, y: Int) throws -> (red: Int, green: Int, blue: Int) {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let offset = (y * image.width + x) * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }

    func fileSize(_ url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
    }
}

// MARK: - Pictures

@Suite struct NookConvertImageJobsTests {
    @Test func pngBecomesEachOtherFormat() throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let source = try fixtures.png(width: 40, height: 20)
        let writable = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])

        for target in [NookImageTarget.jpeg, .heic, .tiff, .gif, .bmp] {
            // A Mac with no HEIC encoder cannot make this one.
            guard writable.contains(target.typeIdentifier) else { continue }
            let out = fixtures.url("out.\(target.fileExtension)")
            try NookConvertJobs.convertImage(at: source, to: out, target: target)
            let result = try #require(CGImageSourceCreateWithURL(out as CFURL, nil))
            #expect(CGImageSourceGetType(result) as String? == target.typeIdentifier)
            #expect(try fixtures.pixelSize(out) == CGSize(width: 40, height: 20))
        }
    }

    @Test func theSourceIsNeverChanged() throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let source = try fixtures.png(width: 40, height: 20)
        let before = try Data(contentsOf: source)

        try NookConvertJobs.convertImage(at: source, to: fixtures.url("a.jpg"), target: .jpeg)
        try NookConvertJobs.resize(at: source, to: fixtures.url("b.png"), resize: .half)
        try NookConvertJobs.smallerImage(at: source, to: fixtures.url("c.jpg"))

        #expect(try Data(contentsOf: source) == before)
    }

    @Test func aBMPOfASeeThroughPictureIsOnWhite() throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let source = try fixtures.png(width: 40, height: 20, transparent: true)
        let out = fixtures.url("out.bmp")

        try NookConvertJobs.convertImage(at: source, to: out, target: .bmp)

        // The left half was see-through, and BMP has no transparency.
        let clear = try fixtures.pixel(out, x: 5, y: 10)
        #expect(clear.red > 235 && clear.green > 235 && clear.blue > 235)
        let red = try fixtures.pixel(out, x: 34, y: 10)
        #expect(red.red > 200 && red.green < 60 && red.blue < 60)
    }

    @Test func resizeHalvesQuartersAndCapsTheLongSide() throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let source = try fixtures.png(width: 400, height: 200)

        let half = fixtures.url("h.png")
        try NookConvertJobs.resize(at: source, to: half, resize: .half)
        #expect(try fixtures.pixelSize(half) == CGSize(width: 200, height: 100))

        let quarter = fixtures.url("q.png")
        try NookConvertJobs.resize(at: source, to: quarter, resize: .quarter)
        #expect(try fixtures.pixelSize(quarter) == CGSize(width: 100, height: 50))

        let capped = fixtures.url("c.png")
        try NookConvertJobs.resize(at: source, to: capped, resize: .longSide(100))
        #expect(try fixtures.pixelSize(capped) == CGSize(width: 100, height: 50))

        // Never made bigger.
        let same = fixtures.url("s.png")
        try NookConvertJobs.resize(at: source, to: same, resize: .longSide(640))
        #expect(try fixtures.pixelSize(same) == CGSize(width: 400, height: 200))
    }

    @Test func resizeKeepsTheKindOfPicture() throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let png = try fixtures.png(width: 40, height: 20)
        let jpeg = fixtures.url("photo.jpg")
        try NookConvertJobs.convertImage(at: png, to: jpeg, target: .jpeg)

        let out = fixtures.url("photo (50%).jpg")
        try NookConvertJobs.resize(at: jpeg, to: out, resize: .half)

        let result = try #require(CGImageSourceCreateWithURL(out as CFURL, nil))
        #expect(CGImageSourceGetType(result) as String? == UTType.jpeg.identifier)
    }

    @Test func smallerImageIsAJPEGUnder2560AndTakesLessRoom() throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let source = try fixtures.png(width: 3200, height: 1600, noisy: true)
        let smaller = fixtures.url("smaller.jpg")
        let plain = fixtures.url("plain.jpg")

        try NookConvertJobs.smallerImage(at: source, to: smaller)
        try NookConvertJobs.convertImage(at: source, to: plain, target: .jpeg)

        let result = try #require(CGImageSourceCreateWithURL(smaller as CFURL, nil))
        #expect(CGImageSourceGetType(result) as String? == UTType.jpeg.identifier)
        #expect(try fixtures.pixelSize(smaller) == CGSize(width: 2560, height: 1280))
        #expect(try fixtures.fileSize(smaller) < fixtures.fileSize(plain))
    }

    @Test func aLowerQualityTakesLessRoom() throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let source = try fixtures.png(width: 400, height: 400, noisy: true)
        let low = fixtures.url("low.jpg")
        let high = fixtures.url("high.jpg")

        try NookConvertJobs.convertImage(at: source, to: low, target: .jpeg, quality: 0.2)
        try NookConvertJobs.convertImage(at: source, to: high, target: .jpeg, quality: 0.95)

        #expect(try fixtures.fileSize(low) < fixtures.fileSize(high))
    }

    @Test func aFileThatIsNotAPictureThrowsAndWritesNothing() throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let source = fixtures.url("fake.png")
        try Data("not a picture".utf8).write(to: source)
        let out = fixtures.url("fake.jpg")

        #expect(throws: NookTrayFileActionError.unreadable) {
            try NookConvertJobs.resize(at: source, to: out, resize: .half)
        }
        #expect(throws: NookTrayFileActionError.unreadable) {
            try NookConvertJobs.smallerImage(at: source, to: out)
        }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }

    @Test func onlyTheFirstPictureOfAnAnimatedGIFIsConverted() throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let source = fixtures.url("moving.gif")
        let frame = try NookConvertFixtureImage.make(width: 16, height: 8)
        try NookConvertFixtureImage.writeGIF([frame, frame, frame], to: source)
        let out = fixtures.url("moving.png")

        try NookConvertJobs.convertImage(at: source, to: out, target: .png)

        let result = try #require(CGImageSourceCreateWithURL(out as CFURL, nil))
        #expect(CGImageSourceGetCount(result) == 1)
        #expect(try fixtures.pixelSize(out) == CGSize(width: 16, height: 8))
    }
}

// MARK: - Video

@Suite(.serialized) struct NookConvertVideoJobsTests {
    func duration(of url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    @Test func movBecomesMP4AndKeepsItsLength() async throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let source = try fixtures.movie(seconds: 1)
        let before = try Data(contentsOf: source)
        let out = fixtures.url("o.mp4")

        try await NookConvertJobs.exportVideo(at: source, to: out, action: .video(.mp4)) { _ in }

        #expect(abs(try await duration(of: out) - 1) < 0.2)
        let tracks = try await AVURLAsset(url: out).loadTracks(withMediaType: .video)
        #expect(tracks.count == 1)
        #expect(try Data(contentsOf: source) == before)
    }

    @Test func mp4BecomesMOV() async throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let mov = try fixtures.movie(seconds: 1)
        let mp4 = fixtures.url("clip.mp4")
        try await NookConvertJobs.exportVideo(at: mov, to: mp4, action: .video(.mp4)) { _ in }
        let out = fixtures.url("clip.mov")

        try await NookConvertJobs.exportVideo(at: mp4, to: out, action: .video(.mov)) { _ in }

        #expect(abs(try await duration(of: out) - 1) < 0.2)
    }

    @Test func aSmallerVideoIsAnMP4OfTheSameLength() async throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let source = try fixtures.movie(seconds: 1)

        for (name, action) in [("a.mp4", NookConvertAction.smallerVideo(.p720)), ("b.mp4", .smallerVideo(.p1080))] {
            let out = fixtures.url(name)
            try await NookConvertJobs.exportVideo(at: source, to: out, action: action) { _ in }
            #expect(abs(try await duration(of: out) - 1) < 0.2)
            let tracks = try await AVURLAsset(url: out).loadTracks(withMediaType: .video)
            #expect(tracks.count == 1)
        }
    }

    @Test func soundOnlyIsAnM4AWithNoPicture() async throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let source = try fixtures.movie(seconds: 1, withSound: true)
        let out = fixtures.url("clip.m4a")

        try await NookConvertJobs.exportVideo(at: source, to: out, action: .soundOnly) { _ in }

        let asset = AVURLAsset(url: out)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        #expect(try await asset.loadTracks(withMediaType: .video).isEmpty)
        #expect(abs(try await duration(of: out) - 1) < 0.3)
    }

    @Test func aVideoWithNoSoundCannotBecomeSound() async throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let source = try fixtures.movie(seconds: 1)
        let out = fixtures.url("clip.m4a")

        await #expect(throws: NookTrayFileActionError.noSound) {
            try await NookConvertJobs.exportVideo(at: source, to: out, action: .soundOnly) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }

    @Test func aFileThatIsNotAVideoThrows() async throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let source = fixtures.url("fake.mov")
        try Data("not a video".utf8).write(to: source)
        let out = fixtures.url("fake.mp4")

        await #expect(throws: NookTrayFileActionError.unreadable) {
            try await NookConvertJobs.exportVideo(at: source, to: out, action: .video(.mp4)) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }

    @Test func aCancelledExportStopsAndLeavesNoFile() async throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let source = try fixtures.movie(seconds: 3)
        let out = fixtures.url("o.mp4")

        let job = Task {
            try await NookConvertJobs.exportVideo(at: source, to: out, action: .smallerVideo(.p720)) { _ in }
        }
        job.cancel()
        let result = await job.result

        #expect(throws: CancellationError.self) { try result.get() }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }
}

// MARK: - PDF

@Suite struct NookConvertPDFJobsTests {
    @Test func pdfPagesComeOutOnePictureEachAtTwiceTheirSize() throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let source = try fixtures.pdf(pages: 3, width: 120, height: 80)
        let out = fixtures.url("pages")

        try NookConvertJobs.pdfPages(at: source, to: out, format: .png)

        let names = try FileManager.default.contentsOfDirectory(atPath: out.path).sorted()
        let base = source.deletingPathExtension().lastPathComponent
        #expect(names == (1...3).map { "\(base) page \($0).png" })
        #expect(try fixtures.pixelSize(out.appendingPathComponent(names[0])) == CGSize(width: 240, height: 160))
    }

    @Test func pdfPagesCanBeJPEGToo() throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let out = fixtures.url("pages")

        try NookConvertJobs.pdfPages(at: try fixtures.pdf(pages: 2), to: out, format: .jpeg)

        let files = try FileManager.default.contentsOfDirectory(atPath: out.path).filter { $0.hasSuffix(".jpg") }
        #expect(files.count == 2)
        let first = out.appendingPathComponent(try #require(files.sorted().first))
        let source = try #require(CGImageSourceCreateWithURL(first as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
    }

    @Test func aPDFOverTheLimitIsRefusedBeforeAnyPageIsDrawn() throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let out = fixtures.url("x")

        #expect(throws: NookTrayFileActionError.tooLarge) {
            try NookConvertJobs.pdfPages(at: try fixtures.pdf(pages: 3), to: out, format: .png, maxPages: 2)
        }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }

    @Test func theLimitIs200Pages() {
        let limit: Int = NookConvertRules.maxPDFPages
        #expect(limit == 200)
    }

    @Test func aFileThatIsNotAPDFThrows() throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let source = fixtures.url("fake.pdf")
        try Data("not a pdf".utf8).write(to: source)

        #expect(throws: NookTrayFileActionError.unreadable) {
            try NookConvertJobs.pdfPages(at: source, to: fixtures.url("x"), format: .png)
        }
        #expect(throws: NookTrayFileActionError.unreadable) {
            try NookConvertJobs.joinPDFs([source], to: fixtures.url("j.pdf"))
        }
        #expect(!FileManager.default.fileExists(atPath: fixtures.url("j.pdf").path))
    }

    @Test func joinKeepsOrderAndCountsPages() throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let small = try fixtures.pdf(pages: 2, width: 100, height: 100)
        let large = try fixtures.pdf(pages: 3, width: 200, height: 200)
        let out = fixtures.url("j.pdf")

        try NookConvertJobs.joinPDFs([small, large], to: out)

        let joined = try #require(PDFDocument(url: out))
        #expect(joined.pageCount == 5)
        // The two small pages come first, as given.
        let widths = (0..<5).map { joined.page(at: $0)?.bounds(for: .mediaBox).width ?? 0 }
        #expect(widths == [100, 100, 200, 200, 200])
        // The PDFs it was made from are as they were.
        #expect(PDFDocument(url: small)?.pageCount == 2)
        #expect(PDFDocument(url: large)?.pageCount == 3)
    }

    @Test func picturesBecomeOnePDFInOrder() throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let wide = try fixtures.png(width: 40, height: 20)
        let tall = try fixtures.png(width: 20, height: 40)
        let out = fixtures.url("p.pdf")

        try NookConvertJobs.picturesToPDF([wide, tall], to: out)

        let document = try #require(PDFDocument(url: out))
        #expect(document.pageCount == 2)
        let first = try #require(document.page(at: 0)).bounds(for: .mediaBox)
        let second = try #require(document.page(at: 1)).bounds(for: .mediaBox)
        #expect(first.width > first.height)
        #expect(second.height > second.width)
    }

    @Test func aPictureThatIsNotOneStopsThePDF() throws {
        let fixtures = try NookConvertFixtures()
        defer { fixtures.cleanUp() }
        let fake = fixtures.url("fake.png")
        try Data("not a picture".utf8).write(to: fake)
        let out = fixtures.url("p.pdf")

        #expect(throws: NookTrayFileActionError.unreadable) {
            try NookConvertJobs.picturesToPDF([try fixtures.png(width: 8, height: 8), fake], to: out)
        }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }
}
