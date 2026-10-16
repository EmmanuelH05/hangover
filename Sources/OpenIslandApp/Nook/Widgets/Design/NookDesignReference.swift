import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One picture on the reference shelf. The picture itself is a copy in the
/// shelf's own folder, which is why it outlives the file it came from.
struct NookDesignReference: Identifiable, Hashable, Sendable {
    var id: UUID
    var collectionID: UUID
    /// The name shown under the picture. Empty when it has none.
    var name: String
    /// The picture's file inside its own folder, "original.png".
    var fileName: String
    /// The picture's size in pixels, turned upright.
    var pixelWidth: Int
    var pixelHeight: Int
    var isFavorite: Bool
    var addedAt: Date
    /// The size, in points, the picture's floating panel was last left at,
    /// whole panel with its strip of controls. Nil until the user resizes
    /// the panel, and for a list saved before this was kept.
    var panelWidth: Int?
    var panelHeight: Int?

    /// Width over height. A picture with no size counts as square.
    var aspectRatio: CGFloat {
        pixelWidth > 0 && pixelHeight > 0 ? CGFloat(pixelWidth) / CGFloat(pixelHeight) : 1
    }

    /// The remembered size of the floating panel, if there is a usable one.
    var panelSize: CGSize? {
        guard let panelWidth, let panelHeight, panelWidth > 0, panelHeight > 0 else { return nil }
        return CGSize(width: panelWidth, height: panelHeight)
    }
}

extension NookDesignReference: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, collectionID, name, fileName, pixelWidth, pixelHeight, isFavorite, addedAt
        case panelWidth, panelHeight
    }

    /// The id and the file name are what find the picture on disk. An
    /// entry without them cannot be shown and is skipped by the list.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let counter = decoder.skipCounter
        id = try container.decode(UUID.self, forKey: .id)
        fileName = try container.decode(String.self, forKey: .fileName)
        collectionID = container.lenient(UUID.self, forKey: .collectionID, fallback: NookDesignCollection.globalID, counter: counter)
        name = container.lenient(String.self, forKey: .name, fallback: "", counter: counter)
        pixelWidth = container.lenient(Int.self, forKey: .pixelWidth, fallback: 0, counter: counter)
        pixelHeight = container.lenient(Int.self, forKey: .pixelHeight, fallback: 0, counter: counter)
        isFavorite = container.lenient(Bool.self, forKey: .isFavorite, fallback: false, counter: counter)
        addedAt = container.lenient(Date.self, forKey: .addedAt, fallback: Date(timeIntervalSince1970: 0), counter: counter)
        // Lists saved before the panel size was kept have neither key.
        panelWidth = container.lenientOptional(Int.self, forKey: .panelWidth, counter: counter)
        panelHeight = container.lenientOptional(Int.self, forKey: .panelHeight, counter: counter)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(collectionID, forKey: .collectionID)
        try container.encode(name, forKey: .name)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(pixelWidth, forKey: .pixelWidth)
        try container.encode(pixelHeight, forKey: .pixelHeight)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(addedAt, forKey: .addedAt)
        // Written only once there is a size, which keeps a list that never
        // had one as it was.
        try container.encodeIfPresent(panelWidth, forKey: .panelWidth)
        try container.encodeIfPresent(panelHeight, forKey: .panelHeight)
    }
}

/// What adding a picture came to.
enum NookDesignReferenceAddResult: Equatable, Sendable {
    case added(NookDesignReference)
    /// The picture is on the shelf and its files are in place, and the list
    /// that names it could not be written. It is not promised to stay.
    case addedNotSaved(NookDesignReference)
    /// The saved files come from a newer Hangover, which are left alone.
    case locked
    /// The file could not be opened to be read, which says nothing about
    /// what is in it.
    case unreadable
    /// Not a picture this Mac can open.
    case notAPicture
    /// It is a picture, and its preview could not be written.
    case previewFailed
    /// Over the file size or the pixel limit.
    case tooLarge
    /// The shelf holds as many pictures as it may.
    case full
    /// The copy could not be written.
    case failed
    /// The file is one of the shelf's own copies. Nothing to do.
    case alreadyHere
}

/// Pure rules for the reference shelf: its limits, names and sizes.
enum NookDesignReferenceRules {
    static let maxReferences = 200
    /// A file larger than this is refused before it is opened.
    static let maxFileBytes = 64 * 1024 * 1024
    /// A picture with more pixels than this is refused from its header.
    static let maxPixels = 100_000_000
    static let maxNameLength = 80
    /// Longer side of a saved thumbnail, in pixels. The largest tile is
    /// 64 points, 128 pixels on a Retina screen, and this leaves room.
    static let thumbnailMaxPixel = 256
    /// Longer side of the picture a floating panel holds in memory.
    static let displayMaxPixel = 4096
    static let thumbnailFileName = "thumbnail.png"
    static let originalBaseName = "original"

