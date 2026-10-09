import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import OpenIslandApp

// MARK: - Test files

/// Makes small files in a folder of its own and reads results back. Nothing
/// here touches the real tray folder.
private enum TrayTestFiles {
    static func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NookTrayToolsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A picture whose left half is see-through and whose right half is red.
    static func makeImage(width: Int, height: Int) throws -> CGImage {
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
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return try #require(context.makeImage())
    }

    /// False when this Mac cannot write the format, which only HEIC may hit.
    @discardableResult
    static func write(_ image: CGImage, to url: URL, type: UTType, orientation: Int? = nil) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            return false
        }
        var options: [CFString: Any] = [:]
        if let orientation { options[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    struct Decoded {
        let typeIdentifier: String
        let width: Int
        let height: Int
        let image: CGImage
    }

    static func decode(_ url: URL) throws -> Decoded {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let type = try #require(CGImageSourceGetType(source)) as String
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return Decoded(typeIdentifier: type, width: image.width, height: image.height, image: image)
    }

    /// Red, green and blue of one pixel, counted from the top left.
    static func pixel(of image: CGImage, x: Int, y: Int) throws -> (red: Int, green: Int, blue: Int) {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &bytes,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let offset = (y * image.width + x) * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }

    static func zipEntries(_ zip: URL) throws -> [String] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        process.arguments = ["-1", zip.path]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }
}

// MARK: - File work

@Suite struct NookTrayFileActionsTests {
    // MARK: Names and targets

    @Test func picturesConvertToTheOtherCommonFormat() {
        #expect(NookTrayFileActions.conversionTarget(forFileNamed: "shot.png") == .jpeg)
        #expect(NookTrayFileActions.conversionTarget(forFileNamed: "SHOT.PNG") == .jpeg)
        #expect(NookTrayFileActions.conversionTarget(forFileNamed: "photo.jpg") == .png)
        #expect(NookTrayFileActions.conversionTarget(forFileNamed: "photo.jpeg") == .png)
        #expect(NookTrayFileActions.conversionTarget(forFileNamed: "IMG_0001.HEIC") == .jpeg)
        #expect(NookTrayFileActions.conversionTarget(forFileNamed: "live.heif") == .jpeg)
    }

    @Test func otherFilesHaveNoConversion() {
        #expect(NookTrayFileActions.conversionTarget(forFileNamed: "notes.txt") == nil)
        #expect(NookTrayFileActions.conversionTarget(forFileNamed: "archive.zip") == nil)
        #expect(NookTrayFileActions.conversionTarget(forFileNamed: "png") == nil)
        #expect(NookTrayFileActions.conversionTarget(forFileNamed: "") == nil)
    }

    @Test func convertedNameSwapsTheExtension() {
        #expect(NookTrayFileActions.convertedName(for: "photo.heic", to: .jpeg) == "photo.jpg")
        #expect(NookTrayFileActions.convertedName(for: "my.shot.jpeg", to: .png) == "my.shot.png")
        #expect(NookTrayFileActions.convertedName(for: "bare", to: .png) == "bare.png")
    }

    @Test func zipNameKeepsTheExtension() {
        #expect(NookTrayFileActions.zipName(for: "notes.txt") == "notes.txt.zip")
        #expect(NookTrayFileActions.zipName(for: "Folder") == "Folder.zip")
    }

    @Test func onlyAFolderKeepsItsParentInTheArchive() {
        let source = URL(fileURLWithPath: "/tmp/a/thing")
        let destination = URL(fileURLWithPath: "/tmp/b/thing.zip")

        let file = NookTrayFileActions.zipArguments(source: source, destination: destination, isDirectory: false)
        let folder = NookTrayFileActions.zipArguments(source: source, destination: destination, isDirectory: true)

        #expect(!file.contains("--keepParent"))
        #expect(folder.contains("--keepParent"))
        #expect(file.suffix(2) == [source.path, destination.path])
        #expect(folder.suffix(2) == [source.path, destination.path])
    }

    // MARK: Zip

