import AppKit
import CoreGraphics
import Foundation
import PDFKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Makes sample strips from pictures drawn in code. Set
/// `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to also write each strip as a PDF and
/// a PNG to `output/render/photobooth/` under the repo root.
@Suite(.serialized, .oneStripAtATime)
struct NookPhotoBoothRenderTests {
    private static let date = Date(timeIntervalSince1970: 1_791_600_420)
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private static func input(
        _ kind: NookPhotoStripLayout.Kind,
        _ theme: NookPhotoStripTheme,
        caption: String
    ) -> NookPhotoStripInput {
        let layout = NookPhotoStripLayout.layout(kind)
        let pictures = (0..<layout.shots).map { shot in
            let camera = PhotoBoothTestPictures.portrait(pose: shot)
            let ready = NookPhotoBoothImaging.prepared(camera, aspect: layout.aspect(ofSlot: shot))!
            return NookPhotoBoothPicture(camera: ready, decorations: nil)
        }
        return NookPhotoStripInput(
            pictures: pictures,
            layout: layout,
            theme: theme,
            caption: caption,
            date: date,
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )
    }

    private static func write(_ name: String, pdf: Data, png: Data) throws {
        guard ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_SNAPSHOTS"] == "1" else { return }
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("output/render/photobooth", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try pdf.write(to: directory.appendingPathComponent("\(name).pdf"))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    /// Draws what the booth lays over the mirror, on a stand-in for the
    /// camera's picture. The mirror itself is never drawn here: it would
    /// start the camera.
    @MainActor
    private static func overlayPNG(_ nook: NookModel, name: String) throws -> Data {
        let size = CGSize(width: 480, height: 270)
        let backdrop = PhotoBoothTestPictures.portrait(pose: 1, width: 960, height: 540)
        let content = Image(decorative: backdrop, scale: 2)
            .resizable()
            .frame(width: size.width, height: size.height)
            .overlay { NookPhotoBoothOverlay(nook: nook) }
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content.environment(\.nookDrawsStill, true))
        renderer.scale = 2
        let image = try #require(renderer.cgImage, "no picture for \(name)")
        let png = try #require(NookPhotoBoothImaging.pngData(image), "no PNG for \(name)")
        if ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_SNAPSHOTS"] == "1" {
            let directory = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("output/render/photobooth", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return png
    }

    @MainActor
    @Test func theOverlayDrawsEachStepOfASession() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NookPhotoBoothRenderTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let nook = NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
        nook.presentRingLight = { _ in }
        let booth = nook.photoBooth
        booth.camera = FakeBoothCamera()
        booth.defaultFolder = folder
        booth.advancesItself = false
        booth.attach(nook: nook)
        booth.play = { _ in }
        booth.useDefaultFolder()
        booth.layoutKind = .classic
        booth.themeID = "gingham"
        booth.caption = ""
        defer { booth.cancel() }

        let idle = try Self.overlayPNG(nook, name: "ui-0-idle")

        nook.isMirrorOn = true
        booth.start()
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        func step(until isThere: (NookPhotoBoothPhase) -> Bool) async {
            var turns = 0
            while let phase = booth.session?.phase, !isThere(phase), booth.result == nil, turns < 400 {
                turns += 1
                now = now.addingTimeInterval(1.3)
                await booth.tick(at: now)
            }
        }
        let ready = try Self.overlayPNG(nook, name: "ui-1-get-ready")
        await step { if case .countdown(1, 3) = $0 { true } else { false } }
        let counting = try Self.overlayPNG(nook, name: "ui-2-countdown")
        await step { $0 == .preview(shot: 1) }
        let looking = try Self.overlayPNG(nook, name: "ui-3-preview")
        await step { $0 == .nextPose(shot: 2) }
        let posing = try Self.overlayPNG(nook, name: "ui-4-next-pose")
        await step { $0 == .done }
        #expect(booth.result != nil)
        let done = try Self.overlayPNG(nook, name: "ui-5-strip")

        // Idle draws nothing, and every step looks different from the last.
        let pictures = [idle, ready, counting, looking, posing, done]
        #expect(Set(pictures).count == pictures.count)
    }

    @Test func everyThemeMakesAStripInEveryLayout() throws {
        for kind in NookPhotoStripLayout.Kind.allCases {
            let layout = NookPhotoStripLayout.layout(kind)
            for theme in NookPhotoStripTheme.all {
                let name = "\(kind.rawValue)-\(theme.id)"
                let input = Self.input(kind, theme, caption: "Friday night")
                let pdf = try #require(NookPhotoStripComposer.pdf(input), "no PDF for \(name)")
                let document = try #require(PDFDocument(data: pdf), "unreadable PDF for \(name)")
                #expect(document.pageCount == 1, "\(name)")
                let box = try #require(document.page(at: 0)).bounds(for: .mediaBox)
                #expect(box.size == layout.pageSize, "\(name)")
                let image = try #require(NookPhotoStripComposer.bitmap(input, scale: 3), "no picture for \(name)")
                let png = try #require(NookPhotoBoothImaging.pngData(image), "no PNG for \(name)")
                try Self.write(name, pdf: pdf, png: png)
            }
        }
    }
}
