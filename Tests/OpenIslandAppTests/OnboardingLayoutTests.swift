import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

// The layout and arrange pages of the welcome tour (D43, D44): the cards, the miniature
// on each and the checklist that teaches moving and resizing.

// MARK: - The checklist stands on code

struct OnboardingRearrangeProofTests {
    private static let proofs = OnboardingRearrangeStep.allCases.flatMap { $0.proofs }
        + OnboardingRearrangeStep.outlineProofs

    /// Each step names a gesture the app has. These are the pieces of code
    /// that do it, and a step whose code is renamed fails here first.
    @Test(arguments: proofs)
    func theCodeBehindATeachingStepIsStillThere(proof: OnboardingProof) throws {
        let source = try HangoverBrandTests.text(of: proof.file)
        #expect(source.contains(proof.text), "\(proof.file) no longer has: \(proof.text)")
    }

    @Test func everyStepHasAProofAndThereAreThree() {
        #expect(OnboardingRearrangeStep.allCases == [.move, .resize, .finish])
        for step in OnboardingRearrangeStep.allCases {
            #expect(!step.proofs.isEmpty, "\(step) has no proof")
        }
    }

    @Test func theSizesAreNamedAsTheAppNamesThem() throws {
        let english = try HangoverBrandTests.table("en")

        for size in NookWidgetSize.allCases {
            #expect(english["onboarding.arrange.size.\(size.rawValue)"] == size.title)
        }
    }

    @Test func theFinishStepNamesTheControlInTheAppsOwnWords() throws {
        let english = try HangoverBrandTests.table("en")

        #expect(try #require(english[OnboardingRearrangeStep.finish.titleKey]).contains("Done"))
    }

    @Test func theStepsAreToldInEveryLanguageInPlainWords() throws {
        let keys = [
            "title", "body", "pick", "outlined", "gone", "stepOf", "stopped", "end.body", "end.remember",
            "another", "reset", "note", "done", "todo",
        ].map { "onboarding.arrange.\($0)" }
            + NookWidgetSize.allCases.map { "onboarding.arrange.size.\($0.rawValue)" }
            + OnboardingRearrangeStep.allCases.flatMap { [$0.titleKey, $0.doneKey] + [$0.howKey].compactMap { $0 } }
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let table = try HangoverBrandTests.table(language)
            for key in keys {
                let value = try #require(table[key], "\(language) is missing \(key)")
                #expect(!value.isEmpty, "\(language) has an empty \(key)")
                #expect(!value.contains("\u{2014}") && !value.contains("\u{2013}"), "\(language) \(key) has a dash")
                #expect(!value.lowercased().split(separator: " ").contains("so"), "\(language) \(key) says so")
            }
        }
    }

    @Test func noStringOfTheOldChecklistIsLeft() throws {
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let table = try HangoverBrandTests.table(language)
            for key in ["step.hold", "step.drag", "step.resize", "finish"] {
                #expect(table["onboarding.arrange.\(key)"] == nil, "\(language) still has \(key)")
            }
        }
    }
}

// MARK: - The row of cards

struct OnboardingLayoutRowTests {
    @Test func theRowLeavesMinimalOutAndHoldsSevenCardsAtMost() {
        for agents in [true, false] {
            var state = OnboardingState()
            state.agentsEnabled = agents
            let templates = PersonalizationTemplate.offeredInTour(agentsEnabled: agents)
            let cards = templates.count + (OnboardingLayoutPage.offersOwnCard(state) ? 1 : 0)

            #expect(!templates.contains { $0.id == .minimal })
            #expect(cards <= 7, "\(cards) cards with agents \(agents)")
        }
        #expect(PersonalizationTemplate.offeredInTour(agentsEnabled: true).count + 1 == 7)
    }

    @Test func withTheAgentsOffTheAgentTemplateStaysOut() {
        let templates = PersonalizationTemplate.offeredInTour(agentsEnabled: false)

        #expect(!templates.contains { $0.needsAgents })
        #expect(templates.first?.id == .everything)
    }
}

// MARK: - The miniatures

@MainActor
struct OnboardingLayoutThumbTests {
    private static func tiles(_ template: PersonalizationTemplate) -> [OnboardingLayoutThumb.Tile] {
        OnboardingLayoutThumb.tiles(
            template.widgets,
            calendarStyle: template.nook.calendarStyle,
            size: OnboardingLayoutThumb.defaultSize,
            name: { $0.title }
        )
    }

