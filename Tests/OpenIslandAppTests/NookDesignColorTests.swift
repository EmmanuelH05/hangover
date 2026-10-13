import AppKit
import Foundation
import Testing
@testable import OpenIslandApp

/// Reading a typed color, turning it between forms, and writing it out.
@Suite struct NookDesignColorTests {
    private typealias Samples = NookDesignSamples

    private func parse(_ text: String) -> NookDesignColor? {
        NookDesignColorParser.parse(text)
    }

    // MARK: HEX

    @Test(arguments: ["#FF8800", "FF8800", "#ff8800", "ff8800", "  #Ff8800  ", "#ff8800;"])
    func sixDigitHexReadsWithAndWithoutTheHash(text: String) {
        #expect(parse(text) == Samples.orange)
    }

    @Test func shorthandHexDoublesEachDigit() {
        #expect(parse("#f80") == Samples.orange)
        #expect(parse("f80") == Samples.orange)
        #expect(parse("#FFF") == Samples.white)
        #expect(parse("#f80c") == NookDesignColor(red: 255, green: 136, blue: 0, alpha: 204))
        #expect(parse("0008") == NookDesignColor(red: 0, green: 0, blue: 0, alpha: 136))
    }

    @Test func eightDigitHexCarriesAlpha() {
        #expect(parse("#00000080") == Samples.scrim)
        #expect(parse("FF880000") == NookDesignColor(red: 255, green: 136, blue: 0, alpha: 0))
        #expect(parse("#FF8800FF")?.isOpaque == true)
    }

    // MARK: RGB

    @Test(arguments: [
        "rgb(255, 136, 0)", "rgb(255,136,0)", "RGB(255, 136, 0)", "rgb( 255 136 0 )",
        "rgb (255, 136, 0)", "255, 136, 0", "255 136 0", "rgb(100%, 53.33%, 0%)",
    ])
    func rgbReadsInEveryCommonForm(text: String) {
        #expect(parse(text) == Samples.orange)
    }

    @Test func rgbTakesAlphaAsADecimalOrAPercentage() {
        let half = NookDesignColor(red: 255, green: 136, blue: 0, alpha: 128)
        #expect(parse("rgba(255, 136, 0, 0.5)") == half)
        #expect(parse("rgb(255 136 0 / 50%)") == half)
        #expect(parse("rgb(255, 136, 0, .5)") == half)
        #expect(parse("255, 136, 0, 0.5") == half)
        #expect(parse("rgba(255, 136, 0, 1)") == Samples.orange)
        #expect(parse("rgba(255, 136, 0, 0)")?.alpha == 0)
    }

    // MARK: HSL

    @Test(arguments: [
        "hsl(32, 100%, 50%)", "hsl(32,100%,50%)", "HSL(32 100% 50%)", "hsl(32deg, 100%, 50%)",
        "hsl(32, 100, 50)", "hsl(392, 100%, 50%)", "hsl(-328, 100%, 50%)",
    ])
    func hslReadsInEveryCommonForm(text: String) {
        #expect(parse(text) == Samples.orange)
    }

    @Test func hslKnownColors() {
        #expect(parse("hsl(0, 100%, 50%)") == NookDesignColor(red: 255, green: 0, blue: 0))
        #expect(parse("hsl(120, 100%, 50%)") == NookDesignColor(red: 0, green: 255, blue: 0))
        #expect(parse("hsl(240, 100%, 50%)") == NookDesignColor(red: 0, green: 0, blue: 255))
        #expect(parse("hsl(210, 50%, 40%)") == NookDesignColor(red: 51, green: 102, blue: 153))
        #expect(parse("hsl(0, 0%, 100%)") == Samples.white)
        #expect(parse("hsl(77, 0%, 0%)") == NookDesignColor(red: 0, green: 0, blue: 0))
        #expect(parse("hsla(0, 0%, 100%, 0.25)") == NookDesignColor(red: 255, green: 255, blue: 255, alpha: 64))
        #expect(parse("hsl(0 0% 100% / 25%)") == NookDesignColor(red: 255, green: 255, blue: 255, alpha: 64))
    }

