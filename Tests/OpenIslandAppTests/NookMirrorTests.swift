import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// The mirror is on demand: its tile is a switch, and the camera view shows
/// above the widgets only while it is turned on.
@Suite struct NookMirrorTests {
    private static func place(_ kind: NookWidgetKind, _ size: NookWidgetSize) -> NookWidgetPlacement {
        NookWidgetPlacement(kind: kind, size: size)
    }

    // MARK: When the mirror shows

    @Test func theMirrorShowsOnlyWhileItIsOnAndItsTileIsOnThePage() {
        let withTile = [Self.place(.media, .medium), Self.place(.mirror, .small)]
        let withoutTile = [Self.place(.media, .medium)]

        #expect(!NookMirrorLayout.isShown(isOn: false, placements: withTile))
        #expect(!NookMirrorLayout.isShown(isOn: true, placements: withoutTile))
        #expect(NookMirrorLayout.isShown(isOn: true, placements: withTile))
    }

    // MARK: The whole picture

    @Test func theMirrorIsAsTallAsTheWholeCameraPictureAtThePagesWidth() {
        // 448pt page on the MacBook notch: a 432pt picture at 16 by 9 is
        // 243pt, plus 8pt of card above and below.
        let wide: CGFloat = 259
        // A 4 by 3 camera needs more height for the same width: 324 plus 16.
        let tall: CGFloat = 340
        #expect(NookMirrorLayout.height(pageWidth: 448, aspectRatio: 16.0 / 9.0) == wide)
        #expect(NookMirrorLayout.height(pageWidth: 448, aspectRatio: 4.0 / 3.0) == tall)
        // A wider page gives a taller mirror.
        #expect(
            NookMirrorLayout.height(pageWidth: 488, aspectRatio: 16.0 / 9.0)
                > NookMirrorLayout.height(pageWidth: 448, aspectRatio: 16.0 / 9.0)
        )
    }

    @Test func aCameraFormatGivesItsShapeAndNonsenseGivesTheDefault() {
        let sixteenByNine: CGFloat = 16.0 / 9.0
        let fourByThree: CGFloat = 4.0 / 3.0
        #expect(NookMirrorLayout.aspectRatio(width: 1920, height: 1080) == sixteenByNine)
        #expect(NookMirrorLayout.aspectRatio(width: 1280, height: 960) == fourByThree)
        #expect(NookMirrorLayout.aspectRatio(width: 0, height: 1080) == NookMirrorLayout.defaultAspectRatio)
        #expect(NookMirrorLayout.aspectRatio(width: 1080, height: 1920) == NookMirrorLayout.defaultAspectRatio)
        #expect(NookMirrorLayout.aspectRatio(width: 9000, height: 100) == NookMirrorLayout.defaultAspectRatio)
    }

    // MARK: Page height

    @Test @MainActor func theMirrorAddsItsHeightAndOneRowGapToThePage() {
        let placements = [Self.place(.mirror, .medium), Self.place(.todo, .medium)]
        let off = NookPanelView.preferredHeight(for: placements, calendarStyle: .strip, isEditing: false)
        let on = NookPanelView.preferredHeight(
            for: placements, calendarStyle: .strip, isEditing: false, extras: NookPageExtras(mirrorHeight: 259)
        )

        #expect(on - off == 259 + NookWidgetLayout.rowSpacing)
    }

    @Test @MainActor func theTileIsAShortSwitchAtEverySize() {
        // Opening the Nook must not cost a camera-sized card for a button.
        let mirror = NookMirrorLayout.height(pageWidth: 448, aspectRatio: NookMirrorLayout.defaultAspectRatio)
        for size in NookWidgetSize.allCases {
            #expect(NookMirrorCard.height(for: size) < mirror, "\(size)")
        }
        #expect(NookMirrorCard.height(for: .small) == NookWidgetLayout.smallHeight)
    }

    // MARK: Turning off

    @Test func aPageLosingTheTileIsNoticed() {
        let withTile = [Self.place(.media, .medium), Self.place(.mirror, .small)]
        let withoutTile = [Self.place(.media, .medium)]

        #expect(NookMirrorLayout.losesTile(from: withTile, to: withoutTile))
        #expect(!NookMirrorLayout.losesTile(from: withTile, to: withTile))
        #expect(!NookMirrorLayout.losesTile(from: withoutTile, to: withTile))
        #expect(!NookMirrorLayout.losesTile(from: withoutTile, to: withoutTile))
    }

    @Test func hidingTheTileOnOneDisplayCountsEvenWhileAnotherKeepsIt() {
        // The Nook tab switch puts the tile on both displays. Removing it
        // from one must turn the mirror off, which is the page-level rule.
        var display = NookDisplayPreferences()
        let enabled = NookWidgetKind.allCases
        let before = display.placements(enabled: enabled)
        display.hiddenWidgets.insert(.mirror)
        let after = display.placements(enabled: enabled)

        #expect(NookMirrorLayout.losesTile(from: before, to: after))
    }

    @Test @MainActor func theMirrorStartsOff() {
        #expect(NookModel().isMirrorOn == false)
    }

    @Test @MainActor func turningTheMirrorOnOrOffResizesTheIsland() {
        let nook = NookModel()
        var resizeCount = 0
        nook.onDisplayPreferencesChanged = { resizeCount += 1 }

        nook.isMirrorOn = true
        nook.isMirrorOn = true
        nook.isMirrorOn = false

        #expect(resizeCount == 2)
    }

    @Test @MainActor func onlyAMirrorOnThePageHoldsTheIslandOpenAndClosingTheIslandTurnsItOff() {
        let model = AppModel()
        // Nothing in this test may light the real screen.
        model.nook.presentRingLight = { _ in }
        model.nook.pageOverride = .nook
        model.notchStatus = .opened
        model.notchOpenReason = .hover

        #expect(model.overlay.shouldAutoCollapseOnMouseLeave)

        // The flag alone holds nothing: only a mirror on the page does, and
        // this page has no Mirror tile.
        model.nook.isMirrorOn = true
        #expect(model.nookMirrorHeight == nil)
        #expect(model.overlay.shouldAutoCollapseOnMouseLeave)

        model.notchClose()
        #expect(model.nook.isMirrorOn == false)
    }

    @Test @MainActor func leavingTheNookPageTurnsTheMirrorOff() {
        let model = AppModel()
        model.nook.presentRingLight = { _ in }
        model.nook.pageOverride = .nook
        model.nook.isMirrorOn = true

        model.showAgentsPage()

        #expect(model.nook.isMirrorOn == false)
    }

    // MARK: Ring light

    @Test @MainActor func theRingLightShowsOnlyWhileTheMirrorIsOn() {
        let nook = NookModel()
        let wasOn = nook.isRingLightOn
        defer { nook.isRingLightOn = wasOn }
        var shown: [Bool] = []
        nook.presentRingLight = { shown.append($0) }
        nook.isRingLightOn = false
        shown.removeAll()

        nook.isRingLightOn = true   // mirror off: the choice is kept, nothing lights
        nook.isMirrorOn = true      // the light comes on with the mirror
        nook.isRingLightOn = false  // the bulb turns it off
        nook.isRingLightOn = true   // and on again
        nook.isMirrorOn = false     // the mirror takes the light with it

        #expect(shown == [false, true, false, true, false])
    }

    @Test func theRingLightBandScalesWithTheScreenWithinLimits() {
        let laptop = NookRingLightLayout.thickness(for: CGSize(width: 1512, height: 982))
        let small = NookRingLightLayout.thickness(for: CGSize(width: 800, height: 500))
        let huge = NookRingLightLayout.thickness(for: CGSize(width: 5120, height: 2880))

        #expect(abs(laptop - 98.2) < 0.001)
        #expect(small == NookRingLightLayout.minThickness)
        #expect(huge == NookRingLightLayout.maxThickness)
    }

    @Test func theRingLightCoversTheEdgesAndLeavesTheMiddleClear() {
        let rect = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let band = NookRingLightLayout.path(in: rect, thickness: 100).cgPath
        func isLit(_ x: CGFloat, _ y: CGFloat) -> Bool {
            band.contains(CGPoint(x: x, y: y), using: .evenOdd)
        }

        #expect(isLit(10, 10))
        #expect(isLit(756, 50))
        #expect(isLit(1500, 491))
        // Just inside the hole's corner the rounding keeps the light on.
        #expect(isLit(104, 104))
        #expect(!isLit(756, 491))
        #expect(!isLit(756, 110))
    }

    @Test func aBandWiderThanTheScreenLightsAllOfIt() {
        let rect = CGRect(x: 0, y: 0, width: 120, height: 80)
        let band = NookRingLightLayout.path(in: rect, thickness: 64).cgPath

        #expect(band.contains(CGPoint(x: 60, y: 40), using: .evenOdd))
    }

    @Test @MainActor func theRingLightDrawsABandWithAClearMiddle() throws {
        let size = CGSize(width: 756, height: 491)
        let png = try render("ring-light", size: size) {
            NookRingLightView(thickness: NookRingLightLayout.thickness(for: size))
        }
        let image = try #require(NSBitmapImageRep(data: png))
        let edge = try #require(image.colorAt(x: 20, y: 20))
        let middle = try #require(image.colorAt(x: image.pixelsWide / 2, y: image.pixelsHigh / 2))

        // The test renders on black: the band is bright, the middle stays dark.
        #expect(edge.brightnessComponent > 0.9)
        #expect(middle.brightnessComponent < 0.1)
    }

    // MARK: Tile

    @Test @MainActor func theTileRendersOffAndOnAtEverySize() throws {
        let nook = NookModel()
        for size in NookWidgetSize.allCases {
            let width: CGFloat = size == .small ? 219 : 448
            let frame = CGSize(width: width, height: NookMirrorCard.height(for: size))

            nook.isMirrorOn = false
            let off = try render("mirror-tile-\(size.rawValue)-off", size: frame) {
                NookMirrorCard(nook: nook).environment(\.nookWidgetSize, size)
            }
            nook.isMirrorOn = true
            let on = try render("mirror-tile-\(size.rawValue)-on", size: frame) {
                NookMirrorCard(nook: nook).environment(\.nookWidgetSize, size)
            }

            #expect(off != on, "\(size): the tile should say whether the mirror is on")
        }
    }

    // MARK: Rendering

    private static let scale: CGFloat = 2

    /// Renders on black at a fixed size. `OPEN_ISLAND_RENDER_SNAPSHOTS=1`
    /// also writes the PNG to `output/render/`.
    @MainActor
    private func render<Content: View>(
        _ name: String,
        size: CGSize,
        @ViewBuilder content: () -> Content
    ) throws -> Data {
        let framed = content()
            .frame(width: size.width, height: size.height)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: framed.environment(\.nookDrawsStill, true))
        renderer.scale = Self.scale
        let image = try #require(renderer.cgImage, "no image for \(name)")
        let png = try #require(
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
            "PNG encoding failed for \(name)"
        )
        if ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_SNAPSHOTS"] == "1" {
            let directory = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("output/render", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return png
    }
}
