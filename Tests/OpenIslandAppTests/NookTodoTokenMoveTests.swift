import Foundation
import Testing
@testable import OpenIslandApp

// The move from the Keychain to the token file. The Keychain is a fake that
// counts its reads: launch must read it zero times, the button once, and a
// new account never. The real Keychain, the network and a window are never
// involved.

/// Stands in for the Keychain item an older build left. Counts every call.
final class CountingOldStore: NookTodoTokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    private var reads = 0
    private var saves = 0
    private var deletes = 0
    private var readError: (any Error)?
    private var deleteError: (any Error)?
    private var gate: DispatchSemaphore?

    init(token: String? = nil) { stored = token }

    var token: String? { lock.withLock { stored } }
    var readCount: Int { lock.withLock { reads } }
    var saveCount: Int { lock.withLock { saves } }
    var deleteCount: Int { lock.withLock { deletes } }

    func failReads(with error: (any Error)?) { lock.withLock { readError = error } }
    func failDeletes(with error: (any Error)?) { lock.withLock { deleteError = error } }

    /// Makes the next read wait, like a macOS prompt that is still up, until
    /// `releaseReads()`. `readCount` goes up as the read begins.
    func holdReads() { lock.withLock { gate = DispatchSemaphore(value: 0) } }
    func releaseReads() { lock.withLock { gate }?.signal() }

    func read() throws -> String? {
        let waiting = lock.withLock { () -> DispatchSemaphore? in
            reads += 1
            return gate
        }
        waiting?.wait()
        return try lock.withLock {
            if let readError { throw readError }
            return stored
        }
    }

    func save(_ token: String) throws {
        lock.withLock {
            saves += 1
            stored = token
        }
    }

    func delete() throws {
        try lock.withLock {
            deletes += 1
            if let deleteError { throw deleteError }
            stored = nil
        }
    }
}

/// An empty token file that cannot be written.
private struct UnwritableTokenStore: NookTodoTokenStoring {
    func read() throws -> String? { nil }
    func save(_ token: String) throws { throw NookTodoTokenFileError(.cannotSave) }
    func delete() throws {}
}

/// A token file whose save says it worked and keeps nothing.
private struct ForgetfulTokenStore: NookTodoTokenStoring {
    func read() throws -> String? { nil }
    func save(_ token: String) throws {}
    func delete() throws {}
}

/// A token file that holds a token and cannot delete it.
private struct UndeletableTokenStore: NookTodoTokenStoring {
    let token: String
    func read() throws -> String? { token }
    func save(_ token: String) throws {}
    func delete() throws { throw NookTodoTokenFileError(.cannotRemove) }
}

/// A token file whose save keeps nothing and whose read hands back what
/// another store holds.
private struct SaveIgnoringStore: NookTodoTokenStoring {
    let readsAs: InMemoryTodoTokenStore
    func read() throws -> String? { try readsAs.read() }
    func save(_ token: String) throws {}
    func delete() throws {}
}

/// Polls until `condition` holds. False when it never did.
@MainActor
private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<1_000 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// A real token file in a temporary folder, a counting fake for the old
/// Keychain item, and one service wired to both.
@MainActor
private final class NotionMoveHarness {
    static let oldToken = "ntn_old_keychain_token"

    let old: CountingOldStore
    let file: NookTodoTokenFile
    let defaults: UserDefaults = MemoryDefaults()
    let transport = StubTodoTransport()
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("NotionMoveTests-\(UUID().uuidString)", isDirectory: true)
    let cache: NotionTodoCache
    let service: NookNotionTodoService

    /// `savedAccount` is the name an older build saved when it connected.
    /// `fileStore` stands in for the token file when a test needs one that
    /// misbehaves.
    init(
        oldToken: String? = NotionMoveHarness.oldToken,
        savedAccount: Bool = true,
        moveWorks: Bool = true,
        fileStore: (any NookTodoTokenStoring)? = nil
    ) {
        old = CountingOldStore(token: oldToken)
        file = NookTodoTokenFile(
            folder: root.appendingPathComponent("Secrets", isDirectory: true),
            fileName: NookTodoTokenFile.fileName(kind: NookTodoTokenFile.notionKind, bundleID: "app.test")
        )
        if savedAccount {
            defaults.set("Nook · Home", forKey: NookNotionTodoService.Keys.account)
        }
        cache = NotionTodoCache(directory: root.appendingPathComponent("Cache", isDirectory: true))
        service = NookNotionTodoService(
            defaults: defaults, transport: transport, tokenStore: fileStore ?? file,
            tokenMove: moveWorks ? NookTodoTokenMove(oldStore: old) : .none,
            cache: cache
        )
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    /// Stops the service, lets a background cache write land, then removes
    /// the folder. Nothing rewrites it afterwards.
    func finish() async {
        service.setActive(false)
        for _ in 0..<20 { await Task.yield() }
        _ = await cache.load()
        try? FileManager.default.removeItem(at: root)
    }

    func activate() async {
        service.setActive(true)
        await service.setupTask?.value
    }

    func serveAccount() {
        transport.setResponder { request, _ in
            switch request.route {
            case "GET /v1/users/me": .json("{\"object\":\"user\",\"name\":\"Nook\",\"bot\":{\"workspace_name\":\"Home\"}}")
            default: .json(NotionFixtures.list([]))
            }
        }
    }

    /// Every value the app wrote to its settings, as one string.
    var savedSettings: String {
        defaults.dictionaryRepresentation().map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
    }
}

@MainActor
private final class TickTickMoveHarness {
    static let oldToken = "tt_old_keychain_token"

