import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Draws the Notes card and the pinned editor with `ImageRenderer`, on a
/// store of its own with files in a temporary folder. Set
/// `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to also write the PNGs to
/// `output/render/notes/` under the repo root for a visual check.
///
/// `ImageRenderer` cannot draw AppKit-backed views, which is why the list
/// and the editor are drawn still: the scroll view and the text editor are
/// swapped for plain look-alikes. No window is opened and the Notes app is
/// never reached.
@MainActor
@Suite(.noNewWindows)
struct NookNotesCardRenderTests {
    private static let scale: CGFloat = 2
    private static let snapshotEnvKey = "OPEN_ISLAND_RENDER_SNAPSHOTS"

    private static func cardSize(_ size: NookWidgetSize) -> CGSize {
        CGSize(width: size == .small ? 204 : 416, height: NookNotesCard.height(for: size))
    }

    private func model(notes: [String] = []) -> (NookModel, NookNotesHarness) {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        for text in notes {
            harness.date = harness.date.addingTimeInterval(60)
            store.beginNewNote()
            store.edit(text)
            store.closeEditor()
        }
        let nook = NookModel(notes: store, defaults: MemoryDefaults(), looksForImportedGIF: false)
        return (nook, harness)
    }

    private let sample = [
        "Try the new cache key\nCheck the hit rate",
        "Ask about the midterm room",
        "Idea: widget presets",
        "Send the slides tonight",
        "Read chapter 6",
    ]

    @Test(arguments: NookWidgetSize.allCases)
    func theCardWithNotesIsNotTheCardWithout(size: NookWidgetSize) throws {
        let (empty, emptyHarness) = model()
        let (full, fullHarness) = model(notes: sample)
        defer { _ = (emptyHarness, fullHarness) }

        let none = try card("empty-\(size.rawValue)", empty, size)
        let some = try card("notes-\(size.rawValue)", full, size, writes: true)

        #expect(none != some)
    }

    @Test(arguments: NookWidgetSize.allCases)
    func theCardWithTheEditorOpenIsNotTheListCard(size: NookWidgetSize) throws {
        let (nook, harness) = model(notes: sample)
        defer { _ = harness }
        let list = try card("list", nook, size)

        nook.notes.beginNewNote()
        nook.notes.edit("A note being written\nwith a second line")
        let editing = try card("editing-\(size.rawValue)", nook, size, writes: true)

        #expect(list != editing)
    }

    @Test func theEditorShowsTheTextTypedAndThePlaceholderBefore() throws {
        let (nook, harness) = model()
        defer { _ = harness }
        nook.notes.beginNewNote()
        let blank = try card("blank", nook, .medium)

        nook.notes.edit("Hello there")
        let typed = try card("typed", nook, .medium)

        #expect(blank != typed)
    }

    @Test func thePinnedEditorIsDrawn() throws {
        let (nook, harness) = model()
        defer { _ = harness }
        nook.notes.beginNewNote()
        nook.notes.edit("Written from the shortcut")

        let pinned = NookPinnedNoteEditor(nook: nook, isStill: true)
            .frame(width: 416, height: NookNoteSizes.pinnedEditorHeight)
            .padding(8)
            .background(V6Palette.ink)
            .environment(\.colorScheme, .dark)
        let picture = try render("pinned", pinned, writes: true)

        #expect(!picture.isEmpty)
    }

    @Test func moreNotesThanRowsDrawOnlyTheRowsTheCardShows() throws {
        let (nook, harness) = model(notes: sample)
        defer { _ = harness }
        let five = try card("five", nook, .medium)

        nook.notes.beginNewNote()
        nook.notes.edit("Sixth")
        nook.notes.closeEditor()
        let six = try card("six", nook, .medium)

        // Medium shows four rows: the newest four are the same either way
        // except for the one that is new.
        #expect(five != six)
    }

    // MARK: Drawing

    private func card(_ name: String, _ nook: NookModel, _ size: NookWidgetSize, writes: Bool = false) throws -> Data {
        let cardSize = Self.cardSize(size)
        let framed = NookNotesCard(nook: nook, isStill: true)
            .environment(\.nookWidgetSize, size)
            .frame(width: cardSize.width, height: cardSize.height)
            .padding(8)
            .background(V6Palette.ink)
            .environment(\.colorScheme, .dark)
        return try render(name, framed, writes: writes)
    }

    private func render(_ name: String, _ view: some View, writes: Bool) throws -> Data {
        let renderer = ImageRenderer(content: view)
        renderer.scale = Self.scale
        let image = try #require(renderer.cgImage, "ImageRenderer returned no image for \(name)")
        let png = try #require(
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
            "PNG encoding failed for \(name)"
        )
        if writes, ProcessInfo.processInfo.environment[Self.snapshotEnvKey] == "1" {
            let directory = Self.repoRoot.appendingPathComponent("output/render/notes", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return png
    }

    /// `Tests/OpenIslandAppTests/<this file>` sits three levels below the root.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