    @Test func everyWidgetIsATileInsideTheBox() {
        let box = CGRect(origin: .zero, size: OnboardingLayoutThumb.defaultSize).insetBy(dx: -0.01, dy: -0.01)
        for template in PersonalizationTemplate.all {
            let tiles = Self.tiles(template)

            #expect(tiles.map(\.kind) == template.widgetKinds, "\(template.id)")
            for tile in tiles {
                #expect(box.contains(tile.frame), "\(template.id) \(tile.kind) is outside the box")
            }
        }
    }

    @Test func sizesShowAtAGlance() throws {
        let tiles = Self.tiles(.everything)
        let media = try #require(tiles.first { $0.kind == .media })
        let calendar = try #require(tiles.first { $0.kind == .calendar })
        let todo = try #require(tiles.first { $0.kind == .todo })
        let notes = try #require(tiles.first { $0.kind == .notes })

        // A small tile is a column, a large one the whole page and taller.
        #expect(media.frame.width > todo.frame.width * 1.8)
        #expect(calendar.frame.width == media.frame.width)
        #expect(media.frame.height > todo.frame.height)
        // Two small tiles sit side by side.
        #expect(todo.frame.minY == notes.frame.minY)
        #expect(todo.frame.maxX < notes.frame.minX)
        // The big tiles have room for their names.
        #expect(media.showsName)
    }

    @Test func aTileIsNamedOnlyWhereTheNameFits() {
        let long = OnboardingLayoutThumb.tiles(
            [NookWidgetPlacement(kind: .todo, size: .small)],
            calendarStyle: .strip,
            size: OnboardingLayoutThumb.defaultSize,
            name: { _ in String(repeating: "W", count: 40) }
        )

        #expect(long.first?.showsName == false)
    }

    /// No two cards look alike: the miniature of each layout, as the page
    /// draws it with the starting widgets on, and with every widget on.
    @Test func everyMiniatureDiffersFromEveryOther() throws {
        for enabled in [Set(NookWidgetKind.defaultEnabled), Set(NookWidgetKind.allCases)] {
            var pictures: [(String, Data)] = []
            for template in PersonalizationTemplate.all {
                let placements = template.widgets.filter { enabled.contains($0.kind) }
                pictures.append((template.id.rawValue, try render(placements, template.nook.calendarStyle)))
            }
            let own = NookDisplayPreferences().placements(enabled: Array(enabled))
            pictures.append(("own", try render(own, .strip)))

            for (index, picture) in pictures.enumerated() {
                for other in pictures[(index + 1)...] {
                    #expect(picture.1 != other.1, "\(picture.0) and \(other.0) look alike")
                }
            }
        }
    }

    private func render(_ placements: [NookWidgetPlacement], _ style: NookCalendarStyle) throws -> Data {
        let thumb = OnboardingLayoutThumb(
            placements: placements,
            calendarStyle: style,
            name: { $0.title }
        )
        let renderer = ImageRenderer(content: thumb.padding(2).background(Color.black))
        renderer.scale = 3
        let image = try #require(renderer.cgImage, "ImageRenderer returned no image")
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        return try #require(png)
    }
}

// MARK: - The own layout card

struct OnboardingOwnLayoutTests {
    @Test func theOwnCardDrawsTheDisplaysPageWhileItIsOnNoTemplate() {
        var state = OnboardingState()
        state.nookPlacements = [NookWidgetPlacement(kind: .tray, size: .large)]

        #expect(state.ownLayoutPlacements == state.nookPlacements)
    }

    @Test func theOwnCardDrawsTheHeldPageWhileATemplateIsOn() {
        var state = OnboardingState()
        state.appliedTemplate = .study
        state.canKeepOwnLayout = true
        state.nookPlacements = PersonalizationTemplate.study.widgets
        state.ownPlacements = [NookWidgetPlacement(kind: .notes, size: .large)]

        #expect(state.ownLayoutPlacements == [NookWidgetPlacement(kind: .notes, size: .large)])
        state.ownPlacements = nil
        #expect(state.ownLayoutPlacements.map(\.kind) == NookDisplayPreferences().placements(enabled: NookWidgetKind.defaultEnabled).map(\.kind))
    }
}
