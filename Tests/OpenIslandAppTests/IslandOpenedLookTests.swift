import CoreGraphics
import Foundation
import Testing
@testable import OpenIslandApp

/// The opened island's look (D35): the numbers each choice gives, that the
/// standard look is the island as it was, and that everything sized from
/// the look agrees.
struct IslandOpenedLookTests {
    private typealias Metrics = IslandOpenedMetrics

    // MARK: The standard look is the island as it was

    @Test func theStandardLookOnANotchIsTheIslandAsItWas() {
        let metrics = Metrics.resolve(look: .standard, profile: .notch, screenWidth: 1512)
        let width: CGFloat = 540
        let radius: CGFloat = 22
        let inset: CGFloat = 46
        let page: CGFloat = 448

        #expect(metrics.panelWidth == width)
        #expect(metrics.topRadius == radius)
        #expect(metrics.bottomRadius == radius)
        #expect(metrics.sideInset == inset)
        #expect(metrics.headerInset == inset)
        #expect(metrics.pageWidth == page)
    }

    @Test func theStandardLookOnATopBarIsTheIslandAsItWas() {
        let metrics = Metrics.resolve(look: .standard, profile: .topBar, screenWidth: 2560)
        let width: CGFloat = 520
        let radius: CGFloat = 22
        let sideInset: CGFloat = 16
        let headerInset: CGFloat = 18
        let page: CGFloat = 488

        #expect(metrics.panelWidth == width)
        #expect(metrics.bottomRadius == radius)
        #expect(metrics.sideInset == sideInset)
        #expect(metrics.headerInset == headerInset)
        #expect(metrics.pageWidth == page)
    }

    @Test func aDisplayThatPicksNothingGetsTheStandardLook() {
        #expect(NookDisplayPreferences().openedLook == .standard)
        #expect(NookDisplayPreferences.load(for: .notch, defaults: MemoryDefaults()).openedLook == .standard)
        #expect(IslandOpenedLook() == IslandOpenedLook(width: .standard, corners: .soft))
        #expect(NookLayoutEditor.pageWidth(for: .notch) == Metrics.resolve(look: .standard, profile: .notch).pageWidth)
    }

    @Test func withNoScreenTheWidthIsThePreferredOne() {
        // The panel controller asks with no screen before one is found, and
        // has always answered with the top bar's width.
        let width: CGFloat = 520
        #expect(Metrics.resolve(look: .standard, profile: .topBar, screenWidth: nil).panelWidth == width)
    }

    // MARK: Width

    @Test(arguments: [
        (IslandOpenedWidth.standard, CGFloat(540), CGFloat(520)),
        (.wide, 640, 620),
        (.widest, 740, 720),
    ])
    func eachWidthOnARoomyScreen(width: IslandOpenedWidth, notch: CGFloat, topBar: CGFloat) {
        for corners in IslandOpenedCorners.allCases {
            let look = IslandOpenedLook(width: width, corners: corners)
            #expect(Metrics.resolve(look: look, profile: .notch, screenWidth: 1512).panelWidth == notch)
            #expect(Metrics.resolve(look: look, profile: .topBar, screenWidth: 1920).panelWidth == topBar)
        }
    }

    @Test func eachStepUpAddsTheSameWidth() {
        for profile in IslandAppearanceDisplayProfile.allCases {
            let standard = Metrics.preferredWidth(.standard, profile: profile)
            #expect(Metrics.preferredWidth(.wide, profile: profile) - standard == Metrics.widthStep)
            #expect(Metrics.preferredWidth(.widest, profile: profile) - standard == Metrics.widthStep * 2)
        }
    }

    @Test(arguments: IslandOpenedLook.all)
    func aScreenTooNarrowForTheLookCutsItToTheScreen(look: IslandOpenedLook) {
        // 600 points across leaves 568 once the margin is kept.
        let narrow: CGFloat = 600
        let room = narrow - Metrics.screenMargin
        for profile in IslandAppearanceDisplayProfile.allCases {
            let metrics = Metrics.resolve(look: look, profile: profile, screenWidth: narrow)
            let preferred = Metrics.preferredWidth(look.width, profile: profile)
            #expect(metrics.panelWidth == min(preferred, room))
            #expect(metrics.panelWidth <= room)
        }
    }

    @Test(arguments: IslandOpenedLook.all)
    func theWidthNeverGoesUnderTheFloor(look: IslandOpenedLook) {
        for profile in IslandAppearanceDisplayProfile.allCases {
            let metrics = Metrics.resolve(look: look, profile: profile, screenWidth: 320)
            #expect(metrics.panelWidth == Metrics.minimumPanelWidth)
        }
    }

