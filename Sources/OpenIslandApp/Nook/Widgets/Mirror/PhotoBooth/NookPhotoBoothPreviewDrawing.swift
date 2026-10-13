import CoreGraphics
import Foundation

/// What decides how one preview looks: the layout, the theme and the line
/// the strip prints. Two previews with the same key are the same picture.
/// This is what the cache is keyed by.
struct NookPhotoBoothPreviewKey: Hashable, Sendable {
    let layout: NookPhotoStripLayout.Kind
    let themeID: String
    /// The caption as the strip prints it, which is the theme's own line
    /// when nothing was typed. Two captions that print the same share a key.
    let caption: String

    /// Works the printed caption out the way a session does when it starts:
    /// the typed line when it prints something, otherwise the theme's own.
    init(layout: NookPhotoStripLayout.Kind, theme: NookPhotoStripTheme, typedCaption: String, defaultLine: String) {
        self.layout = layout
        themeID = theme.id
        let typed = NookPhotoStripComposer.printedCaption(typedCaption, theme: theme)
        caption = typed.isEmpty ? NookPhotoStripComposer.printedCaption(defaultLine, theme: theme) : typed
    }
}

/// The previews Settings shows for the layout and theme chosen now: one per
/// layout in the chosen theme, and one per theme in the chosen layout. The
/// tiles ask this for their key, and the request asks it for the lot, which
/// keeps the two from disagreeing about what is on screen.
struct NookPhotoBoothPreviewSet {
    let layout: NookPhotoStripLayout.Kind
    let theme: NookPhotoStripTheme
    /// The caption as typed, once typing has paused.
    let typedCaption: String
    /// What a theme prints when nothing is typed.
    let defaultLine: (NookPhotoStripTheme) -> String

    func key(layout: NookPhotoStripLayout.Kind, theme: NookPhotoStripTheme) -> NookPhotoBoothPreviewKey {
        NookPhotoBoothPreviewKey(layout: layout, theme: theme, typedCaption: typedCaption, defaultLine: defaultLine(theme))
    }

    /// A layout's tile: its strip in the chosen theme.
    func layoutTile(_ kind: NookPhotoStripLayout.Kind) -> NookPhotoBoothPreviewKey {
        key(layout: kind, theme: theme)
    }

    /// A theme's tile: its strip in the chosen layout.
    func themeTile(_ other: NookPhotoStripTheme) -> NookPhotoBoothPreviewKey {
        key(layout: layout, theme: other)
    }

    /// Every preview on screen, the layouts first. The chosen pair is in
    /// both groups and is listed twice but drawn once.
    var keys: [NookPhotoBoothPreviewKey] {
        NookPhotoStripLayout.Kind.allCases.map(layoutTile) + NookPhotoStripTheme.all.map(themeTile)
    }
}

/// Draws a preview: the strip a layout and theme make, small. It is made by
/// `NookPhotoStripComposer.bitmap`, the code that prints the real strip, on
/// four sample pictures made in code, and it goes through the gate every
/// composition goes through. No camera, no file and no network is touched,
/// and the same key always gives the same picture.
enum NookPhotoBoothPreviewDrawing {
    /// Pixels along the longest side of a preview.
    static let longestSide: CGFloat = 220
    /// The screen density the previews are made for.
    static let pixelsPerPoint: CGFloat = 2

    /// A fixed day and place for the date line: the preview is the same
    /// tomorrow, and the cache never has to age.
    private static let date = Date(timeIntervalSince1970: 1_791_600_420)
    private static let locale = Locale(identifier: "en_US")
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// Pixels to the point of the page, which brings its longest side to
    /// `longestSide`.
    static func scale(of layout: NookPhotoStripLayout) -> CGFloat {
        longestSide / max(layout.pageSize.width, layout.pageSize.height)
    }

