import SwiftUI

/// The stickers, in picker order. Each is drawn in a unit square with a
/// white rim and a soft shadow under it, like one peeled off a sheet, and
/// comes in three colorways. The words a few of them carry are part of
/// the drawing and are not translated.
enum NookMirrorStickerDesigns {
    static let all: [NookMirrorStickerDesign] = hearts + stars + bows + clouds + flowers
        + fruit + moons + lightning + bubbles + props

    /// A design from its colorways and the drawing they share. The name
    /// key follows the id: `sticker.bolt` is named by `nook.mirror.sticker.bolt`.
    static func make(
        _ id: String,
        _ tones: [NookStickerTones],
        _ draw: @escaping @Sendable (NookStickerKit, NookStickerTones) -> Void
    ) -> NookMirrorStickerDesign {
        NookMirrorStickerDesign(id: id, nameKey: "nook.mirror.\(id)", variants: tones.count) { pen, variant in
            guard tones.indices.contains(variant) else { return }
            draw(NookStickerKit(pen: pen), tones[variant])
        }
    }

    private static let shine = Color.white.opacity(0.8)

    // MARK: Hearts

    private static let hearts: [NookMirrorStickerDesign] = [
        make("sticker.heart.puffy", [
            NookStickerTones(0xFF4D6D, ink: 0xB3123A),
            NookStickerTones(0xFF8FC7, ink: 0xC2317F),
            NookStickerTones(0xB79CFF, ink: 0x5B3FD1),
        ]) { kit, tone in
            let heart = kit.heart(0.5, 0.5, width: 0.78)
            kit.rim(heart)
            kit.shape(heart, fill: tone.fill, ink: tone.ink)
            kit.ink(kit.arc(0.34, 0.36, 0.1, from: 180, to: 270), shine, width: 0.05)
            kit.fill(kit.circle(0.25, 0.46, 0.025), shine)
        },
        make("sticker.heart.pixel", [
            NookStickerTones(0xFF3D5A, ink: 0xFF3D5A),
            NookStickerTones(0x3DF2A0, ink: 0x3DF2A0),
            NookStickerTones(0xFFD23F, ink: 0xFFD23F),
        ]) { kit, tone in
            let rows: [[Int]] = [
                [0, 1, 1, 0, 1, 1, 0],
                [1, 1, 1, 1, 1, 1, 1],
                [1, 1, 1, 1, 1, 1, 1],
                [0, 1, 1, 1, 1, 1, 0],
                [0, 0, 1, 1, 1, 0, 0],
                [0, 0, 0, 1, 0, 0, 0],
            ]
            let cell: CGFloat = 0.11
            let origin: (x: CGFloat, y: CGFloat) = (0.115, 0.17)
            var cells = Path()
            var grown = Path()
            for (row, columns) in rows.enumerated() {
                for (column, isFilled) in columns.enumerated() where isFilled == 1 {
                    let left = origin.x + CGFloat(column) * cell
                    let top = origin.y + CGFloat(row) * cell
                    // A hair of overlap keeps seams from showing between cells.
                    cells.addPath(kit.box(left, top, left + cell + 0.004, top + cell + 0.004))
                    grown = grown.union(kit.box(left - 0.045, top - 0.045, left + cell + 0.045, top + cell + 0.045))
                }
            }
            kit.pen.backing(grown, rim: 0)
            kit.fill(cells, tone.fill)
            kit.fill(kit.box(origin.x + cell, origin.y + cell, origin.x + 2 * cell, origin.y + 2 * cell), .white.opacity(0.85))
        },
        make("sticker.heart.twin", [
            NookStickerTones(0xFF6FA8, second: 0xFFC2DC, ink: 0xB3246B),
            NookStickerTones(0xFF5A47, second: 0xFFB020, ink: 0xA32218),
            NookStickerTones(0x6FA8FF, second: 0xB8E4FF, ink: 0x2447A8),
        ]) { kit, tone in
            let back = kit.heart(0.63, 0.4, width: 0.46, turned: 14)
            let front = kit.heart(0.4, 0.58, width: 0.56, turned: -10)
            kit.rim(back.union(front))
            kit.shape(back, fill: tone.second, ink: tone.ink)
            kit.shape(front, fill: tone.fill, ink: tone.ink)
        },
    ]

    // MARK: Stars and sparkles

