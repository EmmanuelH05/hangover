import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

// The welcome tour's page for where the to-dos come from (D43).

// MARK: - The to-dos page

/// Where the to-do widget gets its tasks (D43). Nothing here reaches the
/// Keychain, the network or macOS: a hub that was never started does none
/// of that, and its choice is kept in a `MemoryDefaults`.
@MainActor
struct OnboardingTodosTests {
    @Test(arguments: NookTodoSourceKind.allCases)
    func pickingASourceWritesThePreferenceSettingsWrites(source: NookTodoSourceKind) {
        let defaults = MemoryDefaults()
        let hub = NookTodoHub(defaults: defaults)
        #expect(hub.selectedKind == .reminders)
        #expect(defaults.string(forKey: NookTodoHub.sourceKey) == nil)

        // What the tour's door does with the pick.
        hub.selectedKind = source

        let saved = defaults.string(forKey: NookTodoHub.sourceKey)
        #expect(saved == (source == .reminders ? nil : source.rawValue), "a pick that changes nothing writes nothing")
        // A hub made from the same store comes up on the pick.
        #expect(NookTodoHub(defaults: defaults).selectedKind == source)
    }

    @Test func aPickBackToRemindersIsSavedToo() {
        let defaults = MemoryDefaults()
        let hub = NookTodoHub(defaults: defaults)

        hub.selectedKind = .tickTick
        hub.selectedKind = .reminders

        #expect(defaults.string(forKey: NookTodoHub.sourceKey) == NookTodoSourceKind.reminders.rawValue)
    }

    @Test func theToursPickReachesTheAppOnceAndAsksForNothingElse() {
        let counter = OnboardingCallCounter()
        let tour = OnboardingTour(state: { OnboardingState() }, actions: counter.actions)

        tour.actions.setTodoSource(.tickTick)

        #expect(counter.todoSources == [.tickTick])
        #expect(counter.order == ["todoSource"])
    }

    /// The page follows the to-do widget: with it off the page after
    /// arranging is the notes page, and with it on it is the to-dos.
    @Test func theTourShowsTheToDosPageOnlyWhileTheWidgetIsOnThePage() {
        var widgets = Set(NookWidgetKind.defaultEnabled)
        let tour = OnboardingTour(startingAt: .arrange, state: { OnboardingState(enabledWidgets: widgets) })
        #expect(tour.pages.contains(.todos))

        tour.next()
        #expect(tour.page == .todos)
        tour.back()

        widgets.remove(.todo)
        #expect(!tour.pages.contains(.todos))
        #expect(tour.pages.count == OnboardingPage.allCases.count - 2, "the weather page is off too")
        tour.next()
        #expect(tour.page == .notes)
        tour.back()
        #expect(tour.page == .arrange)

        // A layout that leaves the widget off the display takes the page
        // out as well.
        widgets.insert(.todo)
        let hidden = OnboardingTour(startingAt: .todos, state: {
            var state = OnboardingState()
            state.nookPlacements = [NookWidgetPlacement(kind: .media, size: .medium)]
            return state
        })
        #expect(hidden.page == .arrange)
    }

    // MARK: The steps

    @Test func eachSourceHasItsOwnSteps() {
        #expect(OnboardingTodoChecklist.kinds(for: .reminders) == [.allow])
        #expect(OnboardingTodoChecklist.kinds(for: .notion) == [.open, .connect, .share, .pick])
        #expect(OnboardingTodoChecklist.kinds(for: .tickTick) == [.open, .connect, .pick])

        let all = NookTodoSourceKind.allCases.flatMap { source in
            OnboardingTodoChecklist.kinds(for: source).map { OnboardingTodoGuide.stepKey($0, source: source) }
        }
        #expect(Set(all).count == all.count)
    }

    /// The buttons open the pages Settings links to, under the words
    /// Settings uses, and Reminders has no page to open.
    @Test func theLinksAreTheOnesSettingsUses() throws {
        #expect(NookTodoSetupLink.url(for: .reminders) == nil)
        #expect(NookTodoSetupLink.url(for: .notion)?.absoluteString == "https://www.notion.so/my-integrations")
        #expect(NookTodoSetupLink.url(for: .tickTick)?.absoluteString == "https://ticktick.com/webapp/")
        #expect(OnboardingTodoGuide.linkKey(for: .reminders) == nil)
        #expect(OnboardingTodoGuide.linkKey(for: .notion) == "nook.todo.notion.openIntegrations")
        #expect(OnboardingTodoGuide.linkKey(for: .tickTick) == "nook.todo.ticktick.openWeb")

        let notion = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Nook/Widgets/Todo/Notion/NookNotionTodoSettings.swift")
        let tickTick = try HangoverBrandTests.text(
            of: "Sources/OpenIslandApp/Nook/Widgets/Todo/TickTick/NookTickTickTodoSettings.swift"
        )
        #expect(notion.contains("NookTodoSetupLink.notionIntegrations"))
        #expect(tickTick.contains("NookTodoSetupLink.tickTickWebApp"))
    }

