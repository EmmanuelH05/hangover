import CoreGraphics
import Foundation
import Testing
@testable import OpenIslandApp

@Suite struct NookWidgetLayoutTests {
    private static func place(_ kind: NookWidgetKind, _ size: NookWidgetSize) -> NookWidgetPlacement {
        NookWidgetPlacement(kind: kind, size: size)
    }

    private static func makeDefaults() -> UserDefaults { MemoryDefaults() }

    // MARK: Rows

    @Test func twoSmallWidgetsShareARow() {
        let rows = NookWidgetLayout.rows([
            Self.place(.timer, .small), Self.place(.tray, .small), Self.place(.todo, .medium),
        ])

        #expect(rows.map { $0.placements.map(\.kind) } == [[.timer, .tray], [.todo]])
        #expect(rows[0].isSmallRow)
        #expect(!rows[1].isSmallRow)
    }

    @Test func aSmallWidgetBeforeAWideOneSitsAlone() {
        let rows = NookWidgetLayout.rows([
            Self.place(.timer, .small), Self.place(.calendar, .large), Self.place(.tray, .small),
        ])

        #expect(rows.map { $0.placements.map(\.kind) } == [[.timer], [.calendar], [.tray]])
    }

    @Test func threeSmallWidgetsMakeAPairAndASingle() {
        let rows = NookWidgetLayout.rows([
            Self.place(.timer, .small), Self.place(.tray, .small), Self.place(.notes, .small),
        ])

        #expect(rows.map(\.placements.count) == [2, 1])
    }

    @Test func noWidgetsMeansNoRows() {
        #expect(NookWidgetLayout.rows([]).isEmpty)
        #expect(NookWidgetLayout.contentHeight([]) { _ in 100 } == 0)
    }

    // MARK: Heights

    @Test func smallRowsUseTheSharedHeightAndSpacingSitsBetweenRows() {
        let placements = [Self.place(.timer, .small), Self.place(.tray, .small), Self.place(.todo, .large)]
        let height = NookWidgetLayout.contentHeight(placements) { $0.kind == .todo ? 236 : 999 }

        #expect(height == NookWidgetLayout.smallHeight + NookWidgetLayout.rowSpacing + 236)
    }

    @Test func pageHeightMatchesTheGridForEveryCard() {
        for kind in NookWidgetKind.allCases {
            for size in NookWidgetSize.allCases {
                let placement = Self.place(kind, size)
                let card = NookPanelView.cardHeight(placement, calendarStyle: .strip)
                if size == .small {
                    #expect(card == NookWidgetLayout.smallHeight, "\(kind) small")
                } else {
                    #expect(card > 0, "\(kind) \(size)")
                }
            }
            let medium = NookPanelView.cardHeight(Self.place(kind, .medium), calendarStyle: .strip)
            let large = NookPanelView.cardHeight(Self.place(kind, .large), calendarStyle: .strip)
            #expect(large > medium, "\(kind) large should be taller than medium")
        }
    }

    @Test func columnWidthSplitsThePageAroundTheGap() {
        #expect(NookWidgetLayout.columnWidth(totalWidth: 510) == 250)
        #expect(NookWidgetLayout.columnWidth(totalWidth: 4) == 0)
    }

    // MARK: Moving and resizing

    @Test func movingClampsTheTargetIndex() {
        let order: [NookWidgetKind] = [.media, .calendar, .todo]

        #expect(NookWidgetLayout.moving(.todo, to: 0, in: order) == [.todo, .media, .calendar])
        #expect(NookWidgetLayout.moving(.media, to: 99, in: order) == [.calendar, .todo, .media])
        #expect(NookWidgetLayout.moving(.mirror, to: 0, in: order) == order)
    }

    @Test func resizeGripStepsOneSizePerStepAlongTheLongerAxis() {
        let step = NookWidgetLayout.resizeStep

        #expect(NookWidgetLayout.snappedSize(from: .medium, translation: CGSize(width: 10, height: step + 1)) == .large)
        #expect(NookWidgetLayout.snappedSize(from: .medium, translation: CGSize(width: -(step + 1), height: 5)) == .small)
        #expect(NookWidgetLayout.snappedSize(from: .small, translation: CGSize(width: step * 3, height: 0)) == .large)
        #expect(NookWidgetLayout.snappedSize(from: .large, translation: CGSize(width: 0, height: -(step * 5))) == .small)
        #expect(NookWidgetLayout.snappedSize(from: .medium, translation: CGSize(width: step - 1, height: 0)) == .medium)
    }

    // MARK: Preferences

    @Test func defaultsKeepTodaysPage() {
        let preferences = NookDisplayPreferences()
        let placements = preferences.placements(enabled: NookWidgetKind.defaultEnabled)

        #expect(placements.map(\.kind) == NookWidgetKind.defaultEnabled)
        #expect(placements.allSatisfy { $0.size == .medium })
    }

    @Test func placementsFollowTheSavedOrderAndSkipHiddenAndDisabled() {
        var preferences = NookDisplayPreferences()
        preferences.widgetOrder = [.timer, .media, .timer]
        preferences.widgetSizes = [.timer: .small]
        preferences.hiddenWidgets = [.calendar]

        let placements = preferences.placements(enabled: [.media, .calendar, .todo, .timer])

        #expect(placements.map(\.kind) == [.timer, .media, .todo])
        #expect(placements.first?.size == .small)
        #expect(preferences.normalizedWidgetOrder.count == NookWidgetKind.allCases.count)
    }

    @Test func orderAndSizesRoundTripPerProfile() {
        let defaults = Self.makeDefaults()
        var notch = NookDisplayPreferences()
        notch.widgetOrder = [.todo, .media]
        notch.widgetSizes = [.todo: .large, .media: .small]
        notch.persist(for: .notch, defaults: defaults)

        let loaded = NookDisplayPreferences.load(for: .notch, defaults: defaults)
        let other = NookDisplayPreferences.load(for: .topBar, defaults: defaults)

        #expect(loaded.widgetOrder == [.todo, .media])
        #expect(loaded.widgetSizes == [.todo: .large, .media: .small])
        #expect(other.widgetSizes.isEmpty)
        #expect(other.widgetOrder == NookWidgetKind.allCases)
    }
}
