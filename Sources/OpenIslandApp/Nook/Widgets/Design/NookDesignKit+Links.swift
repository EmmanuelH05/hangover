import Foundation

/// What the Links tab is asking a name for. One question at a time.
enum NookDesignLinkNaming: Hashable, Sendable {
    /// A new name for a link.
    case renamingLink(UUID)
    /// A name for a collection that does not exist yet, which the link is
    /// then moved into.
    case newCollection(forLink: UUID)
    /// A new name for a collection.
    case renamingCollection(UUID)
}

/// What typing or pasting a link came to.
enum NookDesignLinkEntryResult: Equatable, Sendable {
    case added(NookDesignLink)
    /// The collection already has this exact address.
    case duplicate(NookDesignLink)
    case refused(NookDesignLinkRefusal)
    /// The shelf holds as many links as it may.
    case full
    /// The clipboard held no text.
    case nothingToPaste
    /// macOS does not let the app read the clipboard.
    case notAllowed
    /// The shelf has not been read yet, or the kit has no clipboard.
    case unavailable
}

/// The Links tab: adding, opening, copying and organizing. The rules are
/// in `NookDesignLinkRules` and `NookDesignLinkLibrary`; this is the part
/// that talks to the opener, the clipboard and the card's notice.
extension NookDesignKit {
    /// The collection the new links go to: the lit chip, or none. A chip
    /// whose collection was deleted counts as All.
    var activeLinkCollectionID: UUID? {
        selectedLinkCollectionID.flatMap { links.library.collection($0) == nil ? nil : $0 }
    }

    func selectLinkCollection(_ id: UUID?) {
        selectedLinkCollectionID = id
    }

    // MARK: Adding

    /// Adds typed or pasted text as a link, or says why it cannot.
    @discardableResult
    func addLink(text: String) -> NookDesignLinkEntryResult {
        switch NookDesignLinkRules.address(from: text) {
        case let .failure(reason):
            post(reason.noticeKey, .info)
            return .refused(reason)
        case let .success(address):
            return addLink(address)
        }
    }

    /// Reads the clipboard once, because the user pressed Paste link, and
    /// adds what is on it if it is a link.
    @discardableResult
    func pasteLink() -> NookDesignLinkEntryResult {
        guard let pictureClipboard else { return .unavailable }
        switch readClipboard(from: pictureClipboard, emptyNotice: "nook.design.notice.linkNoText", { pictureClipboard.readText() }) {
        case let .got(text): return addLink(text: text)
        case .notAllowed: return .notAllowed
        case .nothing: return .nothingToPaste
        }
    }

    private func addLink(_ address: NookDesignLinkAddress) -> NookDesignLinkEntryResult {
        switch links.addLink(address, to: activeLinkCollectionID, now: now()) {
        case let .added(_, link):
            let name = link.name
            sayAfterWrite { $0.post("nook.design.notice.linkAdded", .done, name) }
            return .added(link)
        case let .duplicate(existing):
            post("nook.design.notice.linkDuplicate", .info)
            return .duplicate(existing)
        case .full:
            post("nook.design.notice.linksFull", .error, NookDesignLinkLibrary.maxLinks)
            return .full
        case .unknownCollection, .notLoaded:
            return .unavailable
        }
    }

    // MARK: Opening and copying

    /// Opens a link exactly as it was saved. When the opener says no, or
    /// there is none, a notice says it did not open and nothing else changes: the link
    /// is not marked as opened and does not move.
    @discardableResult
    func openLink(_ id: UUID) -> Bool {
        guard let link = links.link(id) else { return false }
        // The saved text is checked again, because the file may have been
        // edited by hand since it was read.
        guard let url = NookDesignLinkRules.openableURL(for: link.url),
              let linkOpener, linkOpener.open(url) else {
            post("nook.design.notice.linkNotOpened", .error, link.name)
            return false
        }
        links.markOpened(id, now: now())
        return true
    }

    /// Copies a link's address through the same door a color is copied
    /// through, which keeps it out of the clipboard history. The row shows
    /// the same tick a copied color shows.
    @discardableResult
    func copyLink(_ id: UUID) -> Bool {
        guard let link = links.link(id) else { return false }
        guard copyText?(link.url) == true else {
            post("nook.design.notice.copyFailed", .error)
            return false
        }
        post("nook.design.notice.linkCopied", .done, link.name)
        flash(id)
        return true
    }

