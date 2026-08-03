import Foundation

enum MenuBarIconStyle: String, CaseIterable, Identifiable {
    case percentageOnly
    case iconAndPercentage
    case iconOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .percentageOnly: return "Percentage Only"
        case .iconAndPercentage: return "Icon + Percentage"
        case .iconOnly: return "Icon Only"
        }
    }
}

@MainActor
final class AppearanceSettings: ObservableObject {
    @Published var iconStyle: MenuBarIconStyle {
        didSet { UserDefaults.standard.set(iconStyle.rawValue, forKey: "lit.iconStyle") }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: "lit.iconStyle"),
           let style = MenuBarIconStyle(rawValue: raw) {
            iconStyle = style
        } else {
            iconStyle = .iconAndPercentage
        }
    }
}
