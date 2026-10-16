import Foundation

/// The design kit's sample shelf for the `kit` script (D53, D65): two
/// palettes, a few recent picks and four links, written as the kit's own
/// `palettes.json` and `links.json` in the demo's temporary folder. The
/// owner's real files are never read or written.
enum DemoDesign {
    struct SampleColor: Sendable {
        let name: String
        let red: UInt8
        let green: UInt8
        let blue: UInt8

        var color: NookDesignColor { NookDesignColor(red: red, green: green, blue: blue) }
    }

    /// The palette the card shows. The first color is a favorite.
    static let brand: [SampleColor] = [
        SampleColor(name: "Tangerine", red: 255, green: 107, blue: 53),
        SampleColor(name: "Sun", red: 247, green: 197, blue: 72),
        SampleColor(name: "Lagoon", red: 46, green: 196, blue: 182),
        SampleColor(name: "Ocean", red: 58, green: 134, blue: 255),
        SampleColor(name: "Iris", red: 131, green: 56, blue: 236),
        SampleColor(name: "Rose", red: 255, green: 77, blue: 109),
        SampleColor(name: "Paper", red: 240, green: 238, blue: 233),
        SampleColor(name: "Ink", red: 34, green: 34, blue: 34),
    ]

    static let website: [SampleColor] = [
        SampleColor(name: "Night", red: 18, green: 22, blue: 33),
        SampleColor(name: "Slate", red: 71, green: 85, blue: 105),
        SampleColor(name: "Mist", red: 226, green: 232, blue: 240),
        SampleColor(name: "Mint", red: 52, green: 211, blue: 153),
    ]

    /// Colors the eyedropper picked earlier, newest first.
    static let recents: [SampleColor] = [
        SampleColor(name: "", red: 236, green: 72, blue: 153),
        SampleColor(name: "", red: 14, green: 165, blue: 233),
        SampleColor(name: "", red: 250, green: 204, blue: 21),
    ]

    /// Addresses a designer keeps at hand. Nothing is fetched from them.
    static let links: [(name: String, url: String)] = [
        ("Portfolio, home page", "https://www.figma.com/design/q9ZkD2sample/Portfolio"),
        ("Inter", "https://fonts.google.com/specimen/Inter"),
        ("Trending palettes", "https://coolors.co/palettes/trending"),
        ("Grid systems", "https://www.designsystems.com/space-grids-and-layouts"),
    ]

    static let brandName = "Brand"
    static let websiteName = "Website"
    static let collectionName = "Inspiration"

    /// The library the card reads.
    static func library(now: Date) -> NookDesignLibrary {
        let global = NookDesignCollection.globalID
        func swatches(_ colors: [SampleColor], favorite: Bool) -> [NookDesignSwatch] {
            colors.enumerated().map { index, sample in
                NookDesignSwatch(
                    id: UUID(), color: sample.color, name: sample.name,
                    isFavorite: favorite && index == 0,
                    addedAt: now.addingTimeInterval(-TimeInterval(colors.count - index) * 3600)
                )
            }
        }
        let brandPalette = NookDesignPalette(
            id: UUID(), collectionID: global, name: brandName,
            swatches: swatches(brand, favorite: true), createdAt: now.addingTimeInterval(-86_400 * 3)
        )
        let websitePalette = NookDesignPalette(
            id: UUID(), collectionID: global, name: websiteName,
            swatches: swatches(website, favorite: false), createdAt: now.addingTimeInterval(-86_400 * 2)
        )
        var library = NookDesignLibrary()
        library.palettes = [brandPalette, websitePalette]
        library.recents = recents.enumerated().map { index, sample in
            NookDesignRecentColor(
                id: UUID(), collectionID: global, color: sample.color,
                pickedAt: now.addingTimeInterval(-TimeInterval(index + 1) * 900)
            )
        }
        library.activePaletteIDs = [global.uuidString: brandPalette.id]
        return library
    }

    /// The links tab's shelf: every link in one collection.
    static func linkLibrary(now: Date) -> NookDesignLinkLibrary {
        let collection = NookDesignLinkCollection(
            id: UUID(), name: collectionName, createdAt: now.addingTimeInterval(-86_400 * 5)
        )
        var library = NookDesignLinkLibrary()
        library.collections = [collection]
        library.links = links.enumerated().map { index, link in
            NookDesignLink(
                id: UUID(), url: link.url, name: link.name, collectionID: collection.id,
                isFavorite: index == 0,
                addedAt: now.addingTimeInterval(-TimeInterval(index + 1) * 7200),
                lastOpenedAt: nil
            )
        }
        return library
    }

    /// Writes both files into `folder`, the kit's folder of this run.
    @discardableResult
    static func write(in folder: URL, now: Date) -> Bool {
        let palettes = NookDesignLibraryFile.write(
            library(now: now), to: folder.appendingPathComponent(NookDesignLibraryFile.fileName)
        )
        let links = NookDesignLinkFile.write(
            linkLibrary(now: now), to: folder.appendingPathComponent(NookDesignLinkFile.fileName)
        )
        return palettes && links
    }
}
