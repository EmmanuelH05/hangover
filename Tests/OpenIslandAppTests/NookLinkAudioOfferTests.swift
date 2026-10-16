import AppKit
import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

// Link to MP3 is only in the dev copy. With the build not offering it (the
// release app) the widget does not exist for the user: it cannot be switched
// on, a saved setting loads without it, its service never starts or looks for
// the two programs, and no list a user sees holds it. With the build offering
// it (the dev copy, and the test runner, which has no bundle identifier) every
// other test in the suite holds as it always did. Nothing here shows a window,
// reaches the Mac or writes the real settings.

/// Runs `body` as the release app would see the world.
@MainActor
private func withoutLinkAudio<R>(_ body: @MainActor () throws -> R) rethrows -> R {
    try NookLinkAudioOffer.$override.withValue(false) { try body() }
}

// MARK: - The rule

struct NookLinkAudioOfferRuleTests {
    @Test func theDevCopyOffersItAndTheReleaseAppAndEveryOtherAppDoNot() {
        #expect(NookLinkAudioOffer.isOffered(bundleID: "app.openisland.dev"))
        #expect(!NookLinkAudioOffer.isOffered(bundleID: "com.emmanuelhernandez.hangover"))
        for other in ["app.openisland.dev.links", "app.openisland", "com.example.other", "", "APP.OPENISLAND.DEV"] {
            #expect(!NookLinkAudioOffer.isOffered(bundleID: other), "\(other)")
        }
    }

    /// The test runner has no bundle identifier. It falls back to the dev id,
    /// the way the token files and the Keychain do, which keeps the tests on
    /// the offered side.
    @Test func noBundleIdentifierFallsBackToTheDevIdAndIsOffered() {
        #expect(NookLinkAudioOffer.devBundleID == NookTodoTokenFile.fallbackBundleID)
        #expect(NookLinkAudioOffer.isOffered(bundleID: nil))
        #expect(NookLinkAudioOffer.isOffered, "the suite runs on the offered side")
    }

    @Test func aTestCanSeeTheOtherSideAndOnlyInsideItsOwnScope() {
        NookLinkAudioOffer.$override.withValue(false) {
            #expect(!NookLinkAudioOffer.isOffered)
            #expect(!NookWidgetKind.linkAudio.isOffered)
            #expect(NookWidgetKind.design.isOffered)
            #expect(NookWidgetKind.offered.count == NookWidgetKind.allCases.count - 1)
            #expect(!NookWidgetKind.offered.contains(.linkAudio))
        }
        #expect(NookLinkAudioOffer.isOffered)
        #expect(NookWidgetKind.offered == NookWidgetKind.allCases)
    }

    /// Release builds are packaged with the release id by default.
    @Test func thePackagingScriptsDefaultIsTheReleaseIdAndTheDevScriptsIsTheDevId() throws {
        let package = try HangoverBrandTests.text(of: "scripts/package-app.sh")
        #expect(package.contains("com.emmanuelhernandez.hangover"))
        #expect(!NookLinkAudioOffer.isOffered(bundleID: "com.emmanuelhernandez.hangover"))
        let dev = try HangoverBrandTests.text(of: "scripts/launch-dev-app.sh")
        #expect(dev.contains("<string>\(NookLinkAudioOffer.devBundleID)</string>"))
    }
}

// MARK: - The model

@MainActor
struct NookLinkAudioOfferModelTests {
    private static let key = "nook.enabledWidgets"

    @Test func theModelRefusesToSwitchItOnAndEveryDoorIntoItIsShut() {
        withoutLinkAudio {
            let nook = NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
            nook.activeProfile = { .notch }

            nook.setWidget(.linkAudio, enabled: true)
            #expect(!nook.isWidgetEnabled(.linkAudio))
            nook.setWidgetFromSettings(.linkAudio, enabled: true)
            #expect(!nook.isWidgetEnabled(.linkAudio))
            nook.addWidget(.linkAudio, for: .notch)
            #expect(!nook.widgetPlacements(for: .notch).map(\.kind).contains(.linkAudio))

            // The others are switched on the way they always were.
            nook.setWidgetFromSettings(.design, enabled: true)
            #expect(nook.isWidgetEnabled(.design))
        }
    }