    private static let stars: [NookMirrorStickerDesign] = [
        make("sticker.star.chunky", [
            NookStickerTones(0xFFD23F, ink: 0xB37A00),
            NookStickerTones(0x7DD6FF, ink: 0x1D6FA8),
            NookStickerTones(0xFF5FA8, ink: 0xA31560),
        ]) { kit, tone in
            let star = kit.star(0.5, 0.53, outer: 0.42, inner: 0.2)
            kit.rim(star)
            kit.shape(star, fill: tone.fill, ink: tone.ink, width: 0.05)
            kit.fill(kit.circle(0.42, 0.4, 0.035), shine)
        },
        make("sticker.star.shooting", [
            NookStickerTones(0xFFE94A, accent: 0xFF8A1F, second: 0xFFC266, ink: 0xB38600),
            NookStickerTones(0xFFFFFF, accent: 0x5CC8FF, second: 0xB8E4FF, ink: 0x3B6FB3),
            NookStickerTones(0xFFC2DC, accent: 0xFF5FA8, second: 0xB79CFF, ink: 0xB3246B),
        ]) { kit, tone in
            let star = kit.star(0.63, 0.38, outer: 0.26, inner: 0.12, turned: 15)
            let trails: [(Path, CGFloat, Color)] = [
                (kit.polyline([(0.46, 0.56), (0.16, 0.86)]), 0.07, tone.accent),
                (kit.polyline([(0.38, 0.46), (0.14, 0.7)]), 0.05, tone.second),
                (kit.polyline([(0.56, 0.66), (0.36, 0.86)]), 0.05, tone.second),
            ]
            var silhouette = star
            for trail in trails {
                silhouette = silhouette.union(kit.body(of: trail.0, width: trail.1))
            }
            kit.rim(silhouette)
            for trail in trails {
                kit.ink(trail.0, trail.2, width: trail.1)
            }
            kit.shape(star, fill: tone.fill, ink: tone.ink)
        },
        make("sticker.seal", [
            NookStickerTones(0x22C55E, accent: 0xFFFFFF, ink: 0x0F7A37),
            NookStickerTones(0x4D7CFF, accent: 0xFFFFFF, ink: 0x1D3FA8),
            NookStickerTones(0xFFB020, accent: 0x3A2500, ink: 0x9A5B00),
        ]) { kit, tone in
            let seal = kit.star(0.5, 0.5, outer: 0.42, inner: 0.34, points: 12)
            kit.rim(seal)
            kit.shape(seal, fill: tone.fill, ink: tone.ink)
            kit.ink(kit.circle(0.5, 0.5, 0.26), .white.opacity(0.85), width: 0.03)
            kit.ink(kit.polyline([(0.36, 0.51), (0.46, 0.61), (0.66, 0.39)]), tone.accent, width: 0.09)
        },
        make("sticker.sparkle.big", [
            NookStickerTones(0xFFF3B0, ink: 0xB38600),
            NookStickerTones(0xDDF4FF, ink: 0x2F7FB3),
            NookStickerTones(0xFFD1E8, ink: 0xC2317F),
        ]) { kit, tone in
            let sparkle = kit.sparkle(0.5, 0.5, 0.42)
            kit.rim(sparkle)
            kit.shape(sparkle, fill: tone.fill, ink: tone.ink)
            kit.fill(kit.sparkle(0.5, 0.5, 0.16), .white.opacity(0.85))
        },
        make("sticker.sparkle.trio", [
            NookStickerTones(0xFFE94A, accent: 0xFFFFFF, second: 0xFFB020, ink: 0x9A6B00),
            NookStickerTones(0x7DF2C0, accent: 0x7DD6FF, second: 0xB79CFF, ink: 0x1F6F6A),
            NookStickerTones(0xFF8FC7, accent: 0xFFFFFF, second: 0xFFC2DC, ink: 0xB3246B),
        ]) { kit, tone in
            let big = kit.sparkle(0.38, 0.58, 0.3)
            let middle = kit.sparkle(0.74, 0.3, 0.17)
            let small = kit.sparkle(0.76, 0.76, 0.11)
            kit.rim(big.union(middle).union(small))
            kit.shape(big, fill: tone.fill, ink: tone.ink, width: 0.04)
            kit.shape(middle, fill: tone.accent, ink: tone.ink, width: 0.04)
            kit.shape(small, fill: tone.second, ink: tone.ink, width: 0.04)
        },
    ]

    // MARK: Bows

