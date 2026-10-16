import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Draws the Record card the way the grid does: dark, with the motion stopped,
/// at the card's own width and height. Set `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to
/// also write the PNGs to `output/render/record-card/` under the repo root for
/// a visual check.
@MainActor
enum NookRecordCardSnapshot {
    /// Margin around the card in the picture, in points.
    static let margin: CGFloat = 8
    static let scale: CGFloat = 2

    /// The card at `size`, on a model that records nothing and reads no real
    /// setting. `phase` is where the recording is. `width` stands in for a
    /// narrower page than the real one.
    static func card(
        _ size: NookWidgetSize,
        phase: NookRecordPhase = .idle,
        options: NookRecordOptions = NookRecordOptions(),
        width: CGFloat? = nil
    ) -> some View {
        let defaults = MemoryDefaults()
        let record = NookRecordModel(
            recorder: FakeRecorder(),
            defaults: defaults,
            folder: URL(fileURLWithPath: "/tmp/hangover-record-card-render", isDirectory: true),
            createFolder: { _ in },
            sleep: { _ in },
            fileExists: { _ in false }
        )
        let nook = NookModel(record: record, defaults: defaults, looksForImportedGIF: false, asksMacOSForAccess: false)
        record.options = options
        record.phase = phase
        return NookRecordCardFrame(nook: nook, size: size, width: width ?? Self.width(size))
    }

    /// The width a card has at `size` on the page, in points.
    static func width(_ size: NookWidgetSize) -> CGFloat {
        size == .small ? 204 : 416
    }

    /// Draws `view` in a frame of its own, and writes the picture when asked.
    static func render(_ name: String, _ view: some View, writes: Bool = false) throws -> CGImage {
        let framed = view
            .padding(margin)
            .background(V6Palette.ink)
            .environment(\.colorScheme, .dark)
            .environment(\.nookDrawsStill, true)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = scale
        let image = try #require(renderer.cgImage, "ImageRenderer returned no image for \(name)")
        if writes, ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_SNAPSHOTS"] == "1" {
            let png = try #require(
                NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
                "PNG encoding failed for \(name)"
            )
            let directory = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("output/render/record-card", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return image
    }
}

/// The card in a frame of the size the grid gives it.
private struct NookRecordCardFrame: View {
    let nook: NookModel
    let size: NookWidgetSize
    let width: CGFloat

    var body: some View {
        NookRecordCard(nook: nook)
            .environment(\.nookWidgetSize, size)
            .frame(width: width, height: NookRecordCard.height(for: size))
    }
}

// MARK: - Reading a picture

/// A box of pixels, in the picture's own pixels, top left first.
struct NookRecordPixelBox: Equatable {
    var minX: Int
    var maxX: Int
    var minY: Int
    var maxY: Int

    var midX: Double { Double(minX + maxX) / 2 }
    var midY: Double { Double(minY + maxY) / 2 }
}

/// A rendered card as pixels. What counts as ink is whatever differs from the
/// colour most of the card is, which is the card's own background.
struct NookRecordPixels {
    let width: Int
    let height: Int
    private let bytes: [UInt8]
    private let background: [UInt8]

    /// The content area, in pixels: inside the card's padding.
    let content: NookRecordPixelBox

    @MainActor
    init(_ image: CGImage, size: NookWidgetSize, cardWidth: CGFloat) throws {
        width = image.width
        height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn: Bool = data.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        try #require(drawn, "could not read the picture's pixels")
        bytes = data
        let scale = NookRecordCardSnapshot.scale
        let margin = NookRecordCardSnapshot.margin
        let inset = NookRecordCardLayout.verticalPadding
        content = NookRecordPixelBox(
            minX: Int((margin + 14) * scale),
            maxX: Int((margin + cardWidth - 14) * scale) - 1,
            minY: Int((margin + inset) * scale),
            maxY: Int((margin + NookRecordCard.height(for: size) - inset) * scale) - 1
        )
        background = Self.mostCommonColor(in: data, width: width, box: content)
    }

    private static func mostCommonColor(in data: [UInt8], width: Int, box: NookRecordPixelBox) -> [UInt8] {
        var counts: [UInt32: Int] = [:]
        for y in box.minY...box.maxY {
            for x in box.minX...box.maxX {
                let i = (y * width + x) * 4
                counts[UInt32(data[i]) << 16 | UInt32(data[i + 1]) << 8 | UInt32(data[i + 2]), default: 0] += 1
            }
        }
        let packed = counts.max { $0.value < $1.value }?.key ?? 0
        return [UInt8(packed >> 16 & 0xFF), UInt8(packed >> 8 & 0xFF), UInt8(packed & 0xFF)]
    }

