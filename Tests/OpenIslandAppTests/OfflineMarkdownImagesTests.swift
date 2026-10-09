import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

/// An agent's message is drawn as Markdown. An image address in it must
/// never be fetched: the app would be calling a server chosen by whoever
/// wrote the text.
struct OfflineMarkdownImagesTests {
    @Test(arguments: [
        "https://example.com/pixel.png",
        "http://example.com/a.gif?user=1",
        "file:///etc/hosts",
    ])
    func anInlineImageIsNeverLoaded(address: String) async throws {
        let provider = OfflineMarkdownInlineImageProvider()
        let url = try #require(URL(string: address))

        await #expect(throws: OfflineMarkdownInlineImageProvider.ImagesAreNotLoaded.self) {
            _ = try await provider.image(with: url, label: "picture")
        }
    }

    @Test func everyMarkdownViewInTheAppRefusesRemoteImages() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/OpenIslandApp", isDirectory: true)
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var viewCount: Int = 0

        for case let file as URL in files where file.pathExtension == "swift" {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() where line.contains("Markdown(") && !line.contains("///") {
                viewCount += 1
                // The modifier sits within the few lines that follow the view.
                let following = lines[index..<min(index + 6, lines.count)].joined(separator: "\n")
                #expect(
                    following.contains(".markdownWithoutRemoteImages()"),
                    "\(file.lastPathComponent):\(index + 1) draws Markdown that may fetch images"
                )
            }
        }

        let none: Int = 0
        #expect(viewCount > none, "the check found no Markdown view to look at")
    }
}
