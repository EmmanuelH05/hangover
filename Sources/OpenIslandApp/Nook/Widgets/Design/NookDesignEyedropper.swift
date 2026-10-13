import AppKit

/// Lets the user pick a color from anywhere on the screen. The app passes
/// the system's sampler. Tests pass a fake, and a model nobody handed a
/// sampler to picks nothing.
@MainActor
protocol NookDesignColorSampling: AnyObject {
    /// Starts a pick. `completion` runs once.
    func sample(_ completion: @escaping @MainActor (NookDesignPickResult) -> Void)
}

/// How a pick ended.
enum NookDesignPickResult: Equatable, Sendable {
    case picked(NookDesignColor)
    /// The user gave up with Escape. Nothing changes.
    case cancelled
    /// A color was picked and has no RGB form the kit can keep, such as a
    /// pattern. That is not a cancel, and the card tells the user.
    case unreadable
}

/// The eyedropper is `NSColorSampler`, the loupe macOS itself draws for
/// its color panel. The app is handed one color and never sees the
/// screen, which is why this needs no Screen Recording permission and
/// asks for none. Apple said this when the class came out (WWDC 2019,
/// session 210): an app that samples the screen itself gets the Screen
/// Recording prompt, and one that uses `NSColorSampler` does not. The
/// class reference page says nothing about a permission either way.
///
/// The loupe follows the pointer across every display, and Escape cancels
/// it. Both are the system's doing.
@MainActor
final class NookDesignSystemColorSampler: NookDesignColorSampling {
    /// Kept while the loupe is up.
    private var sampler: NSColorSampler?

    func sample(_ completion: @escaping @MainActor (NookDesignPickResult) -> Void) {
        let sampler = NSColorSampler()
        self.sampler = sampler
        sampler.show { [weak self] picked in
            // The color is taken to sRGB here, before it crosses over. A color
            // with no RGB form is told apart from a cancel.
            let result = Self.result(for: picked)
            // AppKit calls this on the main thread.
            MainActor.assumeIsolated {
                self?.sampler = nil
                completion(result)
            }
        }
    }

    /// What the loupe's answer means: no color is a cancel, and a color the
    /// kit cannot read is not.
    nonisolated static func result(for picked: NSColor?) -> NookDesignPickResult {
        guard let picked else { return .cancelled }
        return NookDesignColor(nsColor: picked).map(NookDesignPickResult.picked) ?? .unreadable
    }
}

/// Where a pick was started from.
enum NookDesignPickSource: Equatable, Sendable {
    /// The eyedropper button on the card. The island closes first, which
    /// gets it out of the way of the screen under it.
    case island
    /// The keyboard shortcut. The island is left as it is.
    case shortcut
}

/// Pictures read from the clipboard because the user pressed Paste.
enum NookDesignPastedPictures: Equatable, Sendable {
    /// Picture files copied in Finder.
    case files([URL])
    /// A picture copied as data, such as a screenshot or a browser image.
    case data(Data)
    case none
}

/// Reads pictures and text off the clipboard for the reference shelf and
/// the Links tab. Nothing is read until the user presses a Paste button.
@MainActor
protocol NookDesignPictureClipboard: AnyObject {
    func readPictures() -> NookDesignPastedPictures
    /// The text on the clipboard, or nil when it holds none. A copied
    /// address from a browser counts as text.
    func readText() -> String?
    /// Whether macOS lets the app read what other apps copied, asks each
    /// time, or refuses. Looking never raises the alert.
    var access: NookClipboardAccess { get }
}

/// The general pasteboard. Only a real launch installs it.
@MainActor
final class NookDesignSystemPictureClipboard: NookDesignPictureClipboard {
    private let pasteboard: NSPasteboard

    init(_ pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Picture data types to look for, in the order they are preferred.
    private static let dataTypes: [NSPasteboard.PasteboardType] = [
        .png, .tiff,
        NSPasteboard.PasteboardType("public.jpeg"),
        NSPasteboard.PasteboardType("public.heic"),
        NSPasteboard.PasteboardType("com.compuserve.gif"),
        NSPasteboard.PasteboardType("org.webmproject.webp"),
    ]

    func readText() -> String? {
        pasteboard.string(forType: .string) ?? pasteboard.string(forType: .URL)
    }

    var access: NookClipboardAccess { NookSystemPasteboard(pasteboard).access }

    func readPictures() -> NookDesignPastedPictures {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
            return .files(urls)
        }
        let types = pasteboard.types ?? []
        for type in Self.dataTypes where types.contains(type) {
            if let data = pasteboard.data(forType: type) { return .data(data) }
        }
        return .none
    }
}
