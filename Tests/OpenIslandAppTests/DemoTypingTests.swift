import Foundation
import Testing
@testable import OpenIslandApp

// The typing of a demo run and the design kit script (D65). Nothing here
// shows a window, reads the owner's design files or touches the real
// clipboard: the copies go to the demo's stand-in pasteboard.

// MARK: - The pace

struct DemoTypingPaceTests {
    @Test func theSameTextIsTypedAtTheSamePaceOnEveryRun() {
        let text = "Pick up groceries on the way back"
        #expect(DemoTyping.gaps(for: text) == DemoTyping.gaps(for: text))
        #expect(
            DemoTypingRun(field: .note, text: text, pressesReturn: true).gaps
                == DemoTypingRun(field: .note, text: text, pressesReturn: true).gaps
        )
        // The seed is FNV-1a, the same in every process. Swift's own hashing
        // is seeded anew each launch and would change the pace.
        #expect(DemoTyping.fnv1a("") == 0xcbf2_9ce4_8422_2325)
        #expect(DemoTyping.fnv1a("a") == 0xaf63_dc4c_8601_ec8c)
        var one = DemoTyping.SplitMix(seed: 42)
        var two = DemoTyping.SplitMix(seed: 42)
        #expect((0..<5).map { _ in one.next() } == (0..<5).map { _ in two.next() })
    }

    @Test(arguments: ["Call home", "Pick up groceries on the way back", "#7B61FF"])
    func eachCharacterTakesFiftyFiveToOneHundredTwentyMilliseconds(text: String) {
        let gaps = DemoTyping.gaps(for: text)
        #expect(gaps.count == text.count)
        #expect(gaps.allSatisfy { $0 >= 0.055 && $0 <= 0.120 })
        #expect(Set(gaps).count > 1, "a little uneven, like a person")
    }

    @Test func aRunTypesEachPrefixThenPressesReturnAfterABeat() {
        let todo = DemoTypingRun(field: .todo, text: "Call", pressesReturn: true)
        #expect(todo.prefixes == ["C", "Ca", "Cal", "Call"])
        #expect(todo.gaps.count == 5)
        #expect(todo.gaps.last == DemoTyping.beforeReturn)
        #expect(abs(todo.duration - todo.gaps.reduce(0, +)) < 1e-12)

        let color = DemoTypingRun(field: .designColor, text: "#7B61FF", pressesReturn: false)
        #expect(color.gaps.count == 7, "no Return: the Add pill keeps the color")
        #expect(DemoAction.typeColor("#7B61FF").typing == color)
        #expect(DemoAction.typeNote("x").typing?.pressesReturn == true)
        #expect(DemoAction.saveNote("x").typing == nil)
    }

    @Test func aScriptsDurationCountsItsTyping() {
        let script = DemoScript(
            name: "tiny", startsPlaying: false,
            steps: [DemoStep(1, .typeTodo("Call home")), DemoStep(1, .closeIsland)]
        )
        let typing = DemoTypingRun(field: .todo, text: "Call home", pressesReturn: true).duration
        #expect(abs(script.duration - (2 + typing + DemoScript.endPause)) < 1e-12)
    }
}

// MARK: - The runner and the typist

@MainActor
struct DemoTypistTests {
    @Test func theRunnerTypesThroughTheDoorsOneKeyAtATime() async {
        let script = DemoScript(
            name: "tiny", startsPlaying: false,
            steps: [DemoStep(1, .typeTodo("Hi")), DemoStep(1, .typeColor("#FFF")), DemoStep(1, .addTypedColor)]
        )
        let doors = RecordingDoors()
        let clock = InstantClock()

        await clock.runner.run(script, doors: doors, launchedAt: DemoFixture.now)

        #expect(doors.actions == [.typeTodo("Hi"), .typeColor("#FFF"), .addTypedColor])
        #expect(doors.keys.map(\.text) == ["H", "Hi", "#", "#F", "#FF", "#FFF"])
        #expect(doors.keys.map(\.field) == [.todo, .todo, .designColor, .designColor, .designColor, .designColor])
        #expect(doors.returns == [.todo], "the color waits for the Add pill")
        #expect(clock.lines.count == 3, "one line for each step, none for a key")
    }

    @Test func aFieldOnScreenTakesTheReturnAndNoFieldLeavesItToTheService() {
        let typist = DemoTypist()
        let hook = UUID()

        typist.focus(.note)
        typist.type("P", into: .note)
        typist.type("Pi", into: .note)
        #expect(typist.line(.note) == DemoTypist.Line(text: "Pi", keys: 2, focuses: 1, returns: 0))
        #expect(!typist.submit(.note), "no field on screen")

        typist.attach(.note, hook: hook)
        #expect(typist.isOnScreen(.note))
        #expect(typist.submit(.note))
        #expect(typist.line(.note).returns == 1)
        #expect(!typist.isOnScreen(.todo))
        typist.detach(.note, hook: hook)
        #expect(!typist.isOnScreen(.note))
        // A new click into the field starts it empty.
        typist.focus(.note)
        #expect(typist.line(.note).text.isEmpty)
    }

