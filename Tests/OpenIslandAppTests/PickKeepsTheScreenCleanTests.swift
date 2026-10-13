import Foundation
import Testing
@testable import OpenIslandApp

/// While the design kit's eyedropper is up, nothing of ours is drawn over
/// the screen: the glow and the lasers would be picked along with the color
/// under the loupe. Fakes only: no loupe, no window, no sound.
@MainActor
@Suite struct PickKeepsTheScreenCleanTests {
    private func model() -> (AppModel, FakeColorSampler) {
        let model = AppModel(defaults: MemoryDefaults())
        let sampler = FakeColorSampler()
        model.nook.design.activate(NookDesignServices(
            sampler: sampler,
            presenter: FakeReferencePresenter(),
            editor: FakeEditorPresenter(),
            pictureClipboard: FakePictureClipboard(),
            hotkeyRegistrar: FakeDesignHotkeyRegistrar(),
            linkOpener: FakeLinkOpener()
        ))
        model.nook.design.setLive(true)
        model.nook.updateDisplayPreferences(for: model.activeAppearanceProfile) {
            $0.haloStyle = .vivid
            $0.haloPulsesWithBeat = true
        }
        return (model, sampler)
    }

    @Test func theGlowAndTheLasersAreOffWhileAColorIsBeingPicked() {
        let (model, sampler) = model()
        defer { model.nook.timer.reset() }
        #expect(model.islandHaloInputs.style == .vivid)
        #expect(model.beatListeningInputs.style == .vivid)

        #expect(model.nook.design.pickColor(from: .shortcut))
        #expect(model.nook.design.isSampling)
        #expect(model.islandHaloInputs.style == .off)
        // The listening rule stops the tap, which takes the lasers' window
        // down with it.
        #expect(model.beatListeningInputs.style == .off)
        #expect(IslandBeatRules.decision(model.beatListeningInputs) == .stop)

        // The pick ends, by a color or by Escape, and the glow is back.
        sampler.finish(NookDesignColor(red: 10, green: 20, blue: 30))
        #expect(!model.nook.design.isSampling)
        #expect(model.islandHaloInputs.style == .vivid)
        #expect(model.beatListeningInputs.style == .vivid)
    }

    @Test func aCancelledPickBringsTheGlowBackToo() {
        let (model, sampler) = model()
        defer { model.nook.timer.reset() }

        #expect(model.nook.design.pickColor(from: .shortcut))
        #expect(model.islandHaloInputs.style == .off)
        sampler.finish(nil)
        #expect(model.islandHaloInputs.style == .vivid)
    }
}
