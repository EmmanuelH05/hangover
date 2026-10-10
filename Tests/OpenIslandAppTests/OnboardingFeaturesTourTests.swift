import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

// The features page in a tour (D47): the ring follows the walk, the buttons
// reach the doors, and every way out of the page, or out of a widget's step,
// switches off what the tour switched on and leaves alone what the user had
// on before. Nothing here starts a camera or lights a screen: the doors are
// recorders that change a plain state.

@MainActor
struct OnboardingFeaturesTourTests {
    /// The app as the tour sees it: the state it reads, and the doors it
    /// pulled, in order. Each door does to the state what the real one does.
    @MainActor
    private final class World {
        var state = OnboardingState()
        var calls: [String] = []
        var outlines: [NookWidgetKind?] = []
        var holds: [Bool] = []

        init(
            kinds: [NookWidgetKind] = [.mirror, .media, .timer, .tray],
            features: OnboardingFeatureReading = OnboardingFeatureReading()
        ) {
            state.nookPlacements = kinds.map { NookWidgetPlacement(kind: $0, size: .medium) }
            state.enabledWidgets = Set(NookWidgetKind.allCases)
            state.features = features
        }

        var actions: OnboardingActions {
            var actions = OnboardingActions()
            actions.setMirror = { [self] in calls.append("mirror \($0)"); state.features.isMirrorOn = $0 }
            actions.setRingLight = { [self] in calls.append("ring \($0)"); state.features.isRingLightOn = $0 }
            actions.startTimer = { [self] _ in calls.append("timer start"); state.features.isTimerActive = true }
            actions.stopTimer = { [self] in calls.append("timer stop"); state.features.isTimerActive = false }
            actions.outlineWidget = { [self] in outlines.append($0) }
            actions.holdIsland = { [self] in holds.append($0) }
            return actions
        }

        /// What the tour switched off, in order.
        var switchedOff: [String] { calls.filter { $0.hasSuffix("false") || $0 == "timer stop" } }
    }

    private static func tour(_ world: World, onEnd: @escaping (OnboardingOutcome) -> Void = { _ in }) -> OnboardingTour {
        OnboardingTour(startingAt: .widgets, state: { world.state }, actions: world.actions, onEnd: onEnd)
    }

    /// A tour on the features page, on the mirror, with the camera and the
    /// ring light switched on by its buttons.
    private static func lit(_ world: World) -> OnboardingTour {
        let tour = Self.tour(world)
        tour.next()
        tour.actions.setMirror(true)
        tour.actions.setRingLight(true)
        return tour
    }

    private func expectBothOff(_ world: World, _ comment: Comment) {
        #expect(!world.state.features.isMirrorOn, comment)
        #expect(!world.state.features.isRingLightOn, comment)
        #expect(world.switchedOff == ["ring false", "mirror false"], comment)
    }

    // MARK: The walk in a tour

    @Test func theFirstWidgetOnThePageIsShownAndRingedWhenThePageComesUp() {
        let world = World()
        let tour = Self.tour(world)
        #expect(tour.state.featureKind == nil, "nothing is picked before the page is up")

        tour.next()

        #expect(tour.page == .features)
        #expect(tour.state.featureKind == .mirror)
        #expect(tour.state.featureWalk.position == 1)
        #expect(world.outlines == [.mirror])
        #expect(world.holds == [true])
    }

    @Test func nextAndPreviousWidgetMoveTheRingAndTheCount() {
        let world = World()
        let tour = Self.tour(world)
        tour.next()

        tour.actions.nextFeature()
        tour.actions.nextFeature()
        #expect(tour.state.featureKind == .timer)
        #expect(tour.state.featureWalk.position == 3 && tour.state.featureWalk.count == 4)

        tour.actions.previousFeature()
        #expect(tour.state.featureKind == .media)
        #expect(world.outlines == [.mirror, .media, .timer, .media])

        tour.actions.previousFeature()
        tour.actions.previousFeature()
        #expect(tour.state.featureKind == .mirror, "the first widget has no previous")
        #expect(world.outlines.count == 5)
    }

    @Test func theToursOwnNextLeavesFromAnyWidget() {
        let world = World()
        let tour = Self.tour(world)
        tour.next()
        tour.actions.nextFeature()

        tour.next()

        #expect(tour.page == .layout)
        #expect(world.outlines.last == .some(nil), "the ring is let go")
        #expect(tour.state.featureKind == nil)
    }

    @Test func nextAndPreviousDoNothingOffThePage() {
        let world = World()
        let tour = Self.tour(world)

        tour.actions.nextFeature()

        #expect(tour.state.featureKind == nil && world.outlines.isEmpty)
    }

    @Test func aWidgetOffThePageIsNotWalked() {
        let world = World(kinds: [.media, .notes])
        let tour = Self.tour(world)
        tour.next()
        #expect(tour.state.featureWalk.kinds == [.media, .notes])
        tour.actions.nextFeature()
        #expect(tour.state.featureKind == .notes)
        tour.actions.nextFeature()
        #expect(tour.state.featureKind == .notes, "the last widget has no next")
    }

