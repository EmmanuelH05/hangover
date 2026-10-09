import Foundation
import OSLog

/// Saves the mirror's decorations with the rest of the Nook settings and
/// reads them back. What comes back is always safe to show: a design this
/// build does not know is skipped, and data that cannot be read means no
/// decorations.
enum NookMirrorDecorationStore {
    static let key = "nook.mirror.decorations"

    private static let log = Logger(subsystem: "app.openisland", category: "nook.mirror")

    static func load(from defaults: UserDefaults) -> NookMirrorDecorationSet {
        guard let data = defaults.data(forKey: key) else { return .none }
        do {
            return try JSONDecoder().decode(NookMirrorDecorationSet.self, from: data).sanitized()
        } catch {
            log.error("The saved mirror decorations could not be read and were left off: \(error.localizedDescription, privacy: .public)")
            return .none
        }
    }

    static func save(_ decorations: NookMirrorDecorationSet, to defaults: UserDefaults) {
        guard !decorations.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        do {
            defaults.set(try JSONEncoder().encode(decorations), forKey: key)
        } catch {
            log.error("The mirror decorations could not be saved: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// What the picker and the sticker handles ask of the model. Each one swaps
// in a new set; the model saves it.
extension NookModel {
    func setMirrorFrame(_ id: String?) {
        mirrorDecorations = mirrorDecorations.settingFrame(id)
    }

    /// Puts a sticker on the mirror and selects it. False when the mirror
    /// is full or the design is not one this build has.
    @discardableResult
    func addMirrorSticker(_ designID: String) -> Bool {
        guard NookMirrorDesigns.sticker(designID) != nil,
              let added = mirrorDecorations.adding(designID: designID) else { return false }
        mirrorDecorations = added.set
        selectedMirrorStickerID = added.sticker.id
        return true
    }

    func replaceMirrorSticker(_ sticker: NookMirrorSticker) {
        mirrorDecorations = mirrorDecorations.replacing(sticker)
    }

    func removeMirrorSticker(_ id: UUID) {
        mirrorDecorations = mirrorDecorations.removing(id)
        if selectedMirrorStickerID == id { selectedMirrorStickerID = nil }
    }

    /// Steps a sticker to its design's next colorway.
    func cycleMirrorStickerVariant(_ id: UUID) {
        guard let sticker = mirrorDecorations.stickers.first(where: { $0.id == id }),
              let design = NookMirrorDesigns.sticker(sticker.designID) else { return }
        var next = sticker
        // Wrapped first: a damaged saved number near the top of Int would
        // overflow on the add.
        next.variant = design.wrapped(design.wrapped(sticker.variant) + 1)
        replaceMirrorSticker(next)
    }

    func clearMirrorDecorations() {
        mirrorDecorations = .none
        selectedMirrorStickerID = nil
    }

    /// Puts the picker away and lets go of the selected sticker.
    func stopDecoratingMirror() {
        isDecoratingMirror = false
        selectedMirrorStickerID = nil
    }
}
