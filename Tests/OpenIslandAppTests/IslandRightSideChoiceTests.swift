import Foundation
import Testing
@testable import OpenIslandApp

@MainActor
@Suite struct IslandRightSideChoiceTests {
    @Test(arguments: [NookSideSlot.agents, .date, .battery, .countdown])
    func anExtraTakesTheWholeRightSide(slot: NookSideSlot) {
        let choice = IslandRightSideChoice.extra(slot)

        // The island's own slot steps aside, whatever it was on.
        #expect(choice.ownSlot == .none)
        #expect(choice.nookSlot == slot)
    }

    @Test(arguments: [IslandRightSlot.count, .agents, .none])
    func oneOfTheIslandsOwnCardsClearsTheExtra(slot: IslandRightSlot) {
        let choice = IslandRightSideChoice.own(slot)

        #expect(choice.ownSlot == slot)
        #expect(choice.nookSlot == nil)
    }

    private func pill(own: IslandRightSlotContent?, extra: NookSideSlotContent?, waiting: Bool) -> V6ClosedPill {
        V6ClosedPill(
            mode: waiting ? .waiting : .idle,
            label: nil,
            rightSlot: own,
            layout: .macbook,
            height: 32,
            physicalNotchWidth: 180,
            agentsNeedAttention: waiting,
            rightExtra: extra
        )
    }

    @Test func aPickedExtraShowsWhileAnAgentWaits() {
        // What a pick of an extra leaves: no own slot, the extra alone.
        let picked = pill(own: nil, extra: .date(9), waiting: true)

        #expect(picked.contentKey.rightExtra == .date(9))
    }

    @Test func theBugThatHidThePick() {
        // What a pick of an extra used to leave when the own slot was on
        // count: the count comes back while an agent waits, and the pick is
        // gone from the pill. Still how a template combines the two.
        let before = pill(own: .count(3), extra: .date(9), waiting: true)
        let quiet = pill(own: .count(3), extra: .date(9), waiting: false)

        #expect(before.contentKey.rightExtra == nil)
        #expect(quiet.contentKey.rightExtra == .date(9))
    }
}