    private static let bows: [NookMirrorStickerDesign] = [
        make("sticker.bow.ribbon", [
            NookStickerTones(0xFF9CC8, accent: 0xFF6FA8, ink: 0xB3246B),
            NookStickerTones(0xFFE9A8, accent: 0xFFD23F, ink: 0x9A6B00),
            NookStickerTones(0x5B5BD6, accent: 0x3F3FA8, ink: 0x1E1E5C),
        ]) { kit, tone in
            let knot: (CGFloat, CGFloat) = (0.5, 0.44)
            let sides = [false, true]
            let tails = sides.map { mirrored in
                kit.curve(from: knot, mirrored: mirrored) { tail in
                    tail.move(-0.05, 0.04)
                    tail.line(-0.26, 0.38)
                    tail.line(-0.15, 0.36)
                    tail.line(-0.1, 0.46)
                    tail.line(0.03, 0.1)
                    tail.close()
                }
            }
            let loops = sides.map { mirrored in
                kit.curve(from: knot, mirrored: mirrored) { loop in
                    loop.move(0, 0)
                    loop.cubic(-0.09, -0.13, -0.27, -0.22, -0.36, -0.15)
                    loop.cubic(-0.42, -0.09, -0.42, 0.09, -0.36, 0.15)
                    loop.cubic(-0.27, 0.22, -0.09, 0.13, 0, 0)
                    loop.close()
                }
            }
            let tie = kit.box(0.43, 0.35, 0.57, 0.53, radius: 0.05)
            kit.rim((tails + loops).reduce(tie) { $0.union($1) })
            for tail in tails { kit.shape(tail, fill: tone.accent, ink: tone.ink) }
            for loop in loops { kit.shape(loop, fill: tone.fill, ink: tone.ink) }
            for mirrored in sides {
                let crease = kit.curve(from: knot, mirrored: mirrored) { line in
                    line.move(-0.07, 0)
                    line.line(-0.22, -0.02)
                }
                kit.ink(crease, tone.ink, width: 0.03)
            }
            kit.shape(tie, fill: tone.accent, ink: tone.ink)
        },
        make("sticker.bow.polka", [
            NookStickerTones(0xFF7FB0, accent: 0xFF4D8B, ink: 0xA31560),
            NookStickerTones(0x6FA8FF, accent: 0x3F7BFF, ink: 0x1D3FA8),
            NookStickerTones(0x9BE38A, accent: 0x5CC060, ink: 0x2F7A33),
        ]) { kit, tone in
            let knot: (CGFloat, CGFloat) = (0.5, 0.5)
            let loops = [false, true].map { mirrored in
                kit.curve(from: knot, mirrored: mirrored) { loop in
                    loop.move(-0.04, 0)
                    loop.cubic(-0.14, -0.2, -0.32, -0.3, -0.38, -0.24)
                    loop.cubic(-0.41, -0.16, -0.41, 0.16, -0.38, 0.24)
                    loop.cubic(-0.32, 0.3, -0.14, 0.2, -0.04, 0)
                    loop.close()
                }
            }
            let tie = kit.circle(0.5, 0.5, 0.09)
            kit.rim(loops.reduce(tie) { $0.union($1) })
            for loop in loops { kit.shape(loop, fill: tone.fill, ink: tone.ink) }
            for dot in [(CGFloat(-0.26), CGFloat(-0.1)), (-0.2, 0.08), (-0.32, 0.06)] {
                kit.fill(kit.circle(0.5 + dot.0, 0.5 + dot.1, 0.035), .white.opacity(0.9))
                kit.fill(kit.circle(0.5 - dot.0, 0.5 + dot.1, 0.035), .white.opacity(0.9))
            }
            kit.shape(tie, fill: tone.accent, ink: tone.ink)
        },
    ]

    // MARK: Clouds

    private static let clouds: [NookMirrorStickerDesign] = [
        make("sticker.cloud.happy", [
            NookStickerTones(0xFFFFFF, accent: 0xFF9CC8, ink: 0x5B7FB3),
            NookStickerTones(0xFFD9E8, accent: 0xFF6FA8, ink: 0xB3246B),
            NookStickerTones(0xC9D3E6, accent: 0x7DD6FF, ink: 0x3B4A66),
        ]) { kit, tone in
            let cloud = kit.circle(0.3, 0.56, 0.17)
                .union(kit.circle(0.48, 0.44, 0.21))
                .union(kit.circle(0.68, 0.52, 0.18))
                .union(kit.box(0.15, 0.52, 0.85, 0.74, radius: 0.11))
            kit.rim(cloud)
            kit.shape(cloud, fill: tone.fill, ink: tone.ink)
            kit.fill(kit.circle(0.33, 0.62, 0.035), tone.accent.opacity(0.7))
            kit.fill(kit.circle(0.67, 0.62, 0.035), tone.accent.opacity(0.7))
            kit.fill(kit.circle(0.41, 0.56, 0.028), tone.ink)
            kit.fill(kit.circle(0.59, 0.56, 0.028), tone.ink)
            kit.ink(kit.arc(0.5, 0.585, 0.05, from: 20, to: 160), tone.ink, width: 0.03)
        },
        make("sticker.cloud.rain", [
            NookStickerTones(0xDDE6F5, accent: 0x5CC8FF, ink: 0x3B4A66),
            NookStickerTones(0xFFFFFF, accent: 0xFF8FC7, ink: 0x7A4FB3),
            NookStickerTones(0x6B7690, accent: 0xFFE94A, ink: 0x1F2738),
        ]) { kit, tone in
            let cloud = kit.circle(0.3, 0.4, 0.16)
                .union(kit.circle(0.48, 0.3, 0.2))
                .union(kit.circle(0.68, 0.37, 0.17))
                .union(kit.box(0.15, 0.37, 0.85, 0.57, radius: 0.1))
            let drops = [kit.drop(0.32, 0.76, 0.045), kit.drop(0.5, 0.84, 0.045), kit.drop(0.68, 0.76, 0.045)]
            kit.rim(drops.reduce(cloud) { $0.union($1) })
            kit.shape(cloud, fill: tone.fill, ink: tone.ink)
            for drop in drops { kit.shape(drop, fill: tone.accent, ink: tone.ink, width: 0.03) }
        },
    ]

