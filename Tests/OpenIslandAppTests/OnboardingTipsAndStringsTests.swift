import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

// The welcome tour's tips and its strings (D43).

// MARK: - The tips

struct OnboardingTipTests {
    private static let everyWidget = Set(NookWidgetKind.allCases)

    @Test func aFullSetupWithAgentsFillsThePage() {
        let tips = OnboardingTip.shown(agentsEnabled: true, widgets: Self.everyWidget)

        #expect(tips == [.keepOpen, .swipeAway, .dropFiles, .rearrange, .switchPages, .jump, .todoNotes, .settings])
        #expect(tips.count == OnboardingTip.pageLimit)
    }

    @Test func withTheAgentsOffNoTipIsAboutAgents() {
        let tips = OnboardingTip.shown(agentsEnabled: false, widgets: Self.everyWidget)

        #expect(tips == [.keepOpen, .swipeAway, .dropFiles, .rearrange, .todoNotes, .quickNotes, .speaker, .settings])
        #expect(tips.allSatisfy { !$0.needsAgents })
    }

    @Test func aTipAboutAWidgetShowsOnlyWhileThatWidgetIsOnThePage() {
        let none = OnboardingTip.shown(agentsEnabled: false, widgets: [])
        #expect(none == [.keepOpen, .swipeAway, .rearrange, .volume, .settings])

        let music = OnboardingTip.shown(agentsEnabled: false, widgets: [.media])
        #expect(music == [.keepOpen, .swipeAway, .rearrange, .speaker, .volume, .settings])

        for tip in OnboardingTip.allCases {
            guard let widget = tip.widget else { continue }
            #expect(!OnboardingTip.shown(agentsEnabled: true, widgets: Self.everyWidget.subtracting([widget])).contains(tip))
        }
    }

    @Test func whereSettingsAreIsAlwaysTheLastTip() {
        for agentsEnabled in [true, false] {
            for widgets in [Set<NookWidgetKind>(), [.todo], Self.everyWidget] {
                let tips = OnboardingTip.shown(agentsEnabled: agentsEnabled, widgets: widgets)
                #expect(tips.last == .settings)
                #expect(tips.filter { $0 == .settings }.count == 1)
                #expect(tips.count <= OnboardingTip.pageLimit)
                #expect(Set(tips).count == tips.count)
            }
        }
    }

    /// Keeping the island open is a click inside it with hover, and a
    /// second click on the notch closes it with click.
    @Test func keepingItOpenIsToldInTheWordsOfTheWayItOpens() {
        #expect(OnboardingTip.keepOpen.keyName(openTrigger: .hover) == "keepOpen.hover")
        #expect(OnboardingTip.keepOpen.keyName(openTrigger: .click) == "keepOpen.click")
        #expect(OnboardingTip.dropFiles.keyName(openTrigger: .click) == "dropFiles")
    }

    @MainActor
    @Test func theTipsSitInRowsOfFour() {
        let eight = OnboardingTip.shown(agentsEnabled: true, widgets: Self.everyWidget)
        #expect(OnboardingTipsPage.rows(eight).map(\.count) == [4, 4])
        #expect(OnboardingTipsPage.rows(Array(eight.prefix(5))).map(\.count) == [4, 1])
        #expect(OnboardingTipsPage.rows([]).isEmpty)
    }

    /// Each tip names a gesture the code has. These are the lines that
    /// carry them, and a tip whose gesture is renamed fails here first.
    @Test(arguments: [
        ("Sources/OpenIslandApp/Island/IslandOpenTrigger.swift", "return .pin"),
        ("Sources/OpenIslandApp/Island/IslandOpenTrigger.swift", ".closeFromNotch"),
        ("Sources/OpenIslandApp/Island/IslandOpenTrigger.swift", "static func swipeAction("),
        ("Sources/OpenIslandApp/Island/IslandOpenTrigger.swift", "? .toggleClosedContent : .none"),
        ("Sources/OpenIslandApp/Views/IslandPanelView.swift", "model.nook.tray.handleDrop(providers)"),
        ("Sources/OpenIslandApp/Nook/Views/NookWidgetGrid.swift", "LongPressGesture(minimumDuration: Self.longPressDuration).onEnded { _ in onBeginEditing() }"),
        ("Sources/OpenIslandApp/Nook/Views/NookWidgetGrid.swift", "Button(\"Edit Widgets\") { onBeginEditing() }"),
        ("Sources/OpenIslandApp/Views/IslandPanelView.swift", "model.toggleNookPage()"),
        ("Sources/OpenIslandApp/Views/IslandPanelView.swift", "onJump: { model.jumpToSession(session) }"),
        ("Sources/OpenIslandApp/Nook/Widgets/Todo/NookTodoCard.swift", "open(item)"),
        ("Sources/OpenIslandApp/Nook/Widgets/Todo/NookTodoCard.swift", "source.complete(item.id)"),
        ("Sources/OpenIslandApp/Nook/Widgets/Notes/NookNotesCard.swift", "service.append(draft)"),
        ("Sources/OpenIslandApp/Nook/Views/NookMediaViews.swift", "nook.audioOutputs.beginPicking()"),
        ("Sources/OpenIslandApp/Views/IslandPanelView.swift", "headerIconButton(systemName: \"gearshape.fill\""),
        ("Sources/OpenIslandApp/Views/SettingsView.swift", "model.showWelcomeTour()"),
    ])
    func theGestureATipNamesIsInTheCode(file: String, line: String) throws {
        let source = try HangoverBrandTests.text(of: file)
        #expect(source.contains(line), "\(file) no longer has: \(line)")
    }
}

