import SwiftUI

/// The accent for a window that stands apart from the island, Settings and
/// the welcome tour, and has no root that hands the accent down: the design
/// kit's palette editor and its reference panels. The app sets it once at
/// start. A view reads it in `body`, which makes the view follow a change.
@MainActor
enum HangoverAccentSource {
    static var tint: @MainActor () -> HangoverAccentTint = { .standard }
}
