import Foundation
import Testing
@testable import OpenIslandApp

/// The editing rules of the Links tab, as pure changes of a value: adding,
/// duplicates, names, favorites, opening, collections and the limits.
@Suite struct NookDesignLinkLibraryTests {
    private typealias Library = NookDesignLinkLibrary

    private let day = Date(timeIntervalSince1970: 1_800_000_000)

    private func add(_ library: Library, _ url: String, name: String = "Name", to collection: UUID? = nil) -> (Library, NookDesignLink)? {
        if case let .added(next, link) = library.addingLink(url: url, name: name, to: collection, now: day) { return (next, link) }
        return nil
    }

    /// A library with these addresses, none in a collection.
    private func library(with urls: [String]) -> (Library, [UUID]) {
        var library = Library.empty
        var ids: [UUID] = []
        for url in urls {
            guard let (next, link) = add(library, url, name: url) else {
                Issue.record("\(url) was not added")
                continue
            }
            library = next
            ids.append(link.id)
        }
        return (library, ids)
    }

    private func collection(in library: Library, _ name: String) -> (Library, NookDesignLinkCollection)? {
        if case let .done(next, made) = library.addingCollection(named: name, now: day) { return (next, made) }
        return nil
    }

    // MARK: Adding

    @Test func aNewLinkGoesToTheFrontWithItsAddressAsGiven() {
        let urls = ["https://a.example/1", "https://b.example/2"]
        let (library, ids) = library(with: urls)
        #expect(library.links.map(\.url) == ["https://b.example/2", "https://a.example/1"])
        #expect(library.links.map(\.id) == ids.reversed())
        #expect(library.links.allSatisfy { !$0.isFavorite && $0.collectionID == nil && $0.lastOpenedAt == nil })
        #expect(library.links.allSatisfy { $0.addedAt == day })
    }

    @Test func theSameAddressTwiceInOneCollectionIsNotAddedAgain() {
        let (library, ids) = library(with: ["https://example.com/x"])
        let again = library.addingLink(url: "https://example.com/x", name: "Other name", now: day)
        guard case let .duplicate(existing) = again else {
            Issue.record("expected a duplicate, got \(again)")
            return
        }
        #expect(existing.id == ids[0])
        #expect(existing.name == "https://example.com/x")
    }

    /// The test is the exact text. A fragment, a trailing slash, a capital
    /// letter or another scheme makes another link.
    @Test(arguments: [
        "https://example.com/x#frag", "https://example.com/x/", "https://example.com/X", "https://Example.com/x",
        "http://example.com/x", "https://example.com/x?", "https://example.com/x?a=1", "https://example.com:443/x",
        "HTTPS://example.com/x", "https://example.com./x", "https://example.com/x%20",
    ])
    func anAddressThatDiffersByEvenOneCharacterIsAnotherLink(other: String) {
        let (library, _) = library(with: ["https://example.com/x"])
        guard case .added = library.addingLink(url: other, name: "n", now: day) else {
            Issue.record("\(other) was taken for a duplicate")
            return
        }
    }

    @Test func theSameAddressMayLiveInTwoCollectionsAndOnceOutsideAny() throws {
        let (withCollection, made) = try #require(collection(in: .empty, "Work"))
        let first = try #require(add(withCollection, "https://example.com/x"))
        let inWork = try #require(add(first.0, "https://example.com/x", to: made.id))
        #expect(inWork.0.links.count == 2)
        #expect(inWork.0.addingLink(url: "https://example.com/x", name: "n", to: made.id, now: day) == .duplicate(inWork.1))
        #expect(inWork.0.addingLink(url: "https://example.com/x", name: "n", to: nil, now: day) == .duplicate(first.1))
    }

    @Test func aLinkForACollectionThatIsGoneIsRefused() {
        #expect(Library.empty.addingLink(url: "https://example.com", name: "n", to: UUID(), now: day) == .unknownCollection)
    }

    @Test func aNameIsCleanedAtTheLimit() throws {
        let exact = String(repeating: "n", count: 80)
        let first = try #require(add(.empty, "https://a.example", name: exact))
        #expect(first.1.name == exact)
        let over = try #require(add(.empty, "https://b.example", name: exact + "n"))
        #expect(over.1.name == exact)
        let blanks = try #require(add(.empty, "https://c.example", name: "  Line\r\none  "))
        #expect(blanks.1.name == "Line one")
    }

