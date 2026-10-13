import Foundation

/// The collections the design kit files things under. There is one for
/// now, Global. A later project selector adds more by writing a list of
/// them beside the stores, and every saved palette, recent color and
/// reference already carries the id of the one it belongs to. An id no
/// list knows is shown under Global.
enum NookDesignCollection {
    /// The built-in collection for things used everywhere.
    static let globalID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
}

/// One saved color in a palette. It belongs to its palette's collection.
struct NookDesignSwatch: Identifiable, Hashable, Sendable {
    var id: UUID
    var color: NookDesignColor
    /// Empty when the color has no name.
    var name: String
    var isFavorite: Bool
    var addedAt: Date
}

/// A named list of colors.
struct NookDesignPalette: Identifiable, Hashable, Sendable {
    var id: UUID
    var collectionID: UUID
    var name: String
    var swatches: [NookDesignSwatch]
    var createdAt: Date
}

/// A color the eyedropper picked, kept apart from the palettes.
struct NookDesignRecentColor: Identifiable, Hashable, Sendable {
    var id: UUID
    var collectionID: UUID
    var color: NookDesignColor
    var pickedAt: Date
}

/// What adding a color came to.
enum NookDesignAddOutcome: Equatable, Sendable {
    case added(NookDesignLibrary, NookDesignSwatch)
    /// The palette already holds this exact color.
    case duplicate(NookDesignSwatch)
    /// The palette holds as many colors as it may.
    case full
    case noPalette
}

/// Everything the color shelf saves: the palettes, the recent picks and
/// which palette is the active one in each collection. A plain value. The
/// editing rules below each return a changed copy, and the store saves it.
struct NookDesignLibrary: Equatable, Sendable {
    static let currentVersion = 1
    static let maxPalettes = 100
    static let maxSwatchesPerPalette = 256
    static let maxRecents = 12
    static let maxNameLength = 60

    var version = NookDesignLibrary.currentVersion
    var palettes: [NookDesignPalette] = []
    var recents: [NookDesignRecentColor] = []
    /// The active palette of each collection, by the collection's id.
    var activePaletteIDs: [String: UUID] = [:]

    static let empty = NookDesignLibrary()

    // MARK: Reading

    func palettes(in collectionID: UUID = NookDesignCollection.globalID) -> [NookDesignPalette] {
        palettes.filter { $0.collectionID == collectionID }
    }

    func palette(_ id: UUID) -> NookDesignPalette? {
        palettes.first { $0.id == id }
    }

    /// The palette new colors go to: the chosen one, or the first when the
    /// choice is gone.
    func activePalette(in collectionID: UUID = NookDesignCollection.globalID) -> NookDesignPalette? {
        let own = palettes(in: collectionID)
        if let id = activePaletteIDs[collectionID.uuidString], let chosen = own.first(where: { $0.id == id }) {
            return chosen
        }
        return own.first
    }

    func recents(in collectionID: UUID = NookDesignCollection.globalID) -> [NookDesignRecentColor] {
        recents.filter { $0.collectionID == collectionID }
    }

    /// The swatch in a palette that already has this color.
    func existingSwatch(_ color: NookDesignColor, in paletteID: UUID) -> NookDesignSwatch? {
        palette(paletteID)?.swatches.first { $0.color == color }
    }

    /// Swatches that repeat a color an earlier swatch of the palette has.
    /// The app never adds one, but a file edited by hand can hold them.
    func duplicateSwatchIDs(in paletteID: UUID) -> Set<UUID> {
        var seen = Set<NookDesignColor>()
        var repeats = Set<UUID>()
        for swatch in palette(paletteID)?.swatches ?? [] where !seen.insert(swatch.color).inserted {
            repeats.insert(swatch.id)
        }
        return repeats
    }

    /// The order the compact card shows a palette in: favorites first,
    /// then the rest, each group in the palette's own order.
    static func compactOrder(_ swatches: [NookDesignSwatch]) -> [NookDesignSwatch] {
        swatches.filter(\.isFavorite) + swatches.filter { !$0.isFavorite }
    }

    /// A name as it is kept (`NookDesignNames.clean`).
    static func cleanName(_ name: String) -> String {
        NookDesignNames.clean(name, limit: maxNameLength)
    }

    // MARK: Palettes