    private func channels(_ x: Int, _ y: Int) -> [Int] {
        let i = (y * width + x) * 4
        return [Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2])]
    }

    func isInk(_ x: Int, _ y: Int) -> Bool {
        let pixel = channels(x, y)
        return zip(pixel, background).contains { abs($0 - Int($1)) > 14 }
    }

    /// Strong red, which only the Record button and the stop button have.
    func isRed(_ x: Int, _ y: Int) -> Bool {
        let pixel = channels(x, y)
        return pixel[0] > 170 && pixel[1] < 110 && pixel[2] < 110
    }

    /// The rows of ink in the content area, top to bottom: each is a run of
    /// pixel rows that have any ink, with how far left and right it reaches.
    var bands: [NookRecordPixelBox] {
        var found: [NookRecordPixelBox] = []
        var current: NookRecordPixelBox?
        for y in content.minY...content.maxY {
            let inked = (content.minX...content.maxX).filter { isInk($0, y) }
            guard let first = inked.first, let last = inked.last else {
                if let done = current { found.append(done) }
                current = nil
                continue
            }
            if var open = current {
                open.maxY = y
                open.minX = min(open.minX, first)
                open.maxX = max(open.maxX, last)
                current = open
            } else {
                current = NookRecordPixelBox(minX: first, maxX: last, minY: y, maxY: y)
            }
        }
        if let done = current { found.append(done) }
        return found
    }

    /// The box around every pixel that differs from `other`'s, nil for two
    /// pictures that are the same.
    func difference(from other: NookRecordPixels) -> NookRecordPixelBox? {
        var box: NookRecordPixelBox?
        for y in content.minY...content.maxY {
            for x in content.minX...content.maxX where zip(channels(x, y), other.channels(x, y)).contains(where: { abs($0 - $1) > 6 }) {
                box = NookRecordPixelBox(
                    minX: min(box?.minX ?? x, x), maxX: max(box?.maxX ?? x, x),
                    minY: min(box?.minY ?? y, y), maxY: max(box?.maxY ?? y, y)
                )
            }
        }
        return box
    }

    /// The box around the red pixels in the content area.
    var redBox: NookRecordPixelBox? {
        var box: NookRecordPixelBox?
        for y in content.minY...content.maxY {
            for x in content.minX...content.maxX where isRed(x, y) {
                box = NookRecordPixelBox(
                    minX: min(box?.minX ?? x, x), maxX: max(box?.maxX ?? x, x),
                    minY: min(box?.minY ?? y, y), maxY: max(box?.maxY ?? y, y)
                )
            }
        }
        return box
    }
}

// MARK: - Every state at every size

@MainActor @Suite(.serialized, .noNewWindows) struct NookRecordCardRenderTests {
    private static let someTime = Date(timeIntervalSince1970: 0)
    private static let folder = URL(fileURLWithPath: "/tmp/hangover-record-card-render/take.mov")

    /// Every state the card can show, by the name its picture carries.
    static let states: [(String, NookRecordPhase)] = [
        ("idle", .idle),
        ("counting", .countdown(secondsLeft: 3)),
        ("recording", .recording(startedAt: Date().addingTimeInterval(-754), pausedTotal: 0)),
        ("paused", .paused(startedAt: someTime, pausedAt: someTime.addingTimeInterval(5), pausedTotal: 0)),
        ("saving", .saving),
        ("saved", .finished(folder, endedBy: .user)),
        ("failed", .failed(.screenPermissionDenied)),
    ]

    @Test(arguments: NookWidgetSize.allCases)
    func everyStateDrawsAtEverySize(size: NookWidgetSize) throws {
        for (name, phase) in Self.states {
            let image = try NookRecordCardSnapshot.render(
                "record-\(size.rawValue)-\(name)", NookRecordCardSnapshot.card(size, phase: phase), writes: true
            )
            #expect(image.width > 0, "\(size) \(name) drew nothing")
        }
    }

    /// No row of anything is pushed to one side: whatever is on a row reaches
    /// across it, or sits in the middle of it. The old small card's capture
    /// choice, the old large card's switches and its lone title all hugged the
    /// left with the right half of their row empty.
    @Test(arguments: NookWidgetSize.allCases)
    func noRowHugsOneSideOfTheCardInAnyState(size: NookWidgetSize) throws {
        let cardWidth = NookRecordCardSnapshot.width(size)
        for (name, phase) in Self.states {
            let image = try NookRecordCardSnapshot.render(
                "record-\(size.rawValue)-\(name)", NookRecordCardSnapshot.card(size, phase: phase)
            )
            let pixels = try NookRecordPixels(image, size: size, cardWidth: cardWidth)
            let middle = pixels.content.midX
            let span = Double(pixels.content.maxX - pixels.content.minX)
            for band in pixels.bands {
                let off = abs(band.midX - middle) / span
                #expect(off <= 0.12, "\(size) \(name): a row at y \(band.minY / 2) is \(Int(off * 100))% off the middle")
            }
        }
    }
}

