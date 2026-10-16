import CoreGraphics
import Testing
@testable import OpenIslandApp

// MARK: - What the closed notch shows

@MainActor @Suite struct NookRecordClosedTests {
    @Test func aRecordingOutranksTheTimerAndNotices() {
        let notice = NookTransientActivity(symbol: "bolt", text: "Charging")
        let activity = NookClosedActivity.resolve(
            transient: notice, timerText: "5m", media: nil,
            preferences: NookDisplayPreferences(), recording: (text: "0:42", isPaused: false)
        )
        #expect(activity?.trailing == .text("0:42"))
    }

    @Test func noRecordingLeavesTheTimerAsItWas() {
        let activity = NookClosedActivity.resolve(
            transient: nil, timerText: "5m", media: nil, preferences: NookDisplayPreferences()
        )
        #expect(activity?.trailing == .text("5m"))
    }

    @Test func aRecordingIsRedAndAPausedOneIsYellow() {
        let running = NookClosedActivity.resolve(
            transient: nil, timerText: nil, media: nil,
            preferences: NookDisplayPreferences(), recording: (text: "0:05", isPaused: false)
        )
        let paused = NookClosedActivity.resolve(
            transient: nil, timerText: nil, media: nil,
            preferences: NookDisplayPreferences(), recording: (text: "0:05", isPaused: true)
        )
        #expect(running?.leading == .symbol("record.circle.fill", .red))
        #expect(paused?.leading == .symbol("pause.circle.fill", .yellow))
        #expect(running?.yieldsToAgents == false)
    }

    @Test func aRecordingShowsEvenWithNoticesTurnedOff() {
        var preferences = NookDisplayPreferences()
        preferences.showsNotices = false
        let activity = NookClosedActivity.resolve(
            transient: nil, timerText: "5m", media: nil,
            preferences: preferences, recording: (text: "1:00", isPaused: false)
        )
        #expect(activity?.trailing == .text("1:00"))
    }

    @Test func theSwipeNeverHidesARecording() {
        let activity = NookClosedActivity.resolve(
            transient: nil, timerText: "5m", media: nil,
            preferences: NookDisplayPreferences(), isHidden: true, recording: (text: "1:00", isPaused: false)
        )
        #expect(activity?.trailing == .text("1:00"))
    }

    @Test func aRecordingOutranksMusic() {
        let media = NookClosedMediaActivity(
            artwork: nil, gifURL: nil, gifScale: 1, gifOffset: .zero, isPlaying: true
        )
        let activity = NookClosedActivity.resolve(
            transient: nil, timerText: nil, media: media,
            preferences: NookDisplayPreferences(), recording: (text: "2:00", isPaused: false)
        )
        #expect(activity?.showsArtwork == false)
        #expect(activity?.trailing == .text("2:00"))
    }
}

// MARK: - A click on the closed notch

@Suite struct NookRecordClickTests {
    func context(
        status: NotchStatus = .closed,
        inClosedSurface: Bool = true,
        isRecording: Bool
    ) -> IslandClickContext {
        IslandClickContext(
            status: status,
            reason: nil,
            isInClosedSurface: inClosedSurface,
            isInExpandedArea: false,
            isOnNotch: false,
            blocksDismiss: false,
            isRecording: isRecording
        )
    }

    @Test func aClickOnTheClosedNotchStopsARecording() {
        #expect(IslandPointerRules.clickAction(context(isRecording: true)) == .stopRecording)
    }

    @Test func withNothingRecordingAClickStillOpensTheIsland() {
        #expect(IslandPointerRules.clickAction(context(isRecording: false)) == .open)
    }

    @Test func aClickOutsideTheClosedNotchIsNotItsOwn() {
        #expect(IslandPointerRules.clickAction(context(inClosedSurface: false, isRecording: true)) == .none)
    }

    @Test func aRecordingChangesNothingOnceTheIslandIsOpen() {
        let withRecording = context(status: .opened, inClosedSurface: false, isRecording: true)
        let without = context(status: .opened, inClosedSurface: false, isRecording: false)
        #expect(IslandPointerRules.clickAction(withRecording) == IslandPointerRules.clickAction(without))
    }
}

// MARK: - The card's sizes

@Suite struct NookRecordCardLayoutTests {
    @Test func everyRowFitsItsCard() {
        for size in NookWidgetSize.allCases {
            let room = NookRecordCardLayout.height(for: size) - NookRecordCardLayout.verticalPadding * 2
            #expect(NookRecordCardLayout.contentHeight(for: size) <= room, "\(size) is too short for its rows")
        }
    }

    @Test func smallSharesTheGridsHeight() {
        let expected: CGFloat = NookWidgetLayout.smallHeight
        #expect(NookRecordCardLayout.height(for: .small) == expected)
    }