    let old: CountingOldStore
    let file: NookTodoTokenFile
    let defaults: UserDefaults = MemoryDefaults()
    let transport = StubTodoTransport()
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("TickTickMoveTests-\(UUID().uuidString)", isDirectory: true)
    let cache: TickTickTodoCache
    let service: NookTickTickTodoService

    /// `savedList` is the list an older build saved when one was picked.
    /// `fileStore` stands in for the token file when a test needs one that
    /// misbehaves.
    init(
        oldToken: String? = TickTickMoveHarness.oldToken,
        savedList: Bool = true,
        fileStore: (any NookTodoTokenStoring)? = nil
    ) {
        old = CountingOldStore(token: oldToken)
        file = NookTodoTokenFile(
            folder: root.appendingPathComponent("Secrets", isDirectory: true),
            fileName: NookTodoTokenFile.fileName(kind: NookTodoTokenFile.tickTickKind, bundleID: "app.test")
        )
        if savedList {
            defaults.set(TickTickFixtures.workID, forKey: NookTickTickTodoService.Keys.listID)
        }
        cache = TickTickTodoCache(directory: root.appendingPathComponent("Cache", isDirectory: true))
        service = NookTickTickTodoService(
            defaults: defaults, transport: transport, tokenStore: fileStore ?? file,
            tokenMove: NookTodoTokenMove(oldStore: old),
            cache: cache
        )
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    /// Stops the service, lets the background cache write that a load starts
    /// land, then removes the folder. Nothing rewrites it afterwards.
    func finish() async {
        service.setActive(false)
        for _ in 0..<20 { await Task.yield() }
        _ = await cache.load()
        try? FileManager.default.removeItem(at: root)
    }

    func activate() async {
        service.setActive(true)
        await service.setupTask?.value
    }

    func serveAccount() {
        transport.setResponder { request, _ in
            switch request.route {
            case "GET /open/v1/project": .json(TickTickFixtures.list([]))
            default: .json(TickTickFixtures.projectData(tasks: []))
            }
        }
    }

    var savedSettings: String {
        defaults.dictionaryRepresentation().map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
    }
}

// MARK: - The button's rule

@Suite struct NookTodoTokenMoveOfferTests {
    @Test func theButtonShowsOnlyWhenAllFourThingsHold() {
        for bits in 0..<16 {
            let offer = NookTodoTokenMoveOffer(
                isNotConnected: bits & 1 != 0,
                hasSavedAccountSign: bits & 2 != 0,
                isKeychainSettled: bits & 4 != 0,
                canMove: bits & 8 != 0
            )
            let expected = bits & 1 != 0 && bits & 2 != 0 && bits & 4 == 0 && bits & 8 != 0
            #expect(offer.isShown == expected, "bits \(bits)")
        }
    }

    @Test func itShowsForNotConnectedWithASignAndAnUnsettledKeychain() {
        let shown = NookTodoTokenMoveOffer(
            isNotConnected: true, hasSavedAccountSign: true, isKeychainSettled: false, canMove: true
        )
        #expect(shown.isShown)
    }

    @Test func theMoveReadsOldItemsOnlyThroughTheStoreItHolds() throws {
        let old = CountingOldStore(token: "old")
        let file = CountingOldStore()
        let move = NookTodoTokenMove(oldStore: old)

        #expect(try move.bringOver(to: file) == .moved)
        #expect(file.token == "old")
        #expect(old.token == nil)
        #expect(old.readCount == 1)
        #expect(try NookTodoTokenMove.none.bringOver(to: file) == .nothingSaved)
        #expect(NookTodoTokenMove.none.hasOldStore == false)
    }

    @Test func aFailedWriteLeavesTheOldItemAlone() throws {
        let old = CountingOldStore(token: "old")
        let file = InMemoryTodoTokenStore()
        file.failure = NookTodoTokenFileError(.cannotSave)

        #expect(throws: NookTodoTokenFileError.self) {
            try NookTodoTokenMove(oldStore: old).bringOver(to: file)
        }
        #expect(old.token == "old")
        #expect(old.deleteCount == 0)
    }

    @Test func aFileThatSavesButKeepsNothingLeavesTheOldItemAlone() throws {
        let old = CountingOldStore(token: "old")

        #expect(throws: NookTodoTokenFileError.self) {
            try NookTodoTokenMove(oldStore: old).bringOver(to: ForgetfulTokenStore())
        }
        #expect(old.token == "old")
        #expect(old.deleteCount == 0)
        #expect(old.readCount == 1)
    }