    @Test func theLayoutEditorsAddListLeavesItOut() {
        withoutLinkAudio {
            let nook = NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
            let addable = nook.addableWidgets(for: .notch)
            #expect(!addable.contains(.linkAudio))
            #expect(addable.contains(.mirror) && addable.contains(.design))
        }
        let nook = NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
        #expect(nook.addableWidgets(for: .notch).contains(.linkAudio), "offered, it is on the list as before")
    }

    @Test func aSavedSettingThatHasItOnLoadsWithoutIt() {
        let defaults = MemoryDefaults()
        defaults.set(["media", "linkAudio", "design", "notes"], forKey: Self.key)

        let release = withoutLinkAudio { NookModel(defaults: defaults, looksForImportedGIF: false) }
        #expect(release.enabledWidgets == [.media, .design, .notes])

        let dev = NookModel(defaults: defaults, looksForImportedGIF: false)
        #expect(dev.enabledWidgets == [.media, .linkAudio, .design, .notes], "the dev copy keeps it")
    }

    @Test func aSavedLayoutThatPlacesItLoadsWithoutIt() {
        let defaults = MemoryDefaults()
        let before = NookModel(defaults: defaults, looksForImportedGIF: false)
        before.setWidget(.linkAudio, enabled: true)
        before.updateDisplayPreferences(for: .notch) {
            $0.widgetOrder = [.linkAudio] + NookWidgetKind.allCases.filter { $0 != .linkAudio }
        }
        #expect(before.widgetPlacements(for: .notch).first?.kind == .linkAudio)

        withoutLinkAudio {
            let after = NookModel(defaults: defaults, looksForImportedGIF: false)
            #expect(!after.widgetPlacements(for: .notch).map(\.kind).contains(.linkAudio))
            #expect(!after.widgetPlacements(for: .topBar).map(\.kind).contains(.linkAudio))
            #expect(after.widgetPlacements(for: .notch).first?.kind == .media)
        }
    }

    /// Whatever service is handed to the model, the release app's model uses
    /// one that finds no program and runs none, and never starts it.
    @Test func theServiceIsNeverStartedAndNeverLooksForTheTwoPrograms() {
        final class Looks: @unchecked Sendable { var count = 0 }
        let looks = Looks()
        let handed = NookLinkAudioService(
            defaults: MemoryDefaults(),
            folder: FileManager.default.temporaryDirectory.appendingPathComponent("offer-\(UUID().uuidString)"),
            runner: FakeLinkAudioRunner(),
            files: FakeLinkAudioFiles(),
            clipboard: FakeLinkAudioClipboard(),
            isExecutable: { _ in looks.count += 1; return true },
            showInFinder: { _ in },
            notifications: NotificationCenter()
        )
        let lookedAtCreation = looks.count

        withoutLinkAudio {
            let nook = NookModel(linkAudio: handed, defaults: MemoryDefaults(), looksForImportedGIF: false)
            #expect(!nook.offersLinkAudio)
            #expect(nook.linkAudio !== handed)
            #expect(nook.linkAudio.runner is NookLinkAudioRefusingRunner)

            nook.startLinkAudioIfOffered()
            nook.setWidget(.linkAudio, enabled: true)
            nook.setWidgetFromSettings(.linkAudio, enabled: true)
            nook.linkAudio.refreshTools()

            #expect(nook.linkAudio.nook == nil, "never started")
            #expect(nook.linkAudio.toolStatus.tools == nil, "it finds no program")
            #expect(looks.count == lookedAtCreation, "the service that was handed in was never asked about a program")
        }

        // Offered, the handed service is the one used, and it starts.
        let dev = NookModel(linkAudio: handed, defaults: MemoryDefaults(), looksForImportedGIF: false)
        #expect(dev.offersLinkAudio && dev.linkAudio === handed)
        dev.startLinkAudioIfOffered()
        #expect(dev.linkAudio.nook === dev)
        #expect(looks.count > lookedAtCreation, "it looked, as it always did")
    }