    // MARK: The limit of links

    private func fill(_ count: Int) -> Library {
        var library = Library.empty
        for index in 0..<count {
            library = add(library, "https://example.com/\(index)")?.0 ?? library
        }
        return library
    }

    @Test func oneBelowTheLimitTakesOneMoreAndTheLimitTakesNoMore() throws {
        let limit = Library.maxLinks
        #expect(limit == 200)
        let below = fill(limit - 1)
        #expect(below.links.count == 199)
        let atLimit = try #require(add(below, "https://example.com/last")).0
        #expect(atLimit.links.count == 200)
        #expect(atLimit.addingLink(url: "https://example.com/one-more", name: "n", now: day) == .full)
        #expect(atLimit.links.count == 200)
    }

    @Test func aFullShelfSaysDuplicateForAnAddressItHasAndFullForOneItDoesNot() {
        let full = fill(Library.maxLinks)
        guard case .duplicate = full.addingLink(url: "https://example.com/5", name: "n", now: day) else {
            Issue.record("expected a duplicate")
            return
        }
        #expect(full.addingLink(url: "https://example.com/new", name: "n", now: day) == .full)
    }

    @Test func removingOneMakesRoomForExactlyOne() throws {
        let full = fill(Library.maxLinks)
        let room = full.removingLink(full.links[10].id)
        let refilled = try #require(add(room, "https://example.com/fresh")).0
        #expect(refilled.links.count == 200)
        #expect(refilled.addingLink(url: "https://example.com/fresher", name: "n", now: day) == .full)
    }

    // MARK: Renaming, favorites, opening, removing

    @Test func renamingCleansTheNameAndABlankNameBringsBackTheDefaultOne() throws {
        let (library, ids) = library(with: ["https://www.figma.com/design/KEY/Brand-Kit?node-id=1"])
        let renamed = library.renamingLink(ids[0], to: "  My\nkit  ")
        #expect(renamed.links[0].name == "My kit")
        #expect(renamed.renamingLink(ids[0], to: "   ").links[0].name == "www.figma.com/Brand-Kit")
        #expect(renamed.renamingLink(ids[0], to: "").links[0].name == "www.figma.com/Brand-Kit")
        #expect(renamed.renamingLink(ids[0], to: String(repeating: "x", count: 200)).links[0].name.count == 80)
        #expect(library.renamingLink(UUID(), to: "Nobody") == library)
        // Renaming touches nothing but the name.
        #expect(renamed.links[0].url == library.links[0].url)
        #expect(renamed.links[0].addedAt == library.links[0].addedAt)
    }

    @Test func favoriteTogglesOnAndOffAndAnUnknownLinkChangesNothing() {
        let (library, ids) = library(with: ["https://a.example", "https://b.example"])
        let marked = library.togglingFavorite(ids[0])
        #expect(marked.link(ids[0])?.isFavorite == true)
        #expect(marked.link(ids[1])?.isFavorite == false)
        #expect(marked.togglingFavorite(ids[0]) == library)
        #expect(library.togglingFavorite(UUID()) == library)
    }

    @Test func openingNotesTheMomentAndMovesTheLinkUp() {
        let (library, ids) = library(with: ["https://a.example", "https://b.example", "https://c.example"])
        let before = library.orderedLinks(in: nil).map(\.id)
        #expect(before == [ids[2], ids[1], ids[0]])

        let opened = library.markingOpened(ids[0], now: day.addingTimeInterval(500))
        #expect(opened.link(ids[0])?.lastOpenedAt == day.addingTimeInterval(500))
        #expect(opened.orderedLinks(in: nil).map(\.id) == [ids[0], ids[2], ids[1]])
        // Opening one link touches nothing of the others.
        #expect(opened.link(ids[1]) == library.link(ids[1]))
        #expect(library.markingOpened(UUID()) == library)
    }

    @Test func removingALinkLeavesTheOthersAndAnUnknownIdChangesNothing() {
        let (library, ids) = library(with: ["https://a.example", "https://b.example"])
        #expect(library.removingLink(ids[0]).links.map(\.id) == [ids[1]])
        #expect(library.removingLink(UUID()) == library)
        #expect(library.removingLink(ids[0]).removingLink(ids[0]).links.count == 1)
    }

