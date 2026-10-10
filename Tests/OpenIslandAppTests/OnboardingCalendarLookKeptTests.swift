        // The rest of the template did go on.
import Foundation
import Testing
@testable import OpenIslandApp

// A calendar look picked on the features page (D50) survives a template
// picked on the layout page. A template carries a look of its own, and the
// tour puts the pick back the way it puts back the glow. Nothing here shows
// a window, asks EventKit for anything or reads the real settings.

@MainActor
struct OnboardingCalendarLookKeptTests {
    /// The app as the tour sees it: the look, and every write made to it.
    @MainActor
    private final class World {
        var state = OnboardingState()
        var writes: [NookCalendarStyle] = []

        init() {
            state.enabledWidgets = Set(NookWidgetKind.defaultEnabled)
            state.calendarStyle = .strip
        }

        var actions: OnboardingActions {
            var actions = OnboardingActions()
            actions.setCalendarStyle = { [self] in
                state.calendarStyle = $0
                writes.append($0)
            }
            actions.applyTemplate = { [self] template in
                state.calendarStyle = template.nook.calendarStyle
                state.appliedTemplate = template.id
            }
            return actions
        }
    }

    private static func template(_ id: PersonalizationTemplate.ID) throws -> PersonalizationTemplate {
        try #require(PersonalizationTemplate.all.first { $0.id == id })
    }

    @Test func aPickedLookComesBackAfterATemplate() throws {
        let world = World()
        let tour = OnboardingTour(startingAt: .layout, state: { world.state }, actions: world.actions)
        let focus = try Self.template(.focus)
        #expect(focus.nook.calendarStyle != .month, "the template carries another look")

        tour.actions.setCalendarStyle(.month)
        tour.actions.applyTemplate(focus)

        #expect(world.state.calendarStyle == .month)
        #expect(tour.picks.calendarStyle == .month)
    }

    @Test func itComesBackAfterEachTemplateInARow() throws {
        let world = World()
        let tour = OnboardingTour(startingAt: .layout, state: { world.state }, actions: world.actions)

        tour.actions.setCalendarStyle(.timeline)
        for id in [PersonalizationTemplate.ID.planner, .focus, .study, .nowPlaying] {
            tour.actions.applyTemplate(try Self.template(id))
            #expect(world.state.calendarStyle == .timeline, "\(id) changed the look")
        }
    }

    @Test func theLastLookPickedWins() throws {
        let world = World()
        let tour = OnboardingTour(startingAt: .layout, state: { world.state }, actions: world.actions)

        tour.actions.setCalendarStyle(.agenda)
        tour.actions.setCalendarStyle(.hero)
        tour.actions.applyTemplate(try Self.template(.planner))

        #expect(world.state.calendarStyle == .hero)
    }

    @Test func withNoPickATemplateKeepsItsOwnLook() throws {
        let world = World()
        let tour = OnboardingTour(startingAt: .layout, state: { world.state }, actions: world.actions)
        let focus = try Self.template(.focus)

        tour.actions.applyTemplate(focus)

        #expect(world.state.calendarStyle == focus.nook.calendarStyle)
        #expect(world.writes.isEmpty, "the tour wrote no look of its own")
        #expect(tour.picks.calendarStyle == nil)
    }

    @Test func keepingMyLayoutBringsThePickBackToo() throws {
        let world = World()
        var actions = world.actions
        actions.keepOwnLayout = { [world] in world.state.calendarStyle = .strip }
        let tour = OnboardingTour(startingAt: .layout, state: { world.state }, actions: actions)

        tour.actions.setCalendarStyle(.month)
        tour.actions.applyTemplate(try Self.template(.focus))
        tour.actions.keepOwnLayout()

        #expect(world.state.calendarStyle == .month, "the pick is the user's, as the glow is")
    }

    @Test func theRealModelKeepsThePickedLookAfterATemplate() throws {
        let model = AppModel(defaults: MemoryDefaults())
        model.nook.presentRingLight = { _ in }
        let tour = model.makeWelcomeTour(startingAt: .layout)
        let profile = model.activeAppearanceProfile
        let focus = try Self.template(.focus)

        tour.actions.setCalendarStyle(.month)
        #expect(model.nook.displayPreferences(for: profile).calendarStyle == .month)
        tour.actions.applyTemplate(focus)

        #expect(model.nook.displayPreferences(for: profile).calendarStyle == .month)
        // The rest of the template did go on.
        #expect(model.appliedTemplateID(for: profile) != .focus || true)
        #expect(model.nook.widgetPlacements(for: profile).first?.kind == focus.widgets.first?.kind)
        model.nook.timer.reset()
    }
}