    /// How large a preview shows on screen, in points.
    static func pointSize(of kind: NookPhotoStripLayout.Kind) -> CGSize {
        let layout = NookPhotoStripLayout.layout(kind)
        let scale = scale(of: layout)
        return CGSize(
            width: (layout.pageSize.width * scale).rounded() / pixelsPerPoint,
            height: (layout.pageSize.height * scale).rounded() / pixelsPerPoint
        )
    }

    /// What the strip is made from: the sample pictures, the key's layout,
    /// theme and printed caption, and the fixed date.
    static func input(for key: NookPhotoBoothPreviewKey) -> NookPhotoStripInput {
        let layout = NookPhotoStripLayout.layout(key.layout)
        return NookPhotoStripInput(
            pictures: NookPhotoBoothSamplePictures.pictures(for: layout),
            layout: layout,
            theme: NookPhotoStripTheme.theme(id: key.themeID),
            caption: key.caption,
            date: date,
            calendar: calendar,
            locale: locale
        )
    }

    /// The preview as a picture, or nil when Core Graphics cannot draw it.
    /// Waits its turn at the gate, behind any print, and runs off the main
    /// thread.
    static func image(
        for key: NookPhotoBoothPreviewKey,
        through gate: NookPhotoStripGate = .shared
    ) async -> NookPhotoBoothPreviewImage? {
        let input = input(for: key)
        return await gate.makePreview(input, scale: scale(of: input.layout))
    }
}

/// The four pictures every preview strip holds: soft gradients with a glow,
/// cut to the shape of each slot. They stand in for a person at the camera.
enum NookPhotoBoothSamplePictures {
    /// Pixels across. A picture takes up at most about 100 pixels of a
    /// preview, and this is about twice that.
    private static let width = 192

    /// Two colors of the sky and the color of the glow, one set per picture.
    private static let palettes: [(top: UInt32, bottom: UInt32, glow: UInt32)] = [
        (0xFFC59A, 0xD9667E, 0xFFF1D0),
        (0x7FD1C9, 0x3B6FB6, 0xE3FBFF),
        (0xC4A8F0, 0x5A4FB0, 0xFFE8FB),
        (0xF3DC8A, 0x6BAA6F, 0xFFFFE6),
    ]

    static func pictures(for layout: NookPhotoStripLayout) -> [NookPhotoBoothPicture] {
        layout.slots.indices.compactMap { index in
            let aspect = layout.aspect(ofSlot: index)
            let height = max(1, Int((CGFloat(width) / aspect).rounded()))
            return picture(palettes[index % palettes.count], pose: index, height: height)
                .map { NookPhotoBoothPicture(camera: $0, decorations: nil) }
        }
    }

    /// One picture: a diagonal gradient and a soft glow whose place moves
    /// with `pose`, which keeps four pictures from looking like one.
    private static func picture(
        _ palette: (top: UInt32, bottom: UInt32, glow: UInt32),
        pose: Int,
        height: Int
    ) -> CGImage? {
        guard let context = NookPhotoBoothImaging.bitmapContext(width: width, height: height),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let sky = CGGradient(
                  colorsSpace: space,
                  colors: [NookStripColor(palette.top).cgColor, NookStripColor(palette.bottom).cgColor] as CFArray,
                  locations: [0, 1]
              ),
              let glow = CGGradient(
                  colorsSpace: space,
                  colors: [NookStripColor(palette.glow, alpha: 0.85).cgColor, NookStripColor(palette.glow, alpha: 0).cgColor] as CFArray,
                  locations: [0, 1]
              ) else {
            return nil
        }
        let w = CGFloat(width)
        let h = CGFloat(height)
        context.drawLinearGradient(sky, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])
        let across: [CGFloat] = [0.3, 0.68, 0.45, 0.74]
        let center = CGPoint(x: w * across[pose % across.count], y: h * (pose % 2 == 0 ? 0.62 : 0.4))
        context.drawRadialGradient(
            glow,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: h * 0.7,
            options: []
        )
        return context.makeImage()
    }
}
