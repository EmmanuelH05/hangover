import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import OpenIslandApp

/// The floating panel rules that need no window: how many, where, how
/// large, and the zoom and fit math.
@Suite struct NookDesignPanelRulesTests {
    private typealias Rules = NookDesignPanelRules

    private static let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)

    private func near(_ a: CGFloat, _ b: CGFloat, within tolerance: CGFloat = 0.0001) -> Bool {
        abs(a - b) <= tolerance
    }

    // MARK: How many

    @Test func theFirstPanelOpensInTheFirstSlot() {
        #expect(Rules.decision(for: UUID(), open: [:]) == .open(slot: 0))
    }

    @Test func aPictureThatIsAlreadyFloatingIsBroughtForward() {
        let id = UUID()
        #expect(Rules.decision(for: id, open: [id: 0, UUID(): 1]) == .focus)
    }

    @Test func noMorePanelsOpenThanTheCap() {
        let maxPanels = 6
        #expect(Rules.maxOpenPanels == maxPanels)
        var open: [UUID: Int] = [:]
        for expected in 0..<Rules.maxOpenPanels {
            let id = UUID()
            #expect(Rules.decision(for: id, open: open) == .open(slot: expected))
            open[id] = expected
        }
        #expect(Rules.decision(for: UUID(), open: open) == .refuse)
        // One that is already up can still be brought forward at the cap.
        for existing in open.keys {
            #expect(Rules.decision(for: existing, open: open) == .focus)
        }
    }

    @Test func aClosedPanelsSlotIsUsedAgain() {
        let ids = (0..<4).map { _ in UUID() }
        var open = Dictionary(uniqueKeysWithValues: zip(ids, 0..<4))
        open[ids[1]] = nil

        #expect(Rules.decision(for: UUID(), open: open) == .open(slot: 1))
        #expect(Rules.lowestFreeSlot([0, 1, 2]) == 3)
        #expect(Rules.lowestFreeSlot([1, 2]) == 0)
        #expect(Rules.lowestFreeSlot([Int]()) == 0)
    }

    // MARK: Shape

    @Test func thePictureAreaTakesThePicturesShapeWithinLimits() {
        let landscape: CGFloat = 1.5
        let low: CGFloat = 0.5
        let high: CGFloat = 2.4
        #expect(Rules.areaAspect(forPictureAspect: 1.5) == landscape)
        #expect(Rules.areaAspect(forPictureAspect: 0.1) == low)
        #expect(Rules.areaAspect(forPictureAspect: 12) == high)
        #expect(Rules.areaAspect(forPictureAspect: 0) == 1)
        #expect(Rules.areaAspect(forPictureAspect: .nan) == 1)
    }

    @Test func aPictureInRangeFillsItsAreaAndOneOutsideIsFittedInside() {
        // A panel in the picture's own shape: the picture fills its area.
        let landscape = Rules.panelSize(width: 300, pictureAspect: 1.5)
        #expect(Rules.fittedFraction(pictureAspect: 1.5, panelSize: landscape) == CGSize(width: 1, height: 1))
        // A panorama twice as wide as the widest area covers half its height.
        let panorama = Rules.panelSize(width: 480, pictureAspect: 4.8)
        #expect(Rules.fittedFraction(pictureAspect: 4.8, panelSize: panorama) == CGSize(width: 1, height: 0.5))
        // A long page a fifth as wide as the narrowest area covers a fifth of its width.
        let page = Rules.fittedFraction(pictureAspect: 0.1, panelSize: Rules.panelSize(width: 300, pictureAspect: 0.1))
        #expect(near(page.width, 0.2))
        #expect(page.height == 1)
    }

    @Test func aPanelIsItsPictureAreaPlusTheStripOfControls() {
        let size = Rules.panelSize(width: 300, pictureAspect: 1.5)
        let expected = CGSize(width: 300, height: 200 + Rules.barHeight)
        #expect(size == expected)
        let width: CGFloat = 300
        #expect(Rules.panelWidth(height: size.height, pictureAspect: 1.5) == width)
    }

    @Test func aNewPanelStartsAtASensibleSize() {
        let room = CGSize(width: 1400, height: 880)
        let landscape = Rules.initialSize(pictureAspect: 2, available: room)
        #expect(landscape == CGSize(width: 360, height: 180 + Rules.barHeight))

        // A tall picture's long side is its height. It is no narrower than
        // the strip of controls needs.
        let tall = Rules.initialSize(pictureAspect: 0.5, available: room)
        #expect(tall == CGSize(width: Rules.minimumWidth, height: Rules.minimumWidth * 2 + Rules.barHeight))

        let square = Rules.initialSize(pictureAspect: 1, available: room)
        #expect(square == CGSize(width: 360, height: 360 + Rules.barHeight))
    }

    @Test func aNewPanelNeverOutgrowsASmallScreen() {
        let room = CGSize(width: 320, height: 300)
        let size = Rules.initialSize(pictureAspect: 1, available: room)

        #expect(size.height <= room.height)
        #expect(size.width <= room.width)
        #expect(size.width == size.height - Rules.barHeight)
    }

    // MARK: Free resize

    private let room = CGSize(width: 2000, height: 1200)

    @Test func aWideDragGivesTheWidthAndLeavesTheHeight() {
        let size = Rules.resizedSize(proposed: CGSize(width: 700, height: 330), available: room)
        #expect(size == CGSize(width: 700, height: 330))
    }

    @Test func aTallDragGivesTheHeightAndLeavesTheWidth() {
        let size = Rules.resizedSize(proposed: CGSize(width: 400, height: 900), available: room)
        #expect(size == CGSize(width: 400, height: 900))
    }

    @Test func aCornerDragGivesBothSidesWhateverTheShape() {
        // Neither side follows the other, and the picture's shape is not asked.
        let size = Rules.resizedSize(proposed: CGSize(width: 520, height: 410), available: room)
        #expect(size == CGSize(width: 520, height: 410))
    }

    @Test func aDragIsRoundedToWholePoints() {
        let size = Rules.resizedSize(proposed: CGSize(width: 400.4, height: 300.6), available: room)
        #expect(size == CGSize(width: 400, height: 301))
    }

    @Test func resizingStopsAtTheMinimums() {
        let strip: CGFloat = 240
        let height: CGFloat = 120 + Rules.barHeight
        #expect(Rules.minimumWidth == strip)
        #expect(Rules.minimumHeight == height)

        let tiny = Rules.resizedSize(proposed: CGSize(width: 10, height: 10), available: room)
        #expect(tiny == CGSize(width: strip, height: height))
        // Each side stops on its own.
        #expect(Rules.resizedSize(proposed: CGSize(width: 100, height: 600), available: room) == CGSize(width: strip, height: 600))
        #expect(Rules.resizedSize(proposed: CGSize(width: 600, height: 20), available: room) == CGSize(width: 600, height: height))
    }

    @Test func resizingStopsAtTheScreen() {
        let screen = CGSize(width: 800, height: 600)
        #expect(Rules.resizedSize(proposed: CGSize(width: 5000, height: 5000), available: screen) == screen)
        #expect(Rules.resizedSize(proposed: CGSize(width: 5000, height: 300), available: screen) == CGSize(width: 800, height: 300))
        #expect(Rules.resizedSize(proposed: CGSize(width: 300, height: 5000), available: screen) == CGSize(width: 300, height: 600))
    }

    @Test func theMinimumWinsOnAScreenSmallerThanIt() {
        let size = Rules.resizedSize(proposed: CGSize(width: 500, height: 500), available: CGSize(width: 200, height: 100))
        #expect(size == CGSize(width: Rules.minimumWidth, height: Rules.minimumHeight))
    }

    @Test func aSizeThatIsNotARealNumberNeverReachesTheWindow() {
        let nothing = Rules.resizedSize(proposed: CGSize(width: CGFloat.nan, height: CGFloat.nan), available: room)
        #expect(nothing == CGSize(width: Rules.minimumWidth, height: Rules.minimumHeight))
        // Without end is as large as the screen allows.
        let endless = Rules.resizedSize(proposed: CGSize(width: CGFloat.infinity, height: CGFloat.infinity), available: room)
        #expect(endless == room)
    }

    // MARK: Opening at a remembered size

    @Test func aPanelWithNothingRememberedOpensAtTheInitialSize() {
        let screen = CGSize(width: 1400, height: 880)
        #expect(
            Rules.openingSize(remembered: nil, pictureAspect: 2, available: screen)
                == Rules.initialSize(pictureAspect: 2, available: screen)
        )
    }

    @Test func aRememberedSizeIsKeptAsItIsWhateverTheShape() {
        let screen = CGSize(width: 1400, height: 880)
        let size = Rules.openingSize(remembered: CGSize(width: 640, height: 250), pictureAspect: 2, available: screen)
        #expect(size == CGSize(width: 640, height: 250))
    }

    @Test func aRememberedSizeLargerThanTheScreenIsClamped() {
        let small = CGSize(width: 700, height: 500)
        let size = Rules.openingSize(remembered: CGSize(width: 1800, height: 1100), pictureAspect: 2, available: small)
        #expect(size == small)
    }

    @Test func aRememberedSizeThatCannotBeUsedFallsBackToTheInitialSize() {
        let screen = CGSize(width: 1400, height: 880)
        let initial = Rules.initialSize(pictureAspect: 1, available: screen)
        for bad in [CGSize.zero, CGSize(width: -5, height: 300), CGSize(width: 300, height: CGFloat.nan), CGSize(width: CGFloat.infinity, height: 300)] {
            #expect(Rules.openingSize(remembered: bad, pictureAspect: 1, available: screen) == initial, "\(bad)")
        }
    }

    // MARK: Back to the picture's shape

    @Test func goingBackToThePicturesShapeKeepsTheWidth() {
        let size = Rules.matchedSize(current: CGSize(width: 500, height: 700), pictureAspect: 2, available: room)
        #expect(size == CGSize(width: 500, height: 250 + Rules.barHeight))
    }

    @Test func goingBackNeverOutgrowsTheScreenOrShrinksPastTheMinimums() {
        // A tall picture at a wide panel is narrowed until it fits the screen's height.
        let tall = Rules.matchedSize(
            current: CGSize(width: 900, height: 300), pictureAspect: 0.5, available: CGSize(width: 1000, height: 800)
        )
        #expect(tall == CGSize(width: 385, height: 800))

        let narrow = Rules.matchedSize(current: CGSize(width: 100, height: 300), pictureAspect: 1, available: room)
        #expect(narrow == CGSize(width: Rules.minimumWidth, height: Rules.minimumWidth + Rules.barHeight))

        // A panorama at the narrowest panel would be shorter than the minimum.
        let panorama = Rules.matchedSize(current: CGSize(width: 240, height: 400), pictureAspect: 4, available: room)
        #expect(panorama == CGSize(width: Rules.minimumWidth, height: Rules.minimumHeight))
    }

    @Test func goingBackToALongPagesShapeStaysWithinTheShapeLimits() {
        let size = Rules.matchedSize(current: CGSize(width: 300, height: 300), pictureAspect: 0.1, available: room)
        #expect(size == CGSize(width: 300, height: 600 + Rules.barHeight))
    }

    @Test func aPanelSentBackToItsShapeKeepsItsTopLeftCorner() {
        // AppKit counts from the bottom left: this panel's top edge is at 900.
        let frame = CGRect(x: 100, y: 200, width: 500, height: 700)
        let size = CGSize(width: 500, height: 280)
        let moved = Rules.frame(keepingTopLeftOf: frame, resizedTo: size, in: Self.screen)
        #expect(moved == CGRect(x: 100, y: 620, width: 500, height: 280))
        #expect(moved.maxY == frame.maxY)
    }

    @Test func aPanelThatGrowsPastTheScreenIsMovedBackByTheOverflowOnly() {
        // Growing down past the bottom edge moves it up until its bottom is on the screen.
        let low = CGRect(x: 100, y: 40, width: 300, height: 200)
        let taller = Rules.frame(keepingTopLeftOf: low, resizedTo: CGSize(width: 300, height: 400), in: Self.screen)
        #expect(taller == CGRect(x: 100, y: 0, width: 300, height: 400))

        // Growing right past the right edge moves it left until its right side is on the screen.
        let right = CGRect(x: 1300, y: 500, width: 200, height: 300)
        let wider = Rules.frame(keepingTopLeftOf: right, resizedTo: CGSize(width: 400, height: 300), in: Self.screen)
        #expect(wider == CGRect(x: 1112, y: 500, width: 400, height: 300))
    }

    @Test func aPanelLeftPartlyOffTheScreenDoesNotJump() {
        // Its bottom is below the screen already. Getting shorter must not move its top.
        let hanging = CGRect(x: 100, y: -100, width: 300, height: 400)
        let shorter = Rules.frame(keepingTopLeftOf: hanging, resizedTo: CGSize(width: 300, height: 300), in: Self.screen)
        #expect(shorter.maxY == hanging.maxY)
        #expect(shorter.minX == hanging.minX)

        // Its right side is off the screen already. Staying as wide must not move it.
        let sideways = CGRect(x: 1400, y: 300, width: 300, height: 300)
        let same = Rules.frame(keepingTopLeftOf: sideways, resizedTo: CGSize(width: 300, height: 200), in: Self.screen)
        #expect(same.minX == sideways.minX)
    }

    // MARK: Fitting inside a free area

    @Test func thePictureIsFittedInsideTheRealAreaWhateverItsShape() {
        // A picture twice as wide as tall.
        // An area that is square: the picture fills the width and half the height.
        let square = CGSize(width: 400, height: 400 + Rules.barHeight)
        #expect(Rules.fittedFraction(pictureAspect: 2, panelSize: square) == CGSize(width: 1, height: 0.5))
        // An area twice as wide as the picture's shape is: the picture fills the height and half the width.
        let wide = CGSize(width: 800, height: 200 + Rules.barHeight)
        #expect(Rules.fittedFraction(pictureAspect: 2, panelSize: wide) == CGSize(width: 0.5, height: 1))
        // An area in the picture's own shape is filled.
        let same = CGSize(width: 400, height: 200 + Rules.barHeight)
        #expect(Rules.fittedFraction(pictureAspect: 2, panelSize: same) == CGSize(width: 1, height: 1))
        // A tall area, taller than any shape the old lock allowed.
        let tall = CGSize(width: 240, height: 1200 + Rules.barHeight)
        #expect(Rules.fittedFraction(pictureAspect: 2, panelSize: tall) == CGSize(width: 1, height: 0.1))
    }

    @Test func aPanelWithNoRoomOrNoPictureShapeFitsEverything() {
        let whole = CGSize(width: 1, height: 1)
        #expect(Rules.fittedFraction(pictureAspect: 2, panelSize: .zero) == whole)
        #expect(Rules.fittedFraction(pictureAspect: 2, panelSize: CGSize(width: 300, height: Rules.barHeight)) == whole)
        #expect(Rules.fittedFraction(pictureAspect: .nan, panelSize: CGSize(width: 300, height: 300)) == whole)
        #expect(Rules.fittedFraction(pictureAspect: 0, panelSize: CGSize(width: 300, height: 300)) == whole)
    }

    @Test func thePanLimitsFollowTheAreaNotThePicturesShape() {
        // A square area holding a picture twice as wide: it covers the width and half the height.
        let inSquare = Rules.fittedFraction(pictureAspect: 2, panelSize: CGSize(width: 400, height: 400 + Rules.barHeight))
        let zoomed = NookDesignZoom(scale: 1.5).panned(by: CGSize(width: 5, height: 5), fitted: inSquare)
        // One and a half times: 1.5 wide, which overflows, and 0.75 tall, which does not.
        #expect(zoomed.offset == CGSize(width: 0.25, height: 0))

        // A wide area holding the same picture: it covers the height and half the width.
        let inWide = Rules.fittedFraction(pictureAspect: 2, panelSize: CGSize(width: 800, height: 200 + Rules.barHeight))
        let other = NookDesignZoom(scale: 1.5).panned(by: CGSize(width: 5, height: 5), fitted: inWide)
        #expect(other.offset == CGSize(width: 0, height: 0.25))
        // Three times covers the area's width as well, and the pan opens along it.
        let more = NookDesignZoom(scale: 3).panned(by: CGSize(width: 5, height: 5), fitted: inWide)
        #expect(more.offset == CGSize(width: 0.25, height: 1))
    }

    @Test func thePercentIsRelativeToTheFitWhateverTheAreasShape() {
        // The fit is 100%, in a wide area as in a square one.
        #expect(NookDesignZoom.fit.percentText == "100%")
        let fitted = Rules.fittedFraction(pictureAspect: 2, panelSize: CGSize(width: 800, height: 200 + Rules.barHeight))
        let zoomed = NookDesignZoom.fit.zoomed(by: NookDesignZoom.step, fitted: fitted)
        #expect(zoomed.percentText == "125%")
        // A fit can be reached again from any zoom by zooming out.
        #expect(zoomed.zoomed(by: 1 / NookDesignZoom.step, fitted: fitted) == .fit)
    }

    // MARK: Place

    @Test func theFirstPanelSitsAtTheTopRightAndLaterOnesCascade() {
        let size = CGSize(width: 360, height: 270)
        let first = Rules.frameOrigin(slot: 0, size: size, in: Self.screen)
        let second = Rules.frameOrigin(slot: 1, size: size, in: Self.screen)

        #expect(first == CGPoint(x: 1512 - 24 - 360, y: 944 - 24 - 270))
        #expect(second == CGPoint(x: first.x - Rules.cascadeStep, y: first.y - Rules.cascadeStep))
    }

    @Test func everySlotKeepsThePanelOnTheScreen() {
        // The second screen of a pair sits to the left of the main one and lower.
        let screens = [Self.screen, CGRect(x: -1920, y: -200, width: 1920, height: 1055)]
        let sizes = [CGSize(width: 360, height: 270), CGSize(width: 240, height: 510), CGSize(width: 900, height: 700)]
        for screen in screens {
            for size in sizes {
                var seen = Set<String>()
                for slot in 0..<40 {
                    let origin = Rules.frameOrigin(slot: slot, size: size, in: screen)
                    let frame = CGRect(origin: origin, size: size)
                    #expect(screen.contains(frame), "slot \(slot) of \(size) left \(screen)")
                    seen.insert("\(origin.x),\(origin.y)")
                }
                // The cap's worth of panels never land on top of each other.
                let firstSix = Set((0..<Rules.maxOpenPanels).map { slot -> String in
                    let origin = Rules.frameOrigin(slot: slot, size: size, in: screen)
                    return "\(origin.x),\(origin.y)"
                })
                #expect(firstSix.count == Rules.maxOpenPanels, "\(size) in \(screen)")
            }
        }
    }

    @Test func aPanelLargerThanTheScreenStartsAtItsCorner() {
        let small = CGRect(x: 100, y: 50, width: 300, height: 200)
        let origin = Rules.frameOrigin(slot: 3, size: CGSize(width: 400, height: 400), in: small)
        #expect(origin == CGPoint(x: 100, y: 50))
    }

    // MARK: Zoom and fit

    @Test func theFitIsTheWholePictureInTheMiddle() {
        let one: CGFloat = 1
        #expect(NookDesignZoom.fit.scale == one)
        #expect(NookDesignZoom.fit.offset == .zero)
        #expect(NookDesignZoom.fit.isFit)
        #expect(NookDesignZoom.fit.percentText == "100%")
        #expect(NookDesignZoom(scale: 2.5).percentText == "250%")
        #expect(!NookDesignZoom(scale: 2).isFit)
    }

    @Test func zoomStaysBetweenTheFitAndEightTimes() {
        let low: CGFloat = 1
        let high: CGFloat = 8
        #expect(NookDesignZoom.fit.zoomed(to: 0.2).scale == low)
        #expect(NookDesignZoom.fit.zoomed(to: 50).scale == high)
        #expect(NookDesignZoom.fit.zoomed(to: .nan).scale == low)
        #expect(NookDesignZoom(scale: .infinity).clamped().scale == low)

        var zoom = NookDesignZoom.fit
        for _ in 0..<30 { zoom = zoom.zoomed(by: NookDesignZoom.step) }
        #expect(zoom.scale == high)
        for _ in 0..<30 { zoom = zoom.zoomed(by: 1 / NookDesignZoom.step) }
        #expect(zoom == .fit)
    }

    @Test func zoomingAroundThePointerKeepsTheSpotUnderIt() {
        // The spot of the picture under an anchor, in the picture's own
        // fractions: (anchor - offset) / scale.
        func spot(_ zoom: NookDesignZoom, under anchor: CGPoint) -> CGPoint {
            CGPoint(x: (anchor.x - zoom.offset.width) / zoom.scale, y: (anchor.y - zoom.offset.height) / zoom.scale)
        }
        let anchor = CGPoint(x: 0.2, y: -0.1)
        let start = NookDesignZoom(scale: 3, offset: CGSize(width: 0.3, height: -0.2))
        let before = spot(start, under: anchor)

        for target: CGFloat in [3.5, 4, 6, 8] {
            let zoomed = start.zoomed(to: target, around: anchor)
            let after = spot(zoomed, under: anchor)
            #expect(zoomed.scale == target)
            #expect(near(after.x, before.x) && near(after.y, before.y), "at \(target) the spot moved")
        }
        // Around the middle, a picture in the middle stays in the middle.
        #expect(NookDesignZoom.fit.zoomed(to: 4).offset == .zero)
    }

    @Test func thePictureCannotBeDraggedOutOfItsPanel() {
        let zoom = NookDesignZoom(scale: 3)
        let limit: CGFloat = 1
        #expect(NookDesignZoom.maxOffset(scale: 3, fitted: CGSize(width: 1, height: 1)) == CGSize(width: 1, height: 1))

        let far = zoom.panned(by: CGSize(width: 9, height: -9))
        #expect(far.offset == CGSize(width: limit, height: -limit))
        let some = zoom.panned(by: CGSize(width: 0.25, height: 0.5))
        #expect(some.offset == CGSize(width: 0.25, height: 0.5))
        // At the fit there is nowhere to pan to.
        #expect(NookDesignZoom.fit.panned(by: CGSize(width: 0.4, height: 0.4)) == .fit)
        // Zooming out pulls the picture back in.
        #expect(far.zoomed(to: 1) == .fit)
        #expect(NookDesignZoom(scale: 2, offset: CGSize(width: CGFloat.nan, height: 5)).clamped().offset == CGSize(width: 0, height: 0.5))
    }

    @Test func aFittedPictureOnlyPansAlongTheSideThatOverflows() {
        // A panorama covers its area's width and half its height.
        let fitted = CGSize(width: 1, height: 0.5)
        let zoom = NookDesignZoom(scale: 1.5).panned(by: CGSize(width: 5, height: 5), fitted: fitted)
        // One and a half times: 1.5 wide, which overflows, and 0.75 tall, which does not.
        #expect(zoom.offset == CGSize(width: 0.25, height: 0))

        let more = NookDesignZoom(scale: 4).panned(by: CGSize(width: 5, height: 5), fitted: fitted)
        #expect(more.offset == CGSize(width: 1.5, height: 0.5))
    }

    @Test func aPointerPlaceBecomesAnAnchorInThePictureArea() {
        let panel = CGSize(width: 400, height: 200 + Rules.barHeight)
        // AppKit counts from the bottom left. The strip of controls is at the bottom.
        let middle = Rules.anchor(forPanelPoint: CGPoint(x: 200, y: Rules.barHeight + 100), panelSize: panel)
        #expect(middle == .zero)
        let topLeft = Rules.anchor(forPanelPoint: CGPoint(x: 0, y: panel.height), panelSize: panel)
        #expect(topLeft == CGPoint(x: -0.5, y: -0.5))
        let bottomRight = Rules.anchor(forPanelPoint: CGPoint(x: 400, y: Rules.barHeight), panelSize: panel)
        #expect(bottomRight == CGPoint(x: 0.5, y: 0.5))
        // A pointer over the strip counts as the picture's bottom edge.
        let onBar = Rules.anchor(forPanelPoint: CGPoint(x: 200, y: 5), panelSize: panel)
        #expect(onBar == CGPoint(x: 0, y: 0.5))
        #expect(Rules.anchor(forPanelPoint: .zero, panelSize: .zero) == .zero)
    }

    @Test func aScrollWithAModifierZoomsByABoundedAmount() {
        let none: CGFloat = 1
        #expect(Rules.zoomFactor(forScroll: 0) == none)
        #expect(Rules.zoomFactor(forScroll: 10) > 1)
        #expect(Rules.zoomFactor(forScroll: -10) < 1)
        #expect(near(Rules.zoomFactor(forScroll: 10) * Rules.zoomFactor(forScroll: -10), 1))
        let most: CGFloat = 2
        let least: CGFloat = 0.5
        #expect(Rules.zoomFactor(forScroll: 100_000) == most)
        #expect(Rules.zoomFactor(forScroll: -100_000) == least)
        #expect(Rules.zoomFactor(forScroll: .nan) == none)
    }

    // MARK: Look

    @Test func opacityStaysWhereThePanelCanStillBeSeen() {
        let least = 0.2
        let most = 1.0
        #expect(Rules.clampedOpacity(0) == least)
        #expect(Rules.clampedOpacity(-3) == least)
        #expect(Rules.clampedOpacity(0.6) == 0.6)
        #expect(Rules.clampedOpacity(7) == most)
        #expect(Rules.clampedOpacity(.nan) == most)
    }

    @Test func alwaysOnTopFloatsAndFollowsAcrossSpaces() {
        typealias Controller = NookDesignReferencePanelController
        #expect(Controller.level(isPinned: true) == .floating)
        #expect(Controller.level(isPinned: false) == .normal)
        // Either way the panel may sit over another app's full screen window.
        #expect(Controller.collectionBehavior(isPinned: true).contains(.fullScreenAuxiliary))
        #expect(Controller.collectionBehavior(isPinned: false).contains(.fullScreenAuxiliary))
        #expect(Controller.collectionBehavior(isPinned: true).contains(.canJoinAllSpaces))
        #expect(!Controller.collectionBehavior(isPinned: false).contains(.canJoinAllSpaces))
        // A floating panel sits under the island, which is at the status bar's level.
        #expect(Controller.level(isPinned: true).rawValue < NSWindow.Level.statusBar.rawValue)
    }
}

