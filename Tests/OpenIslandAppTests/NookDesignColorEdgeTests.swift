import AppKit
import Foundation
import Testing
@testable import OpenIslandApp

/// The edges of typing and pasting a color: input that is empty, odd,
/// too long, out of range, written in mixed case, or see-through. The
/// plain cases are in `NookDesignColorTests`.
@Suite struct NookDesignColorEdgeTests {
    private typealias Samples = NookDesignSamples

    private func parse(_ text: String) -> NookDesignColor? {
        NookDesignColorParser.parse(text)
    }

    // MARK: Empty and whitespace

    @Test(arguments: [
        "", " ", "\t", "\n", "\r\n", " \t\n ", "\u{00A0}", ";", " ; ", ";;", "#;", "# ", "()", "rgb()", "hsl()", ",", ", ,", "/",
    ])
    func nothingButBlanksAndPunctuationIsNotAColor(text: String) {
        #expect(parse(text) == nil, "\(text.debugDescription)")
    }

    @Test(arguments: [
        "\n#f80\n", "\t#f80\t", "\r\n#f80\r\n", "\u{00A0}#f80\u{00A0}", " #f80 ; ", "#f80 ;",
        // A zero width space at either end is dropped with the blanks. One inside is not.
        "\u{200B}#f80", "#f80\u{200B}",
    ])
    func blanksAroundAColorAreIgnored(text: String) {
        #expect(parse(text) == Samples.orange)
    }

    @Test func onlyOneClosingSemicolonIsDropped() {
        #expect(parse("#f80;") == Samples.orange)
        #expect(parse("#f80;;") == nil)
        #expect(parse(";#f80") == nil)
        #expect(parse("rgb(255, 136, 0);") == Samples.orange)
    }

    @Test(arguments: [
        "rgb(255,\t136,\t0)", "rgb(255,\n136,\n0)", "rgb(255,\r\n 136,\r\n 0)", "rgb(255,\u{00A0}136,\u{00A0}0)",
        "255\t136\t0", "255\n136\n0", "255\u{00A0}136\u{00A0}0", "hsl(32,\t100%,\t50%)", "hsl(32,\u{00A0}100%,\u{00A0}50%)",
    ])
    func anyKindOfBlankSeparatesTheNumbers(text: String) {
        // Text copied from a web page or a design file often carries tabs,
        // line breaks and no-break spaces where a typist would use a space.
        #expect(parse(text) == Samples.orange, "\(text.debugDescription)")
    }

    // MARK: HEX

    @Test(arguments: ["#FF8800", "#ff8800", "#Ff8800", "#fF8800", "#FF8800", "FF8800", "ff8800", "Ff8800"])
    func hexInAnyCaseIsTheSameColor(text: String) {
        #expect(parse(text) == Samples.orange)
    }

    @Test func shorthandAndLongHexInMixedCase() {
        #expect(parse("#F80") == Samples.orange)
        #expect(parse("#f80C") == NookDesignColor(red: 255, green: 136, blue: 0, alpha: 204))
        #expect(parse("#F80c") == NookDesignColor(red: 255, green: 136, blue: 0, alpha: 204))
        #expect(parse("#Ff8800Cc") == NookDesignColor(red: 255, green: 136, blue: 0, alpha: 204))
        #expect(parse("#FF8800CC") == parse("#ff8800cc"))
    }

    @Test func hexAtTheEdgesOfTheByteRange() {
        #expect(parse("#000") == NookDesignColor(red: 0, green: 0, blue: 0))
        #expect(parse("#fff") == Samples.white)
        #expect(parse("#000000") == NookDesignColor(red: 0, green: 0, blue: 0))
        #expect(parse("#ffffff") == Samples.white)
        #expect(parse("#0000") == NookDesignColor(red: 0, green: 0, blue: 0, alpha: 0))
        #expect(parse("#ffff") == Samples.white)
        #expect(parse("#00000000") == NookDesignColor(red: 0, green: 0, blue: 0, alpha: 0))
        #expect(parse("#ffffffff") == Samples.white)
        #expect(parse("#fff0") == NookDesignColor(red: 255, green: 255, blue: 255, alpha: 0))
    }

    @Test func shorthandEqualsItsLongForm() {
        for digits in ["000", "123", "abc", "f80", "fff", "0f0", "9a1"] {
            let long = digits.map { "\($0)\($0)" }.joined()
            #expect(parse("#" + digits) == parse("#" + long), "\(digits)")
        }
    }

