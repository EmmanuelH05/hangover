import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// A camera that takes no pictures. It hands back ones drawn in code, can
/// be told to fail, and can hold a picture back until a test lets it go.
final class FakeBoothCamera: NookPhotoBoothCamera, @unchecked Sendable {
    private let lock = NSLock()
    private var held: [CheckedContinuation<Void, Never>] = []
    private var isHolding = false
    private var storedCaptures = 0
    private var storedPrepares = 0
    private var storedError: NookPhotoBoothCameraError?
    private var storedReady = true

    @MainActor var isReady: Bool { lock.withLock { storedReady } }

    var captures: Int { lock.withLock { storedCaptures } }
    var prepares: Int { lock.withLock { storedPrepares } }

    func setReady(_ ready: Bool) { lock.withLock { storedReady = ready } }
    func fail(with error: NookPhotoBoothCameraError?) { lock.withLock { storedError = error } }

    /// From now on a picture waits until `release()`.
    func hold() { lock.withLock { isHolding = true } }

    func release() {
        let waiting = lock.withLock {
            isHolding = false
            let waiting = held
            held = []
            return waiting
        }
        waiting.forEach { $0.resume() }
    }

    func prepare() { lock.withLock { storedPrepares += 1 } }

    func captureStill() async throws -> NookPhotoBoothStill {
        let shot = lock.withLock {
            storedCaptures += 1
            return storedCaptures
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let waits = lock.withLock {
                if isHolding { held.append(continuation) }
                return isHolding
            }
            if !waits { continuation.resume() }
        }
        if let error = lock.withLock({ storedError }) { throw error }
        return NookPhotoBoothStill(image: PhotoBoothTestPictures.portrait(pose: shot, width: 640, height: 360))
    }
}

@MainActor
struct NookPhotoBoothModelTests {
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private final class Fixture {
        let booth: NookPhotoBoothModel
        let camera: FakeBoothCamera
        let clock: ManualClock
        let folder: URL
        let defaults: MemoryDefaults
        var sounds: [NookPhotoBoothSound] = []
        var mirrorOn = true

        @MainActor
        init() {
            let camera = FakeBoothCamera()
            let clock = ManualClock(NookPhotoBoothModelTests.start)
            let defaults = MemoryDefaults()
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("NookPhotoBoothTests-\(UUID().uuidString)", isDirectory: true)
            self.camera = camera
            self.clock = clock
            self.defaults = defaults
            self.folder = folder
            booth = NookPhotoBoothModel(
                defaults: defaults,
                camera: camera,
                // A retake deletes its strip here. The real Trash is never used.
                store: NookPhotoBoothStore(trash: { try FileManager.default.removeItem(at: $0) }),
                defaultFolder: folder,
                now: { clock.now },
                advancesItself: false
            )
            booth.isMirrorOn = { [unowned self] in self.mirrorOn }
            booth.play = { [unowned self] in self.sounds.append($0) }
            booth.defaultCaption = { _ in "default line" }
            booth.reveal = { _ in }
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: folder)
        }

        var savedFiles: [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        }

        /// Moves the clock and the booth one step.
        @MainActor
        func step(_ seconds: TimeInterval = 1.3) async {
            clock.advance(seconds)
            await booth.tick(at: clock.now)
        }