    // MARK: Collections

    @Test func aCollectionIsMadeByNamingItAndTheNameIsCleaned() throws {
        let (library, made) = try #require(collection(in: .empty, "  Client\nwork  "))
        #expect(made.name == "Client work")
        #expect(library.collections == [made])
        #expect(library.addingCollection(named: "   ") == .nameEmpty)
        #expect(library.addingCollection(named: "") == .nameEmpty)
        #expect(library.addingCollection(named: String(repeating: "c", count: 90)).collectionName?.count == 80)
    }

    @Test func aNameAlreadyTakenIsFoundWhateverItsCaseOrBlanks() throws {
        let (library, made) = try #require(collection(in: .empty, "Client work"))
        for name in ["Client work", "client WORK", "CLIENT WORK", "  Client work  ", "Client\nwork"] {
            #expect(library.addingCollection(named: name) == .nameTaken(made), "\(name.debugDescription)")
        }
        #expect(library.collection(named: "client work") == made)
        #expect(library.collection(named: "Client") == nil)
        // A name that only starts the same is another name.
        #expect(library.addingCollection(named: "Client work 2").collectionName == "Client work 2")
    }

    @Test func oneBelowTheLimitOfCollectionsTakesOneMoreAndTheLimitTakesNoMore() throws {
        var library = Library.empty
        for index in 0..<(Library.maxCollections - 1) {
            library = try #require(collection(in: library, "C\(index)")).0
        }
        #expect(library.collections.count == 23)
        let atLimit = try #require(collection(in: library, "C23")).0
        #expect(atLimit.collections.count == 24)
        #expect(Library.maxCollections == 24)
        #expect(atLimit.addingCollection(named: "C24") == .full)
        // A name it already has gets nameTaken, not full.
        guard case .nameTaken = atLimit.addingCollection(named: "c3") else {
            Issue.record("expected nameTaken")
            return
        }
        #expect(atLimit.collections.count == 24)
    }

    @Test func renamingACollectionOntoAnotherOnesNameIsRefused() throws {
        let one = try #require(collection(in: .empty, "One"))
        let two = try #require(collection(in: one.0, "Two"))
        let library = two.0
        #expect(library.renamingCollection(two.1.id, to: "one") == .nameTaken(one.1))
        #expect(library.renamingCollection(two.1.id, to: " ONE ") == .nameTaken(one.1))
        #expect(library.renamingCollection(two.1.id, to: "") == .nameEmpty)
        #expect(library.renamingCollection(two.1.id, to: " \n ") == .nameEmpty)
        #expect(library.renamingCollection(UUID(), to: "Three") == .unknown)
        // Its own name in another case is fine, and a new name is too.
        #expect(library.renamingCollection(two.1.id, to: "TWO").collectionName == "TWO")
        #expect(library.renamingCollection(two.1.id, to: "Three").collectionName == "Three")
        #expect(library.renamingCollection(two.1.id, to: String(repeating: "n", count: 99)).collectionName?.count == 80)
        #expect(library.renamingCollection(two.1.id, to: "Two").collectionName == "Two")
    }

    @Test func renamingACollectionKeepsItsLinksAndItsPlace() throws {
        let one = try #require(collection(in: .empty, "One"))
        let two = try #require(collection(in: one.0, "Two"))
        let added = try #require(add(two.0, "https://a.example", to: two.1.id))
        guard case let .done(renamed, _) = added.0.renamingCollection(two.1.id, to: "Second") else {
            Issue.record("not renamed")
            return
        }
        #expect(renamed.collections.map(\.name) == ["One", "Second"])
        #expect(renamed.link(added.1.id)?.collectionID == two.1.id)
    }

    @Test func deletingACollectionKeepsItsLinksAndLeavesThemInNone() throws {
        let work = try #require(collection(in: .empty, "Work"))
        let home = try #require(collection(in: work.0, "Home"))
        var library = home.0
        let a = try #require(add(library, "https://a.example", to: work.1.id))
        library = a.0
        let b = try #require(add(library, "https://b.example", to: work.1.id))
        library = b.0
        let c = try #require(add(library, "https://c.example", to: home.1.id))
        library = c.0
        let d = try #require(add(library, "https://d.example"))
        library = d.0

        let after = library.removingCollection(work.1.id)

        #expect(after.collections == [home.1])
        #expect(after.links.count == 4)
        #expect(after.link(a.1.id)?.collectionID == nil)
        #expect(after.link(b.1.id)?.collectionID == nil)
        #expect(after.link(c.1.id)?.collectionID == home.1.id)
        #expect(after.link(d.1.id)?.collectionID == nil)
        // Nothing but the filing changed.
        #expect(after.link(a.1.id)?.name == a.1.name)
        #expect(after.link(a.1.id)?.url == a.1.url)
        #expect(library.removingCollection(UUID()) == library)
    }