    // MARK: The clean-up

    @Test func movingToTheNextWidgetSwitchesOffTheMirrorAndItsLight() {
        let world = World()
        let tour = Self.lit(world)

        tour.actions.nextFeature()

        expectBothOff(world, "leaving the mirror's step")
        #expect(tour.state.featureKind == .media)
    }

    @Test func theToursNextBackAndADotSwitchThemOff() {
        let next = World()
        Self.lit(next).next()
        expectBothOff(next, "Next")

        let back = World()
        Self.lit(back).back()
        expectBothOff(back, "Back")

        let dot = World()
        Self.lit(dot).go(to: .done)
        expectBothOff(dot, "a progress dot")
    }

    @Test func skippingAndFinishingSwitchThemOffOnce() {
        let skipped = World()
        var ended: [OnboardingOutcome] = []
        let skipTour = Self.tour(skipped) { ended.append($0) }
        skipTour.next()
        skipTour.actions.setMirror(true)
        skipTour.actions.setRingLight(true)
        skipTour.skip()
        #expect(ended == [.skipped])
        expectBothOff(skipped, "Skip")

        let finished = World()
        let finishTour = Self.tour(finished) { ended.append($0) }
        finishTour.next()
        finishTour.actions.setMirror(true)
        finishTour.actions.setRingLight(true)
        finishTour.go(to: .done)
        finishTour.next()
        #expect(ended == [.skipped, .finished])
        expectBothOff(finished, "finishing")
    }

    @Test func theWindowClosingSwitchesThemOffBeforeTheSkip() {
        let world = World()
        let tour = Self.lit(world)

        tour.releaseIsland()
        expectBothOff(world, "the window closing")

        tour.skip()
        tour.releaseIsland()
        expectBothOff(world, "and nothing is switched off twice")
    }

    @Test func theUserLeavingTheAppSwitchesThemOffAndTheIslandGoes() {
        let world = World()
        let tour = Self.lit(world)

        tour.setPresence(appIsActive: false, windowIsVisible: true)

        expectBothOff(world, "the hold going off")
        #expect(world.holds.last == false)
    }

    @Test func aTourThatIsDroppedSwitchesThemOff() {
        let world = World()
        var tour: OnboardingTour? = Self.lit(world)
        #expect(world.state.features.isMirrorOn)

        tour = nil

        #expect(tour == nil)
        expectBothOff(world, "the tour being dropped")
    }

    @Test func comingBackToThePageStartsAgainWithTheCameraOff() {
        let world = World()
        let tour = Self.lit(world)
        tour.next()
        tour.back()

        #expect(tour.state.featureKind == .mirror)
        #expect(!world.state.features.isMirrorOn)
        #expect(tour.state.featureProgress.done.isEmpty, "the ticks start over with the page")
    }

    // MARK: What was on before

    @Test func aMirrorAndALightTheUserHadOnBeforeAreLeftAlone() {
        let world = World(features: OnboardingFeatureReading(isMirrorOn: true, isRingLightOn: true))
        let tour = Self.tour(world)
        tour.next()

        // Pressing a switch that is already on does not make it the tour's.
        tour.actions.setMirror(true)
        tour.actions.setRingLight(true)
        tour.actions.nextFeature()
        tour.next()
        tour.releaseIsland()

        #expect(world.switchedOff.isEmpty)
        #expect(world.state.features.isMirrorOn && world.state.features.isRingLightOn)
    }

    @Test func aLightTheTourSwitchedOnGoesOffAndAMirrorTheUserHadOnStays() {
        let world = World(features: OnboardingFeatureReading(isMirrorOn: true))
        let tour = Self.tour(world)
        tour.next()
        tour.actions.setRingLight(true)

        tour.next()

        #expect(world.switchedOff == ["ring false"])
        #expect(world.state.features.isMirrorOn)
    }

    @Test func aTimerTheUserHadRunningIsNotStopped() {
        let world = World(kinds: [.timer], features: OnboardingFeatureReading(isTimerActive: true))
        let tour = Self.tour(world)
        tour.next()
        _ = tour.state

        tour.actions.stopTimer()
        world.calls.removeAll()
        tour.next()

        #expect(world.switchedOff.isEmpty, "the tour stopped nothing of its own")
    }

    @Test func aTimerTheTourStartedIsStoppedWhenTheStepIsLeft() {
        let world = World(kinds: [.timer, .media])
        let tour = Self.tour(world)
        tour.next()
        tour.actions.startTimer(60)
        _ = tour.state
        #expect(tour.state.featureProgress.done.contains(.timerStart))

        tour.actions.nextFeature()

        #expect(world.calls == ["timer start", "timer stop"])
        #expect(!world.state.features.isTimerActive)
    }

    @Test func theTicksAreReadFromTheAppThroughTheTour() {
        let world = World()
        let tour = Self.tour(world)
        tour.next()
        #expect(!tour.state.isDone(.mirrorOn))

        tour.actions.setMirror(true)

        #expect(tour.state.isDone(.mirrorOn))
        #expect(!tour.state.isDone(.ringLight))
    }