    @Test func withNoFieldOnScreenTheDoorsSaveTheTypedLineThroughTheService() {
        let fixture = DemoFixture(now: Date())
        defer { fixture.remove() }
        fixture.startSampleServices()
        var lines: [String] = []
        let doors = AppDemoDoors(model: fixture.model, typist: DemoTypist(), openTour: {}, currentTour: { nil })
        doors.log = { lines.append($0) }

        doors.perform(.typeNote("Milk"))
        for text in ["M", "Mi", "Mil", "Milk"] { doors.type(text, into: .note) }
        doors.submit(.note)

        #expect(fixture.nook.notes.notes.first?.title == "Milk")
        #expect(lines == ["DEMO no note field on screen, its service took the text"])
    }
}

// MARK: - The kit script

@MainActor
@Suite(.noNewWindows)
struct DemoKitScriptTests {
    @Test func kitPutsTheKitFirstAndLargeWithItsSamplesInTheSessionsFolder() async {
        let fixture = DemoFixture(script: "kit", now: Date())
        defer { fixture.remove() }
        let nook = fixture.nook
        let kit = nook.design

        #expect(fixture.session.runsKitScript)
        #expect(!fixture.session.usesRealDesignServices)
        for profile in IslandAppearanceDisplayProfile.allCases {
            let first = nook.widgetPlacements(for: profile).first
            #expect(first?.kind == .design && first?.size == .large)
        }
        let folder = kit.palettes.folderURL
        #expect(folder.path.hasPrefix(fixture.root.path))
        #expect(!folder.path.contains("Application Support"))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("palettes.json").path))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("links.json").path))

        kit.start(nook: nook)
        await kit.load()

        #expect(kit.palettes.palettes.map(\.name) == [DemoDesign.brandName, DemoDesign.websiteName])
        #expect(kit.palettes.activePalette?.name == DemoDesign.brandName)
        #expect(kit.palettes.activePalette?.swatches.map(\.name) == DemoDesign.brand.map(\.name))
        #expect(kit.palettes.recents.count == DemoDesign.recents.count)
        #expect(kit.links.library.links.count == DemoDesign.links.count)
        #expect(kit.links.library.links.allSatisfy { $0.address != nil }, "every sample is a link the rules let in")
    }

    @Test func kitCopiesToTheDemosOwnPasteboardAndKeepsTheTypedColor() async throws {
        let fixture = DemoFixture(script: "kit", now: Date())
        defer { fixture.remove() }
        fixture.startSampleServices()
        let kit = fixture.nook.design
        kit.start(nook: fixture.nook)
        await kit.load()
        let pasteboard = fixture.session.pasteboard
        #expect(pasteboard.changeCount == 0)

        let doors = AppDemoDoors(model: fixture.model, typist: DemoTypist(), openTour: {}, currentTour: { nil })
        doors.log = { _ in }
        await InstantClock().runner.run(DemoScripts.kit, doors: doors, launchedAt: DemoFixture.now)

        // Four swatches copied, each to the stand-in. The app never reads it
        // back, and nothing was handed the Mac's clipboard.
        #expect(pasteboard.changeCount == 4)
        #expect(pasteboard.read() == nil)
        #expect(pasteboard.lastWrite == .text("#7B61FF"))
        #expect(kit.pictureClipboard == nil)
        #expect(kit.hotkey.status == .none)
        // The typed color was kept on the active palette, last.
        let swatches = try #require(kit.palettes.activePalette?.swatches)
        #expect(swatches.count == DemoDesign.brand.count + 1)
        #expect(swatches.last?.color == NookDesignColorParser.parse("#7B61FF"))
        #expect(kit.tab == .colors)
        #expect(kit.keepsPicking, "the pill was switched on")
        #expect(kit.justCopiedID == swatches.last?.id, "the card ticks the color it copied")
        #expect(fixture.model.notchStatus == .closed)
    }

    @Test func theFirstCopyIsTheFirstSwatchAsHex() async {
        let fixture = DemoFixture(script: "kit", now: Date())
        defer { fixture.remove() }
        fixture.startSampleServices()
        let kit = fixture.nook.design
        kit.start(nook: fixture.nook)
        await kit.load()
        let doors = AppDemoDoors(model: fixture.model, typist: DemoTypist(), openTour: {}, currentTour: { nil })

        doors.perform(.copySwatch(position: 0))

        let hex = NookDesignColorFormat.hex.text(for: DemoDesign.brand[0].color)
        #expect(fixture.session.pasteboard.lastWrite == .text(hex))
        #expect(kit.notice?.text.contains(hex) == true, "the card says it copied")
        // A place past the end of the palette presses nothing.
        doors.perform(.copySwatch(position: 99))
        #expect(fixture.session.pasteboard.changeCount == 1)
    }

    @Test func withTheHandSwitchOnTheKitScriptStillKeepsTheKitOffTheMacsClipboard() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hangover-demo-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func session(_ extra: [String: String]) -> DemoSession {
            var environment = DemoFixture.environment
            environment.merge(extra) { _, new in new }
            return DemoSession(environment: environment, now: DemoFixture.now, temporary: root, putsPanelOnScreen: false)
        }

        let both = session([DemoMode.designKey: "1", DemoMode.scriptKey: "kit"])
        #expect(!both.usesRealDesignServices)
        both.model.nook.timer.reset()
        let byHand = session([DemoMode.designKey: "1"])
        #expect(byHand.usesRealDesignServices, "a recording by hand keeps its real eyedropper and clipboard (D53)")
        byHand.model.nook.timer.reset()
        let otherScript = session([DemoMode.scriptKey: "use"])
        #expect(!otherScript.runsKitScript)
        #expect(!otherScript.model.nook.isWidgetEnabled(.design))
        otherScript.model.nook.timer.reset()
    }
}
