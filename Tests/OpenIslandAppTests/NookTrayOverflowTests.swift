import Foundation
import Testing
@testable import OpenIslandApp

/// The tray's overflow choice, the row arithmetic and the all-files state,
/// on a folder and settings of their own held in a temp folder and memory.
@MainActor
private struct OverflowFixture {
    let store: NookTrayStore
    let folder: URL
    let incoming: URL
    let defaults: UserDefaults

    init(defaults: UserDefaults = MemoryDefaults()) throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NookTrayOverflowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        incoming = FileManager.default.temporaryDirectory
            .appendingPathComponent("NookTrayOverflowIncoming-\(UUID().uuidString)", isDirectory: true)
        self.defaults = defaults
        store = Self.makeStore(folder: folder, defaults: defaults)
    }

    static func makeStore(folder: URL, defaults: UserDefaults) -> NookTrayStore {
        NookTrayStore(
            folder: folder,
            clipboard: NookClipboardMonitor(pasteboard: NookFakePasteboard(), defaults: defaults),
            defaults: defaults
        )
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.removeItem(at: incoming)
    }

    /// Puts a file in the tray under `name` and waits for the copy.
    @discardableResult
    func add(named name: String, contents: URL? = nil) async throws -> NookTrayItem {
        let source = incoming.appendingPathComponent("incoming-\(UUID().uuidString)").appendingPathComponent(name)
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let contents {
            try FileManager.default.copyItem(at: contents, to: source)
        } else {
            try Data("hello".utf8).write(to: source)
        }
        await store.add(fileAt: source)?.value
        return try #require(store.items.first { $0.originalName == name })
    }
}

@MainActor @Suite(.serialized, .noNewWindows) struct NookTrayOverflowTests {
    // MARK: The choice

    @Test func scrollIsTheDefault() throws {
        let fixture = try OverflowFixture()
        defer { fixture.cleanUp() }
        #expect(fixture.store.overflow == .scroll)
    }

    @Test func theChoicePersistsInTheDefaultsItWasGiven() throws {
        let fixture = try OverflowFixture()
        defer { fixture.cleanUp() }
        fixture.store.overflow = .count
        let second = OverflowFixture.makeStore(folder: fixture.folder, defaults: fixture.defaults)
        #expect(second.overflow == .count)
    }

    @Test func anUnknownStoredValueReadsScroll() throws {
        let defaults = MemoryDefaults()
        defaults.set("sideways", forKey: NookTrayStore.overflowKey)
        let fixture = try OverflowFixture(defaults: defaults)
        defer { fixture.cleanUp() }
        #expect(fixture.store.overflow == .scroll)
    }

    // MARK: The row math

    @Test func smallAtCompactFitsSixSlotsAndShowsFive() {
        let slots = NookTrayRowLayout.slots(width: 285, tileWidth: 40)
        #expect(slots == 6)
        #expect(NookTrayRowLayout.shown(count: 145, slots: slots) == 5)
    }

    @Test func mediumAtRegularFitsTenSlotsAndShowsNine() {
        let slots = NookTrayRowLayout.slots(width: 612, tileWidth: 52)
        #expect(slots == 10)
        #expect(NookTrayRowLayout.shown(count: 145, slots: slots) == 9)
    }

    @Test func aRowThatFitsShowsEveryFile() {
        #expect(NookTrayRowLayout.shown(count: 4, slots: 6) == 4)
        #expect(NookTrayRowLayout.shown(count: 6, slots: 6) == 6)
    }

    @Test func slotsAreNeverBelowOne() {
        #expect(NookTrayRowLayout.slots(width: 0, tileWidth: 40) == 1)
        #expect(NookTrayRowLayout.slots(width: 10, tileWidth: 400) == 1)
        #expect(NookTrayRowLayout.shown(count: 5, slots: 1) == 0)
    }

    // MARK: All files

    @Test func showAllFilesNeedsFiles() throws {
        let fixture = try OverflowFixture()
        defer { fixture.cleanUp() }
        fixture.store.showAllFiles()
        #expect(!fixture.store.isShowingAllFiles)
    }

    @Test func showAllFilesAndHideAllFilesToggleTheState() async throws {
        let fixture = try OverflowFixture()
        defer { fixture.cleanUp() }
        try await fixture.add(named: "a.txt")
        fixture.store.showAllFiles()
        #expect(fixture.store.isShowingAllFiles)
        fixture.store.hideAllFiles()
        #expect(!fixture.store.isShowingAllFiles)
    }

    @Test func openingTheConvertStripClosesAllFiles() async throws {
        let fixture = try OverflowFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.add(named: "a.txt")
        fixture.store.showAllFiles()
        fixture.store.convertSourceItem = item
        #expect(!fixture.store.isShowingAllFiles)
        #expect(fixture.store.convertSourceItem == item)
    }

    @Test func openingTheGIFOptionsClosesAllFiles() async throws {
        let fixture = try OverflowFixture()
        defer { fixture.cleanUp() }
        let files = try NookConvertFixtures()
        defer { files.cleanUp() }
        let item = try await fixture.add(named: "clip.mov", contents: try files.movie(seconds: 1))
        fixture.store.showAllFiles()
        #expect(fixture.store.isShowingAllFiles)
        #expect(fixture.store.convert(item, action: .makeGIF) == nil)
        #expect(fixture.store.gifSourceItem == item)
        #expect(!fixture.store.isShowingAllFiles)
    }

    @Test func showAllFilesClosesAnOpenConvertStrip() async throws {
        let fixture = try OverflowFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.add(named: "a.txt")
        fixture.store.convertSourceItem = item
        fixture.store.showAllFiles()
        #expect(fixture.store.convertSourceItem == nil)
        #expect(fixture.store.isShowingAllFiles)
    }

    @Test func showAllFilesClosesAnOpenGIFStrip() async throws {
        let fixture = try OverflowFixture()
        defer { fixture.cleanUp() }
        let files = try NookConvertFixtures()
        defer { files.cleanUp() }
        let item = try await fixture.add(named: "clip.mov", contents: try files.movie(seconds: 1))
        _ = fixture.store.convert(item, action: .makeGIF)
        #expect(fixture.store.gifSourceItem == item)
        fixture.store.showAllFiles()
        #expect(fixture.store.gifSourceItem == nil)
        #expect(fixture.store.isShowingAllFiles)
    }

    @Test func clearingTheTrayClosesAllFiles() async throws {
        let fixture = try OverflowFixture()
        defer { fixture.cleanUp() }
        try await fixture.add(named: "a.txt")
        fixture.store.showAllFiles()
        fixture.store.clear()
        #expect(fixture.store.items.isEmpty)
        #expect(!fixture.store.isShowingAllFiles)
    }

    @Test func removingTheLastFileClosesAllFiles() async throws {
        let fixture = try OverflowFixture()
        defer { fixture.cleanUp() }
        let item = try await fixture.add(named: "a.txt")
        fixture.store.showAllFiles()
        fixture.store.remove(item)
        #expect(!fixture.store.isShowingAllFiles)
    }
}
