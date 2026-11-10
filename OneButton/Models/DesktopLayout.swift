import SwiftUI

enum DesktopLayout: String {
    case list
    case grid

    static let gridColumnCount = 3

    static func columnCount(for width: CGFloat) -> Int {
        max(1, Int((width - 16) / 104))
    }

    func selectionIndex(from current: Int?, direction: MoveCommandDirection, itemCount: Int,
                        columnCount: Int = gridColumnCount) -> Int? {
        guard itemCount > 0 else { return nil }
        guard let current, (0..<itemCount).contains(current) else { return 0 }

        switch direction {
        case .up:
            let step = self == .grid ? max(1, columnCount) : 1
            return current >= step ? current - step : current
        case .down:
            let step = self == .grid ? max(1, columnCount) : 1
            guard current / step < (itemCount - 1) / step else { return current }
            return min(current + step, itemCount - 1)
        case .left:
            return self == .grid ? max(current - 1, 0) : current
        case .right:
            return self == .grid ? min(current + 1, itemCount - 1) : current
        @unknown default:
            return current
        }
    }
}