    // MARK: Bad input

    @Test(arguments: [
        "", "   ", "#", "#12", "#12345", "#1234567", "#123456789", "#GGGGGG", "ff88zz",
        "rgb(256, 0, 0)", "rgb(-1, 0, 0)", "rgb(1, 2)", "rgb(1, 2, 3, 4, 5)", "rgb(255, 136, 0",
        "rgb((1), 2, 3)", "rgb(1, 2, 3))", "rgbx(1, 2, 3)", "rgba(0, 0, 0, 1.5)", "rgba(0, 0, 0, 101%)",
        "rgb(101%, 0%, 0%)", "hsl(10, 101%, 50%)", "hsl(10, 50%)", "hsl(deg, 50%, 50%)", "hsl(10, -5%, 50%)",
        "red", "transparent", "1e3, 0, 0", "nan nan nan", "inf, 0, 0", "0x10 0 0", "1.2.3, 0, 0", "., 0, 0",
        "#ff8800 extra", "＃ｆｆ８８００", "ｆｆ８８００", "ff 88 0g", "255,,",
    ])
    func whatIsNotAColorIsRefused(text: String) {
        #expect(parse(text) == nil, "\(text) should not read as a color")
    }

    @Test func aChannelOutOfRangeIsRefusedAndNotClamped() {
        #expect(parse("300, 0, 0") == nil)
        #expect(parse("rgb(255.6, 0, 0)") == nil)
        #expect(parse("rgb(254.6, 0, 0)") == NookDesignColor(red: 255, green: 0, blue: 0))
    }

    @Test func textTooLongToBeAColorIsRefusedUnread() {
        let long = "#" + String(repeating: "f", count: NookDesignColorParser.maxLength)
        #expect(parse(long) == nil)
    }

    // MARK: Writing

    @Test func aColorWritesInEveryFormat() {
        #expect(Samples.orange.hex() == "#FF8800")
        #expect(Samples.orange.hex(includesHash: false) == "FF8800")
        #expect(Samples.orange.rgbText == "rgb(255, 136, 0)")
        #expect(Samples.orange.hslText == "hsl(32, 100%, 50%)")
        #expect(Samples.scrim.hex() == "#00000080")
        #expect(Samples.scrim.rgbText == "rgba(0, 0, 0, 0.5)")
        #expect(Samples.scrim.hslText == "hsla(0, 0%, 0%, 0.5)")
    }

    @Test func theCopyFormatsGiveTheirOwnText() {
        let texts = NookDesignColorFormat.allCases.map { $0.text(for: Samples.orange) }
        #expect(texts == ["#FF8800", "FF8800", "rgb(255, 136, 0)", "hsl(32, 100%, 50%)"])
    }

    @Test func steppingThroughTheFormatsComesBackToTheFirst() {
        var format = NookDesignColorFormat.hex
        var seen: [NookDesignColorFormat] = []
        for _ in NookDesignColorFormat.allCases {
            seen.append(format)
            format = format.next
        }
        #expect(seen == NookDesignColorFormat.allCases)
        #expect(format == .hex)
    }

    @Test func everyAlphaWritesAsTextThatReadsBackTheSame() {
        for alpha in UInt8.min...UInt8.max {
            let color = NookDesignColor(red: 10, green: 20, blue: 30, alpha: alpha)
            #expect(parse(color.rgbText) == color, "alpha \(alpha) wrote \(color.rgbText)")
            #expect(parse(color.hex()) == color)
        }
        #expect(NookDesignColor(red: 0, green: 0, blue: 0, alpha: 128).alphaText == "0.5")
        #expect(NookDesignColor(red: 0, green: 0, blue: 0, alpha: 0).alphaText == "0")
        #expect(NookDesignColor(red: 0, green: 0, blue: 0, alpha: 255).alphaText == "1")
    }

