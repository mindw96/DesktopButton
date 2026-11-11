import Foundation

enum DesktopIconSize: String, CaseIterable, Sendable {
    case small, medium, large

    var title: String {
        switch self {
        case .small: return "작게"
        case .medium: return "보통"
        case .large: return "크게"
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