    @Test func aFileThatHoldsSomethingElseAfterTheSaveLeavesTheOldItemAlone() throws {
        let old = CountingOldStore(token: "old")
        let other = InMemoryTodoTokenStore(token: "not the token")
        // Saving does nothing here, and the read hands back another token.
        let file = SaveIgnoringStore(readsAs: other)

        #expect(throws: NookTodoTokenFileError.self) {
            try NookTodoTokenMove(oldStore: old).bringOver(to: file)
        }
        #expect(old.deleteCount == 0)
    }

    @Test func aTokenTheFileWouldRefuseLeavesTheOldItemAlone() throws {
        let old = CountingOldStore(token: "has a space")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenMoveRefusal-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = NookTodoTokenFile(folder: root.appendingPathComponent("Secrets"), fileName: "refusal.token")

        #expect(throws: NookTodoTokenFileError.self) {
            try NookTodoTokenMove(oldStore: old).bringOver(to: file)
        }
        #expect(old.token == "has a space")
        #expect(old.deleteCount == 0)
    }

    @Test func anItemThatWillNotBeDeletedStillCountsAsMovedToTheFile() throws {
        let old = CountingOldStore(token: "old")
        old.failDeletes(with: NookTodoKeychainError(status: -25308))
        let file = CountingOldStore()

        #expect(try NookTodoTokenMove(oldStore: old).bringOver(to: file) == .movedButItemRemains)
        #expect(file.token == "old")
    }
}

// MARK: - Notion