    @Test(arguments: [
        "#", "##", "##fff", "#-fff", "#+fff", "# fff", "#ff", "#fffff", "#fffffff", "#fffffffff", "0xfff", "0xff8800", "&hff8800",
        "#ff88001", "#gg0000", "#ff880g", "#ff 88 00", "#ff-88-00", "#ff,88,00", "ff8800ff8800", "\\#fff",
        "#f\u{200B}ff", "#ｆｆｆ", "#٠٠٠", "#🎨", "🎨",
    ])
    func oddHexIsRefused(text: String) {
        #expect(parse(text) == nil, "\(text.debugDescription)")
    }

    // MARK: Out of range

    @Test(arguments: [
        "rgb(256, 0, 0)", "rgb(0, 256, 0)", "rgb(0, 0, 256)", "rgb(255.5, 0, 0)", "rgb(1000, 1000, 1000)",
        "rgb(100000000000, 0, 0)", "rgb(1000000000000, 0, 0)", "rgb(101%, 0%, 0%)", "rgb(0%, 100.01%, 0%)",
        "rgba(0, 0, 0, 1.0001)", "rgba(0, 0, 0, 2)", "rgba(0, 0, 0, 100.1%)", "rgba(0, 0, 0, 255)",
        "hsl(0, 101%, 50%)", "hsl(0, 100.5%, 50%)", "hsl(0, 100%, 101%)", "hsl(0, 50%, 100.01%)", "hsla(0, 50%, 50%, 1.5)",
    ])
    func aValueOutOfRangeIsRefusedWhicheverChannelItIsIn(text: String) {
        #expect(parse(text) == nil, "\(text)")
    }

    @Test func theLastValueInRangeIsTakenAndTheNextIsNot() {
        #expect(parse("rgb(255, 255, 255)") == Samples.white)
        #expect(parse("rgb(0, 0, 0)") == NookDesignColor(red: 0, green: 0, blue: 0))
        #expect(parse("rgb(100%, 100%, 100%)") == Samples.white)
        #expect(parse("rgb(0%, 0%, 0%)") == NookDesignColor(red: 0, green: 0, blue: 0))
        #expect(parse("rgba(0, 0, 0, 1)")?.isOpaque == true)
        #expect(parse("rgba(0, 0, 0, 100%)")?.isOpaque == true)
        #expect(parse("hsl(0, 100%, 100%)") == Samples.white)
        #expect(parse("hsl(0, 0%, 0%)") == NookDesignColor(red: 0, green: 0, blue: 0))
    }

    // MARK: Negative and signed numbers

    @Test(arguments: [
        "rgb(-1, 0, 0)", "rgb(0, -1, 0)", "rgb(0, 0, -1)", "rgb(-0.4, 0, 0)", "rgb(-1%, 0%, 0%)",
        "rgba(0, 0, 0, -0.1)", "rgba(0, 0, 0, -1%)", "hsl(0, -1%, 50%)", "hsl(0, 50%, -1%)", "hsla(0, 50%, 50%, -0.5)",
        "-1, 0, 0", "rgb(--1, 0, 0)", "rgb(+-1, 0, 0)", "rgb(1-, 0, 0)", "rgb(-, 0, 0)", "rgb(+, 0, 0)",
    ])
    func aNegativeNumberIsRefusedWhereItMakesNoSense(text: String) {
        #expect(parse(text) == nil, "\(text)")
    }

    @Test func minusZeroAndPlusSignsAreJustNumbers() {
        let black = NookDesignColor(red: 0, green: 0, blue: 0)
        #expect(parse("rgb(-0, -0, -0)") == black)
        #expect(parse("rgb(-0%, -0%, -0%)") == black)
        #expect(parse("rgba(0, 0, 0, -0)")?.alpha == 0)
        #expect(parse("rgb(+255, +136, +0)") == Samples.orange)
        #expect(parse("+255 +136 +0") == Samples.orange)
    }

    @Test func aNegativeHueWrapsAroundTheWheel() {
        let red = NookDesignColor(red: 255, green: 0, blue: 0)
        let blue = NookDesignColor(red: 0, green: 0, blue: 255)
        #expect(parse("hsl(-0, 100%, 50%)") == red)
        #expect(parse("hsl(-360, 100%, 50%)") == red)
        #expect(parse("hsl(-120, 100%, 50%)") == blue)
        #expect(parse("hsl(-480, 100%, 50%)") == blue)
        #expect(parse("hsl(-30deg, 100%, 50%)") == parse("hsl(330, 100%, 50%)"))
        #expect(parse("hsl(-0.5, 100%, 50%)") == parse("hsl(359.5, 100%, 50%)"))
    }