    @Test func aNoteSavedWhileTheFeaturesPageIsUpTicksTheNotesStep() {
        let world = World(kinds: [.notes])
        world.state.notesSavedCount = 3
        let tour = Self.tour(world)
        tour.next()
        #expect(!tour.state.isDone(.notesLine))

        world.state.notesSavedCount = 4

        #expect(tour.state.isDone(.notesLine))
    }
}

// MARK: - Drawn pages

@MainActor
struct OnboardingFeaturesRenderTests {
    private static let scale: CGFloat = 2
    private static let snapshotEnvKey = "OPEN_ISLAND_RENDER_SNAPSHOTS"
    /// The window scrolls, and a picture cannot. A taller frame shows the
    /// buttons under a long list of lines.
    private static let tallHeight: CGFloat = 1300

    private static func state(_ kind: NookWidgetKind, kinds: [NookWidgetKind] = NookWidgetKind.allCases) -> OnboardingState {
        var state = OnboardingState()
        state.enabledWidgets = Set(kinds)
        state.nookPlacements = kinds.map { NookWidgetPlacement(kind: $0, size: .medium) }
        state.featureKind = kind
        return state
    }

    @Test(arguments: OnboardingTestSize.narrowWidths)
    func theFeaturesPageDrawsEachWidgetAtBothWidths(width: CGFloat) throws {
        var pictures: [Data] = []
        for kind in NookWidgetKind.allCases {
            pictures.append(try render("07-features-\(kind.rawValue)-\(Int(width))") {
                tourView(Self.state(kind), width: width)
            })
        }
        #expect(Set(pictures).count == NookWidgetKind.allCases.count, "two widgets drew the same page")
    }

    @Test func theMirrorPageDrawsItsStatesAtTheNarrowestWidth() throws {
        let off = Self.state(.mirror)
        var on = off
        on.features = OnboardingFeatureReading(isMirrorOn: true, isRingLightOn: true, canStartBooth: true)
        on.featureProgress = progress(on.features)
        var waiting = off
        waiting.features.isMirrorOn = true

        let pictures = [
            try render("07-features-mirror-off-320") { tourView(off, width: 320, height: Self.tallHeight) },
            try render("07-features-mirror-on-320") { tourView(on, width: 320, height: Self.tallHeight) },
            try render("07-features-mirror-waiting-320") { tourView(waiting, width: 320, height: Self.tallHeight) },
        ]
        #expect(Set(pictures).count == 3, "the mirror's three states should each draw differently")
    }

    @Test func theLastWidgetSaysTheOthersCanBeSwitchedOnAndAllOnSaysNothingOfTheSort() throws {
        let few = Self.state(.weather, kinds: [.media, .weather])
        let all = Self.state(.weather)
        let fewPicture = try render("07-features-weather-few-420") { tourView(few, width: 420) }
        let allPicture = try render(nil) { tourView(all, width: 420) }
        #expect(fewPicture != allPicture)
        #expect(few.featureWalk.isAtEnd && all.featureWalk.isAtEnd)
        #expect(few.featureWalk.kinds.count < NookWidgetKind.allCases.count)
    }

    @Test func noWidgetsDrawsTheEmptyPage() throws {
        var none = Self.state(.media, kinds: [])
        none.nookPlacements = []
        _ = try render("07-features-none-320") { tourView(none, width: 320) }
        #expect(none.featureWalk.current == nil)
    }

    @Test func thePageIsTheNarrowWindowsSize() throws {
        let size = try image { tourView(Self.state(.media), width: 320) }
        #expect(size.width == Int(320 * Self.scale))
        #expect(size.height == Int(OnboardingWindowFrame.narrowMaxHeight * Self.scale))
    }

    // MARK: Rendering

    private func progress(_ reading: OnboardingFeatureReading) -> OnboardingFeatureProgress {
        var progress = OnboardingFeatureProgress()
        progress.note(reading)
        return progress
    }

    private func tourView(_ state: OnboardingState, width: CGFloat, height: CGFloat = OnboardingWindowFrame.narrowMaxHeight) -> some View {
        OnboardingView(
            tour: OnboardingTour(startingAt: .features, state: { state }),
            lang: LanguageManager.shared
        )
        .frame(width: width, height: height)
    }

    private func image<Content: View>(@ViewBuilder _ content: () -> Content) throws -> CGImage {
        let renderer = ImageRenderer(content: content().environment(\.nookDrawsStill, true))
        renderer.scale = Self.scale
        return try #require(renderer.cgImage, "ImageRenderer returned no image")
    }

    private func render<Content: View>(_ name: String?, @ViewBuilder _ content: () -> Content) throws -> Data {
        let representation = NSBitmapImageRep(cgImage: try image(content))
        let png = try #require(representation.representation(using: .png, properties: [:]), "PNG encoding failed")
        if let name, ProcessInfo.processInfo.environment[Self.snapshotEnvKey] == "1" {
            let directory = HangoverBrandTests.repoRoot.appendingPathComponent("output/render/onboarding", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return png
    }
}
