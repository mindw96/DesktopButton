import Foundation

enum DesktopIconSize: String, CaseIterable, Sendable {
    case small, medium, large

    var title: String {
        switch self {
        case .small: return String(localized: "Small")
        case .medium: return String(localized: "Medium")
        case .large: return String(localized: "Large")
        }
    }

    var gridSize: CGFloat {
        switch self {
        case .small: return 32
        case .medium: return 48
        case .large: return 72
        }
    }

    var listSize: CGFloat {
        switch self {
        case .small: return 16
        case .medium: return 24
        case .large: return 32
        }
    }
}
