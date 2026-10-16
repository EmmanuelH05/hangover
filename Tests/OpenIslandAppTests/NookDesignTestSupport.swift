import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import OpenIslandApp

/// Colors, pictures and folders for the design kit's tests. Pictures are
/// drawn in memory and written only under the temporary folder. Nothing
/// here reads the screen, the clipboard or the user's own files.
enum NookDesignSamples {
    static let orange = NookDesignColor(red: 255, green: 136, blue: 0)
    static let teal = NookDesignColor(red: 46, green: 196, blue: 182)
    static let ink = NookDesignColor(red: 17, green: 17, blue: 17)
    static let scrim = NookDesignColor(red: 0, green: 0, blue: 0, alpha: 128)
    static let white = NookDesignColor(red: 255, green: 255, blue: 255)

    /// A date with no fraction of a second, which is what the files keep.
    static let day = Date(timeIntervalSince1970: 1_800_000_000)

    static func temporaryFolder(_ label: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NookDesign-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A picture of one color with a lighter corner, as PNG data.
    static func pngData(width: Int, height: Int, color: NookDesignColor = orange) -> Data {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(
            red: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255,
            blue: CGFloat(color.blue) / 255, alpha: 1
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.7)
        context.fill(CGRect(x: 0, y: 0, width: max(1, width / 3), height: max(1, height / 3)))
        let image = context.makeImage()!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    @discardableResult
    static func writePNG(named name: String, in folder: URL, width: Int = 60, height: Int = 40, color: NookDesignColor = orange) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try pngData(width: width, height: height, color: color).write(to: url)
        return url
    }

    static func pixelSize(ofPictureAt url: URL) -> CGSize? {
        NookDesignPictures.inspect(fileAt: url).map { CGSize(width: $0.pixelWidth, height: $0.pixelHeight) }
    }

    /// Waits for something another task is doing, checking every few
    /// milliseconds. False when it never came true.
    @MainActor
    static func wait(seconds: Double = 5, until condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}

/// Records what the kit copies. The real clipboard is never touched.
@MainActor
final class NookDesignCopyRecorder {
    private(set) var texts: [String] = []
    var succeeds = true

    func copy(_ text: String) -> Bool {
        guard succeeds else { return false }
        texts.append(text)
        return true
    }
}

/// A sampler that never shows the system's loupe. The test decides what
/// the pick comes to.
@MainActor
final class FakeColorSampler: NookDesignColorSampling {
    private(set) var sampleCount = 0
    private var completion: (@MainActor (NookDesignPickResult) -> Void)?

    func sample(_ completion: @escaping @MainActor (NookDesignPickResult) -> Void) {
        sampleCount += 1
        self.completion = completion
    }

    /// Ends the pick under way, with nil for a cancel.
    func finish(_ color: NookDesignColor?) {
        let done = completion
        completion = nil
        done?(color.map(NookDesignPickResult.picked) ?? .cancelled)
    }

    /// The loupe handed back a color the kit cannot read.
    func finishUnreadable() {
        let done = completion
        completion = nil
        done?(.unreadable)
    }
}

/// Records the panels the kit asks for. No window is ever made.
@MainActor
final class FakeReferencePresenter: NookDesignReferencePresenting {
    struct Presented: Equatable {
        let id: UUID
        let slot: Int
        let pixelWidth: Int
    }

    private(set) var presented: [Presented] = []
    private(set) var focused: [UUID] = []
    private(set) var closed: [UUID] = []
    private(set) var closeAllCount = 0
    /// The size each reference carried when its panel was asked for, in
    /// the order the panels were asked for. A real panel opens at it.
    private(set) var rememberedSizes: [CGSize?] = []
    private var onClose: [UUID: @MainActor () -> Void] = [:]
    private var onResize: [UUID: @MainActor (CGSize) -> Void] = [:]

    func present(
        _ reference: NookDesignReference,
        image: CGImage,
        slot: Int,
        onResize: @escaping @MainActor (CGSize) -> Void,
        onClose: @escaping @MainActor () -> Void
    ) {
        presented.append(Presented(id: reference.id, slot: slot, pixelWidth: image.width))
        rememberedSizes.append(reference.panelSize)
        self.onResize[reference.id] = onResize
        self.onClose[reference.id] = onClose
    }

    func focus(_ id: UUID) { focused.append(id) }

    func close(_ id: UUID) {
        closed.append(id)
        onResize[id] = nil
        onClose.removeValue(forKey: id)?()
    }

    func closeAll() {
        closeAllCount += 1
        let waiting = onClose
        onClose = [:]
        onResize = [:]
        for close in waiting.values { close() }
    }

    /// The user closes a panel with its own button or with Escape.
    func userCloses(_ id: UUID) {
        onResize[id] = nil
        onClose.removeValue(forKey: id)?()
    }

    /// The user drags a panel to a new size.
    func userResizes(_ id: UUID, to size: CGSize) {
        onResize[id]?(size)
    }
}

@MainActor
final class FakeEditorPresenter: NookDesignEditorPresenting {
    private(set) var showCount = 0
    private(set) var closeCount = 0

    func show(_ kit: NookDesignKit) { showCount += 1 }
    func close() { closeCount += 1 }
}

/// A clipboard that holds what the test puts on it.
@MainActor
final class FakePictureClipboard: NookDesignPictureClipboard {
    var pictures: NookDesignPastedPictures = .none
    /// The text on the clipboard, nil for none.
    var text: String?
    var access = NookClipboardAccess.allowed
    /// The model whose prompt count is looked at during a read.
    weak var nook: NookModel?
    /// Whether a system prompt was counted as up during the last read.
    private(set) var promptWasUpDuringRead = false
    private(set) var reads = 0
    private(set) var textReads = 0

    func readPictures() -> NookDesignPastedPictures {
        reads += 1
        promptWasUpDuringRead = nook?.isSystemPromptUp == true
        return pictures
    }

    func readText() -> String? {
        textReads += 1
        promptWasUpDuringRead = nook?.isSystemPromptUp == true
        return text
    }
}

/// Opens nothing. It records what it was asked to open and answers as the
/// test says. No browser or app is ever started.
@MainActor
final class FakeLinkOpener: NookDesignLinkOpening {
    private(set) var opened: [URL] = []
    var accepts = true

    func open(_ url: URL) -> Bool {
        opened.append(url)
        return accepts
    }
}

/// A hot key registrar that registers nothing with macOS.
@MainActor
final class FakeDesignHotkeyRegistrar: NookDesignHotkeyRegistering {
    var system: Set<AgentHotkeyCombo> = []
    /// What macOS answers. Nil accepts.
    var refusalCode: Int32?
    private(set) var registered: AgentHotkeyCombo?
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private var onPress: (@MainActor () -> Void)?

    func register(_ combo: AgentHotkeyCombo, onPress: @escaping @MainActor () -> Void) -> AgentHotkeyRegistrationOutcome {
        registerCount += 1
        if let refusalCode { return .failed(code: refusalCode) }
        registered = combo
        self.onPress = onPress
        return .registered
    }

    func unregister() {
        unregisterCount += 1
        registered = nil
        onPress = nil
    }

    func systemShortcuts() -> Set<AgentHotkeyCombo> { system }

    func keyName(for keyCode: UInt16) -> String? { AgentHotkeyKeyboard.usName(for: keyCode) }

    /// The user presses the shortcut. Nothing happens unless it is held.
    func press() { onPress?() }
}

/// A kit on a folder, settings and services of its own.
@MainActor
struct NookDesignFixture {
    let folder: URL
    let defaults: MemoryDefaults
    let copies = NookDesignCopyRecorder()
    let sampler = FakeColorSampler()
    let presenter = FakeReferencePresenter()
    let editor = FakeEditorPresenter()
    let clipboard = FakePictureClipboard()
    let opener = FakeLinkOpener()
    let registrar = FakeDesignHotkeyRegistrar()
    let kit: NookDesignKit

    /// A kit with fake services, switched on and read, unless `isLive` is
    /// false.
    init(_ label: String = "kit", isLive: Bool = true, defaults: MemoryDefaults = MemoryDefaults()) async throws {
        folder = try NookDesignSamples.temporaryFolder(label)
        self.defaults = defaults
        let copies = copies
        kit = NookDesignKit(folder: folder, defaults: defaults, copyText: { copies.copy($0) })
        kit.activate(NookDesignServices(
            sampler: sampler,
            presenter: presenter,
            editor: editor,
            pictureClipboard: clipboard,
            hotkeyRegistrar: registrar,
            linkOpener: opener
        ))
        if isLive {
            kit.setLive(true)
            await kit.load()
        }
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A picture on the shelf, added from a file that is then deleted.
    @discardableResult
    func addPicture(named name: String = "shot.png", width: Int = 60, height: Int = 40) async throws -> NookDesignReference {
        let sources = try NookDesignSamples.temporaryFolder("sources")
        defer { try? FileManager.default.removeItem(at: sources) }
        let url = try NookDesignSamples.writePNG(named: name, in: sources, width: width, height: height)
        let result = await kit.references.add(fileAt: url).value
        guard case let .added(item) = result else {
            throw NookDesignFixtureError.notAdded(String(describing: result))
        }
        return item
    }
}

enum NookDesignFixtureError: Error {
    case notAdded(String)
}
