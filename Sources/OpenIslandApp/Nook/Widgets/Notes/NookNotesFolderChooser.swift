import AppKit
import Foundation

/// The folder chooser for notes (D70). Settings and the problem lines on the
/// card and in the editor open the same one: it starts in the Obsidian iCloud
/// folder when there is one, and the folder chosen is where notes go from
/// then on. A note that could not be saved in the old place is carried over.
@MainActor
enum NookNotesFolderChooser {
    /// Asks for a folder and hands it to the store. `holdsIsland` is true
    /// when the island is open behind the panel, which would otherwise close
    /// when the panel takes the keyboard (D52).
    static func choose(for store: NookNotesStore, holdsIsland: Bool = false) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = LanguageManager.shared.t("nook.notes.settings.chooseFolder.prompt")
        panel.directoryURL = NookNoteLocations.pickerStart(
            home: FileManager.default.homeDirectoryForCurrentUser, current: store.folderURL
        )
        if holdsIsland { store.onSystemPrompt(true) }
        let answer = panel.runModal()
        if holdsIsland { store.onSystemPrompt(false) }
        if answer == .OK, let url = panel.url {
            store.setFolder(url)
        }
    }
}

extension NookNotesStore {
    /// Where macOS lets an app control another: Privacy and Security, Automation.
    static let automationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    /// Runs the button a notice offers.
    func perform(_ action: NookNotesNotice.Action) {
        switch action {
        case .chooseFolder:
            NookNotesFolderChooser.choose(for: self, holdsIsland: true)
        case .createFolder:
            createFolder()
        case .openAutomationSettings:
            openSettings(Self.automationSettingsURL)
        }
    }
}
