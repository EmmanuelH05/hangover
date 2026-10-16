import AVFoundation
import Foundation
import Testing
@testable import OpenIslandApp

/// What a session watch reported, from whichever thread posted.
final class SessionWatchLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [NookCaptureSessionWatch.Problem] = []
    func add(_ problem: NookCaptureSessionWatch.Problem) { lock.withLock { items.append(problem) } }
    var all: [NookCaptureSessionWatch.Problem] { lock.withLock { items } }
}

/// The watch listens to one `AVCaptureSession`. These sessions have no input
/// and are never started: nothing here opens a camera or a microphone, the
/// notifications are posted by hand.
@Suite struct NookRecordSessionWatchTests {
    @Test func aRuntimeErrorIsReportedOnce() {
        let session = AVCaptureSession()
        let log = SessionWatchLog()
        let watch = NookCaptureSessionWatch(session: session) { log.add($0) }
        defer { watch.stop() }

        NotificationCenter.default.post(name: AVCaptureSession.runtimeErrorNotification, object: session)
        NotificationCenter.default.post(name: AVCaptureSession.runtimeErrorNotification, object: session)
        NotificationCenter.default.post(name: AVCaptureSession.wasInterruptedNotification, object: session)

        #expect(log.all == [.runtimeError])
    }

    @Test func anInterruptionIsReported() {
        let session = AVCaptureSession()
        let log = SessionWatchLog()
        let watch = NookCaptureSessionWatch(session: session) { log.add($0) }
        defer { watch.stop() }

        NotificationCenter.default.post(name: AVCaptureSession.wasInterruptedNotification, object: session)

        #expect(log.all == [.interrupted])
    }

    @Test func anotherSessionsTroubleIsNotThisOnes() {
        let session = AVCaptureSession()
        let other = AVCaptureSession()
        let log = SessionWatchLog()
        let watch = NookCaptureSessionWatch(session: session) { log.add($0) }
        defer { watch.stop() }

        NotificationCenter.default.post(name: AVCaptureSession.runtimeErrorNotification, object: other)

        #expect(log.all.isEmpty)
    }

    @Test func aStoppedWatchSaysNothing() {
        let session = AVCaptureSession()
        let log = SessionWatchLog()
        let watch = NookCaptureSessionWatch(session: session) { log.add($0) }
        watch.stop()
        watch.stop()

        NotificationCenter.default.post(name: AVCaptureSession.runtimeErrorNotification, object: session)

        #expect(log.all.isEmpty)
    }
}

@Suite struct NookFaceCamProblemTests {
    @Test func deniedAndRestrictedAccessIsTheNoAccessProblem() {
        #expect(NookFaceCamRules.problem(for: .denied) == .noAccess)
        #expect(NookFaceCamRules.problem(for: .restricted) == .noAccess)
        #expect(NookFaceCamRules.problem(for: .authorized) == nil)
        // macOS has not been asked yet: the bubble asks, it is not a problem.
        #expect(NookFaceCamRules.problem(for: .notDetermined) == nil)
    }

    @Test func everyProblemHasItsOwnSentenceInEveryLanguage() throws {
        let problems: [NookFaceCamProblem] = [.noAccess, .noCamera, .cameraFailed, .stopped]
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let table = try NookRecordStringsTests.table(language)
            let sentences = problems.compactMap { table[$0.noticeKey] }
            #expect(sentences.count == problems.count, "\(language) is missing a face cam sentence")
            #expect(Set(sentences).count == problems.count, "\(language) repeats a face cam sentence")
            for sentence in sentences {
                #expect(!sentence.contains("\u{2014}") && !sentence.contains("\u{2013}"))
            }
        }
    }

    @Test func theNoAccessSentenceIsTheOneTheFixListWrote() throws {
        let en = try NookRecordStringsTests.table("en")
        #expect(en[NookFaceCamProblem.noAccess.noticeKey] == "Face cam is off: Hangover has no camera access. Turn it on in System Settings, Privacy & Security, Camera.")
    }
}
