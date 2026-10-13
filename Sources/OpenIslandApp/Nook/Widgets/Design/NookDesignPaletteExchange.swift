import Foundation

/// One palette as it travels in a file: a name and its colors.
struct NookDesignExchangePalette: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        var name: String
        var color: NookDesignColor
        var isFavorite: Bool
    }

    var name: String
    var colors: [Entry]
}

/// What a palette file held.
struct NookDesignImport: Equatable, Sendable {
    var palettes: [NookDesignExchangePalette]
    /// Colors that could not be read, or were over a palette's limit.
    var skippedColors = 0
    /// Colors left out because their palette already had them.
    var duplicateColors = 0
    /// Palettes left out: past the limit, not an object, or with no color.
    var skippedPalettes = 0

    var colorCount: Int { palettes.reduce(0) { $0 + $1.colors.count } }
}

enum NookDesignImportError: Error, Equatable, Sendable {
    case tooLarge
    /// The file could not be opened or read at all.
    case unreadable
    case notJSON
    /// JSON, but with no color in it that could be read.
    case noColors
}

/// The file format palettes are exported to and imported from. It is
/// plain JSON, made to be written by hand or by a script.
///
/// One palette:
///
/// ```json
/// {
///   "format": "open-island-palette",
///   "version": 1,
///   "name": "Brand",
///   "colors": [
///     { "name": "Primary", "hex": "#FF8800", "favorite": true },
///     { "name": "Scrim", "hex": "#00000080" }
///   ]
/// }
/// ```
///
/// Several palettes use `"palettes": [ { "name": …, "colors": [ … ] } ]`
/// in place of `name` and `colors`.
///
/// Export always writes `hex`, as "#RRGGBB" or "#RRGGBBAA" with alpha.
/// Import is more forgiving. A color may be a bare string in place of an
/// object, its value may sit under `hex`, `color` or `value`, and the
/// value may be any text the color parser reads: HEX, `rgb()` or `hsl()`.
/// `name` and `favorite` are optional. A file that is only a list of
/// color strings is one palette with no name. A color that does not read
/// is left out and counted, and a color the same palette already has is
/// left out and counted apart. `format` and `version` are written for
/// other tools and are not required on import.
enum NookDesignPaletteExchange {
    static let formatName = "open-island-palette"
    static let version = 1
    /// A palette file larger than this is refused unread.
    static let maxFileBytes = 1_048_576
    static let fileExtension = "json"

    // MARK: Export

    static func export(_ palettes: [NookDesignPalette]) throws -> Data {
        var root: [String: Any] = ["format": formatName, "version": version]
        if palettes.count == 1, let only = palettes.first {
            root["name"] = only.name
            root["colors"] = colorObjects(only)
        } else {
            root["palettes"] = palettes.map { ["name": $0.name, "colors": colorObjects($0)] as [String: Any] }
        }
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    private static func colorObjects(_ palette: NookDesignPalette) -> [[String: Any]] {
        palette.swatches.map { swatch in
            var object: [String: Any] = ["hex": swatch.color.hex()]
            if !swatch.name.isEmpty { object["name"] = swatch.name }
            if swatch.isFavorite { object["favorite"] = true }
            return object
        }
    }

    /// "Brand.palette.json", with the characters a file name cannot hold
    /// taken out. `fallback` names a palette that has no usable name.
    static func fileName(for palettes: [NookDesignPalette], fallback: String) -> String {
        let raw = palettes.count == 1 ? (palettes.first?.name ?? "") : fallback
        let safe = raw
            .components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.controlCharacters))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return "\(safe.isEmpty ? fallback : safe).palette.\(fileExtension)"
    }

    // MARK: Import

    static func read(_ data: Data) throws(NookDesignImportError) -> NookDesignImport {
        guard data.count <= maxFileBytes else { throw .tooLarge }
        guard let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw .notJSON
        }

        var result = NookDesignImport(palettes: [])
        if let object = json as? [String: Any] {
            if let list = object["palettes"] as? [Any] {
                // Everything left out is counted: palettes past the limit,
                // entries that are not objects, and palettes with no color.
                result.skippedPalettes += max(0, list.count - NookDesignLibrary.maxPalettes)
                for item in list.prefix(NookDesignLibrary.maxPalettes) {
                    guard let palette = item as? [String: Any] else {
                        result.skippedPalettes += 1
                        continue
                    }
                    append(palette, to: &result)
                }
            } else {
                append(object, to: &result)
            }
        } else if let colors = json as? [Any] {
            append(["colors": colors], to: &result)
        }
        guard result.colorCount > 0 else { throw .noColors }
        return result
    }

    private static func append(_ object: [String: Any], to result: inout NookDesignImport) {
        guard let colors = object["colors"] as? [Any] else {
            result.skippedPalettes += 1
            return
        }
        var palette = NookDesignExchangePalette(
            name: NookDesignLibrary.cleanName(object["name"] as? String ?? ""),
            colors: []
        )
        var seen = Set<NookDesignColor>()
        for item in colors {
            guard let entry = entry(from: item) else {
                result.skippedColors += 1
                continue
            }
            guard seen.insert(entry.color).inserted else {
                result.duplicateColors += 1
                continue
            }
            guard palette.colors.count < NookDesignLibrary.maxSwatchesPerPalette else {
                result.skippedColors += 1
                continue
            }
            palette.colors.append(entry)
        }
        if palette.colors.isEmpty {
            result.skippedPalettes += 1
        } else {
            result.palettes.append(palette)
        }
    }

    private static func entry(from item: Any) -> NookDesignExchangePalette.Entry? {
        if let text = item as? String {
            return NookDesignColorParser.parse(text).map { .init(name: "", color: $0, isFavorite: false) }
        }
        guard let object = item as? [String: Any] else { return nil }
        let text = ["hex", "color", "value"].lazy.compactMap { object[$0] as? String }.first
        guard let text, let color = NookDesignColorParser.parse(text) else { return nil }
        return .init(
            name: NookDesignLibrary.cleanName(object["name"] as? String ?? ""),
            color: color,
            isFavorite: object["favorite"] as? Bool ?? false
        )
    }
}

extension NookDesignLibrary {
    /// Adds imported palettes as new palettes of a collection, up to the
    /// limit, and makes the first one active. `untitled` names a palette
    /// the file gave no name. Returns the library and how many were added.
    func importing(
        _ imported: NookDesignImport,
        in collectionID: UUID = NookDesignCollection.globalID,
        untitled: String,
        now: Date = NookDesignFiles.now()
    ) -> (library: NookDesignLibrary, added: Int) {
        var result = self
        var added = 0
        var firstID: UUID?
        for palette in imported.palettes where result.palettes.count < Self.maxPalettes {
            let id = UUID()
            let swatches = palette.colors.map { entry in
                NookDesignSwatch(id: UUID(), color: entry.color, name: entry.name, isFavorite: entry.isFavorite, addedAt: now)
            }
            result.palettes.append(NookDesignPalette(
                id: id,
                collectionID: collectionID,
                name: palette.name.isEmpty ? untitled : palette.name,
                swatches: swatches,
                createdAt: now
            ))
            firstID = firstID ?? id
            added += 1
        }
        if let firstID { result.activePaletteIDs[collectionID.uuidString] = firstID }
        return (result, added)
    }
}
