import AppKit
import QuartzCore
import Testing
@testable import OpenIslandApp

/// The lasers' layers (D56). No window is shown: the layer tree is made,
/// handed fans and read back, and drawn into a bitmap for the pictures.
/// `OPEN_ISLAND_RENDER_SNAPSHOTS=1` also writes the pictures to
/// `output/render/lasers/`.
@MainActor
@Suite struct IslandLaserLayerTests {
    private static let canvas = CGSize(width: 760, height: 360)
    /// The notch, at the top of the canvas with y growing upward.
    private static let notch = CGRect(x: 280, y: 328, width: 200, height: 32)
    private static let tint = IslandHaloRGB(rgb: 0xE0245E)
    /// The room the canvas gives the beams.
    private static let space = IslandLaserSpace(pill: notch, screen: CGRect(origin: .zero, size: canvas))

    private static func fan(
        low: Double,
        hit: IslandBeatHit? = nil,
        arrangement: IslandLaserArrangement = .fan,
        count: Int = IslandLaserCount.standard,
        hue: Int = 0,
        reach: Double = IslandBeatReach.standard,
        time: TimeInterval = 0
    ) -> IslandLaserFan {
        IslandLaserFan(
            frame: IslandBeatFrame(low: low, mid: low, hit: hit),
            reach: reach,
            tint: tint,
            lineup: arrangement.lineup(count: count, space: space, reach: reach),
            hueIndex: hue,
            time: time
        )
    }

    private static func makeLayer(reach: Double = IslandBeatReach.standard) -> IslandLaserLayer {
        let layer = IslandLaserLayer()
        layer.container.frame = CGRect(origin: .zero, size: canvas)
        layer.setContentsScale(2)
        layer.layout(notch: notch, reach: reach)
        return layer
    }

    // MARK: The door

    @Test func aFanShowsItsBeamsWhereTheNumbersSay() {
        let layer = Self.makeLayer()
        #expect(layer.shownBeamCount == 0)
        #expect(layer.container.opacity == 0)

        let fan = Self.fan(low: 0.6)
        layer.apply(fan)
        #expect(layer.container.opacity == 1)
        #expect(layer.shownBeamCount == fan.beams.count)
        for (index, beam) in fan.beams.enumerated() {
            #expect(abs(layer.lean(ofBeam: index) - beam.lean) < 0.0001)
            #expect(abs(layer.length(ofBeam: index) - beam.length) < 0.01)
            let holder = layer.beams[index].holder
            #expect(abs(holder.position.x - (Self.notch.midX + beam.start)) < 0.0001)
            #expect(holder.position.y == Self.notch.minY)
            #expect(abs(Double(holder.opacity) - beam.brightness) < 0.0001)
        }
    }

    @Test func aFanWithFewerBeamsThanTheLayerHoldsHidesTheRest() {
        let layer = Self.makeLayer()
        layer.apply(Self.fan(low: 0.6, arrangement: .comb))
        #expect(layer.shownBeamCount == IslandLaserCount.standard)
        layer.apply(Self.fan(low: 0.6, hit: .snare, arrangement: .wings, count: 8))
        #expect(layer.shownBeamCount == 8)
        #expect(layer.beams[9].holder.opacity == 0)
    }

    // MARK: How many