    @Test func zipsOneFileAndLeavesItAlone() throws {
        let folder = try TrayTestFiles.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("note.txt")
        try Data("hello".utf8).write(to: source)
        let zip = folder.appendingPathComponent("note.txt.zip")

        try NookTrayFileActions.zip(source, to: zip)

        #expect(try TrayTestFiles.zipEntries(zip) == ["note.txt"])
        #expect(try Data(contentsOf: source) == Data("hello".utf8))
    }

    @Test func zipsAFolderUnderItsOwnName() throws {
        let folder = try TrayTestFiles.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: source.appendingPathComponent("a.txt"))
        let zip = folder.appendingPathComponent("Project.zip")

        try NookTrayFileActions.zip(source, to: zip)

        let entries = try TrayTestFiles.zipEntries(zip)
        #expect(entries.contains("Project/a.txt"))
        #expect(!entries.contains { $0.hasPrefix("__MACOSX") })
    }

    @Test func zippingAMissingFileThrows() throws {
        let folder = try TrayTestFiles.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(throws: NookTrayFileActionError.unreadable) {
            try NookTrayFileActions.zip(
                folder.appendingPathComponent("gone.txt"),
                to: folder.appendingPathComponent("gone.txt.zip")
            )
        }
    }

    @Test func aFailedZipCarriesTheToolsStatusAndWords() throws {
        let folder = try TrayTestFiles.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("note.txt")
        try Data("hello".utf8).write(to: source)
        // A folder already sits where the zip should land, which the tool
        // refuses to write over.
        let destination = folder.appendingPathComponent("note.txt.zip", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        do {
            try NookTrayFileActions.zip(source, to: destination)
            Issue.record("the zip should have failed")
        } catch let NookTrayFileActionError.zipFailed(status, detail) {
            let clean: Int32 = 0
            #expect(status != clean)
            #expect(!detail.isEmpty)
            #expect(!detail.contains("\n"))
            #expect(detail.count <= NookTrayFileActions.zipErrorLimit)
            #expect(NookTrayFileActionError.zipFailed(status: status, detail: detail).logSummary.contains("\(status)"))
        }
        // The folder in the way is left as it was.
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
    }

    @Test func theZipToolsWordsBecomeOneShortCleanLine() {
        let noisy = Data("ditto: one\nditto: two\u{1B}[0m\r\n\u{0}".utf8)
        let long = Data(String(repeating: "x", count: 5000).utf8)

        #expect(NookTrayFileActions.zipErrorDetail(from: noisy) == "ditto: one | ditto: two[0m")
        #expect(NookTrayFileActions.zipErrorDetail(from: long).count == NookTrayFileActions.zipErrorLimit)
        #expect(NookTrayFileActions.zipErrorDetail(from: Data()).isEmpty)
    }

    @Test func onlyAPictureOverTheLimitHasItsOwnNotice() {
        #expect(NookTrayFileActionError.tooLarge.noticeKey == "nook.tray.notice.convertTooLarge")
        #expect(NookTrayFileActionError.unreadable.noticeKey == nil)
        #expect(NookTrayFileActionError.writeFailed.noticeKey == nil)
        #expect(NookTrayFileActionError.zipFailed(status: 1, detail: "x").noticeKey == nil)
        // The tool's own words stay out of the public part of the log.
        #expect(!NookTrayFileActionError.zipFailed(status: 1, detail: "secret.txt").logSummary.contains("secret"))
        #expect(NookTrayFileActionError.zipFailed(status: 1, detail: "secret.txt").logDetail == "secret.txt")
        #expect(NookTrayFileActionError.tooLarge.logDetail.isEmpty)
    }

    // MARK: Convert

    @Test func aPictureSizeIsHeldToThePixelLimit() {
        let limit: Int = NookTrayFileActions.maxConvertPixels
        // A 48 megapixel phone photo and a 61 megapixel full frame one.
        #expect(NookTrayFileActions.isWithinConvertLimit(width: 8064, height: 6048))
        #expect(NookTrayFileActions.isWithinConvertLimit(width: 9504, height: 6336))
        #expect(NookTrayFileActions.isWithinConvertLimit(width: 8000, height: 8000))
        #expect(NookTrayFileActions.isWithinConvertLimit(width: limit, height: 1))
        // What a small file can claim in its header.
        #expect(!NookTrayFileActions.isWithinConvertLimit(width: 30000, height: 30000))
        #expect(!NookTrayFileActions.isWithinConvertLimit(width: limit + 1, height: 1))
        #expect(!NookTrayFileActions.isWithinConvertLimit(width: 8001, height: 8000))
        // A size that does not fit in a number, and sizes that are no size.
        #expect(!NookTrayFileActions.isWithinConvertLimit(width: Int.max, height: Int.max))
        #expect(!NookTrayFileActions.isWithinConvertLimit(width: 0, height: 100))
        #expect(!NookTrayFileActions.isWithinConvertLimit(width: 100, height: -1))
    }

    @Test(arguments: [NookTrayImageFormat.jpeg, .png])
    func aPictureOverTheLimitIsRefusedAndNothingIsWritten(format: NookTrayImageFormat) throws {
        let folder = try TrayTestFiles.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent(format == .jpeg ? "wide.png" : "wide.jpg")
        let image = try TrayTestFiles.makeImage(width: 40, height: 30)
        #expect(TrayTestFiles.write(image, to: source, type: format == .jpeg ? .png : .jpeg))
        let before = try Data(contentsOf: source)
        let destination = folder.appendingPathComponent("wide." + format.fileExtension)

        // 40 by 30 is 1200 pixels. One under that refuses it.
        #expect(throws: NookTrayFileActionError.tooLarge) {
            try NookTrayFileActions.convertImage(at: source, to: destination, format: format, maxPixels: 1199)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(try Data(contentsOf: source) == before)

        // At the limit it goes through.
        try NookTrayFileActions.convertImage(at: source, to: destination, format: format, maxPixels: 1200)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func pngBecomesJpegOnWhiteAndTheOriginalStays() throws {
        let folder = try TrayTestFiles.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("shot.png")
        #expect(TrayTestFiles.write(try TrayTestFiles.makeImage(width: 40, height: 20), to: source, type: .png))
        let before = try Data(contentsOf: source)
        let destination = folder.appendingPathComponent("shot.jpg")

        try NookTrayFileActions.convertImage(at: source, to: destination, format: .jpeg)

        let decoded = try TrayTestFiles.decode(destination)
        #expect(decoded.typeIdentifier == UTType.jpeg.identifier)
        let expectedWidth: Int = 40
        let expectedHeight: Int = 20
        #expect(decoded.width == expectedWidth)
        #expect(decoded.height == expectedHeight)
        // The see-through half is white now, not black.
        let clear = try TrayTestFiles.pixel(of: decoded.image, x: 5, y: 10)
        #expect(clear.red > 235 && clear.green > 235 && clear.blue > 235)
        let red = try TrayTestFiles.pixel(of: decoded.image, x: 34, y: 10)
        #expect(red.red > 200 && red.green < 60 && red.blue < 60)
        #expect(try Data(contentsOf: source) == before)
    }

    @Test func jpegBecomesPngTurnedUpright() throws {
        let folder = try TrayTestFiles.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("photo.jpg")
        // Orientation 6 is how a phone held upright tags a sideways sensor.
        #expect(TrayTestFiles.write(
            try TrayTestFiles.makeImage(width: 40, height: 20),
            to: source,
            type: .jpeg,
            orientation: 6
        ))
        let destination = folder.appendingPathComponent("photo.png")

        try NookTrayFileActions.convertImage(at: source, to: destination, format: .png)

        let decoded = try TrayTestFiles.decode(destination)
        #expect(decoded.typeIdentifier == UTType.png.identifier)
        let expectedWidth: Int = 20
        let expectedHeight: Int = 40
        #expect(decoded.width == expectedWidth)
        #expect(decoded.height == expectedHeight)
    }

    @Test func heicBecomesJpeg() throws {
        let folder = try TrayTestFiles.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("IMG_0001.heic")
        // A Mac with no HEIC encoder cannot make the test file.
        guard TrayTestFiles.write(try TrayTestFiles.makeImage(width: 64, height: 64), to: source, type: .heic) else {
            return
        }
        let destination = folder.appendingPathComponent("IMG_0001.jpg")

        try NookTrayFileActions.convertImage(at: source, to: destination, format: .jpeg)

        let decoded = try TrayTestFiles.decode(destination)
        #expect(decoded.typeIdentifier == UTType.jpeg.identifier)
        let expectedSide: Int = 64
        #expect(decoded.width == expectedSide)
        #expect(decoded.height == expectedSide)
    }

    @Test func aFileThatIsNotAPictureThrowsAndWritesNothing() throws {
        let folder = try TrayTestFiles.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("fake.png")
        try Data("not a picture".utf8).write(to: source)
        let destination = folder.appendingPathComponent("fake.jpg")

        #expect(throws: NookTrayFileActionError.unreadable) {
            try NookTrayFileActions.convertImage(at: source, to: destination, format: .jpeg)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    // MARK: Thumbnail

    @Test func thumbnailIsASmallPng() throws {
        let folder = try TrayTestFiles.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("wide.png")
        #expect(TrayTestFiles.write(try TrayTestFiles.makeImage(width: 400, height: 200), to: source, type: .png))

        let thumbnail = try #require(NookClipboardThumbnail.make(from: try Data(contentsOf: source)))
        let imageSource = try #require(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))

        let expectedWidth: Int = NookClipboardThumbnail.maxPixelSize
        let expectedHeight: Int = 48
        #expect(image.width == expectedWidth)
        #expect(image.height == expectedHeight)
        #expect(NookClipboardThumbnail.make(from: Data("not a picture".utf8)) == nil)
    }
}

