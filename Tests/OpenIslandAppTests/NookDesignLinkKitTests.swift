import Foundation
import Testing
@testable import OpenIslandApp

private typealias Samples = NookDesignSamples

private let figmaURL = "https://www.figma.com/design/KEY123/Brand-Kit?node-id=12-34&t=XyZ-1#Frame-One"

private func text(_ key: String, _ arguments: any CVarArg...) -> String {
    let format = LanguageManager.shared.t(key)
    return arguments.isEmpty ? format : String(format: format, arguments: arguments)
}

// MARK: - Adding and pasting

@MainActor
@Suite struct NookDesignLinkAddingTests {
    @Test func aTypedLinkIsSavedWithTheNameMadeFromItsAddress() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }

        guard case let .added(link) = fixture.kit.addLink(text: "  \(figmaURL)\n") else {
            Issue.record("not added")
            return
        }

        #expect(link.url == figmaURL)
        #expect(link.name == "www.figma.com/Brand-Kit")
        #expect(fixture.kit.links.links == [link])
        // Said once the link is on disk.
        #expect(await Samples.wait { fixture.kit.notice != nil })
        #expect(fixture.kit.notice?.kind == .done)
        #expect(fixture.kit.notice?.text == text("nook.design.notice.linkAdded", link.name))
        // Nothing was opened, copied or fetched.
        #expect(fixture.opener.opened.isEmpty)
        #expect(fixture.copies.texts.isEmpty)
        #expect(fixture.clipboard.textReads == 0)
    }

    @Test func aLinkWithNoSchemeIsSavedWithHttpsInFront() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        fixture.kit.addLink(text: "figma.com/board/KEY/Notes?node-id=1-2")
        #expect(fixture.kit.links.links.map(\.url) == ["https://figma.com/board/KEY/Notes?node-id=1-2"])
    }

    @Test(arguments: [
        ("", NookDesignLinkRefusal.empty),
        ("   \n", .empty),
        ("javascript:alert(1)", .notAWebLink),
        ("file:///etc/passwd", .notAWebLink),
        ("data:text/html,x", .notAWebLink),
        ("mailto:a@example.com", .notAWebLink),
        ("ftp://example.com/x", .notAWebLink),
        ("https://exa mple.com", .notAWebLink),
        ("localhost", .notAWebLink),
        ("#only-a-fragment", .notAWebLink),
        ("https://user:pw@example.com/", .hasCredentials),
        ("https://example.com/" + String(repeating: "a", count: 2_100), .tooLong),
    ] as [(String, NookDesignLinkRefusal)])
    func textThatIsNotALinkIsRefusedWithALineAndSavesNothing(input: String, reason: NookDesignLinkRefusal) async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }

        #expect(fixture.kit.addLink(text: input) == .refused(reason))

        #expect(fixture.kit.links.links.isEmpty)
        #expect(fixture.kit.notice?.kind == .info)
        #expect(fixture.kit.notice?.text == text(reason.noticeKey))
        await fixture.kit.flush()
        #expect(!FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent(NookDesignLinkFile.fileName).path))
    }

    @Test func everyRefusalHasItsOwnLineInEveryLanguage() throws {
        let reasons: [NookDesignLinkRefusal] = [.empty, .tooLong, .notAWebLink, .hasCredentials]
        #expect(Set(reasons.map(\.noticeKey)).count == 4)
        for language in HangoverBrandTests.languages {
            let table = try HangoverBrandTests.table(language)
            for reason in reasons {
                #expect(!(table[reason.noticeKey] ?? "").isEmpty, "\(language) \(reason.noticeKey)")
            }
        }
    }

    @Test func theSameAddressTwiceIsSaidToBeSavedAndNotAddedAgain() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        guard case let .added(first) = fixture.kit.addLink(text: figmaURL) else { return }

        #expect(fixture.kit.addLink(text: figmaURL) == .duplicate(first))
        #expect(fixture.kit.notice?.kind == .info)
        #expect(fixture.kit.notice?.text == text("nook.design.notice.linkDuplicate"))
        #expect(fixture.kit.links.links.count == 1)
        // The same page written with a different fragment is another link.
        guard case .added = fixture.kit.addLink(text: figmaURL + "x") else {
            Issue.record("a different address was taken for a duplicate")
            return
        }
        #expect(fixture.kit.links.links.count == 2)
    }

    @Test func aNewLinkGoesInTheLitCollectionAndTheSameAddressMayBeThereToo() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit
        guard case let .added(outside) = kit.addLink(text: "https://example.com/x") else { return }
        kit.moveLink(outside.id, toCollectionNamed: "Work")
        let work = try #require(kit.links.collections.first)
        // The link moved into Work. None is free again.
        guard case .added = kit.addLink(text: "https://example.com/x") else {
            Issue.record("the address was still taken in no collection")
            return
        }
        #expect(kit.links.links.count == 2)

        kit.selectLinkCollection(work.id)
        #expect(kit.activeLinkCollectionID == work.id)
        // Work already holds this address.
        guard case .duplicate = kit.addLink(text: "https://example.com/x") else {
            Issue.record("expected a duplicate in the lit collection")
            return
        }
        guard case let .added(inWork) = kit.addLink(text: "https://example.com/y") else { return }
        #expect(inWork.collectionID == work.id)

        // A chip whose collection is gone counts as All.
        kit.deleteCollection(work.id)
        #expect(kit.selectedLinkCollectionID == nil)
        guard case let .added(afterwards) = kit.addLink(text: "https://example.com/z") else { return }
        #expect(afterwards.collectionID == nil)
    }

    @Test func aStaleChipThatNobodyClearedCountsAsAll() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        fixture.kit.selectLinkCollection(UUID())
        #expect(fixture.kit.activeLinkCollectionID == nil)
        guard case let .added(link) = fixture.kit.addLink(text: "https://example.com/x") else { return }
        #expect(link.collectionID == nil)
    }

    @Test func at199LinksOneMoreIsTakenAndAt200TheNextIsRefusedWithALine() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit
        for index in 0..<199 { kit.addLink(text: "https://example.com/\(index)") }
        #expect(kit.links.links.count == 199)

        guard case .added = kit.addLink(text: "https://example.com/199") else {
            Issue.record("the 200th link was refused")
            return
        }
        #expect(kit.links.links.count == 200)
        #expect(kit.addLink(text: "https://example.com/200") == .full)
        #expect(kit.notice?.kind == .error)
        #expect(kit.notice?.text == text("nook.design.notice.linksFull", NookDesignLinkLibrary.maxLinks))
        #expect(kit.links.links.count == 200, "an old link was dropped")
        #expect(kit.links.links.contains { $0.url == "https://example.com/0" })
        // An address already there is a duplicate, and the shelf is not called full.
        guard case .duplicate = kit.addLink(text: "https://example.com/7") else {
            Issue.record("expected a duplicate")
            return
        }
    }

    @Test func aKitThatWasNotReadYetTakesNothing() async throws {
        let fixture = try await NookDesignFixture(isLive: false)
        defer { fixture.cleanUp() }
        #expect(fixture.kit.addLink(text: "https://example.com") == .unavailable)
        #expect(fixture.kit.links.links.isEmpty)
    }

    // MARK: Pasting

    @Test func pastingReadsTheClipboardOnlyWhenAskedAndAddsALinkOnIt() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        fixture.clipboard.text = "  \(figmaURL)  "
        // Setting up, adding by hand and waiting read nothing.
        fixture.kit.addLink(text: "https://example.com/typed")
        try await Task.sleep(for: .milliseconds(20))
        #expect(fixture.clipboard.textReads == 0)

        guard case let .added(link) = fixture.kit.pasteLink() else {
            Issue.record("not added")
            return
        }

        #expect(link.url == figmaURL)
        #expect(fixture.clipboard.textReads == 1)
        #expect(fixture.clipboard.reads == 0, "no picture was looked for")
    }

    @Test func pastingWithNoTextOnTheClipboardSaysSoAndChangesNothing() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        fixture.clipboard.text = nil

        #expect(fixture.kit.pasteLink() == .nothingToPaste)

        #expect(fixture.kit.notice?.kind == .info)
        #expect(fixture.kit.notice?.text == text("nook.design.notice.linkNoText"))
        #expect(fixture.kit.links.links.isEmpty)
        #expect(fixture.clipboard.textReads == 1)
    }

    @Test func aPictureOnTheClipboardIsNoTextAndIsNotReadAsAPicture() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        fixture.clipboard.pictures = .data(Samples.pngData(width: 20, height: 20))
        fixture.clipboard.text = nil

        #expect(fixture.kit.pasteLink() == .nothingToPaste)

        #expect(fixture.clipboard.reads == 0)
        #expect(fixture.kit.links.links.isEmpty)
        #expect(fixture.kit.references.items.isEmpty)
    }

    @Test func textOnTheClipboardThatIsNotALinkIsRefusedWithTheSameLinesAsTyping() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        for (clip, reason) in [
            ("just some words", NookDesignLinkRefusal.notAWebLink), ("javascript:alert(1)", .notAWebLink), ("   ", .empty),
            ("https://u:p@example.com", .hasCredentials), (String(repeating: "x", count: 5_000), .tooLong),
        ] {
            fixture.clipboard.text = clip
            #expect(fixture.kit.pasteLink() == .refused(reason), "\(clip.prefix(20))")
            #expect(fixture.kit.notice?.text == text(reason.noticeKey))
        }
        #expect(fixture.kit.links.links.isEmpty)
        #expect(fixture.clipboard.textReads == 5)
    }

    @Test func pastingTheSameLinkTwiceAddsItOnce() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        fixture.clipboard.text = figmaURL

        fixture.kit.pasteLink()
        guard case .duplicate = fixture.kit.pasteLink() else {
            Issue.record("expected a duplicate")
            return
        }
        #expect(fixture.kit.links.links.count == 1)
    }

    @Test func aKitWithNoClipboardDoorReadsNothingAndSaysNothing() async throws {
        let folder = try Samples.temporaryFolder("nodoor")
        defer { try? FileManager.default.removeItem(at: folder) }
        let kit = NookDesignKit(folder: folder, defaults: MemoryDefaults())
        kit.setLive(true)
        await kit.load()

        #expect(kit.pasteLink() == .unavailable)
        #expect(kit.notice == nil)
        #expect(kit.links.links.isEmpty)
    }
}