@MainActor
@Suite struct NotionTokenMoveTests {
    @Test func launchReadsOnlyTheFileAndNeverTheKeychain() async {
        let harness = NotionMoveHarness()

        await harness.activate()

        #expect(harness.old.readCount == 0)
        #expect(harness.old.saveCount == 0)
        #expect(harness.old.deleteCount == 0)
        #expect(harness.service.state == .noToken)
        #expect(harness.service.hasToken == false)
        #expect(harness.service.tokenMoveOffer.isShown)
        #expect(harness.transport.requests.isEmpty)
        #expect(harness.service.connection == .unavailable(
            message: LanguageManager.shared.t("nook.todo.token.state.movePending")
        ))
    }

    @Test func switchingTheSourceOnAndOffAgainStillNeverReadsTheKeychain() async {
        let harness = NotionMoveHarness()

        for _ in 0..<3 {
            await harness.activate()
            harness.service.setActive(false)
        }

        #expect(harness.old.readCount == 0)
        #expect(harness.old.deleteCount == 0)
    }

    @Test func thePressReadsOnceWritesTheFileAndDeletesTheKeychainItem() async throws {
        let harness = NotionMoveHarness()
        await harness.activate()

        await harness.service.bringTokenOver()

        #expect(harness.old.readCount == 1)
        #expect(harness.old.deleteCount == 1)
        #expect(harness.old.token == nil, "the Keychain item is gone")
        #expect(try harness.file.read() == NotionMoveHarness.oldToken)
        #expect(harness.service.hasToken)
        #expect(harness.service.tokenMoveOffer.isShown == false)
        #expect(harness.defaults.bool(forKey: NookNotionTodoService.Keys.keychainSettled))
        #expect(harness.service.moveFailed == false)
    }

    @Test func aSecondPressDoesNothing() async {
        let harness = NotionMoveHarness()
        await harness.activate()
        await harness.service.bringTokenOver()

        await harness.service.bringTokenOver()
        await harness.service.bringTokenOver()

        #expect(harness.old.readCount == 1)
        #expect(harness.old.deleteCount == 1)
    }

    @Test func twoPressesAtOnceReadOnce() async {
        let harness = NotionMoveHarness()
        await harness.activate()

        async let first: Void = harness.service.bringTokenOver()
        async let second: Void = harness.service.bringTokenOver()
        _ = await (first, second)

        #expect(harness.old.readCount == 1)
    }

    @Test func aRelaunchAfterTheMoveReadsOnlyTheFile() async {
        let harness = NotionMoveHarness()
        await harness.activate()
        await harness.service.bringTokenOver()
        harness.service.setActive(false)

        await harness.activate()

        #expect(harness.service.hasToken)
        #expect(harness.old.readCount == 1, "still just the one press")
    }

    @Test func theMovedTokenIsInThePrivateFileAndNowhereElse() async throws {
        let harness = NotionMoveHarness()
        await harness.activate()
        await harness.service.bringTokenOver()

        var info = stat()
        #expect(lstat(harness.file.fileURL.path, &info) == 0)
        #expect(Int(info.st_mode & 0o777) == 0o600)
        #expect(!harness.savedSettings.contains(NotionMoveHarness.oldToken))
    }

    @Test func connectingANewAccountWritesTheFileAndNeverTouchesTheKeychain() async throws {
        let harness = NotionMoveHarness()
        harness.serveAccount()
        await harness.activate()

        await harness.service.connect(token: "  ntn_fresh_token\n")

        #expect(try harness.file.read() == "ntn_fresh_token")
        #expect(harness.service.hasToken)
        #expect(harness.old.readCount == 0)
        #expect(harness.old.saveCount == 0)
        #expect(harness.old.deleteCount == 0)
        #expect(harness.old.token == NotionMoveHarness.oldToken, "the old item is left as it was")
        #expect(!harness.savedSettings.contains("ntn_fresh_token"))
    }

    @Test func noButtonWithoutASignThatAnAccountWasConnected() async {
        let harness = NotionMoveHarness(savedAccount: false)

        await harness.activate()

        #expect(harness.service.tokenMoveOffer.isShown == false)
        #expect(harness.old.readCount == 0)
    }

    @Test func aSavedDatabaseOrAnOfflineCopyIsASignToo() async throws {
        let withDatabase = NotionMoveHarness(savedAccount: false)
        withDatabase.defaults.set(NotionFixtures.dataSourceID, forKey: NookNotionTodoService.Keys.dataSourceID)
        await withDatabase.activate()
        #expect(withDatabase.service.tokenMoveOffer.isShown)

        let withCopy = NotionMoveHarness(savedAccount: false)
        try await withCopy.cache.save(NotionTodoSnapshot(
            dataSourceID: "x", databaseTitle: "To-Do", savedAt: Date(timeIntervalSince1970: 0), items: []
        ))
        await withCopy.activate()
        #expect(withCopy.service.tokenMoveOffer.isShown)
        #expect(withCopy.old.readCount == 0)
    }

    @Test func noButtonWhenTheFileHoldsATokenOrTheKeychainIsSettled() async throws {
        let withToken = NotionMoveHarness()
        try withToken.file.save("ntn_in_the_file")
        await withToken.activate()
        #expect(withToken.service.hasToken)
        #expect(withToken.service.tokenMoveOffer.isShown == false)

        let settled = NotionMoveHarness()
        settled.defaults.set(true, forKey: NookNotionTodoService.Keys.keychainSettled)
        await settled.activate()
        #expect(settled.service.state == .noToken)
        #expect(settled.service.tokenMoveOffer.isShown == false)
        #expect(settled.old.readCount == 0)
    }

    @Test func noButtonWhileTheSourceIsOffOrWithNoWayToMove() async {
        let off = NotionMoveHarness()
        #expect(off.service.tokenMoveOffer.isShown == false, "the source is not active")

        let demo = NotionMoveHarness(moveWorks: false)
        await demo.activate()
        #expect(demo.service.tokenMoveOffer.isShown == false)
        await demo.service.bringTokenOver()
        #expect(demo.old.readCount == 0)
    }

    @Test func aRefusedPasteLeavesTheButtonWhereItWas() async {
        let harness = NotionMoveHarness()
        harness.transport.setResponder { _, _ in .json("{\"code\":\"unauthorized\"}", status: 401) }
        await harness.activate()
        #expect(harness.service.tokenMoveOffer.isShown)

        await harness.service.connect(token: "ntn_wrong")

        #expect(harness.service.state == .invalidToken)
        #expect(harness.service.hasToken == false)
        #expect(harness.service.tokenMoveOffer.isShown, "the saved token is still on offer")
        #expect(harness.old.readCount == 0)
    }

    @Test func aFileThatCannotBeUsedLeavesTheButtonAndAPressReplacesIt() async throws {
        let harness = NotionMoveHarness()
        try harness.file.save("ntn_stale_token")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: harness.file.fileURL.path)
        await harness.activate()
        #expect(harness.service.state == .keychainUnavailable)
        #expect(harness.service.tokenMoveOffer.isShown)

        await harness.service.bringTokenOver()

        #expect(try harness.file.read() == NotionMoveHarness.oldToken)
        #expect(harness.service.hasToken)
        #expect(harness.service.tokenProblem == nil)
        var info = stat()
        #expect(lstat(harness.file.fileURL.path, &info) == 0)
        #expect(Int(info.st_mode & 0o777) == 0o600)
    }

    @Test func aPressWhileAPastedTokenIsBeingCheckedDoesNothing() async {
        let harness = NotionMoveHarness()
        let gate = ReleaseGate()
        harness.serveAccount()
        harness.transport.setHold { _ in await gate.wait() }
        await harness.activate()

        let connecting = Task { await harness.service.connect(token: "ntn_new_token") }
        #expect(await eventually { harness.service.state == .connecting && !harness.transport.requests.isEmpty })
        await harness.service.bringTokenOver()
        await gate.open()
        await connecting.value

        #expect(harness.old.readCount == 0)
        #expect(harness.service.hasToken)
        await harness.finish()
    }

    // MARK: A second action while the prompt is up

    @Test func aConnectWhileTheMacOSPromptIsUpDoesNothingAndIsNotOverwritten() async throws {
        let harness = NotionMoveHarness()
        harness.serveAccount()
        await harness.activate()
        harness.old.holdReads()
        let pressing = Task { await harness.service.bringTokenOver() }
        #expect(await eventually { harness.old.readCount == 1 })
        #expect(harness.service.isMovingToken)

        await harness.service.connect(token: "ntn_pasted_meanwhile")
        #expect(harness.transport.requests.isEmpty, "nothing was sent for it")
        #expect(try harness.file.read() == nil, "nothing was written for it")

        harness.old.releaseReads()
        await pressing.value

        #expect(try harness.file.read() == NotionMoveHarness.oldToken)
        #expect(harness.service.isMovingToken == false)
        #expect(harness.service.hasToken)
    }

    @Test func aSourceSwitchWhileThePromptIsUpStillEndsConnected() async throws {
        let harness = NotionMoveHarness()
        await harness.activate()
        harness.old.holdReads()
        let pressing = Task { await harness.service.bringTokenOver() }
        #expect(await eventually { harness.old.readCount == 1 })

        // Away and back: the new activation reads a file with no token yet.
        harness.service.setActive(false)
        await harness.activate()
        #expect(harness.service.state == .noToken)
        harness.old.releaseReads()
        await pressing.value

        #expect(harness.service.isActive)
        #expect(harness.service.hasToken, "the card is not left on not connected")
        #expect(try harness.file.read() == NotionMoveHarness.oldToken)
        #expect(harness.defaults.bool(forKey: NookNotionTodoService.Keys.keychainSettled))
    }

    @Test func aSourceSwitchedOffForGoodWhileThePromptIsUpLeavesTheSourceOff() async throws {
        let harness = NotionMoveHarness()
        await harness.activate()
        harness.old.holdReads()
        let pressing = Task { await harness.service.bringTokenOver() }
        #expect(await eventually { harness.old.readCount == 1 })

        harness.service.setActive(false)
        harness.old.releaseReads()
        await pressing.value

        #expect(harness.service.isActive == false)
        #expect(harness.service.state == .inactive)
        #expect(try harness.file.read() == NotionMoveHarness.oldToken, "the token still came over")
    }

    // MARK: Failures

    @Test func aKeychainThatWillNotAnswerKeepsTheButtonAndTheOldItem() async throws {
        let harness = NotionMoveHarness()
        harness.old.failReads(with: NookTodoKeychainError(status: -128))
        await harness.activate()

        await harness.service.bringTokenOver()

        #expect(harness.service.moveFailed)
        #expect(harness.service.state == .noToken)
        #expect(harness.service.tokenMoveOffer.isShown, "the user can try again")
        #expect(try harness.file.read() == nil)
        #expect(harness.old.token == NotionMoveHarness.oldToken)
        #expect(harness.old.deleteCount == 0)

        harness.old.failReads(with: nil)
        await harness.service.bringTokenOver()
        #expect(harness.service.moveFailed == false)
        #expect(try harness.file.read() == NotionMoveHarness.oldToken)
    }

    @Test func aKeychainWithNothingInItSettlesQuietly() async {
        let harness = NotionMoveHarness(oldToken: nil)
        await harness.activate()

        await harness.service.bringTokenOver()

        #expect(harness.old.readCount == 1)
        #expect(harness.service.state == .noToken)
        #expect(harness.service.tokenMoveOffer.isShown == false)
        await harness.service.bringTokenOver()
        #expect(harness.old.readCount == 1)
    }

    @Test func aFileThatCannotBeWrittenKeepsTheKeychainItem() async {
        let harness = NotionMoveHarness(fileStore: UnwritableTokenStore())
        await harness.activate()

        await harness.service.bringTokenOver()

        #expect(harness.service.state == .keychainUnavailable)
        #expect(harness.service.tokenProblem?.reason == .cannotSave)
        #expect(harness.old.token == NotionMoveHarness.oldToken)
        #expect(harness.old.deleteCount == 0)
    }

    @Test func aFileThatSavesButKeepsNothingKeepsTheKeychainItem() async {
        let harness = NotionMoveHarness(fileStore: ForgetfulTokenStore())
        await harness.activate()

        await harness.service.bringTokenOver()

        #expect(harness.service.state == .keychainUnavailable)
        #expect(harness.service.tokenProblem?.reason == .cannotSave)
        #expect(harness.service.hasToken == false)
        #expect(harness.old.token == NotionMoveHarness.oldToken)
        #expect(harness.old.deleteCount == 0)
        #expect(harness.defaults.bool(forKey: NookNotionTodoService.Keys.keychainSettled) == false)
    }

    @Test func aFileThatIsNotSafeIsReportedWithItsReasonAndNotSilently() async throws {
        let harness = NotionMoveHarness()
        try harness.file.save("ntn_in_the_file")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: harness.file.fileURL.path
        )

        await harness.activate()

        #expect(harness.service.state == .keychainUnavailable)
        #expect(harness.service.hasToken == false)
        #expect(harness.service.tokenProblem?.reason == .readableByOthers)
        #expect(harness.service.tokenProblemText == LanguageManager.shared.t("nook.todo.token.problem.readableByOthers"))
        #expect(harness.old.readCount == 0)
        #expect(harness.transport.requests.isEmpty)
        if case .unavailable(let message) = harness.service.connection {
            #expect(message.contains(LanguageManager.shared.t("nook.todo.token.problem.readableByOthers")))
            #expect(!message.contains("ntn_in_the_file"))
        } else {
            Issue.record("the card should say it is unavailable")
        }
    }

    @Test func theTourShowsTheReasonTheSettingsPaneShows() async throws {
        let harness = NotionMoveHarness()
        try harness.file.save("ntn_in_the_file")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: harness.file.fileURL.path)
        await harness.activate()
        let hub = NookTodoHub(defaults: MemoryDefaults(), notion: harness.service)
        hub.selectedKind = .notion
        let connector = OnboardingTodoConnector(
            hub: hub,
            reminders: NookRemindersService(access: FakeEventKitPermission(status: .notDetermined).access),
            lang: LanguageManager.shared
        )

        let message = try #require(connector.setup().message)

        let lang = LanguageManager.shared
        #expect(message.isProblem)
        #expect(message.text.contains(lang.t("nook.todo.notion.state.keychain")))
        #expect(message.text.contains(lang.t("nook.todo.token.problem.readableByOthers")))
        #expect(!message.text.contains("ntn_in_the_file"))
    }

    // MARK: Disconnecting

    @Test func disconnectingDeletesTheFileAndAnUnmovedKeychainItem() async throws {
        let harness = NotionMoveHarness()
        try harness.file.save("ntn_in_the_file")
        await harness.activate()
        #expect(harness.service.hasToken)

        await harness.service.disconnect()

        #expect(try harness.file.read() == nil)
        #expect(harness.old.token == nil)
        #expect(harness.old.deleteCount == 1)
        #expect(harness.old.readCount == 0, "a delete never reads")
        #expect(harness.service.state == .noToken)
        #expect(harness.service.tokenMoveOffer.isShown == false)
    }

    @Test func disconnectingAfterTheMoveLeavesTheKeychainAlone() async throws {
        let harness = NotionMoveHarness()
        await harness.activate()
        await harness.service.bringTokenOver()

        await harness.service.disconnect()

        #expect(try harness.file.read() == nil)
        #expect(harness.old.deleteCount == 1, "only the move's own delete")
        #expect(harness.old.readCount == 1)
    }

    @Test func aKeychainDeleteThatFailsOnDisconnectIsReported() async throws {
        let harness = NotionMoveHarness()
        try harness.file.save("ntn_in_the_file")
        harness.old.failDeletes(with: NookTodoKeychainError(status: -25308))
        await harness.activate()

        await harness.service.disconnect()

        #expect(try harness.file.read() == nil, "the file is gone")
        #expect(harness.service.state == .keychainUnavailable)
        #expect(harness.service.tokenProblem?.reason == .oldItemRemains)
        #expect(harness.defaults.bool(forKey: NookNotionTodoService.Keys.keychainSettled) == false)
    }

    @Test func aFileThatCannotBeDeletedIsReportedAsThatAndTheOldItemIsLeftAlone() async {
        let harness = NotionMoveHarness(fileStore: UndeletableTokenStore(token: "ntn_in_the_file"))
        await harness.activate()
        #expect(harness.service.hasToken)

        await harness.service.disconnect()

        #expect(harness.service.state == .keychainUnavailable)
        #expect(harness.service.tokenProblem?.reason == .cannotRemove)
        #expect(harness.old.deleteCount == 0)
    }
}

