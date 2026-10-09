import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NookNotesSettings: View {
    var nook: NookModel

    var body: some View {
        let service = nook.notes
        Section("Notes") {
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
