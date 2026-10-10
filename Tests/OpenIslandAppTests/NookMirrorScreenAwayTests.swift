import Foundation
import Testing
@testable import OpenIslandApp

/// The mirror, and with it a photo booth session, ends when the screen
/// sleeps or locks: no camera on, and no pictures, behind a lock screen.
@MainActor
@Suite struct NookMirrorScreenAwayTests {
    @Test func theMirrorGoesOffWhenTheScreenGoesAway() {
        let nook = NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
        nook.presentRingLight = { _ in }
        nook.isMirrorOn = true

        nook.screenWentAway()

        #expect(nook.isMirrorOn == false)
    }

    @Test func aMirrorThatIsOffStaysOff() {
        let nook = NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
        nook.presentRingLight = { _ in }

        nook.screenWentAway()

        #expect(nook.isMirrorOn == false)
    }

    @Test func steppingAStickersColorSurvivesADamagedSavedNumber() throws {
        let id = try #require(NookMirrorDesigns.stickerIDs.sorted().first)
        let design = try #require(NookMirrorDesigns.sticker(id))

        let stepped = design.wrapped(design.wrapped(Int.max) + 1)

        #expect(stepped >= 0)
        #expect(stepped == design.wrapped(stepped))
    }
}