    @Test func aWiderLookIsNeverNarrowerThanANarrowerOne() {
        for screen in [CGFloat(320), 600, 700, 800, 1512, 3840] {
            for profile in IslandAppearanceDisplayProfile.allCases {
                let widths = IslandOpenedWidth.allCases.map {
                    Metrics.resolve(look: IslandOpenedLook(width: $0), profile: profile, screenWidth: screen).panelWidth
                }
                #expect(widths == widths.sorted(), "screen \(screen), \(profile)")
            }
        }
    }

    // MARK: Corners

    @Test func softCornersAreTheShapesOwnRadii() {
        let radii = Metrics.radii(for: .soft)
        #expect(radii.top == NotchShape.openedTopRadius)
        #expect(radii.bottom == NotchShape.openedBottomRadius)
    }

    @Test func squareCornersAreSmallAndKeepALittleFlare() {
        let soft = Metrics.radii(for: .soft)
        let square = Metrics.radii(for: .square)
        let top: CGFloat = 6
        let bottom: CGFloat = 10

        #expect(square.top == top)
        #expect(square.bottom == bottom)
        #expect(square.top < soft.top)
        #expect(square.bottom < soft.bottom)
        // Some flare stays, which is what joins the shape to the top edge.
        #expect(square.top > 0)
    }

    @Test func onANotchTheContentStartsOneBodyPaddingInsideTheFlare() {
        for look in IslandOpenedLook.all {
            let metrics = Metrics.resolve(look: look, profile: .notch)
            #expect(metrics.sideInset == metrics.topRadius + Metrics.notchBodyPadding)
            #expect(metrics.headerInset == metrics.sideInset)
        }
    }

    @Test func onATopBarTheCornersDoNotMoveTheContent() {
        let soft = Metrics.resolve(look: IslandOpenedLook(corners: .soft), profile: .topBar)
        let square = Metrics.resolve(look: IslandOpenedLook(corners: .square), profile: .topBar)
        #expect(soft.sideInset == square.sideInset)
        #expect(soft.pageWidth == square.pageWidth)
        #expect(soft.bottomRadius != square.bottomRadius)
    }

    // MARK: What follows the width

    @Test(arguments: IslandOpenedLook.all)
    func theWindowAndTheClickAreaFollowTheWidth(look: IslandOpenedLook) {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let inset = IslandChromeMetrics.openedShadowHorizontalInset
        let metrics = Metrics.resolve(look: look, profile: .notch, screenWidth: screen.width)

        let window = IslandPanelSizing.windowFrame(
            panelWidth: metrics.panelWidth,
            windowHeight: 400,
            screenFrame: screen,
            horizontalInset: inset
        )
        let shape = IslandPanelSizing.visibleShapeRect(in: window, shapeHeight: 300, horizontalInset: inset)

        // The window is the shape plus the shadow inset on both sides,
        // centered and hanging from the top of the screen.
        #expect(window.width == metrics.panelWidth + inset * 2)
        #expect(window.midX == screen.midX)
        #expect(window.maxY == screen.maxY)
        // The click area is exactly as wide as the shape and sits under it.
        #expect(shape.width == metrics.panelWidth)
        #expect(shape.midX == screen.midX)
        #expect(shape.maxY == screen.maxY)
    }