    @Test func biggerSizesAreTallerAndTheCardIsNeverShorterThanSmall() {
        let small = NookRecordCardLayout.height(for: .small)
        let medium = NookRecordCardLayout.height(for: .medium)
        let large = NookRecordCardLayout.height(for: .large)
        #expect(medium > 0)
        #expect(large > medium)
        #expect(small >= NookRecordCardLayout.contentHeight(for: .small) + NookRecordCardLayout.verticalPadding * 2)
    }

    @Test func theHeightIsTheRowsPlusTheGapsPlusThePadding() {
        // Medium: header 16, controls 26, button 28, two gaps of 5, padding 24.
        let medium: CGFloat = 16 + 26 + 28 + 5 * 2 + 12 * 2
        #expect(NookRecordCardLayout.height(for: .medium) == medium)
        // Large: header 16, two controls 52, button 28, status 26, four gaps of 7.5, padding 24.
        let large: CGFloat = 16 + 26 + 26 + 28 + 26 + 7.5 * 4 + 12 * 2
        #expect(NookRecordCardLayout.height(for: .large) == large)
    }

    @Test func theCardsKeepTheHeightsTheGridAlreadyGaveThem() {
        let small: CGFloat = 120
        let medium: CGFloat = 104
        let large: CGFloat = 176
        #expect(NookRecordCardLayout.height(for: .small) == small)
        #expect(NookRecordCardLayout.height(for: .medium) == medium)
        #expect(NookRecordCardLayout.height(for: .large) == large)
    }

    @Test func theSmallCardsRowsFillItsHeightWithNoBandLeftOver() {
        let room = NookRecordCardLayout.height(for: .small) - NookRecordCardLayout.verticalPadding * 2
        #expect(NookRecordCardLayout.contentHeight(for: .small) == room)
    }

    @Test func theCaptureChoiceAndTheSwitchesShareTheTopRowAtMedium() throws {
        let rows = NookRecordCardLayout.setupRows(for: .medium)
        let top = try #require(rows.first { $0.contains(.capture) })
        #expect(top.contains(.switches), "medium should hold both groups on one row")
        #expect(top.first == .capture, "the capture choice is on the left")
        #expect(top.last == .switches, "the switches are on the right")
    }

    @Test(arguments: NookWidgetSize.allCases)
    func theRecordButtonHasARowToItselfSoItRunsTheCardsWholeWidth(size: NookWidgetSize) throws {
        let rows = NookRecordCardLayout.setupRows(for: size)
        let row = try #require(rows.first { $0.contains(.record) })
        #expect(row == [.record])
    }

    @Test func theQualityChoiceSitsWithTheTitleWhereTheCardHasARowForIt() {
        for size in [NookWidgetSize.medium, .large] {
            let header = NookRecordCardLayout.setupRows(for: size).first
            #expect(header == [.title, .quality], "\(size) keeps the quality choice beside the title")
        }
        let small = NookRecordCardLayout.setupRows(for: .small).flatMap { $0 }
        #expect(!small.contains(.quality), "the small card has no room for the quality choice")
    }

    @Test(arguments: NookWidgetSize.allCases)
    func everyRowHasAHeightAndNoPartIsLeftOut(size: NookWidgetSize) {
        let rows = NookRecordCardLayout.setupRows(for: size)
        #expect(NookRecordCardLayout.rowHeights(for: size).count == rows.count)
        let parts = rows.flatMap { $0 }
        #expect(parts.count == Set(parts).count, "\(size) lists a part twice")
        for part in [NookRecordSetupPart.capture, .switches, .record] {
            #expect(parts.contains(part), "\(size) is missing \(part)")
        }
    }

    @Test func theCardIsReachableFromThePagesHeightMath() {
        for size in NookWidgetSize.allCases {
            let placement = NookWidgetPlacement(kind: .record, size: size)
            let height = NookPanelView.cardHeight(placement, calendarStyle: .strip)
            #expect(height == NookRecordCard.height(for: size))
        }
    }
}

// MARK: - The face cam bubble's sizes

@Suite struct NookFaceCamLayoutTests {
    @Test func aSizeIsHeldBetweenTheSmallestAndTheLargest() {
        let smallest: CGFloat = 120
        let largest: CGFloat = 360
        #expect(NookFaceCamLayout.clamped(10) == smallest)
        #expect(NookFaceCamLayout.clamped(1000) == largest)
        #expect(NookFaceCamLayout.clamped(200) == 200)
    }

