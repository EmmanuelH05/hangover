import Foundation
import Testing
@testable import OpenIslandApp

/// The preview stage's rules: what one moment of one setup shows.
@Suite struct PreviewSceneTests {
    private typealias Template = PersonalizationTemplate

    private static func setup(_ template: Template) -> PersonalizationSetup {
        PersonalizationSetup(appearance: template.appearance, nook: template.applying(to: NookDisplayPreferences()))
    }

    private static func scene(
        _ moment: PreviewMoment,
        _ template: Template,
        profile: IslandAppearanceDisplayProfile = .notch,
        flashToken: UInt64? = nil
    ) -> PreviewScene {
        PreviewScene.resolve(moment, setup: setup(template), profile: profile, policy: .full, flashToken: flashToken)
    }

    // MARK: Pages

    @Test func onlyTheTwoOpenMomentsOpenTheIsland() {
        for moment in PreviewMoment.allCases {
            let scene = Self.scene(moment, .cockpit)
            switch moment {
            case .openAgents: #expect(scene.page == .agents)
            case .openNook: #expect(scene.page == .nook)
            default: #expect(scene.page == nil, "\(moment)")
            }
            #expect(scene.halo.isOpened == (scene.page != nil), "\(moment)")
        }
    }

    @Test func theBarsFollowTheSetupAndThePage() {
        // The cockpit shows both bars; Minimal shows neither.
        #expect(Self.scene(.openNook, .cockpit).showsAgentsBar)
        #expect(!Self.scene(.openNook, .cockpit).showsCompactBar)
        #expect(Self.scene(.openAgents, .cockpit).showsCompactBar)
        #expect(!Self.scene(.openAgents, .cockpit).showsAgentsBar)
        #expect(!Self.scene(.openNook, .minimal).showsAgentsBar)
        #expect(!Self.scene(.openAgents, .minimal).showsCompactBar)
        #expect(!Self.scene(.working, .cockpit).showsAgentsBar)
    }

    // MARK: The closed island

    @Test func eachMomentPutsTheAgentsInTheRightState() {
        #expect(Self.scene(.idle, .cockpit).mode == .idle)
        #expect(Self.scene(.working, .cockpit).mode == .running)
        #expect(Self.scene(.approval, .cockpit).mode == .waiting)
        #expect(Self.scene(.finished, .cockpit).mode == .idle)
        #expect(Self.scene(.music, .cockpit).mode == .running)
    }

    @Test func musicAndNoticesShowOnlyWhereTheSetupLetsThem() {
        #expect(Self.scene(.music, .nowPlaying).activity == .music)
        #expect(Self.scene(.music, .cockpit).activity == .music)
        #expect(Self.scene(.music, .minimal).activity == nil)
        #expect(Self.scene(.notice, .focus).activity == .notice)
        #expect(Self.scene(.notice, .minimal).activity == nil)
        #expect(Self.scene(.working, .nowPlaying).activity == nil)
    }

    @Test func theCenterLabelShowsOnlyOnAnExternalDisplay() {
        #expect(Self.scene(.working, .cockpit, profile: .notch).label == nil)
        #expect(Self.scene(.working, .cockpit, profile: .topBar).label == .agentAction)
        #expect(Self.scene(.approval, .cockpit, profile: .topBar).label == .permissionNeeded)
        #expect(Self.scene(.idle, .cockpit, profile: .topBar).label == nil)
        // Now playing puts the track in the label; the planner shows the next event at rest.
        #expect(Self.scene(.music, .nowPlaying, profile: .topBar).label == .track)
        #expect(Self.scene(.idle, .planner, profile: .topBar).label == .nextEvent)
        // Focus turns the agent label off and still shows the next event.
        #expect(Self.scene(.working, .focus, profile: .topBar).label == nil)
        #expect(Self.scene(.idle, .focus, profile: .topBar).label == .nextEvent)
        // An opened island has no pill to label.
        #expect(Self.scene(.openAgents, .cockpit, profile: .topBar).label == nil)
    }

    // MARK: The glow

    @Test func theGlowIsFedWhatTheMomentHolds() {
        let approval = Self.scene(.approval, .cockpit)
        let finished = Self.scene(.finished, .cockpit, flashToken: 7)
        let working = Self.scene(.working, .cockpit)

        #expect(approval.halo.waiting == .approval)
        #expect(approval.halo.style == .vivid)
        #expect(finished.halo.flashToken == 7)
        #expect(working.halo.flashToken == nil)
        #expect(working.halo.isRunning)
        #expect(Self.scene(.approval, .cockpit, flashToken: 7).halo.flashToken == nil)
    }

    @Test func theGlowTakesTheAlbumColorOnlyWhenTheSetupFollowsMusic() {
        #expect(Self.scene(.music, .nowPlaying).halo.musicTint == PreviewSamples.musicTint)
        // The cockpit shows the art and keeps its own glow colors.
        #expect(Self.scene(.music, .cockpit).halo.musicTint == nil)
        #expect(Self.scene(.music, .minimal).halo.musicTint == nil)
        #expect(Self.scene(.notice, .focus).halo.noticeTint == PreviewSamples.noticeTint)
        #expect(Self.scene(.notice, .minimal).halo.noticeTint == nil)
    }

