import AppKit
import Metal
import QuartzCore
import Testing
@testable import OpenIslandApp

/// The fan that comes out of the screen toward the viewer (D56): the same
/// beams as the flat fan, in a plane turned about the notch's lower edge
/// and drawn with perspective. No window is shown. The numbers are plain
/// values, the layer tree is read back, and the pictures are drawn off
/// screen by the system's own renderer, which is the one that knows depth.
/// `OPEN_ISLAND_RENDER_SNAPSHOTS=1` also writes the pictures to
/// `output/render/lasers/`.
@MainActor
@Suite struct IslandLaserTiltTests {
    private static let counts = [8, 16, 24]
    /// A 14 inch MacBook's screen, and its closed island at the top middle.
    private static let screen = CGRect(x: 0, y: 0, width: 1_512, height: 982)
    private static let pill = CGRect(x: 619, y: 950, width: 274, height: 32)
    private static let space = IslandLaserSpace(pill: pill, screen: screen)
    private static let tint = IslandHaloRGB(rgb: 0xE0245E)
    private static let close = 0.000_1
    private static let shapes: [IslandLaserArrangement] = [.fan, .wings, .comb, .crossed]

    private static func length(reach: Double = IslandLaserReach.standard) -> Double {
        IslandLaserWindowPlan.beamLength(reach: reach, pill: pill, screen: screen)
    }

    /// A fan at the top of a low hit: every beam at its full length.
    private static func fan(
        _ arrangement: IslandLaserArrangement,
        count: Int = 16,
        reach: Double = IslandLaserReach.standard,
        nudge: Double = 1,
        time: TimeInterval = 0
    ) -> IslandLaserFan {
        IslandLaserFan(
            frame: IslandBeatFrame(low: 1, mid: 1, hit: .kick), reach: reach, tint: tint,
            lineup: arrangement.lineup(count: count, space: space, reach: reach), hueIndex: 0,
            nudges: Array(repeating: nudge, count: count), time: time, fullLength: length(reach: reach)
        )
    }

    /// Where the tip of each beam of a fan lands on the screen.
    private static func tips(of fan: IslandLaserFan, lunge: Double = 0) -> [IslandLaserTilt.Spot] {
        fan.beams.map {
            IslandLaserTilt.spot(start: $0.start, lean: $0.lean, along: $0.length, tilt: fan.tilt + lunge, eye: fan.eye)
        }
    }

    // MARK: The list