    // MARK: Percent and degree forms

    @Test func percentChannelsRoundToTheNearestByte() {
        #expect(parse("rgb(50%, 50%, 50%)") == NookDesignColor(red: 128, green: 128, blue: 128))
        #expect(parse("rgb(0.2%, 0%, 0%)")?.red == 1)
        #expect(parse("rgb(0.1%, 0%, 0%)")?.red == 0)
        #expect(parse("rgb(100%, 50, 0%)") == NookDesignColor(red: 255, green: 50, blue: 0))
    }

    @Test(arguments: [
        "rgb(%, 0, 0)", "rgb(5%%, 0, 0)", "rgb(%5, 0, 0)", "rgb(5 %, 0, 0)", "hsl(32%, 100%, 50%)", "hsl(32, %, 50%)",
        "hsl(32 deg, 100%, 50%)", "hsl(32degrees, 100%, 50%)", "hsl(32dg, 100%, 50%)", "hsl(deg32, 100%, 50%)",
        "hsl(0.5turn, 100%, 50%)", "hsl(100grad, 100%, 50%)", "hsl(1rad, 100%, 50%)", "hsl(32º, 100%, 50%)",
        "rgb(255deg, 0, 0)", "rgb(255°, 0, 0)", "rgba(0, 0, 0, 50%%)", "rgba(0, 0, 0, %)",
    ])
    func unitsInTheWrongPlaceAreRefused(text: String) {
        #expect(parse(text) == nil, "\(text)")
    }

    @Test func theDegreeSignAndTheWordBothMarkAHue() {
        #expect(parse("hsl(32°, 100%, 50%)") == Samples.orange)
        #expect(parse("hsl(32deg, 100%, 50%)") == Samples.orange)
        #expect(parse("hsl(32DEG, 100%, 50%)") == Samples.orange)
        #expect(parse("hsl(32.0deg, 100%, 50%)") == Samples.orange)
        #expect(parse("hsl(32 100% 50%)") == Samples.orange)
    }

    @Test func aHueGoesAroundTheWheelAsOftenAsItIsAsked() {
        let red = NookDesignColor(red: 255, green: 0, blue: 0)
        #expect(parse("hsl(360, 100%, 50%)") == red)
        #expect(parse("hsl(720, 100%, 50%)") == red)
        #expect(parse("hsl(3600, 100%, 50%)") == red)
        #expect(parse("hsl(392, 100%, 50%)") == parse("hsl(32, 100%, 50%)"))
        #expect(parse("hsl(999999999999, 100%, 50%)") != nil)
        // Saturation and lightness do not wrap.
        #expect(parse("hsl(0, 100%, 101%)") == nil)
    }

    @Test func hueMeansNothingWhenTheColorHasNoSaturationOrNoLightness() {
        let gray = parse("hsl(0, 0%, 50%)")
        #expect(gray != nil)
        for hue in [0, 90, 180, 270, 359] {
            #expect(parse("hsl(\(hue), 0%, 50%)") == gray)
            #expect(parse("hsl(\(hue), 80%, 0%)") == NookDesignColor(red: 0, green: 0, blue: 0))
            #expect(parse("hsl(\(hue), 80%, 100%)") == Samples.white)
        }
    }

    // MARK: Mixed case and spacing

    @Test(arguments: [
        "RgB(255, 136, 0)", "RGBA(255, 136, 0, 1)", "rGbA(255,136,0,1)", "Rgb (255, 136, 0)", "HSL(32, 100%, 50%)",
        "HsLa(32, 100%, 50%, 1)", "hSl(32DEG, 100%, 50%)",
    ])
    func functionNamesIgnoreCase(text: String) {
        #expect(parse(text) == Samples.orange)
    }

    @Test func anyNumberOfSpacesOutsideAndInsideTheBracketsIsFine() {
        #expect(parse("rgb(   255   ,   136   ,   0   )") == Samples.orange)
        #expect(parse("rgb     (255,136,0)") == Samples.orange)
        #expect(parse("   rgb(255,136,0)   ") == Samples.orange)
        #expect(parse("255 ,136 , 0") == Samples.orange)
        #expect(parse("rgb(255 , 136 , 0 , 1 )") == Samples.orange)
    }