// MARK: - Opening and copying

@MainActor
@Suite struct NookDesignLinkOpeningTests {
    private func kitWithLink(_ fixture: NookDesignFixture, _ url: String = figmaURL) throws -> NookDesignLink {
        guard case let .added(link) = fixture.kit.addLink(text: url) else { throw CancellationError() }
        return link
    }

    @Test func openingHandsTheOpenerTheAddressExactlyAsSaved() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let link = try kitWithLink(fixture)

        #expect(fixture.kit.openLink(link.id))

        let url = try #require(fixture.opener.opened.first)
        #expect(fixture.opener.opened.count == 1)
        #expect(url.absoluteString == figmaURL)
        #expect(url.query == "node-id=12-34&t=XyZ-1")
        #expect(url.fragment == "Frame-One")
    }

    @Test func openingNotesTheMomentAndMovesTheLinkUpAmongTheRest() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        fixture.kit.now = { clock }
        let a = try kitWithLink(fixture, "https://a.example/1")
        clock.addTimeInterval(10)
        let b = try kitWithLink(fixture, "https://b.example/2")
        #expect(fixture.kit.links.library.orderedLinks(in: nil).map(\.id) == [b.id, a.id])

        clock.addTimeInterval(100)
        fixture.kit.openLink(a.id)

        #expect(fixture.kit.links.link(a.id)?.lastOpenedAt == clock)
        #expect(fixture.kit.links.library.orderedLinks(in: nil).map(\.id) == [a.id, b.id])
    }

    @Test func whenTheOpenerSaysNoANoticeSaysItDidNotOpenAndNothingElseChanges() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let a = try kitWithLink(fixture, "https://a.example/1")
        _ = try kitWithLink(fixture, "https://b.example/2")
        let before = fixture.kit.links.library
        fixture.opener.accepts = false

        #expect(!fixture.kit.openLink(a.id))

        #expect(fixture.kit.notice?.kind == .error)
        #expect(fixture.kit.notice?.text == text("nook.design.notice.linkNotOpened", a.name))
        #expect(fixture.kit.links.library == before)
        #expect(fixture.kit.links.link(a.id)?.lastOpenedAt == nil)
        #expect(fixture.opener.opened.count == 1)
    }

    @Test func aKitWithNoOpenerOpensNothingAndSaysSo() async throws {
        let folder = try Samples.temporaryFolder("noopener")
        defer { try? FileManager.default.removeItem(at: folder) }
        let kit = NookDesignKit(folder: folder, defaults: MemoryDefaults())
        kit.setLive(true)
        await kit.load()
        guard case let .added(link) = kit.addLink(text: "https://example.com/x") else { return }

        #expect(!kit.openLink(link.id))

        #expect(kit.notice?.kind == .error)
        #expect(kit.links.link(link.id)?.lastOpenedAt == nil)
    }

    @Test func aLinkThatIsNotThereOpensNothingAndSaysNothing() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        #expect(!fixture.kit.openLink(UUID()))
        #expect(fixture.kit.notice == nil)
        #expect(fixture.opener.opened.isEmpty)
    }

    @Test func copyingGoesThroughTheDoorAColorIsCopiedThroughAndShowsTheSameTick() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let link = try kitWithLink(fixture)

        #expect(fixture.kit.copyLink(link.id))

        #expect(fixture.copies.texts == [figmaURL])
        #expect(fixture.kit.justCopiedID == link.id)
        #expect(fixture.kit.notice?.kind == .done)
        #expect(fixture.kit.notice?.text == text("nook.design.notice.linkCopied", link.name))
        // The pasteboard was only written through the door. Nothing was read.
        #expect(fixture.clipboard.textReads == 0)
        #expect(fixture.opener.opened.isEmpty)
    }

    @Test func aCopyThatDidNotTakeSaysSoWithTheLineACopiedColorUses() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let link = try kitWithLink(fixture)
        fixture.copies.succeeds = false

        #expect(!fixture.kit.copyLink(link.id))

        #expect(fixture.kit.notice?.kind == .error)
        #expect(fixture.kit.notice?.text == text("nook.design.notice.copyFailed"))
        #expect(fixture.kit.justCopiedID == nil)
        #expect(!fixture.kit.copyLink(UUID()))
    }

    @Test func copyingALinkAndAColorShareOneTickThatMovesBetweenThem() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let link = try kitWithLink(fixture)
        let color = NookDesignColor(red: 255, green: 136, blue: 0)
        let colorID = UUID()

        fixture.kit.copy(color, from: colorID)
        #expect(fixture.kit.justCopiedID == colorID)
        fixture.kit.copyLink(link.id)
        #expect(fixture.kit.justCopiedID == link.id)
        #expect(fixture.copies.texts == ["#FF8800", figmaURL])
    }
}