// MARK: - TickTick

@MainActor
@Suite struct TickTickTokenMoveTests {
    @Test func launchReadsOnlyTheFileAndNeverTheKeychain() async {
        let harness = TickTickMoveHarness()

        await harness.activate()

        #expect(harness.old.readCount == 0)
        #expect(harness.old.saveCount == 0)
        #expect(harness.old.deleteCount == 0)
        #expect(harness.service.state == .noToken)
        #expect(harness.service.tokenMoveOffer.isShown)
        #expect(harness.transport.requests.isEmpty)
        #expect(harness.service.connection == .unavailable(
            message: LanguageManager.shared.t("nook.todo.token.state.movePending")
        ))
    }

    @Test func thePressReadsOnceWritesTheFileAndDeletesTheKeychainItem() async throws {
        let harness = TickTickMoveHarness()
        harness.serveAccount()
        await harness.activate()

        await harness.service.bringTokenOver()

        #expect(harness.old.readCount == 1)
        #expect(harness.old.deleteCount == 1)
        #expect(harness.old.token == nil)
        #expect(try harness.file.read() == TickTickMoveHarness.oldToken)
        #expect(harness.service.hasToken)
        #expect(harness.service.tokenMoveOffer.isShown == false)
        #expect(harness.defaults.bool(forKey: NookTickTickTodoService.Keys.keychainSettled))
        #expect(!harness.savedSettings.contains(TickTickMoveHarness.oldToken))
        await harness.finish()
    }

    @Test func aSecondPressDoesNothing() async {
        let harness = TickTickMoveHarness()
        harness.serveAccount()
        await harness.activate()
        await harness.service.bringTokenOver()

        await harness.service.bringTokenOver()

        #expect(harness.old.readCount == 1)
        #expect(harness.old.deleteCount == 1)
        await harness.finish()
    }

    @Test func connectingANewAccountWritesTheFileAndNeverTouchesTheKeychain() async throws {
        let harness = TickTickMoveHarness()
        harness.serveAccount()
        await harness.activate()

        await harness.service.connect(token: "tt_fresh_token")

        #expect(try harness.file.read() == "tt_fresh_token")
        #expect(harness.service.hasToken)
        #expect(harness.old.readCount == 0)
        #expect(harness.old.saveCount == 0)
        #expect(harness.old.deleteCount == 0)
        #expect(harness.old.token == TickTickMoveHarness.oldToken)
        #expect(!harness.savedSettings.contains("tt_fresh_token"))
        await harness.finish()
    }

    @Test func noButtonWithoutASignThatAnAccountWasConnected() async {
        let harness = TickTickMoveHarness(savedList: false)

        await harness.activate()

        #expect(harness.service.tokenMoveOffer.isShown == false)
        #expect(harness.old.readCount == 0)
    }

    @Test func aRefusedPasteLeavesTheButtonWhereItWas() async {
        let harness = TickTickMoveHarness()
        harness.transport.setResponder { _, _ in .json("{\"error\":\"invalid_token\"}", status: 401) }
        await harness.activate()
        #expect(harness.service.tokenMoveOffer.isShown)

        await harness.service.connect(token: "tt_wrong")

        #expect(harness.service.state == .invalidToken)
        #expect(harness.service.hasToken == false)
        #expect(harness.service.tokenMoveOffer.isShown, "the saved token is still on offer")
        #expect(harness.old.readCount == 0)
        await harness.finish()
    }

    @Test func aKeychainThatWillNotAnswerKeepsTheButton() async throws {
        let harness = TickTickMoveHarness()
        harness.old.failReads(with: NookTodoKeychainError(status: -128))
        await harness.activate()

        await harness.service.bringTokenOver()

        #expect(harness.service.moveFailed)
        #expect(harness.service.tokenMoveOffer.isShown)
        #expect(try harness.file.read() == nil)
        #expect(harness.old.token == TickTickMoveHarness.oldToken)
    }

    @Test func aFileThatSavesButKeepsNothingKeepsTheKeychainItem() async {
        let harness = TickTickMoveHarness(fileStore: ForgetfulTokenStore())
        await harness.activate()

        await harness.service.bringTokenOver()

        #expect(harness.service.state == .keychainUnavailable)
        #expect(harness.service.tokenProblem?.reason == .cannotSave)
        #expect(harness.old.token == TickTickMoveHarness.oldToken)
        #expect(harness.old.deleteCount == 0)
    }

    // MARK: A second action while the prompt is up

    @Test func aConnectWhileTheMacOSPromptIsUpDoesNothingAndIsNotOverwritten() async throws {
        let harness = TickTickMoveHarness()
        harness.serveAccount()
        await harness.activate()
        harness.old.holdReads()
        let pressing = Task { await harness.service.bringTokenOver() }
        #expect(await eventually { harness.old.readCount == 1 })
        #expect(harness.service.isMovingToken)

        await harness.service.connect(token: "tt_pasted_meanwhile")
        #expect(harness.transport.requests.isEmpty, "nothing was sent for it")
        #expect(try harness.file.read() == nil, "nothing was written for it")

        harness.old.releaseReads()
        await pressing.value

        #expect(try harness.file.read() == TickTickMoveHarness.oldToken)
        #expect(harness.service.isMovingToken == false)
        #expect(harness.service.hasToken)
        await harness.finish()
    }

    @Test func aSourceSwitchWhileThePromptIsUpStillEndsConnected() async throws {
        let harness = TickTickMoveHarness()
        harness.serveAccount()
        await harness.activate()
        harness.old.holdReads()
        let pressing = Task { await harness.service.bringTokenOver() }
        #expect(await eventually { harness.old.readCount == 1 })

        harness.service.setActive(false)
        await harness.activate()
        #expect(harness.service.state == .noToken)
        harness.old.releaseReads()
        await pressing.value

        #expect(harness.service.isActive)
        #expect(harness.service.hasToken, "the card is not left on not connected")
        #expect(try harness.file.read() == TickTickMoveHarness.oldToken)
        await harness.finish()
    }

    // MARK: Disconnecting

    @Test func disconnectingDeletesTheFileAndAnUnmovedKeychainItem() async throws {
        let harness = TickTickMoveHarness()
        try harness.file.save("tt_in_the_file")
        harness.serveAccount()
        await harness.activate()
        #expect(harness.service.hasToken)

        await harness.service.disconnect()

        #expect(try harness.file.read() == nil)
        #expect(harness.old.token == nil)
        #expect(harness.old.deleteCount == 1)
        #expect(harness.old.readCount == 0)
        #expect(harness.service.state == .noToken)
        #expect(harness.service.tokenRemovalFailed == false)
        await harness.finish()
    }

    @Test func anOldItemThatWillNotGoFinishesTheDisconnectAndSaysWhatIsLeft() async throws {
        let harness = TickTickMoveHarness()
        try harness.file.save("tt_in_the_file")
        harness.old.failDeletes(with: NookTodoKeychainError(status: -25308))
        harness.serveAccount()
        await harness.activate()
        #expect(harness.service.hasToken)

        await harness.service.disconnect()

        #expect(try harness.file.read() == nil, "the file is gone")
        #expect(harness.service.hasToken == false, "the session ended with it")
        #expect(harness.service.token == nil)
        #expect(harness.service.tokenRemovalFailed == false, "the file did come off")
        #expect(harness.service.state == .keychainUnavailable)
        #expect(harness.service.tokenProblem?.reason == .oldItemRemains)
        #expect(harness.defaults.bool(forKey: NookTickTickTodoService.Keys.keychainSettled) == false)
        await harness.finish()
    }

    @Test func aFileThatCannotBeRemovedKeepsTheSessionAndLeavesTheOldItemAlone() async {
        let harness = TickTickMoveHarness(fileStore: UndeletableTokenStore(token: "tt_in_the_file"))
        harness.serveAccount()
        await harness.activate()
        #expect(harness.service.hasToken)

        await harness.service.disconnect()

        #expect(harness.service.tokenRemovalFailed)
        #expect(harness.service.hasToken, "the session stays as it was")
        #expect(harness.old.deleteCount == 0)
        await harness.finish()
    }

    @Test func aFileThatIsNotSafeIsReportedWithItsReason() async throws {
        let harness = TickTickMoveHarness()
        let target = harness.root.appendingPathComponent("elsewhere.txt")
        try FileManager.default.createDirectory(at: harness.file.folder, withIntermediateDirectories: true)
        try Data("tt_in_the_file".utf8).write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        try FileManager.default.createSymbolicLink(at: harness.file.fileURL, withDestinationURL: target)

        await harness.activate()

        #expect(harness.service.state == .keychainUnavailable)
        #expect(harness.service.tokenProblem?.reason == .symbolicLink)
        #expect(harness.old.readCount == 0)
        #expect(harness.transport.requests.isEmpty)
    }

    @Test func theTourShowsTheReasonTheSettingsPaneShows() async throws {
        let harness = TickTickMoveHarness()
        let target = harness.root.appendingPathComponent("elsewhere.txt")
        try FileManager.default.createDirectory(at: harness.file.folder, withIntermediateDirectories: true)
        try Data("tt_in_the_file".utf8).write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        try FileManager.default.createSymbolicLink(at: harness.file.fileURL, withDestinationURL: target)
        await harness.activate()
        let hub = NookTodoHub(defaults: MemoryDefaults(), tickTick: harness.service)
        hub.selectedKind = .tickTick
        let connector = OnboardingTodoConnector(
            hub: hub,
            reminders: NookRemindersService(access: FakeEventKitPermission(status: .notDetermined).access),
            lang: LanguageManager.shared
        )

        let message = try #require(connector.setup().message)

        let lang = LanguageManager.shared
        #expect(message.isProblem)
        #expect(message.text.contains(lang.t("nook.todo.ticktick.state.keychain")))
        #expect(message.text.contains(lang.t("nook.todo.token.problem.symbolicLink")))
    }
}