    /// Adds an empty palette and makes it the active one. Nil when there
    /// are as many palettes as there may be.
    func addingPalette(
        named name: String,
        in collectionID: UUID = NookDesignCollection.globalID,
        id: UUID = UUID(),
        now: Date = NookDesignFiles.now()
    ) -> (library: NookDesignLibrary, palette: NookDesignPalette)? {
        guard palettes.count < Self.maxPalettes else { return nil }
        let palette = NookDesignPalette(
            id: id,
            collectionID: collectionID,
            name: Self.cleanName(name),
            swatches: [],
            createdAt: now
        )
        var result = self
        result.palettes.append(palette)
        result.activePaletteIDs[collectionID.uuidString] = id
        return (result, palette)
    }

    func renamingPalette(_ id: UUID, to name: String) -> NookDesignLibrary {
        updatingPalette(id) { $0.name = Self.cleanName(name) }
    }

    /// Removes a palette and its colors. The collection's active palette
    /// falls back to the first one left.
    func removingPalette(_ id: UUID) -> NookDesignLibrary {
        guard let removed = palette(id) else { return self }
        var result = self
        result.palettes.removeAll { $0.id == id }
        let key = removed.collectionID.uuidString
        if result.activePaletteIDs[key] == id {
            result.activePaletteIDs[key] = result.palettes(in: removed.collectionID).first?.id
        }
        return result
    }

    func settingActivePalette(_ id: UUID) -> NookDesignLibrary {
        guard let palette = palette(id) else { return self }
        var result = self
        result.activePaletteIDs[palette.collectionID.uuidString] = id
        return result
    }

    // MARK: Colors

    /// Adds a color to the end of a palette, unless the palette already
    /// has that exact color.
    func addingColor(
        _ color: NookDesignColor,
        named name: String = "",
        to paletteID: UUID,
        id: UUID = UUID(),
        now: Date = NookDesignFiles.now()
    ) -> NookDesignAddOutcome {
        guard let palette = palette(paletteID) else { return .noPalette }
        if let existing = existingSwatch(color, in: paletteID) { return .duplicate(existing) }
        guard palette.swatches.count < Self.maxSwatchesPerPalette else { return .full }
        let swatch = NookDesignSwatch(id: id, color: color, name: Self.cleanName(name), isFavorite: false, addedAt: now)
        return .added(updatingPalette(paletteID) { $0.swatches.append(swatch) }, swatch)
    }

    func renamingSwatch(_ id: UUID, to name: String) -> NookDesignLibrary {
        updatingSwatch(id) { $0.name = Self.cleanName(name) }
    }

    func togglingFavorite(_ id: UUID) -> NookDesignLibrary {
        updatingSwatch(id) { $0.isFavorite.toggle() }
    }

    func removingSwatch(_ id: UUID) -> NookDesignLibrary {
        var result = self
        for index in result.palettes.indices {
            result.palettes[index].swatches.removeAll { $0.id == id }
        }
        return result
    }

    /// Moves a swatch to `index` within its palette, clamped to the list.
    func movingSwatch(_ id: UUID, to index: Int) -> NookDesignLibrary {
        guard let paletteIndex = palettes.firstIndex(where: { palette in palette.swatches.contains { $0.id == id } }),
              let from = palettes[paletteIndex].swatches.firstIndex(where: { $0.id == id }) else {
            return self
        }
        var result = self
        let swatch = result.palettes[paletteIndex].swatches.remove(at: from)
        let target = min(max(0, index), result.palettes[paletteIndex].swatches.count)
        result.palettes[paletteIndex].swatches.insert(swatch, at: target)
        return result
    }

    /// Moves a swatch one place toward the front or the back.
    func nudgingSwatch(_ id: UUID, by offset: Int) -> NookDesignLibrary {
        for palette in palettes {
            if let index = palette.swatches.firstIndex(where: { $0.id == id }) {
                return movingSwatch(id, to: index + offset)
            }
        }
        return self
    }

    /// Removes every swatch that repeats an earlier color of the palette.
    func removingDuplicates(in paletteID: UUID) -> NookDesignLibrary {
        let repeats = duplicateSwatchIDs(in: paletteID)
        guard !repeats.isEmpty else { return self }
        return updatingPalette(paletteID) { $0.swatches.removeAll { repeats.contains($0.id) } }
    }

    // MARK: Recent picks

