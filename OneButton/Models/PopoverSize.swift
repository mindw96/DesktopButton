import Combine
import Foundation

@MainActor
final class PopoverSize: ObservableObject {
    static let defaultSize = CGSize(width: 340, height: 440)
    static let minimumSize = CGSize(width: 300, height: 260)
    static let maximumSize = CGSize(width: 960, height: 900)

    @Published private(set) var size: CGSize
    @Published private(set) var resizesFromLeadingEdge = true
    private var preferredSize: CGSize
    private var availableSize: CGSize
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        availableSize = Self.maximumSize
        let width = defaults.object(forKey: "popoverWidth") as? Double ?? Self.defaultSize.width
        let height = defaults.object(forKey: "popoverHeight") as? Double ?? Self.defaultSize.height
        let restored = Self.clamped(CGSize(width: width, height: height), available: Self.maximumSize)
        preferredSize = restored
        size = restored
    }

    func fit(in available: CGSize, fromLeadingEdge: Bool) {
        availableSize = available
        resizesFromLeadingEdge = fromLeadingEdge
        let fitted = Self.clamped(preferredSize, available: available)
        if size != fitted { size = fitted }
    }

    func resize(to proposed: CGSize) {
        let next = Self.clamped(proposed, available: availableSize)
        guard next != size else { return }
        // Resizing one axis on a small screen preserves the preference for the other.
        if next.width != size.width { preferredSize.width = next.width }
        if next.height != size.height { preferredSize.height = next.height }
        size = next
    }

    func save() {
        defaults.set(preferredSize.width, forKey: "popoverWidth")
        defaults.set(preferredSize.height, forKey: "popoverHeight")
    }

    static func draggedSize(from size: CGSize, start: CGPoint, current: CGPoint, fromLeadingEdge: Bool) -> CGSize {
        CGSize(width: size.width + (current.x - start.x) * (fromLeadingEdge ? -1 : 1),
               height: size.height - (current.y - start.y))
    }

    static func clamped(_ proposed: CGSize, available: CGSize) -> CGSize {
        func dimension(_ value: CGFloat, available: CGFloat, minimum: CGFloat,
                       maximum: CGFloat, fallback: CGFloat) -> CGFloat {
            let upper = max(1, min(available.isFinite ? available : maximum, maximum))
            return min(max(value.isFinite ? value : fallback, min(minimum, upper)), upper)
        }
        return CGSize(
            width: dimension(proposed.width, available: available.width, minimum: minimumSize.width,
                             maximum: maximumSize.width, fallback: defaultSize.width),
            height: dimension(proposed.height, available: available.height, minimum: minimumSize.height,
                              maximum: maximumSize.height, fallback: defaultSize.height)
        )
    }
}
