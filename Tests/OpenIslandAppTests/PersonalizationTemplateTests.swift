import Foundation
import Testing
@testable import OpenIslandApp

@Suite struct PersonalizationTemplateTests {
    private typealias Template = PersonalizationTemplate

    /// A setup nobody would mistake for a template: its own order, sizes,
    /// hidden widgets and calendars.
    private static func customDisplay() -> NookDisplayPreferences {
        var display = NookDisplayPreferences()
        display.leftSlot = .grid
        display.calendarStyle = .timeline
        display.widgetOrder = [.notes, .media, .calendar, .tray, .todo, .timer, .mirror]
        display.widgetSizes = [.notes: .large, .tray: .small]
        display.hiddenWidgets = [.timer]
        display.hiddenCalendarIDs = ["work", "family"]
        return display
    }

    private static func customSetup() -> PersonalizationSetup {
        var appearance = IslandAppearancePreferences()
        appearance.sessionGroup = .project
        return PersonalizationSetup(appearance: appearance, nook: customDisplay())
    }

    private static func setup(on template: Template) -> PersonalizationSetup {
        PersonalizationSetup(appearance: template.appearance, nook: template.applying(to: NookDisplayPreferences()))
    }

    // MARK: The set

    @Test func thereAreFiveTemplatesInTheListedOrder() {
        #expect(Template.all.map(\.id) == Template.ID.allCases)
        #expect(Template.all.count == 5)
    }

    @Test func noTemplatePlacesTheMirror() {
        for template in Template.all {
            #expect(!template.widgetKinds.contains(.mirror), "\(template.id)")
        }
    }

    @Test func everyTemplatePlacesEachWidgetOnce() {
        for template in Template.all {
            #expect(!template.widgets.isEmpty, "\(template.id)")
            #expect(Set(template.widgetKinds).count == template.widgetKinds.count, "\(template.id)")
        }
    }

    // MARK: Applying to a display

    @Test func applyingPutsTheTemplatesWidgetsOnThePageInOrder() {
        for template in Template.all {
            let applied = template.applying(to: Self.customDisplay())

            #expect(applied.placements(enabled: NookWidgetKind.allCases) == template.widgets, "\(template.id)")
        }
    }

    @Test func applyingTwiceChangesNothingMore() {
        for template in Template.all {
            let once = template.applying(to: Self.customDisplay())

            #expect(template.applying(to: once) == once, "\(template.id)")
        }
    }

    @Test func applyingKeepsTheCalendarsAndTheWidgetsLeftOffThePage() {
        let applied = Template.planner.applying(to: Self.customDisplay())

        #expect(applied.hiddenCalendarIDs == ["work", "family"])
        // Notes and the tray are not on the planner's page. They keep their
        // sizes and their order relative to each other.
        #expect(applied.widgetSizes[.notes] == .large)
        #expect(applied.widgetSizes[.tray] == .small)
        #expect(applied.widgetOrder == [.calendar, .todo, .notes, .media, .tray, .timer, .mirror, .weather])
        #expect(applied.hiddenWidgets == [.media, .notes, .tray, .timer, .mirror, .weather])
    }

    @Test func applyingSetsEveryChoiceTheTemplateOwns() {
        let applied = Template.minimal.applying(to: Self.customDisplay())

        #expect(applied.leftSlot == .agents)
        #expect(applied.mediaStyle == .off)
        #expect(applied.showsNotices == false)
        #expect(applied.haloStyle == .off)
        #expect(applied.calendarStyle == .agenda)
    }

    // MARK: Matching

    @Test func aDisplayMatchesOnlyTheTemplateAppliedToIt() {
        for applied in Template.all {
            let display = applied.applying(to: Self.customDisplay())
            let matching = Template.all.filter { $0.matches(appearance: applied.appearance, nook: display) }

            #expect(matching.map(\.id) == [applied.id], "\(applied.id)")
        }
    }