    @Test func aFunctionNameNeedsItsBrackets() {
        for text in ["rgb 255, 136, 0", "rgb255,136,0", "rgb[255,136,0]", "rgb{255,136,0}", "rgb(255,136,0]", "rgb[255,136,0)",
                     "hsl 32 100% 50%", "hsl(32,100%,50%", "hsl32,100%,50%)", "rgba", "rgb", "hsl(", ")", "rgb(rgb(1,2,3))"] {
            #expect(parse(text) == nil, "\(text)")
        }
    }

    @Test func twoColorsInOneStringAreNotOne() {
        #expect(parse("rgb(1, 2, 3)rgb(4, 5, 6)") == nil)
        #expect(parse("#f80 #08f") == nil)
        #expect(parse("#f80, #08f") == nil)
        #expect(parse("#f80;#08f") == nil)
    }

    // MARK: Very long input

    @Test func theLengthLimitCountsTheTextAfterTheBlanksAroundItAreTrimmed() {
        let atTheLimit = "rgb(" + String(repeating: " ", count: 54) + "1,2,3)"
        #expect(atTheLimit.count == NookDesignColorParser.maxLength)
        #expect(parse(atTheLimit) == NookDesignColor(red: 1, green: 2, blue: 3))

        let past = "rgb(" + String(repeating: " ", count: 55) + "1,2,3)"
        #expect(past.count == NookDesignColorParser.maxLength + 1)
        #expect(parse(past) == nil)

        // Blanks outside the color do not count against it.
        let padded = String(repeating: " ", count: 500) + "#fff" + String(repeating: "\n", count: 500)
        #expect(parse(padded) == Samples.white)
    }

    @Test func hugeInputIsRefusedAtOnce() {
        #expect(parse(String(repeating: "f", count: 10_000)) == nil)
        #expect(parse("#" + String(repeating: "0", count: 100_000)) == nil)
        #expect(parse("rgb(" + String(repeating: "1", count: 50_000) + ", 0, 0)") == nil)
        #expect(parse(String(repeating: "(", count: 20_000)) == nil)
        #expect(parse(String(repeating: "rgb(", count: 5_000)) == nil)
        #expect(parse(String(repeating: "1,", count: 30_000)) == nil)
        #expect(parse(String(repeating: "🎨", count: 5_000)) == nil)
    }

    @Test func aNumberLongerThanTwelveCharactersIsNotRead() {
        #expect(parse("rgb(000000000255, 0, 0)")?.red == 255)
        #expect(parse("rgb(0000000000255, 0, 0)") == nil)
        #expect(parse("rgb(0.0000000001, 0, 0)")?.red == 0)
        #expect(parse("rgb(0.00000000001, 0, 0)") == nil)
    }

    // MARK: Transparency

    @Test func everyAlphaFormReadsTheSameAmountOfSeeThrough() {
        let quarter = NookDesignColor(red: 255, green: 136, blue: 0, alpha: 64)
        #expect(parse("rgba(255, 136, 0, 0.25)") == quarter)
        #expect(parse("rgba(255, 136, 0, .25)") == quarter)
        #expect(parse("rgba(255, 136, 0, 25%)") == quarter)
        #expect(parse("rgb(255 136 0 / 0.25)") == quarter)
        #expect(parse("rgb(255 136 0 / 25%)") == quarter)
        #expect(parse("255, 136, 0, 0.25") == quarter)
        #expect(parse("255 136 0 25%") == quarter)
        #expect(parse("#ff880040") == quarter)
        #expect(parse("#f804") == NookDesignColor(red: 255, green: 136, blue: 0, alpha: 68))
        #expect(parse("hsla(32, 100%, 50%, 0.25)") == quarter)
        #expect(parse("hsl(32 100% 50% / 25%)") == quarter)
    }

    @Test func fullyClearAndFullyOpaqueAreTheTwoEnds() {
        let clear = parse("rgba(255, 136, 0, 0)")
        #expect(clear?.alpha == 0)
        #expect(clear?.isOpaque == false)
        #expect(clear?.opacity == 0)
        #expect(parse("rgba(255, 136, 0, 0%)") == clear)
        #expect(parse("#ff880000") == clear)
        #expect(parse("rgba(255, 136, 0, 1)")?.isOpaque == true)
        #expect(parse("rgba(255, 136, 0, 1)")?.opacity == 1)
    }