    @Test func aMidHitWalksThroughTheFanShapesFlatAndTowardTheViewer() {
        let all = IslandLaserArrangement.all
        #expect(all.map(\.name) == [
            "fan", "wingsTowardViewer", "comb", "crossedTowardViewer",
            "wings", "fanTowardViewer", "crossed", "combTowardViewer",
        ])
        #expect(Set(all).count == all.count)
        // Each of the four shapes, once flat and once toward the viewer.
        for shape in Self.shapes {
            #expect(all.contains(shape))
            #expect(all.contains(shape.forward))
        }
        // Every step is another shape and the other orientation, the
        // step from the last back to the first as well.
        for index in all.indices {
            let next = IslandLaserArrangement.at(index + 1)
            #expect(next.shape != all[index].shape)
            #expect((next.orientation == .flat) != (all[index].orientation == .flat))
        }
        // The beams that come straight down side by side are in no hit's
        // way. They are kept apart, for a show that picks its own looks.
        #expect(all.allSatisfy { !$0.isUpright })
        #expect(IslandLaserArrangement.uprights == [.curtain, .wideCurtain, .split])
        #expect(IslandLaserArrangement.uprights.allSatisfy { $0.orientation == .flat })
    }

    @Test func theTiltIsAValueOfTheArrangementAndTheBeamsAreTheSame() {
        #expect(IslandLaserOrientation.flat.tilt == 0)
        #expect(IslandLaserOrientation.forward.tilt == IslandLaserTilt.standard)
        #expect(IslandLaserOrientation.towardViewer(degrees: 400).tilt == IslandLaserTilt.most)
        #expect(IslandLaserOrientation.towardViewer(degrees: -9).tilt == 0)
        #expect(IslandLaserOrientation.towardViewer(degrees: .nan).tilt == 0)

        for shape in Self.shapes {
            for count in Self.counts {
                let flat = shape.lineup(count: count, space: Self.space, reach: 0.25)
                let forward = shape.forward.lineup(count: count, space: Self.space, reach: 0.25)
                // The same beams, standing the same way in their plane.
                #expect(forward.stands == flat.stands)
                #expect(forward.longest == flat.longest)
                #expect(flat.tilt == 0)
                #expect(forward.tilt == IslandLaserTilt.standard)
                // Only the slow sway is left out: the perspective would
                // draw it several times over.
                #expect(flat.sways && !forward.sways)

                let flatFan = Self.fan(shape, count: count)
                let forwardFan = Self.fan(shape.forward, count: count)
                for (mine, flats) in zip(forwardFan.beams, flatFan.beams) {
                    #expect(mine.start == flats.start)
                    #expect(mine.length == flats.length)
                    #expect(mine.brightness == flats.brightness)
                    #expect(abs(mine.lean - flats.lean) <= IslandLaserLimits.driftLean + Self.close)
                }
                // The left half is the right half turned around.
                for index in 0..<count {
                    #expect(abs(forwardFan.beams[index].lean + forwardFan.beams[count - 1 - index].lean) < Self.close)
                }
                #expect(forwardFan.color == flatFan.color)
                #expect(flatFan.tilt == 0 && flatFan.eye == .infinity)
                #expect(forwardFan.tilt == IslandLaserTilt.standard)
                #expect(forwardFan.eye == IslandLaserTilt.eyeDistance(fullLength: Self.length(), tilt: forwardFan.tilt))
            }
        }
    }

    // MARK: Where the beams land

    @Test func aFlatFanLandsWhereItAlwaysDid() {
        let fan = Self.fan(.fan)
        for (beam, tip) in zip(fan.beams, Self.tips(of: fan)) {
            #expect(abs(tip.x - (beam.start + beam.length * sin(beam.lean))) < Self.close)
            #expect(abs(tip.down - beam.length * cos(beam.lean)) < Self.close)
            #expect(tip.scale == 1)
        }
    }

    @Test func aTiltedFanReachesFurtherAndWiderThanTheFlatOne() {
        for shape in Self.shapes {
            for count in Self.counts {
                // The same beams, as they land turned toward the viewer
                // and as they would land lying flat.
                let fan = Self.fan(shape.forward, count: count)
                let forward = Self.tips(of: fan)
                let flat = fan.beams.map {
                    IslandLaserTilt.spot(start: $0.start, lean: $0.lean, along: $0.length, tilt: 0, eye: .infinity)
                }
                #expect(forward.count == count)
                var short = 0
                for index in 0..<count {
                    // Wider: further from the middle, on the same side.
                    let isWider = abs(forward[index].x) >= abs(flat[index].x) - Self.close
                        && forward[index].x * flat[index].x >= 0
                    // Further: from under the middle of the notch.
                    let isFurther = hypot(forward[index].x, forward[index].down)
                        > hypot(flat[index].x, flat[index].down)
                    if !isWider || !isFurther { short += 1 }
                }
                #expect(short == 0, "\(shape.name) with \(count) beams")
                // The whole fan is wider, and a shape with beams near
                // straight down goes further down the screen too. The
                // wings have none: theirs go out to the sides.
                #expect((forward.map(\.x).max() ?? 0) > (flat.map(\.x).max() ?? 0))
                if shape != .wings {
                    #expect((forward.map(\.down).max() ?? 0) > (flat.map(\.down).max() ?? 0) * 1.2)
                }
            }
        }
    }

    @Test func everyBeamOfATiltedFanStaysInFrontOfTheEyeAndInsideItsRoom() {
        for step in 0...10 {
            let reach = Double(step) / 10
            let length = Self.length(reach: reach)
            let room = IslandLaserRoom.tiltedReach(
                length: length, tilt: IslandLaserTilt.standard, halfEdge: Self.space.halfEdge
            )
            // Further than the flat fan's room to the side and below.
            let flat = IslandLaserRoom.insets(length: length)
            #expect(room.side > flat.side + CGFloat(Self.space.halfEdge))
            #expect(room.below > flat.below)

            for shape in Self.shapes {
                for count in Self.counts {
                    var outside = 0
                    var time = 0.0
                    while time < IslandLaserLimits.driftPeriod {
                        // Every beam nudged as far as a hat may nudge it,
                        // at rest and at the top of a lunge.
                        let fan = Self.fan(
                            shape.forward, count: count, reach: reach, nudge: 1 + IslandLaserLimits.hatCeiling,
                            time: time
                        )
                        for lunge in [0, IslandLaserTilt.lunge] {
                            for (beam, tip) in zip(fan.beams, Self.tips(of: fan, lunge: lunge)) {
                                let soft = IslandLaserLimits.softHalfWidth * tip.scale
                                let forward = beam.length * cos(beam.lean) * sin((fan.tilt + lunge) * .pi / 180)
                                let isInside = abs(tip.x) + soft <= Double(room.side)
                                    && tip.down + soft <= Double(room.below)
                                    && tip.down >= 0
                                    && forward < fan.eye * 0.8
                                if !isInside { outside += 1 }
                            }
                        }
                        time += 0.7
                    }
                    #expect(outside == 0, "\(shape.name) with \(count) beams at a reach of \(reach)")
                }
            }
        }
    }

    @Test func theWindowHoldsTheTiltedFanAndIsCutAtTheScreensEdge() throws {
        let displays: [(screen: CGRect, pill: CGRect)] = [
            (Self.screen, Self.pill),
            (CGRect(x: 1_512, y: 0, width: 1_920, height: 1_080), CGRect(x: 1_540, y: 1_056, width: 200, height: 24)),
            (CGRect(x: -2_560, y: 200, width: 2_560, height: 1_440), CGRect(x: -1_460, y: 1_616, width: 360, height: 24)),
        ]
        for (screen, pill) in displays {
            for step in 0...10 {
                let reach = Double(step) / 10
                let length = IslandLaserWindowPlan.beamLength(reach: reach, pill: pill, screen: screen)
                let room = IslandLaserRoom.rect(length: length, reach: reach, pill: pill, screen: screen)
                let tilted = IslandLaserRoom.tiltedReach(
                    length: length, tilt: IslandLaserRoom.widestTilt, halfEdge: Double(pill.width) / 2
                )
                // As far as the tilted fan goes, and never past the screen.
                #expect(screen.contains(room))
                #expect(abs(room.minX - max(screen.minX, pill.midX - tilted.side)) < 0.001)
                #expect(abs(room.maxX - min(screen.maxX, pill.midX + tilted.side)) < 0.001)
                #expect(abs(room.minY - max(screen.minY, pill.minY - tilted.below)) < 0.001)
                #expect(room.maxY == pill.maxY)

                let plan = try #require(IslandLaserWindowPlan.plan(
                    look: .lasers, showsPulse: true, pill: pill, screen: screen, reach: reach, isDemo: false
                ))
                #expect(screen.contains(plan.frame))
            }
        }
        #expect(IslandLaserRoom.widestTilt == IslandLaserTilt.standard)
    }

    // MARK: The taper

    @Test func aBeamThatComesForwardIsDrawnLargerTowardItsFarEnd() {
        let fan = Self.fan(.fan.forward)
        // The beam nearest straight down, which comes furthest forward.
        let beam = fan.beams[7]
        var last = 0.0
        for step in 0...10 {
            let spot = IslandLaserTilt.spot(
                start: beam.start, lean: beam.lean, along: beam.length * Double(step) / 10, tilt: fan.tilt, eye: fan.eye
            )
            // Thicker with every step away from the notch.
            #expect(spot.scale > last)
            last = spot.scale
        }
        let root = IslandLaserTilt.spot(start: beam.start, lean: beam.lean, along: 0, tilt: fan.tilt, eye: fan.eye)
        #expect(root.scale == 1)
        // At its far end it is drawn more than twice as thick, and at the
        // top of a lunge thicker still, and it always stays in front of
        // the eye, where it can be drawn.
        #expect(last > 2)
        let lunged = Self.tips(of: fan, lunge: IslandLaserTilt.lunge)[7]
        #expect(lunged.scale > last)
        #expect(lunged.scale <= 1 / (1 - IslandLaserTilt.depthShare) + Self.close)
        // The beams at the fan's ends come forward least.
        #expect(Self.tips(of: fan)[0].scale < last)
        #expect(Self.tips(of: fan)[0].scale > 1)
    }

    @Test func theEyeMovesBackWithTheBeamsAndAFlatFanHasNone() {
        #expect(IslandLaserTilt.eyeDistance(fullLength: 500, tilt: 0) == .infinity)
        #expect(IslandLaserTilt.eyeDistance(fullLength: 0, tilt: 50) == .infinity)
        #expect(IslandLaserTilt.eyeDistance(fullLength: .nan, tilt: 50) == .infinity)
        let near = IslandLaserTilt.eyeDistance(fullLength: 300, tilt: 50)
        let far = IslandLaserTilt.eyeDistance(fullLength: 900, tilt: 50)
        #expect(abs(far - near * 3) < Self.close)
        // The same picture at every reach: the tips land three times as
        // far for beams three times as long.
        let small = IslandLaserTilt.spot(start: 0, lean: 0.4, along: 300, tilt: 50, eye: near)
        let large = IslandLaserTilt.spot(start: 0, lean: 0.4, along: 900, tilt: 50, eye: far)
        #expect(abs(large.x - small.x * 3) < 0.001)
        #expect(abs(large.down - small.down * 3) < 0.001)
        #expect(abs(large.scale - small.scale) < Self.close)
    }

    // MARK: The layer

    private static func makeLayer(count: Int = 16, reach: Double = IslandLaserReach.standard) -> IslandLaserLayer {
        let layer = IslandLaserLayer()
        layer.container.frame = screen
        layer.setContentsScale(1)
        layer.setBeamCount(count)
        layer.layout(notch: pill, length: length(reach: reach))
        return layer
    }

    @Test func theLayerTurnsItsPlaneAboutTheNotchsLowerEdge() {
        let layer = Self.makeLayer()
        #expect(layer.pivot == CGPoint(x: Self.pill.midX, y: Self.pill.minY))
        #expect(layer.tilt == 0)
        #expect(layer.eye == .infinity)

        let forward = Self.fan(.fan.forward)
        layer.apply(forward)
        #expect(abs(layer.tilt - IslandLaserTilt.standard) < 0.001)
        #expect(abs(layer.eye - forward.eye) < 0.01)
        // The beams themselves stand as they did: the same places, leans
        // and lengths inside their plane.
        for (index, beam) in forward.beams.enumerated() {
            #expect(abs(layer.lean(ofBeam: index) - beam.lean) < Self.close)
            #expect(abs(layer.length(ofBeam: index) - beam.length) < 0.01)
            #expect(abs(layer.beams[index].holder.position.x - (Self.pill.midX + beam.start)) < Self.close)
        }
        #expect(layer.beamLayerCount == 16)

        // And flat again with the next flat fan.
        layer.apply(Self.fan(.wings))
        #expect(layer.tilt == 0)
        #expect(layer.eye == .infinity)
    }

    @Test func whatHangsBelowTheNotchComesTowardTheViewer() {
        // A point one unit below the edge, turned by the plane's own
        // transform: it keeps some of its drop and gains depth toward the
        // viewer, which is positive z.
        let turned = IslandLaserLayer.turned(50)
        let y = -1 * turned.m22
        let z = -1 * turned.m23
        #expect(abs(Double(y) + cos(50 * Double.pi / 180)) < Self.close)
        #expect(abs(Double(z) - sin(50 * Double.pi / 180)) < Self.close)
        #expect(abs(IslandLaserLayer.tilt(of: turned) - 50) < Self.close)
        #expect(CATransform3DIsIdentity(IslandLaserLayer.turned(0)))
    }

    @Test func aBeamThatFacesTheViewerIsBrightestAtItsFarEnd() throws {
        let layer = Self.makeLayer()
        func alphas(_ gradient: CAGradientLayer) throws -> [CGFloat] {
            try #require(gradient.colors as? [CGColor]).map(\.alpha)
        }

        layer.apply(Self.fan(.fan))
        let flatCore = try alphas(layer.beams[0].core)
        // Flat: white hot at the notch, gone at the tip.
        #expect(flatCore.first == 1 && flatCore.last == 0)
        #expect(layer.beams[0].soft.startPoint.y == 1)

        layer.apply(Self.fan(.fan.forward))
        let forwardCore = try alphas(layer.beams[0].core)
        // Toward the viewer: faint at the notch and brighter all the way
        // to white hot near its far end, with a short fade after it.
        #expect(forwardCore.first == IslandLaserLayer.forwardRoot)
        #expect(forwardCore.dropLast() == forwardCore.dropLast().sorted())
        #expect(forwardCore.dropLast().last == 1)
        #expect(forwardCore.last == 0)
        let stops = try #require(layer.beams[0].core.locations?.map(\.doubleValue))
        #expect(stops.count == forwardCore.count)
        #expect(stops[stops.count - 2] == IslandLaserLayer.forwardPeak)
        let white = try #require((layer.beams[0].core.colors as? [CGColor])?.dropLast().last?.components)
        #expect(white.prefix(3).allSatisfy { $0 == 1 })
        // The soft edge is centered on the far end, which tapers it to
        // nothing at the notch.
        #expect(layer.beams[0].soft.startPoint.y == 0)
        #expect(try alphas(layer.beams[0].soft).first == IslandLaserLayer.forwardHalo)

        // Back to flat, the beams are drawn as they were.
        layer.apply(Self.fan(.comb))
        #expect(try alphas(layer.beams[0].core) == flatCore)
        #expect(layer.beams[0].soft.startPoint.y == 1)
    }

    @Test func aLowHitLungesATiltedFanAndItIsBackWithItsBeams() throws {
        let layer = Self.makeLayer()
        layer.shoot(Self.fan(.fan.forward), over: IslandBeatGlow.punchFall, lunge: IslandLaserTilt.lunge)

        let lunge = try #require(layer.tiltFall)
        #expect(lunge.duration == IslandBeatGlow.punchFall)
        let from = try #require((lunge.fromValue as? NSValue)?.caTransform3DValue)
        let to = try #require((lunge.toValue as? NSValue)?.caTransform3DValue)
        #expect(abs(IslandLaserLayer.tilt(of: from) - (IslandLaserTilt.standard + IslandLaserTilt.lunge)) < 0.001)
        #expect(abs(IslandLaserLayer.tilt(of: to) - IslandLaserTilt.standard) < 0.001)
        // What the layer holds when it is over is its own tilt.
        #expect(abs(layer.tilt - IslandLaserTilt.standard) < 0.001)
        // The beams retract in the same time.
        #expect(layer.lengthFall(ofBeam: 0)?.duration == lunge.duration)

        // A lunge larger than the rule's is held to it, and a flat fan
        // does not lunge at all.
        layer.shoot(Self.fan(.fan.forward), over: 0.14, lunge: 60)
        let held = try #require((layer.tiltFall?.fromValue as? NSValue)?.caTransform3DValue)
        #expect(abs(IslandLaserLayer.tilt(of: held) - (IslandLaserTilt.standard + IslandLaserTilt.lunge)) < 0.001)
        layer.shoot(Self.fan(.fan), over: 0.14, lunge: IslandLaserTilt.lunge)
        #expect(layer.tiltFall == nil)
        #expect(layer.tilt == 0)
    }

    // MARK: Pictures

    /// The fan flat and toward the viewer, sixteen beams at full length on
    /// a screen's worth of black, at the reach the slider starts at.
    @Test func theFanFlatAndTowardTheViewerAtFullLength() throws {
        var lit: [IslandLaserArrangement: (columns: ClosedRange<Int>, rows: ClosedRange<Int>)] = [:]
        for arrangement in [IslandLaserArrangement.fan, .fan.forward] {
            let layer = Self.makeLayer()
            layer.apply(Self.fan(arrangement))
            guard let image = try Self.render(layer) else {
                // No renderer on this machine: there is nothing to look at.
                return
            }
            let name = arrangement.orientation == .flat ? "fan-flat-16" : "fan-toward-viewer-16"
            try Self.write(image, named: name)
            lit[arrangement] = try #require(Self.litBox(in: image), "\(name) is all black")
        }
        let flat = try #require(lit[.fan])
        let forward = try #require(lit[.fan.forward])
        // Wider and further down the screen than the flat fan.
        #expect(forward.columns.count > flat.columns.count)
        #expect(forward.rows.upperBound > flat.rows.upperBound)
        // And still centered on the island.
        let middle = Int(Self.pill.midX)
        #expect(abs((forward.columns.lowerBound + forward.columns.upperBound) / 2 - middle) < 12)
    }

    /// The layer tree as the system's own renderer draws it, depth and
    /// all, into a texture: `CALayer.render(in:)` leaves 3D transforms
    /// out. Nil when the machine has no Metal device.
    private static func render(_ layer: IslandLaserLayer) throws -> CGImage? {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        let width = Int(screen.width)
        let height = Int(screen.height)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        let root = CALayer()
        root.frame = screen
        root.backgroundColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        root.addSublayer(layer.container)
        // The island itself, a shade off black, over the top of the beams
        // as its panel is.
        let island = CALayer()
        island.frame = pill
        island.cornerRadius = 10
        island.backgroundColor = CGColor(srgbRed: 0.09, green: 0.09, blue: 0.1, alpha: 1)
        root.addSublayer(island)

        let renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue: queue])
        renderer.layer = root
        renderer.bounds = root.bounds
        CATransaction.flush()
        renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
        renderer.addUpdate(root.bounds)
        renderer.render()
        renderer.endFrame()
        // The queue runs in order: when this empty buffer is done, the
        // renderer's own are too.
        let done = try #require(queue.makeCommandBuffer())
        done.commit()
        done.waitUntilCompleted()

        var upsideDown = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(
            &upsideDown, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0
        )
        // The renderer counts rows from the bottom, as the layers do, and
        // a picture counts them from the top.
        var bytes = [UInt8]()
        bytes.reserveCapacity(upsideDown.count)
        for row in stride(from: height - 1, through: 0, by: -1) {
            bytes.append(contentsOf: upsideDown[(row * width * 4)..<((row + 1) * width * 4)])
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    /// The columns and rows that hold light under the island, rows counted
    /// from the top of the picture.
    private static func litBox(in image: CGImage) -> (columns: ClosedRange<Int>, rows: ClosedRange<Int>)? {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        var columns: ClosedRange<Int>?
        var rows: ClosedRange<Int>?
        // Below the island's own lower edge.
        for row in Int(pill.height + 4)..<image.height {
            for column in 0..<image.width {
                let offset = row * image.bytesPerRow + column * 4
                guard Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2]) > 60 else { continue }
                columns = columns.map { min($0.lowerBound, column)...max($0.upperBound, column) } ?? column...column
                rows = rows.map { $0.lowerBound...max($0.upperBound, row) } ?? row...row
            }
        }
        guard let columns, let rows else { return nil }
        return (columns, rows)
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