// MARK: - The card's layout

@Suite struct NookDesignCardLayoutTests {
    @Test func theCardHasThreeFixedHeights() {
        let small = NookWidgetLayout.smallHeight
        #expect(NookDesignCardLayout.height(for: .small) == small)
        #expect(NookDesignCardLayout.height(for: .medium) == NookDesignCardLayout.mediumHeight)
        #expect(NookDesignCardLayout.height(for: .large) == NookDesignCardLayout.largeHeight)
        #expect(NookDesignCardLayout.height(for: .large) > NookDesignCardLayout.height(for: .medium))
    }

    @Test @MainActor func thePageCountsTheCardAtItsOwnHeight() {
        for size in NookWidgetSize.allCases {
            let placement = NookWidgetPlacement(kind: .design, size: size)
            #expect(NookPanelView.cardHeight(placement, calendarStyle: .strip) == NookDesignCardLayout.height(for: size))
            #expect(NookDesignCard.height(for: size) == NookDesignCardLayout.height(for: size))
        }
    }

    @Test func aRowHoldsAsManySquaresAsFit() {
        let six = 6
        // Six squares of 26 with five gaps of 6 are 186 wide.
        #expect(NookDesignCardLayout.capacity(width: 186, side: 26) == six)
        #expect(NookDesignCardLayout.capacity(width: 185, side: 26) == 5)
        #expect(NookDesignCardLayout.capacity(width: 10, side: 26) == 0)
        #expect(NookDesignCardLayout.capacity(width: 0, side: 26) == 0)
        #expect(NookDesignCardLayout.capacity(width: 300, side: 0) == 0)
    }

