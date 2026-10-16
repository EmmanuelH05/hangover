import Foundation
import Testing
@testable import OpenIslandApp

/// The AppleScript that talks to Notes (N5 and N15). No script is run here:
/// the text is read, `osacompile` checks its syntax, and the timeout is
/// tried on a program that only sleeps.
@Suite struct NookNotesScriptTests {
    // MARK: What the scripts say

    @Test func theUpdateScriptCallsANoteMissingOnlyForNoSuchObject() {
        let script = NookAppleNotesScripts.update

        #expect(script.contains("errorNumber is -1728"))
        #expect(script.contains("error errorText number errorNumber"), "every other error is thrown out")
        // The old script answered "missing" to any error at all.
        #expect(!script.contains("on error\n"))
    }

    @Test func theUpdateScriptAsksWhichFolderTheNoteIsIn() {
        let script = NookAppleNotesScripts.update

        #expect(script.contains("set folderName to item 3 of argv"))
        #expect(script.contains("name of container of theNote"))
        #expect(script.contains("is not folderName then return \"missing\""))
    }

    @Test func theDeleteScriptIgnoresOnlyANoteThatIsAlreadyGone() {
        let script = NookAppleNotesScripts.delete

        #expect(script.contains("errorNumber is not -1728 then error errorText number errorNumber"))
        // The old script swallowed every error between try and end try.
        #expect(!script.contains("try\n            delete note id noteID\n        end try"))
    }

