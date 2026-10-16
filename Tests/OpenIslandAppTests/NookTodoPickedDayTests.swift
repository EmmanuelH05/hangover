import Foundation
import Testing
@testable import OpenIslandApp

/// A picked day is not lost when the source cannot take dates for a while
/// (D3 of the review fixes). It waits, and a different source drops it.
@MainActor
@Suite struct NookTodoPickedDayTests {
    private typealias F = NookTodoDueFixtures
    private let day = F.day(2026, 10, 16)

    // MARK: The source goes offline and comes back

    @Test func aSourceThatCannotTakeDatesForNowIsNotSentTheDay() {
        let sent = NookTodoAdding.dayToSend(picked: day, isSmall: false, canSetDue: false)

        #expect(sent == nil)
    }

    @Test func theDayGoesOnceTheSourceCanTakeItAgain() {
        let offline = NookTodoAdding.dayToSend(picked: day, isSmall: false, canSetDue: false)
        let online = NookTodoAdding.dayToSend(picked: day, isSmall: false, canSetDue: true)

        #expect(offline == nil)
        #expect(online == day)
    }

    @Test func aTaskAddedWhileTheSourceCouldNotTakeADayDoesNotUseTheDayUp() {
        // The card sent no day. A day still picked is not cleared by the add.
        let sent = NookTodoAdding.dayToSend(picked: day, isSmall: false, canSetDue: false)

        let kept = NookTodoAdding.fields(afterAdding: true, sent: "HW3", sentDue: sent, draft: "HW3", dueDraft: day)

        #expect(kept.draft.isEmpty)
        #expect(kept.dueDraft == day)
    }

    @Test func theSmallCardSendsNoDay() {
        #expect(NookTodoAdding.dayToSend(picked: day, isSmall: true, canSetDue: true) == nil)
    }

    @Test func noPickedDayIsNoDay() {
        #expect(NookTodoAdding.dayToSend(picked: nil, isSmall: false, canSetDue: true) == nil)
    }

    // MARK: A different source

    @Test(arguments: NookTodoSourceKind.allCases)
    func theSameSourceKeepsThePickedDay(kind: NookTodoSourceKind) {
        #expect(NookTodoAdding.pickedDay(day, afterSourceChangedFrom: kind, to: kind) == day)
    }

    @Test func anotherSourceDropsThePickedDay() {
        for old in NookTodoSourceKind.allCases {
            for new in NookTodoSourceKind.allCases where new != old {
                let picked = NookTodoAdding.pickedDay(day, afterSourceChangedFrom: old, to: new)
                #expect(picked == nil, "\(old) to \(new)")
            }
        }
    }

    @Test func noPickedDayStaysNoPickedDay() {
        #expect(NookTodoAdding.pickedDay(nil, afterSourceChangedFrom: .reminders, to: .notion) == nil)
    }
}
