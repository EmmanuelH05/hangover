@preconcurrency import MarkdownUI
import SwiftUI

/// Images in an agent's message are never fetched.
///
/// MarkdownUI's own providers load an image's address from the network the
/// moment a view shows it. The text on a completion card is an agent's, and
/// an agent often quotes a web page or a file. One image address in it
/// would make this app call a server of the writer's choosing, with no
/// click and no setting to stop it. The card shows the words only.
struct OfflineMarkdownImageProvider: ImageProvider {
    func makeImage(url: URL?) -> some View {
        EmptyView()
    }
}

/// The same for an image inside a line of text. Throwing is how a provider
/// says "no image", and MarkdownUI then draws the line without it.
struct OfflineMarkdownInlineImageProvider: InlineImageProvider {
    struct ImagesAreNotLoaded: Error {}

    func image(with url: URL, label: String) async throws -> Image {
        throw ImagesAreNotLoaded()
    }
}

extension View {
    /// Keeps a Markdown view from fetching any image. Every `Markdown` view
    /// in the app carries it, and a test checks that.
    func markdownWithoutRemoteImages() -> some View {
        markdownImageProvider(OfflineMarkdownImageProvider())
            .markdownInlineImageProvider(OfflineMarkdownInlineImageProvider())
    }
}