    @Test func deletingACollectionLeavesAnotherLinkWithTheSameAddressInNoneAsItIs() throws {
        // The two links were apart by their collections. Now both are in
        // none. Neither is dropped, and the list shows both.
        let work = try #require(collection(in: .empty, "Work"))
        let outside = try #require(add(work.0, "https://example.com/x"))
        let inside = try #require(add(outside.0, "https://example.com/x", to: work.1.id))
        let after = inside.0.removingCollection(work.1.id)
        #expect(after.links.count == 2)
        #expect(after.links.allSatisfy { $0.collectionID == nil })
    }

    // MARK: Moving

    @Test func movingFilesALinkUnderACollectionOrUnderNone() throws {
        let work = try #require(collection(in: .empty, "Work"))
        let added = try #require(add(work.0, "https://a.example"))
        guard case let .moved(inWork) = added.0.movingLink(added.1.id, to: work.1.id) else {
            Issue.record("not moved")
            return
        }
        #expect(inWork.link(added.1.id)?.collectionID == work.1.id)
        guard case let .moved(out) = inWork.movingLink(added.1.id, to: nil) else {
            Issue.record("not moved out")
            return
        }
        #expect(out.link(added.1.id)?.collectionID == nil)
        #expect(added.0.movingLink(added.1.id, to: nil) == .moved(added.0))
        #expect(added.0.movingLink(UUID(), to: work.1.id) == .unknownLink)
        #expect(added.0.movingLink(added.1.id, to: UUID()) == .unknownCollection)
    }

    @Test func aLinkCannotMoveWhereTheSameAddressAlreadyIs() throws {
        let work = try #require(collection(in: .empty, "Work"))
        let outside = try #require(add(work.0, "https://example.com/x"))
        let inside = try #require(add(outside.0, "https://example.com/x", to: work.1.id))
        #expect(inside.0.movingLink(outside.1.id, to: work.1.id) == .duplicate(inside.1))
        #expect(inside.0.movingLink(inside.1.id, to: nil) == .duplicate(outside.1))
        // The same page with another fragment is another address. It may go.
        let other = try #require(add(inside.0, "https://example.com/x#frag"))
        guard case .moved = other.0.movingLink(other.1.id, to: work.1.id) else {
            Issue.record("a different address was refused")
            return
        }
    }

    @Test func movingByNameMakesTheCollectionWhenThereIsNoneOfThatName() throws {
        let (library, ids) = library(with: ["https://a.example"])
        guard case let .moved(next) = library.movingLink(ids[0], toCollectionNamed: "  Pitch deck ", newID: UUID(), now: day) else {
            Issue.record("not moved")
            return
        }
        #expect(next.collections.map(\.name) == ["Pitch deck"])
        #expect(next.link(ids[0])?.collectionID == next.collections[0].id)
    }

    @Test func movingByNameUsesTheCollectionOfThatNameInAnyCase() throws {
        let work = try #require(collection(in: .empty, "Work"))
        let added = try #require(add(work.0, "https://a.example"))
        guard case let .moved(next) = added.0.movingLink(added.1.id, toCollectionNamed: "WORK") else {
            Issue.record("not moved")
            return
        }
        #expect(next.collections == [work.1])
        #expect(next.link(added.1.id)?.collectionID == work.1.id)
    }

