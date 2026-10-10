import CoreGraphics
import CoreText
import Foundation

/// Everything one strip is made from.
struct NookPhotoStripInput: Sendable {
    var pictures: [NookPhotoBoothPicture]
    var layout: NookPhotoStripLayout
    var theme: NookPhotoStripTheme
    var caption: String
    var date: Date
    var calendar: Calendar = .current
    var locale: Locale = .current
}

/// Draws a strip. The same drawing makes the PDF that is saved and the
/// picture of it shown on screen, which keeps the two from drifting apart.
/// Pure: the same input always gives the same strip.
enum NookPhotoStripComposer {
    /// Longest caption that is printed. Longer text is cut here.
    static let maxCaptionLength = 60

    /// The strip as a one-page PDF at its real size.
    static func pdf(_ input: NookPhotoStripInput) -> Data? {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: input.layout.pageSize)
        let info = [
            kCGPDFContextCreator: "Hangover",
            kCGPDFContextTitle: "Photo booth strip",
        ] as CFDictionary
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info) else {
            return nil
        }
        context.beginPDFPage(nil)
        draw(input, in: context, compactPictures: true)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    /// The strip as a picture, `scale` pixels to the point.
    static func bitmap(_ input: NookPhotoStripInput, scale: CGFloat) -> CGImage? {
        let page = input.layout.pageSize
        let width = Int((page.width * scale).rounded())
        let height = Int((page.height * scale).rounded())
        guard width > 0, height > 0,
              let context = NookPhotoBoothImaging.bitmapContext(width: width, height: height) else {
            return nil
        }
        context.scaleBy(x: scale, y: scale)
        draw(input, in: context, compactPictures: false)
        return context.makeImage()
    }

    /// The caption as it is printed: one line of text with no line breaks
    /// of its own, trimmed, cut to length and cased the theme's way.
    static func printedCaption(_ caption: String, theme: NookPhotoStripTheme) -> String {
        let flat = caption
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return theme.footer.captionCase.apply(String(flat.prefix(maxCaptionLength)))
    }

    /// Where to draw a picture to cover a rectangle without stretching.
    static func fillRect(for image: CGImage, covering rect: CGRect) -> CGRect {
        guard image.width > 0, image.height > 0, rect.width > 0, rect.height > 0 else { return rect }
        let scale = max(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
        let width = CGFloat(image.width) * scale
        let height = CGFloat(image.height) * scale
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }

    // MARK: - Page

    /// Draws the page. A PDF or bitmap context starts with its origin at
    /// the bottom left; this turns it over first, which lets every number
    /// below be measured from the top left like the layouts are.
    private static func draw(_ input: NookPhotoStripInput, in context: CGContext, compactPictures: Bool) {
        let layout = input.layout
        let theme = input.theme
        let page = CGRect(origin: .zero, size: layout.pageSize)

        context.saveGState()
        context.translateBy(x: 0, y: page.height)
        context.scaleBy(x: 1, y: -1)
        context.clip(to: page)

        drawPaper(theme.paper, in: page, context: context)
        for pattern in theme.patterns {
            context.saveGState()
            NookPhotoStripPatterns.draw(pattern, layout: layout, context: context)
            context.restoreGState()
        }
        for (index, slot) in layout.slots.enumerated() {
            let picture = index < input.pictures.count ? input.pictures[index] : nil
            drawSlot(
                picture,
                index: index,
                count: layout.slots.count,
                slot: slot,
                theme: theme,
                context: context,
                compact: compactPictures
            )
        }
        drawFooter(input, context: context)
        drawWordmark(input, context: context)
        context.restoreGState()
    }

    private static func drawPaper(_ paper: NookStripPaper, in page: CGRect, context: CGContext) {
        switch paper {
        case let .solid(color):
            context.setFillColor(color.cgColor)
            context.fill(page)
        case let .gradient(colors, stops):
            guard colors.count == stops.count, colors.count > 1,
                  let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let gradient = CGGradient(
                      colorsSpace: space,
                      colors: colors.map(\.cgColor) as CFArray,
                      locations: stops
                  ) else {
                context.setFillColor((colors.first ?? .white).cgColor)
                context.fill(page)
                return
            }
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: page.midX, y: page.minY),
                end: CGPoint(x: page.midX, y: page.maxY),
                options: []
            )
        }
    }

    // MARK: - Pictures

    private static func drawSlot(
        _ picture: NookPhotoBoothPicture?,
        index: Int,
        count: Int,
        slot: CGRect,
        theme: NookPhotoStripTheme,
        context: CGContext,
        compact: Bool
    ) {
        let frame = theme.frame
        let slotShape = rounded(slot, frame.radius)
        var pictureRect = slot
        var pictureRadius = frame.radius
        if let mat = frame.mat {
            context.addPath(slotShape)
            context.setFillColor(mat.cgColor)
            context.fillPath()
            pictureRect = slot.insetBy(dx: frame.matInset, dy: frame.matInset)
            pictureRadius = max(0, frame.radius - 2)
        }

        context.saveGState()
        context.addPath(rounded(pictureRect, pictureRadius))
        context.clip()
        if let picture {
            let developed = NookPhotoBoothImaging.treated(picture.camera, theme.treatment) ?? picture.camera
            let image = compact ? (NookPhotoBoothImaging.jpegBacked(developed) ?? developed) : developed
            context.interpolationQuality = .high
            drawImage(image, in: fillRect(for: image, covering: pictureRect), context: context)
            if let decorations = picture.decorations {
                drawImage(decorations, in: pictureRect, context: context)
            }
        } else {
            // A slot with no picture prints as an empty frame.
            context.setFillColor(NookStripColor(0x808080, alpha: 0.25).cgColor)
            context.fill(pictureRect)
        }
        if let scanlines = frame.scanlines {
            context.setStrokeColor(scanlines.cgColor)
            context.setLineWidth(0.35)
            for y in stride(from: pictureRect.minY + 1, to: pictureRect.maxY, by: 2) {
                context.move(to: CGPoint(x: pictureRect.minX, y: y))
                context.addLine(to: CGPoint(x: pictureRect.maxX, y: y))
            }
            context.strokePath()
        }
        if let ink = frame.counter {
            drawCounter("\(index + 1)/\(count)", ink: ink, plate: frame.counterPlate, in: pictureRect, context: context)
        }
        context.restoreGState()

        // The border may sit a little askew. The picture never does.
        let turn = frame.tilt * (index % 2 == 0 ? 1 : -1) * .pi / 180
        context.saveGState()
        context.translateBy(x: slot.midX, y: slot.midY)
        context.rotate(by: turn)
        context.translateBy(x: -slot.midX, y: -slot.midY)
        if let border = frame.border, border.width > 0 {
            context.addPath(slotShape)
            context.setStrokeColor(border.color.cgColor)
            context.setLineWidth(border.width)
            context.strokePath()
        }
        if let outer = frame.outerLine, outer.width > 0 {
            let reach = (frame.border?.width ?? 0) / 2 + frame.outerGap + outer.width / 2
            context.addPath(rounded(slot.insetBy(dx: -reach, dy: -reach), frame.radius + reach))
            context.setStrokeColor(outer.color.cgColor)
            context.setLineWidth(outer.width)
            context.strokePath()
        }
        context.restoreGState()

        if let tape = frame.tape {
            let degrees: CGFloat = index % 2 == 0 ? -8 : 6
            context.saveGState()
            context.translateBy(x: slot.midX, y: slot.minY)
            context.rotate(by: degrees * .pi / 180)
            context.setFillColor(tape.cgColor)
            context.fill(CGRect(x: -11, y: -3.5, width: 22, height: 7))
            context.restoreGState()
        }
    }

    private static func drawCounter(
        _ text: String,
        ink: NookStripColor,
        plate: NookStripColor?,
        in picture: CGRect,
        context: CGContext
    ) {
        let pill = CGRect(x: picture.minX + 3, y: picture.maxY - 3 - 8, width: 20, height: 8)
        if let plate {
            context.addPath(rounded(pill, 4))
            context.setFillColor(plate.cgColor)
            context.fillPath()
        }
        drawText(
            text,
            font: .named("Menlo-Bold", fallback: .mono),
            maxSize: 5.5,
            color: ink.cgColor,
            tracking: 0,
            alignment: .center,
            in: pill,
            context: context
        )
    }

    // MARK: - Footer

    private static func drawFooter(_ input: NookPhotoStripInput, context: CGContext) {
        let layout = input.layout
        let footer = input.theme.footer
        let caption = printedCaption(input.caption, theme: input.theme)
        let date = footer.dateText(for: input.date, calendar: input.calendar, locale: input.locale)
        let captionSize = footer.captionSize * layout.captionScale
        let dateSize = footer.dateSize * layout.dateScale

        if let plate = footer.plate {
            let inset: CGFloat = layout.footer.height < 30 ? 1 : 4
            let box = layout.footer.insetBy(dx: inset, dy: inset)
            context.addPath(rounded(box, min(footer.plateRadius, box.height / 2)))
            context.setFillColor(plate.cgColor)
            context.fillPath()
        }
        if case let .doubleRule(color) = footer.ornament {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(0.5)
            for offset in [CGFloat(1), 3] {
                context.move(to: CGPoint(x: layout.footer.minX + 2, y: layout.footer.minY + offset))
                context.addLine(to: CGPoint(x: layout.footer.maxX - 2, y: layout.footer.minY + offset))
            }
            context.strokePath()
        }

        // A split footer shares one line. The caption strip has room to
        // stack, which is what its big caption is for.
        let onOneLine = layout.footerStyle == .inline || (footer.alignment == .split && layout.kind != .caption)
        if onOneLine {
            // Caption at the left, date at the right, sharing one line.
            let line = layout.footer.insetBy(dx: 7, dy: 2)
            let dateWidth = min(line.width * 0.5, lineWidth(date, font: footer.dateFont, size: dateSize, tracking: footer.dateTracking) + 2)
            let dateBox = CGRect(x: line.maxX - dateWidth, y: line.minY, width: dateWidth, height: line.height)
            drawText(date, font: footer.dateFont, maxSize: dateSize, color: footer.dateInk.cgColor,
                     tracking: footer.dateTracking, alignment: .right, in: dateBox, context: context)
            let captionBox = CGRect(x: line.minX, y: line.minY, width: max(0, line.width - dateWidth - 6), height: line.height)
            drawText(caption, font: footer.captionFont, maxSize: captionSize, color: footer.captionInk.cgColor,
                     tracking: footer.captionTracking, alignment: .left, in: captionBox, context: context)
            return
        }

        let alignment: CTTextAlignment = footer.alignment == .center ? .center : .left
        var captionBox = layout.captionBox.insetBy(dx: 5, dy: 1)
        let dateBox = layout.dateBox.insetBy(dx: 5, dy: 0.5)
        if case let .bow(fill, accent, ink) = footer.ornament {
            // The bow takes the top of the caption's room.
            let width: CGFloat = 13 * min(layout.captionScale, 1.4)
            NookPhotoStripPatterns.drawBow(
                knot: CGPoint(x: captionBox.midX, y: captionBox.minY + width * 0.2),
                width: width, fill: fill, accent: accent, ink: ink, context: context
            )
            let taken = width * 0.7
            captionBox = CGRect(x: captionBox.minX, y: captionBox.minY + taken, width: captionBox.width, height: captionBox.height - taken)
        }
        if caption.isEmpty {
            // With no caption the date has the footer to itself.
            drawText(date, font: footer.dateFont, maxSize: dateSize * 1.3, color: footer.dateInk.cgColor,
                     tracking: footer.dateTracking, alignment: alignment, in: captionBox.union(dateBox), context: context)
            return
        }
        var heartRoom: CGFloat = 0
        if case .hearts = footer.ornament { heartRoom = 13 }
        let used = drawText(
            caption, font: footer.captionFont, maxSize: captionSize, color: footer.captionInk.cgColor,
            tracking: footer.captionTracking, alignment: alignment,
            in: captionBox.insetBy(dx: heartRoom, dy: 0), context: context
        )
        if case let .hearts(color) = footer.ornament, let used, used.lines == 1 {
            context.setFillColor(color.cgColor)
            let reach = used.width / 2 + 6 + 3.5
            for side in [CGFloat(-1), 1] {
                context.addPath(NookPhotoStripPatterns.heart(center: CGPoint(x: captionBox.midX + side * reach, y: used.midY), width: 7))
            }
            context.fillPath()
        }
        drawText(date, font: footer.dateFont, maxSize: dateSize, color: footer.dateInk.cgColor,
                 tracking: footer.dateTracking, alignment: alignment, in: dateBox, context: context)
    }

    // MARK: - Wordmark

    /// The app's name as it is printed on every strip: what it says, where
    /// it sits and the ink. Kept apart from the drawing so a test can read it.
    struct Wordmark: Equatable {
        var text: String
        var rect: CGRect
        var color: NookStripColor
    }

    /// Largest the name is set. It shrinks to fit a narrow band.
    static let wordmarkSize: CGFloat = 6

    static func wordmark(layout: NookPhotoStripLayout, theme: NookPhotoStripTheme) -> Wordmark {
        Wordmark(text: AppBrand.name, rect: layout.wordmarkBox, color: theme.footer.captionInk.opacity(1))
    }

    /// Small and centered under the footer, in the theme's caption ink. Every
    /// strip gets it, whatever the theme, layout or file it is saved as.
    private static func drawWordmark(_ input: NookPhotoStripInput, context: CGContext) {
        let mark = wordmark(layout: input.layout, theme: input.theme)
        drawText(
            mark.text,
            font: input.theme.footer.captionFont,
            maxSize: wordmarkSize,
            color: mark.color.cgColor,
            tracking: 1,
            alignment: .center,
            in: mark.rect,
            context: context
        )
    }

    // MARK: - Text and pictures in a turned-over context

    /// What a block of text took up once set.
    private struct TextExtent {
        var width: CGFloat
        var midY: CGFloat
        var lines: Int
    }

    /// Sets text in a box, as large as fits up to `maxSize`. Long text
    /// wraps and shrinks, and at the smallest size it is cut to what the
    /// box holds.
    @discardableResult
    private static func drawText(
        _ text: String,
        font: NookStripFont,
        maxSize: CGFloat,
        color: CGColor,
        tracking: CGFloat,
        alignment: CTTextAlignment,
        in rect: CGRect,
        context: CGContext
    ) -> TextExtent? {
        guard !text.isEmpty, rect.width > 1, rect.height > 1 else { return nil }
        let minSize = max(3.5, maxSize * 0.35)
        var size = maxSize
        var string = attributed(text, font: font, size: size, color: color, tracking: tracking, alignment: alignment)
        var setter = CTFramesetterCreateWithAttributedString(string)
        var height = fittedHeight(setter, length: string.length, width: rect.width)
        while height == nil || height! > rect.height, size > minSize {
            size = max(minSize, size * 0.92)
            string = attributed(text, font: font, size: size, color: color, tracking: tracking, alignment: alignment)
            setter = CTFramesetterCreateWithAttributedString(string)
            height = fittedHeight(setter, length: string.length, width: rect.width)
        }
        let blockHeight = min(rect.height, ((height ?? rect.height) + 0.5).rounded(.up))
        let box = CGRect(x: rect.minX, y: rect.midY - blockHeight / 2, width: rect.width, height: blockHeight)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: box, transform: nil), nil)

        // Core Text draws upward. Turning the context over about the
        // box's middle stands the text back up in the same place.
        context.saveGState()
        context.translateBy(x: 0, y: box.minY + box.maxY)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.restoreGState()

        let lines = (CTFrameGetLines(frame) as? [CTLine]) ?? []
        let widest = lines.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }.max() ?? 0
        return TextExtent(width: widest, midY: box.midY, lines: lines.count)
    }

    /// Draws a picture the right way up in the turned-over context.
    private static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    private static func lineWidth(_ text: String, font: NookStripFont, size: CGFloat, tracking: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let string = attributed(text, font: font, size: size, color: CGColor(gray: 0, alpha: 1), tracking: tracking, alignment: .left)
        return CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(string), nil, nil, nil))
    }

    /// Height the text needs at this width, or nil when a single word is
    /// wider than the box and the text cannot be set whole.
    private static func fittedHeight(_ setter: CTFramesetter, length: Int, width: CGFloat) -> CGFloat? {
        var fit = CFRange()
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            setter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: width, height: .greatestFiniteMagnitude),
            &fit
        )
        guard fit.length >= length, size.width <= width + 0.5 else { return nil }
        return size.height
    }

    private static func attributed(
        _ text: String,
        font: NookStripFont,
        size: CGFloat,
        color: CGColor,
        tracking: CGFloat,
        alignment: CTTextAlignment
    ) -> NSAttributedString {
        var alignment = alignment
        let paragraph = withUnsafePointer(to: &alignment) { pointer in
            var setting = CTParagraphStyleSetting(
                spec: .alignment,
                valueSize: MemoryLayout<CTTextAlignment>.size,
                value: pointer
            )
            return CTParagraphStyleCreate(&setting, 1)
        }
        // Core Text reads its own keys here, not AppKit's.
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font.font(size: size),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTKernAttributeName as String): tracking,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph,
        ]
        return NSAttributedString(string: text, attributes: attributes)
    }

    private static func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
        let fitted = max(0, min(radius, min(rect.width, rect.height) / 2))
        return CGPath(roundedRect: rect, cornerWidth: fitted, cornerHeight: fitted, transform: nil)
    }
}