    @Test func whatDoesNotFitHidesBehindAPlusTile() {
        let all = NookDesignCardLayout.visible([1, 2, 3], capacity: 3)
        #expect(all.shown == [1, 2, 3])
        #expect(all.hidden == 0)

        // The last square gives way to the "+N" tile.
        let some = NookDesignCardLayout.visible([1, 2, 3, 4, 5], capacity: 3)
        #expect(some.shown == [1, 2])
        #expect(some.hidden == 3)

        let none = NookDesignCardLayout.visible([1, 2], capacity: 0)
        #expect(none.shown.isEmpty)
        #expect(none.hidden == 2)
        #expect(NookDesignCardLayout.visible([Int](), capacity: 4).hidden == 0)
    }

    @Test func aLongPaletteNameIsCutToFitItsChip() {
        #expect(NookDesignCardLayout.chipText("Brand") == "Brand")
        #expect(NookDesignCardLayout.chipText("Exactly 14 long") == "Exactly 14 lo…")
        #expect(NookDesignCardLayout.chipText("Marketing site 2026").count == 14)
        #expect(NookDesignCardLayout.chipText("abc", limit: 0) == "a…")
    }

    @Test func swatchesAndTilesNeverShrinkUnderAHitTarget() {
        for size in NookWidgetSize.allCases {
            #expect(NookDesignCardLayout.swatchSide(for: size) >= 26)
            #expect(NookDesignCardLayout.tileSide(for: size) >= 52)
        }
    }
}