    // MARK: Flowers

    private static let flowers: [NookMirrorStickerDesign] = [
        make("sticker.flower.daisy", [
            NookStickerTones(0xFFFFFF, accent: 0xFFD23F, ink: 0x8A6A00),
            NookStickerTones(0xFF9CC8, accent: 0xFFE94A, ink: 0xB3246B),
            NookStickerTones(0xB8C4FF, accent: 0xFFF3B0, ink: 0x3F4FB3),
        ]) { kit, tone in
            let petals = (0..<8).map { index -> Path in
                let degrees = CGFloat(index) * 45
                let angle = degrees * .pi / 180
                return kit.ellipse(
                    0.5 + cos(angle) * 0.25, 0.5 + sin(angle) * 0.25, width: 0.3, height: 0.16, turned: degrees
                )
            }
            let center = kit.circle(0.5, 0.5, 0.13)
            kit.rim(petals.reduce(center) { $0.union($1) })
            for petal in petals { kit.shape(petal, fill: tone.fill, ink: tone.ink, width: 0.035) }
            kit.shape(center, fill: tone.accent, ink: tone.ink)
            for dot in [(CGFloat(0.46), CGFloat(0.47)), (0.54, 0.48), (0.5, 0.55)] {
                kit.fill(kit.circle(dot.0, dot.1, 0.02), tone.ink.opacity(0.5))
            }
        },
        make("sticker.flower.tulip", [
            NookStickerTones(0xFF5A6E, accent: 0x3DBF6B, ink: 0x8A1F33),
            NookStickerTones(0xFFD23F, accent: 0x3DBF6B, ink: 0x8A6A00),
            NookStickerTones(0xC9A0FF, accent: 0x5FCF9A, ink: 0x5B3FB3),
        ]) { kit, tone in
            let bloom = kit.curve { bloom in
                bloom.move(0.28, 0.16)
                bloom.cubic(0.24, 0.4, 0.36, 0.56, 0.5, 0.56)
                bloom.cubic(0.64, 0.56, 0.76, 0.4, 0.72, 0.16)
                bloom.line(0.61, 0.3)
                bloom.line(0.5, 0.14)
                bloom.line(0.39, 0.3)
                bloom.close()
            }
            let stem = kit.polyline([(0.5, 0.56), (0.5, 0.88)])
            let leaf = kit.curve { leaf in
                leaf.move(0.5, 0.82)
                leaf.quad(0.3, 0.78, 0.24, 0.58)
                leaf.quad(0.42, 0.64, 0.5, 0.82)
                leaf.close()
            }
            kit.rim(bloom.union(leaf).union(kit.body(of: stem, width: 0.06)))
            kit.ink(stem, tone.accent, width: 0.06)
            kit.shape(leaf, fill: tone.accent, ink: tone.ink, width: 0.03)
            kit.shape(bloom, fill: tone.fill, ink: tone.ink)
        },
        make("sticker.flower.bloom", [
            NookStickerTones(0xFFC2DC, accent: 0xFF5FA8, ink: 0xB3246B),
            NookStickerTones(0xFFE94A, accent: 0xFF8A1F, ink: 0x9A6B00),
            NookStickerTones(0x8ADCFF, accent: 0xFFFFFF, ink: 0x1D6FA8),
        ]) { kit, tone in
            var bloom = Path()
            for degrees in [CGFloat(-90), -18, 54, 126, 198] {
                let angle = degrees * .pi / 180
                bloom = bloom.union(kit.circle(0.5 + cos(angle) * 0.21, 0.5 + sin(angle) * 0.21, 0.17))
            }
            kit.rim(bloom)
            kit.shape(bloom, fill: tone.fill, ink: tone.ink)
            kit.fill(kit.star(0.5, 0.5, outer: 0.1, inner: 0.045), tone.accent)
        },
    ]
}
