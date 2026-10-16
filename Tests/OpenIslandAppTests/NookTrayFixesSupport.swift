import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import OpenIslandApp

/// A tray store on a folder in a temp directory, a fake pasteboard and
/// settings that live in memory, for the tray fix tests. Files come from
/// `NookConvertFixtures`. `cleanUp()` removes everything, and nothing leaves
/// the temp folder.
@MainActor
struct NookTrayFixesFixture {
    let files: NookConvertFixtures
    let folder: URL
    let store: NookTrayStore

    init() throws {
        files = try NookConvertFixtures()
        folder = files.url("tray")
        store = Self.makeStore(folder: folder)
    }

    /// A store on the same folder, as after Hangover is quit and opened again.
    func relaunched() -> NookTrayStore {
        Self.makeStore(folder: folder)
    }

    private static func makeStore(folder: URL) -> NookTrayStore {
        let defaults = MemoryDefaults()
        return NookTrayStore(
            folder: folder,
            clipboard: NookClipboardMonitor(pasteboard: NookFakePasteboard(), defaults: defaults),
            defaults: defaults
        )
    }

    func cleanUp() {
        // A test that made something read-only gives it back first.
        restorePermissions(at: files.folder)
        files.cleanUp()
    }

    /// Puts a copy of `source` in the tray under `name` and waits for it.
    @discardableResult
    func add(_ source: URL, named name: String, to target: NookTrayStore? = nil, linking: Bool = false) async throws -> NookTrayItem {
        let store = target ?? self.store
        let renamed = files.url("incoming-\(UUID().uuidString)").appendingPathComponent(name)
        try FileManager.default.createDirectory(at: renamed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: renamed)
        await store.add(fileAt: renamed, linking: linking)?.value
        return try #require(store.items.first { $0.originalName == name })
    }

    var names: [String] { store.items.map(\.originalName) }

    /// The folders directly inside the tray folder.
    var subfolders: [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
    }

    var indexURL: URL { folder.appendingPathComponent("index.json") }
    var badIndexURL: URL { folder.appendingPathComponent("index.json.bad") }

    func text(_ key: String) -> String {
        LanguageManager.shared.t(key)
    }

    private func restorePermissions(at root: URL) {
        let fm = FileManager.default
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in walker {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }
}

extension NookConvertFixtures {
    /// A PNG that looks like a photo to a compressor: a smooth gradient with
    /// a little grain on every pixel. PNG cannot squeeze the grain and JPEG
    /// can, so the JPEG of it is the smaller file. The grain comes from a
    /// fixed seed, which keeps the sizes the same on every run.
    func photoPNG(width: Int, height: Int) throws -> URL {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        var seed: UInt32 = 12_345
        for y in 0..<height {
            for x in 0..<width {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let grain = Int(seed >> 24) % 17 - 8
                let offset = (y * width + x) * 4
                bytes[offset] = UInt8(clamping: x * 255 / max(1, width) + grain)
                bytes[offset + 1] = UInt8(clamping: y * 255 / max(1, height) + grain)
                bytes[offset + 2] = UInt8(clamping: 128 + grain * 2)
            }
        }
        let image: CGImage = try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            return try #require(context.makeImage())
        }
        let file = url("\(UUID().uuidString).png")
        let destination = try #require(CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return file
    }
}