// MARK: - Organizing

@MainActor
@Suite struct NookDesignLinkOrganizingTests {
    private func added(_ fixture: NookDesignFixture, _ url: String) -> NookDesignLink {
        if case let .added(link) = fixture.kit.addLink(text: url) { return link }
        Issue.record("\(url) was not added")
        return NookDesignLink(id: UUID(), url: url, name: "", collectionID: nil, isFavorite: false, addedAt: Date(), lastOpenedAt: nil)
    }

    @Test func favoritesComeFirstInTheListAndThenTheMostRecent() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        fixture.kit.now = { clock }
        let a = added(fixture, "https://a.example/1")
        clock.addTimeInterval(5)
        let b = added(fixture, "https://b.example/2")
        clock.addTimeInterval(5)
        let c = added(fixture, "https://c.example/3")

        fixture.kit.toggleLinkFavorite(a.id)
        #expect(fixture.kit.links.library.orderedLinks(in: nil).map(\.id) == [a.id, c.id, b.id])
        fixture.kit.toggleLinkFavorite(a.id)
        #expect(fixture.kit.links.library.orderedLinks(in: nil).map(\.id) == [c.id, b.id, a.id])
    }

    @Test func movingAndNamingACollectionAndDeletingItKeepsTheLinks() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit
        let a = added(fixture, "https://a.example/1")
        let b = added(fixture, "https://b.example/2")

        #expect(kit.moveLink(a.id, toCollectionNamed: "  Client\nwork "))
        #expect(kit.moveLink(b.id, toCollectionNamed: "client WORK"))
        let work = try #require(kit.links.collections.first)
        #expect(kit.links.collections.count == 1)
        #expect(work.name == "Client work")
        #expect(kit.links.links.allSatisfy { $0.collectionID == work.id })

        #expect(kit.renameCollection(work.id, to: "Clients"))
        kit.selectLinkCollection(work.id)
        kit.deleteCollection(work.id)

        #expect(kit.links.collections.isEmpty)
        #expect(kit.links.links.count == 2)
        #expect(kit.links.links.allSatisfy { $0.collectionID == nil })
        #expect(kit.selectedLinkCollectionID == nil)
    }

    @Test func aCollectionRenamedOntoAnotherOnesNameIsRefusedWithALine() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit
        let a = added(fixture, "https://a.example/1")
        let b = added(fixture, "https://b.example/2")
        kit.moveLink(a.id, toCollectionNamed: "One")
        kit.moveLink(b.id, toCollectionNamed: "Two")
        let two = try #require(kit.links.collections.last)

        #expect(!kit.renameCollection(two.id, to: " one "))
        #expect(kit.notice?.text == text("nook.design.notice.collectionNameTaken"))
        #expect(!kit.renameCollection(two.id, to: "  "))
        #expect(kit.notice?.text == text("nook.design.notice.collectionNameEmpty"))
        #expect(kit.links.collections.map(\.name) == ["One", "Two"])
        #expect(kit.renameCollection(two.id, to: "TWO"))
    }

    @Test func at23CollectionsOneMoreIsTakenAndAt24TheNextIsRefusedWithALine() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit
        let link = added(fixture, "https://a.example/1")
        for index in 0..<23 { kit.links.addCollection(named: "C\(index)") }
        #expect(kit.links.collections.count == 23)

        #expect(kit.moveLink(link.id, toCollectionNamed: "C23"))
        #expect(kit.links.collections.count == 24)
        #expect(!kit.moveLink(link.id, toCollectionNamed: "C24"))
        #expect(kit.notice?.kind == .error)
        #expect(kit.notice?.text == text("nook.design.notice.collectionsFull", NookDesignLinkLibrary.maxCollections))
        #expect(kit.links.collections.count == 24)
        #expect(kit.links.link(link.id)?.collectionID == kit.links.collections.last?.id, "the link stayed where it was")
        // An existing name is still fine.
        #expect(kit.moveLink(link.id, toCollectionNamed: "c0"))
    }

    @Test func movingWhereTheSameAddressAlreadyIsSaysSoAndMovesNothing() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit
        let a = added(fixture, "https://a.example/1")
        kit.moveLink(a.id, toCollectionNamed: "Work")
        let outside = added(fixture, "https://a.example/1")
        #expect(outside.collectionID == nil)

        #expect(!kit.moveLink(outside.id, toCollectionNamed: "Work"))
        #expect(kit.notice?.text == text("nook.design.notice.linkMoveDuplicate"))
        #expect(!kit.moveLink(outside.id, to: kit.links.collections[0].id))
        #expect(kit.links.link(outside.id)?.collectionID == nil)
        #expect(kit.links.collections.count == 1)
    }

    @Test func deletingALinkTakesItAwayAndFreesItsAddress() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let link = added(fixture, "https://a.example/1")
        fixture.kit.deleteLink(link.id)
        #expect(fixture.kit.links.links.isEmpty)
        guard case .added = fixture.kit.addLink(text: "https://a.example/1") else {
            Issue.record("the address was still taken")
            return
        }
    }

    // MARK: Asking for a name

    @Test func renamingALinkThroughTheNameFieldKeepsTheNameAndClosesTheQuestion() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let link = added(fixture, "https://a.example/1")

        fixture.kit.beginNaming(.renamingLink(link.id))
        #expect(fixture.kit.namingSeed(for: .renamingLink(link.id)) == link.name)
        #expect(fixture.kit.commitNaming("  Pitch\r\ndeck  "))

        #expect(fixture.kit.links.link(link.id)?.name == "Pitch deck")
        #expect(fixture.kit.linkNaming == nil)
    }

    @Test func aBlankNameBringsBackTheDefaultOne() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let link = added(fixture, "https://a.example/docs")
        fixture.kit.links.renameLink(link.id, to: "Mine")

        fixture.kit.beginNaming(.renamingLink(link.id))
        fixture.kit.commitNaming("   ")

        #expect(fixture.kit.links.link(link.id)?.name == "a.example/docs")
    }

    @Test func aNewCollectionIsMadeByNamingItWhenALinkMovesIntoIt() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let link = added(fixture, "https://a.example/1")

        fixture.kit.beginNaming(.newCollection(forLink: link.id))
        #expect(fixture.kit.namingSeed(for: .newCollection(forLink: link.id)).isEmpty)
        #expect(fixture.kit.commitNaming("Pitch deck"))

        #expect(fixture.kit.links.collections.map(\.name) == ["Pitch deck"])
        #expect(fixture.kit.links.link(link.id)?.collectionID == fixture.kit.links.collections.first?.id)
        #expect(fixture.kit.linkNaming == nil)
    }

    @Test func aNameThatIsRefusedLeavesTheQuestionUpWithALine() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let link = added(fixture, "https://a.example/1")
        fixture.kit.moveLink(link.id, toCollectionNamed: "Work")
        let work = try #require(fixture.kit.links.collections.first)
        let other = added(fixture, "https://b.example/2")

        fixture.kit.beginNaming(.renamingCollection(work.id))
        #expect(fixture.kit.namingSeed(for: .renamingCollection(work.id)) == "Work")
        #expect(fixture.kit.commitNaming("  ") == false)
        #expect(fixture.kit.linkNaming == .renamingCollection(work.id))
        #expect(fixture.kit.notice?.text == text("nook.design.notice.collectionNameEmpty"))

        fixture.kit.beginNaming(.newCollection(forLink: other.id))
        fixture.kit.links.addCollection(named: "Taken")
        // A name that exists moves the link there instead of making a second one.
        #expect(fixture.kit.commitNaming("taken"))
        #expect(fixture.kit.links.collections.count == 2)
    }

    @Test func escapeLeavesTheNameAsItWasAndDeletingWhatIsBeingNamedClosesTheQuestion() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let link = added(fixture, "https://a.example/1")

        fixture.kit.beginNaming(.renamingLink(link.id))
        fixture.kit.cancelNaming()
        #expect(fixture.kit.linkNaming == nil)
        #expect(!fixture.kit.commitNaming("Ignored"))
        #expect(fixture.kit.links.link(link.id)?.name == link.name)

        fixture.kit.beginNaming(.renamingLink(link.id))
        fixture.kit.deleteLink(link.id)
        #expect(fixture.kit.linkNaming == nil)

        let next = added(fixture, "https://b.example/2")
        fixture.kit.moveLink(next.id, toCollectionNamed: "Work")
        let work = try #require(fixture.kit.links.collections.first)
        fixture.kit.beginNaming(.renamingCollection(work.id))
        fixture.kit.deleteCollection(work.id)
        #expect(fixture.kit.linkNaming == nil)
    }

    @Test func switchingTheWidgetOffPutsTheQuestionAway() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let link = added(fixture, "https://a.example/1")
        fixture.kit.beginNaming(.renamingLink(link.id))

        fixture.kit.setLive(false)

        #expect(fixture.kit.linkNaming == nil)
    }

    @Test func aNameIsADraftOnlyWhenItDiffersFromTheSavedOneAndHasSomethingInIt() {
        let limit = NookDesignLinkRules.maxNameLength
        #expect(!NookDesignNames.isUnsaved("Pitch", saved: "Pitch", limit: limit))
        #expect(!NookDesignNames.isUnsaved("  Pitch  ", saved: "Pitch", limit: limit))
        #expect(!NookDesignNames.isUnsaved("", saved: "Pitch", limit: limit))
        #expect(!NookDesignNames.isUnsaved(" \n", saved: "", limit: limit))
        #expect(NookDesignNames.isUnsaved("Pitch 2", saved: "Pitch", limit: limit))
        #expect(NookDesignNames.isUnsaved("x", saved: "", limit: limit))
        // A new collection name starts empty. Any text is a draft.
        #expect(NookDesignNames.isUnsaved(String(repeating: "x", count: 90), saved: "", limit: limit))
    }
}

