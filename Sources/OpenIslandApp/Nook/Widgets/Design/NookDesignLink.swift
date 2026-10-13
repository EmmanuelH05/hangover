import Foundation

/// One saved link. The address is kept exactly as it was saved and opened
/// exactly as saved: the query and the fragment are never dropped or put in
/// another order.
struct NookDesignLink: Identifiable, Hashable, Sendable {
    var id: UUID
    var url: String
    /// What the card shows. Starts as the host and the last part of the
    /// path, and the user can change it.
    var name: String
    /// The collection it is filed under, or nil for none.
    var collectionID: UUID?
    var isFavorite: Bool
    var addedAt: Date
    /// When it was last opened from the card. Nil for a link never opened.
    var lastOpenedAt: Date?

    /// The latest of when it was added and when it was opened, which is
    /// what "most recent" means in the list.
    var recency: Date { max(addedAt, lastOpenedAt ?? addedAt) }

    /// The parts of the address. Nil for a saved text that is no link,
    /// which the loader never lets in.
    var address: NookDesignLinkAddress? {
        try? NookDesignLinkRules.address(from: url).get()
    }
}

/// A named group of links. A link is in one collection or in none.
struct NookDesignLinkCollection: Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date
}

/// What adding a link came to.
enum NookDesignLinkAddOutcome: Equatable, Sendable {
    case added(NookDesignLinkLibrary, NookDesignLink)
    /// The collection already holds this exact address.
    case duplicate(NookDesignLink)
    /// The shelf holds as many links as it may.
    case full
    /// The collection is not there.
    case unknownCollection
    /// The shelf has not been read yet. Only the store says this.
    case notLoaded
}

/// What a change to a collection came to.
enum NookDesignCollectionOutcome: Equatable, Sendable {
    case done(NookDesignLinkLibrary, NookDesignLinkCollection)
    /// The name is empty once it is cleaned.
    case nameEmpty
    /// Another collection already has this name, whatever its case.
    case nameTaken(NookDesignLinkCollection)
    /// There are as many collections as there may be.
    case full
    case unknown
}

/// What moving a link came to.
enum NookDesignLinkMoveOutcome: Equatable, Sendable {
    case moved(NookDesignLinkLibrary)
    /// The collection already holds this exact address.
    case duplicate(NookDesignLink)
    case unknownLink
    case unknownCollection
    case collection(NookDesignCollectionOutcome)
}

/// Everything the Links tab saves: the links and the collections. A plain
/// value. The editing rules below each return a changed copy, and the
/// store saves it.
struct NookDesignLinkLibrary: Equatable, Sendable {
    static let currentVersion = 1
    static let maxLinks = NookDesignLinkRules.maxLinks
    static let maxCollections = NookDesignLinkRules.maxCollections

    var version = NookDesignLinkLibrary.currentVersion
    /// Newest first, which is how a tie in the list is settled.
    var links: [NookDesignLink] = []
    var collections: [NookDesignLinkCollection] = []

    static let empty = NookDesignLinkLibrary()

    // MARK: Reading

    func link(_ id: UUID) -> NookDesignLink? {
        links.first { $0.id == id }
    }

    func collection(_ id: UUID) -> NookDesignLinkCollection? {
        collections.first { $0.id == id }
    }

    /// The collection with this name, whatever the case of either.
    func collection(named name: String) -> NookDesignLinkCollection? {
        let wanted = Self.cleanCollectionName(name)
        return collections.first { $0.name.compare(wanted, options: .caseInsensitive) == .orderedSame }
    }

    /// The links in a collection, or all of them for nil, in the order the
    /// card lists them.
    func orderedLinks(in collectionID: UUID?) -> [NookDesignLink] {
        NookDesignLinkRules.ordered(collectionID.map { id in links.filter { $0.collectionID == id } } ?? links)
    }

    /// The link that already has this address in this collection (nil for
    /// no collection). The address is compared as the exact text: a
    /// trailing slash, a fragment or a capital letter makes another link.
    /// Two links to one page in two collections are two links.
    func existingLink(url: String, in collectionID: UUID?) -> NookDesignLink? {
        links.first { $0.url == url && $0.collectionID == collectionID }
    }

    func linkCount(in collectionID: UUID) -> Int {
        links.filter { $0.collectionID == collectionID }.count
    }

    static func cleanCollectionName(_ name: String) -> String {
        NookDesignLinkRules.cleanName(name)
    }

    // MARK: Links

    /// Adds a link at the front of the list. The address and the name are
    /// taken as they are, and the caller has already checked the address.
    func addingLink(
        url: String,
        name: String,
        to collectionID: UUID? = nil,
        id: UUID = UUID(),
        now: Date = NookDesignFiles.now()
    ) -> NookDesignLinkAddOutcome {
        if let collectionID, collection(collectionID) == nil { return .unknownCollection }
        if let existing = existingLink(url: url, in: collectionID) { return .duplicate(existing) }
        guard links.count < Self.maxLinks else { return .full }
        let link = NookDesignLink(
            id: id, url: url, name: NookDesignLinkRules.cleanName(name), collectionID: collectionID,
            isFavorite: false, addedAt: now, lastOpenedAt: nil
        )
        var result = self
        result.links.insert(link, at: 0)
        return .added(result, link)
    }

    /// Renames a link. A name with nothing in it puts the name made from
    /// the address back.
    func renamingLink(_ id: UUID, to name: String) -> NookDesignLinkLibrary {
        updatingLink(id) { link in
            let cleaned = NookDesignLinkRules.cleanName(name)
            if cleaned.isEmpty, let address = link.address {
                link.name = NookDesignLinkRules.defaultName(for: address)
            } else {
                link.name = cleaned
            }
        }
    }

