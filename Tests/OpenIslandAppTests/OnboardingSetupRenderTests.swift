import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Draws the hands-on pages of the tour (the to-dos, the notes and the weather
/// page, D44) offscreen at the narrow window's width, in several states.
/// Set `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to also write the PNGs to
/// `output/render/onboarding/`. The secret field may come out blank here:
/// a SwiftUI `SecureField` is an AppKit view.
@MainActor
struct OnboardingSetupRenderTests {
    private static let scale: CGFloat = 2
    /// Taller than the narrow window, which scrolls: a snapshot draws the
    /// page in place and cuts it at the bottom, and this shows all of it.
    private static let tallHeight: CGFloat = 1500
    private static let snapshotEnvKey = "OPEN_ISLAND_RENDER_SNAPSHOTS"

    private static var base: OnboardingState {
        var state = OnboardingState()
        state.nookPlacements = [.media, .todo, .notes].map { NookWidgetPlacement(kind: $0, size: .medium) }
        state.notesFilePath = "~/Library/Application Support/OpenIsland/Notes/Quick Notes.md"
        return state
    }

    private static func todos(_ source: NookTodoSourceKind, _ setup: OnboardingTodoSetup) -> OnboardingState {
        var state = base
        state.todoSource = source
        state.todoSetup = setup
        return state
    }

    private static let databases = ["Tasks", "Reading list", "Projects"].enumerated().map {
        OnboardingTodoChoice(id: "db\($0.offset)", title: $0.element)
    }

    private func pictures(_ page: OnboardingPage, _ states: [(String, OnboardingState)]) throws -> [Data] {
        try states.flatMap { name, state in
            try [320.0, 420.0].map { width in
                try render("\(page.snapshotName)-\(name)-\(Int(width))") { view(page, state, width: width) }
            }
        }
    }

    // MARK: The to-dos page

    @Test func theToDosPageDrawsEachStageOfNotionAtTheNarrowWidths() throws {
        let failure = OnboardingTodoMessage(text: "Notion rejected the token. Paste a new one in Settings.", isProblem: true)
        let states: [(String, OnboardingState)] = [
            ("notion-fresh", Self.todos(.notion, OnboardingTodoSetup())),
            ("notion-failed", Self.todos(.notion, OnboardingTodoSetup(message: failure))),
            ("notion-connected", Self.todos(.notion, OnboardingTodoSetup(
                isConnected: true, accountName: "Nook", hasLoadedChoices: true,
                message: OnboardingTodoMessage(text: "No database is shared with the integration yet.", isProblem: false)
            ))),
            ("notion-pick", Self.todos(.notion, OnboardingTodoSetup(
                isConnected: true, accountName: "Nook", choices: Self.databases, hasLoadedChoices: true
            ))),
            ("notion-done", Self.todos(.notion, OnboardingTodoSetup(
                isConnected: true, accountName: "Nook", choices: Self.databases, hasLoadedChoices: true,
                chosenID: "db0", taskCount: 5
            ))),
            ("notion-columns", Self.todos(.notion, OnboardingTodoSetup(
                isConnected: true, accountName: "Nook", choices: Self.databases, hasLoadedChoices: true,
                chosenID: "db0",
                message: OnboardingTodoMessage(text: "Choose the column that marks a task done.", isProblem: true),
                needsColumns: true
            ))),
        ]
        let drawn = try pictures(.todos, states)
        #expect(Set(drawn).count == drawn.count, "every stage and width should draw its own picture")
    }

    @Test func theToDosPageDrawsTickTickAndRemindersToo() throws {
        let states: [(String, OnboardingState)] = [
            ("ticktick-fresh", Self.todos(.tickTick, OnboardingTodoSetup())),
            ("ticktick-done", Self.todos(.tickTick, OnboardingTodoSetup(
                isConnected: true, choices: Self.databases, hasLoadedChoices: true, chosenID: "db0", taskCount: 1
            ))),
            ("reminders-ask", Self.todos(.reminders, OnboardingTodoSetup())),
            ("reminders-refused", Self.todos(.reminders, OnboardingTodoSetup(
                message: OnboardingTodoMessage(text: "Reminders access was refused. In System Settings, open Privacy & Security, then Reminders, and switch Hangover on.", isProblem: true),
                remindersAccess: .refused
            ))),
            ("reminders-granted", Self.todos(.reminders, OnboardingTodoSetup(
                isConnected: true, taskCount: 4, remindersAccess: .granted
            ))),
        ]
        let drawn = try pictures(.todos, states)
        #expect(Set(drawn).count == drawn.count)
    }

    // MARK: The notes page

    @Test func theNotesPageDrawsEachPlaceAndTheTickedStep() throws {
        var file = Self.base
        var saved = file
        saved.hasSavedNote = true
        var apple = Self.base
        apple.notesDestination = .appleNotes
        var appleSaved = apple
        appleSaved.hasSavedNote = true
        file.notesDestination = .file

        let drawn = try pictures(.notes, [
            ("file", file), ("file-saved", saved), ("apple", apple), ("apple-saved", appleSaved),
        ])
        #expect(Set(drawn).count == drawn.count, "every state and width should draw its own picture")
    }

    @Test func theNotesPageIsNotDrawnWhileTheNotesWidgetIsOff() throws {
        var off = Self.base
        off.nookPlacements = [.media, .todo].map { NookWidgetPlacement(kind: $0, size: .medium) }
        #expect(try render(nil) { view(.notes, off, width: 320) } == render(nil) { view(.todos, off, width: 320) })
    }

    @Test func theRecapDrawsTheNotesChoice() throws {
        var file = Self.base
        file.notesDestination = .file
        var apple = file
        apple.notesDestination = .appleNotes
        let a = try render("16-done-notes-file") { view(.done, file, size: OnboardingStyle.windowSize) }
        let b = try render("16-done-notes-apple") { view(.done, apple, size: OnboardingStyle.windowSize) }
        #expect(a != b)
    }

    // MARK: The weather page

    private static func weather(_ setup: OnboardingWeatherSetup) -> OnboardingState {
        var state = base
        state.nookPlacements = [.media, .weather, .notes].map { NookWidgetPlacement(kind: $0, size: .medium) }
        state.weather = setup
        return state
    }

    private static let losAngeles = NookWeatherPlace(
        name: "Los Angeles", region: "California", country: "United States", latitude: 34.05, longitude: -118.24
    )
    private static let found = [
        losAngeles,
        NookWeatherPlace(name: "Los \u{00C1}ngeles", region: "Biobio", country: "Chile", latitude: -37.47, longitude: -72.35),
        NookWeatherPlace(name: "Los \u{00C1}ngeles", region: nil, country: "Panama", latitude: 7.88, longitude: -80.35),
    ]

    @Test func theWeatherPageDrawsEachStateAtTheNarrowWidths() throws {
        let states: [(String, OnboardingState)] = [
            ("fresh", Self.weather(OnboardingWeatherSetup())),
            ("searching", Self.weather(OnboardingWeatherSetup(place: nil, search: .searching))),
            ("results", Self.weather(OnboardingWeatherSetup(place: nil, results: Self.found))),
            ("nomatch", Self.weather(OnboardingWeatherSetup(place: nil, search: .noMatch))),
            ("offline", Self.weather(OnboardingWeatherSetup(place: nil, search: .failed(.offline)))),
            ("set-filling", Self.weather(OnboardingWeatherSetup(
                place: Self.losAngeles, unit: .celsius, forecast: .loading
            ))),
            ("set-filled", Self.weather(OnboardingWeatherSetup(place: Self.losAngeles, hasReport: true))),
            ("set-failed", Self.weather(OnboardingWeatherSetup(
                place: Self.losAngeles, forecast: .failed(.offline)
            ))),
        ]
        let drawn = try pictures(.weather, states)
        #expect(Set(drawn).count == drawn.count, "every state and width should draw its own picture")
    }

    @Test func theRecapDrawsThePlace() throws {
        let none = Self.weather(OnboardingWeatherSetup())
        let set = Self.weather(OnboardingWeatherSetup(place: Self.losAngeles))
        let a = try render("17-done-weather-none") { view(.done, none, size: OnboardingStyle.windowSize) }
        let b = try render("17-done-weather-set") { view(.done, set, size: OnboardingStyle.windowSize) }
        #expect(a != b)
    }

    // MARK: Rendering

    private func view(_ page: OnboardingPage, _ state: OnboardingState, width: CGFloat) -> some View {
        view(page, state, size: CGSize(width: width, height: Self.tallHeight))
    }

    private func view(_ page: OnboardingPage, _ state: OnboardingState, size: CGSize) -> some View {
        OnboardingView(
            tour: OnboardingTour(startingAt: page, state: { state }),
            lang: LanguageManager.shared
        )
        .frame(width: size.width, height: size.height)
    }

    private func render<Content: View>(_ name: String?, @ViewBuilder _ content: () -> Content) throws -> Data {
        let renderer = ImageRenderer(content: content().environment(\.nookDrawsStill, true))
        renderer.scale = Self.scale
        let image = try #require(renderer.cgImage, "ImageRenderer returned no image")
        let png = try #require(
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
            "PNG encoding failed"
        )
        if let name, ProcessInfo.processInfo.environment[Self.snapshotEnvKey] == "1" {
            let directory = Self.repoRoot.appendingPathComponent("output/render/onboarding", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return png
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