// MARK: - The tour's sentence

@MainActor
@Suite struct TourTokenProblemTests {
    @Test func aTokenProblemAddsItsReasonOnlyToTheTokenFileState() {
        let lang = LanguageManager.shared
        let problem = NookTodoTokenFileError(.unsafeFolder)
        let reason = lang.t(problem.messageKey)

        let withReason = OnboardingTodoMessage.notion(.keychainUnavailable, lang: lang, tokenProblem: problem)
        let without = OnboardingTodoMessage.notion(.keychainUnavailable, lang: lang)
        let other = OnboardingTodoMessage.notion(.invalidToken, lang: lang, tokenProblem: problem)

        #expect(withReason?.text.hasSuffix(reason) == true)
        #expect(without?.text == lang.t(NotionTodoState.keychainUnavailable.messageKey))
        #expect(other?.text.contains(reason) == false, "only that state carries a reason")
        let tickTick = OnboardingTodoMessage.tickTick(.keychainUnavailable, lang: lang, tokenProblem: problem)
        #expect(tickTick?.text.hasSuffix(reason) == true)
    }
}

// MARK: - Who can reach the Keychain

@MainActor
@Suite struct TokenMoveReachTests {
    @Test func aHubBuiltInATestRunHasNoWayToTheKeychain() {
        let hub = NookTodoHub(defaults: MemoryDefaults())

        #expect(hub.notion.tokenMove.hasOldStore == false)
        #expect(hub.tickTick.tokenMove.hasOldStore == false)
        #expect(NookTodoTokenMoves.forThisRun.notion.hasOldStore == false)
        #expect(NookTodoTokenMoves.forThisRun.tickTick.hasOldStore == false)
    }

