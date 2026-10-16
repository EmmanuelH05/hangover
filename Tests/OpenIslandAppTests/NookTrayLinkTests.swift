import Foundation
import Testing
@testable import OpenIslandApp

@MainActor @Suite struct NookTrayLinkTests {
    @Test func aLinkedFileSharesTheDiskSpaceOfItsSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("Recording.mp4")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 4096).write(to: source)
        defer { try? FileManager.default.removeItem(at: root) }

        let defaults = MemoryDefaults()
        let store = NookTrayStore(
            folder: root.appendingPathComponent("tray"),
            clipboard: NookClipboardMonitor(pasteboard: NookFakePasteboard(), defaults: defaults),
            defaults: defaults
        )
        await store.add(fileAt: source, linking: true)?.value

        let item = try #require(store.items.first)
        #expect(item.linkedFrom == source.path)
        let stored = store.storedURL(for: item)
        let a = try FileManager.default.attributesOfItem(atPath: source.path)[.systemFileNumber] as? Int
        let b = try FileManager.default.attributesOfItem(atPath: stored.path)[.systemFileNumber] as? Int
        #expect(a != nil && a == b)
    }

    @Test func anOrdinaryAddStillCopies() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("photo.png")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 64).write(to: source)
        defer { try? FileManager.default.removeItem(at: root) }

        let defaults = MemoryDefaults()
        let store = NookTrayStore(
            folder: root.appendingPathComponent("tray"),
            clipboard: NookClipboardMonitor(pasteboard: NookFakePasteboard(), defaults: defaults),
            defaults: defaults
        )
        await store.add(fileAt: source)?.value

        let item = try #require(store.items.first)
        #expect(item.linkedFrom == nil)
        let a = try FileManager.default.attributesOfItem(atPath: source.path)[.systemFileNumber] as? Int
        let b = try FileManager.default.attributesOfItem(atPath: store.storedURL(for: item).path)[.systemFileNumber] as? Int
        #expect(a != b)
    }

    @Test func anOldIndexWithoutLinkedFromStillLoads() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","originalName":"a.png","storedName":"x/a.png","addedDate":0}"#
        let item = try JSONDecoder().decode(NookTrayItem.self, from: Data(json.utf8))
        #expect(item.linkedFrom == nil)
    }
}
