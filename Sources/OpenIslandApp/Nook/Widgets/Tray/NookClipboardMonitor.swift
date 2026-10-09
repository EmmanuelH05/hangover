import AppKit
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

/// What the clipboard history needs from a pasteboard. The app passes the
/// general pasteboard. Tests pass a fake, which keeps them off the real one.
@MainActor
protocol NookPasteboardAccess: AnyObject {
    var changeCount: Int { get }
    var access: NookClipboardAccess { get }
    /// The types on the pasteboard, without its contents.
    func types() -> [String]
    /// Reads the copy itself. Called only after `types()` passed the skip
    /// rule, and at most once per change. A picture comes back without its
    /// thumbnail: the monitor makes that once the copy is known to be kept.
    func read() -> NookClipboardContent?
    /// Puts a copy on the pasteboard. False when it did not take.
    func write(_ content: NookClipboardContent) -> Bool
}

/// The general pasteboard.
@MainActor
final class NookSystemPasteboard: NookPasteboardAccess {
    private let pasteboard: NSPasteboard

    init(_ pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    var access: NookClipboardAccess {
        guard #available(macOS 15.4, *) else { return .allowed }
        switch pasteboard.accessBehavior {
        case .ask: return .asks
        case .alwaysDeny: return .denied
        // `.default` reads until macOS has put up its first alert, after
        // which it reports `.ask`.
        case .default, .alwaysAllow: return .allowed
        @unknown default: return .allowed
        }
    }

    func types() -> [String] {
        pasteboard.types?.map(\.rawValue) ?? []
    }

    /// One read call per copy: text when there is text, a picture
    /// otherwise. Nothing is decoded here. The pasteboard cannot say how
    /// large a copy is without handing it over, which leaves the size
    /// check to the caller, before anything is drawn from the data.
    func read() -> NookClipboardContent? {
        let types = pasteboard.types ?? []
        if types.contains(.string) {
            return pasteboard.string(forType: .string).map(NookClipboardContent.text)
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] where types.contains(type) {
            guard let data = pasteboard.data(forType: type) else { return nil }
            return .image(data: data, typeIdentifier: type.rawValue, thumbnail: nil)
        }
        return nil
    }

    func write(_ content: NookClipboardContent) -> Bool {
        pasteboard.clearContents()
        switch content {
        case let .text(text):
            return pasteboard.setString(text, forType: .string)
        case let .image(data, typeIdentifier, _):
            return pasteboard.setData(data, forType: NSPasteboard.PasteboardType(typeIdentifier))
        }
    }
}

/// Makes the small picture a copied image shows as in the list.
enum NookClipboardThumbnail {
    static let maxPixelSize = 96