// MARK: - The panel's state follows its window

@MainActor
@Suite struct NookDesignPanelStateTests {
    private static func picture(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 1, green: 0.5, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    private func state(pictureWidth: Int, pictureHeight: Int, panelSize: CGSize? = nil) throws -> NookDesignPanelState {
        let reference = NookDesignReference(
            id: UUID(), collectionID: NookDesignCollection.globalID, name: "Shot",
            fileName: "original.png", pixelWidth: pictureWidth, pixelHeight: pictureHeight,
            isFavorite: false, addedAt: NookDesignSamples.day
        )
        return NookDesignPanelState(
            reference: reference, image: try Self.picture(width: 8, height: 4), panelSize: panelSize
        )
    }

    @Test func aPanelWithNoSizeGivenIsInThePicturesShape() throws {
        let state = try state(pictureWidth: 300, pictureHeight: 200)
        #expect(state.fitted == CGSize(width: 1, height: 1))
        #expect(state.panelSize == NookDesignPanelRules.panelSize(width: 360, pictureAspect: 1.5))
    }

    @Test func whatThePictureCoversIsReadFromTheAreaThePanelHas() throws {
        let state = try state(pictureWidth: 400, pictureHeight: 200, panelSize: CGSize(width: 400, height: 400 + NookDesignPanelRules.barHeight))
        #expect(state.fitted == CGSize(width: 1, height: 0.5))

        state.resize(to: CGSize(width: 800, height: 200 + NookDesignPanelRules.barHeight))
        #expect(state.fitted == CGSize(width: 0.5, height: 1))
    }

    @Test func aZoomedPictureIsPulledBackWhenTheAreaGrowsAroundIt() throws {
        let bar = NookDesignPanelRules.barHeight
        let state = try state(pictureWidth: 400, pictureHeight: 200, panelSize: CGSize(width: 400, height: 200 + bar))
        state.zoom = state.zoom.zoomed(to: 3, fitted: state.fitted).panned(by: CGSize(width: 9, height: 9), fitted: state.fitted)
        #expect(state.zoom.offset == CGSize(width: 1, height: 1))

        // A third as tall as wide: the zoomed picture no longer overflows the width.
        state.resize(to: CGSize(width: 1200, height: 200 + bar))
        #expect(state.zoom.scale == 3)
        #expect(state.zoom.offset == CGSize(width: 0, height: 1))
        #expect(state.zoom.percentText == "300%")
    }

    @Test func aPictureAtTheFitStaysAtTheFitWhateverTheSize() throws {
        let bar = NookDesignPanelRules.barHeight
        let state = try state(pictureWidth: 400, pictureHeight: 200, panelSize: CGSize(width: 400, height: 200 + bar))
        for size in [CGSize(width: 240, height: 900), CGSize(width: 900, height: 150), CGSize(width: 500, height: 330)] {
            state.resize(to: size)
            #expect(state.zoom.isFit)
            #expect(state.zoom.percentText == "100%")
        }
    }
}