    @Test func theBeamsAreMadeAgainOnlyWhenTheCountChanges() {
        let layer = Self.makeLayer()
        #expect(layer.beams.count == IslandLaserCount.standard)
        #expect(layer.rebuilds == 0)

        // The count it already has: nothing is made.
        let first = layer.beams.map(\.holder)
        layer.setBeamCount(IslandLaserCount.standard)
        #expect(layer.rebuilds == 0)
        #expect(zip(layer.beams, first).allSatisfy { $0.holder === $1 })

        layer.apply(Self.fan(low: 0.5, hue: 1))
        layer.setBeamCount(24)
        #expect(layer.rebuilds == 1)
        #expect(layer.beams.count == 24)
        #expect(layer.beamLayerCount == 24)
        #expect(first.allSatisfy { $0.superlayer == nil })
        // The new ones are drawn like the old: the size, the scale and
        // the color that was showing.
        let drawn = first[0].bounds.size
        for beam in layer.beams {
            #expect(beam.holder.bounds.size == drawn)
            #expect(beam.soft.contentsScale == 2)
            #expect(beam.core.colors != nil)
        }

        // The same count again, and every fan after it, makes nothing.
        let second = layer.beams.map(\.holder)
        for step in 0..<50 {
            layer.setBeamCount(24)
            layer.apply(Self.fan(low: Double(step % 10) / 10, hit: step % 5 == 0 ? .kick : nil, count: 24))
            layer.shoot(Self.fan(low: 1, hit: .kick, arrangement: .curtain, count: 24), over: 0.14)
        }
        #expect(layer.rebuilds == 1)
        #expect(zip(layer.beams, second).allSatisfy { $0.holder === $1 })
        #expect(layer.shownBeamCount == 0)

        layer.setBeamCount(8)
        #expect(layer.rebuilds == 2)
        #expect(layer.beams.count == 8)
    }

    @Test func aCountOutsideEightToTwentyFourIsHeld() {
        let layer = Self.makeLayer()
        layer.setBeamCount(3)
        #expect(layer.beams.count == IslandLaserCount.least)
        layer.setBeamCount(10_000)
        #expect(layer.beams.count == IslandLaserCount.most)
        #expect(layer.rebuilds == 2)
    }

    @Test func uprightBeamsStandSideBySideWithNoLean() {
        for arrangement in IslandLaserArrangement.uprights {
            for count in [8, 16, 24] {
                let layer = Self.makeLayer()
                layer.setBeamCount(count)
                let fan = Self.fan(low: 1, hit: .kick, arrangement: arrangement, count: count)
                layer.apply(fan)
                #expect(layer.shownBeamCount == count)
                for index in 0..<count {
                    #expect(layer.lean(ofBeam: index) == 0)
                    #expect(abs(layer.beams[index].holder.position.x - (Self.notch.midX + fan.beams[index].start)) < 0.0001)
                    #expect(layer.beams[index].holder.position.y == Self.notch.minY)
                    #expect(abs(layer.length(ofBeam: index) - fan.beams[index].length) < 0.01)
                }
                // Left to right, and inside the canvas.
                let places = layer.beams.map(\.holder.position.x)
                #expect(zip(places.dropFirst(), places).allSatisfy { $0 > $1 })
                #expect((places.first ?? -1) >= 0 && (places.last ?? .infinity) <= Self.canvas.width)
            }
        }
    }

    @Test func aHitLandsWithNoAnimationAndTheFallIsAnimated() {
        let layer = Self.makeLayer()
        // The first fan has nothing to come from.
        layer.apply(Self.fan(low: 0.3))
        #expect(layer.animationStarts == 0)

        layer.apply(Self.fan(low: 1, hit: .kick))
        #expect(layer.animationStarts == 0)
        for beam in layer.beams {
            #expect(beam.holder.animationKeys() == nil)
            #expect(beam.stem.animationKeys() == nil)
        }

        // The bass lets go: the beams shorten over the fall.
        layer.apply(Self.fan(low: 0.4))
        #expect(layer.animationStarts > 0)
        let falling = layer.beams[0].stem.animation(forKey: "laser.length") as? CABasicAnimation
        #expect(falling?.duration == IslandLaserLayer.fall)

        // And it comes back up over the rise, which is shorter.
        layer.apply(Self.fan(low: 0.7))
        let rising = layer.beams[0].stem.animation(forKey: "laser.length") as? CABasicAnimation
        #expect(rising?.duration == IslandLaserLayer.rise)
        #expect(IslandLaserLayer.rise < IslandLaserLayer.fall)
    }

    @Test func aSnaresColorIsOnTheBeamsAtOnce() {
        let layer = Self.makeLayer()
        layer.apply(Self.fan(low: 0.5))
        let first = layer.beams[0].core.colors as? [CGColor]
        layer.apply(Self.fan(low: 0.5, hit: .snare, arrangement: .wings, hue: 1))
        let second = layer.beams[0].core.colors as? [CGColor]
        #expect(first != second)
        #expect(layer.beams[0].core.animation(forKey: "laser.color") == nil)
        // The core starts white hot whatever the color is.
        #expect(second?.first?.components?.prefix(3).allSatisfy { $0 == 1 } == true)
    }