// MARK: - The tour's strings

struct OnboardingStringsTests {
    /// Every key a page builds from a value, which a search of the sources
    /// for string literals would not find.
    private static var builtKeys: [String] {
        var keys = ["onboarding.step"]
        keys += OnboardingChapter.allCases.map(\.titleKey)
        keys += OnboardingClosedSide.allCases.flatMap { [$0.titleKey, $0.noteKey] }
        keys += OnboardingClosedLeft.allCases.flatMap { [$0.titleKey, $0.noteKey] }
        keys += ["onboarding.closed.left.title", "onboarding.closed.right.title", "onboarding.closed.calendar"]
        keys += ["onboarding.done.recap.closed.value"]
        keys += NookWidgetKind.allCases.flatMap { ["onboarding.nook.widget.\($0.rawValue)", "onboarding.widgets.\($0.rawValue)"] }
        keys += ["lives", "point", "opens"].flatMap {
            ["onboarding.welcome.step.\($0).title", "onboarding.welcome.step.\($0).text"]
        }
        keys += ["onboarding.welcome.step.lives.title.topBar"]
        keys += ["day", "agents"].flatMap { ["onboarding.purpose.\($0).title", "onboarding.purpose.\($0).text"] }
        for grant in OnboardingGrant.allCases {
            keys += [
                "onboarding.permissions.\(grant.rawValue).title",
                "onboarding.permissions.\(grant.rawValue).when",
                grant.noteKey(agentsEnabled: true),
                grant.noteKey(agentsEnabled: false),
            ]
        }
        for tip in OnboardingTip.allCases {
            for trigger in IslandOpenTrigger.allCases {
                let name = tip.keyName(openTrigger: trigger)
                keys += ["onboarding.tips.\(name).title", "onboarding.tips.\(name).text"]
            }
        }
        keys += ["approval", "question", "completed", "running", "album", "music", "notice", "timer", "charger"]
            .map { OnboardingGlowLegendEntry(id: $0, color: .white).labelKey }
        keys += OnboardingRecapRow.allCases.map { "onboarding.done.recap.\($0.rawValue)" }
        for source in NookTodoSourceKind.allCases {
            keys += OnboardingTodoChecklist.kinds(for: source).map { OnboardingTodoGuide.stepKey($0, source: source) }
            keys += [OnboardingTodoGuide.noteKey(for: source), OnboardingTodoGuide.nameKey(for: source)]
            if let link = OnboardingTodoGuide.linkKey(for: source) { keys.append(link) }
        }
        keys += [
            "onboarding.todos.notion.noneShared", "onboarding.todos.reminders.allowButton",
            "onboarding.todos.reminders.refused", "onboarding.todos.reminders.openSystem",
            "onboarding.todos.keychain", "onboarding.todos.checkAgain", "onboarding.todos.account",
            "onboarding.todos.settings", "nook.todo.notion.token.placeholder", "nook.todo.ticktick.token.placeholder",
            "nook.todo.notion.connect", "nook.todo.ticktick.connect", "nook.todo.ticktick.token.saved",
            "onboarding.notes.title", "onboarding.notes.body", "onboarding.notes.note", "onboarding.notes.file.where",
            "onboarding.notes.file.choose", "onboarding.notes.file.panelPrompt", "onboarding.notes.file.any",
            "onboarding.notes.appleNotes.where", "onboarding.notes.appleNotes.ask",
            "onboarding.notes.try", "onboarding.notes.try.done",
            "onboarding.weather.title", "onboarding.weather.body", "onboarding.weather.note",
            "onboarding.weather.unset", "onboarding.weather.set", "onboarding.weather.change",
            "onboarding.weather.keep", "onboarding.weather.filling", "onboarding.weather.filled",
            "onboarding.weather.unit", "onboarding.weather.search.offline", "onboarding.weather.search.server",
            "onboarding.done.recap.weather.none", "nook.weather.settings.search.placeholder",
            "nook.weather.settings.search", "nook.weather.settings.searching",
            "nook.weather.settings.noMatch", "nook.weather.settings.unit.fahrenheit",
            "nook.weather.settings.unit.celsius", "nook.weather.failed.offline", "nook.weather.failed.server",
        ]
        keys += [0, 1, 2].map { OnboardingTodoChecklist.loadedKey(count: $0) }
        for destination in NookNotesDestination.allCases {
            keys += [
                OnboardingNotesGuide.titleKey(for: destination),
                OnboardingNotesGuide.textKey(for: destination),
                OnboardingNotesGuide.showKey(for: destination),
            ]
        }
        keys += (1...4).map { "onboarding.todos.sample\($0)" }
        keys += OnboardingAbility.allCases.map(\.textKey)
        keys += OnboardingFeatureNumbersTests.pageKeys
        keys += OnboardingIntegration.allCases.flatMap { [$0.nameKey, $0.textKey, $0.whereKey] }
        return keys
    }