    @Test func theWindowFrameForTheStandardLookIsTheOneItAlwaysHad() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let window = IslandPanelSizing.windowFrame(
            panelWidth: 540,
            windowHeight: 400,
            screenFrame: screen,
            horizontalInset: 18
        )
        #expect(window == CGRect(x: 468, y: 582, width: 576, height: 400))
    }

    @Test func aChangeOfLookIsNotAHeightOnlyChange() {
        // A width change is applied at once, never through the grow-first
        // and shrink-after steps, which only ever move the bottom edge.
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let standard = IslandPanelSizing.windowFrame(
            panelWidth: Metrics.resolve(look: .standard, profile: .notch).panelWidth,
            windowHeight: 400, screenFrame: screen, horizontalInset: 18
        )
        let wide = IslandPanelSizing.windowFrame(
            panelWidth: Metrics.resolve(look: IslandOpenedLook(width: .wide), profile: .notch).panelWidth,
            windowHeight: 400, screenFrame: screen, horizontalInset: 18
        )
        let taller = IslandPanelSizing.windowFrame(
            panelWidth: Metrics.resolve(look: .standard, profile: .notch).panelWidth,
            windowHeight: 520, screenFrame: screen, horizontalInset: 18
        )

        #expect(!IslandPanelSizing.isHeightOnlyChange(from: standard, to: wide))
        #expect(IslandPanelSizing.isHeightOnlyChange(from: standard, to: taller))
    }

    // MARK: The Nook page

    /// The grid keeps its two columns at every width: the tiles stretch.
    @Test(arguments: [
        (IslandOpenedLook(width: .standard, corners: .soft), CGFloat(448), CGFloat(219)),
        (IslandOpenedLook(width: .wide, corners: .soft), 548, 269),
        (IslandOpenedLook(width: .widest, corners: .soft), 648, 319),
        (IslandOpenedLook(width: .standard, corners: .square), 480, 235),
        (IslandOpenedLook(width: .widest, corners: .square), 680, 335),
    ])
    func theNookPageAndItsColumnsOnANotch(look: IslandOpenedLook, page: CGFloat, column: CGFloat) {
        let metrics = Metrics.resolve(look: look, profile: .notch)
        #expect(metrics.pageWidth == page)
        #expect(NookWidgetLayout.columnWidth(totalWidth: metrics.pageWidth) == column)
        #expect(NookLayoutEditor.pageWidth(for: .notch, look: look) == page)
    }

    @Test func textMeasuredForTheStandardWidthGainsWhatTheLookAdds() {
        let none: CGFloat = 0
        let step: CGFloat = 100
        let cornersOnly: CGFloat = 32

        #expect(Metrics.pageWidthGain(look: .standard, profile: .notch) == none)
        #expect(Metrics.pageWidthGain(look: IslandOpenedLook(width: .wide), profile: .notch) == step)
        #expect(Metrics.pageWidthGain(look: IslandOpenedLook(width: .widest), profile: .topBar) == step * 2)
        // Square corners move the content out on a notch by what the
        // smaller flare frees on both sides.
        #expect(Metrics.pageWidthGain(look: IslandOpenedLook(corners: .square), profile: .notch) == cornersOnly)
        #expect(Metrics.pageWidthGain(look: IslandOpenedLook(corners: .square), profile: .topBar) == none)
        // A screen that clamps both looks to the same width leaves no gain.
        #expect(Metrics.pageWidthGain(look: IslandOpenedLook(width: .widest), profile: .topBar, screenWidth: 500) == none)
    }

    // MARK: The mirror

    @Test func theMirrorGrowsWithThePage() {
        let ratio: CGFloat = 16.0 / 9.0
        let standard = NookMirrorFit.size(
            pageWidth: Metrics.resolve(look: .standard, profile: .notch).pageWidth, aspectRatio: ratio, room: nil
        )
        let widest = NookMirrorFit.size(
            pageWidth: Metrics.resolve(look: IslandOpenedLook(width: .widest), profile: .notch).pageWidth,
            aspectRatio: ratio, room: nil
        )
        let standardHeight: CGFloat = 259
        let widestHeight: CGFloat = 372
        let widestWidth: CGFloat = 648

        #expect(standard.height == standardHeight)
        #expect(standard.height == NookMirrorLayout.height(pageWidth: 448, aspectRatio: ratio))
        #expect(widest.height == widestHeight)
        #expect(widest.width == widestWidth)
    }

    @Test func aMirrorWithRoomIsLeftAtThePagesFullWidth() {
        let size = NookMirrorFit.size(pageWidth: 648, aspectRatio: 16.0 / 9.0, room: 600)
        let width: CGFloat = 648
        let height: CGFloat = 372
        #expect(size == CGSize(width: width, height: height))
    }

    @Test func aMirrorTallerThanItsRoomIsDrawnSmallerAtThePicturesShape() {
        let ratio: CGFloat = 16.0 / 9.0
        let size = NookMirrorFit.size(pageWidth: 648, aspectRatio: ratio, room: 250)
        let height: CGFloat = 250
        let padding = NookMirrorLayout.padding

        #expect(size.height == height)
        #expect(size.width < 648)
        // The picture inside keeps the camera's shape, which is what keeps
        // stickers and frames where they were put.
        let picture = CGSize(width: size.width - padding * 2, height: size.height - padding * 2)
        #expect(abs(picture.width / picture.height - ratio) < 0.01)
    }

    @Test func theMirrorIsNeverCutBelowItsFloor() {
        let size = NookMirrorFit.size(pageWidth: 648, aspectRatio: 16.0 / 9.0, room: 20)
        #expect(size.height == NookMirrorFit.minimumHeight)
    }

    /// The widest look on a short screen: the mirror, the gap under it and
    /// the decoration picker all fit the room the screen leaves, and the
    /// island's content is held to that room.
    @Test func atTheWidestLookTheMirrorAndItsPickerFitAShortScreen() {
        let ratio: CGFloat = 16.0 / 9.0
        let pageWidth = Metrics.resolve(look: IslandOpenedLook(width: .widest), profile: .notch).pageWidth
        // A screen 560 points tall with a 32 point notch.
        let contentRoom = IslandOpenedLayout.nookContentRoom(
            screenMaxY: 560,
            visibleMinY: 0,
            headerHeight: 32,
            bottomPadding: 0,
            shadowBottomInset: IslandChromeMetrics.openedShadowBottomInset
        )
        let natural = NookMirrorLayout.height(pageWidth: pageWidth, aspectRatio: ratio)
        let mirror = NookMirrorFit.size(
            pageWidth: pageWidth,
            aspectRatio: ratio,
            room: NookMirrorFit.room(contentRoom: contentRoom, barsHeight: 0)
        )
        let extras = NookPageExtras(
            mirrorHeight: mirror.height,
            mirrorWidth: mirror.width,
            showsMirrorDecorationPicker: true
        )
        let page = NookPanelView.verticalPadding * 2 + extras.pinnedHeight

        #expect(natural > mirror.height, "this screen is short enough to cut the mirror")
        #expect(page <= contentRoom)
        // Whatever a page asks for, the island stops at the screen.
        let asked = page + 900
        #expect(IslandOpenedLayout.clampedContentHeight(requested: asked, nookRoom: contentRoom) == contentRoom)
    }

    @Test func onAnOrdinaryScreenTheWidestMirrorIsNotCut() {
        let ratio: CGFloat = 16.0 / 9.0
        let pageWidth = Metrics.resolve(look: IslandOpenedLook(width: .widest), profile: .notch).pageWidth
        // A 14 inch MacBook Pro at its default size.
        let contentRoom = IslandOpenedLayout.nookContentRoom(
            screenMaxY: 982,
            visibleMinY: 0,
            headerHeight: 32,
            bottomPadding: 0,
            shadowBottomInset: IslandChromeMetrics.openedShadowBottomInset
        )
        let mirror = NookMirrorFit.size(
            pageWidth: pageWidth,
            aspectRatio: ratio,
            room: NookMirrorFit.room(contentRoom: contentRoom, barsHeight: 44)
        )
        #expect(mirror.width == pageWidth)
        #expect(mirror.height == NookMirrorLayout.height(pageWidth: pageWidth, aspectRatio: ratio))
    }

    // MARK: Saving

    @Test func aLookIsSavedAndComesBack() {
        let defaults = MemoryDefaults()
        var preferences = NookDisplayPreferences()
        preferences.openedLook = IslandOpenedLook(width: .widest, corners: .square)

        preferences.persist(for: .notch, defaults: defaults)

        #expect(NookDisplayPreferences.load(for: .notch, defaults: defaults).openedLook == preferences.openedLook)
        // The other display keeps its own.
        #expect(NookDisplayPreferences.load(for: .topBar, defaults: defaults).openedLook == .standard)
    }

    @Test func changingTheWidthWritesOneKey() {
        let defaults = MemoryDefaults()
        let old = NookDisplayPreferences()
        var new = old
        new.openedLook.width = .wide

        new.persistChanges(from: old, for: .notch, defaults: defaults)

        #expect(Set(defaults.all.keys) == ["nook.display.notch.openedWidth"])
        #expect(defaults.string(forKey: "nook.display.notch.openedWidth") == "wide")
    }

    @Test func changingTheCornersWritesOneKey() {
        let defaults = MemoryDefaults()
        let old = NookDisplayPreferences()
        var new = old
        new.openedLook.corners = .square

        new.persistChanges(from: old, for: .topBar, defaults: defaults)

        #expect(Set(defaults.all.keys) == ["nook.display.topBar.openedCorners"])
        #expect(defaults.string(forKey: "nook.display.topBar.openedCorners") == "square")
    }

    @Test func aSaveThatChangesNothingWritesNothing() {
        let defaults = MemoryDefaults()
        var preferences = NookDisplayPreferences()
        preferences.openedLook = IslandOpenedLook(width: .wide, corners: .square)

        preferences.persistChanges(from: preferences, for: .notch, defaults: defaults)

        #expect(defaults.all.isEmpty)
    }

    @Test func aSavedValueThisBuildDoesNotKnowFallsBackToTheStandardLook() {
        let defaults = MemoryDefaults()
        defaults.set("enormous", forKey: "nook.display.notch.openedWidth")
        defaults.set(7, forKey: "nook.display.notch.openedCorners")

        #expect(NookDisplayPreferences.load(for: .notch, defaults: defaults).openedLook == .standard)
    }

    // MARK: Templates

    @Test(arguments: PersonalizationTemplate.all)
    func aTemplateLeavesTheLookAlone(template: PersonalizationTemplate) {
        var current = NookDisplayPreferences()
        current.openedLook = IslandOpenedLook(width: .widest, corners: .square)

        let applied = template.applying(to: current)

        #expect(applied.openedLook == current.openedLook)
        // The look is not part of what makes a display "on" a template.
        #expect(template.matches(appearance: template.appearance, nook: applied))
    }

    @Test func undoingATemplateKeepsALookChosenWhileOnIt() {
        let template = PersonalizationTemplate.planner
        let before = PersonalizationSetup(appearance: IslandAppearancePreferences(), nook: NookDisplayPreferences())
        var onTemplate = PersonalizationSetup(
            appearance: template.appearance,
            nook: template.applying(to: before.nook)
        )
        onTemplate.nook.openedLook = IslandOpenedLook(width: .wide, corners: .square)

        let undone = onTemplate.undoing(before)

        #expect(undone.nook.openedLook == onTemplate.nook.openedLook)
    }

    // MARK: The Settings previews

    @Test func theAgentsPreviewTriesTheWidthsItAlwaysDidAtTheStandardLook() {
        let notch: [CGFloat] = [540, 500, 460]
        let topBar: [CGFloat] = [520, 500, 460]
        #expect(SessionListPanelPreview.panelWidths(for: 540) == notch)
        #expect(SessionListPanelPreview.panelWidths(for: 520) == topBar)
    }

    @Test func aWiderPreviewFallsBackThroughNarrowerWidthsInOrder() {
        for preferred in [CGFloat(620), 640, 720, 740] {
            let widths = SessionListPanelPreview.panelWidths(for: preferred)
            #expect(widths.first == preferred)
            #expect(widths == widths.sorted(by: >), "widest first")
            #expect(Set(widths).count == widths.count)
            #expect(widths.last == 460)
        }
    }

    @Test func theCardPictureDrawsAWiderShapeForAWiderLook() {
        let box = CGSize(width: 120, height: 56)
        for profile in IslandAppearanceDisplayProfile.allCases {
            let widths = IslandOpenedWidth.allCases.map {
                OpenedLookArtLayout.shapeSize(look: IslandOpenedLook(width: $0), profile: profile, in: box).width
            }
            #expect(widths == widths.sorted())
            #expect(Set(widths).count == widths.count)
            #expect(widths.allSatisfy { $0 <= box.width })
        }
    }
}

