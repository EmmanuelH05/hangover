import AppKit
import Foundation
import UniformTypeIdentifiers

/// How one file of a drop or a paste ended.
enum NookDesignBatchOutcome: CaseIterable, Sendable {
    case added
    /// It is on the shelf and the list that names it was not written.
    case addedNotSaved
    /// Not a picture: it went to the file tray, which is where the island
    /// promises every other file goes (D20).
    case toTray
    case notAPicture
    case unreadable
    case previewFailed
    case tooLarge
    case full
    case failed
    /// The provider of the drop did not hand the file over.
    case dropFailed

    /// The words that count this outcome in the one line a batch ends in.
    var countKey: String {
        switch self {
        case .added: "nook.design.batch.added"
        case .addedNotSaved: "nook.design.batch.notSaved"
        case .toTray: "nook.design.batch.toTray"
        case .notAPicture: "nook.design.batch.notAPicture"
        case .unreadable: "nook.design.batch.unreadable"
        case .previewFailed: "nook.design.batch.previewFailed"
        case .tooLarge: "nook.design.batch.tooLarge"
        case .full: "nook.design.batch.full"
        case .failed: "nook.design.batch.failed"
        case .dropFailed: "nook.design.batch.dropFailed"
        }
    }

    var isGoodNews: Bool { self == .added || self == .toTray }

    /// The outcome an add came to. A picture already on the shelf and a
    /// refusal the shelf already said are not counted.
    static func of(_ result: NookDesignReferenceAddResult) -> NookDesignBatchOutcome? {
        switch result {
        case .added: .added
        case .addedNotSaved: .addedNotSaved
        case .notAPicture: .notAPicture
        case .unreadable: .unreadable
        case .previewFailed: .previewFailed
        case .tooLarge: .tooLarge
        case .full: .full
        case .failed: .failed
        case .alreadyHere, .locked: nil
        }
    }
}

/// The files of one drop or paste. Each one ends one way, and when the last
/// has ended the kit says it all in one line, which a later file cannot
/// take the place of.
@MainActor
final class NookDesignReferenceBatch {
    enum Entry: Equatable {
        case result(NookDesignReferenceAddResult)
        case toTray
        case dropFailed
    }

    let expected: Int
    private(set) var entries: [Entry] = []
    private let finish: (NookDesignReferenceBatch) -> Void

    init(expected: Int, finish: @escaping (NookDesignReferenceBatch) -> Void) {
        self.expected = expected
        self.finish = finish
    }

    func record(_ entry: Entry) {
        entries.append(entry)
        if entries.count == expected { finish(self) }
    }

    var counts: [NookDesignBatchOutcome: Int] {
        var counts: [NookDesignBatchOutcome: Int] = [:]
        for entry in entries {
            let outcome: NookDesignBatchOutcome?
            switch entry {
            case let .result(result): outcome = NookDesignBatchOutcome.of(result)
            case .toTray: outcome = .toTray
            case .dropFailed: outcome = .dropFailed
            }
            if let outcome { counts[outcome, default: 0] += 1 }
        }
        return counts
    }
}

extension NookDesignKit {
    // MARK: Dropping

