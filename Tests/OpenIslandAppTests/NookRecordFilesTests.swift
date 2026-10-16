import Foundation
import Testing
@testable import OpenIslandApp

@Suite struct NookRecordFilesTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    func date(_ hour: Int, _ minute: Int, _ second: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: hour, minute: minute, second: second))!
    }

    @Test func theNameReadsLikeAMacScreenshot() {
        #expect(NookRecordFiles.fileName(for: date(15, 42, 10), calendar: calendar) == "Recording 2026-10-14 at 3.42.10 PM.mp4")
    }

    @Test func justAfterMidnightIsTwelveAM() {
        #expect(NookRecordFiles.fileName(for: date(0, 5, 0), calendar: calendar) == "Recording 2026-10-14 at 12.05.00 AM.mp4")
    }

    @Test func noonIsTwelvePM() {
        #expect(NookRecordFiles.fileName(for: date(12, 0, 0), calendar: calendar) == "Recording 2026-10-14 at 12.00.00 PM.mp4")
    }

    @Test func aTakenNameGetsANumber() {
        let folder = URL(fileURLWithPath: "/tmp/x")
        let taken: Set<String> = ["/tmp/x/A.mp4", "/tmp/x/A 2.mp4"]
        let url = NookRecordFiles.uniqueURL(in: folder, name: "A.mp4") { taken.contains($0.path) }
        #expect(url.lastPathComponent == "A 3.mp4")
    }

    @Test func aFreeNameIsKeptAsItIs() {
        let folder = URL(fileURLWithPath: "/tmp/x")
        let url = NookRecordFiles.uniqueURL(in: folder, name: "A.mp4") { _ in false }
        #expect(url.lastPathComponent == "A.mp4")
    }

    @Test func theFolderIsMoviesHangover() {
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(NookRecordFiles.folder(home: home).path == "/Users/someone/Movies/Hangover")
    }
}
