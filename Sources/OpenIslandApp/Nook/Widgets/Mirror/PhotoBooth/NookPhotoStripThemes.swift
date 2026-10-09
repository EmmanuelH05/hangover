import CoreGraphics
import Foundation

/// The strip themes the booth ships with. Each is this app's own design,
/// built from the parts in `NookPhotoStripTheme`. Type sizes are for the
/// classic strip's footer.
enum NookPhotoStripThemes {
    static let catalog: [NookPhotoStripTheme] = [
        classic, paperWhite, sepia, film, gingham, ribbon, chrome, arcade,
        notebook, terminal, goldenHour, frontPage, confetti, starlight, blueprint, scrapbook,
    ]

    /// Black card, white lines, black and white pictures, typewriter type.
    private static let classic = NookPhotoStripTheme(
        id: "classic",
        paper: .solid(NookStripColor(0x0B0B0C)),
        frame: NookStripFrame(border: NookStripLine(color: .white, width: 1.5)),
        treatment: .adjusted(saturation: 0, contrast: 1.15, brightness: 0.02, wash: nil),
        footer: NookStripFooter(
            captionFont: .named("AmericanTypewriter-Bold", fallback: .serif), captionSize: 11,
            captionInk: .white, captionCase: .upper, captionTracking: 1.5,
            dateFont: .named("AmericanTypewriter", fallback: .serif), dateSize: 7,
            dateInk: NookStripColor(0xFFFFFF, alpha: 0.7), dateFormat: "MMM dd yyyy", dateCase: .upper
        )
    )

    /// Off-white paper, hairlines, small quiet type on one line.
    private static let paperWhite = NookPhotoStripTheme(
        id: "paperWhite",
        paper: .solid(NookStripColor(0xFAFAF7)),
        frame: NookStripFrame(radius: 2, border: NookStripLine(color: NookStripColor(0x000000, alpha: 0.12), width: 0.5)),
        footer: NookStripFooter(
            captionFont: .named("HelveticaNeue-Medium"), captionSize: 8,
            captionInk: NookStripColor(0x1F1F24), captionCase: .lower, captionTracking: 1.2,
            dateFont: .named("HelveticaNeue-Light"), dateSize: 8,
            dateInk: NookStripColor(0x1F1F24, alpha: 0.6), dateFormat: "yyyy.MM.dd",
            alignment: .split
        )
    )

    /// Dark brown card with darker corners, cream lines, sepia pictures.
    private static let sepia = NookPhotoStripTheme(
        id: "sepia",
        paper: .solid(NookStripColor(0x2A1F17)),
        patterns: [.vignette(NookStripColor(0x000000, alpha: 0.35))],
        frame: NookStripFrame(radius: 1, border: NookStripLine(color: NookStripColor(0xE8D9BF), width: 2)),
        treatment: .sepia(intensity: 0.85, vignette: 0.4),
        footer: NookStripFooter(
            captionFont: .named("Baskerville-Italic", fallback: .serif), captionSize: 12,
            captionInk: NookStripColor(0xE8D9BF),
            dateFont: .named("Baskerville", fallback: .serif), dateSize: 7,
            dateInk: NookStripColor(0xE8D9BF, alpha: 0.7), dateFormat: "d MMMM yyyy", dateCase: .upper, dateTracking: 1
        )
    )

    /// A length of film: dark base, perforations, amber edge print.
    private static let film = NookPhotoStripTheme(
        id: "film",
        paper: .solid(NookStripColor(0x0A0A0A)),
        patterns: [.sprockets(NookStripColor(0xEDEAE0, alpha: 0.92))],
        frame: NookStripFrame(radius: 2),
        treatment: .adjusted(saturation: 0.9, contrast: 0.92, brightness: 0, wash: NookStripColor(0xFFB060, alpha: 0.06)),
        footer: NookStripFooter(
            captionFont: .named("CourierNewPS-BoldMT", fallback: .mono), captionSize: 8,
            captionInk: NookStripColor(0xFFB020), captionCase: .upper, captionTracking: 1,
            dateFont: .named("CourierNewPS-BoldMT", fallback: .mono), dateSize: 7,
            dateInk: NookStripColor(0xFFB020), dateFormat: "yy MM dd"
        )
    )