    /// Takes what was dropped on the card: files, or picture data such as an
    /// image dragged out of a browser. A file that is a picture goes to the
    /// shelf, and every other file goes to the file tray, as it does when it
    /// is dropped anywhere else on the island. True when the drop was taken.
    func handlePictureDrop(_ providers: [NSItemProvider]) -> Bool {
        enum Taken {
            case file(NSItemProvider)
            case image(NSItemProvider, type: String)
        }
        var taken: [Taken] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                taken.append(.file(provider))
            } else if let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) {
                // The picture is asked for by the type it was offered as.
                taken.append(.image(provider, type: type))
            }
        }
        guard !taken.isEmpty else { return false }

        let batch = NookDesignReferenceBatch(expected: taken.count) { [weak self] in self?.finish($0) }
        for item in taken {
            switch item {
            case let .file(provider):
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { loaded, _ in
                    var url: URL?
                    if let data = loaded as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let direct = loaded as? URL {
                        url = direct
                    }
                    Task { @MainActor in
                        guard let url, url.isFileURL else { return batch.record(.dropFailed) }
                        self.route(droppedFile: url, in: batch)
                    }
                }
            case let .image(provider, type):
                let name = provider.suggestedName ?? ""
                _ = provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                    Task { @MainActor in
                        guard let data else { return batch.record(.dropFailed) }
                        let result = await self.references.add(imageData: data, named: name).value
                        batch.record(.result(result))
                    }
                }
            }
        }
        return true
    }

    /// A dropped file is a picture when it opens as one. A name proves
    /// nothing.
    private func route(droppedFile url: URL, in batch: NookDesignReferenceBatch) {
        Task { @MainActor in
            let isPicture = await Task.detached(priority: .userInitiated) {
                NookDesignPictures.inspect(fileAt: url) != nil
            }.value
            if isPicture {
                batch.record(.result(await references.add(fileAt: url).value))
            } else if let tray = nook?.tray {
                tray.add(fileAt: url)
                batch.record(.toTray)
            } else {
                batch.record(.result(.notAPicture))
            }
        }
    }

    // MARK: Adding

    /// Copies a picture file onto the shelf and says how it went.
    @discardableResult
    func addReference(fileAt url: URL) -> Task<Void, Never> {
        let adding = references.add(fileAt: url)
        return Task { [weak self] in
            let result = await adding.value
            self?.report(result)
        }
    }

    @discardableResult
    func addReference(imageData data: Data, named name: String) -> Task<Void, Never> {
        let adding = references.add(imageData: data, named: name)
        return Task { [weak self] in
            let result = await adding.value
            self?.report(result)
        }
    }

    /// Reads the clipboard once, because the user pressed Paste, and adds
    /// the pictures on it. Several files end in one line that counts them.
    @discardableResult
    func pasteReference() -> [Task<Void, Never>] {
        guard let pictureClipboard else { return [] }
        let read = readClipboard(from: pictureClipboard, emptyNotice: "nook.design.notice.nothingToPaste") { () -> NookDesignPastedPictures? in
            let pictures = pictureClipboard.readPictures()
            if case .none = pictures { return nil }
            return pictures
        }
        guard case let .got(pictures) = read else { return [] }
        switch pictures {
        case let .files(urls):
            guard urls.count > 1 else { return urls.map { addReference(fileAt: $0) } }
            let batch = NookDesignReferenceBatch(expected: urls.count) { [weak self] in self?.finish($0) }
            return urls.map { url in
                Task { batch.record(.result(await references.add(fileAt: url).value)) }
            }
        case let .data(data):
            return [addReference(imageData: data, named: LanguageManager.shared.t("nook.design.reference.pasted"))]
        case .none:
            return []
        }
    }

    // MARK: Saying how it went

    /// The line for a batch that has ended. One file has its own lines.
    private func finish(_ batch: NookDesignReferenceBatch) {
        if batch.expected == 1, let entry = batch.entries.first {
            switch entry {
            case let .result(result): report(result)
            case .toTray: post("nook.design.notice.droppedToTray", .done)
            case .dropFailed: post("nook.design.notice.dropFailed", .error)
            }
            return
        }
        let counts = batch.counts
        let parts = NookDesignBatchOutcome.allCases.compactMap { outcome -> String? in
            counts[outcome].map { LanguageManager.shared.t(outcome.countKey, $0) }
        }
        guard !parts.isEmpty else { return }
        if counts[.added] != nil || counts[.addedNotSaved] != nil { tab = .references }
        let isGood = counts.keys.allSatisfy(\.isGoodNews)
        postText(parts.joined(separator: ", "), isGood ? .done : .error)
    }

    func report(_ result: NookDesignReferenceAddResult) {
        switch result {
        case .added:
            tab = .references
            post("nook.design.notice.referenceAdded", .done)
        case .unreadable: post("nook.design.notice.referenceUnreadable", .error)
        case .notAPicture: post("nook.design.notice.notAPicture", .error)
        case .previewFailed: post("nook.design.notice.referencePreviewFailed", .error)
        case .tooLarge: post("nook.design.notice.pictureTooLarge", .error)
        case .full: post("nook.design.notice.referencesFull", .error)
        case .failed: post("nook.design.notice.referenceFailed", .error)
        case .alreadyHere, .locked: break
        case .addedNotSaved:
            tab = .references
            post("nook.design.notice.referenceNotSaved", .error)
        }
    }
}
