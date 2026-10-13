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
        #expect(Rules.fittedFraction(pictureAspect: 1.5) == CGSize(width: 1, height: 1))
        // A panorama twice as wide as the widest area covers half its height.
        #expect(Rules.fittedFraction(pictureAspect: 4.8) == CGSize(width: 1, height: 0.5))
        // A long page a fifth as wide as the narrowest area covers a fifth of its width.
        let page = Rules.fittedFraction(pictureAspect: 0.1)
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

    @Test func resizingKeepsThePicturesShape() {
        let current = Rules.panelSize(width: 400, pictureAspect: 2)
        let room = CGSize(width: 2000, height: 1200)

        // The right edge was dragged: the height follows the width.
        let wider = Rules.resizedSize(
            proposed: CGSize(width: 600, height: current.height), current: current, pictureAspect: 2, available: room
        )
        #expect(wider == CGSize(width: 600, height: 300 + Rules.barHeight))

        // The bottom edge was dragged: the width follows the height.
        let taller = Rules.resizedSize(
            proposed: CGSize(width: current.width, height: 330), current: current, pictureAspect: 2, available: room
        )
        #expect(taller == CGSize(width: 600, height: 300 + Rules.barHeight))

        // A corner drag goes by the edge that moved more.
        let corner = Rules.resizedSize(
            proposed: CGSize(width: 500, height: current.height + 10), current: current, pictureAspect: 2, available: room
        )
        #expect(corner == CGSize(width: 500, height: 250 + Rules.barHeight))
    }

    @Test func resizingStopsAtTheMinimumAndAtTheScreen() {
        let current = Rules.panelSize(width: 400, pictureAspect: 2)
        let room = CGSize(width: 800, height: 600)

        let tiny = Rules.resizedSize(proposed: CGSize(width: 10, height: 10), current: current, pictureAspect: 2, available: room)
        #expect(tiny == Rules.panelSize(width: Rules.minimumWidth, pictureAspect: 2))

        let huge = Rules.resizedSize(proposed: CGSize(width: 5000, height: 5000), current: current, pictureAspect: 2, available: room)
        #expect(huge == Rules.panelSize(width: 800, pictureAspect: 2))

        let square = Rules.resizedSize(proposed: CGSize(width: 5000, height: 5000), current: current, pictureAspect: 1, available: room)
        #expect(square.height <= room.height)
        #expect(square.width == square.height - Rules.barHeight)
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
