import CoreGraphics
import Foundation
import Testing
@testable import OpenIslandApp

/// The small pictures Settings shows for each layout and theme. These draw
/// strips and take their turn with the other tests that do.
@Suite(.serialized, .oneStripAtATime)
struct NookPhotoBoothPreviewTests {
    private static func key(
        _ kind: NookPhotoStripLayout.Kind,
        _ themeID: String,
        typed: String = "",
        line: String = "PHOTO BOOTH"
    ) -> NookPhotoBoothPreviewKey {
        NookPhotoBoothPreviewKey(layout: kind, theme: .theme(id: themeID), typedCaption: typed, defaultLine: line)
    }

    /// How many different colors a picture holds, told apart to the nearest
    /// sixteenth of a channel. A blank picture holds one.
    private static func distinctColors(_ image: CGImage) -> Int {
        guard let context = NookPhotoBoothImaging.bitmapContext(width: image.width, height: image.height),
              let data = context.data else {
            return 0
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * image.height)
        var seen = Set<UInt32>()
        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = y * context.bytesPerRow + x * 4
                seen.insert(UInt32(bytes[offset] >> 4) << 8 | UInt32(bytes[offset + 1] >> 4) << 4 | UInt32(bytes[offset + 2] >> 4))
            }
        }
        return seen.count
    }

    // MARK: Drawing

    @Test func everyLayoutInEveryThemeGivesAPreviewInTheLayoutsProportions() async throws {
        for kind in NookPhotoStripLayout.Kind.allCases {
            let page = NookPhotoStripLayout.layout(kind).pageSize
            for theme in NookPhotoStripTheme.all {
                let name = "\(kind.rawValue)-\(theme.id)"
                let image = try #require(
                    await NookPhotoBoothPreviewDrawing.image(for: Self.key(kind, theme.id, typed: "Friday night")),
                    "no preview for \(name)"
                ).image
                #expect(max(image.width, image.height) == 220, "\(name) is \(image.width) by \(image.height)")
                let shape = CGFloat(image.width) / CGFloat(image.height)
                #expect(abs(shape - page.width / page.height) < 0.01, "\(name) has the wrong proportions")
                #expect(Self.distinctColors(image) >= 12, "\(name) looks blank")
            }
        }
    }

    @Test func aPreviewShowsAtTheSizeItWasDrawnFor() async throws {
        for kind in NookPhotoStripLayout.Kind.allCases {
            let image = try #require(await NookPhotoBoothPreviewDrawing.image(for: Self.key(kind, "classic"))).image
            let size = NookPhotoBoothPreviewDrawing.pointSize(of: kind)
            #expect(size.width * NookPhotoBoothPreviewDrawing.pixelsPerPoint == CGFloat(image.width), "\(kind.rawValue)")
            #expect(size.height * NookPhotoBoothPreviewDrawing.pixelsPerPoint == CGFloat(image.height), "\(kind.rawValue)")
        }
        #expect(NookPhotoBoothPreviewDrawing.pointSize(of: .classic) == CGSize(width: 36.5, height: 110))
        #expect(NookPhotoBoothPreviewDrawing.pointSize(of: .grid) == CGSize(width: 110, height: 73.5))
    }

    @Test func theSameKeyAlwaysGivesTheSamePicture() async throws {
        let key = Self.key(.grid, "gingham", typed: "Friday night")
        let first = try #require(await NookPhotoBoothPreviewDrawing.image(for: key)).image
        let second = try #require(await NookPhotoBoothPreviewDrawing.image(for: key)).image
        #expect(NookPhotoBoothImaging.pngData(first) == NookPhotoBoothImaging.pngData(second))
    }

    @Test func theThemeAndTheLayoutChangeThePicture() async throws {
        func png(_ key: NookPhotoBoothPreviewKey) async throws -> Data? {
            NookPhotoBoothImaging.pngData(try #require(await NookPhotoBoothPreviewDrawing.image(for: key)).image)
        }
        let base = try await png(Self.key(.classic, "classic"))
        #expect(try await png(Self.key(.classic, "gingham")) != base)
        #expect(try await png(Self.key(.caption, "classic")) != base)
    }

    @Test func theCaptionIsPrintedOnThePreview() async throws {
        func png(_ typed: String) async throws -> Data? {
            let made = try #require(await NookPhotoBoothPreviewDrawing.image(for: Self.key(.caption, "paperWhite", typed: typed)))
            return NookPhotoBoothImaging.pngData(made.image)
        }
        #expect(try await png("Friday night") != png("Sunday brunch"))
        // This theme prints in lower case, and the default line is "PHOTO BOOTH".
        #expect(try await png("") == png("Photo Booth"), "the theme's own line prints when nothing is typed")
    }

    // MARK: The key

    @Test func anEmptyCaptionAndTheThemesOwnLineShareAKey() {
        let empty = Self.key(.classic, "classic", typed: "", line: "Photo booth")
        // The classic theme prints in capitals, and all three print the same.
        let typed = Self.key(.classic, "classic", typed: "PHOTO BOOTH", line: "something else")
        let lower = Self.key(.classic, "classic", typed: "photo booth", line: "something else")
        #expect(empty == typed)
        #expect(empty == lower)
        #expect(empty.caption == "PHOTO BOOTH")
        #expect(Set([empty, typed, lower]).count == 1)
    }

    @Test func aCaptionThatPrintsNothingFallsBackToTheThemesLine() {
        let line = Self.key(.classic, "classic", typed: "", line: "Photo booth")
        #expect(Self.key(.classic, "classic", typed: "   ", line: "Photo booth") == line)
        #expect(Self.key(.classic, "classic", typed: "\n", line: "Photo booth") == line)
    }

    @Test func aCaptionKeysByWhatPrintsNotByWhatWasTyped() {
        // Line breaks and spaces at the ends do not print.
        let plain = Self.key(.classic, "gingham", typed: "best day")
        #expect(Self.key(.classic, "gingham", typed: "  best day ") == plain)
        #expect(Self.key(.classic, "gingham", typed: "best\nday") == plain)
        #expect(Self.key(.classic, "gingham", typed: "best day").caption == "best day")
        #expect(Self.key(.classic, "gingham", typed: "best\nday").caption == "best day")
        // What passes the length the strip prints is not part of the key.
        let long = String(repeating: "a", count: NookPhotoStripComposer.maxCaptionLength)
        #expect(Self.key(.classic, "gingham", typed: long + "zzz") == Self.key(.classic, "gingham", typed: long))
    }

    @Test func keysThatPrintDifferentlyAreDifferent() {
        let base = Self.key(.classic, "gingham", typed: "best day")
        #expect(Self.key(.grid, "gingham", typed: "best day") != base)
        #expect(Self.key(.classic, "film", typed: "best day") != base)
        #expect(Self.key(.classic, "gingham", typed: "worst day") != base)
    }
}