/// The live glue: the panel controller and the app model read the look the
/// display has saved and size from it. Nothing here writes a setting.
@MainActor
struct IslandOpenedLookAppTests {
    private static func makeModel() -> AppModel {
        let model = AppModel()
        model.nook.presentRingLight = { _ in }
        return model
    }

    @Test func thePanelControllerSizesTheWindowFromTheDisplaysLook() {
        let model = Self.makeModel()
        let controller = OverlayPanelController()
        controller.model = model
        // With no screen the controller answers for a top bar.
        let look = model.nook.displayPreferences(for: .topBar).openedLook

        let metrics = controller.openedMetrics(for: nil)

        #expect(metrics == IslandOpenedMetrics.resolve(look: look, profile: .topBar))
        #expect(controller.openedPanelWidth(for: nil) == metrics.panelWidth)
    }

    @Test func aControllerWithNoModelUsesTheStandardLook() {
        let controller = OverlayPanelController()
        #expect(controller.openedMetrics(for: nil) == IslandOpenedMetrics.resolve(look: .standard, profile: .topBar))
    }

    @Test func theAppModelsMetricsAreTheActiveDisplaysLook() {
        let model = Self.makeModel()
        let profile = model.activeAppearanceProfile
        let look = model.nook.displayPreferences(for: profile).openedLook

        let metrics = model.islandOpenedMetrics
        let unclamped = IslandOpenedMetrics.resolve(look: look, profile: profile)

        // Radii and insets never depend on the screen. The width can only
        // be cut by it.
        #expect(metrics.topRadius == unclamped.topRadius)
        #expect(metrics.bottomRadius == unclamped.bottomRadius)
        #expect(metrics.sideInset == unclamped.sideInset)
        #expect(metrics.panelWidth <= unclamped.panelWidth)
    }

    @Test func withTheMirrorOffThePageNamesNoMirror() {
        let model = Self.makeModel()
        #expect(model.nookMirrorSize == nil)
        #expect(model.nookPageExtras.mirrorHeight == nil)
        #expect(model.nookPageExtras.mirrorWidth == nil)
    }
}