    @Test func anyVisibleChangeEndsTheMatch() {
        let template = Template.cockpit
        let display = template.applying(to: NookDisplayPreferences())

        var otherGlow = display
        otherGlow.haloStyle = .subtle
        var resized = display
        resized.widgetSizes[.todo] = .large
        var reordered = display
        reordered.widgetOrder = [.todo, .timer, .tray]
        var extraWidget = display
        extraWidget.hiddenWidgets.remove(.notes)
        var otherGroup = template.appearance
        otherGroup.sessionGroup = .none

        #expect(template.matches(appearance: template.appearance, nook: display))
        #expect(!template.matches(appearance: template.appearance, nook: otherGlow))
        #expect(!template.matches(appearance: template.appearance, nook: resized))
        #expect(!template.matches(appearance: template.appearance, nook: reordered))
        #expect(!template.matches(appearance: template.appearance, nook: extraWidget))
        #expect(!template.matches(appearance: otherGroup, nook: display))
    }

    @Test func pickingCalendarsKeepsTheMatch() {
        let template = Template.planner
        var display = template.applying(to: NookDisplayPreferences())
        display.hiddenCalendarIDs = ["work"]

        #expect(template.matches(appearance: template.appearance, nook: display))
    }

    @Test func layoutsThatDrawAlikeMatch() {
        let template = Template.cockpit
        var display = template.applying(to: Self.customDisplay())
        // The same page saved another way: only the leading widgets listed,
        // a medium size spelled out, and the hidden widgets resized.
        display.widgetOrder = [.timer, .tray, .todo]
        display.widgetSizes[.todo] = .medium
        display.widgetSizes[.media] = .large

        #expect(template.matches(appearance: template.appearance, nook: display))
    }

    @Test func resettingTheLayoutEndsTheMatchOnlyWhenThePageChanges() {
        // Reset layout puts the order and sizes back to the defaults and
        // leaves hidden widgets hidden.
        func reset(_ display: NookDisplayPreferences) -> NookDisplayPreferences {
            var result = display
            result.widgetOrder = NookWidgetKind.allCases
            result.widgetSizes = [:]
            return result
        }
        // The planner's page already is the default order at medium size.
        let planner = Template.planner
        let plannerDisplay = planner.applying(to: Self.customDisplay())
        // The focus page is not: its timer leads and is large.
        let focus = Template.focus
        let focusDisplay = focus.applying(to: Self.customDisplay())

        #expect(planner.matches(appearance: planner.appearance, nook: reset(plannerDisplay)))
        #expect(!focus.matches(appearance: focus.appearance, nook: reset(focusDisplay)))
    }

    // MARK: Widgets that are switched off

    @Test func aSwitchedOffWidgetIsReportedAndTheTemplateStillMatches() {
        let template = Template.focus
        let display = template.applying(to: NookDisplayPreferences())
        let enabled: [NookWidgetKind] = [.media, .calendar, .todo, .notes]

        #expect(template.widgetsSwitchedOff(enabled: enabled) == [.timer])
        #expect(template.widgetsSwitchedOff(enabled: NookWidgetKind.defaultEnabled).isEmpty)
        #expect(template.matches(appearance: template.appearance, nook: display))
        // The page shows the rest, and the timer keeps its place for later.
        #expect(display.placements(enabled: enabled).map(\.kind) == [.calendar, .todo, .notes])
        #expect(display.placements(enabled: enabled + [.timer]) == template.widgets)
    }

    // MARK: Applying and undoing a setup

    @Test func applyingATemplateHoldsTheSetupFromBefore() {
        let setup = Self.customSetup()
        let applied = setup.applying(.nowPlaying, keeping: nil)

        #expect(applied.setup.appliedTemplateID == .nowPlaying)
        #expect(applied.undo == setup)
        #expect(applied.setup.undoing(setup) == setup)
    }

