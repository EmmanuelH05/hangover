import Foundation
import OpenIslandCore
import Testing
@testable import OpenIslandApp

// The token file that replaced the Keychain for the Notion and TickTick
// tokens: where it lives, the modes it is written with, what a read refuses,
// and that no token text ever leaves in an error. Every test works in a
// temporary folder. None touches the Keychain, the network or a window.

/// A folder of its own per test. `defer { fixture.remove() }` cleans it up.
private struct TokenFileFixture {
    static let token = "ntn_secret_value_1234567890"

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("NookTodoTokenFileTests-\(UUID().uuidString)", isDirectory: true)
    let store: NookTodoTokenFile

    var folder: URL { store.folder }
    var fileURL: URL { store.fileURL }

    init(bundleID: String? = "app.test.hangover") {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = NookTodoTokenFile(
            folder: root.appendingPathComponent(NookTodoTokenFile.folderName, isDirectory: true),
            fileName: NookTodoTokenFile.fileName(kind: NookTodoTokenFile.notionKind, bundleID: bundleID)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    /// The permission bits of the item at `url`, without following a link.
    func mode(of url: URL) throws -> Int {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw CocoaError(.fileNoSuchFile) }
        return Int(info.st_mode & 0o7777)
    }

    func setMode(_ mode: Int, of url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }

    /// A file written by hand, the way another tool or the user might.
    func plantFile(_ text: String = TokenFileFixture.token, mode: Int = 0o600) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: fileURL)
        try setMode(mode, of: fileURL)
    }

    func reason<T>(of block: () throws -> T) -> NookTodoTokenFileError.Reason? {
        do {
            _ = try block()
            return nil
        } catch let error as NookTodoTokenFileError {
            return error.reason
        } catch {
            return nil
        }
    }
}

@Suite struct NookTodoTokenFileTests {
    // MARK: Round trip