// MARK: - The store

@MainActor
@Suite struct NookTrayStoreToolsTests {
    /// A store on a folder, a pasteboard and settings of its own, held in memory.
    private struct Fixture {
        let store: NookTrayStore
        let folder: URL
        let outside: URL
        let pasteboard: NookFakePasteboard
        let defaults: UserDefaults
        let suiteName: String

        @MainActor
        init() throws {
            folder = try TrayTestFiles.makeFolder()
            outside = try TrayTestFiles.makeFolder()
            suiteName = "NookTrayStoreToolsTests"
            defaults = MemoryDefaults()
            pasteboard = NookFakePasteboard()
            store = NookTrayStore(
                folder: folder,
                clipboard: NookClipboardMonitor(pasteboard: pasteboard, defaults: defaults),
                defaults: defaults
            )
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: outside)
            defaults.removePersistentDomain(forName: suiteName)
        }

        /// Adds a file to the tray and waits for the copy to land.
        @MainActor
        func addFile(named name: String, contents: Data) async throws -> NookTrayItem {
            let source = outside.appendingPathComponent(name)
            try contents.write(to: source)
            await store.add(fileAt: source)?.value
            return try #require(store.items.first { $0.originalName == name })
        }

        var subfolderCount: Int {
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey]
            )) ?? []
            return entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.count
        }
    }

    @Test func compressAddsTheZipAsANewFileAndKeepsTheOriginal() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.addFile(named: "note.txt", contents: Data("hello".utf8))

        await fixture.store.compress(item).value

        let expectedCount: Int = 2
        #expect(fixture.store.items.count == expectedCount)
        let zip = try #require(fixture.store.items.first)
        #expect(zip.originalName == "note.txt.zip")
        #expect(try TrayTestFiles.zipEntries(fixture.store.storedURL(for: zip)) == ["note.txt"])
        #expect(try Data(contentsOf: fixture.store.storedURL(for: item)) == Data("hello".utf8))
        #expect(fixture.store.workingIDs.isEmpty)
    }

    @Test func convertAddsThePictureInItsNewFormat() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let png = fixture.outside.appendingPathComponent("made.png")
        #expect(TrayTestFiles.write(try TrayTestFiles.makeImage(width: 16, height: 16), to: png, type: .png))
        let item = try await fixture.addFile(named: "shot.png", contents: try Data(contentsOf: png))

        await fixture.store.convert(item, to: .jpeg).value

        let converted = try #require(fixture.store.items.first)
        #expect(converted.originalName == "shot.jpg")
        let decoded = try TrayTestFiles.decode(fixture.store.storedURL(for: converted))
        #expect(decoded.typeIdentifier == UTType.jpeg.identifier)
        #expect(FileManager.default.fileExists(atPath: fixture.store.storedURL(for: item).path))
    }

    @Test func aFailedActionSaysSoAndLeavesNothingBehind() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.addFile(named: "fake.png", contents: Data("not a picture".utf8))
        let foldersBefore = fixture.subfolderCount

        await fixture.store.convert(item, to: .jpeg).value

        let expectedCount: Int = 1
        #expect(fixture.store.items.count == expectedCount)
        #expect(fixture.store.notice?.isError == true)
        #expect(fixture.store.workingIDs.isEmpty)
        #expect(fixture.subfolderCount == foldersBefore)
    }

    @Test func compressingAFileThatVanishedSaysSo() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.addFile(named: "note.txt", contents: Data("hello".utf8))
        try FileManager.default.removeItem(at: fixture.store.storedURL(for: item))

        await fixture.store.compress(item).value

        let expectedCount: Int = 1
        #expect(fixture.store.items.count == expectedCount)
        #expect(fixture.store.notice?.isError == true)
    }

    @Test func copyPathPutsTheTrayCopysPathOnThePasteboard() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.addFile(named: "note.txt", contents: Data("hello".utf8))

        fixture.store.copyPath(of: item)

        #expect(fixture.pasteboard.content == .text(fixture.store.storedURL(for: item).path))
        #expect(fixture.store.notice?.isError == false)
    }

    @Test func aRefusedCopySaysSo() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.addFile(named: "note.txt", contents: Data("hello".utf8))
        fixture.pasteboard.acceptsWrites = false

        fixture.store.copyPath(of: item)

        #expect(fixture.store.notice?.isError == true)
    }

    @Test func askingForAPrivateCopyExplainsWhyNothingWasAdded() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.pasteboard.accessValue = .asks
        fixture.store.clipboard.setEnabled(true)
        fixture.pasteboard.simulateCopy(.text("x"), types: ["org.nspasteboard.ConcealedType"])

        fixture.store.captureClipboardNow()

        #expect(fixture.store.notice != nil)
        #expect(fixture.store.notice?.isError == false)
        #expect(fixture.store.clipboard.history.entries.isEmpty)
    }

    @Test func theChosenTabIsSavedAndComesBack() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        #expect(fixture.store.tab == .files)

        fixture.store.tab = .clipboard

        let saved = fixture.defaults.persistentDomain(forName: fixture.suiteName) ?? [:]
        #expect(saved[NookTrayStore.tabKey] as? String == "clipboard")
        let reopened = NookTrayStore(
            folder: fixture.folder,
            clipboard: NookClipboardMonitor(pasteboard: fixture.pasteboard, defaults: fixture.defaults),
            defaults: fixture.defaults
        )
        #expect(reopened.tab == .clipboard)
    }

    @Test func droppedFilesTurnTheCardToTheFileList() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let source = fixture.outside.appendingPathComponent("dropped.txt")
        try Data("hello".utf8).write(to: source)
        fixture.store.tab = .clipboard

        #expect(!fixture.store.handleDrop([NSItemProvider(object: "just text" as NSString)]))
        #expect(fixture.store.tab == .clipboard)

        #expect(fixture.store.handleDrop([NSItemProvider(object: source as NSURL)]))
        #expect(fixture.store.tab == .files)

        // The copy lands a moment later. Wait for it before the folder goes.
        for _ in 0..<200 where fixture.store.items.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(fixture.store.items.first?.originalName == "dropped.txt")
    }
}