    @Test func tryingSeveralTemplatesStillLeadsBackToTheFirstSetup() throws {
        let setup = Self.customSetup()
        let first = setup.applying(.cockpit, keeping: nil)
        let second = first.setup.applying(.planner, keeping: first.undo)
        let third = second.setup.applying(.minimal, keeping: second.undo)

        #expect(third.setup.appliedTemplateID == .minimal)
        #expect(third.undo == setup)
        #expect(third.setup.undoing(try #require(third.undo)) == setup)
    }

    @Test func aChangeAfterATemplateStartsAFreshSnapshot() {
        let first = Self.customSetup().applying(.cockpit, keeping: nil)
        var tweaked = first.setup
        tweaked.nook.haloStyle = .subtle
        let second = tweaked.applying(.planner, keeping: first.undo)

        #expect(tweaked.appliedTemplateID == nil)
        #expect(second.undo == tweaked)
    }

    @Test func clickingTheAppliedTemplateChangesNothing() {
        let original = Self.customSetup()
        let first = original.applying(.focus, keeping: nil)
        let again = first.setup.applying(.focus, keeping: first.undo)
        // After a relaunch the display is still on the template and nothing
        // is held. The click must not make an undo that leads nowhere.
        let afterRelaunch = first.setup.applying(.focus, keeping: nil)

        #expect(again.setup == first.setup)
        #expect(again.undo == original)
        #expect(afterRelaunch.setup == first.setup)
        #expect(afterRelaunch.undo == nil)
    }

    @Test func goingFromOneTemplateToAnotherWithNothingHeldGoesBackToTheFirst() {
        // After a relaunch: on the planner, nothing held, then Minimal.
        let onPlanner = Self.setup(on: .planner)
        let applied = onPlanner.applying(.minimal, keeping: nil)

        #expect(applied.setup.appliedTemplateID == .minimal)
        #expect(applied.undo == onPlanner)
    }

    @Test func undoKeepsCalendarsPickedWhileOnATemplate() {
        let setup = Self.customSetup()
        var later = setup.applying(.planner, keeping: nil).setup
        later.nook.hiddenCalendarIDs = ["school"]

        let undone = later.undoing(setup)

        #expect(undone.nook.hiddenCalendarIDs == ["school"])
        #expect(undone.nook.leftSlot == .grid)
        #expect(undone.appearance == setup.appearance)
    }

    // MARK: Thumbnail

    @Test func theThumbnailGlowFollowsTheGlowSetting() {
        for template in Template.all {
            #expect((template.previewGlow == nil) == (template.nook.haloStyle == .off), "\(template.id)")
        }
    }

    @Test func theThumbnailShowsWhatTheClosedIslandWouldShow() {
        #expect(Template.cockpit.previewLeft == .bars)
        #expect(Template.cockpit.previewRight == .agents)
        #expect(Template.nowPlaying.previewLeft == .artwork)
        #expect(Template.nowPlaying.previewRight == .visualizer)
        #expect(Template.planner.previewLeft == .date)
        #expect(Template.planner.previewRight == .countdown)
        #expect(Template.focus.previewLeft == .battery)
        #expect(Template.minimal.previewRight == .none)
    }

    // MARK: Strings

    @Test func everyTemplateStringExistsInEveryLanguage() throws {
        let shared = ["title", "note", "applied", "undo", "show", "hide", "current", "switchedOff"]
            .map { "settings.appearance.templates.\($0)" }
        let perTemplate = Template.ID.allCases.flatMap { id -> [String] in
            let keys = TemplateText.keys(for: id)
            return [keys.title, keys.bestFor] + keys.points
        }

        for language in ["en", "zh-Hans", "zh-Hant"] {
            let url = Self.repoRoot
                .appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String], "\(language) did not load")

            for key in shared + perTemplate {
                let value = table[key] ?? ""
                #expect(!value.isEmpty, "\(language) is missing \(key)")
            }
        }
    }

    /// `Tests/OpenIslandAppTests/<this file>` sits three levels below the root.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
