import SwiftUI

// The second half of the sticker sheet: fruit, moons, lightning, speech
// bubbles and props.
extension NookMirrorStickerDesigns {
    private static let gloss = Color.white.opacity(0.8)

    // MARK: Fruit

    static let fruit: [NookMirrorStickerDesign] = [
        make("sticker.fruit.cherry", [
            NookStickerTones(0xE8284A, accent: 0x3DBF6B, ink: 0x7A0F26),
            NookStickerTones(0x8A1F4D, accent: 0x5FCF9A, ink: 0x3D0A21),
            NookStickerTones(0xFF8FB8, accent: 0x5FCF9A, ink: 0xB3246B),
        ]) { kit, tone in
            let cherries = [kit.circle(0.32, 0.68, 0.17), kit.circle(0.66, 0.72, 0.17)]
            let stems = [
                kit.curve { stem in
                    stem.move(0.32, 0.52)
                    stem.quad(0.36, 0.28, 0.56, 0.16)
                },
                kit.curve { stem in
                    stem.move(0.66, 0.56)
                    stem.quad(0.66, 0.34, 0.56, 0.16)
                },
            ]
            let leaf = kit.curve { leaf in
                leaf.move(0.56, 0.16)
                leaf.quad(0.72, 0.07, 0.86, 0.18)
                leaf.quad(0.7, 0.28, 0.56, 0.16)
                leaf.close()
            }
            var silhouette = cherries[0].union(cherries[1]).union(leaf)
            for stem in stems { silhouette = silhouette.union(kit.body(of: stem, width: 0.04)) }
            kit.rim(silhouette)
            for stem in stems { kit.ink(stem, tone.accent, width: 0.04) }
            kit.shape(leaf, fill: tone.accent, ink: tone.ink, width: 0.03)
            for cherry in cherries { kit.shape(cherry, fill: tone.fill, ink: tone.ink) }
            kit.ink(kit.arc(0.32, 0.68, 0.1, from: 200, to: 250), gloss, width: 0.04)
            kit.ink(kit.arc(0.66, 0.72, 0.1, from: 200, to: 250), gloss, width: 0.04)
        },
        make("sticker.fruit.strawberry", [
            NookStickerTones(0xFF3D5A, accent: 0x3DBF6B, second: 0xFFF3B0, ink: 0x8A0F26),
            NookStickerTones(0xFF8FB8, accent: 0x5FCF9A, second: 0xFFFFFF, ink: 0xB3246B),
            NookStickerTones(0xFFD23F, accent: 0x3DBF6B, second: 0xFFFFFF, ink: 0x8A6A00),
        ]) { kit, tone in
            let berry = kit.curve { berry in
                berry.move(0.5, 0.9)
                berry.cubic(0.3, 0.82, 0.12, 0.56, 0.18, 0.36)
                berry.cubic(0.22, 0.24, 0.38, 0.24, 0.5, 0.3)
                berry.cubic(0.62, 0.24, 0.78, 0.24, 0.82, 0.36)
                berry.cubic(0.88, 0.56, 0.7, 0.82, 0.5, 0.9)
                berry.close()
            }
            let cap = kit.polygon([
                (0.28, 0.2), (0.4, 0.26), (0.44, 0.12), (0.5, 0.24), (0.56, 0.12),
                (0.6, 0.26), (0.72, 0.2), (0.62, 0.34), (0.5, 0.38), (0.38, 0.34),
            ])
            kit.rim(berry.union(cap))
            kit.shape(berry, fill: tone.fill, ink: tone.ink)
            for seed in [(CGFloat(0.34), CGFloat(0.5)), (0.5, 0.48), (0.66, 0.5), (0.41, 0.63), (0.59, 0.63), (0.5, 0.76)] {
                kit.fill(kit.ellipse(seed.0, seed.1, width: 0.036, height: 0.056), tone.second)
            }
            kit.shape(cap, fill: tone.accent, ink: tone.ink)
        },
        make("sticker.fruit.citrus", [
            NookStickerTones(0xFFD23F, accent: 0xFFF07A, second: 0xFFFBE6, ink: 0x9A6B00),
            NookStickerTones(0xFF8A1F, accent: 0xFFB85C, second: 0xFFF3E0, ink: 0x9A4A00),
            NookStickerTones(0x5FCF4A, accent: 0xB6F26B, second: 0xF3FFE0, ink: 0x2F7A22),
        ]) { kit, tone in
            let rind = kit.circle(0.5, 0.5, 0.4)
            kit.rim(rind)
            kit.shape(rind, fill: tone.fill, ink: tone.ink)
            kit.fill(kit.circle(0.5, 0.5, 0.34), tone.second)
            kit.fill(kit.circle(0.5, 0.5, 0.3), tone.accent)
            for degrees in [CGFloat(0), 45, 90, 135] {
                let angle = degrees * .pi / 180
                let reach: CGFloat = 0.31
                kit.ink(
                    kit.polyline([
                        (0.5 - cos(angle) * reach, 0.5 - sin(angle) * reach),
                        (0.5 + cos(angle) * reach, 0.5 + sin(angle) * reach),
                    ]),
                    tone.second,
                    width: 0.035
                )
            }
            kit.fill(kit.circle(0.5, 0.5, 0.05), tone.second)
        },
    ]

