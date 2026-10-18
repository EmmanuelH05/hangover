import Foundation
import Testing
@testable import OpenIslandApp

/// The hub that owns which task apps are on (D83): the saved choice, the
/// add target, the sections and the merged list. Every service is a stub on
/// a transport that never reaches the network, and every token store is in
/// memory.
@MainActor
@Suite struct NookTodoHubTests {
    private struct Rig {
        let defaults: UserDefaults
        let hub: NookTodoHub
        let nook: NookModel
        let tickTick: NookTickTickTodoService
    }

    private func rig(
        defaults: UserDefaults = MemoryDefaults(),
        reminders: [NookTodoItem] = []
    ) -> Rig {
        let center = NotificationCenter()
        let directory = TickTickFixtures.makeTempDirectory()
        let notion = NookNotionTodoService(
            defaults: defaults, transport: StubTodoTransport(), tokenStore: InMemoryTodoTokenStore(token: nil),
            cache: NotionTodoCache(directory: directory)
        )
        let tickTick = NookTickTickTodoService(
            defaults: defaults, transport: StubTodoTransport(), tokenStore: InMemoryTodoTokenStore(token: nil),
            cache: TickTickTodoCache(directory: directory)
        )
        let hub = NookTodoHub(
            defaults: defaults,
            notion: notion,
            tickTick: tickTick,
            asana: NookAsanaTodoService(
                defaults: defaults, transport: StubTodoTransport(), tokenStore: InMemoryTodoTokenStore(token: nil)
            ),
            monday: NookMondayTodoService(
                defaults: defaults, transport: StubTodoTransport(), tokenStore: InMemoryTodoTokenStore(token: nil)
            ),
            canvas: NookCanvasTodoService(
                defaults: defaults, transport: StubTodoTransport(), tokenStore: InMemoryTodoTokenStore(token: nil)
            ),
            dueReminder: NookTodoDueReminder(defaults: defaults, notifications: center),
            notifications: center
        )
        let nook = NookModel(
            reminders: NookRemindersService(defaults: MemoryDefaults(), sample: reminders),
            todo: hub, defaults: MemoryDefaults(), looksForImportedGIF: false, asksMacOSForAccess: false
        )
        hub.start(nook: nook)
        return Rig(defaults: defaults, hub: hub, nook: nook, tickTick: tickTick)
    }

    private func savedSources(_ defaults: UserDefaults) -> [String]? {
        defaults.stringArray(forKey: NookTodoHub.sourcesKey)
    }

    private func item(_ id: String) -> NookTodoItem {
        NookTodoItem(id: id, title: id, dueDate: nil, isCompleted: false, listName: "List")
    }

    private func tickTickRow(_ id: String) -> TickTickRow {
        TickTickRow(item: item(id), projectID: "p1", notesField: .content)
    }

    // MARK: What is on at the start

    @Test func aFreshCopyHasRemindersAloneOnAndAsTheAddTarget() {
        let rig = rig()

        #expect(rig.hub.enabledKinds == [.reminders])
        #expect(rig.hub.addKind == .reminders)
        #expect(rig.hub.hasManyEnabled == false)
        #expect(rig.hub.asana.isActive == false)
        #expect(rig.hub.tickTick.isActive == false)
    }

    @Test func aCopyFromBeforeD83ComesUpWithItsOneAppAlone() async {
        let defaults = MemoryDefaults()
        defaults.set("ticktick", forKey: NookTodoHub.sourceKey)
        #expect(savedSources(defaults) == nil)

        let rig = rig(defaults: defaults)

        #expect(rig.hub.enabledKinds == [.tickTick])
        #expect(rig.hub.addKind == .tickTick)
        #expect(rig.tickTick.isActive)
        await rig.tickTick.setupTask?.value
    }

    // MARK: Turning apps on and off

    @Test func settingEnabledTurnsServicesOnAndOffAndSavesTheChoice() async {
        let rig = rig()

        rig.hub.setEnabled(.asana, true)
        rig.hub.setEnabled(.monday, true)
        #expect(rig.hub.asana.isActive)
        #expect(rig.hub.monday.isActive)
        #expect(rig.hub.canvas.isActive == false)
        #expect(rig.hub.enabledKinds == [.reminders, .asana, .monday])
        #expect(savedSources(rig.defaults) == ["reminders", "asana", "monday"])
        #expect(rig.hub.hasManyEnabled)

        rig.hub.setEnabled(.asana, false)
        #expect(rig.hub.asana.isActive == false)
        #expect(rig.hub.monday.isActive)
        #expect(savedSources(rig.defaults) == ["reminders", "monday"])

        await rig.hub.monday.setupTask?.value
    }

