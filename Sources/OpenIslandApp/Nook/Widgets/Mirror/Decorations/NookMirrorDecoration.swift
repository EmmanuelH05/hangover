import SwiftUI

/// What the user has put on the mirror: at most one frame around the
/// picture and any number of stickers on it. A plain value: it is saved
/// with the Nook settings, and the live mirror and a photo booth photo
/// draw it the same way.
struct NookMirrorDecorationSet: Codable, Equatable, Sendable {
    /// The frame design's identifier, or nil for no frame.
    var frameID: String?
    var stickers: [NookMirrorSticker] = []

    static let none = NookMirrorDecorationSet()

    var isEmpty: Bool { frameID == nil && stickers.isEmpty }

    init(frameID: String? = nil, stickers: [NookMirrorSticker] = []) {
        self.frameID = frameID
        self.stickers = stickers
    }

    private enum CodingKeys: String, CodingKey {
        case frameID
        case stickers
    }

    // Every field is optional on the way in, which keeps data saved by an
    // older build readable after fields are added.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frameID = try container.decodeIfPresent(String.self, forKey: .frameID)
        stickers = try container.decodeIfPresent([NookMirrorSticker].self, forKey: .stickers) ?? []
    }
}

/// One sticker on the mirror. Its place and size are fractions of the
/// picture, which keeps it in the same spot at every size the picture is
/// drawn at.
struct NookMirrorSticker: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    /// The sticker design's identifier.
    var designID: String
    /// Center of the sticker: 0 to 1 from the left and from the top of the
    /// picture as the user sees it.
    var x: Double
    var y: Double
    /// Width as a fraction of the picture's width.
    var width: Double
    /// Degrees, clockwise.
    var rotation: Double = 0
    /// Which of the design's colorways to draw. Out of range wraps around.
    var variant: Int = 0

    init(
        id: UUID = UUID(),
        designID: String,
        x: Double,
        y: Double,
        width: Double,
        rotation: Double = 0,
        variant: Int = 0
    ) {
        self.id = id
        self.designID = designID
        self.x = x
        self.y = y
        self.width = width
        self.rotation = rotation
        self.variant = variant
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case designID
        case x
        case y
        case width
        case rotation
        case variant
    }

    // Only the design is required. The rest falls back to a sticker in the
    // middle of the picture, which keeps older data readable.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        designID = try container.decode(String.self, forKey: .designID)
        x = try container.decodeIfPresent(Double.self, forKey: .x) ?? 0.5
        y = try container.decodeIfPresent(Double.self, forKey: .y) ?? 0.5
        width = try container.decodeIfPresent(Double.self, forKey: .width)
            ?? NookMirrorDecorationLayout.defaultStickerWidth
        rotation = try container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        variant = try container.decodeIfPresent(Int.self, forKey: .variant) ?? 0
    }
}

// Changes hand back a new set and leave the old one as it was.
extension NookMirrorDecorationSet {
    func settingFrame(_ id: String?) -> NookMirrorDecorationSet {
        NookMirrorDecorationSet(frameID: id, stickers: stickers)
    }

    /// The set with one more sticker of this design, placed where it does
    /// not hide the last one. Nil when the set is full.
    func adding(designID: String) -> (set: NookMirrorDecorationSet, sticker: NookMirrorSticker)? {
        guard stickers.count < NookMirrorDecorationLayout.maxStickers else { return nil }
        let spot = NookMirrorDecorationLayout.dropPoint(count: stickers.count)
        let sticker = NookMirrorSticker(
            designID: designID,
            x: spot.x,
            y: spot.y,
            width: NookMirrorDecorationLayout.defaultStickerWidth
        )
        return (NookMirrorDecorationSet(frameID: frameID, stickers: stickers + [sticker]), sticker)
    }

    func removing(_ id: UUID) -> NookMirrorDecorationSet {
        NookMirrorDecorationSet(frameID: frameID, stickers: stickers.filter { $0.id != id })
    }

    /// The set with this sticker swapped in for the one that shares its
    /// id, kept on the picture and inside the size limits.
    func replacing(_ sticker: NookMirrorSticker) -> NookMirrorDecorationSet {
        let fitted = NookMirrorDecorationLayout.clamped(sticker)
        return NookMirrorDecorationSet(
            frameID: frameID,
            stickers: stickers.map { $0.id == fitted.id ? fitted : $0 }
        )
    }

    /// What is safe to show from saved data: designs this build knows,
    /// every sticker on the picture, no more than the cap, no id twice.
    func sanitized(
        knownFrames: Set<String> = NookMirrorDesigns.frameIDs,
        knownStickers: Set<String> = NookMirrorDesigns.stickerIDs
    ) -> NookMirrorDecorationSet {
        var seen: Set<UUID> = []
        let kept = stickers
            .filter { knownStickers.contains($0.designID) && seen.insert($0.id).inserted }
            .prefix(NookMirrorDecorationLayout.maxStickers)
            .map(NookMirrorDecorationLayout.clamped)
        let frame = frameID.flatMap { knownFrames.contains($0) ? $0 : nil }
        return NookMirrorDecorationSet(frameID: frame, stickers: Array(kept))
    }
}

/// Draws a decoration set over the picture it is laid on, filling the
/// space it is given. Pure SwiftUI: no AppKit view, no clock and no
/// animation that needs one, which lets the photo booth draw the same
/// thing into a saved photo with `ImageRenderer`.
struct NookMirrorDecorationOverlay: View {
    var decorations: NookMirrorDecorationSet
    /// The line a frame with a note writes. Today's date, unless a caller
    /// that needs the same picture every day says otherwise.
    var note = NookMirrorDecorationNote.today()

    var body: some View {
        Canvas { context, size in
            NookMirrorDecorationRenderer.draw(decorations, in: context, size: size, note: note)
        }
        .accessibilityHidden(true)
    }
}

/// The line the Instant Print frame writes under the picture: the day, in
/// the app's language. Read once when a picture is drawn, never on a clock.
enum NookMirrorDecorationNote {
    static func text(for date: Date, languageCode: String) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted, locale: Locale(identifier: languageCode))
        )
    }

    static func today() -> String {
        text(for: .now, languageCode: LanguageManager.shared.language.resolvedCode)
    }
}

/// The one place a decoration set is turned into drawing. The live mirror,
/// the picker's thumbnails and a photo all come through here.
enum NookMirrorDecorationRenderer {
    static func draw(
        _ decorations: NookMirrorDecorationSet,
        in context: GraphicsContext,
        size: CGSize,
        note: String = ""
    ) {
        guard size.width > 0, size.height > 0 else { return }
        if let frame = NookMirrorDesigns.frame(decorations.frameID) {
            frame.draw(NookDecorationPen(context: context, rect: CGRect(origin: .zero, size: size), note: note))
        }
        for sticker in decorations.stickers {
            draw(sticker, in: context, size: size)
        }
    }

    static func draw(_ sticker: NookMirrorSticker, in context: GraphicsContext, size: CGSize) {
        guard let design = NookMirrorDesigns.sticker(sticker.designID) else { return }
        let rect = NookMirrorDecorationLayout.rect(of: sticker, in: size)
        guard rect.width > 0 else { return }
        // Turn about the sticker's own center, then draw it there.
        var turned = context
        turned.translateBy(x: rect.midX, y: rect.midY)
        turned.rotate(by: .degrees(sticker.rotation))
        let local = CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height)
        design.draw(NookDecorationPen(context: turned, rect: local), design.wrapped(sticker.variant))
    }
}
