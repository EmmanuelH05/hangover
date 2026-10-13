import AppKit
import Foundation

/// The folder chooser of the widget's Settings section. It is a system
/// window on a level below the open island's, and the island can be held
/// open (a typed line, the mirror, the tour). It counts as a system window
/// while it is up, the way the tour's folder chooser does (D52), which
/// steps an open island below it.
@MainActor
enum NookLinkAudioFolderPicker {
    /// Asks for a folder and keeps the one chosen. `ask` shows the chooser,
    /// starting at the folder that is set now, and answers with what was
    /// chosen or nil. A test hands in one that shows nothing.
    static func choose(for nook: NookModel, ask: @MainActor (URL) -> URL? = NookLinkAudioFolderPicker.runChooser) {
        nook.systemPromptBegan()
        defer { nook.systemPromptEnded() }
        guard let folder = ask(nook.linkAudio.folder) else { return }
        nook.linkAudio.setFolder(folder)
    }

    private static func runChooser(startingAt current: URL) -> URL? {
        let lang = LanguageManager.shared
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = current
        panel.prompt = lang.t("nook.linkAudio.settings.choosePrompt")
        panel.message = lang.t("nook.linkAudio.settings.chooseMessage")
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }
}
