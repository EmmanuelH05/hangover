import Foundation
import OpenIslandCore

/// The one job the Keychain store still has: bringing a token that an older
/// build saved there over to the token file. This is the only place the
/// Keychain store is made (a source test holds it to that).
///
/// Nothing here runs by itself. The app reads only the file at launch,
/// because reading the Keychain is what raised macOS's prompt after every
/// update. The move runs when the user presses "Bring my saved token over",
/// and macOS may ask then, which is fine: the user asked.
struct NookTodoTokenMove: Sendable {
    enum Outcome: Equatable, Sendable {
        /// The token is in the file and the Keychain item is gone.
        case moved
        /// The token is in the file. The Keychain item could not be deleted,
        /// and a later disconnect tries again.
        case movedButItemRemains
        /// The Keychain holds nothing for this source.
        case nothingSaved
    }

    /// Where an older build left the token. Nil for the demo and for tests
    /// that have no use for one.
    let oldStore: (any NookTodoTokenStoring)?

    static var notion: NookTodoTokenMove { NookTodoTokenMove(oldStore: NookTodoKeychain.notion) }
    static var tickTick: NookTodoTokenMove { NookTodoTokenMove(oldStore: NookTodoKeychain.tickTick) }
    static let none = NookTodoTokenMove(oldStore: nil)

    var hasOldStore: Bool { oldStore != nil }

    /// Reads the old store once, writes the file, reads the file back, then
    /// deletes the old item. The delete comes last and waits for the read
    /// back: a write that failed, or reported success without keeping the
    /// token, leaves the token where it was.
    func bringOver(to file: any NookTodoTokenStoring) throws -> Outcome {
        guard let oldStore, let token = try oldStore.read() else { return .nothingSaved }
        try file.save(token)
        guard try file.read() == token else { throw NookTodoTokenFileError(.cannotSave) }
        do {
            try oldStore.delete()
        } catch {
            return .movedButItemRemains
        }
        return .moved
    }

    /// Deletes the old item without reading it. A delete does not raise
    /// macOS's prompt. A missing item counts as deleted.
    func removeOldItem() throws {
        try oldStore?.delete()
    }
}

/// The move each service gets. The real ones reach the Keychain, and only
/// when the user presses the button. A test run gets none by construction,
/// whatever a test builds with default arguments.
struct NookTodoTokenMoves: Sendable {
    var notion: NookTodoTokenMove
    var tickTick: NookTodoTokenMove

    static let real = NookTodoTokenMoves(notion: .notion, tickTick: .tickTick)
    static let none = NookTodoTokenMoves(notion: .none, tickTick: .none)

    /// What the hub uses unless it is told otherwise.
    static var forThisRun: NookTodoTokenMoves { isTestRun ? .none : .real }

    private static let isTestRun = OpenIslandStateDirectory.isTestRun(
        processName: ProcessInfo.processInfo.processName,
        environment: ProcessInfo.processInfo.environment,
        loadedBundlePaths: Bundle.allBundles.map(\.bundlePath)
    )
}

/// Whether Settings shows "Bring my saved token over", as a plain value. It
/// shows only when no token is in use, an older build may have left one
/// in the Keychain, and that has not been dealt with yet. Nothing here asks
/// the Keychain: the query is what raises the prompt. The sign that one may
/// exist is what the app already saved when an account was connected.
struct NookTodoTokenMoveOffer: Equatable, Sendable {
    /// The source is on and holds no token. A pasted token that was refused
    /// leaves it that way, and a file that could not be used does the same:
    /// the press writes a fresh private file over either.
    var isNotConnected: Bool
    /// The app saved an account name, a picked database or list, or an
    /// offline copy of the tasks, which only a connected account leaves.
    var hasSavedAccountSign: Bool
    /// The old item was moved, found missing or deleted already.
    var isKeychainSettled: Bool
    /// There is an old store to read.
    var canMove: Bool

    var isShown: Bool {
        isNotConnected && hasSavedAccountSign && !isKeychainSettled && canMove
    }
}

extension NookTodoTokenFileError {
    /// The error to show for whatever a store threw. A file error keeps its
    /// own reason. Anything else, a Keychain status for one, gets `fallback`.
    /// Only a reason is kept, never the error's own text.
    static func describing(_ error: any Error, fallback: Reason) -> NookTodoTokenFileError {
        (error as? NookTodoTokenFileError) ?? NookTodoTokenFileError(fallback)
    }
}