    /// The tour's switch for the widget is Settings' door, which is shut too.
    @Test func theTourCannotSwitchItOnEither() {
        withoutLinkAudio {
            let nook = NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
            let model = AppModel(agentsDefaults: MemoryDefaults(), defaults: MemoryDefaults(), nookModel: nook)
            nook.activeProfile = { [weak model] in model?.activeAppearanceProfile ?? .topBar }
            let tour = model.makeWelcomeTour(startingAt: .widgets)

            tour.actions.setWidget(.linkAudio, true)

            #expect(!nook.isWidgetEnabled(.linkAudio))
            #expect(tour.picks.tools.isEmpty, "not a tool the tour offers, and not one it keeps")
            #expect(!model.onboardingState.showsWidget(.linkAudio))
        }
    }
}

// MARK: - The tour

@MainActor
struct NookLinkAudioOfferTourTests {
    private static func everythingOn() -> OnboardingState {
        var state = OnboardingState()
        state.length = .medium
        state.enabledWidgets = Set(NookWidgetKind.allCases)
        state.nookPlacements = NookWidgetKind.allCases.map { NookWidgetPlacement(kind: $0, size: .medium) }
        return state
    }

    @Test func theWidgetsPageListsTenAndTheWalkEndsOnTheDesignKit() {
        withoutLinkAudio {
            let state = Self.everythingOn()
            #expect(NookWidgetKind.offered.count == 10)
            #expect(!state.shownPlacements.contains { $0.kind == .linkAudio })
            #expect(!state.ownLayoutPlacements.contains { $0.kind == .linkAudio })
            #expect(!state.showsWidget(.linkAudio))

            #expect(OnboardingFeatureWalk.everyKind.count == 10)
            #expect(state.featureWalk.kinds.last == .design)
            #expect(!state.featureWalk.kinds.contains(.linkAudio))
            #expect(NookWidgetKind.tools == [.record, .design])
            #expect(NookWidgetKind.startsOff == [.mirror, .weather, .record, .design])
        }
    }

    @Test func theSummaryAndTheLayoutCardsDoNotNameItEvenForAStateThatHasItOn() {
        withoutLinkAudio {
            var state = Self.everythingOn()
            state.nookPlacements = nil
            state.enabledWidgets = Set(NookWidgetKind.allCases)
            #expect(!state.shownPlacements.contains { $0.kind == .linkAudio })
            let template = PersonalizationTemplate.all[0]
            #expect(!OnboardingLayoutPage.page(of: template, keeping: state).contains { $0.kind == .linkAudio })
        }
    }

    @Test func aLayoutPickedInTheTourNeverBringsItBack() {
        withoutLinkAudio {
            let nook = NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
            let model = AppModel(agentsDefaults: MemoryDefaults(), defaults: MemoryDefaults(), nookModel: nook)
            nook.activeProfile = { [weak model] in model?.activeAppearanceProfile ?? .topBar }
            let tour = model.makeWelcomeTour(startingAt: .layout)
            tour.actions.setWidget(.design, true)

            tour.actions.applyTemplate(PersonalizationTemplate.all[0])

            let page = nook.widgetPlacements(for: model.activeAppearanceProfile).map(\.kind)
            #expect(page.contains(.design) && !page.contains(.linkAudio))
            #expect(tour.state.featureWalk.kinds.last == .design)
        }
    }

    @Test func theWidgetsPageDrawsTenRowsWhereElevenWereDrawn() throws {
        func png(_ state: OnboardingState) throws -> Data {
            let view = OnboardingView(tour: OnboardingTour(startingAt: .widgets, state: { state }), lang: LanguageManager.shared)
                .frame(width: 320, height: OnboardingWindowFrame.narrowMaxHeight)
            let renderer = ImageRenderer(content: view.environment(\.nookDrawsStill, true))
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            return try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        }
        var state = OnboardingState()
        state.length = .short
        state.enabledWidgets = Set(NookWidgetKind.defaultEnabled)
        let offered = try png(state)
        let hidden = try withoutLinkAudio { try png(state) }
        #expect(offered != hidden)
    }

