import AppKit

/// Opens a saved link. The app passes the system's opener. Tests pass a
/// fake, and a kit nobody handed one to opens nothing and shows a notice.
@MainActor
protocol NookDesignLinkOpening: AnyObject {
    /// True when the system took the link.
    func open(_ url: URL) -> Bool
}

/// The workspace's own `open`, which hands a web link to the browser, or
/// to an app that has claimed it, such as the Figma desktop app.
@MainActor
final class NookDesignSystemLinkOpener: NookDesignLinkOpening {
    func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}