    @Test func nothingIsMadeWhileTheMusicPlays() {
        let layer = Self.makeLayer()
        let layers = layer.container.sublayers?.count
        #expect(layer.beamLayerCount == IslandLaserCount.standard)
        var score = IslandLaserScore()
        for step in 0..<400 {
            let hit: IslandBeatHit? = step % 16 == 8 ? .snare : (step % 8 == 0 ? .kick : (step % 2 == 0 ? .hat : nil))
            let frame = IslandBeatFrame(low: Double(step % 10) / 10, mid: 0.4, high: 0.8, hit: hit)
            layer.apply(score.fan(for: frame, reach: 0.5, tint: Self.tint, space: Self.space, time: Double(step) / 30))
        }
        // Every arrangement was shown, flat and toward the viewer.
        #expect(score.arrangementIndex == 25 % IslandLaserArrangement.all.count)
        #expect(layer.rebuilds == 0)
        #expect(layer.container.sublayers?.count == layers)
        #expect(layer.beamLayerCount == IslandLaserCount.standard)
        for beam in layer.beams {
            #expect(beam.holder.sublayers?.count == 1)
            #expect(beam.stem.sublayers?.count == 2)
            // The pictures are gradients, drawn by the system: no contents
            // are handed over for a frame.
            #expect(beam.soft.contents == nil && beam.core.contents == nil)
        }
    }

    @Test func aLongerReachDrawsLongerBeamsAndKeepsTheFan() {
        let layer = Self.makeLayer(reach: 0)
        let near = Self.fan(low: 1, reach: 0)
        layer.apply(near)
        #expect(abs(layer.length(ofBeam: 3) - near.beams[3].length) < 0.01)

        layer.layout(notch: Self.notch, reach: 1)
        let far = Self.fan(low: 1, reach: 1)
        layer.apply(far)
        #expect(abs(layer.length(ofBeam: 3) - far.beams[3].length) < 0.01)
        #expect(far.beams[3].length > near.beams[3].length * 3)
    }

    @Test func endingTakesTheLasersOffAndKeepsTheBeams() {
        let layer = Self.makeLayer()
        layer.apply(Self.fan(low: 0.5))
        layer.end(animated: false)
        #expect(layer.container.opacity == 0)
        #expect(layer.fan == nil)
        #expect(layer.beams.count == IslandLaserCount.standard)
        layer.apply(Self.fan(low: 0.5))
        #expect(layer.container.opacity == 1)
    }

    // MARK: Pictures

    @Test func moreBassLightsMoreOfThePicture() throws {
        var lit: [Int] = []
        for (name, low) in [("low", 0.0), ("medium", 0.5), ("full", 1.0)] {
            let layer = Self.makeLayer(reach: 0.75)
            layer.apply(Self.fan(low: low, reach: 0.75))
            let image = try Self.picture(of: layer, canvas: Self.canvas, notch: Self.notch, scale: 2)
            lit.append(Self.litPixels(in: image))
            try Self.write(image, named: name)
        }
        #expect(lit[0] > 0)
        #expect(lit[0] < lit[1])
        #expect(lit[1] < lit[2])
    }

    /// A 14 inch MacBook's screen, and its closed island at the top middle.
    private static let screen = CGSize(width: 1_512, height: 982)
    private static let pill = CGRect(x: 619, y: 950, width: 274, height: 32)