    /// No string the tour shows with the build not offering the widget says
    /// MP3, yt-dlp or ffmpeg, and its footnotes name four widgets.
    @Test(arguments: HangoverBrandTests.languages)
    func theFootnotesNameFourWidgetsAndSayNothingAboutTheWidgetThatIsNotThere(language: String) throws {
        let table = try HangoverBrandTests.table(language)
        withoutLinkAudio {
            #expect(OnboardingWidgetsPage.footnoteKey == "onboarding.widgets.note.release")
            #expect(OnboardingFeaturesPage.footnoteKey == "onboarding.features.note.release")
        }
        #expect(OnboardingWidgetsPage.footnoteKey == "onboarding.widgets.note", "offered, the footnote is what it was")

        let widgets = try #require(table["onboarding.widgets.note.release"])
        for kind: NookWidgetKind in [.mirror, .weather, .record, .design] {
            let name = try #require(table["onboarding.nook.widget.\(kind.rawValue)"])
            #expect(widgets.contains(name), "\(language): \(name)")
        }
        let features = try #require(table["onboarding.features.note.release"])
        let design = try #require(table["onboarding.nook.widget.design"])
        #expect(features.lowercased().contains(design.lowercased()) || language != "en")
        // The note says Record goes off again, and that the tour never starts a recording.
        let record = try #require(table["onboarding.nook.widget.record"])
        #expect(features.lowercased().contains(record.lowercased()), "\(language): \(features)")
        for text in [widgets, features] { #expect(Self.mentionsTheWidget(text) == false, "\(language): \(text)") }
    }

    static func mentionsTheWidget(_ text: String) -> Bool {
        text.range(of: "mp3|yt-dlp|ffmpeg", options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Every string that mentions the widget, in every language, belongs to
    /// the widget itself or to the tour text that is only used where it is
    /// offered. A new string that mentions it somewhere else fails here.
    @Test(arguments: HangoverBrandTests.languages)
    func everyStringThatMentionsItIsReachedOnlyThroughTheWidgetOrTheOfferedTourText(language: String) throws {
        let table = try HangoverBrandTests.table(language)
        let onlyWhereOffered: Set<String> = [
            "onboarding.widgets.note", "onboarding.features.note",
        ]
        for (key, value) in table where Self.mentionsTheWidget(value) {
            let isTheWidgets = key.hasPrefix("nook.linkAudio.")
                || key.hasPrefix("onboarding.nook.widget.linkAudio")
                || key.hasPrefix("onboarding.widgets.linkAudio")
                || key.hasPrefix("onboarding.feature.linkAudio")
                || key.hasPrefix("onboarding.features.try.linkAudio")
            #expect(isTheWidgets || onlyWhereOffered.contains(key), "\(language) \(key): \(value)")
        }
    }
}

// MARK: - The lists

struct NookLinkAudioOfferListsTests {
    /// A list of widgets for the user reads `NookWidgetKind.offered`. These
    /// are the files that still walk every case, none of which the user sees:
    /// the order a display saves, the hidden set a layout writes, the order
    /// widgets switch on in, the layout reset and the macOS access pass.
    @Test func noFileThatShowsAListWalksEveryWidgetCase() throws {
        let allowed: Set<String> = [
            "NookModel.swift", "NookModel+Layout.swift", "NookDisplayPreferences.swift",
            "PersonalizationTemplate.swift", "NookLinkAudioOffer.swift",
        ]
        let root = HangoverBrandTests.repoRoot.appendingPathComponent("Sources/OpenIslandApp", isDirectory: true)
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            if source.contains("NookWidgetKind.allCases"), !allowed.contains(url.lastPathComponent) {
                offenders.append(url.lastPathComponent)
            }
        }
        #expect(offenders.isEmpty, "walk NookWidgetKind.offered instead: \(offenders)")
    }

    /// The Settings pane's switches and its section for the widget, the
    /// tour's page and the editor's list all read the one gate.
    @Test func theSettingsPaneTheTourPageAndTheEditorReadTheGate() throws {
        let pane = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Nook/Views/NookSettingsPane.swift")
        #expect(pane.contains("ForEach(NookWidgetKind.offered)"))
        #expect(pane.contains("if nook.offersLinkAudio { NookLinkAudioSettings(nook: nook) }"))
        let page = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Onboarding/OnboardingNookPages.swift")
        #expect(page.contains("NookWidgetKind.offered.enumerated()"))
        let layout = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Nook/NookModel+Layout.swift")
        #expect(layout.contains("NookWidgetKind.offered.filter { !shown.contains($0) }"))
    }
}
