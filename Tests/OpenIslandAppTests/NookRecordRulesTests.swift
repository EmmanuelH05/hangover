import CoreGraphics
import Foundation
import ScreenCaptureKit
import Testing
@testable import OpenIslandApp

@Suite struct NookRecordRulesTests {
    @Test func standardShrinksARetinaScreenTo1920Wide() {
        let size = NookRecordRules.outputSize(source: CGSize(width: 3024, height: 1964), quality: .standard)
        #expect(size.width == 1920)
        #expect(size.height == 1246)
    }

    @Test func highKeepsTheScreenSize() {
        let size = NookRecordRules.outputSize(source: CGSize(width: 3024, height: 1964), quality: .high)
        #expect(size.width == 3024)
        #expect(size.height == 1964)
    }

    @Test func aSmallAreaIsNeverMadeBiggerAndStaysEven() {
        let size = NookRecordRules.outputSize(source: CGSize(width: 641, height: 359), quality: .standard)
        #expect(size.width == 640)
        #expect(size.height == 358)
    }

    @Test func aTinyAreaStillHasTwoPixels() {
        let size = NookRecordRules.outputSize(source: CGSize(width: 1, height: 1), quality: .standard)
        #expect(size.width == 2)
        #expect(size.height == 2)
    }

    @Test func theNotchIsRecordedUnlessTheSettingIsOff() {
        let island: [CGWindowID] = [11, 12]
        #expect(NookRecordRules.excludedWindows(island: island, includeIsland: true).isEmpty)
        #expect(NookRecordRules.excludedWindows(island: island, includeIsland: false) == island)
    }

    @Test func recordingStopsUnderOneGigabyteFree() {
        #expect(NookRecordRules.shouldStopForSpace(freeBytes: 999_999_999))
        #expect(!NookRecordRules.shouldStopForSpace(freeBytes: 1_000_000_000))
        #expect(!NookRecordRules.shouldStopForSpace(freeBytes: nil))
    }

    // MARK: What happens after the file is closed (R1)

    @Test func aCancelWithNoPictureIsNotAFailure() {
        let url = URL(fileURLWithPath: "/tmp/a.mp4")
        #expect(NookRecordRules.phaseAfterFinish(fileURL: url, cause: .user, finishSucceeded: false, videoFramesWritten: 0) == .idle)
    }

    @Test func noPictureFromTheStreamNamesWhatHappened() {
        let url = URL(fileURLWithPath: "/tmp/a.mp4")
        for cause in [NookRecordStopCause.noPicture, .system] {
            #expect(NookRecordRules.phaseAfterFinish(fileURL: url, cause: cause, finishSucceeded: false, videoFramesWritten: 0) == .failed(.noPicture))
        }
        #expect(NookRecordRules.phaseAfterFinish(fileURL: url, cause: .lowDisk, finishSucceeded: false, videoFramesWritten: 0) == .failed(.lowDisk))
    }

    @Test func aFileWithPicturesIsKeptWhateverEndedIt() {
        let url = URL(fileURLWithPath: "/tmp/a.mp4")
        #expect(NookRecordRules.phaseAfterFinish(fileURL: url, cause: .user, finishSucceeded: true, videoFramesWritten: 5) == .finished(url, endedBy: .user))
        #expect(NookRecordRules.phaseAfterFinish(fileURL: url, cause: .lowDisk, finishSucceeded: true, videoFramesWritten: 5) == .finished(url, endedBy: .lowDisk))
        #expect(NookRecordRules.phaseAfterFinish(fileURL: url, cause: .user, finishSucceeded: false, videoFramesWritten: 5, secondsWritten: 3) == .failed(.writerFailed(atSeconds: 3)))
    }

    @Test func aWriterThatFailedNamesTheTimeItStoppedAt() {
        let url = URL(fileURLWithPath: "/tmp/a.mp4")
        for finished in [true, false] {
            for frames in [0, 40] {
                #expect(NookRecordRules.phaseAfterFinish(fileURL: url, cause: .writeError, finishSucceeded: finished, videoFramesWritten: frames, secondsWritten: 760) == .failed(.writerFailed(atSeconds: 760)))
            }
        }
    }

    @Test func theFirstFrameGetsFiveSeconds() {
        #expect(NookRecordRules.firstFrameDeadline == .seconds(5))
    }
}

/// The recorder with nothing running. No test starts a real capture.
@MainActor @Suite struct NookScreenRecorderIdleTests {
    @Test func pauseResumeAndStopDoNothingWithoutARecording() async {
        let recorder = NookScreenRecorder()
        var phases: [NookRecordPhase] = []
        recorder.onPhaseChange = { phases.append($0) }
        recorder.pause()
        recorder.resume()
        await recorder.stop()
        #expect(phases.isEmpty)
    }
}