        /// Steps until the booth reaches a phase, or gives up.
        @MainActor
        func run(until isThere: (NookPhotoBoothModel) -> Bool) async {
            var turns = 0
            while !isThere(booth), turns < 400 {
                turns += 1
                await step()
            }
        }
    }

    // MARK: A whole session

    @Test func aSessionTakesFourPicturesAndSavesOneStrip() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let booth = fixture.booth
        #expect(booth.canStart)

        booth.start()
        #expect(booth.isRunning)
        #expect(booth.session?.phase == .getReady)
        let onePrepare = 1
        #expect(fixture.camera.prepares == onePrepare)

        await fixture.run { $0.result != nil || $0.failure != nil }

        let result = try #require(booth.result)
        let four = 4
        #expect(fixture.camera.captures == four)
        #expect(booth.pictures.count == four)
        #expect(booth.flashes == four)
        #expect(booth.session?.phase == .done)
        #expect(!booth.isRunning)
        #expect(booth.isShowing)

        #expect(fixture.savedFiles.count == 1)
        #expect(result.fileURL.deletingLastPathComponent().standardizedFileURL == fixture.folder.standardizedFileURL)
        let document = try #require(PDFDocument(url: result.fileURL))
        #expect(document.pageCount == 1)
        let layout = NookPhotoStripLayout.layout(.classic)
        #expect(document.page(at: 0)?.bounds(for: .mediaBox).size == layout.pageSize)
        #expect(result.pageSize == layout.pageSize)

        // Five numbers and a shutter for the first picture, three and a
        // shutter for each of the rest.
        let shutters = fixture.sounds.filter { $0 == .shutter }.count
        let lastTicks = fixture.sounds.filter { $0 == .lastTick }.count
        let ticks = fixture.sounds.filter { $0 == .tick }.count
        let expectedTicks = 4 + 3 * 2
        #expect(shutters == four)
        #expect(lastTicks == four)
        #expect(ticks == expectedTicks)
    }

    @Test func noPictureIsTakenBeforeItsCountdownHasRun() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.booth.countdown = 10
        fixture.booth.start()
        // One second to get ready brings up 10. Nine more bring up 9 to 1.
        // Ten steps, and no picture in any of them.
        for _ in 0..<10 {
            await fixture.step(1)
            #expect(fixture.camera.captures == 0)
        }
        #expect(fixture.booth.session?.phase == .countdown(shot: 1, number: 1))
        // The picture comes only once the 1 has had its second.
        await fixture.step(0.5)
        #expect(fixture.camera.captures == 0)
        await fixture.step(0.5)
        let one = 1
        #expect(fixture.camera.captures == one)
    }

    @Test func soundsStayOffWhenTheSettingIsOff() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.booth.playsSound = false
        fixture.booth.start()
        await fixture.run { $0.result != nil }
        #expect(fixture.sounds.isEmpty)
    }

    // MARK: Starting

    @Test func aSessionOnlyStartsWithTheMirrorOnAndACamera() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.mirrorOn = false
        fixture.booth.start()
        #expect(fixture.booth.session == nil)

        fixture.mirrorOn = true
        fixture.camera.setReady(false)
        fixture.booth.start()
        #expect(fixture.booth.session == nil)

        fixture.camera.setReady(true)
        fixture.booth.start()
        #expect(fixture.booth.session != nil)
        // A second press while one runs starts nothing new.
        let before = fixture.booth.session
        fixture.clock.advance(0.5)
        fixture.booth.start()
        #expect(fixture.booth.session == before)
    }

    @Test func aSessionKeepsTheSettingsItStartedWith() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.booth.layoutKind = .grid
        fixture.booth.start()
        fixture.booth.layoutKind = .caption
        await fixture.run { $0.result != nil }
        let result = try #require(fixture.booth.result)
        #expect(result.pageSize == NookPhotoStripLayout.layout(.grid).pageSize)
    }

    // MARK: Throwing a session away

    @Test func cancelAtEveryQuietStepLeavesNothingBehind() async {
        let stops: [(String, (NookPhotoBoothPhase) -> Bool)] = [
            ("get ready", { $0 == .getReady }),
            ("first countdown", { if case .countdown(1, 2) = $0 { true } else { false } }),
            ("looking at a picture", { $0 == .preview(shot: 1) }),
            ("next pose", { $0 == .nextPose(shot: 2) }),
            ("later countdown", { if case .countdown(3, _) = $0 { true } else { false } }),
            ("last picture", { $0 == .preview(shot: 4) }),
        ]
        for (name, isThere) in stops {
            let fixture = Fixture()
            defer { fixture.cleanUp() }
            fixture.booth.start()
            await fixture.run { booth in booth.session.map { isThere($0.phase) } ?? true }
            #expect(fixture.booth.session != nil, "\(name): the session ended before the stop")
            let takenBefore = fixture.camera.captures

            fixture.booth.cancel()

            #expect(fixture.booth.session == nil, "\(name)")
            #expect(fixture.booth.pictures.isEmpty, "\(name)")
            #expect(!fixture.booth.isShowing, "\(name)")
            // Time going on does nothing more: no picture, no strip.
            for _ in 0..<40 { await fixture.step() }
            #expect(fixture.camera.captures == takenBefore, "\(name)")
            #expect(fixture.booth.result == nil, "\(name)")
            #expect(fixture.savedFiles.isEmpty, "\(name)")
        }
    }

    @Test func cancelWhileThePictureIsOnItsWayDropsThatPicture() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let booth = fixture.booth
        booth.start()
        await fixture.run { booth in
            if case .countdown(1, 1) = booth.session?.phase { true } else { false }
        }
        fixture.camera.hold()
        fixture.clock.advance(1.3)
        let now = fixture.clock.now
        let taking = Task { await booth.tick(at: now) }
        var waits = 0
        while fixture.camera.captures == 0, waits < 1000 {
            waits += 1
            await Task.yield()
        }
        #expect(booth.session?.phase == .capturing(shot: 1))

        booth.cancel()
        fixture.camera.release()
        await taking.value

        #expect(booth.session == nil)
        #expect(booth.pictures.isEmpty)
        #expect(booth.failure == nil)
        #expect(fixture.savedFiles.isEmpty)
    }

    @Test func cancelWhileTheStripPrintsKeepsNoFile() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let booth = fixture.booth
        booth.start()
        await fixture.run { $0.session?.phase == .preview(shot: 4) }
        fixture.clock.advance(1.3)
        let now = fixture.clock.now
        let printing = Task { await booth.tick(at: now) }
        var waits = 0
        while booth.session?.phase != .composing, waits < 1000 {
            waits += 1
            await Task.yield()
        }
        #expect(booth.session?.phase == .composing)

        booth.cancel()
        await printing.value

        #expect(booth.result == nil)
        #expect(booth.session == nil)
        #expect(fixture.savedFiles.isEmpty)
    }

    @Test func turningTheMirrorOffThrowsTheSessionAway() {
        // The x, closing the island, leaving the page and removing the
        // tile all turn the mirror off, and that is the one hook.
        let nook = NookModel()
        nook.presentRingLight = { _ in }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NookPhotoBoothTests-\(UUID().uuidString)", isDirectory: true)
        let booth = nook.photoBooth
        booth.camera = FakeBoothCamera()
        booth.defaultFolder = folder
        booth.advancesItself = false
        booth.attach(nook: nook)
        booth.play = { _ in }

        #expect(!booth.canStart)
        nook.isMirrorOn = true
        booth.start()
        #expect(booth.session != nil)

        nook.isMirrorOn = false
        #expect(booth.session == nil)
        #expect(!booth.isShowing)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    // MARK: When something goes wrong

    @Test func aCameraThatGivesNothingEndsTheSessionWithAnError() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.camera.fail(with: .timedOut)
        fixture.booth.start()
        await fixture.run { $0.failure != nil || $0.result != nil }
        #expect(fixture.booth.failure == .camera)
        #expect(fixture.booth.session == nil)
        #expect(fixture.booth.result == nil)
        #expect(fixture.savedFiles.isEmpty)
        // The error is on screen, and the button cannot start over it.
        #expect(fixture.booth.isShowing)
        #expect(!fixture.booth.canStart)
        fixture.booth.cancel()
        #expect(fixture.booth.canStart)
    }

    @Test func aFolderThatCannotBeWrittenEndsWithASaveError() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        // A file where the folder should be.
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("NookPhotoBoothTests-blocker-\(UUID().uuidString)")
        try Data("x".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        fixture.booth.folderPath = blocker.appendingPathComponent("inside").path
        fixture.booth.start()
        await fixture.run { $0.failure != nil || $0.result != nil }
        #expect(fixture.booth.failure == .save)
        #expect(fixture.booth.result == nil)
    }

    @Test func aFailedSaveKeepsThePicturesAndSavesThemAgain() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        // A file where the folder should be.
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("NookPhotoBoothTests-blocker-\(UUID().uuidString)")
        try Data("x".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        fixture.booth.folderPath = blocker.appendingPathComponent("inside").path
        fixture.booth.start()
        await fixture.run { $0.failure != nil || $0.result != nil }
        #expect(fixture.booth.failure == .save)
        #expect(fixture.booth.unsavedStrip != nil)

        // Still blocked: the error and the pictures both stay.
        await fixture.booth.saveAgain()
        #expect(fixture.booth.failure == .save)
        #expect(fixture.booth.unsavedStrip != nil)

        // A folder that works: the same pictures are written, with no new session.
        fixture.booth.folderPath = fixture.folder.path
        await fixture.booth.saveAgain()
        #expect(fixture.booth.failure == nil)
        #expect(fixture.booth.unsavedStrip == nil)
        #expect(fixture.booth.session == nil)
        let saved = try #require(fixture.booth.result?.fileURL)
        #expect(FileManager.default.fileExists(atPath: saved.path))

        fixture.booth.cancel()
        #expect(fixture.booth.result == nil)
        #expect(fixture.booth.canStart)
    }

    // MARK: After the strip

    @Test func retakeBinsTheStripAndStartsOver() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let booth = fixture.booth
        booth.start()
        await fixture.run { $0.result != nil }
        let first = try #require(booth.result).fileURL
        #expect(FileManager.default.fileExists(atPath: first.path))

        booth.retake()

        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(booth.result == nil)
        #expect(booth.session?.phase == .getReady)
        #expect(fixture.savedFiles.isEmpty)
    }

    @Test func doneKeepsTheFileAndClearsTheMirror() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let booth = fixture.booth
        booth.start()
        await fixture.run { $0.result != nil }
        let file = try #require(booth.result).fileURL

        booth.finish()

        #expect(!booth.isShowing)
        #expect(booth.canStart)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func twoSessionsInTheSameSecondKeepBothStrips() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let booth = fixture.booth
        booth.start()
        await fixture.run { $0.result != nil }
        let first = try #require(booth.result).fileURL
        booth.finish()

        // The same clock reading again, as a quick second go would give.
        let again = NookPhotoBoothStore()
        let second = try again.save(Data("second".utf8), into: fixture.folder, at: fixture.clock.now)
        #expect(second != first)
        #expect(second.lastPathComponent.hasSuffix(" 2.pdf"))
        #expect(fixture.savedFiles.count == 2)
    }

    @Test func revealShowsTheSavedStrip() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        var revealed: [URL] = []
        fixture.booth.reveal = { revealed.append($0) }
        fixture.booth.revealInFinder()
        #expect(revealed.isEmpty)
        fixture.booth.start()
        await fixture.run { $0.result != nil }
        fixture.booth.revealInFinder()
        #expect(revealed == [try #require(fixture.booth.result).fileURL])
    }

    // MARK: Caption and settings

    @Test func anEmptyCaptionPrintsTheThemesOwnLine() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        var asked: [String] = []
        fixture.booth.defaultCaption = { theme in
            asked.append(theme.id)
            return "default line"
        }
        fixture.booth.caption = "   "
        fixture.booth.themeID = "film"
        fixture.booth.start()
        #expect(asked == ["film"])

        fixture.booth.cancel()
        fixture.booth.caption = "Our night"
        fixture.booth.start()
        #expect(asked == ["film"])
    }

    @Test func settingsAreSavedAndReadBack() {
        let defaults = MemoryDefaults()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("unused-\(UUID().uuidString)")
        func make() -> NookPhotoBoothModel {
            NookPhotoBoothModel(defaults: defaults, camera: FakeBoothCamera(), defaultFolder: folder, advancesItself: false)
        }
        let first = make()
        #expect(first.layoutKind == .classic)
        #expect(first.themeID == NookPhotoStripTheme.defaultID)
        #expect(first.caption.isEmpty)
        #expect(first.countdown == NookPhotoBoothPlan.defaultCountdown)
        #expect(first.playsSound)
        #expect(first.folderPath == nil)
        #expect(first.folderURL == folder)
        #expect(defaults.all.isEmpty)

        first.layoutKind = .grid
        first.themeID = "arcade"
        first.caption = "Hello"
        first.countdown = 10
        first.playsSound = false
        first.folderPath = "/tmp/strips"

        let second = make()
        #expect(second.layoutKind == .grid)
        #expect(second.themeID == "arcade")
        #expect(second.caption == "Hello")
        let ten = 10
        #expect(second.countdown == ten)
        #expect(!second.playsSound)
        #expect(second.folderURL.path == "/tmp/strips")

        second.useDefaultFolder()
        #expect(make().folderPath == nil)
    }

    @Test func savedValuesThisBuildDoesNotKnowFallBack() {
        let defaults = MemoryDefaults()
        defaults.set("hologram", forKey: NookPhotoBoothModel.themeKey)
        defaults.set("poster", forKey: NookPhotoBoothModel.layoutKey)
        defaults.set(7, forKey: NookPhotoBoothModel.countdownKey)
        let booth = NookPhotoBoothModel(
            defaults: defaults,
            camera: FakeBoothCamera(),
            defaultFolder: FileManager.default.temporaryDirectory,
            advancesItself: false
        )
        #expect(booth.themeID == NookPhotoStripTheme.defaultID)
        #expect(booth.layoutKind == NookPhotoStripLayout.defaultKind)
        #expect(booth.countdown == NookPhotoBoothPlan.defaultCountdown)
    }

    @Test func noLinkFromAnotherAppReachesTheBooth() {
        // Another app must not be able to take pictures, under either scheme.
        for scheme in IslandURLAction.acceptedSchemes.sorted() {
            for words in ["photobooth", "photobooth/start", "mirror/photo", "booth"] {
                let text = "\(scheme)://\(words)"
                let url = URL(string: text)!
                if case .success = IslandURLAction.parse(url) {
                    Issue.record("\(text) was taken as an action")
                }
            }
        }
    }
}