    @Test(arguments: HangoverBrandTests.languages)
    func everyKeyAPageBuildsIsInEveryLanguage(language: String) throws {
        let table = try HangoverBrandTests.table(language)
        for key in Self.builtKeys {
            #expect(!(table[key] ?? "").isEmpty, "\(language) is missing \(key)")
        }
    }

    /// The three languages hold the same tour keys, and the sources ask
    /// for none that is missing.
    @Test func theLanguagesHoldTheSameTourKeysAndThePagesUseNoOther() throws {
        let english = Set(try HangoverBrandTests.table("en").keys.filter { $0.hasPrefix("onboarding.") })
        for language in HangoverBrandTests.languages {
            let keys = Set(try HangoverBrandTests.table(language).keys.filter { $0.hasPrefix("onboarding.") })
            #expect(keys == english, "\(language) differs by \(keys.symmetricDifference(english).sorted())")
        }

        let folder = HangoverBrandTests.repoRoot.appendingPathComponent("Sources/OpenIslandApp/Onboarding")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        let literal = try NSRegularExpression(pattern: "\"(onboarding\\.[A-Za-z0-9.]+)\"")
        var used: Set<String> = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for match in literal.matches(in: text, range: range) {
                if let found = Range(match.range(at: 1), in: text) { used.insert(String(text[found])) }
            }
        }
        // A literal that ends in a dot is the front of a key built from a
        // value, and is covered by the test above.
        let missing = used.filter { !$0.hasSuffix(".") && !english.contains($0) }.sorted()
        #expect(missing.isEmpty, "the pages ask for \(missing)")
        #expect(used.count > 60)
    }

    /// The tour is written in plain words: no dash of either length, and
    /// no jargon left unexplained.
    @Test func theToursWordsStayPlain() throws {
        for language in HangoverBrandTests.languages {
            let table = try HangoverBrandTests.table(language)
            for (key, value) in table where key.hasPrefix("onboarding.") {
                #expect(!value.contains("\u{2014}") && !value.contains("\u{2013}"), "\(language) \(key) has a dash")
            }
        }
        let english = try HangoverBrandTests.table("en")
        // The Nook is named where the widgets are first asked about, with
        // what it is.
        let widgets = try #require(english["onboarding.widgets.body"])
        #expect(widgets.contains("called the Nook"))
        // A hook is said to be a helper before it is named.
        let hook = try #require(english["onboarding.agents.connect.note"])
        let helper = try #require(hook.range(of: "helper"))
        let named = try #require(hook.range(of: "hook"))
        #expect(helper.lowerBound < named.lowerBound)
        let mentions = english.filter { $0.key.hasPrefix("onboarding.") && $0.value.lowercased().contains("hook") }
        #expect(mentions.keys.sorted() == ["onboarding.agents.connect.note"])
        // A coding agent is said to be what it is where the tour asks about it.
        #expect(try #require(english["onboarding.purpose.body"]).contains("A coding agent is"))
    }
}