// MARK: - The island under a share picker

@Suite struct NookTraySharePickerRulesTests {
    private static func context(
        reason: NotchOpenReason,
        inExpandedArea: Bool,
        onNotch: Bool = false,
        blocksDismiss: Bool = false,
        hasOpenPicker: Bool
    ) -> IslandClickContext {
        IslandClickContext(
            status: .opened,
            reason: reason,
            isInClosedSurface: false,
            isInExpandedArea: inExpandedArea,
            isOnNotch: onNotch,
            blocksDismiss: blocksDismiss,
            hasOpenPicker: hasOpenPicker
        )
    }

    @Test func aClickOutsideBelongsToThePickerAndTheIslandStays() {
        for reason in [NotchOpenReason.hover, .click] {
            let action = IslandPointerRules.clickAction(
                Self.context(reason: reason, inExpandedArea: false, hasOpenPicker: true)
            )
            #expect(action == .none)
        }
    }

    @Test func withoutAPickerAClickOutsideStillCloses() {
        let action = IslandPointerRules.clickAction(
            Self.context(reason: .click, inExpandedArea: false, hasOpenPicker: false)
        )
        #expect(action == .dismiss)
    }

    @Test func thePickerWinsOverAPendingDecision() {
        let action = IslandPointerRules.clickAction(
            Self.context(reason: .click, inExpandedArea: false, blocksDismiss: true, hasOpenPicker: true)
        )
        #expect(action == .none)
    }