    /// File endings the file tray offers "Add to references" for. The
    /// shelf itself decides by opening the file, never by its name.
    static let pictureExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "gif", "tif", "tiff", "webp", "bmp",
    ]

    static func isPictureFileName(_ name: String) -> Bool {
        pictureExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// The name a picture gets from the file it came from: the file's
    /// name without its ending.
    static func displayName(forFileNamed fileName: String) -> String {
        cleanName(((fileName as NSString).lastPathComponent as NSString).deletingPathExtension)
    }

    /// A name as it is kept (`NookDesignNames.clean`).
    static func cleanName(_ name: String) -> String {
        NookDesignNames.clean(name, limit: maxNameLength)
    }

    /// Whether the rename field holds a name the shelf does not have yet
    /// (`NookDesignNames.isUnsaved`).
    static func isUnsavedName(_ typed: String, saved: String) -> Bool {
        NookDesignNames.isUnsaved(typed, saved: saved, limit: maxNameLength)
    }

    /// The order the card shows the shelf in: favorites first, then the
    /// rest, each group in the shelf's own order. The colors do the same.
    /// The shelf itself keeps its order, which the move commands act on.
    static func compactOrder(_ items: [NookDesignReference]) -> [NookDesignReference] {
        items.filter(\.isFavorite) + items.filter { !$0.isFavorite }
    }

    /// The name of the copy on disk. It is built from the picture's type
    /// alone, which keeps anything a file was called out of the path.
    static func storedFileName(typeIdentifier: String) -> String {
        let ending = UTType(typeIdentifier)?.preferredFilenameExtension ?? "img"
        return "\(originalBaseName).\(ending)"
    }

    /// The size a picture is drawn at for a thumbnail: its own shape, its
    /// longer side no more than `maxSide`, and never larger than it is.
    static func thumbnailSize(forPixelWidth width: Int, pixelHeight height: Int, maxSide: Int = thumbnailMaxPixel) -> CGSize {
        guard width > 0, height > 0, maxSide > 0 else { return .zero }
        let longer = max(width, height)
        guard longer > maxSide else { return CGSize(width: width, height: height) }
        let scale = CGFloat(maxSide) / CGFloat(longer)
        return CGSize(
            width: max(1, (CGFloat(width) * scale).rounded()),
            height: max(1, (CGFloat(height) * scale).rounded())
        )
    }

    /// The size a picture is drawn at inside a tile `side` points square,
    /// whole and in its own shape.
    static func fittedSize(aspectRatio: CGFloat, in side: CGFloat) -> CGSize {
        guard aspectRatio > 0, side > 0 else { return .zero }
        return aspectRatio >= 1
            ? CGSize(width: side, height: side / aspectRatio)
            : CGSize(width: side * aspectRatio, height: side)
    }

    /// The order with `id` moved to `index`, clamped to the list.
    static func moving(_ id: UUID, to index: Int, in items: [NookDesignReference]) -> [NookDesignReference] {
        guard let from = items.firstIndex(where: { $0.id == id }) else { return items }
        var result = items
        let item = result.remove(at: from)
        result.insert(item, at: min(max(0, index), result.count))
        return result
    }
}

/// What a picture file says about itself, read from its header.
struct NookDesignPictureInfo: Equatable, Sendable {
    var typeIdentifier: String
    var pixelWidth: Int
    var pixelHeight: Int

    var pixelCount: Int { pixelWidth * pixelHeight }
}

/// The ImageIO work behind the shelf. None of it touches the main actor,
/// and callers run it off it.
enum NookDesignPictures {
    /// Reads a picture's type and size without decoding it. Nil when the
    /// data is not a picture ImageIO opens.
    static func inspect(_ source: CGImageSource) -> NookDesignPictureInfo? {
        guard CGImageSourceGetCount(source) > 0,
              let type = CGImageSourceGetType(source) as String?,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else {
            return nil
        }
        // Orientations five to eight lie on their side.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let isTurned = (5...8).contains(orientation)
        return NookDesignPictureInfo(
            typeIdentifier: type,
            pixelWidth: isTurned ? height : width,
            pixelHeight: isTurned ? width : height
        )
    }

    static func inspect(fileAt url: URL) -> NookDesignPictureInfo? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap(inspect)
    }

    static func inspect(_ data: Data) -> NookDesignPictureInfo? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap(inspect)
    }

    /// The picture scaled down to `maxPixel` on its longer side and turned
    /// upright. A picture already smaller is decoded as it is.
    static func image(fileAt url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Whether a decoded picture can have see-through parts. Such a
    /// picture is drawn over a checkerboard, which shows where they are.
    static func carriesAlpha(_ info: CGImageAlphaInfo) -> Bool {
        switch info {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }

    /// Writes the picture's thumbnail as a PNG. False when the picture did
    /// not decode or the file could not be written.
    static func writeThumbnail(ofFileAt url: URL, to destination: URL) -> Bool {
        guard let thumbnail = image(fileAt: url, maxPixel: NookDesignReferenceRules.thumbnailMaxPixel),
              let output = CGImageDestinationCreateWithURL(
                  destination as CFURL, UTType.png.identifier as CFString, 1, nil
              ) else {
            return false
        }
        CGImageDestinationAddImage(output, thumbnail, nil)
        return CGImageDestinationFinalize(output)
    }
}