    /// A fan, the curtain and the split with sixteen beams at full length,
    /// on a screen's worth of black and at the reach the slider starts at.
    @Test func aFanACurtainAndASplitAtFullLength() throws {
        let bounds = CGRect(origin: .zero, size: Self.screen)
        let space = IslandLaserSpace(pill: Self.pill, screen: bounds)
        let reach = IslandLaserReach.standard
        let length = IslandLaserWindowPlan.beamLength(reach: reach, pill: Self.pill, screen: bounds)
        // A row a hundred points under the island.
        let row = Self.pill.minY - 100

        var lit: [IslandLaserArrangement: [Int]] = [:]
        for arrangement in [IslandLaserArrangement.fan, .curtain, .split] {
            let layer = IslandLaserLayer()
            layer.container.frame = bounds
            layer.setContentsScale(1)
            layer.setBeamCount(16)
            layer.layout(notch: Self.pill, length: length)
            layer.apply(IslandLaserFan(
                frame: IslandBeatFrame(low: 1, mid: 1, hit: .kick), reach: reach, tint: Self.tint,
                lineup: arrangement.lineup(count: 16, space: space, reach: reach),
                hueIndex: 0, time: 0, fullLength: length
            ))
            #expect(layer.shownBeamCount == 16)
            let image = try Self.picture(of: layer, canvas: Self.screen, notch: Self.pill, scale: 1)
            lit[arrangement] = Self.litColumns(in: image, atRow: Int(Self.screen.height - row))
            try Self.write(image, named: "\(arrangement.name)-16")
        }

        let middle = Int(Self.pill.midX)
        let soft = Int(IslandLaserLimits.softHalfWidth) + 1
        // The curtain: light under the notch and a little beyond, and
        // none further out.
        let curtain = try #require(lit[.curtain])
        let half = Int(space.curtain.right)
        #expect(!curtain.isEmpty)
        #expect(curtain.allSatisfy { abs($0 - middle) <= half + soft })
        #expect(curtain.contains { $0 < middle - half / 2 } && curtain.contains { $0 > middle + half / 2 })

        // The split: light on both sides, and the middle third dark.
        let split = try #require(lit[.split])
        let wide = space.wide(reach: reach)
        let gap = Int(wide.right * IslandLaserLimits.splitGap)
        #expect(split.contains { $0 < middle - gap } && split.contains { $0 > middle + gap })
        #expect(split.allSatisfy { abs($0 - middle) >= gap - soft })
        #expect(split.allSatisfy { abs($0 - middle) <= Int(wide.right) + soft })

        // The fan is far wider at that depth than the notch.
        let fan = try #require(lit[.fan])
        #expect((fan.max() ?? 0) - (fan.min() ?? 0) > Int(Self.pill.width))
    }

    /// The columns that are lit in one row of the picture, counted from
    /// the top.
    private static func litColumns(in image: CGImage, atRow row: Int) -> [Int] {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data),
              (0..<image.height).contains(row) else { return [] }
        return (0..<image.width).filter { column in
            let offset = row * image.bytesPerRow + column * 4
            return Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2]) > 48
        }
    }

    /// The layer tree on black, with the notch drawn in for scale.
    private static func picture(
        of layer: IslandLaserLayer, canvas: CGSize, notch: CGRect, scale: CGFloat
    ) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil,
            width: Int(canvas.width * scale),
            height: Int(canvas.height * scale),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: canvas))
        layer.container.render(in: context)
        // The notch itself, a shade off black, which shows where the beams
        // leave from.
        context.setFillColor(CGColor(srgbRed: 0.09, green: 0.09, blue: 0.1, alpha: 1))
        context.addPath(CGPath(roundedRect: notch, cornerWidth: 10, cornerHeight: 10, transform: nil))
        context.fillPath()
        return try #require(context.makeImage())
    }

    private static func litPixels(in image: CGImage) -> Int {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return 0 }
        let rowBytes = image.bytesPerRow
        // Only the part under the notch, which the beams alone light.
        let rows = Int(Double(image.height) * 0.85)
        var count = 0
        for row in (image.height - rows)..<image.height {
            for column in 0..<image.width {
                let offset = row * rowBytes + column * 4
                if Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2]) > 48 { count += 1 }
            }
        }
        return count
    }

    private static func write(_ image: CGImage, named name: String) throws {
        guard ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_SNAPSHOTS"] == "1" else { return }
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("output/render/lasers", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let png = try #require(
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
            "PNG encoding failed for \(name)"
        )
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