    func removingLink(_ id: UUID) -> NookDesignLinkLibrary {
        var result = self
        result.links.removeAll { $0.id == id }
        return result
    }

    func togglingFavorite(_ id: UUID) -> NookDesignLinkLibrary {
        updatingLink(id) { $0.isFavorite.toggle() }
    }

    /// Notes that a link was opened, which moves it up in the list.
    func markingOpened(_ id: UUID, now: Date = NookDesignFiles.now()) -> NookDesignLinkLibrary {
        updatingLink(id) { $0.lastOpenedAt = now }
    }

    /// Files a link under a collection, or under none for nil. A link
    /// cannot go where the same address already is.
    func movingLink(_ id: UUID, to collectionID: UUID?) -> NookDesignLinkMoveOutcome {
        guard let link = link(id) else { return .unknownLink }
        if let collectionID, collection(collectionID) == nil { return .unknownCollection }
        if link.collectionID == collectionID { return .moved(self) }
        if let existing = existingLink(url: link.url, in: collectionID) { return .duplicate(existing) }
        return .moved(updatingLink(id) { $0.collectionID = collectionID })
    }

    /// Files a link under the collection with this name, making the
    /// collection first when there is none. This is how a collection is
    /// created: by naming it when a link moves into it.
    func movingLink(
        _ id: UUID,
        toCollectionNamed name: String,
        newID: UUID = UUID(),
        now: Date = NookDesignFiles.now()
    ) -> NookDesignLinkMoveOutcome {
        guard link(id) != nil else { return .unknownLink }
        let target: NookDesignLinkCollection
        var working = self
        if let existing = collection(named: name) {
            target = existing
        } else {
            switch addingCollection(named: name, id: newID, now: now) {
            case let .done(library, made):
                working = library
                target = made
            case let .nameTaken(existing):
                target = existing
            case .nameEmpty: return .collection(.nameEmpty)
            case .full: return .collection(.full)
            case .unknown: return .collection(.unknown)
            }
        }
        // A link that cannot go leaves no collection made for it: the
        // outcome then carries no library, and the caller keeps its own.
        return working.movingLink(id, to: target.id)
    }

    // MARK: Collections

    func addingCollection(
        named name: String,
        id: UUID = UUID(),
        now: Date = NookDesignFiles.now()
    ) -> NookDesignCollectionOutcome {
        let cleaned = Self.cleanCollectionName(name)
        guard !cleaned.isEmpty else { return .nameEmpty }
        if let existing = collection(named: cleaned) { return .nameTaken(existing) }
        guard collections.count < Self.maxCollections else { return .full }
        let made = NookDesignLinkCollection(id: id, name: cleaned, createdAt: now)
        var result = self
        result.collections.append(made)
        return .done(result, made)
    }

    /// Renames a collection. Another collection's name is refused, in any
    /// case. The collection's own name in another case is fine.
    func renamingCollection(_ id: UUID, to name: String) -> NookDesignCollectionOutcome {
        guard collection(id) != nil else { return .unknown }
        let cleaned = Self.cleanCollectionName(name)
        guard !cleaned.isEmpty else { return .nameEmpty }
        if let other = collection(named: cleaned), other.id != id { return .nameTaken(other) }
        var result = self
        guard let index = result.collections.firstIndex(where: { $0.id == id }) else { return .unknown }
        result.collections[index].name = cleaned
        return .done(result, result.collections[index])
    }

    /// Removes a collection. Its links stay and are in no collection.
    func removingCollection(_ id: UUID) -> NookDesignLinkLibrary {
        guard collection(id) != nil else { return self }
        var result = self
        result.collections.removeAll { $0.id == id }
        for index in result.links.indices where result.links[index].collectionID == id {
            result.links[index].collectionID = nil
        }
        return result
    }

    // MARK: Cleaning up loaded data

    /// The library made safe to show: ids are unique, names are clean,
    /// nothing is over a limit, and a link whose collection is gone is in
    /// no collection. A repeated id gets a new one and is kept. Links are
    /// never dropped for repeating an address, only for being over a limit.
    func sanitized() -> NookDesignLinkLibrary {
        var result = NookDesignLinkLibrary()
        var collectionIDs = Set<UUID>()
        for collection in collections.prefix(Self.maxCollections) {
            var clean = collection
            if !collectionIDs.insert(clean.id).inserted {
                clean.id = UUID()
                collectionIDs.insert(clean.id)
            }
            clean.name = Self.cleanCollectionName(collection.name)
            result.collections.append(clean)
        }
        var linkIDs = Set<UUID>()
        for link in links.prefix(Self.maxLinks) {
            var clean = link
            if !linkIDs.insert(clean.id).inserted {
                clean.id = UUID()
                linkIDs.insert(clean.id)
            }
            clean.name = NookDesignLinkRules.cleanName(link.name)
            if clean.name.isEmpty, let address = clean.address { clean.name = NookDesignLinkRules.defaultName(for: address) }
            if let id = clean.collectionID, !collectionIDs.contains(id) { clean.collectionID = nil }
            result.links.append(clean)
        }
        return result
    }

    // MARK: Private

    private func updatingLink(_ id: UUID, _ change: (inout NookDesignLink) -> Void) -> NookDesignLinkLibrary {
        guard let index = links.firstIndex(where: { $0.id == id }) else { return self }
        var result = self
        change(&result.links[index])
        return result
    }
}
