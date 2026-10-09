import Foundation
import Testing
@testable import OpenIslandCore

/// A command that opens with a long run of words the reader strips one at a
/// time is not read at all. Each strip copies the rest of the text, and the
/// reader runs on the bridge's one queue.
struct ClaudeBashStripLimitTests {
    private static let hostile: [String] = [
        String(repeating: "do ", count: 3_000) + "rm -rf x",
        String(repeating: "A=1 ", count: 2_400) + "rm -rf x",
        "nice" + String(repeating: " -a", count: 3_000) + " rm -rf x",
        "timeout" + String(repeating: " -k 1s", count: 1_500) + " rm -rf x",
        String(repeating: "nice ", count: 1_900) + "rm -rf x",
    ]

    @Test func aLongRunOfStrippedWordsIsUnreadable() {
        for command in Self.hostile {
            #expect(ClaudeBashCommandParts.reading(of: command) == .unreadable)
        }
    }

    @Test func theHostileCommandsAreTurnedAwayQuickly() {
        let clock = ContinuousClock()
        let spent = clock.measure {
            for command in Self.hostile { _ = ClaudeBashCommandParts.reading(of: command) }
        }
        #expect(spent < .seconds(1))
    }

    @Test func anOrdinaryCommandIsStillReadPastItsWrappers() {
        let reading = ClaudeBashCommandParts.reading(of: "FOO=1 BAR=2 nice -n 5 rm -rf build")
        guard case let .commands(commands) = reading else {
            Issue.record("an ordinary command came back unreadable")
            return
        }
        #expect(commands.contains("rm -rf build"))
    }

    @Test func aRunUnderTheLimitIsStillRead() {
        let command = String(repeating: "A=1 ", count: 40) + "rm -rf x"
        guard case let .commands(commands) = ClaudeBashCommandParts.reading(of: command) else {
            Issue.record("forty assignments came back unreadable")
            return
        }
        #expect(commands.contains("rm -rf x"))
    }

    @Test func aCommandThatDoesNotStartWithAStrippedWordIsNeverCounted() {
        #expect(ClaudeBashCommandParts.stripsTooManyWords("rm -rf " + String(repeating: "-a ", count: 500)) == false)
        #expect(ClaudeBashCommandParts.stripsTooManyWords("git commit -m 'do do do do'") == false)
    }
}
