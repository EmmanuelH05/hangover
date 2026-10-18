import SwiftUI

/// How each task app is drawn: its dot on the card's section headers and
/// rows, its mark in Settings, and the symbol the tour's cards use. The
/// colors are the design kit's (`design/todo-sources/feature.css`, T3, T14).
extension NookTodoSourceKind {
    var dotColor: Color {
        switch self {
        case .reminders: Color(red: 0xff / 255, green: 0x5b / 255, blue: 0x4d / 255)
        case .notion: Color.white
        case .tickTick: Color(red: 0x47 / 255, green: 0x72 / 255, blue: 0xfa / 255)
        case .asana: Color(red: 0xf0 / 255, green: 0x6a / 255, blue: 0x6a / 255)
        case .monday: Color(red: 0x61 / 255, green: 0x61 / 255, blue: 0xff / 255)
        case .canvas: Color(red: 0xe4 / 255, green: 0x45 / 255, blue: 0x2f / 255)
        }
    }

    var symbol: String {
        switch self {
        case .reminders: "list.bullet"
        case .notion: "tablecells"
        case .tickTick: "checkmark.circle"
        case .asana: "circle.hexagongrid"
        case .monday: "square.grid.2x2"
        case .canvas: "graduationcap"
        }
    }
}
