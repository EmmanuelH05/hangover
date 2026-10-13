import Foundation

/// Whether Link to MP3 is offered in this build. It is only in the dev copy,
/// the app whose bundle identifier is `app.openisland.dev`. The release app
/// does not have it: its widget cannot be switched on, a saved setting that
/// has it on loads without it, its service never starts or looks for the two
/// programs, and no list a user sees holds it. One rule in one place, which
/// every one of those reads.
enum NookLinkAudioOffer {
    /// The one app that offers it.
    static let devBundleID = "app.openisland.dev"

    /// What a test sets to see the other side of the rule. A task-local, which
    /// keeps tests that run side by side from changing each other's answer.
    @TaskLocal static var override: Bool?

    /// True in the dev copy. A process with no bundle identifier, which is how
    /// the test runner looks, counts as the dev copy, the same fallback the
    /// token files and the Keychain use.
    static var isOffered: Bool {
        override ?? isOffered(bundleID: Bundle.main.bundleIdentifier)
    }

    /// The rule itself, for a bundle identifier.
    static func isOffered(bundleID: String?) -> Bool {
        (bundleID ?? NookTodoTokenFile.fallbackBundleID) == devBundleID
    }
}

extension NookWidgetKind {
    /// False for Link to MP3 where the build does not offer it.
    var isOffered: Bool {
        self != .linkAudio || NookLinkAudioOffer.isOffered
    }

    /// Every widget a user can be shown, switched on or shown a switch for.
    /// Lists for the user walk this and not `allCases`.
    static var offered: [NookWidgetKind] {
        allCases.filter(\.isOffered)
    }
}
