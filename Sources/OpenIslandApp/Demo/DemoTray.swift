import AppKit
import Foundation

/// The sample files in the file tray (D51), made in the demo's temporary
/// folder in the layout the tray keeps its own: one folder for each file,
/// and an index. The tray then loads them the way it loads its saved ones.
@MainActor
enum DemoTray {
    struct SampleFile: Equatable, Sendable {
        let name: String
        let contents: String
    }

    static let files = [
        SampleFile(name: "Problem set 3.txt", contents: "Problem 1: show the reduction runs in linear time.\nProblem 2: draw the state machine.\n"),
        SampleFile(name: "Budget.csv", contents: "item,amount\nbooks,120\nrent,1450\ngroceries,310\n"),
        SampleFile(name: "Packing list.md", contents: "# Packing list\n\n- charger\n- notebook\n- rain jacket\n"),
        SampleFile(name: "Poster draft.png", contents: ""),
    ]

    /// Writes the files and the index into `folder`, newest first like the
    /// tray lists them.
    static func populate(folder: URL, now: Date) throws {
        let manager = FileManager.default
        var items: [NookTrayItem] = []
        for (index, file) in files.enumerated() {
            let id = UUID()
            let subfolder = folder.appendingPathComponent(id.uuidString, isDirectory: true)
            try manager.createDirectory(at: subfolder, withIntermediateDirectories: true)
            let url = subfolder.appendingPathComponent(file.name)
            if file.name.hasSuffix(".png") {
                guard let png = DemoArtwork.png(hue: 0.6) else { continue }
                try png.write(to: url)
            } else {
                try file.contents.write(to: url, atomically: true, encoding: .utf8)
            }
            items.append(NookTrayItem(
                id: id,
                originalName: file.name,
                storedName: "\(id.uuidString)/\(file.name)",
                addedDate: now.addingTimeInterval(-TimeInterval(index + 1) * 600)
            ))
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(items).write(to: folder.appendingPathComponent("index.json"), options: .atomic)
    }
}

/// A pasteboard that holds nothing and reads nothing from the Mac (D51).
/// The tray's clipboard list is off in the demo, and this keeps it off the
/// real pasteboard even if it were switched on.
@MainActor
final class DemoPasteboard: NookPasteboardAccess {
    private(set) var changeCount = 0
    let access = NookClipboardAccess.allowed
    private var content: NookClipboardContent?

    func types() -> [String] { [] }
    func read() -> NookClipboardContent? { nil }

    func write(_ content: NookClipboardContent) -> Bool {
        self.content = content
        changeCount += 1
        return true
    }
}

/// A token store that holds nothing and touches no Keychain (D51).
struct DemoTokenStore: NookTodoTokenStoring {
    func read() throws -> String? { nil }
    func save(_ token: String) throws {}
    func delete() throws {}
}