    /// Puts a picked color at the front of the recent list. A color
    /// already there moves up and adds no entry, and the list keeps the
    /// newest `maxRecents` of each collection.
    func recordingRecent(
        _ color: NookDesignColor,
        in collectionID: UUID = NookDesignCollection.globalID,
        id: UUID = UUID(),
        now: Date = NookDesignFiles.now()
    ) -> NookDesignLibrary {
        var result = self
        let known = result.recents.first { $0.collectionID == collectionID && $0.color == color }
        result.recents.removeAll { $0.collectionID == collectionID && $0.color == color }
        let entry = NookDesignRecentColor(id: known?.id ?? id, collectionID: collectionID, color: color, pickedAt: now)
        result.recents.insert(entry, at: 0)
        var kept = 0
        result.recents.removeAll { recent in
            guard recent.collectionID == collectionID else { return false }
            kept += 1
            return kept > Self.maxRecents
        }
        return result
    }

    func removingRecent(_ id: UUID) -> NookDesignLibrary {
        var result = self
        result.recents.removeAll { $0.id == id }
        return result
    }

    func clearingRecents(in collectionID: UUID = NookDesignCollection.globalID) -> NookDesignLibrary {
        var result = self
        result.recents.removeAll { $0.collectionID == collectionID }
        return result
    }

    // MARK: Cleaning up loaded data

    /// The library made safe to show: ids are unique, names are clean,
    /// nothing is over its limit and every active palette exists. A
    /// palette or a color whose id repeats gets a new id and is kept.
    /// Colors are never dropped for repeating, only for being over a limit.
    func sanitized() -> NookDesignLibrary {
        var result = NookDesignLibrary()
        var paletteIDs = Set<UUID>()
        var swatchIDs = Set<UUID>()
        for palette in palettes.prefix(Self.maxPalettes) {
            var clean = palette
            if !paletteIDs.insert(clean.id).inserted {
                clean.id = UUID()
                paletteIDs.insert(clean.id)
            }
            clean.name = Self.cleanName(palette.name)
            clean.swatches = palette.swatches.prefix(Self.maxSwatchesPerPalette).map { swatch in
                var cleanSwatch = swatch
                if !swatchIDs.insert(cleanSwatch.id).inserted {
                    cleanSwatch.id = UUID()
                    swatchIDs.insert(cleanSwatch.id)
                }
                cleanSwatch.name = Self.cleanName(swatch.name)
                return cleanSwatch
            }
            result.palettes.append(clean)
        }
        var recentIDs = Set<UUID>()
        var recentColors = Set<String>()
        var perCollection: [UUID: Int] = [:]
        for recent in recents {
            let colorKey = recent.collectionID.uuidString + recent.color.hex()
            guard perCollection[recent.collectionID, default: 0] < Self.maxRecents,
                  !recentIDs.contains(recent.id),
                  recentColors.insert(colorKey).inserted else { continue }
            recentIDs.insert(recent.id)
            perCollection[recent.collectionID, default: 0] += 1
            result.recents.append(recent)
        }
        for (key, id) in activePaletteIDs {
            guard let palette = result.palette(id), palette.collectionID.uuidString == key else { continue }
            result.activePaletteIDs[key] = id
        }
        return result
    }

    /// How much of this library `clean` (its `sanitized()` form) does not
    /// hold: palettes and colors over a limit, and recent colors over a
    /// limit or repeating another. A color of a palette that was dropped
    /// whole is not counted again.
    func countLeftOut(by clean: NookDesignLibrary) -> Int {
        var count = palettes.count - clean.palettes.count
        for (kept, original) in zip(clean.palettes, palettes.prefix(clean.palettes.count)) {
            count += original.swatches.count - kept.swatches.count
        }
        return count + recents.count - clean.recents.count
    }

    // MARK: Private

    private func updatingPalette(_ id: UUID, _ change: (inout NookDesignPalette) -> Void) -> NookDesignLibrary {
        guard let index = palettes.firstIndex(where: { $0.id == id }) else { return self }
        var result = self
        change(&result.palettes[index])
        return result
    }

    private func updatingSwatch(_ id: UUID, _ change: (inout NookDesignSwatch) -> Void) -> NookDesignLibrary {
        var result = self
        for paletteIndex in result.palettes.indices {
            if let index = result.palettes[paletteIndex].swatches.firstIndex(where: { $0.id == id }) {
                change(&result.palettes[paletteIndex].swatches[index])
                return result
            }
        }
        return self
    }
}