    @Test func theScriptsCompile() throws {
        let compiler = URL(fileURLWithPath: "/usr/bin/osacompile")
        guard FileManager.default.isExecutableFile(atPath: compiler.path),
              FileManager.default.fileExists(atPath: "/System/Applications/Notes.app") else { return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NookScripts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        for (name, script) in [
            ("create", NookAppleNotesScripts.create),
            ("update", NookAppleNotesScripts.update),
            ("delete", NookAppleNotesScripts.delete),
            ("find", NookAppleNotesScripts.find),
        ] {
            let source = folder.appendingPathComponent("\(name).applescript")
            try script.write(to: source, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = compiler
            process.arguments = ["-o", folder.appendingPathComponent("\(name).scpt").path, source.path]
            let errors = Pipe()
            process.standardError = errors
            try process.run()
            process.waitUntilExit()
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            #expect(process.terminationStatus == 0, "\(name) does not compile: \(message)")
        }
    }

    @Test func theFindScriptLooksOnlyInTheHangoverFolderAndPrintsNothingWithoutOne() {
        let script = NookAppleNotesScripts.find

        #expect(script.contains("set folderName to item 1 of argv"))
        #expect(script.contains("set noteTitle to item 2 of argv"))
        #expect(script.contains("if not (exists folder folderName of theAccount) then return \"\""), "a folder never made has no note")
        #expect(script.contains("notes of folder folderName of theAccount whose name is noteTitle"))
        #expect(!script.contains("make new"), "it only looks")
        #expect(!script.contains("delete"))
    }

    // MARK: What came back

    @Test func theUpdateAnswerIsOkOrMissingAndNothingElse() throws {
        #expect(try NookAppleNotesScriptBridge.updateResult(fromOutput: "ok\n") == true)
        #expect(try NookAppleNotesScriptBridge.updateResult(fromOutput: "missing\n") == false)
        #expect(throws: NookAppleNotesError.failed) { try NookAppleNotesScriptBridge.updateResult(fromOutput: "") }
        #expect(throws: NookAppleNotesError.failed) { try NookAppleNotesScriptBridge.updateResult(fromOutput: "maybe") }
    }

    @Test func aRunThatFailedIsThrownAndARefusalIsToldApart() {
        let refused = NookAppleNotesScriptBridge.Outcome(
            status: 1, standardOutput: "", standardError: "execution error: Not authorized to send Apple events to Notes. (-1743)"
        )
        let busy = NookAppleNotesScriptBridge.Outcome(
            status: 1, standardOutput: "", standardError: "execution error: Notes got an error: AppleEvent timed out. (-1712)"
        )
        let fine = NookAppleNotesScriptBridge.Outcome(status: 0, standardOutput: "ok", standardError: "")

        #expect(throws: NookAppleNotesError.notPermitted) { try NookAppleNotesScriptBridge.check(refused, operation: "delete") }
        #expect(throws: NookAppleNotesError.failed) { try NookAppleNotesScriptBridge.check(busy, operation: "update") }
        #expect(throws: Never.self) { try NookAppleNotesScriptBridge.check(fine, operation: "update") }
    }

    @Test func theFindAnswerIsOneIdToALine() {
        #expect(NookAppleNotesScriptBridge.ids(fromOutput: "x-coredata://A/ICNote/p1\nx-coredata://A/ICNote/p2\n")
            == ["x-coredata://A/ICNote/p1", "x-coredata://A/ICNote/p2"])
        #expect(NookAppleNotesScriptBridge.ids(fromOutput: "\n").isEmpty, "a folder with no such note")
        #expect(NookAppleNotesScriptBridge.ids(fromOutput: "").isEmpty)
    }

    @Test func theTitleOfANoteIsTheLineNotesNamesItBy() {
        #expect(NookAppleNotesBody.title(of: "Plan\nbody") == "Plan")
        #expect(NookAppleNotesBody.title(of: "\n\n  Plan  \r\nbody") == "Plan", "blank lines above and spaces round it are not part of it")
        #expect(NookAppleNotesBody.title(of: "# Plan") == "# Plan", "as the body sets it")
        #expect(NookAppleNotesBody.title(of: "  \n ").isEmpty)
    }

    @Test func aScriptThatTimedOutIsAFailureEvenWithAZeroStatus() {
        let hung = NookAppleNotesScriptBridge.Outcome(status: 0, standardOutput: "", standardError: "", timedOut: true)

        #expect(throws: NookAppleNotesError.failed) { try NookAppleNotesScriptBridge.check(hung, operation: "update") }
    }

    @Test func theErrorNumberIsTheLastOneInBrackets() {
        let text = #"Notes got an error: Can't get note id "x-coredata://ABC/ICNote/p(12)". (-1728)"#

        #expect(NookNotesLog.errorNumber(in: text) == "-1728")
        #expect(NookNotesLog.errorNumber(in: "no number here") == nil)
    }

    // MARK: The timeout

    @Test func aProgramThatRunsTooLongIsEndedAndSaidToHaveTimedOut() async {
        let started = Date()

        let outcome = await NookAppleNotesScriptBridge.run(
            executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], timeout: 0.3
        )

        #expect(outcome.timedOut)
        #expect(Date().timeIntervalSince(started) < 10, "it did not wait for the program")
    }

    @Test func aProgramThatEndsInTimeIsNotTimedOut() async {
        let outcome = await NookAppleNotesScriptBridge.run(
            executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["hello"], timeout: 20
        )

        #expect(!outcome.timedOut)
        #expect(outcome.status == 0)
        #expect(outcome.standardOutput == "hello\n")
    }

    @Test func theScriptsGetTwentySeconds() {
        #expect(NookAppleNotesScriptBridge.timeout == 20)
        for operation in ["update", "delete", "find"] {
            #expect(NookAppleNotesScriptBridge.timeout(for: operation) == 20, "\(operation)")
        }
    }

    @Test func aCreateGetsTwoMinutesBecauseItsEventLandsWhenTheScriptIsEnded() throws {
        #expect(NookAppleNotesScriptBridge.createTimeout == 120)
        #expect(NookAppleNotesScriptBridge.timeout(for: "create") == 120)

        // The create goes through the same door as the others, with its name.
        let source = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Nook/Widgets/Notes/NookAppleNotes.swift")
        #expect(source.contains("[NookAppleNotesBody.folderName, bodyHTML], operation: \"create\")"))
    }
}