    // MARK: Moons

    static let moons: [NookMirrorStickerDesign] = [
        make("sticker.moon.crescent", [
            NookStickerTones(0xFFE9A8, accent: 0xFFFFFF, ink: 0x9A6B00),
            NookStickerTones(0xE6ECF5, accent: 0xFFE94A, ink: 0x4A5670),
            NookStickerTones(0xFFC2DC, accent: 0xFFF3B0, ink: 0xB3246B),
        ]) { kit, tone in
            let moon = NookDecorationShapes.crescent(
                kit.at(0.46, 0.52),
                radius: kit.length(0.36),
                bite: CGSize(width: kit.length(0.14), height: kit.length(-0.08)),
                biteRadius: kit.length(0.3)
            )
            let star = kit.star(0.72, 0.3, outer: 0.12, inner: 0.055)
            kit.rim(moon.union(star))
            kit.shape(moon, fill: tone.fill, ink: tone.ink)
            kit.shape(star, fill: tone.accent, ink: tone.ink, width: 0.03)
        },
        make("sticker.moon.cratered", [
            NookStickerTones(0xF2EFE6, accent: 0xD6D0C2, ink: 0x6B6557),
            NookStickerTones(0xFFE066, accent: 0xFFC21F, ink: 0x9A6B00),
            NookStickerTones(0xB8D4FF, accent: 0x8FB3F5, ink: 0x2F4F9A),
        ]) { kit, tone in
            let disc = kit.circle(0.5, 0.5, 0.4)
            kit.rim(disc)
            kit.shape(disc, fill: tone.fill, ink: tone.ink)
            let craters: [(CGFloat, CGFloat, CGFloat)] = [
                (0.38, 0.38, 0.09), (0.62, 0.5, 0.06), (0.46, 0.68, 0.075), (0.66, 0.3, 0.035),
            ]
            for crater in craters {
                kit.fill(kit.circle(crater.0, crater.1, crater.2), tone.accent)
                kit.ink(kit.arc(crater.0, crater.1, crater.2, from: 180, to: 300), tone.ink.opacity(0.4), width: 0.025)
            }
        },
    ]

    // MARK: Lightning

    /// The bolt both lightning stickers share, in the sticker's square.
    private static let boltPoints: [(CGFloat, CGFloat)] = [
        (0.5, 0.08), (0.24, 0.54), (0.45, 0.54), (0.34, 0.92), (0.78, 0.4), (0.56, 0.4), (0.7, 0.08),
    ]