// MARK: - Saved between launches, through the kit

@MainActor
@Suite struct NookDesignLinkSavingTests {
    @Test func linksCollectionsFavoritesAndOpeningsComeBackOnTheNextLaunch() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        let kit = fixture.kit
        guard case let .added(link) = kit.addLink(text: figmaURL) else { return }
        kit.moveLink(link.id, toCollectionNamed: "Client work")
        kit.toggleLinkFavorite(link.id)
        kit.openLink(link.id)
        await kit.flush()

        let next = NookDesignKit(folder: fixture.folder, defaults: MemoryDefaults())
        await next.load()

        #expect(next.links.library == kit.links.library)
        #expect(next.links.link(link.id)?.url == figmaURL)
        #expect(next.links.link(link.id)?.isFavorite == true)
        #expect(next.links.link(link.id)?.lastOpenedAt != nil)
        #expect(next.links.collections.map(\.name) == ["Client work"])
    }

    @Test func aFailedWriteIsSaidOnTheCard() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        try FileManager.default.removeItem(at: fixture.folder)
        try Data("in the way".utf8).write(to: fixture.folder)

        fixture.kit.addLink(text: "https://example.com/x")
        await fixture.kit.flush()

        #expect(await Samples.wait { fixture.kit.notice?.text == text("nook.design.notice.saveFailed") })
        #expect(fixture.kit.links.links.count == 1, "the link stays in memory")
    }

    @Test func theLinksFileSitsBesideTheColorsAndTheFilesDoNotTouchEachOther() async throws {
        let fixture = try await NookDesignFixture()
        defer { fixture.cleanUp() }
        fixture.kit.addColor(NookDesignColor(red: 1, green: 2, blue: 3))
        fixture.kit.addLink(text: "https://example.com/x")
        await fixture.kit.flush()

        let files = ((try? FileManager.default.contentsOfDirectory(atPath: fixture.folder.path)) ?? []).sorted()
        #expect(files == ["links.json", "palettes.json"])
        #expect(fixture.kit.links.folderURL == fixture.kit.palettes.folderURL)
    }

    @Test func theLinksTabIsRememberedLikeTheOthers() async throws {
        let defaults = MemoryDefaults()
        let first = try await NookDesignFixture(defaults: defaults)
        defer { first.cleanUp() }
        first.kit.tab = .links
        let second = try await NookDesignFixture(defaults: defaults)
        defer { second.cleanUp() }
        #expect(second.kit.tab == .links)
        #expect(NookDesignTab.allCases == [.colors, .links, .references])
        #expect(NookDesignTab.links.symbol == "link")
    }
}