    /// Pink gingham, fat white borders, a heart either side of the caption.
    private static let gingham = NookPhotoStripTheme(
        id: "gingham",
        paper: .solid(NookStripColor(0xFFE3F0)),
        patterns: [.gingham(NookStripColor(0xFF9CC8, alpha: 0.35), band: 6, period: 12)],
        frame: NookStripFrame(radius: 8, border: NookStripLine(color: .white, width: 3)),
        treatment: .adjusted(saturation: 1.1, contrast: 1, brightness: 0.04, wash: NookStripColor(0xFF9CC8, alpha: 0.05)),
        footer: NookStripFooter(
            captionFont: .named("ArialRoundedMTBold"), captionSize: 11,
            captionInk: NookStripColor(0xFF4D8B),
            dateFont: .named("ArialRoundedMTBold"), dateSize: 7,
            dateInk: NookStripColor(0xFF4D8B, alpha: 0.7), dateFormat: "MM.dd.yy",
            plate: NookStripColor(0xFFFFFF, alpha: 0.92), plateRadius: 10,
            ornament: .hearts(NookStripColor(0xFF4D8B))
        )
    )

    /// Cream paper with pink pinstripes, each picture on a white card, a
    /// bow over a looping script.
    private static let ribbon = NookPhotoStripTheme(
        id: "ribbon",
        paper: .solid(NookStripColor(0xFFF6F0)),
        patterns: [.pinstripes(NookStripColor(0xF5C6D6, alpha: 0.6), width: 0.75, period: 6, start: 3)],
        frame: NookStripFrame(
            radius: 12,
            border: NookStripLine(color: NookStripColor(0xD98AA5), width: 1),
            mat: .white, matInset: 3
        ),
        treatment: .adjusted(saturation: 0.95, contrast: 0.95, brightness: 0, wash: NookStripColor(0xFFD9E6, alpha: 0.08)),
        footer: NookStripFooter(
            captionFont: .named("SnellRoundhand-Bold", fallback: .serif), captionSize: 15,
            captionInk: NookStripColor(0xB3476B),
            dateFont: .named("Didot-Italic", fallback: .serif), dateSize: 7,
            dateInk: NookStripColor(0xB3476B, alpha: 0.8), dateFormat: "MMMM d, yyyy",
            ornament: .bow(fill: NookStripColor(0xFF9CC8), accent: NookStripColor(0xFF6FA8), ink: NookStripColor(0xB3246B))
        )
    )

    /// Ice blue into lilac into pink, with glints and doubled borders.
    private static let chrome = NookPhotoStripTheme(
        id: "chrome",
        paper: .gradient([NookStripColor(0xB8F1FF), NookStripColor(0xC9B8FF), NookStripColor(0xFFB8E6)], stops: [0, 0.5, 1]),
        patterns: [.glints(NookStripColor(0xFFFFFF, alpha: 0.9))],
        frame: NookStripFrame(
            radius: 14,
            border: NookStripLine(color: .white, width: 2),
            outerLine: NookStripLine(color: NookStripColor(0x7A6BFF), width: 1)
        ),
        treatment: .adjusted(saturation: 1, contrast: 1.05, brightness: 0.06, wash: NookStripColor(0x7DD6FF, alpha: 0.06)),
        footer: NookStripFooter(
            captionFont: .named("Futura-CondensedExtraBold"), captionSize: 15,
            captionInk: NookStripColor(0x5B3FD1), captionCase: .upper,
            dateFont: .named("Futura-Medium"), dateSize: 7,
            dateInk: NookStripColor(0x5B3FD1), dateFormat: "MM/dd/yy"
        )
    )

    /// A game screen at night: a faint grid, cyan and pink lines, scanlines.
    private static let arcade = NookPhotoStripTheme(
        id: "arcade",
        paper: .solid(NookStripColor(0x0D0D1A)),
        patterns: [.grid(NookStripColor(0x19E3FF, alpha: 0.12), spacing: 8, line: 0.5)],
        frame: NookStripFrame(
            border: NookStripLine(color: NookStripColor(0x19E3FF), width: 2),
            outerLine: NookStripLine(color: NookStripColor(0xFF4FA3), width: 1), outerGap: 2,
            scanlines: NookStripColor(0x000000, alpha: 0.18)
        ),
        treatment: .adjusted(saturation: 1.25, contrast: 1.1, brightness: 0, wash: nil),
        footer: NookStripFooter(
            captionFont: .named("Menlo-Bold", fallback: .mono), captionSize: 9,
            captionInk: NookStripColor(0xFFE600), captionCase: .upper,
            dateFont: .named("Menlo-Regular", fallback: .mono), dateSize: 7,
            dateInk: NookStripColor(0x19E3FF), dateFormat: "yyyy-MM-dd",
            plate: NookStripColor(0x0D0D1A)
        )
    )