    @Test func turningTheAddTargetOffMovesItToTheFirstAppLeftThatTakesTasks() {
        let rig = rig()
        rig.hub.setEnabled(.canvas, true)
        rig.hub.setEnabled(.asana, true)
        rig.hub.setEnabled(.monday, true)
        rig.hub.setAddKind(.monday)
        #expect(rig.hub.addKind == .monday)

        rig.hub.setEnabled(.monday, false)
        #expect(rig.hub.addKind == .reminders, "falls to the first app left that takes tasks")

        rig.hub.setEnabled(.reminders, false)
        #expect(rig.hub.addKind == .asana, "Canvas is on but never takes a typed task")
        #expect(rig.defaults.string(forKey: NookTodoHub.sourceKey) == "asana")
    }

    @Test func canvasIsNeverTheAddTargetNorOneOfTheAddableKinds() {
        let rig = rig()
        rig.hub.setEnabled(.canvas, true)

        #expect(rig.hub.addableKinds == [.reminders])
        rig.hub.setAddKind(.canvas)
        #expect(rig.hub.addKind == .reminders)
        #expect(NookTodoHub.addTarget(preferred: .canvas, among: [.canvas, .asana]) == .asana)
    }

    @Test func anAppThatIsOffCannotBeTheAddTarget() {
        let rig = rig()

        rig.hub.setAddKind(.notion)

        #expect(rig.hub.addKind == .reminders)
    }

    @Test func selectedKindTurnsThatAppOnAlone() async {
        let rig = rig()
        rig.hub.setEnabled(.asana, true)

        rig.hub.selectedKind = .notion

        #expect(rig.hub.enabledKinds == [.notion])
        #expect(rig.hub.addKind == .notion)
        #expect(rig.hub.selectedKind == .notion)
        #expect(rig.hub.notion.isActive)
        #expect(rig.hub.asana.isActive == false)
        #expect(savedSources(rig.defaults) == ["notion"])
        await rig.hub.notion.setupTask?.value
    }

    // MARK: What the card reads

    @Test func sectionsComeInTheOrderOfAllCases() {
        let defaults = MemoryDefaults()
        defaults.set(["canvas", "monday", "ticktick", "reminders", "notion", "asana"], forKey: NookTodoHub.sourcesKey)
        let rig = rig(defaults: defaults)

        let sections = rig.hub.sections(reminders: rig.nook.reminders)

        #expect(sections.map(\.kind) == NookTodoSourceKind.allCases)
        #expect(rig.hub.enabledKinds == NookTodoSourceKind.allCases)
    }

    @Test func itemsMergeOnlyTheSectionsThatAreReady() async {
        let defaults = MemoryDefaults()
        defaults.set(["reminders", "ticktick", "asana"], forKey: NookTodoHub.sourcesKey)
        let rig = rig(defaults: defaults, reminders: [item("r1")])
        await rig.tickTick.setupTask?.value
        await rig.hub.asana.setupTask?.value

        rig.tickTick.rows = [tickTickRow("t1")]
        rig.tickTick.state = .noToken
        #expect(rig.hub.items(reminders: rig.nook.reminders).map(\.id) == ["r1"], "TickTick is not ready")

        rig.tickTick.state = .ready
        #expect(rig.hub.items(reminders: rig.nook.reminders).map(\.id) == ["r1", "t1"])
    }

    @Test func aSectionThatIsOffAddsNothingToTheMergedList() {
        let rig = rig(reminders: [item("r1")])
        rig.tickTick.rows = [tickTickRow("t1")]
        rig.tickTick.state = .ready

        #expect(rig.hub.items(reminders: rig.nook.reminders).map(\.id) == ["r1"])
    }

    @Test func sourceHoldingFindsTheServiceThatHasTheTask() async {
        let defaults = MemoryDefaults()
        defaults.set(["reminders", "ticktick"], forKey: NookTodoHub.sourcesKey)
        let rig = rig(defaults: defaults, reminders: [item("r1")])
        await rig.tickTick.setupTask?.value
        rig.tickTick.rows = [tickTickRow("t1")]
        rig.tickTick.state = .ready

        let reminders = rig.nook.reminders
        let forReminder = rig.hub.source(holding: "r1", reminders: reminders)
        let forTickTick = rig.hub.source(holding: "t1", reminders: reminders)

        #expect(forReminder.map { $0 as AnyObject } === reminders)
        #expect(forTickTick.map { $0 as AnyObject } === rig.tickTick)
        #expect(rig.hub.source(holding: "nope", reminders: reminders) == nil)
    }

    @Test func sourceForKindGivesTheServiceBehindIt() {
        let rig = rig()
        let reminders = rig.nook.reminders

        #expect(rig.hub.source(for: .reminders, reminders: reminders) === reminders)
        #expect(rig.hub.source(for: .notion, reminders: reminders) === rig.hub.notion)
        #expect(rig.hub.source(for: .tickTick, reminders: reminders) === rig.tickTick)
        #expect(rig.hub.source(for: .asana, reminders: reminders) === rig.hub.asana)
        #expect(rig.hub.source(for: .monday, reminders: reminders) === rig.hub.monday)
        #expect(rig.hub.source(for: .canvas, reminders: reminders) === rig.hub.canvas)
        #expect(rig.hub.source(reminders: reminders) === reminders, "the add target is Reminders")
    }
}