    @Test func theThreeSizesAreAllInRange() {
        for size in NookFaceCamSize.allCases {
            #expect(NookFaceCamLayout.clamped(size.diameter) == size.diameter)
        }
        let defaultSize: CGFloat = 160
        #expect(NookFaceCamSize.medium.diameter == defaultSize)
    }

    @Test func draggingTheEdgeOutMakesTheCircleBigger() {
        let center = CGPoint(x: 500, y: 400)
        let diameter = NookFaceCamLayout.diameter(draggingTo: CGPoint(x: 600, y: 400), center: center)
        let expected: CGFloat = 200
        #expect(diameter == expected)
    }

    @Test func draggingPastTheLimitsStopsAtThem() {
        let center = CGPoint(x: 500, y: 400)
        let tiny: CGFloat = 120
        let huge: CGFloat = 360
        #expect(NookFaceCamLayout.diameter(draggingTo: CGPoint(x: 510, y: 400), center: center) == tiny)
        #expect(NookFaceCamLayout.diameter(draggingTo: CGPoint(x: 2000, y: 400), center: center) == huge)
    }

    @Test func aPressNearTheEdgeResizesAndOneInsideMoves() {
        let diameter: CGFloat = 160
        // The middle, a quarter in, and the rim at the right.
        #expect(!NookFaceCamLayout.isOnEdge(CGPoint(x: 80, y: 80), diameter: diameter))
        #expect(!NookFaceCamLayout.isOnEdge(CGPoint(x: 120, y: 80), diameter: diameter))
        #expect(NookFaceCamLayout.isOnEdge(CGPoint(x: 158, y: 80), diameter: diameter))
        #expect(NookFaceCamLayout.isOnEdge(CGPoint(x: 150, y: 80), diameter: diameter))
        // A square's corner is outside the circle, so it counts as the rim.
        #expect(NookFaceCamLayout.isOnEdge(CGPoint(x: 2, y: 2), diameter: diameter))
    }

    @Test func resizingKeepsTheCenterWhereItWas() {
        let frame = CGRect(x: 100, y: 100, width: 160, height: 160)
        let bigger = NookFaceCamLayout.resized(frame, to: 240)
        #expect(bigger.midX == frame.midX)
        #expect(bigger.midY == frame.midY)
        let width: CGFloat = 240
        #expect(bigger.width == width)
        #expect(bigger.height == width)
    }

    @Test func itFirstAppearsAtTheBottomLeftOfTheVisibleScreen() {
        let visible = CGRect(x: 0, y: 25, width: 1440, height: 800)
        let frame = NookFaceCamLayout.startFrame(in: visible)
        let margin: CGFloat = 24
        #expect(frame.minX == visible.minX + margin)
        #expect(frame.minY == visible.minY + margin)
        let diameter: CGFloat = 160
        #expect(frame.width == diameter)
    }
}

// MARK: - The area overlay's rectangle

@Suite struct NookRecordAreaRulesTests {
    @Test func aRectangleDraggedUpAndLeftIsTheSameAsOneDraggedDownAndRight() {
        let a = NookRecordAreaRules.rect(from: CGPoint(x: 50, y: 60), to: CGPoint(x: 10, y: 20))
        let b = NookRecordAreaRules.rect(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 50, y: 60))
        #expect(a == b)
        #expect(a == CGRect(x: 10, y: 20, width: 40, height: 40))
    }

    @Test func aSlipOfTheHandIsNotUsable() {
        #expect(!NookRecordAreaRules.isUsable(CGRect(x: 0, y: 0, width: 5, height: 300)))
        #expect(!NookRecordAreaRules.isUsable(CGRect(x: 0, y: 0, width: 300, height: 15)))
        #expect(NookRecordAreaRules.isUsable(CGRect(x: 0, y: 0, width: 16, height: 16)))
    }

    @Test func theRectangleIsHeldInsideTheDisplay() {
        let display = CGSize(width: 1440, height: 900)
        let spilling = CGRect(x: 1400, y: 800, width: 200, height: 200)
        #expect(NookRecordAreaRules.clamped(spilling, toDisplayOfSize: display) == CGRect(x: 1400, y: 800, width: 40, height: 100))
        let inside = CGRect(x: 10, y: 10, width: 300, height: 200)
        #expect(NookRecordAreaRules.clamped(inside, toDisplayOfSize: display) == inside)
    }

    @Test func aRectangleOffTheDisplayOrLeftWithASliverIsNothing() {
        let display = CGSize(width: 1440, height: 900)
        #expect(NookRecordAreaRules.clamped(CGRect(x: 2000, y: 0, width: 100, height: 100), toDisplayOfSize: display) == nil)
        #expect(NookRecordAreaRules.clamped(CGRect(x: 1435, y: 0, width: 100, height: 100), toDisplayOfSize: display) == nil)
    }
}