    /// A notebook page: ruled lines, taped pictures, marker handwriting.
    private static let notebook = NookPhotoStripTheme(
        id: "notebook",
        paper: .solid(NookStripColor(0xFFFDF5)),
        patterns: [.ruled(NookStripColor(0x9CC8FF, alpha: 0.6), period: 12, margin: NookStripColor(0xFF8FA3), marginX: 5)],
        frame: NookStripFrame(
            radius: 3,
            border: NookStripLine(color: NookStripColor(0x1F1F24), width: 1.5),
            tilt: 0.8,
            tape: NookStripColor(0xFFE94A, alpha: 0.75)
        ),
        footer: NookStripFooter(
            captionFont: .named("MarkerFelt-Wide"), captionSize: 13,
            captionInk: NookStripColor(0x1F1F24),
            dateFont: .named("Noteworthy-Bold"), dateSize: 8,
            dateInk: NookStripColor(0x4D7CFF), dateFormat: "EEE, MMM d",
            plate: NookStripColor(0xFFFDF5, alpha: 0.9)
        )
    )

    /// Green phosphor on black, each picture numbered like a log line.
    private static let terminal = NookPhotoStripTheme(
        id: "terminal",
        paper: .solid(NookStripColor(0x0D0D0F)),
        frame: NookStripFrame(
            radius: 4,
            border: NookStripLine(color: NookStripColor(0x4DFF7A, alpha: 0.7), width: 1),
            counter: NookStripColor(0x4DFF7A),
            counterPlate: NookStripColor(0x0D0D0F, alpha: 0.75)
        ),
        treatment: .duotone(dark: NookStripColor(0x06140B), light: NookStripColor(0x9DFFB8), contrast: 1.1),
        footer: NookStripFooter(
            captionFont: .named("Menlo-Bold", fallback: .mono), captionSize: 8,
            captionInk: NookStripColor(0x4DFF7A),
            dateFont: .named("Menlo-Regular", fallback: .mono), dateSize: 7,
            dateInk: NookStripColor(0x4DFF7A, alpha: 0.7), dateFormat: "yyyy-MM-dd HH:mm",
            alignment: .left
        )
    )

    /// Orange into pink into violet, soft white frames, lowercase type.
    private static let goldenHour = NookPhotoStripTheme(
        id: "goldenHour",
        paper: .gradient([NookStripColor(0xFF8A5C), NookStripColor(0xFF5FA8), NookStripColor(0x7A6BFF)], stops: [0, 0.55, 1]),
        frame: NookStripFrame(radius: 12, border: NookStripLine(color: NookStripColor(0xFFFFFF, alpha: 0.3), width: 3)),
        treatment: .adjusted(saturation: 1.1, contrast: 1, brightness: 0, wash: NookStripColor(0xFFB060, alpha: 0.1)),
        footer: NookStripFooter(
            captionFont: .named("AvenirNext-Heavy"), captionSize: 12,
            captionInk: .white, captionCase: .lower,
            dateFont: .named("AvenirNext-Medium"), dateSize: 7,
            dateInk: NookStripColor(0xFFFFFF, alpha: 0.85), dateFormat: "MMM d, yyyy"
        )
    )

    /// Newsprint: halftone dots, hard black and white, a headline under a
    /// double rule.
    private static let frontPage = NookPhotoStripTheme(
        id: "frontPage",
        paper: .solid(NookStripColor(0xF2EEE3)),
        patterns: [.halftone(NookStripColor(0x000000, alpha: 0.1), radius: 0.6, pitch: 4)],
        frame: NookStripFrame(border: NookStripLine(color: NookStripColor(0x111111), width: 0.75)),
        treatment: .adjusted(saturation: 0, contrast: 1.3, brightness: 0, wash: nil),
        footer: NookStripFooter(
            captionFont: .named("Didot-Bold", fallback: .serif), captionSize: 13,
            captionInk: NookStripColor(0x111111), captionCase: .upper,
            dateFont: .named("Georgia-Italic", fallback: .serif), dateSize: 6.5,
            dateInk: NookStripColor(0x111111), dateFormat: "EEEE, MMMM d, yyyy",
            plate: NookStripColor(0xF2EEE3),
            ornament: .doubleRule(NookStripColor(0x111111))
        )
    )

