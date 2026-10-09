import SwiftUI

struct NookNotesCard: View {
    var nook: NookModel

    static let height: CGFloat = 120

    /// Height at each size. Small rows always use the grid’s shared height.
    static func height(for size: NookWidgetSize) -> CGFloat {
        switch size {
        case .small: NookWidgetLayout.smallHeight
        case .medium: height
        case .large: 220
        }
    }

    @Environment(\.nookWidgetSize) private var size
    @State private var draft = ""

    /// Recent notes shown under the field. Small is as tall as medium, only
    /// narrower, so both fit the same three rows; large has room for seven
    /// next to the footer.
    private var visibleEntryCount: Int {
        switch size {
        case .small, .medium: 3
        case .large: 7
        }
    }

    private var placeholder: String {
        size == .small ? "Jot, return to save" : "Jot something, return to save"
    }

    var body: some View {
        let service = nook.notes
        VStack(alignment: .leading, spacing: 6) {
            // The file name is the first thing to go on the narrow column,
            // and a long one truncates in the middle instead of wrapping.
            NookCardHeader(
                title: "Notes",
                systemImage: "note.text",
                trailing: size == .small ? nil : Self.destinationName(service)
            )
            .lineLimit(1)
            .truncationMode(.middle)
            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.08)))
                .onSubmit {
                    service.append(draft)
                    draft = ""
                }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(service.entries.prefix(visibleEntryCount)) { entry in
                    NookNoteRow(entry: entry, canDelete: service.canDelete) { service.delete(entry.id) }
                }
            }
            Spacer(minLength: 0)
            if size == .large {
                Text(Self.destinationLine(service))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NookCardBackground())
    }

    /// The short name for the card's header.
    static func destinationName(_ service: NookNotesService) -> String {
        service.destination == .appleNotes ? "Apple Notes" : service.fileURL.lastPathComponent
    }

    /// The line under the large card's list.
    static func destinationLine(_ service: NookNotesService) -> String {
        service.destination == .appleNotes
            ? "Saves to Apple Notes, in \(NookAppleNotesLine.noteTitle)"
            : "Saves to \(displayPath(service.fileURL))"
    }

    /// The file path with the home folder shortened to a tilde.
    private static func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}

private struct NookNoteRow: View {
    let entry: NookNoteEntry
    var canDelete = true
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(entry.date, format: .dateTime.hour().minute())
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(entry.text)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if isHovering, canDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}
