import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

// The calendar step's picker (D50): the five looks Settings offers, in its
// order, each drawn by the app's own sample calendar; a press writes the look
// through one door and the choice is kept. Nothing here reads or writes the
// real settings or asks EventKit for anything.

// MARK: - What the picker lists

struct OnboardingCalendarLooksListTests {
    @Test func theCardsAreTheLooksSettingsOffersInItsOrder() throws {
        #expect(OnboardingCalendarLooks.all == [.strip, .agenda, .timeline, .hero, .month])
        #expect(OnboardingCalendarLooks.all == NookCalendarStyle.allCases)

        // Settings builds its row from the same list, with these names.
        let settings = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Nook/Views/NookPersonalizationSections.swift")
        #expect(settings.contains("options: NookCalendarStyle.allCases"))
        let english = try HangoverBrandTests.table("en")
        for style in OnboardingCalendarLooks.all {
            #expect(settings.contains("lang.t(\"\(OnboardingCalendarLooks.nameKey(style))\")"))
            #expect(english[OnboardingCalendarLooks.nameKey(style)] != nil)
        }
    }

    @Test func everyLookHasANameAndALineInEveryLanguage() throws {
        for language in HangoverBrandTests.languages {
            let table = try HangoverBrandTests.table(language)
            for style in OnboardingCalendarLooks.all {
                for key in [OnboardingCalendarLooks.nameKey(style), OnboardingCalendarLooks.lineKey(style)] {
                    #expect(!(table[key] ?? "").isEmpty, "\(language) has no \(key)")
                }
            }
            for key in [OnboardingCalendarLooks.titleKey, OnboardingCalendarLooks.noteKey, "onboarding.done.recap.calendar"] {
                #expect(!(table[key] ?? "").isEmpty, "\(language) has no \(key)")
            }
        }
    }

    @Test func theLinesAreDifferentForEveryLook() throws {
        let english = try HangoverBrandTests.table("en")
        let lines = OnboardingCalendarLooks.all.compactMap { english[OnboardingCalendarLooks.lineKey($0)] }
        #expect(Set(lines).count == 5)
    }

    @Test func theCalendarStepKeepsItsLineAboutFiveLooks() throws {
        let english = try HangoverBrandTests.table("en")
        #expect(english[OnboardingAbility.calendarLooks.textKey] == "Five looks, from a week strip to a month grid.")
        #expect(OnboardingAbility.lines(for: .calendar).contains(.calendarLooks))
    }

    @Test func theRecapNamesTheLookOnlyWhileTheCalendarIsOnThePage() {
        #expect(OnboardingRecapRow.shown(agentsEnabled: true, hasCalendarWidget: true) == OnboardingRecapRow.allCases)
        #expect(OnboardingRecapRow.shown(agentsEnabled: true, hasCalendarWidget: false)
            == OnboardingRecapRow.allCases.filter { $0 != .calendar })
    }
}

// MARK: - The picture is the app's own

struct OnboardingCalendarLookPictureTests {
    /// The picker draws `NookSampleCard`, the sample card Settings' preview
    /// stage draws, which draws the look from the same sample events. These
    /// pieces of code have to stay in place.
    @Test(arguments: [
        ("Sources/OpenIslandApp/Onboarding/OnboardingCalendarLooks.swift", "NookSampleCard(kind: .calendar, size: .medium, calendarStyle: style)"),
        ("Sources/OpenIslandApp/Onboarding/OnboardingCalendarLooks.swift", "NookCalendarCard.height(for: style)"),
        ("Sources/OpenIslandApp/Views/Settings/PreviewNookPage.swift", "case .calendar: NookSampleCalendar(size: size, style: calendarStyle)"),
        ("Sources/OpenIslandApp/Views/Settings/PreviewNookPage.swift", "private struct NookSampleCalendar: View"),
        ("Sources/OpenIslandApp/Nook/Widgets/Calendar/NookCalendarCard.swift", "case .strip: NookCalendarStripView.height"),
        ("Sources/OpenIslandApp/Nook/Widgets/Calendar/NookCalendarCard.swift", "case .month: NookCalendarMonthView.height"),
    ])
    func theCodeBehindThePictureIsStillThere(file: String, text: String) throws {
        let source = try HangoverBrandTests.text(of: file)
        #expect(source.contains(text), "\(file) no longer has: \(text)")
    }

    @Test func eachPictureHasTheHeightTheRealCardHas() {
        for style in OnboardingCalendarLooks.all {
            #expect(OnboardingCalendarLookPicture.naturalHeight(style) == NookCalendarCard.height(for: style))
        }
    }
}

// MARK: - The press and what keeps it

@MainActor
struct OnboardingCalendarLooksTourTests {
    /// The app as the tour sees it: the look the display is on, and the
    /// doors pulled in order. The door does to the state what the real one
    /// does to the display's preferences.
    @MainActor
    private final class World {
        var state = OnboardingState()
        var calls: [String] = []

        init() {
            state.nookPlacements = [.calendar, .media].map { NookWidgetPlacement(kind: $0, size: .medium) }
            state.enabledWidgets = Set(NookWidgetKind.allCases)
        }