    // MARK: Conversion

    @Test func rgbToHslKnownValues() {
        let red = NookDesignColor(red: 255, green: 0, blue: 0).hsl
        #expect(red.hue == 0)
        #expect(red.saturation == 1)
        #expect(red.lightness == 0.5)

        let blue = NookDesignColor(red: 0, green: 0, blue: 255).hsl
        #expect(blue.hue == 240)

        let gray = NookDesignColor(red: 128, green: 128, blue: 128).hsl
        #expect(gray.saturation == 0)
        #expect(abs(gray.lightness - 0.502) < 0.001)

        #expect(Samples.white.hsl.lightness == 1)
        #expect(NookDesignColor(red: 0, green: 0, blue: 0).hsl.lightness == 0)
    }

    @Test func rgbToHslAndBackIsTheSameColor() {
        var checked = 0
        for red in stride(from: 0, through: 255, by: 17) {
            for green in stride(from: 0, through: 255, by: 17) {
                for blue in stride(from: 0, through: 255, by: 17) {
                    let color = NookDesignColor(red: UInt8(red), green: UInt8(green), blue: UInt8(blue))
                    let hsl = color.hsl
                    let back = NookDesignColor(hue: hsl.hue, saturation: hsl.saturation, lightness: hsl.lightness)
                    #expect(back == color, "\(color.hex()) came back as \(back.hex())")
                    checked += 1
                }
            }
        }
        #expect(checked == 4096)
    }

    @Test func aSystemColorIsTakenToEightBitSRGB() {
        let picked = NSColor(srgbRed: 1, green: 136.0 / 255, blue: 0, alpha: 1)
        #expect(NookDesignColor(nsColor: picked) == Samples.orange)

        // A wide color is brought into sRGB and kept in range.
        let wide = NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1)
        #expect(NookDesignColor(nsColor: wide)?.red == 255)
    }

    @Test func aColorIsSavedAsItsHexText() throws {
        let data = try JSONEncoder().encode([Samples.orange, Samples.scrim])
        #expect(String(decoding: data, as: UTF8.self) == "[\"#FF8800\",\"#00000080\"]")
        #expect(try JSONDecoder().decode([NookDesignColor].self, from: data) == [Samples.orange, Samples.scrim])

        // A file edited by hand may use any form the parser reads.
        let byHand = Data("[\"rgb(255, 136, 0)\", \"f80\"]".utf8)
        #expect(try JSONDecoder().decode([NookDesignColor].self, from: byHand) == [Samples.orange, Samples.orange])
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([NookDesignColor].self, from: Data("[\"teal-ish\"]".utf8))
        }
    }

    // MARK: The closed island's notice

    @Test func aColorTooDarkForThePillIsShownInWhite() {
        #expect(Samples.ink.noticeTint == Samples.white)
        #expect(NookDesignColor(red: 0, green: 0, blue: 0).noticeTint == Samples.white)
        #expect(Samples.orange.noticeTint == Samples.orange)
        // The tint never carries alpha.
        #expect(NookDesignColor(red: 255, green: 136, blue: 0, alpha: 10).noticeTint == Samples.orange)
    }

    @Test func theNoticeShowsWhatWasCopiedWhenItFits() {
        #expect(NookDesignKit.noticeText(for: Samples.orange, copied: "#FF8800") == "#FF8800")
        #expect(NookDesignKit.noticeText(for: Samples.orange, copied: "rgb(255, 136, 0)") == "rgb(255, 136, 0)")
        #expect(NookDesignKit.noticeText(for: Samples.orange, copied: "hsl(32, 100%, 50%)") == "hsl(32, 100%, 50%)")
        let long = "hsl(332, 100%, 50%)"
        #expect(long.count > 18)
        #expect(NookDesignKit.noticeText(for: Samples.orange, copied: long) == "#FF8800")
    }
}
