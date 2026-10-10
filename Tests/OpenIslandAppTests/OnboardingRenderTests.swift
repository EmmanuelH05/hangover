import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Draws every page of the welcome tour offscreen with `ImageRenderer`. The
/// pages are plain SwiftUI, which is what lets this work: an AppKit-backed
/// control would come out as a placeholder. Set
/// `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to also write one PNG a page to
/// `output/render/onboarding/` under the repo root.
///
/// Nothing here opens a window, and the tours are fed a fixed state with
/// actions that do nothing.
@MainActor
struct OnboardingRenderTests {
    private static let scale: CGFloat = 2
    private static let snapshotEnvKey = "OPEN_ISLAND_RENDER_SNAPSHOTS"

    /// A setup part of the way through: one agent connected, one busy, one
    /// that cannot be connected yet, and a template on.
    private static var sampleState: OnboardingState {
        OnboardingState(
            openTrigger: .hover,
            isIslandOpen: false,
            agents: [
                .claudeCode: OnboardingAgentStatus(isConnected: true),
                .codex: OnboardingAgentStatus(isBusy: true),
                .cursor: OnboardingAgentStatus(canConnect: false),
            ],
            closedSide: .count,
            enabledWidgets: Set(NookWidgetKind.defaultEnabled),
            appliedTemplate: .planner,
            glowStyle: .subtle,
            glowThemeID: IslandHaloTheme.standard.id,
            approveKeys: ["control", "option", "Y"],
            denyKeys: ["control", "option", "N"]
        )
    }

    /// The sample state, with a page that has the to-do, notes and weather widgets
    /// for the pages that need them: the planner template leaves notes off.
    static func state(for page: OnboardingPage) -> OnboardingState {
        guard page == .notes || page == .weather else { return sampleState }
        var state = sampleState
        state.nookPlacements = [.todo, .notes, .weather].map { NookWidgetPlacement(kind: $0, size: .medium) }
        return state
    }

    /// A page's snapshot name with what is special about this picture.
    private static func name(_ page: OnboardingPage, _ variant: String) -> String {
        "\(page.snapshotName)-\(variant)"
    }

    /// The same setup with the agents switched off.
    private static var nookOnlyState: OnboardingState {
        var state = sampleState
        state.agentsEnabled = false
        state.closedSide = .nothing
        state.closedLeft = .nothing
        return state
    }

    @Test func everyPageDrawsSomethingOfItsOwn() throws {
        let blank = try render(nil) {
            V6Palette.ink.frame(width: OnboardingStyle.windowSize.width, height: OnboardingStyle.windowSize.height)
        }
        let pages = try OnboardingPage.allCases.map { page in
            try render(page.snapshotName) { tourView(page, Self.state(for: page)) }
        }

        for (page, png) in zip(OnboardingPage.allCases, pages) {
            #expect(png != blank, "\(page) came out blank")
        }
        #expect(Set(pages).count == OnboardingPage.allCases.count, "every page should draw its own picture")
    }

    @Test func everyPageIsTheSizeOfTheWindow() throws {
        for page in OnboardingPage.allCases {
            let size = OnboardingTestSize.of(page)
            let image = try image { tourView(page, Self.state(for: page)) }
            #expect(image.width == Int(size.width * Self.scale), "\(page) is \(image.width) wide")
            #expect(image.height == Int(size.height * Self.scale), "\(page) is \(image.height) tall")
        }
    }

    /// A live page (D44) is drawn at the narrow window's least and greatest
    /// width and comes out different from every other page at both.
    @Test(arguments: OnboardingTestSize.narrowWidths)
    func everyLivePageDrawsInTheNarrowWindow(width: CGFloat) throws {
        var pictures: [Data] = []
        for page in OnboardingPage.allCases where page.isLive {
            let size = CGSize(width: width, height: OnboardingWindowFrame.narrowMaxHeight)
            pictures.append(try render(Self.name(page, "narrow-\(Int(width))")) {
                tourView(page, Self.state(for: page), size: size)
            })
        }
        #expect(pictures.count == 7)
        #expect(Set(pictures).count == pictures.count, "two live pages drew the same picture")
    }