    static let lightning: [NookMirrorStickerDesign] = [
        make("sticker.bolt", [
            NookStickerTones(0xFFE600, ink: 0x9A6B00),
            NookStickerTones(0x5CC8FF, ink: 0x1D4FA8),
            NookStickerTones(0xFF4FA3, ink: 0x8A0F5C),
        ]) { kit, tone in
            let bolt = kit.polygon(boltPoints)
            kit.rim(bolt)
            kit.shape(bolt, fill: tone.fill, ink: tone.ink)
            kit.ink(kit.polyline([(0.53, 0.16), (0.42, 0.36)]), .white.opacity(0.7), width: 0.035)
        },
        make("sticker.badge.power", [
            NookStickerTones(0x22C55E, accent: 0xFFFFFF, ink: 0x0F7A37),
            NookStickerTones(0xFF5A47, accent: 0xFFE94A, ink: 0x8A1F14),
            NookStickerTones(0x2B2B33, accent: 0xFFE600, ink: 0x000000),
        ]) { kit, tone in
            let disc = kit.circle(0.5, 0.5, 0.4)
            kit.rim(disc)
            kit.shape(disc, fill: tone.fill, ink: tone.ink)
            kit.ink(kit.circle(0.5, 0.5, 0.32), .white.opacity(0.35), width: 0.025)
            // The bolt at 62 percent of its size, about the middle.
            kit.fill(kit.polygon(boltPoints.map { (0.5 + ($0.0 - 0.5) * 0.62, 0.5 + ($0.1 - 0.5) * 0.62) }), tone.accent)
        },
    ]

    // MARK: Speech bubbles

    static let bubbles: [NookMirrorStickerDesign] = [
        make("sticker.bubble.hi", [
            NookStickerTones(0xFFFFFF, ink: 0x1F1F24, text: 0x1F1F24),
            NookStickerTones(0xFF8FC7, ink: 0xA31560, text: 0xFFFFFF),
            NookStickerTones(0x7DF2C0, ink: 0x1F6F5A, text: 0x0F3F33),
        ]) { kit, tone in
            let bubble = kit.ellipse(0.5, 0.44, width: 0.8, height: 0.6)
                .union(kit.polygon([(0.3, 0.66), (0.22, 0.9), (0.46, 0.72)]))
            kit.rim(bubble)
            kit.shape(bubble, fill: tone.fill, ink: tone.ink)
            kit.word("hi", 0.5, 0.44, size: 0.34, font: .rounded(.heavy), color: tone.text)
        },
        make("sticker.burst.wow", [
            NookStickerTones(0xFFE600, ink: 0x1F1F24, text: 0xFF3D5A),
            NookStickerTones(0xFF5FA8, ink: 0x6B0F3F, text: 0xFFFFFF),
            NookStickerTones(0x19E3FF, ink: 0x0F4F6B, text: 0x1F1F24),
        ]) { kit, tone in
            let burst = kit.star(0.5, 0.5, outer: 0.42, inner: 0.31, points: 14, turned: 6, squash: 0.85)
            kit.rim(burst)
            kit.shape(burst, fill: tone.fill, ink: tone.ink)
            kit.word("WOW", 0.5, 0.5, size: 0.22, font: .rounded(.black), color: tone.text, turned: -8)
        },
        make("sticker.tag.lgtm", [
            NookStickerTones(0x22C55E, ink: 0x0F5F2D, text: 0xFFFFFF),
            NookStickerTones(0x1F1F24, ink: 0x000000, text: 0x4DFF7A),
            NookStickerTones(0x8E7CFF, ink: 0x3B2F9A, text: 0xFFFFFF),
        ]) { kit, tone in
            let tag = kit.box(0.08, 0.28, 0.92, 0.66, radius: 0.12)
                .union(kit.polygon([(0.58, 0.66), (0.7, 0.86), (0.74, 0.66)]))
            kit.rim(tag)
            kit.shape(tag, fill: tone.fill, ink: tone.ink)
            kit.word("LGTM", 0.5, 0.47, size: 0.21, font: .mono(bold: true), color: tone.text)
        },
        make("sticker.thought.zzz", [
            NookStickerTones(0xDDEBFF, ink: 0x3B5FA8, text: 0x3B5FA8),
            NookStickerTones(0xE6DBFF, ink: 0x5B3FB3, text: 0x5B3FB3),
            NookStickerTones(0x2B2B45, ink: 0x0F0F24, text: 0xFFE94A),
        ]) { kit, tone in
            let thought = kit.circle(0.36, 0.4, 0.2)
                .union(kit.circle(0.56, 0.32, 0.22))
                .union(kit.circle(0.7, 0.46, 0.18))
                .union(kit.circle(0.48, 0.52, 0.2))
            let dots = [kit.circle(0.28, 0.76, 0.055), kit.circle(0.19, 0.87, 0.035)]
            kit.rim(dots.reduce(thought) { $0.union($1) })
            kit.shape(thought, fill: tone.fill, ink: tone.ink)
            for dot in dots { kit.shape(dot, fill: tone.fill, ink: tone.ink, width: 0.03) }
            kit.word("zzz", 0.53, 0.42, size: 0.22, font: .rounded(.bold, italic: true), color: tone.text)
        },
    ]

