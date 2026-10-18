import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// A model with a to-do hub whose apps hold the frames' sample tasks (T4).
/// Nothing here reaches the network, a token file or the real settings:
/// the services take a stub transport and an in-memory token store, and
/// Reminders holds its sample rows. The Asana and monday services are fed
/// through their `items` and `state`, which needs no network either.
@MainActor
struct NookTodoCardHarness {
    let nook: NookModel
    let hub: NookTodoHub
    let tickTick: NookTickTickTodoService
    let asana: NookAsanaTodoService
    let monday: NookMondayTodoService

    private static let calendar = Calendar.current

    private static func day(_ offset: Int) -> Date {
        let start = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: offset, to: start) ?? start
    }

    private static func item(_ id: String, _ title: String, due: Date? = nil, list: String) -> NookTodoItem {
        NookTodoItem(id: id, title: title, dueDate: due, isCompleted: false, listName: list)
    }

    /// `enabled` are the apps switched on, `addKind` where a typed task goes.
    init(enabled: [NookTodoSourceKind], addKind: NookTodoSourceKind? = nil, reminders sample: [NookTodoItem]? = nil) {
        let defaults = MemoryDefaults()
        let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("hangover-todo-card-render", isDirectory: true)
        tickTick = NookTickTickTodoService(
            defaults: defaults, transport: StubTodoTransport(), tokenStore: InMemoryTodoTokenStore(),
            cache: TickTickTodoCache(directory: folder.appendingPathComponent("TickTick", isDirectory: true))
        )
        asana = NookAsanaTodoService(
            defaults: defaults, transport: StubTodoTransport(), tokenStore: InMemoryTodoTokenStore()
        )
        monday = NookMondayTodoService(
            defaults: defaults, transport: StubTodoTransport(), tokenStore: InMemoryTodoTokenStore()
        )
        hub = NookTodoHub(
            defaults: defaults,
            notion: NookNotionTodoService(
                defaults: defaults, transport: StubTodoTransport(), tokenStore: InMemoryTodoTokenStore(),
                cache: NotionTodoCache(directory: folder.appendingPathComponent("Notion", isDirectory: true))
            ),
            tickTick: tickTick,
            asana: asana,
            monday: monday
        )
        let remindersSample = sample ?? [
            Self.item("r1", "Finish problem set 3", due: Self.day(0), list: "Reminders"),
            Self.item("r2", "Renew parking permit", list: "Reminders"),
        ]
        nook = NookModel(
            reminders: NookRemindersService(defaults: defaults, sample: remindersSample),
            todo: hub,
            defaults: defaults,
            looksForImportedGIF: false,
            asksMacOSForAccess: false
        )
        asana.items = [
            Self.item("asana:1", "Write the sprint notes", due: Self.day(-1), list: "UCLA Blueprint"),
            Self.item("asana:2", "Email the TA", due: Self.day(0), list: "UCLA Blueprint"),
        ]
        asana.state = .ready
        monday.items = [Self.item("monday:1", "Review the pull request", due: Self.day(1), list: "Sprint board")]
        monday.state = .ready
        tickTick.rows = [
            TickTickRow(
                item: Self.item("tt1", "Book flights", due: Self.day(4), list: "Inbox"),
                projectID: "inbox", notesField: .content
            ),
        ]
        tickTick.state = .ready
        for kind in enabled { hub.setEnabled(kind, true) }
        if let addKind { hub.setAddKind(addKind) }
    }
}

/// Draws the to-do card the way the grid does, dark and still, at the
/// width the design frames use. With `OPEN_ISLAND_RENDER_SNAPSHOTS=1` the
/// PNGs also go to `output/render/todo-sources/` under the repo root.
@MainActor
enum NookTodoCardSnapshot {
    static let margin: CGFloat = 8
    static let scale: CGFloat = 2

    /// Card widths of the frames (`design/todo-sources`, T2).
    static func width(_ size: NookWidgetSize) -> CGFloat {
        switch size {
        case .small: 219
        case .medium: 448
        case .large: 488
        }
    }

    static func card(_ harness: NookTodoCardHarness, size: NookWidgetSize) -> some View {
        NookTodoCard(nook: harness.nook)
            .environment(\.nookWidgetSize, size)
            .frame(width: width(size), height: NookTodoCard.height(for: size))
    }

    static func render(_ name: String, _ view: some View, writes: Bool = true) throws -> CGImage {
        let framed = view
            .padding(margin)
            .background(V6Palette.ink)
            .environment(\.colorScheme, .dark)
            .environment(\.nookDrawsStill, true)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = scale
        let image = try #require(renderer.cgImage, "ImageRenderer returned no image for \(name)")
        if writes, ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_SNAPSHOTS"] == "1" {
            let png = try #require(
                NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
                "PNG encoding failed for \(name)"
            )
            let directory = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("output/render/todo-sources", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return image
    }

    /// The bytes of a picture, to tell two renders apart.
    static func bytes(_ image: CGImage) -> Data {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) ?? Data()
    }
}