    @Test func aClearColorIsNotTheSameColorAsItsOpaqueTwin() {
        let clear = NookDesignColor(red: 255, green: 136, blue: 0, alpha: 0)
        #expect(clear != Samples.orange)
        #expect(Set([clear, Samples.orange]).count == 2)
        // The text keeps the difference.
        #expect(clear.hex() == "#FF880000")
        #expect(clear.rgbText == "rgba(255, 136, 0, 0)")
        #expect(clear.hslText == "hsla(32, 100%, 50%, 0)")
        #expect(clear.hex(includesHash: false) == "FF880000")
    }

    @Test func theOddestAlphasWriteTheirShortestExactText() {
        func alphaText(_ alpha: UInt8) -> String { NookDesignColor(red: 0, green: 0, blue: 0, alpha: alpha).alphaText }
        #expect(alphaText(0) == "0")
        #expect(alphaText(1) == "0.004")
        #expect(alphaText(2) == "0.008")
        #expect(alphaText(51) == "0.2")
        #expect(alphaText(64) == "0.25")
        #expect(alphaText(127) == "0.498")
        #expect(alphaText(128) == "0.5")
        #expect(alphaText(254) == "0.996")
        #expect(alphaText(255) == "1")
    }

    @Test func everyAlphaSurvivesTheHslAndHexWritingsToo() {
        for alpha in UInt8.min...UInt8.max {
            let black = NookDesignColor(red: 0, green: 0, blue: 0, alpha: alpha)
            #expect(parse(black.hslText) == black, "alpha \(alpha) wrote \(black.hslText)")
            #expect(parse(black.hex(includesHash: false)) == black)
            let gray = NookDesignColor(red: 128, green: 128, blue: 128, alpha: alpha)
            #expect(parse(gray.hex()) == gray)
        }
    }

    @Test func alphaDoesNotChangeHowBrightAColorLooks() {
        let solid = Samples.orange.perceivedBrightness
        for alpha in [UInt8(0), 1, 128, 254] {
            #expect(NookDesignColor(red: 255, green: 136, blue: 0, alpha: alpha).perceivedBrightness == solid)
            #expect(NookDesignColor(red: 255, green: 136, blue: 0, alpha: alpha).hsl.lightness == Samples.orange.hsl.lightness)
        }
    }