    @Test func theRealResolverTurnsTheSceneIntoTheRightGlow() {
        #expect(IslandHaloState.resolve(Self.scene(.approval, .cockpit).halo).source == .approval)
        #expect(IslandHaloState.resolve(Self.scene(.working, .cockpit).halo).source == .running)
        #expect(IslandHaloState.resolve(Self.scene(.music, .nowPlaying).halo).source == .music)
        #expect(IslandHaloState.resolve(Self.scene(.notice, .focus).halo).source == .notice)
        #expect(IslandHaloState.resolve(Self.scene(.finished, .planner, flashToken: 1).halo).source == .completed)
        #expect(!IslandHaloState.resolve(Self.scene(.idle, .cockpit).halo).isVisible)
        // Minimal has no glow at any moment.
        for moment in PreviewMoment.allCases {
            #expect(!IslandHaloState.resolve(Self.scene(moment, .minimal, flashToken: 1).halo).isVisible, "\(moment)")
        }
    }

    // MARK: Captions

    @Test func everyCaptionASetupCanProduceIsAKnownKey() {
        let known = Set(PreviewScene.allCaptionKeys)
        var produced = Set<String>()
        var styles: [NookDisplayPreferences] = []
        for template in Template.all {
            styles.append(Self.setup(template).nook)
        }
        // The templates do not cover every branch; these fill the rest.
        var quietNotice = NookDisplayPreferences()
        quietNotice.haloStyle = .off
        styles.append(quietNotice)
        var agentsFirst = NookDisplayPreferences()
        agentsFirst.openedPage = .agents
        styles.append(agentsFirst)

        for nook in styles {
            let setup = PersonalizationSetup(appearance: IslandAppearancePreferences(), nook: nook)
            for moment in PreviewMoment.allCases {
                let keys = PreviewScene.resolve(moment, setup: setup, profile: .notch, policy: .full).captionKeys
                #expect(!keys.isEmpty, "\(moment)")
                produced.formUnion(keys)
            }
        }

        #expect(produced.isSubset(of: known))
        #expect(produced == known, "unused or unreachable: \(known.subtracting(produced).sorted())")
    }

    @Test func aCaptionSaysWhenASetupShowsNothing() {
        let prefix = PreviewScene.captionPrefix

        #expect(Self.scene(.approval, .minimal).captionKeys == [prefix + "approval", prefix + "approval.noGlow"])
        #expect(Self.scene(.music, .minimal).captionKeys == [prefix + "music", prefix + "music.off"])
        #expect(Self.scene(.notice, .minimal).captionKeys == [prefix + "notice", prefix + "notice.off"])
        #expect(Self.scene(.finished, .minimal).captionKeys.last == prefix + "finished.noFlash")
        #expect(Self.scene(.approval, .cockpit).captionKeys.last == prefix + "approval.vivid")
        #expect(Self.scene(.music, .nowPlaying).captionKeys.last == prefix + "music.glow")
        #expect(Self.scene(.openNook, .cockpit).captionKeys.last == prefix + "openNook.opensOnAgents")
        #expect(Self.scene(.openAgents, .nowPlaying).captionKeys.contains(prefix + "openAgents.opensOnNook"))
    }

    // MARK: Storyboard

    @Test func theStoryboardShowsEveryMomentOnce() {
        let moments = PreviewStoryboard.steps.map(\.moment)

        #expect(Set(moments) == Set(PreviewMoment.allCases))
        #expect(moments.count == PreviewMoment.allCases.count)
        #expect(moments.first == .idle)
        #expect(moments.last == .openNook)
        for step in PreviewStoryboard.steps {
            #expect(step.seconds >= 2, "\(step.moment) is too short to read")
        }
        for moment in PreviewMoment.allCases {
            #expect(PreviewStoryboard.steps[PreviewStoryboard.index(of: moment)].moment == moment)
        }
    }

    @Test func thePlayButtonPausesPlaysOrReplays() {
        let count = PreviewStoryboard.steps.count

        #expect(PreviewStoryboard.control(isPlaying: true, stepIndex: 2) == .pause)
        #expect(PreviewStoryboard.control(isPlaying: false, stepIndex: 2) == .play)
        #expect(PreviewStoryboard.control(isPlaying: false, stepIndex: count) == .replay)
    }

    // MARK: Strings

    @Test func everyStageStringExistsInEveryLanguage() throws {
        let fixed = [
            "play", "pause", "replay", "close", "sample", "sampleTag", "emptyNook",
            "preview", "useTemplate", "seeInAction", "yourSetup",
        ].map { "settings.appearance.stage.\($0)" }
        let keys = fixed + PreviewMoment.allCases.map(\.titleKey) + PreviewScene.allCaptionKeys

        for language in ["en", "zh-Hans", "zh-Hant"] {
            let url = Self.repoRoot
                .appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String], "\(language) did not load")

            for key in keys {
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