    // MARK: Props

    static let props: [NookMirrorStickerDesign] = [
        // The glasses keep their lenses see-through, which is why the rim
        // here is a line around them and not a white shape under them.
        make("sticker.glasses", [
            NookStickerTones(0xFFD9A8, ink: 0x7A4A1F, fillOpacity: 0.25),
            NookStickerTones(0x1F1F24, ink: 0x1F1F24, fillOpacity: 0.85),
            NookStickerTones(0xFF9CC8, ink: 0xFF5FA8, fillOpacity: 0.35),
        ]) { kit, tone in
            let lenses = [kit.circle(0.28, 0.5, 0.17), kit.circle(0.72, 0.5, 0.17)]
            let bridge = kit.curve { bridge in
                bridge.move(0.44, 0.46)
                bridge.quad(0.5, 0.4, 0.56, 0.46)
            }
            let wire = lenses.reduce(kit.body(of: bridge, width: 0.05)) { $0.union(kit.body(of: $1, width: 0.06)) }
            let unit = kit.pen.unit
            kit.pen.context.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.3), radius: 3 * unit, x: 0, y: 2 * unit))
                layer.stroke(wire, with: .color(.white), style: StrokeStyle(lineWidth: 10 * unit, lineJoin: .round))
                layer.fill(wire, with: .color(.white))
            }
            for lens in lenses {
                kit.fill(lens, tone.fill.opacity(tone.fillOpacity))
                kit.ink(lens, tone.ink, width: 0.06)
            }
            kit.ink(bridge, tone.ink, width: 0.05)
            for center in [(CGFloat(0.28), CGFloat(0.5)), (0.72, 0.5)] {
                kit.ink(
                    kit.polyline([(center.0 - 0.07, center.1 - 0.03), (center.0 - 0.02, center.1 - 0.09)]),
                    .white.opacity(0.85),
                    width: 0.03
                )
            }
        },
        make("sticker.crown", [
            NookStickerTones(0xFFD23F, accent: 0xFFB020, second: 0xFF4D6D, ink: 0x8A5A00),
            NookStickerTones(0xDDF4FF, accent: 0x8ADCFF, second: 0xB79CFF, ink: 0x2F5F9A),
            NookStickerTones(0xFFC2CF, accent: 0xFF9CB0, second: 0xFFFFFF, ink: 0xA3475C),
        ]) { kit, tone in
            let crown = kit.polygon([
                (0.15, 0.74), (0.15, 0.36), (0.325, 0.53), (0.5, 0.24), (0.675, 0.53), (0.85, 0.36), (0.85, 0.74),
            ])
            let tips = [kit.circle(0.15, 0.32, 0.045), kit.circle(0.5, 0.2, 0.045), kit.circle(0.85, 0.32, 0.045)]
            kit.rim(tips.reduce(crown) { $0.union($1) })
            kit.fill(crown, tone.fill)
            kit.fill(kit.box(0.15, 0.64, 0.85, 0.74), tone.accent)
            kit.ink(kit.polyline([(0.15, 0.64), (0.85, 0.64)]), tone.ink, width: 0.03)
            kit.ink(crown, tone.ink)
            for tip in tips { kit.shape(tip, fill: tone.second, ink: tone.ink, width: 0.03) }
            for x in [CGFloat(0.32), 0.5, 0.68] {
                kit.fill(kit.circle(x, 0.69, 0.03), tone.second)
            }
        },
        make("sticker.duck", [
            NookStickerTones(0xFFD23F, accent: 0xFF8A1F, ink: 0x8A5A00),
            NookStickerTones(0x3B3B55, accent: 0xFFB020, ink: 0x14142B),
            NookStickerTones(0xFF9CC8, accent: 0xFFE94A, ink: 0xA31560),
        ]) { kit, tone in
            let duck = kit.ellipse(0.46, 0.64, width: 0.64, height: 0.44)
                .union(kit.polygon([(0.18, 0.52), (0.1, 0.44), (0.24, 0.48)]))
                .union(kit.circle(0.62, 0.36, 0.17))
            let beak = kit.ellipse(0.82, 0.4, width: 0.16, height: 0.09)
            kit.rim(duck.union(beak))
            kit.shape(beak, fill: tone.accent, ink: tone.ink, width: 0.03)
            kit.shape(duck, fill: tone.fill, ink: tone.ink)
            kit.fill(kit.circle(0.66, 0.32, 0.03), tone.ink)
            kit.ink(kit.arc(0.42, 0.64, 0.13, from: 20, to: 160), tone.ink, width: 0.035)
        },
        make("sticker.mug", [
            NookStickerTones(0xFFFFFF, accent: 0x6B3F1F, second: 0xFF4D6D, ink: 0x2B2B33),
            NookStickerTones(0x2B2B45, accent: 0x8A5A2B, second: 0xFFE94A, ink: 0x0F0F24),
            NookStickerTones(0xB6E3A8, accent: 0x5FA84A, second: 0xFFFFFF, ink: 0x2F5F2A),
        ]) { kit, tone in
            let handle = kit.arc(0.69, 0.62, 0.12, from: -70, to: 70)
            let mug = kit.box(0.2, 0.42, 0.68, 0.86, radius: 0.08)
            let steam = [CGFloat(0), 0.2].map { shift in
                kit.curve(from: (shift, 0)) { wisp in
                    wisp.move(0.34, 0.34)
                    wisp.quad(0.28, 0.27, 0.34, 0.2)
                    wisp.quad(0.4, 0.13, 0.34, 0.08)
                }
            }
            var silhouette = mug.union(kit.body(of: handle, width: 0.11))
            for wisp in steam { silhouette = silhouette.union(kit.body(of: wisp, width: 0.08)) }
            kit.rim(silhouette)
            kit.ink(handle, tone.ink, width: 0.11)
            kit.ink(handle, tone.fill, width: 0.06)
            kit.fill(mug, tone.fill)
            NookStickerKit(pen: kit.pen.clipped(to: mug)).fill(kit.box(0.2, 0.42, 0.68, 0.5), tone.accent)
            kit.ink(mug, tone.ink)
            kit.fill(kit.heart(0.44, 0.68, width: 0.16), tone.second)
            for wisp in steam {
                kit.ink(wisp, tone.ink, width: 0.08)
                kit.ink(wisp, .white, width: 0.04)
            }
        },
    ]
}