    // MARK: Organizing

    func toggleLinkFavorite(_ id: UUID) {
        links.toggleFavorite(id)
    }

    func deleteLink(_ id: UUID) {
        if case .renamingLink(id)? = linkNaming { linkNaming = nil }
        if case .newCollection(forLink: id)? = linkNaming { linkNaming = nil }
        links.removeLink(id)
    }

    /// Files a link under a collection, or under none for nil.
    @discardableResult
    func moveLink(_ id: UUID, to collectionID: UUID?) -> Bool {
        switch links.moveLink(id, to: collectionID) {
        case .moved:
            return true
        case .duplicate:
            post("nook.design.notice.linkMoveDuplicate", .info)
            return false
        case .unknownLink, .unknownCollection, .collection:
            return false
        }
    }

    /// Files a link under the collection of this name, making it first
    /// when there is none.
    @discardableResult
    func moveLink(_ id: UUID, toCollectionNamed name: String) -> Bool {
        switch links.moveLink(id, toCollectionNamed: name) {
        case .moved:
            return true
        case .duplicate:
            post("nook.design.notice.linkMoveDuplicate", .info)
        case .collection(.nameEmpty):
            post("nook.design.notice.collectionNameEmpty", .info)
        case .collection(.full):
            post("nook.design.notice.collectionsFull", .error, NookDesignLinkLibrary.maxCollections)
        case .unknownLink, .unknownCollection, .collection:
            break
        }
        return false
    }

    @discardableResult
    func renameCollection(_ id: UUID, to name: String) -> Bool {
        switch links.renameCollection(id, to: name) {
        case .done:
            return true
        case .nameTaken:
            post("nook.design.notice.collectionNameTaken", .info)
        case .nameEmpty:
            post("nook.design.notice.collectionNameEmpty", .info)
        case .full, .unknown:
            break
        }
        return false
    }

    /// Removes a collection. Its links stay and are in no collection.
    func deleteCollection(_ id: UUID) {
        if selectedLinkCollectionID == id { selectedLinkCollectionID = nil }
        if case .renamingCollection(id)? = linkNaming { linkNaming = nil }
        links.removeCollection(id)
    }

    // MARK: Asking for a name

    /// True while the card has a question open that wants a name typed: a
    /// link, a collection or a reference picture. The island does not close
    /// under the pointer for as long (`OverlayUICoordinator`), because a
    /// question with nothing typed yet is not a draft.
    var isAskingForName: Bool { linkNaming != nil || renamingReferenceID != nil }

    func beginNaming(_ naming: NookDesignLinkNaming) {
        linkNaming = naming
        onNameQuestionOpened()
    }

    /// Asks for a new name for a picture on the shelf.
    func beginRenamingReference(_ id: UUID) {
        renamingReferenceID = id
        onNameQuestionOpened()
    }

    /// Puts any open name question away. Runs on every way the island
    /// closes or turns to another page.
    func endNaming() {
        linkNaming = nil
        renamingReferenceID = nil
    }

    func cancelNaming() {
        linkNaming = nil
    }

    /// What the name field starts with.
    func namingSeed(for naming: NookDesignLinkNaming) -> String {
        switch naming {
        case let .renamingLink(id): links.link(id)?.name ?? ""
        case .newCollection: ""
        case let .renamingCollection(id): links.library.collection(id)?.name ?? ""
        }
    }

    /// Keeps the typed name. The question stays up when the name was
    /// refused, with the notice saying why.
    @discardableResult
    func commitNaming(_ text: String) -> Bool {
        guard let naming = linkNaming else { return false }
        let kept: Bool
        switch naming {
        case let .renamingLink(id):
            links.renameLink(id, to: text)
            kept = true
        case let .newCollection(forLink: id):
            kept = moveLink(id, toCollectionNamed: text)
        case let .renamingCollection(id):
            kept = renameCollection(id, to: text)
        }
        if kept { linkNaming = nil }
        return kept
    }
}
