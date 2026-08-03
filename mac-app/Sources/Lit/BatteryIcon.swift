import SwiftUI

/// Shared battery glyph + color logic used by the menu bar label, the main
/// battery row, and the peripheral device list — keeps them visually consistent.
enum BatteryIcon {
    static func symbolName(forPercentage percentage: Int) -> String {
        switch percentage {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    static func color(forPercentage percentage: Int, isPluggedIn: Bool) -> Color {
        if isPluggedIn { return .green }
        if percentage <= 10 { return .red }
        if percentage <= 20 { return .orange }
        return .primary
    }
}