    /// A PNG no larger than `maxPixelSize` on its longer side, or nil when
    /// the data is not a picture.
    static func make(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

/// What came of reading the pasteboard because the user asked.
enum NookClipboardCapture: Equatable, Sendable {
    case added
    /// Marked private by the app that copied it, or a copied file.
    case skipped
    /// Nothing the history keeps, or macOS refused the read.
    case nothing
}

/// Watches the general pasteboard and keeps the last copies while the user
/// has the history switched on. While it is off nothing is read, not even
/// the change count.
@MainActor
@Observable
final class NookClipboardMonitor {
    nonisolated static let enabledKey = "nook.tray.clipboardHistory"
    nonisolated static let pollInterval: TimeInterval = 1
    /// System Settings, Privacy and Security, Paste from Other Apps.
    nonisolated static let pasteSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard")

    private(set) var history = NookClipboardHistory()
    private(set) var isEnabled: Bool
    private(set) var access: NookClipboardAccess = .allowed
    /// The row last copied from, which shows a tick for a moment.
    private(set) var justCopiedID: UUID?

    @ObservationIgnored private let pasteboard: any NookPasteboardAccess
    @ObservationIgnored private let defaults: UserDefaults
    /// The change count at the last look. Nil while the history is off.
    @ObservationIgnored private var lastChangeCount: Int?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var copiedTask: Task<Void, Never>?
    /// Draws a kept picture's thumbnail. Tests pass their own.
    @ObservationIgnored private let makeThumbnail: @Sendable (Data) -> Data?
    /// The thumbnail being drawn for the newest picture. Tests wait on it.
    @ObservationIgnored private(set) var thumbnailTask: Task<Void, Never>?

    init(
        pasteboard: (any NookPasteboardAccess)? = nil,
        defaults: UserDefaults = .standard,
        makeThumbnail: @escaping @Sendable (Data) -> Data? = { NookClipboardThumbnail.make(from: $0) }
    ) {
        self.pasteboard = pasteboard ?? NookSystemPasteboard()
        self.defaults = defaults
        self.makeThumbnail = makeThumbnail
        isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    /// Begins watching if the history is on. What is on the pasteboard at
    /// launch is not read: only copies made from here on are.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        if isEnabled { beginWatching(readsCurrentCopy: false) }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        if enabled {
            // The copy on the pasteboard right now is the first row, which
            // shows the switch took. If macOS wants to ask about reading,
            // it asks here, while the user is looking at the tray.
            beginWatching(readsCurrentCopy: true)
        } else {
            stopWatching()
            history.clear()
        }
    }

    /// One look at the pasteboard. Only the change count is read unless it
    /// moved.
    func poll() {
        guard isEnabled else { return }
        refreshAccess()
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        // While macOS asks before each read, reading here would put an
        // alert up on every copy. The count is left alone, which means the
        // newest copy is picked up as soon as reads are allowed.
        guard access == .allowed else { return }
        lastChangeCount = count
        capture()
    }

    /// Reads the pasteboard once because the user asked for it.
    func captureNow() -> NookClipboardCapture {
        guard isEnabled else { return .nothing }
        refreshAccess()
        guard access != .denied else { return .nothing }
        lastChangeCount = pasteboard.changeCount
        let result = capture()
        refreshAccess()
        return result
    }

    /// Puts a row back on the pasteboard and moves it to the top.
    @discardableResult
    func copyAgain(_ entry: NookClipboardEntry) -> Bool {
        guard pasteboard.write(entry.content) else { return false }
        // Our own write. There is nothing to read back.
        lastChangeCount = pasteboard.changeCount
        history.moveToTop(entry.id)
        flash(entry.id)
        return true
    }

    /// Puts text the tray made itself on the pasteboard, such as a file's
    /// path. It lands in the history without a read.
    func copy(text: String) -> Bool {
        let content = NookClipboardContent.text(text)
        guard pasteboard.write(content) else { return false }
        if isEnabled {
            lastChangeCount = pasteboard.changeCount
            history.record(content)
        }
        return true
    }

    func remove(_ entry: NookClipboardEntry) {
        history.remove(entry.id)
    }

    func clear() {
        history.clear()
    }

    // MARK: - Private

    private func beginWatching(readsCurrentCopy: Bool) {
        refreshAccess()
        lastChangeCount = pasteboard.changeCount
        if readsCurrentCopy, access == .allowed {
            capture()
            refreshAccess()
        }
        // Tests drive `poll()` by hand and never call `start()`.
        guard hasStarted, ticker == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] timer in
            // A monitor that is gone leaves nothing to poll for.
            guard self != nil else { return timer.invalidate() }
            Task { @MainActor in self?.poll() }
        }
        timer.tolerance = Self.pollInterval * 0.3
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopWatching() {
        ticker?.invalidate()
        ticker = nil
        lastChangeCount = nil
        copiedTask?.cancel()
        justCopiedID = nil
    }

    private func refreshAccess() {
        let current = pasteboard.access
        if current != access { access = current }
    }

    @discardableResult
    private func capture() -> NookClipboardCapture {
        let count = pasteboard.changeCount
        guard !NookClipboardHistory.shouldSkip(types: pasteboard.types()) else { return .skipped }
        guard let content = pasteboard.read() else { return .nothing }
        // A copy that landed between the look at the types and the read
        // was never checked for the private markers. It is thrown away,
        // and the count it left behind brings the next poll back to it.
        guard pasteboard.changeCount == count else {
            lastChangeCount = count
            return .nothing
        }
        // `record` turns down a copy over the size caps, which comes
        // before anything is drawn from a picture's data.
        guard let entry = history.record(content) else { return .nothing }
        drawThumbnail(for: entry)
        return .added
    }

    /// Draws the small picture for a kept image off the main actor and
    /// hands it to the row when it is done.
    private func drawThumbnail(for entry: NookClipboardEntry) {
        guard case let .image(data, _, thumbnail) = entry.content, thumbnail == nil else { return }
        let id = entry.id
        let makeThumbnail = makeThumbnail
        thumbnailTask = Task.detached(priority: .utility) { [weak self] in
            let drawn = makeThumbnail(data)
            await MainActor.run { self?.history.setThumbnail(drawn, for: id) }
        }
    }

    private func flash(_ id: UUID) {
        justCopiedID = id
        copiedTask?.cancel()
        copiedTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.justCopiedID = nil
        }
    }
}