// MARK: - The idle layout

@MainActor @Suite(.serialized, .noNewWindows) struct NookRecordIdleLayoutTests {
    private func pixels(
        _ name: String, _ size: NookWidgetSize, options: NookRecordOptions = NookRecordOptions(), width: CGFloat? = nil
    ) throws -> NookRecordPixels {
        let cardWidth = width ?? NookRecordCardSnapshot.width(size)
        let image = try NookRecordCardSnapshot.render(
            name, NookRecordCardSnapshot.card(size, options: options, width: width)
        )
        return try NookRecordPixels(image, size: size, cardWidth: cardWidth)
    }

    private func options(capture: NookRecordCapture = .fullScreen, switches: Bool) -> NookRecordOptions {
        var options = NookRecordOptions()
        options.capture = capture
        options.faceCam = switches
        options.voice = switches
        options.macSound = switches
        return options
    }

    /// Where the capture choice and the three switches sit, read off the
    /// pictures: each is found by changing only it and seeing what moved.
    private func groups(_ size: NookWidgetSize, width: CGFloat? = nil) throws
        -> (capture: NookRecordPixelBox, switches: NookRecordPixelBox, content: NookRecordPixelBox) {
        let suffix = width.map { "-\(Int($0))" } ?? ""
        let off = try pixels("record-\(size.rawValue)-switches-off\(suffix)", size, options: options(switches: false), width: width)
        let on = try pixels("record-\(size.rawValue)-switches-on\(suffix)", size, options: options(switches: true), width: width)
        let area = try pixels("record-\(size.rawValue)-area\(suffix)", size, options: options(capture: .area, switches: false), width: width)
        let switches = try #require(off.difference(from: on), "turning the switches on changed nothing")
        let capture = try #require(off.difference(from: area), "choosing Area changed nothing")
        return (capture, switches, off.content)
    }

    @Test func theCaptureChoiceIsOnTheLeftAndTheSwitchesOnTheRightOfOneRowAtMedium() throws {
        let (capture, switches, content) = try groups(.medium)
        let span = Double(content.maxX - content.minX)
        #expect(capture.minX - content.minX < 8, "the capture choice starts at the left edge")
        #expect(switches.maxX >= content.maxX - 4, "the switches end at the right edge")
        #expect(Double(switches.minX - content.minX) > span * 0.4, "the switches are on the right half")
        #expect(abs(capture.midY - switches.midY) < 4, "both groups share one row")
        #expect(capture.maxX < switches.minX, "the capture choice ends before the switches begin")
    }

    // Away from the widths where the choice of capture mode (whose name is
    // longer or shorter) tips the row from one fit to the next.
    @Test(arguments: [330, 250] as [CGFloat])
    func aNarrowerPageKeepsBothGroupsOnOneRowAtMedium(width: CGFloat) throws {
        _ = try NookRecordCardSnapshot.render(
            "record-medium-narrow-\(Int(width))", NookRecordCardSnapshot.card(.medium, width: width), writes: true
        )
        let (capture, switches, _) = try groups(.medium, width: width)
        #expect(abs(capture.midY - switches.midY) < 4, "both groups still share one row at \(width) points")
        #expect(capture.maxX < switches.minX, "the groups do not run into each other at \(width) points")
    }

    @Test(arguments: NookWidgetSize.allCases)
    func theRecordButtonRunsTheWholeWidthOfTheCard(size: NookWidgetSize) throws {
        let idle = try pixels("record-\(size.rawValue)-idle-button", size)
        let button = try #require(idle.redBox, "no Record button was drawn")
        #expect(button.minX - idle.content.minX < 8, "\(size): the button starts at the left edge")
        #expect(button.maxX >= idle.content.maxX - 4, "\(size): the button ends at the right edge")
    }

    @Test(arguments: [NookWidgetSize.small, .large])
    func theCaptureChoiceAndTheSwitchesEachRunTheWholeWidthWhereTheyHaveARow(size: NookWidgetSize) throws {
        let (capture, switches, content) = try groups(size)
        #expect(capture.maxX >= content.maxX - 4, "\(size): the capture choice reaches the right edge")
        #expect(switches.maxX >= content.maxX - 4, "\(size): the switches reach the right edge")
        #expect(capture.midY != switches.midY, "\(size): they have a row each")
    }

    @Test func theMediumCardHasThreeRowsAndTheButtonIsTheLastOne() throws {
        let idle = try pixels("record-medium-idle-rows", .medium)
        let bands = idle.bands
        #expect(bands.count == 3, "title and quality, then capture and switches, then Record: \(bands.count) rows")
        let button = try #require(idle.redBox)
        #expect(try #require(bands.last).minY == button.minY)
    }
}
