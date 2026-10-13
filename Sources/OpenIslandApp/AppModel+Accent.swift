import SwiftUI

/// The accent color as the windows read it (D62). The choice itself and
/// the system's color live in `HangoverAccentModel`.
extension AppModel {
    /// What the island, Settings and the tour put in their environment.
    var accentTint: HangoverAccentTint { accent.tint }

    /// The Settings window's tint: a fixed color, and nil for Default and
    /// for System. `HangoverAccent.settingsRootTint` says why.
    var settingsRootTint: Color? {
        HangoverAccent.settingsRootTint(choice: accent.choice)?.color
    }

    /// The label of a prominent button in Settings. White on Apple's green
    /// or orange is about 2 to 1, which is why a fixed color brings the
    /// tone that reads on it. Nil leaves the label as macOS draws it.
    var settingsProminentLabel: Color? {
        HangoverAccent.settingsRootTint(choice: accent.choice).map { HangoverAccent.textTone(on: $0).rgb.color }
    }
}
