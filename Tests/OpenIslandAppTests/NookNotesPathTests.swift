import Foundation
import Testing
@testable import OpenIslandApp

/// Where the notes widget keeps its file when the user never picked one:
/// the app's own folder, on every Mac.
@MainActor
struct NookNotesPathTests {
    @Test func aFilePickedInSettingsAlwaysWins() {
        let picked: String = "~/Notes/Inbox.md"
        #expect(NookNotesService.resolvePath(stored: picked) == picked)
    }

    @Test func aFreshInstallKeepsNotesInTheAppsOwnFolder() {
        let path = NookNotesService.resolvePath(stored: nil)

        #expect(path == NookNotesService.defaultPath)
        #expect(path.hasPrefix("~/Library/Application Support/OpenIsland/"))
        // Not a folder macOS asks about, and no new folder in the home.
        for asked in ["/Documents/", "/Desktop/", "/Downloads/"] {
            #expect(!path.contains(asked))
        }
    }
}