    /// The arrange page in every state it has, at the narrowest window:
    /// the pick, each step, a step asked again, the end and a widget gone.
    @Test func theArrangePageDrawsEveryStateOfTheWalkThrough() throws {
        let start = [
            NookWidgetPlacement(kind: .media, size: .large),
            NookWidgetPlacement(kind: .todo, size: .small),
            NookWidgetPlacement(kind: .notes, size: .small),
        ]
        var pick = Self.sampleState
        pick.nookPlacements = start
        pick.arrangeStart = start
        var walk = pick
        walk.arrangePick = OnboardingArrangePick(kind: .media, atPick: start)
        walk.isEditingWidgets = true
        var moved = walk
        moved.nookPlacements = [start[1], start[0], start[2]]
        var resized = moved
        resized.nookPlacements = [NookWidgetPlacement(kind: .todo, size: .small), NookWidgetPlacement(kind: .media, size: .small), start[2]]
        var stopped = walk
        stopped.isEditingWidgets = false
        stopped.arrangePick?.hasEndedEditing = true
        var end = resized
        end.isEditingWidgets = false
        end.arrangePick?.hasEndedEditing = true
        var gone = walk
        gone.nookPlacements = [start[1], start[2]]

        let states: [(String, OnboardingState)] = [
            ("pick", pick), ("move", walk), ("resize", moved), ("finish", resized),
            ("stopped", stopped), ("end", end), ("gone", gone),
        ]
        let size = CGSize(width: 320, height: OnboardingWindowFrame.narrowMaxHeight)
        let pictures = try states.map { name, state in
            try render(Self.name(.arrange, name)) { tourView(.arrange, state, size: size) }
        }
        #expect(Set(pictures).count == states.count, "each state of the walk-through should draw its own picture")
        // The widest narrow window draws it too.
        _ = try render(Self.name(.arrange, "move-420")) {
            tourView(.arrange, walk, size: CGSize(width: 420, height: OnboardingWindowFrame.narrowMaxHeight))
        }
    }

    /// The layout cards are quiet grays: no pixel of a card's miniature is
    /// colored, whatever the widget.
    @Test func theLayoutCardsHaveNoColorAWidget() throws {
        let image = try image {
            OnboardingLayoutThumb(
                placements: PersonalizationTemplate.everything.widgets,
                calendarStyle: .hero,
                name: { $0.title },
                size: CGSize(width: 120, height: 90)
            )
            .background(Color.black)
        }
        let colored = Self.coloredPixelCount(image)
        #expect(colored == 0, "\(colored) colored pixels in a layout miniature")
    }

    /// Counts the pixels whose red, green and blue differ by more than the
    /// rounding of the renderer.
    private static func coloredPixelCount(_ image: CGImage) -> Int {
        let representation = NSBitmapImageRep(cgImage: image)
        var count = 0
        for y in 0..<representation.pixelsHigh {
            for x in 0..<representation.pixelsWide {
                guard let color = representation.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let spread = max(color.redComponent, color.greenComponent, color.blueComponent)
                    - min(color.redComponent, color.greenComponent, color.blueComponent)
                if spread > 0.02 { count += 1 }
            }
        }
        return count
    }

    // MARK: A choice changes its page's picture