    /// The Notion steps say what the app's own Settings rows ask for, in
    /// the order a first-timer meets them. Each phrase here is one the
    /// app's own strings use, which is what keeps the steps honest.
    @Test func theNotionStepsAreTheOnesTheSettingsRowsAskFor() throws {
        let english = try HangoverBrandTests.table("en")
        func line(_ kind: OnboardingTodoStepKind) throws -> String {
            try #require(english[OnboardingTodoGuide.stepKey(kind, source: .notion)])
        }

        // The integration, with the capabilities the app's errors name.
        #expect(try line(.open).contains("internal integration"))
        #expect(try #require(english["nook.todo.notion.token.help"]).contains("internal integration"))
        for (capability, key) in [
            ("Read content", "nook.todo.notion.state.missingRead"),
            ("Update content", "nook.todo.notion.error.cannotUpdate"),
            ("Insert content", "nook.todo.notion.error.cannotInsert"),
        ] {
            #expect(try line(.open).contains(capability))
            #expect(try #require(english[key]).contains(capability))
        }
        // The token is pasted into the field and Connect is pressed.
        #expect(try line(.connect).contains(try #require(english["nook.todo.notion.connect"])))
        // Sharing the database, the step people miss.
        let empty = try #require(english["nook.todo.notion.database.empty"])
        for phrase in ["•••", "Connections", "add your integration"] {
            #expect(try line(.share).contains(phrase))
            #expect(empty.contains(phrase))
        }
        #expect(try line(.pick).contains("database"))
    }

    @Test func theTickTickStepsAreTheOnesTheSettingsRowsAskFor() throws {
        let english = try HangoverBrandTests.table("en")
        func line(_ kind: OnboardingTodoStepKind) throws -> String {
            try #require(english[OnboardingTodoGuide.stepKey(kind, source: .tickTick)])
        }
        let help = try #require(english["nook.todo.ticktick.token.help"])

        for phrase in ["TickTick on the web", "Settings, then Account, then API Token"] {
            #expect(try line(.open).contains(phrase))
            #expect(help.contains(phrase))
        }
        #expect(try line(.connect).contains(try #require(english["nook.todo.ticktick.connect"])))
        #expect(try line(.pick).contains(try #require(english["nook.todo.ticktick.inbox"])))
    }

    /// The tour has two fields: the secret field of the to-dos page, which
    /// is a secure one, and the place field of the weather page. No other
    /// page takes typed text.
    @Test func theTourHasOneFieldAndItIsSecure() throws {
        let folder = HangoverBrandTests.repoRoot.appendingPathComponent("Sources/OpenIslandApp/Onboarding")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(files.count > 8)
        var secure: [String] = []
        var plain: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("TextEditor("), "\(file.lastPathComponent) has a TextEditor")
            if text.contains("TextField(") { plain.append(file.lastPathComponent) }
            if text.contains("SecureField(") { secure.append(file.lastPathComponent) }
        }
        #expect(secure == ["OnboardingTodoSteps.swift"])
        #expect(plain == ["OnboardingWeatherPage.swift"])
    }

    // MARK: The recap

    @Test func theRecapNamesTheSourceOnlyWhileTheToDoWidgetIsOn() {
        #expect(OnboardingRecapRow.shown(agentsEnabled: true, hasTodoWidget: true) == OnboardingRecapRow.allCases)
        #expect(OnboardingRecapRow.shown(agentsEnabled: true, hasTodoWidget: false)
            == OnboardingRecapRow.allCases.filter { $0 != .todos })
        #expect(OnboardingRecapRow.shown(agentsEnabled: false, hasTodoWidget: false, hasNotesWidget: false, hasWeatherWidget: false)
            == [.opens, .closed, .widgets, .calendar, .layout, .opened, .glow])
    }

    @Test func theRecapNamesTheNotesPlaceOnlyWhileTheNotesWidgetIsOn() {
        #expect(OnboardingRecapRow.shown(agentsEnabled: true).contains(.notes))
        #expect(OnboardingRecapRow.shown(agentsEnabled: true, hasNotesWidget: false)
            == OnboardingRecapRow.allCases.filter { $0 != .notes })
    }
}
