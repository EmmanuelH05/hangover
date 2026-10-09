import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NookNotesSettings: View {
    var nook: NookModel

    private static let notesAppURL = URL(fileURLWithPath: "/System/Applications/Notes.app")

    var body: some View {
        let service = nook.notes
        Section("Notes") {
            Picker("Save to", selection: Binding(
                get: { service.destination },
                set: { service.setDestination($0) }
            )) {
                Text("Markdown file").tag(NookNotesDestination.file)
                Text("Apple Notes").tag(NookNotesDestination.appleNotes)
            }

            if service.destination == .appleNotes {
                Text("Each note is added as a line to a note called \(NookAppleNotesLine.noteTitle), in the default folder of your Notes app. macOS asks once whether Hangover may control Notes. Hangover sets that note's whole text again each time it adds a line, which can drop pictures and checklists you put in it by hand.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Notes") {
                    NSWorkspace.shared.open(Self.notesAppURL)
                }
            } else {
                LabeledContent("File") {
                    Text(service.fileURL.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("Choose file…") { chooseFile(service) }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([service.fileURL])
                    }
                }
            }
        }
    }

    private func chooseFile(_ service: NookNotesService) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = service.fileURL.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            service.setFileURL(url)
        }
    }
}