    @Test func theRealHubGivesEachServiceItsOwnMove() throws {
        let hub = NookTodoHub(defaults: MemoryDefaults(), tokenMoves: .real)

        let notion = try #require(hub.notion.tokenMove.oldStore as? NookTodoKeychain)
        let tickTick = try #require(hub.tickTick.tokenMove.oldStore as? NookTodoKeychain)
        #expect(notion.service.hasSuffix(NookTodoKeychain.notionServiceSuffix))
        #expect(notion.account == "integration-token")
        #expect(tickTick.service.hasSuffix(NookTodoKeychain.tickTickServiceSuffix))
        #expect(tickTick.account == "api-token")
    }

    @Test func aSwappedPairIsCaught() throws {
        let swapped = NookTodoTokenMoves(notion: .tickTick, tickTick: .notion)
        let hub = NookTodoHub(defaults: MemoryDefaults(), tokenMoves: swapped)

        let notion = try #require(hub.notion.tokenMove.oldStore as? NookTodoKeychain)
        #expect(!notion.service.hasSuffix(NookTodoKeychain.notionServiceSuffix), "this is what a swap looks like")
    }

    @Test func theDemoCannotReachTheKeychainOrTheTokenFile() {
        let fixture = DemoFixture()
        defer { fixture.remove() }

        #expect(fixture.nook.todo.notion.tokenMove.hasOldStore == false)
        #expect(fixture.nook.todo.tickTick.tokenMove.hasOldStore == false)
        #expect(fixture.nook.todo.notion.tokenStore is DemoTokenStore)
        #expect(fixture.nook.todo.tickTick.tokenStore is DemoTokenStore)
    }
}

/// Holds work until a test lets go.
private actor ReleaseGate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}