    @Test func theNotchStillClosesTheIslandUnderAPicker() {
        let action = IslandPointerRules.clickAction(
            Self.context(reason: .click, inExpandedArea: true, onNotch: true, hasOpenPicker: true)
        )
        #expect(action == .closeFromNotch)
    }

    @Test func aClickInsideStillPinsAHoverOpenedIsland() {
        let action = IslandPointerRules.clickAction(
            Self.context(reason: .hover, inExpandedArea: true, hasOpenPicker: true)
        )
        #expect(action == .pin)
    }
}

// MARK: - Strings

@Suite struct NookTrayStringsTests {
    /// `Tests/OpenIslandAppTests/<this file>` sits three levels below the root.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// Every "nook.tray." key written out in the tray's source files, plus
    /// the ones built from an enum's raw value.
    private static func usedKeys() throws -> Set<String> {
        let folder = repoRoot.appendingPathComponent("Sources/OpenIslandApp/Nook/Widgets/Tray")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        let pattern = try NSRegularExpression(pattern: "\"(nook\\.tray\\.[A-Za-z0-9.]+)\"")
        var keys = Set<String>()
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            for match in pattern.matches(in: source, range: range) {
                guard let keyRange = Range(match.range(at: 1), in: source) else { continue }
                keys.insert(String(source[keyRange]))
            }
        }
        // Defaults keys are not strings to show.
        keys.subtract([NookClipboardMonitor.enabledKey, NookTrayStore.tabKey])
        keys.formUnion(NookTrayTab.allCases.map(\.titleKey))
        keys.formUnion([NookTrayImageFormat.jpeg, .png].map(\.actionTitleKey))
        // The short lines the two smaller cards show, built from the long keys.
        keys.formUnion(["nook.tray.clipboard.asks.short", "nook.tray.clipboard.denied.short"])
        return keys
    }

    @Test func everyTrayStringExistsInEveryLanguageAndHasNoDash() throws {
        let keys = try Self.usedKeys()
        #expect(keys.count > 30)

        for language in ["en", "zh-Hans", "zh-Hant"] {
            let url = Self.repoRoot
                .appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String], "\(language) did not load")

            for key in keys.sorted() {
                let value = table[key] ?? ""
                #expect(!value.isEmpty, "\(language) is missing \(key)")
                #expect(!value.contains("\u{2014}") && !value.contains("\u{2013}"), "\(language) \(key) has a dash")
            }
        }
    }
}