        var actions: OnboardingActions {
            var actions = OnboardingActions()
            actions.setCalendarStyle = { [self] in calls.append("look \($0.rawValue)"); state.calendarStyle = $0 }
            actions.setMirror = { [self] in calls.append("mirror \($0)") }
            return actions
        }
    }

    private static func tourOnCalendar(_ world: World) -> OnboardingTour {
        let tour = OnboardingTour(startingAt: .widgets, state: { world.state }, actions: world.actions, onEnd: { _ in })
        tour.next()
        return tour
    }

    @Test func aPressCallsTheDoorWithThatLookAndTheStateShowsItChosen() {
        let world = World()
        let tour = Self.tourOnCalendar(world)
        #expect(tour.state.featureKind == .calendar)
        #expect(tour.state.calendarStyle == .strip)

        tour.actions.setCalendarStyle(.month)

        #expect(world.calls == ["look month"])
        #expect(tour.state.calendarStyle == .month)
    }

    @Test func leavingTheStepThePageOrTheTourDoesNotChangeItBack() {
        let world = World()
        let tour = Self.tourOnCalendar(world)
        tour.actions.setCalendarStyle(.timeline)

        tour.actions.nextFeature()
        #expect(tour.state.calendarStyle == .timeline, "leaving the step")
        tour.actions.previousFeature()
        tour.next()
        #expect(tour.page == .layout)
        #expect(tour.state.calendarStyle == .timeline, "leaving the page")
        tour.back()
        tour.skip()
        #expect(tour.state.calendarStyle == .timeline, "leaving the tour")
        #expect(world.calls == ["look timeline"], "nothing wrote it again or put it back")
    }

    @Test func theLookIsNotATryItAndTheTrialsKnowNothingOfIt() {
        let world = World()
        let tour = Self.tourOnCalendar(world)

        tour.actions.setCalendarStyle(.hero)

        #expect(tour.state.featureProgress == OnboardingFeatureProgress())
        #expect(OnboardingTry.allCases.allSatisfy { $0.doorName != "setCalendarStyle" })
    }

    @Test func theLastLookPressedIsTheOneInUse() {
        let world = World()
        let tour = Self.tourOnCalendar(world)

        tour.actions.setCalendarStyle(.agenda)
        tour.actions.setCalendarStyle(.hero)

        #expect(world.calls == ["look agenda", "look hero"])
        #expect(tour.state.calendarStyle == .hero)
    }
}

// MARK: - Drawn

@MainActor
struct OnboardingCalendarLooksRenderTests {
    private static let scale: CGFloat = 2
    private static let snapshotEnvKey = "OPEN_ISLAND_RENDER_SNAPSHOTS"
    private static let tallHeight: CGFloat = 2400

    private static func state(look: NookCalendarStyle) -> OnboardingState {
        var state = OnboardingState()
        state.enabledWidgets = Set(NookWidgetKind.allCases)
        state.nookPlacements = NookWidgetKind.allCases.map { NookWidgetPlacement(kind: $0, size: .medium) }
        state.featureKind = .calendar
        state.calendarStyle = look
        return state
    }

    @Test func eachLookDrawsItsOwnPictureAtTheSizeOfACard() throws {
        var pictures: [Data] = []
        for style in OnboardingCalendarLooks.all {
            let png = try render("07-features-calendar-look-\(style.rawValue)") {
                OnboardingCalendarLookPicture(style: style)
                    .frame(width: OnboardingCalendarLookPicture.naturalWidth)
                    .padding(10)
                    .background(OnboardingStyle.ink)
            }
            pictures.append(png)
        }
        #expect(Set(pictures).count == 5, "two looks drew the same picture")
    }

    @Test(arguments: OnboardingTestSize.narrowWidths)
    func theCalendarStepDrawsAtBothWidths(width: CGFloat) throws {
        let png = try render("07-features-calendar-\(Int(width))") { tourView(Self.state(look: .strip), width: width) }
        let other = try render(nil) { tourView(Self.state(look: .month), width: width) }
        #expect(png != other, "the card in use should be marked")
    }

    @Test func theCalendarStepIsNotTheMediaStep() throws {
        var media = Self.state(look: .strip)
        media.featureKind = .media
        let calendar = try render(nil) { tourView(Self.state(look: .strip), width: 320) }
        let other = try render(nil) { tourView(media, width: 320) }
        #expect(calendar != other)
    }

    private func tourView(_ state: OnboardingState, width: CGFloat) -> some View {
        OnboardingView(
            tour: OnboardingTour(startingAt: .features, state: { state }),
            lang: LanguageManager.shared
        )
        .frame(width: width, height: Self.tallHeight)
    }

    private func render<Content: View>(_ name: String?, @ViewBuilder _ content: () -> Content) throws -> Data {
        let renderer = ImageRenderer(content: content().environment(\.nookDrawsStill, true))
        renderer.scale = Self.scale
        let image = try #require(renderer.cgImage, "ImageRenderer returned no image")
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]), "PNG encoding failed")
        if let name, ProcessInfo.processInfo.environment[Self.snapshotEnvKey] == "1" {
            let directory = HangoverBrandTests.repoRoot.appendingPathComponent("output/render/onboarding", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return png
    }
}