    @Test func aSavedTokenReadsBack() throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }

        try fixture.store.save(TokenFileFixture.token)

        #expect(try fixture.store.read() == TokenFileFixture.token)
    }

    @Test func aMissingFileReadsAsNil() throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }

        #expect(try fixture.store.read() == nil, "no folder yet")

        try fixture.store.save("one")
        try fixture.store.delete()
        #expect(try fixture.store.read() == nil, "folder there, file gone")
    }

    @Test func anEmptyFileReadsAsNil() throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }
        try fixture.plantFile("")

        #expect(try fixture.store.read() == nil)
    }

    @Test func deletingRemovesTheFileAndAMissingFileIsFine() throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }
        try fixture.store.save(TokenFileFixture.token)

        try fixture.store.delete()
        try fixture.store.delete()

        #expect(!FileManager.default.fileExists(atPath: fixture.fileURL.path))
    }

    @Test func eachServiceHasAFileOfItsOwn() throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }
        let tickTick = NookTodoTokenFile(
            folder: fixture.folder,
            fileName: NookTodoTokenFile.fileName(kind: NookTodoTokenFile.tickTickKind, bundleID: "app.test.hangover")
        )

        try fixture.store.save("notion_token")
        try tickTick.save("ticktick_token")

        #expect(try fixture.store.read() == "notion_token")
        #expect(try tickTick.read() == "ticktick_token")
        try fixture.store.delete()
        #expect(try tickTick.read() == "ticktick_token", "deleting one leaves the other")
    }

    // MARK: Modes

    @Test func theFolderIsPrivateAndTheFileIsPrivateAfterASave() throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }

        try fixture.store.save(TokenFileFixture.token)

        #expect(try fixture.mode(of: fixture.folder) == 0o700)
        #expect(try fixture.mode(of: fixture.fileURL) == 0o600)
    }

    @Test func theModesAreSetAgainAfterAnOverwrite() throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }
        try fixture.store.save("first")
        // Something loosened both since the last write.
        try fixture.setMode(0o755, of: fixture.folder)
        try fixture.setMode(0o644, of: fixture.fileURL)

        try fixture.store.save("second")

        #expect(try fixture.store.read() == "second")
        #expect(try fixture.mode(of: fixture.folder) == 0o700)
        #expect(try fixture.mode(of: fixture.fileURL) == 0o600)
    }

    @Test func aSaveLeavesNoTemporaryFileBehind() throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }

        try fixture.store.save("first")
        try fixture.store.save("second")

        let names = try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path)
        #expect(names == [fixture.store.fileName])
    }

    // MARK: Refusals

    @Test func aSymbolicLinkIsRefused() throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }
        let target = fixture.root.appendingPathComponent("elsewhere.txt")
        try Data(TokenFileFixture.token.utf8).write(to: target)
        try fixture.setMode(0o600, of: target)
        try FileManager.default.createDirectory(at: fixture.folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: fixture.fileURL, withDestinationURL: target)

        #expect(fixture.reason { try fixture.store.read() } == .symbolicLink)
    }

    @Test func aFolderInTheFilesPlaceIsRefused() throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.fileURL, withIntermediateDirectories: true)

        #expect(fixture.reason { try fixture.store.read() } == .notRegularFile)
    }

    @Test(arguments: [0o644, 0o640, 0o604, 0o660, 0o606, 0o666, 0o670, 0o607])
    func aFileThatGroupOrOthersCanReachIsRefused(mode: Int) throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }
        try fixture.plantFile(mode: mode)

        #expect(fixture.reason { try fixture.store.read() } == .readableByOthers)

        try fixture.setMode(0o600, of: fixture.fileURL)
        #expect(try fixture.store.read() == TokenFileFixture.token, "mode 0600 is accepted")
    }

    @Test func aFileMuchBiggerThanAnyTokenIsRefused() throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }
        try fixture.plantFile(String(repeating: "x", count: NookTodoTokenFile.maxBytes + 1))

        #expect(fixture.reason { try fixture.store.read() } == .unreadable)
    }

    @Test func bytesThatAreNotTextAreRefused() throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.folder, withIntermediateDirectories: true)
        try Data([0xFF, 0xFE, 0xFD]).write(to: fixture.fileURL)
        try fixture.setMode(0o600, of: fixture.fileURL)

        #expect(fixture.reason { try fixture.store.read() } == .unreadable)
    }

    // MARK: Saving over what is there

    @Test func savingReplacesALinkAndNeverWritesThroughIt() throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }
        let target = fixture.root.appendingPathComponent("elsewhere.txt")
        try Data("untouched".utf8).write(to: target)
        try FileManager.default.createDirectory(at: fixture.folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: fixture.fileURL, withDestinationURL: target)

        try fixture.store.save(TokenFileFixture.token)

        #expect(try String(contentsOf: target, encoding: .utf8) == "untouched")
        #expect(try fixture.store.read() == TokenFileFixture.token)
        #expect(try fixture.mode(of: fixture.fileURL) == 0o600)
    }

    @Test func savingRefusesAFolderPlaceThatIsAFile() throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }
        try Data("a file".utf8).write(to: fixture.folder)

        #expect(fixture.reason { try fixture.store.save(TokenFileFixture.token) } == .unsafeFolder)
        #expect(fixture.reason { try fixture.store.read() } == .unsafeFolder)
        #expect(fixture.reason { try fixture.store.delete() } == .unsafeFolder)
        #expect(try String(contentsOf: fixture.folder, encoding: .utf8) == "a file")
    }

    @Test func savingRefusesAFolderPlaceThatIsALink() throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }
        let elsewhere = fixture.root.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: fixture.folder, withDestinationURL: elsewhere)

        #expect(fixture.reason { try fixture.store.save(TokenFileFixture.token) } == .unsafeFolder)
        #expect(try FileManager.default.contentsOfDirectory(atPath: elsewhere.path).isEmpty)
    }

    @Test func savingOverAFolderInTheFilesPlaceFailsAndLeavesNoTemporaryFile() throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.fileURL, withIntermediateDirectories: true)

        #expect(fixture.reason { try fixture.store.save(TokenFileFixture.token) } == .cannotSave)

        let names = try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path)
        #expect(names == [fixture.store.fileName], "only the folder that was there")
    }

    @Test func deletingALinkRemovesTheLinkAndNotItsTarget() throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }
        let target = fixture.root.appendingPathComponent("elsewhere.txt")
        try Data("kept".utf8).write(to: target)
        try FileManager.default.createDirectory(at: fixture.folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: fixture.fileURL, withDestinationURL: target)

        try fixture.store.delete()

        #expect(try String(contentsOf: target, encoding: .utf8) == "kept")
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: fixture.fileURL.path)) == nil)
    }

    // MARK: Blank space around a token

    @Test(arguments: ["\n", "\r\n", " ", "\t"])
    func aTrailingBlankIsDroppedOnRead(blank: String) throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }
        try fixture.plantFile(TokenFileFixture.token + blank)

        #expect(try fixture.store.read() == TokenFileFixture.token)
    }

    @Test func leadingAndTrailingBlankSpaceAreBothDropped() throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }
        try fixture.plantFile("  \n\t" + TokenFileFixture.token + "\n\n")

        #expect(try fixture.store.read() == TokenFileFixture.token)
    }

    @Test(arguments: ["\n", " \n\t ", "\r\n\r\n"])
    func aFileOfBlankSpaceOnlyReadsAsNil(blank: String) throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }
        try fixture.plantFile(blank)

        #expect(try fixture.store.read() == nil)
    }

    @Test(arguments: ["ntn_one two", "ntn_one\ntwo", "ntn_one\tntn_two"])
    func blankSpaceInsideATokenIsRefused(text: String) throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }
        try fixture.plantFile(text)

        #expect(fixture.reason { try fixture.store.read() } == .unreadable)
    }

    @Test(arguments: ["", " ", "has space", "has\nnewline", "trailing\n"])
    func aSaveRefusesWhatAReadWouldNotHandBack(token: String) throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }

        #expect(fixture.reason { try fixture.store.save(token) } == .cannotSave)
        #expect(!FileManager.default.fileExists(atPath: fixture.folder.path), "nothing was made")
    }

    @Test func aSaveHoldsToTheSameSizeLimitAsARead() throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }
        let largest = String(repeating: "x", count: NookTodoTokenFile.maxBytes)

        try fixture.store.save(largest)
        #expect(try fixture.store.read() == largest, "the limit itself is fine both ways")

        let tooBig = largest + "x"
        #expect(fixture.reason { try fixture.store.save(tooBig) } == .cannotSave)
        #expect(try fixture.store.read() == largest, "the refused save changed nothing")
    }

    // MARK: A folder that is a link, or not ours

    /// A real folder holding a valid token, and `Secrets` made a link to it.
    private func linkedFolderFixture() throws -> (fixture: TokenFileFixture, elsewhere: URL) {
        let fixture = TokenFileFixture()
        let elsewhere = fixture.root.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let planted = elsewhere.appendingPathComponent(fixture.store.fileName)
        try Data("ntn_planted_token".utf8).write(to: planted)
        try fixture.setMode(0o600, of: planted)
        try FileManager.default.createSymbolicLink(at: fixture.folder, withDestinationURL: elsewhere)
        return (fixture, elsewhere)
    }

    @Test func aLinkedFolderIsRefusedOnRead() throws {
        let (fixture, _) = try linkedFolderFixture()
        defer { fixture.remove() }

        #expect(fixture.reason { try fixture.store.read() } == .unsafeFolder)
    }

    @Test func aLinkedFolderIsRefusedOnSaveAndNothingGoesThroughIt() throws {
        let (fixture, elsewhere) = try linkedFolderFixture()
        defer { fixture.remove() }

        #expect(fixture.reason { try fixture.store.save("ntn_new_token") } == .unsafeFolder)

        let names = try FileManager.default.contentsOfDirectory(atPath: elsewhere.path)
        #expect(names == [fixture.store.fileName], "no temporary file went through the link")
        let planted = elsewhere.appendingPathComponent(fixture.store.fileName)
        #expect(try String(contentsOf: planted, encoding: .utf8) == "ntn_planted_token")
    }

    @Test func aLinkedFolderIsRefusedOnDeleteAndTheFileBehindItStays() throws {
        let (fixture, elsewhere) = try linkedFolderFixture()
        defer { fixture.remove() }

        #expect(fixture.reason { try fixture.store.delete() } == .unsafeFolder)

        let planted = elsewhere.appendingPathComponent(fixture.store.fileName)
        #expect(FileManager.default.fileExists(atPath: planted.path))
    }

    @Test func aFolderOfAnotherAccountIsRefusedOnEveryCall() throws {
        try #require(geteuid() != 0, "root owns /Library, which is the stand-in")
        // /Library belongs to root. Nothing is written there: the refusal
        // comes before the first byte.
        let store = NookTodoTokenFile(folder: URL(fileURLWithPath: "/Library", isDirectory: true), fileName: "x.token")

        #expect(Self.reason { try store.read() } == .unsafeFolder)
        #expect(Self.reason { try store.save("ntn_token") } == .unsafeFolder)
        #expect(Self.reason { try store.delete() } == .unsafeFolder)
    }

    @Test func aFileOfAnotherAccountIsRefusedOnRead() throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }
        try fixture.store.save("ntn_first")
        let strangers = NookTodoTokenFile(
            folder: fixture.folder, fileName: fixture.store.fileName, userID: geteuid() &+ 1
        )

        #expect(Self.reason { try strangers.read() } == .otherOwner)
        #expect(try fixture.store.read() == "ntn_first", "the owner reads it fine")
    }

    private static func reason<T>(of block: () throws -> T) -> NookTodoTokenFileError.Reason? {
        do {
            _ = try block()
            return nil
        } catch let error as NookTodoTokenFileError {
            return error.reason
        } catch {
            return nil
        }
    }

    // MARK: Leftovers of a save that was killed

    @Test func aSaveSweepsAwayTheTemporaryFilesOfAKilledSave() throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }
        try fixture.store.save("ntn_first")
        let leftover = fixture.folder.appendingPathComponent(".\(fixture.store.fileName).\(UUID().uuidString).tmp")
        try Data("ntn_left_behind".utf8).write(to: leftover)
        let unrelated = fixture.folder.appendingPathComponent("notes.txt")
        try Data("keep me".utf8).write(to: unrelated)

        try fixture.store.save("ntn_second")

        #expect(!FileManager.default.fileExists(atPath: leftover.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path), "only this file's temporaries go")
        #expect(try fixture.store.read() == "ntn_second")
    }

    @Test func aDeleteSweepsThemAwayToo() throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }
        try fixture.store.save("ntn_first")
        let leftover = fixture.folder.appendingPathComponent(".\(fixture.store.fileName).\(UUID().uuidString).tmp")
        try Data("ntn_left_behind".utf8).write(to: leftover)

        try fixture.store.delete()

        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path).isEmpty)
    }

    @Test func theOtherServicesTemporaryFilesAreLeftAlone() throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }
        let tickTick = NookTodoTokenFile(
            folder: fixture.folder,
            fileName: NookTodoTokenFile.fileName(kind: NookTodoTokenFile.tickTickKind, bundleID: "app.test.hangover")
        )
        try tickTick.save("tt_first")
        let theirs = fixture.folder.appendingPathComponent(".\(tickTick.fileName).\(UUID().uuidString).tmp")
        try Data("tt_in_flight".utf8).write(to: theirs)

        try fixture.store.save("ntn_first")
        try fixture.store.delete()

        #expect(FileManager.default.fileExists(atPath: theirs.path))
    }

    // MARK: Kept out of backups

    @Test func theFolderIsKeptOutOfBackupsWhenItIsMade() throws {
        let fixture = TokenFileFixture()
        defer { fixture.remove() }

        try fixture.store.save(TokenFileFixture.token)

        let values = try fixture.folder.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    // MARK: No token text in an error

    @Test func noErrorTheStoreThrowsCarriesTheTokenText() throws {
        var errors: [any Error] = []
        func collect(_ block: () throws -> Void) {
            do { try block() } catch { errors.append(error) }
        }

        // A link, a folder, a loose mode, a size and a bad encoding on read.
        let link = TokenFileFixture()
        defer { link.remove() }
        let target = link.root.appendingPathComponent("elsewhere.txt")
        try Data(TokenFileFixture.token.utf8).write(to: target)
        try link.setMode(0o600, of: target)
        try FileManager.default.createDirectory(at: link.folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link.fileURL, withDestinationURL: target)
        collect { _ = try link.store.read() }

        let folder = TokenFileFixture()
        defer { folder.remove() }
        try FileManager.default.createDirectory(at: folder.fileURL, withIntermediateDirectories: true)
        collect { _ = try folder.store.read() }
        collect { try folder.store.save(TokenFileFixture.token) }
        collect { try folder.store.delete() }

        let loose = TokenFileFixture()
        defer { loose.remove() }
        try loose.plantFile(mode: 0o644)
        collect { _ = try loose.store.read() }

        let big = TokenFileFixture()
        defer { big.remove() }
        try big.plantFile(TokenFileFixture.token + String(repeating: "x", count: NookTodoTokenFile.maxBytes))
        collect { _ = try big.store.read() }

        // A save that cannot make its folder.
        let blocked = TokenFileFixture()
        defer { blocked.remove() }
        try Data("a file".utf8).write(to: blocked.folder)
        collect { try blocked.store.save(TokenFileFixture.token) }

        #expect(errors.count == 7, "every scenario threw")
        for error in errors {
            let texts = [
                String(describing: error), String(reflecting: error), error.localizedDescription,
                (error as? NookTodoTokenFileError)?.messageKey ?? "",
            ]
            for text in texts {
                #expect(!text.contains(TokenFileFixture.token), "an error carried the token: \(text)")
                #expect(!text.contains("ntn_"))
            }
        }
    }

    @Test func everyReasonHasASentenceInEveryLanguage() throws {
        let reasons: [NookTodoTokenFileError.Reason] = [
            .symbolicLink, .notRegularFile, .readableByOthers, .otherOwner, .unsafeFolder, .unreadable, .cannotSave,
            .cannotRemove, .oldItemRemains,
        ]
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let path = root.appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: path) as? [String: String])
            for reason in reasons {
                let key = NookTodoTokenFileError(reason).messageKey
                #expect(table[key]?.isEmpty == false, "\(language) has no \(key)")
            }
        }
    }

    // MARK: Where the files live

    @Test func theFileNameKeepsADevCopyAndTheInstalledAppApart() {
        let dev = NookTodoTokenFile.fileName(kind: NookTodoTokenFile.notionKind, bundleID: "app.openisland.dev")
        let installed = NookTodoTokenFile.fileName(
            kind: NookTodoTokenFile.notionKind, bundleID: "com.emmanuelhernandez.hangover"
        )
        let unknown = NookTodoTokenFile.fileName(kind: NookTodoTokenFile.notionKind, bundleID: nil)

        #expect(dev == "app.openisland.dev.todo-notion.token")
        #expect(installed == "com.emmanuelhernandez.hangover.todo-notion.token")
        #expect(dev != installed)
        #expect(unknown == dev, "no bundle identifier falls back to the dev one")
    }

    @Test func aBundleIdentifierCannotChangeThePath() {
        let name = NookTodoTokenFile.fileName(kind: NookTodoTokenFile.tickTickKind, bundleID: "../../etc/passwd")

        #expect(!name.contains("/"))
        #expect(name.hasSuffix(".todo-ticktick.token"))
    }

    @Test func theServicesFilesSitInASecretsFolderOfTheStateFolder() {
        let notion = NookTodoTokenFile.notion
        let tickTick = NookTodoTokenFile.tickTick

        #expect(notion.folder == OpenIslandStateDirectory.url.appendingPathComponent("Secrets", isDirectory: true))
        #expect(tickTick.folder == notion.folder)
        #expect(notion.fileURL != tickTick.fileURL)
        #expect(notion.fileName.hasSuffix(".todo-notion.token"))
        #expect(tickTick.fileName.hasSuffix(".todo-ticktick.token"))
    }

    @MainActor
    @Test func theServicesDefaultToTheFileAndNeverToTheKeychain() {
        let notion = NookNotionTodoService(defaults: MemoryDefaults())
        let tickTick = NookTickTickTodoService(defaults: MemoryDefaults())

        #expect(notion.tokenStore is NookTodoTokenFile)
        #expect(tickTick.tokenStore is NookTodoTokenFile)
        #expect(notion.tokenMove.hasOldStore == false)
        #expect(tickTick.tokenMove.hasOldStore == false)
    }

    // MARK: The Keychain store stays in one place

    /// The Keychain asks again after every update for an app signed without a
    /// paid certificate, which is why the tokens moved to a file. The store
    /// stays in the code for the move and for nothing else. Each file that
    /// names it is listed, and a new one belongs here only on purpose.
    @Test func theKeychainStoreIsUsedInExactlyOnePlaceOutsideItsOwnFile() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        let enumerator = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        // Not \b: a dot between letters is no word boundary to Swift's regex,
        // and it has no lookbehind. A longer name such as the error type is
        // left out by the lookahead.
        let name = try Regex(#"NookTodoKeychain(?![A-Za-z0-9_])"#)
        let securityCall = try Regex(#"SecItem[A-Za-z]*"#)
        var naming: Set<String> = []
        var calling: Set<String> = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains(name) { naming.insert(url.lastPathComponent) }
            if text.contains(securityCall) { calling.insert(url.lastPathComponent) }
        }

        #expect(naming == ["NookTodoKeychain.swift", "NookTodoTokenMove.swift"], "the move is the one user")
        #expect(calling == ["NookTodoKeychain.swift"], "nothing else asks the Keychain")
    }

    @Test func theTokenMoveReachesTheKeychainOnlyThroughItsOwnStores() {
        #expect(NookTodoTokenMove.notion.hasOldStore)
        #expect(NookTodoTokenMove.tickTick.hasOldStore)
        #expect(NookTodoTokenMove.none.hasOldStore == false)
    }
}