    @Test func aSystemColorKeepsItsAlphaAndAPatternHasNoColor() {
        let faint = NSColor(srgbRed: 1, green: 136.0 / 255, blue: 0, alpha: 0.5)
        #expect(NookDesignColor(nsColor: faint) == NookDesignColor(red: 255, green: 136, blue: 0, alpha: 128))
        let clear = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 0)
        #expect(NookDesignColor(nsColor: clear)?.alpha == 0)
        // A pattern has no single color. The picker would count it as a cancel.
        let pattern = NSColor(patternImage: NSImage(size: NSSize(width: 4, height: 4)))
        #expect(NookDesignColor(nsColor: pattern) == nil)
    }

    // MARK: Conversions

    @Test func everyGrayHasNoSaturationAndComesBackFromItsLightness() {
        for level in UInt8.min...UInt8.max {
            let gray = NookDesignColor(red: level, green: level, blue: level)
            let hsl = gray.hsl
            #expect(hsl.saturation == 0, "gray \(level)")
            #expect(hsl.hue == 0)
            #expect(NookDesignColor(hue: hsl.hue, saturation: hsl.saturation, lightness: hsl.lightness) == gray)
        }
    }

    @Test func everyStepOfEachChannelComesBackThroughHsl() {
        for level in UInt8.min...UInt8.max {
            for other in [UInt8(0), 255] {
                for color in [
                    NookDesignColor(red: level, green: other, blue: 0),
                    NookDesignColor(red: 0, green: level, blue: other),
                    NookDesignColor(red: other, green: 0, blue: level),
                    NookDesignColor(red: level, green: 255 - level, blue: other),
                ] {
                    let hsl = color.hsl
                    let back = NookDesignColor(hue: hsl.hue, saturation: hsl.saturation, lightness: hsl.lightness)
                    #expect(back == color, "\(color.hex()) came back as \(back.hex())")
                }
            }
        }
    }

    @Test func aSpreadOfRandomColorsComesBackThroughHsl() {
        // A fixed generator, which keeps the run the same every time.
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> UInt8 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return UInt8(truncatingIfNeeded: state >> 33)
        }
        for _ in 0..<20_000 {
            let color = NookDesignColor(red: next(), green: next(), blue: next())
            let hsl = color.hsl
            #expect(hsl.hue >= 0 && hsl.hue < 360, "\(color.hex()) hue \(hsl.hue)")
            #expect((0...1).contains(hsl.saturation) && (0...1).contains(hsl.lightness))
            let back = NookDesignColor(hue: hsl.hue, saturation: hsl.saturation, lightness: hsl.lightness)
            #expect(back == color, "\(color.hex()) came back as \(back.hex())")
        }
    }

    @Test func hslValuesOutOfRangeAreKeptInRange() {
        #expect(NookDesignColor(hue: 0, saturation: 5, lightness: 0.5) == NookDesignColor(red: 255, green: 0, blue: 0))
        #expect(NookDesignColor(hue: 0, saturation: -5, lightness: 0.5) == NookDesignColor(red: 128, green: 128, blue: 128))
        #expect(NookDesignColor(hue: 120, saturation: 1, lightness: 9) == Samples.white)
        #expect(NookDesignColor(hue: 120, saturation: 1, lightness: -9) == NookDesignColor(red: 0, green: 0, blue: 0))
        #expect(NookDesignColor(hue: -1e-20, saturation: 1, lightness: 0.5) == NookDesignColor(red: 255, green: 0, blue: 0))
    }

    @Test func theHslTextRoundsTheHueIntoTheWheel() {
        // 359.6 degrees is 360, which is 0, and never "360".
        let nearlyRed = NookDesignColor(hue: 359.6, saturation: 1, lightness: 0.5)
        #expect(nearlyRed.hslText.hasPrefix("hsl(0, "))
        #expect(NookDesignColor(red: 255, green: 0, blue: 1).hslText.hasPrefix("hsl(360") == false)
        #expect(NookDesignColor(red: 0, green: 0, blue: 0).hslText == "hsl(0, 0%, 0%)")
        #expect(Samples.white.hslText == "hsl(0, 0%, 100%)")
    }

    // MARK: The color as a saved value

    @Test func aSavedColorKeepsItsAlphaAndATextWithBlanksStillReads() throws {
        let data = try JSONEncoder().encode([NookDesignColor(red: 1, green: 2, blue: 3, alpha: 4)])
        #expect(String(decoding: data, as: UTF8.self) == "[\"#01020304\"]")
        #expect(try JSONDecoder().decode([NookDesignColor].self, from: data).first?.alpha == 4)

        let byHand = Data("[\" #F80 \", \"RGBA(0,0,0,0.5)\", \"hsl(0 0% 100%)\"]".utf8)
        #expect(try JSONDecoder().decode([NookDesignColor].self, from: byHand) == [Samples.orange, Samples.scrim, Samples.white])
        for bad in ["[\"\"]", "[5]", "[null]", "[[\"#fff\"]]", "[{\"hex\":\"#fff\"}]"] {
            #expect(throws: DecodingError.self, "\(bad)") {
                try JSONDecoder().decode([NookDesignColor].self, from: Data(bad.utf8))
            }
        }
    }

    @Test func theNoticeTextFitsTheWingAtItsLimit() {
        let at18 = "rgb(255, 255, 255)"
        let at19 = "hsl(359, 100%, 50%)"
        #expect(at18.count == 18)
        #expect(at19.count == 19)
        #expect(NookDesignKit.noticeText(for: Samples.white, copied: at18) == at18)
        #expect(NookDesignKit.noticeText(for: Samples.white, copied: at19) == "#FFFFFF")
        #expect(NookDesignKit.noticeText(for: Samples.white, copied: "") == "")
        // A see-through color's long text falls back to its HEX form, alpha included.
        #expect(NookDesignKit.noticeText(for: Samples.scrim, copied: "rgba(0, 0, 0, 0.5)") == "rgba(0, 0, 0, 0.5)")
        let faint = NookDesignColor(red: 0, green: 0, blue: 0, alpha: 127)
        #expect(faint.rgbText.count > 18)
        #expect(NookDesignKit.noticeText(for: faint, copied: faint.rgbText) == "#0000007F")
    }
}