    @Test func movingByABlankNameOrIntoAFullShelfOfCollectionsChangesNothing() throws {
        let (library, ids) = library(with: ["https://a.example"])
        #expect(library.movingLink(ids[0], toCollectionNamed: "  ") == .collection(.nameEmpty))
        #expect(library.movingLink(UUID(), toCollectionNamed: "New") == .unknownLink)

        var full = library
        for index in 0..<Library.maxCollections { full = try #require(collection(in: full, "C\(index)")).0 }
        #expect(full.movingLink(ids[0], toCollectionNamed: "One more") == .collection(.full))
        // Into one it already has is still fine.
        guard case .moved = full.movingLink(ids[0], toCollectionNamed: "c5") else {
            Issue.record("a name it had was refused")
            return
        }
    }

    @Test func movingByNameIntoACollectionThatHoldsTheAddressLeavesNoNewCollectionBehind() throws {
        let work = try #require(collection(in: .empty, "Work"))
        let outside = try #require(add(work.0, "https://example.com/x"))
        let inside = try #require(add(outside.0, "https://example.com/x", to: work.1.id))
        #expect(inside.0.movingLink(outside.1.id, toCollectionNamed: "Work") == .duplicate(inside.1))
        // A new name for a link that cannot go anywhere is not kept either.
        let result = inside.0.movingLink(UUID(), toCollectionNamed: "Brand new")
        #expect(result == .unknownLink)
        #expect(inside.0.collections.count == 1)
    }

    // MARK: Ordering and reading through a collection

    @Test func theListOfACollectionHoldsItsLinksOnlyAndAllHoldsEveryLink() throws {
        let work = try #require(collection(in: .empty, "Work"))
        var library = work.0
        let a = try #require(add(library, "https://a.example", to: work.1.id))
        library = a.0
        let b = try #require(add(library, "https://b.example"))
        library = b.0
        #expect(library.orderedLinks(in: work.1.id).map(\.id) == [a.1.id])
        #expect(library.orderedLinks(in: nil).count == 2)
        #expect(library.orderedLinks(in: UUID()).isEmpty)
        #expect(library.linkCount(in: work.1.id) == 1)
    }

    // MARK: Cleaning up what was read

    @Test func sanitizingCutsEachShelfAtItsLimitAndNoLower() {
        var library = Library.empty
        for index in 0..<(Library.maxLinks + 1) {
            library.links.append(NookDesignLink(
                id: UUID(), url: "https://example.com/\(index)", name: "n\(index)", collectionID: nil,
                isFavorite: false, addedAt: day, lastOpenedAt: nil
            ))
        }
        for index in 0..<(Library.maxCollections + 1) {
            library.collections.append(NookDesignLinkCollection(id: UUID(), name: "C\(index)", createdAt: day))
        }
        let clean = library.sanitized()
        #expect(clean.links.count == Library.maxLinks)
        #expect(clean.collections.count == Library.maxCollections)
        #expect(clean.links.first?.url == "https://example.com/0")

        library.links.removeLast()
        library.collections.removeLast()
        #expect(library.sanitized().links.count == Library.maxLinks)
        #expect(library.sanitized().collections.count == Library.maxCollections)
    }

    @Test func sanitizingGivesARepeatedIdANewOneAndKeepsEveryLink() {
        let id = UUID()
        var library = Library.empty
        library.collections = [
            NookDesignLinkCollection(id: id, name: "A", createdAt: day), NookDesignLinkCollection(id: id, name: "B", createdAt: day),
        ]
        let linkID = UUID()
        library.links = ["https://a.example", "https://a.example"].map {
            NookDesignLink(id: linkID, url: $0, name: "same", collectionID: nil, isFavorite: false, addedAt: day, lastOpenedAt: nil)
        }
        let clean = library.sanitized()
        #expect(clean.links.count == 2, "an address is never dropped for repeating")
        #expect(Set(clean.links.map(\.id)).count == 2)
        #expect(Set(clean.collections.map(\.id)).count == 2)
    }

    @Test func sanitizingPutsALinkWhoseCollectionIsGoneInNoneAndFillsABlankName() {
        var library = Library.empty
        let gone = UUID()
        library.links = [
            NookDesignLink(id: UUID(), url: "https://example.com/docs", name: "   ", collectionID: gone, isFavorite: true, addedAt: day, lastOpenedAt: nil),
        ]
        let clean = library.sanitized()
        #expect(clean.links[0].collectionID == nil)
        #expect(clean.links[0].name == "example.com/docs")
        #expect(clean.links[0].isFavorite)
    }
}

private extension NookDesignCollectionOutcome {
    /// The name of the collection a change ended with.
    var collectionName: String? {
        if case let .done(_, collection) = self { return collection.name }
        return nil
    }
}