// MARK: - Errors (R4)

@Suite struct NookRecordErrorRulesTests {
    @Test func theStreamsOwnErrorsKeepTheirFixAndEveryOtherOneIsCouldNotStart() {
        let domain = SCStreamErrorDomain
        #expect(NookRecordRules.startFailure(domain: domain, code: SCStreamError.userDeclined.rawValue) == .screenPermissionDenied)
        #expect(NookRecordRules.startFailure(domain: domain, code: SCStreamError.noDisplayList.rawValue) == .noDisplay)
        #expect(NookRecordRules.startFailure(domain: domain, code: SCStreamError.noWindowList.rawValue) == .noDisplay)
        #expect(NookRecordRules.startFailure(domain: domain, code: SCStreamError.failedToStart.rawValue) == .couldNotStart)
        // Not "could not be saved": nothing was being saved yet.
        #expect(NookRecordRules.startFailure(domain: "NSCocoaErrorDomain", code: 4) == .couldNotStart)
    }

    @Test func aLoggedErrorCarriesItsDomainAndCodeAndTheOneUnderneath() {
        let underlying = NSError(domain: NSOSStatusErrorDomain, code: -16341)
        let error = NSError(domain: "AVFoundationErrorDomain", code: -11800, userInfo: [NSUnderlyingErrorKey: underlying])
        #expect(NookRecordRules.describe(error) == "AVFoundationErrorDomain -11800 (NSOSStatusErrorDomain -16341)")
        #expect(NookRecordRules.describe(NSError(domain: "X", code: 7)) == "X 7")
    }
}

// MARK: - What the saved notice adds (R6)

@Suite struct NookRecordNotesTests {
    @Test func voiceThatWasOnAndLeftNothingIsFlagged() {
        #expect(NookRecordRules.notes(voiceWasOn: true, voiceBuffersWritten: 0) == [.noVoice])
        #expect(NookRecordRules.notes(voiceWasOn: true, voiceBuffersWritten: 1).isEmpty)
        #expect(NookRecordRules.notes(voiceWasOn: false, voiceBuffersWritten: 0).isEmpty)
    }

    @Test func aFinishedPhaseCarriesTheNotes() {
        let url = URL(fileURLWithPath: "/tmp/a.mp4")
        let phase = NookRecordRules.phaseAfterFinish(
            fileURL: url, cause: .user, finishSucceeded: true, videoFramesWritten: 9, notes: [.noVoice]
        )
        #expect(phase == .finished(url, endedBy: .user, notes: [.noVoice]))
        #expect(phase != .finished(url, endedBy: .user))
    }

    @Test func theNoticeAddsEachNoteAfterTheEnding() {
        let lang = LanguageManager.shared
        let plain = NookRecordNotice.saved(endedBy: .user, lang: lang)
        #expect(!plain.isWarning)
        let noted = NookRecordNotice.saved(endedBy: .system, notes: [.noVoice, .droppedFrames, .suggestStandard], lang: lang)
        #expect(noted.isWarning)
        #expect(noted.symbol == "exclamationmark.triangle.fill")
        #expect(noted.text == [
            lang.t("nook.record.notice.system"), lang.t("nook.record.notice.noVoice"), lang.t("nook.record.notice.droppedFrames"),
        ].joined(separator: " "))
    }
}

// MARK: - Partial files and dropped frames (R8, R9)

@Suite struct NookRecordPartialAndDropTests {
    let url = URL(fileURLWithPath: "/tmp/a.mp4")