/// The chip's open menu, drawn as a still: an open `Menu` is a window of
/// its own and an image renderer cannot show it. The rows are the hub's
/// `addableKinds` with a tick on the add target (T6).
private struct NookTodoAddMenuStill: View {
    let hub: NookTodoHub

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(hub.addableKinds) { kind in
                HStack(spacing: 8) {
                    Circle().fill(kind.dotColor).frame(width: 6, height: 6)
                    Text(LanguageManager.shared.t(kind.nameKey))
                        .font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 12)
                    if kind == hub.addKind {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                    }
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 5).fill(kind == hub.addKind ? .white.opacity(0.12) : .clear))
            }
        }
        .padding(4)
        .frame(width: 150)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.14)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1)))
    }
}

@MainActor @Suite(.serialized, .noNewWindows) struct NookTodoCardRenderTests {
    private static let four: [NookTodoSourceKind] = [.reminders, .asana, .monday, .tickTick]

    @Test func groupedSmall() throws {
        let harness = NookTodoCardHarness(enabled: Self.four, addKind: .asana)
        let image = try NookTodoCardSnapshot.render("card-grouped-small", NookTodoCardSnapshot.card(harness, size: .small))
        #expect(image.width > 0)
        let sections = NookTodoCardSections(
            sections: harness.hub.sections(reminders: harness.nook.reminders),
            budget: NookTodoCard.maxRows(for: .small), size: .small
        )
        #expect(sections.lines.count == 3)
        #expect(sections.openCount == 6)
    }

    @Test func groupedMedium() throws {
        let harness = NookTodoCardHarness(enabled: Self.four, addKind: .asana)
        let image = try NookTodoCardSnapshot.render("card-grouped", NookTodoCardSnapshot.card(harness, size: .medium))
        #expect(image.width > 0)
        let sections = NookTodoCardSections(
            sections: harness.hub.sections(reminders: harness.nook.reminders),
            budget: NookTodoCard.maxRows(for: .medium), size: .medium
        )
        #expect(sections.lines.last == .more(4))
    }

    @Test func groupedLarge() throws {
        let harness = NookTodoCardHarness(enabled: Self.four, addKind: .asana)
        let image = try NookTodoCardSnapshot.render("card-grouped-large", NookTodoCardSnapshot.card(harness, size: .large))
        #expect(image.width > 0)
        let sections = NookTodoCardSections(
            sections: harness.hub.sections(reminders: harness.nook.reminders),
            budget: NookTodoCard.maxRows(for: .large), size: .large
        )
        #expect(sections.lines.count <= 8)
        #expect(sections.hidden == 2)
    }

    @Test func oneAppIsTodaysCardWithNoMarks() throws {
        let items = [
            NookTodoItem(id: "r1", title: "Finish problem set 3", dueDate: Calendar.current.startOfDay(for: Date()), isCompleted: false, listName: "Reminders"),
            NookTodoItem(id: "r2", title: "Renew parking permit", dueDate: nil, isCompleted: false, listName: "Reminders"),
            NookTodoItem(id: "r3", title: "Call the dentist", dueDate: Calendar.current.startOfDay(for: Date()), isCompleted: false, listName: "Reminders"),
        ]
        let harness = NookTodoCardHarness(enabled: [.reminders], reminders: items)
        #expect(!harness.hub.hasManyEnabled)
        let image = try NookTodoCardSnapshot.render("card-one-app", NookTodoCardSnapshot.card(harness, size: .medium))
        #expect(image.width > 0)
        // Turning a second app on changes the picture; turning it off brings
        // today's card back exactly (T12).
        let before = NookTodoCardSnapshot.bytes(image)
        harness.hub.setEnabled(.asana, true)
        let grouped = try NookTodoCardSnapshot.render("card-one-app-grouped", NookTodoCardSnapshot.card(harness, size: .medium), writes: false)
        #expect(NookTodoCardSnapshot.bytes(grouped) != before)
        harness.hub.setEnabled(.asana, false)
        let back = try NookTodoCardSnapshot.render("card-one-app-back", NookTodoCardSnapshot.card(harness, size: .medium), writes: false)
        #expect(NookTodoCardSnapshot.bytes(back) == before)
    }

    @Test func addPickerListsTheAppsThatTakeTasks() throws {
        let harness = NookTodoCardHarness(enabled: [.reminders, .tickTick, .asana, .canvas], addKind: .asana)
        #expect(harness.hub.addableKinds == [.reminders, .tickTick, .asana])
        #expect(harness.hub.addKind == .asana)
        let view = VStack(alignment: .trailing, spacing: 6) {
            NookTodoCardSnapshot.card(harness, size: .medium)
            NookTodoAddMenuStill(hub: harness.hub)
        }
        let image = try NookTodoCardSnapshot.render("card-add-picker", view)
        #expect(image.height > Int(NookTodoCard.height(for: .medium) * 2))
    }

    /// Canvas never takes the typed task, even when it is the last one
    /// picked before it was turned on.
    @Test func theChipNeverOffersCanvas() {
        let harness = NookTodoCardHarness(enabled: [.reminders, .canvas])
        #expect(!harness.hub.addableKinds.contains(.canvas))
        harness.hub.setAddKind(.canvas)
        #expect(harness.hub.addKind == .reminders)
    }
}