    /// White paper after a party.
    private static let confetti = NookPhotoStripTheme(
        id: "confetti",
        paper: .solid(NookStripColor(0xFFFDF8)),
        patterns: [.confetti(
            [NookStripColor(0xFF5A5F), NookStripColor(0xFFC53D), NookStripColor(0x3DCCB4), NookStripColor(0x5B8DEF), NookStripColor(0xB57BEE)],
            count: 150, seed: 7
        )],
        frame: NookStripFrame(radius: 5, border: NookStripLine(color: .white, width: 2.5)),
        footer: NookStripFooter(
            captionFont: .system(.rounded), captionSize: 11,
            captionInk: NookStripColor(0x2B2B2B),
            dateFont: .system(.rounded, bold: false), dateSize: 7,
            dateInk: NookStripColor(0x6E6E6E), dateFormat: "MMMM d, yyyy",
            plate: NookStripColor(0xFFFDF8, alpha: 0.94), plateRadius: 8
        )
    )

    /// A night sky that fades to violet, with sparkles.
    private static let starlight = NookPhotoStripTheme(
        id: "starlight",
        paper: .gradient([NookStripColor(0x141A45), NookStripColor(0x4B2C73)], stops: [0, 1]),
        patterns: [.sparkles(NookStripColor(0xFFF2B0, alpha: 0.9), count: 70, seed: 11)],
        frame: NookStripFrame(radius: 7, border: NookStripLine(color: NookStripColor(0xFFF2B0), width: 1)),
        footer: NookStripFooter(
            captionFont: .system(.serif), captionSize: 12,
            captionInk: NookStripColor(0xFFF6CF),
            dateFont: .system(.serif, bold: false), dateSize: 7,
            dateInk: NookStripColor(0xC9BDF2), dateFormat: "MMMM d, yyyy",
            plate: NookStripColor(0x2A1F57, alpha: 0.85), plateRadius: 6
        )
    )

    /// A blueprint: one blue ink on a fine white grid.
    private static let blueprint = NookPhotoStripTheme(
        id: "blueprint",
        paper: .solid(NookStripColor(0x1B4A9A)),
        patterns: [.grid(NookStripColor(0xFFFFFF, alpha: 0.22), spacing: 6, line: 0.3)],
        frame: NookStripFrame(border: NookStripLine(color: NookStripColor(0xEAF2FF), width: 0.9)),
        treatment: .duotone(dark: NookStripColor(0x0E2C63), light: NookStripColor(0xEAF2FF), contrast: 1.05),
        footer: NookStripFooter(
            captionFont: .system(.mono), captionSize: 8.5,
            captionInk: NookStripColor(0xEAF2FF), captionCase: .upper, captionTracking: 1.2,
            dateFont: .system(.mono, bold: false), dateSize: 7,
            dateInk: NookStripColor(0xB9D4FF), dateFormat: "yyyy-MM-dd",
            plate: NookStripColor(0x1B4A9A)
        )
    )

    /// Brown paper with each picture on a white card, like a page from a
    /// scrapbook.
    private static let scrapbook = NookPhotoStripTheme(
        id: "scrapbook",
        paper: .solid(NookStripColor(0xC8A57A)),
        patterns: [.halftone(NookStripColor(0x8E6E48, alpha: 0.2), radius: 0.4, pitch: 5)],
        frame: NookStripFrame(
            radius: 1,
            border: NookStripLine(color: NookStripColor(0xE6DFD0), width: 0.5),
            mat: NookStripColor(0xFDFBF5), matInset: 4,
            tilt: 0.6,
            tape: NookStripColor(0xF4F0E4, alpha: 0.8)
        ),
        footer: NookStripFooter(
            captionFont: .named("BradleyHandITCTT-Bold"), captionSize: 13,
            captionInk: NookStripColor(0x3E2A17),
            dateFont: .named("BradleyHandITCTT-Bold"), dateSize: 8,
            dateInk: NookStripColor(0x5E4630), dateFormat: "MMMM d, yyyy"
        )
    )
}