    @Test func aPartialFileThatPlaysIsKeptLikeAFinishedOne() {
        for cause in [NookRecordStopCause.writeError, .user] {
            #expect(NookRecordRules.phaseAfterFinish(
                fileURL: url, cause: cause, finishSucceeded: false, videoFramesWritten: 300, secondsWritten: 12, partialPlays: true
            ) == .finished(url, endedBy: .writeError(atSeconds: 12)))
        }
        // The writer failed but the close went through, and it plays.
        #expect(NookRecordRules.phaseAfterFinish(
            fileURL: url, cause: .writeError, finishSucceeded: true, videoFramesWritten: 300, secondsWritten: 12, partialPlays: true
        ) == .finished(url, endedBy: .writeError(atSeconds: 12)))
    }

    @Test func aPartialFileThatDoesNotPlayIsAFailureThatNamesTheTime() {
        #expect(NookRecordRules.phaseAfterFinish(
            fileURL: url, cause: .writeError, finishSucceeded: false, videoFramesWritten: 300, secondsWritten: 12, partialPlays: false
        ) == .failed(.writerFailed(atSeconds: 12)))
    }

    @Test func aPartialFileKeepsTheNotesToo() {
        let phase = NookRecordRules.phaseAfterFinish(
            fileURL: url, cause: .writeError, finishSucceeded: false, videoFramesWritten: 300, secondsWritten: 12,
            notes: [.noVoice], partialPlays: true
        )
        #expect(phase == .finished(url, endedBy: .writeError(atSeconds: 12), notes: [.noVoice]))
    }

    @Test func theKeptFileIsSaidToBeInTheFolder() {
        let lang = LanguageManager.shared
        let notice = NookRecordNotice.saved(endedBy: .writeError(atSeconds: 760), lang: lang)
        #expect(notice.isWarning)
        #expect(notice.text == NookRecordFailure.writerFailed(atSeconds: 760).sentence(lang) + " " + lang.t("nook.record.notice.keptPartial"))
        #expect(notice.text.contains("12:40"))
    }

    @Test func moreThanFivePercentDroppedIsWorthAWord() {
        #expect(!NookRecordRules.droppedFramesAreHigh(written: 0, dropped: 0))
        #expect(!NookRecordRules.droppedFramesAreHigh(written: 100, dropped: 0))
        // Exactly 5% is not above it.
        #expect(!NookRecordRules.droppedFramesAreHigh(written: 95, dropped: 5))
        #expect(NookRecordRules.droppedFramesAreHigh(written: 94, dropped: 6))
        #expect(NookRecordRules.droppedFramesAreHigh(written: 0, dropped: 3))
    }

    @Test func theNotesCombineVoiceAndDrops() {
        let notes = NookRecordRules.notes(voiceWasOn: true, voiceBuffersWritten: 0, videoWritten: 80, videoDropped: 20)
        #expect(notes == [.noVoice, .droppedFrames])
        #expect(NookRecordRules.notes(voiceWasOn: false, voiceBuffersWritten: 0, videoWritten: 99, videoDropped: 1).isEmpty)
    }

    // MARK: The Standard advice goes only to a High recording (R9 wording)

    @Test func dropsAtHighQualityAlsoSuggestStandard() {
        let notes = NookRecordRules.notes(
            voiceWasOn: false, voiceBuffersWritten: 0, videoWritten: 80, videoDropped: 20, quality: .high
        )
        #expect(notes == [.droppedFrames, .suggestStandard])
    }

    @Test func dropsAtStandardQualityDoNotSuggestStandard() {
        let notes = NookRecordRules.notes(
            voiceWasOn: false, voiceBuffersWritten: 0, videoWritten: 80, videoDropped: 20, quality: .standard
        )
        #expect(notes == [.droppedFrames])
    }

    @Test func highQualityWithoutManyDropsSaysNothing() {
        let notes = NookRecordRules.notes(
            voiceWasOn: false, voiceBuffersWritten: 0, videoWritten: 99, videoDropped: 1, quality: .high
        )
        #expect(notes.isEmpty)
    }

    @Test func theNoticeAtHighQualityOffersStandardAndAtStandardDoesNot() {
        let lang = LanguageManager.shared
        let high = NookRecordNotice.saved(endedBy: .user, notes: [.droppedFrames, .suggestStandard], lang: lang)
        #expect(high.text == lang.t("nook.record.notice.saved") + " " + lang.t("nook.record.notice.droppedFrames"))
        #expect(high.text.contains("Standard quality may be smoother on this Mac."))

        let standard = NookRecordNotice.saved(endedBy: .user, notes: [.droppedFrames], lang: lang)
        #expect(standard.isWarning)
        #expect(standard.text == lang.t("nook.record.notice.saved") + " " + lang.t("nook.record.notice.droppedFramesPlain"))
        #expect(standard.text.hasSuffix("Some frames were dropped."))
        #expect(!standard.text.contains("Standard quality"))
    }

    @Test func theAdviceIsMissingFromThePlainSentenceInEveryLanguage() throws {
        let plain = "nook.record.notice.droppedFramesPlain"
        let advice = "nook.record.notice.droppedFrames"
        let words: [String: [String]] = ["en": ["Standard"], "zh-Hans": ["标准"], "zh-Hant": ["標準"]]
        for (language, markers) in words {
            let table = try NookRecordStringsTests.table(language)
            let withAdvice = try #require(table[advice])
            let withoutAdvice = try #require(table[plain])
            for marker in markers {
                #expect(withAdvice.contains(marker), "\(language) lost its advice")
                #expect(!withoutAdvice.contains(marker), "\(language) gives the advice to a Standard recording")
            }
            #expect(withAdvice.hasPrefix(String(withoutAdvice.dropLast())), "\(language): the plain sentence is the first half of the full one")
        }
    }
}