    @Test func theWayItOpensShowsOnItsPage() throws {
        var click = Self.sampleState
        click.openTrigger = .click
        #expect(try render(nil) { tourView(.opening, Self.sampleState) } != render(nil) { tourView(.opening, click) })

        var opened = Self.sampleState
        opened.isIslandOpen = true
        #expect(
            try render(Self.name(.opening, "tried")) { tourView(.opening, opened) }
                != render(nil) { tourView(.opening, Self.sampleState) },
            "opening the real island should change the line under the choices"
        )
    }

    /// The purpose page is the agents switch (D41) asked as a question. It
    /// is drawn in SwiftUI alone, which is what lets a snapshot show it.
    @Test func thePurposePageShowsWhichAnswerIsPicked() throws {
        #expect(
            try render(Self.name(.purpose, "agents-off")) { tourView(.purpose, Self.nookOnlyState) }
                != render(nil) { tourView(.purpose, Self.sampleState) }
        )
    }

    @Test func theClosedPageDrawsThePickOnTheIsland() throws {
        var pictures: [Data] = []
        for side in OnboardingClosedSide.allCases {
            var state = Self.sampleState
            state.closedSide = side
            pictures.append(try render(Self.name(.closed, side.rawValue)) { tourView(.closed, state) })
        }
        #expect(Set(pictures).count == OnboardingClosedSide.allCases.count, "every pick should draw its own picture")

        // A pick made in Settings that the tour does not offer selects no
        // card and says why.
        var own = Self.sampleState
        own.closedSide = nil
        #expect(!pictures.contains(try render(Self.name(.closed, "own")) { tourView(.closed, own) }))
    }

    /// Both sides of the closed island, every card, with the agents on and
    /// off. A pick on either side redraws the page, and each side has its own
    /// picture for every card.
    @Test func theClosedPageDrawsEveryCardOfBothSidesWithTheAgentsOnAndOff() throws {
        for agents in [true, false] {
            var base = agents ? Self.sampleState : Self.nookOnlyState
            base.agentsEnabled = agents
            let variant = agents ? "agents-on" : "agents-off"
            let blank = try render(nil) { V6Palette.ink.frame(width: 900, height: 640) }
            let first = try render(Self.name(.closed, variant)) { tourView(.closed, base) }
            #expect(first != blank)

            var pictures: [Data] = [first]
            for left in OnboardingClosedLeft.offered(agentsEnabled: agents) where left != base.closedLeft {
                var state = base
                state.closedLeft = left
                pictures.append(try render(Self.name(.closed, "\(variant)-left-\(left.rawValue)")) { tourView(.closed, state) })
            }
            for side in OnboardingClosedSide.offered(agentsEnabled: agents) where side != base.closedSide {
                var state = base
                state.closedSide = side
                pictures.append(try render(Self.name(.closed, "\(variant)-right-\(side.rawValue)")) { tourView(.closed, state) })
            }
            // The music group: each style and each switch redraws the page.
            for style in NookClosedMediaStyle.allCases where style != base.closedMusic.style {
                var state = base
                state.closedMusic.style = style
                pictures.append(try render(Self.name(.closed, "\(variant)-music-\(style.rawValue)")) { tourView(.closed, state) })
            }
            for option in NookClosedMusicOption.offered(agentsEnabled: agents, profile: base.displayProfile) {
                var state = base
                if state.closedMusic.onOptions.contains(option) {
                    state.closedMusic.onOptions.remove(option)
                } else {
                    state.closedMusic.onOptions.insert(option)
                }
                pictures.append(try render(nil) { tourView(.closed, state) })
            }
            // An external display adds the two center label switches.
            var topBar = base
            topBar.displayProfile = .topBar
            pictures.append(try render(Self.name(.closed, "\(variant)-top-bar")) { tourView(.closed, topBar) })
            #expect(Set(pictures).count == pictures.count, "each pick should redraw the page (\(variant))")
        }
    }

    @Test func theWidgetsPageDrawsTheWidgetsThatAreOn() throws {
        let standard = try render(nil) { tourView(.widgets, Self.sampleState) }

        var withMirror = Self.sampleState
        withMirror.appliedTemplate = nil
        withMirror.enabledWidgets.insert(.mirror)
        var plain = withMirror
        plain.enabledWidgets.remove(.mirror)
        #expect(try render(Self.name(.widgets, "mirror")) { tourView(.widgets, withMirror) } != render(nil) { tourView(.widgets, plain) })

        var none = Self.sampleState
        none.enabledWidgets = []
        #expect(try render(Self.name(.widgets, "none")) { tourView(.widgets, none) } != standard)

        // The display's own page wins over the template's when the app
        // hands one in.
        var own = Self.sampleState
        own.nookPlacements = [NookWidgetPlacement(kind: .timer, size: .small)]
        #expect(try render(nil) { tourView(.widgets, own) } != standard)
    }

    /// Each source draws its own card as picked, its own name on the
    /// widget and its own steps.
    @Test func theToDosPageDrawsEachSourcesOwnSteps() throws {
        var pictures: [Data] = []
        for source in NookTodoSourceKind.allCases {
            var state = Self.sampleState
            state.todoSource = source
            pictures.append(try render(Self.name(.todos, source.rawValue)) { tourView(.todos, state) })
        }
        #expect(Set(pictures).count == NookTodoSourceKind.allCases.count, "every source should draw its own picture")

        // Once the source is connected the page draws it ticked.
        var connected = Self.sampleState
        connected.todoSource = .notion
        connected.todoSetup = OnboardingTodoSetup(isConnected: true, accountName: "Nook")
        #expect(!pictures.contains(try render(Self.name(.todos, "notion-connected")) { tourView(.todos, connected) }))
    }

    /// With the to-do widget off the page, a tour asked for the to-dos
    /// page shows the page before it, and the recap names no task source.
    @Test func withTheToDoWidgetOffItsPageIsNotDrawn() throws {
        var off = Self.sampleState
        off.appliedTemplate = nil
        off.enabledWidgets.remove(.todo)
        var on = off
        on.enabledWidgets.insert(.todo)

        #expect(try render(nil) { tourView(.todos, off) } == render(nil) { tourView(.arrange, off) })
        #expect(try render(nil) { tourView(.todos, on) } != render(nil) { tourView(.widgets, on) })
        #expect(try render(Self.name(.done, "no-todo")) { tourView(.done, off) } != render(nil) { tourView(.done, on) })
    }

    @Test func theLayoutPageDrawsTheChosenLayout() throws {
        let planner = try render(nil) { tourView(.layout, Self.sampleState) }

        var focus = Self.sampleState
        focus.appliedTemplate = .focus
        #expect(try render(Self.name(.layout, "focus")) { tourView(.layout, focus) } != planner)

        // On a layout of the user's own the page shows that card, picked.
        var own = Self.sampleState
        own.appliedTemplate = nil
        let ownPicture = try render(Self.name(.layout, "own")) { tourView(.layout, own) }
        #expect(ownPicture != planner)

        // A template picked over the user's own keeps the way back.
        var kept = Self.sampleState
        kept.canKeepOwnLayout = true
        #expect(try render(Self.name(.layout, "keep-mine")) { tourView(.layout, kept) } != planner)
    }

    /// Picking a template changes the big picture: each of the row's
    /// templates draws its own, with the agents on and off.
    @Test func pickingATemplateChangesTheBigPreview() throws {
        for agents in [true, false] {
            var pictures: [Data] = []
            for template in PersonalizationTemplate.offeredInTour(agentsEnabled: agents) {
                var state = agents ? Self.sampleState : Self.nookOnlyState
                state.appliedTemplate = template.id
                let variant = "\(template.id.rawValue)-\(agents ? "agents" : "agents-off")"
                pictures.append(try render(Self.name(.layout, variant)) { tourView(.layout, state) })
            }
            #expect(Set(pictures).count == pictures.count, "two templates drew the same page with agents \(agents)")
        }
    }

    /// The island stands alone in its picture: the framed screen is the
    /// widgets page's.
    @Test func theLayoutPreviewIsTheIslandAloneAndLargerThanTheFramedOne() throws {
        let placements = PersonalizationTemplate.focus.widgets
        let size = CGSize(width: 340, height: 282)
        func preview(_ showsScreen: Bool) -> OnboardingNookPreview {
            OnboardingNookPreview(
                placements: placements, calendarStyle: .hero, profile: .notch,
                emptyTitle: "", size: size, showsScreen: showsScreen
            )
        }
        #expect(try render(nil) { preview(true) } != render(nil) { preview(false) })

        let natural = OnboardingNookPreview.naturalSize(placements: placements, calendarStyle: .hero, profile: .notch, look: .standard)
        let alone = OnboardingScaledPreview<EmptyView>.scale(natural: natural, box: size)
        let framed = OnboardingScaledPreview<EmptyView>.scale(
            natural: natural, box: CGSize(width: size.width - 88, height: size.height - 18)
        )
        #expect(alone > framed)
    }

    @Test func theOpenedPageShowsTheChosenWidthAndCorners() throws {
        var wide = Self.sampleState
        wide.openedLook = IslandOpenedLook(width: .widest, corners: .square)
        var topBar = Self.sampleState
        topBar.displayProfile = .topBar
        let standard = try render(nil) { tourView(.opened, Self.sampleState) }

        #expect(try render(Self.name(.opened, "widest-square")) { tourView(.opened, wide) } != standard)
        #expect(try render(Self.name(.opened, "top-bar")) { tourView(.opened, topBar) } != standard)
    }

    @Test func theGlowPageShowsTheChosenStrengthAndTheme() throws {
        let standard = try render(nil) { tourView(.look, Self.sampleState) }

        var vivid = Self.sampleState
        vivid.glowStyle = .vivid
        #expect(try render(nil) { tourView(.look, vivid) } != standard)

        var off = Self.sampleState
        off.glowStyle = .off
        #expect(try render(Self.name(.look, "off")) { tourView(.look, off) } != standard)

        var themed = Self.sampleState
        themed.glowThemeID = IslandHaloTheme.lagoon.id
        themed.glowPalette = IslandHaloTheme.lagoon.palette
        #expect(try render(Self.name(.look, "lagoon")) { tourView(.look, themed) } != standard)

        var own = Self.sampleState
        own.glowThemeID = nil
        #expect(try render(nil) { tourView(.look, own) } != standard)
    }

    // MARK: The agents page

    @Test func theAgentsPageShowsEachAgentsStanding() throws {
        var none = Self.sampleState
        none.agents = [:]
        #expect(try render(Self.name(.agents, "none")) { tourView(.agents, none) } != render(nil) { tourView(.agents, Self.sampleState) })

        var noKeys = Self.sampleState
        noKeys.approveKeys = nil
        noKeys.denyKeys = nil
        #expect(
            try render(Self.name(.agents, "shortcuts-off")) { tourView(.agents, noKeys) }
                != render(nil) { tourView(.agents, Self.sampleState) }
        )
    }

    @Test func aConnectThatFailedShowsOnItsRowAndUnderTheList() throws {
        var failed = Self.sampleState
        failed.agents[.gemini] = OnboardingAgentStatus(didFail: true)
        #expect(
            try render(Self.name(.agents, "failed")) { tourView(.agents, failed) }
                != render(nil) { tourView(.agents, Self.sampleState) }
        )
    }

    // MARK: The try-it line

    @Test func theTryItLineStaysAnsweredOnceTheIslandWasOpened() throws {
        var opened = Self.sampleState
        opened.hasOpenedIsland = true
        var open = Self.sampleState
        open.isIslandOpen = true
        let waiting = try render(nil) { tourView(.opening, Self.sampleState) }

        // Closed again after having been opened draws what open draws.
        #expect(try render(nil) { tourView(.opening, opened) } != waiting)
        #expect(try render(nil) { tourView(.opening, opened) } == render(nil) { tourView(.opening, open) })
    }

    // MARK: Tips

    @Test func theTipsFollowTheWayTheIslandOpensAndTheWidgetsThatAreOn() throws {
        let standard = try render(nil) { tourView(.tips, Self.sampleState) }

        var click = Self.sampleState
        click.openTrigger = .click
        #expect(try render(Self.name(.tips, "click")) { tourView(.tips, click) } != standard)

        // The app's starting widgets and the agents fill both rows.
        var full = Self.sampleState
        full.appliedTemplate = nil
        #expect(try render(Self.name(.tips, "full")) { tourView(.tips, full) } != standard)
        var fullNookOnly = Self.nookOnlyState
        fullNookOnly.appliedTemplate = nil
        #expect(try render(Self.name(.tips, "full-agents-off")) { tourView(.tips, fullNookOnly) } != standard)

        // With no to-do widget on the page, its tip is gone.
        var noTodo = Self.sampleState
        noTodo.nookPlacements = [NookWidgetPlacement(kind: .media, size: .medium)]
        #expect(try render(Self.name(.tips, "music-only")) { tourView(.tips, noTodo) } != standard)
    }

    // MARK: The recap

    @Test func theLastPageSaysBackWhatWasChosen() throws {
        var other = Self.sampleState
        other.openTrigger = .click
        other.agents = [:]
        other.hasAgentOutsideTour = true
        other.appliedTemplate = nil
        other.glowStyle = .off
        other.denyKeys = nil
        other.closedSide = .date
        other.todoSource = .notion
        #expect(try render(Self.name(.done, "other")) { tourView(.done, other) } != render(nil) { tourView(.done, Self.sampleState) })
    }

    /// The recap names the template picked in the tour even after another
    /// choice made the setup the user's own.
    @Test func theRecapNamesTheTemplateThatWasPicked() throws {
        var own = Self.sampleState
        own.appliedTemplate = nil
        var picked = own
        picked.pickedTemplate = .planner

        #expect(try render(nil) { tourView(.done, picked) } != render(nil) { tourView(.done, own) })
        #expect(try render(nil) { tourView(.done, picked) } == render(nil) { tourView(.done, Self.sampleState) })
    }

    // MARK: The agents switched off

    @Test func thePagesSayNothingAboutAgentsWhileTheSwitchIsOff() throws {
        for page in OnboardingPage.shown(agentsEnabled: false) where !page.offersAgentsSwitch {
            let size = OnboardingTestSize.of(page)
            let expectedWidth = Int(size.width * Self.scale)
            let expectedHeight = Int(size.height * Self.scale)
            let withAgents = try render(nil) { tourView(page, Self.sampleState) }
            let without = try render(Self.name(page, "agents-off")) { tourView(page, Self.nookOnlyState) }
            // On a page that says nothing of agents either way, the step
            // count and the progress dots alone differ: one page fewer.
            #expect(without != withAgents, "\(page) drew the same with the agents off")

            let image = try image { tourView(page, Self.nookOnlyState) }
            #expect(image.width == expectedWidth, "\(page) is \(image.width) wide")
            #expect(image.height == expectedHeight, "\(page) is \(image.height) tall")
        }
    }

    // MARK: - Rendering

    /// The tour in a window of `size`: the full window, or the narrow one
    /// for a live page.
    private func tourView(_ page: OnboardingPage, _ state: OnboardingState, size: CGSize? = nil) -> some View {
        let size = size ?? OnboardingTestSize.of(page)
        return OnboardingView(
            tour: OnboardingTour(startingAt: page, state: { state }),
            lang: LanguageManager.shared
        )
        .frame(width: size.width, height: size.height)
    }

    private func image<Content: View>(@ViewBuilder _ content: () -> Content) throws -> CGImage {
        let renderer = ImageRenderer(content: content().environment(\.nookDrawsStill, true))
        renderer.scale = Self.scale
        let rendered = renderer.cgImage
        return try #require(rendered, "ImageRenderer returned no image")
    }

    private func render<Content: View>(_ name: String?, @ViewBuilder _ content: () -> Content) throws -> Data {
        let representation = NSBitmapImageRep(cgImage: try image(content))
        let encoded = representation.representation(using: .png, properties: [:])
        let png = try #require(encoded, "PNG encoding failed for \(name ?? "a picture")")

        if let name, ProcessInfo.processInfo.environment[Self.snapshotEnvKey] == "1" {
            let directory = Self.repoRoot.appendingPathComponent("output/render/onboarding", isDirectory: true)
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

/// The size a page is drawn at in the tests: the full window, or the narrow
/// one a live page is in (D44).
enum OnboardingTestSize {
    /// The least and the greatest width the narrow window has.
    static let narrowWidths: [CGFloat] = [320, 420]

    static func of(_ page: OnboardingPage) -> CGSize {
        page.isLive
            ? CGSize(width: narrowWidths[0], height: OnboardingWindowFrame.narrowMaxHeight)
            : OnboardingStyle.windowSize
    }
}
