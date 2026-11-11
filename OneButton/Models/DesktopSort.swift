import Foundation

enum DesktopSort: String, CaseIterable, Sendable {
    case name, kind, size, lastUsed, added, modified, created, tags, application

    var title: String {
        switch self {
        case .name: return "이름"
        case .kind: return "종류"
        case .size: return "크기"
        case .lastUsed: return "최근 사용일"
        case .added: return "추가된 날짜"
        case .modified: return "수정일"
        case .created: return "생성일"
        case .tags: return "태그"
        case .application: return "응용 프로그램"
        }
    }

    var isDate: Bool {
        switch self {
        case .lastUsed, .added, .modified, .created: return true
        default: return false
        }
    }

    func sorted(_ items: [DesktopItem], direction: DesktopSortDirection) -> [DesktopItem] {
        items.sorted { lhs, rhs in
            let result = compare(lhs, rhs, direction: direction)
            if result != .orderedSame { return result == .orderedAscending }
            let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
            return nameOrder == .orderedSame ? lhs.url.path < rhs.url.path : nameOrder == .orderedAscending
        }
    }

    private func compare(_ lhs: DesktopItem, _ rhs: DesktopItem,
                         direction: DesktopSortDirection) -> ComparisonResult {
        switch self {
        case .name:
            return compare(lhs.name, rhs.name, direction: direction) { $0.localizedStandardCompare($1) }
        case .kind:
            return compare(nonempty(lhs.kind), nonempty(rhs.kind), direction: direction) { $0.localizedStandardCompare($1) }
        case .size:
            return compare(lhs.size, rhs.size, direction: direction) { $0 == $1 ? .orderedSame : ($0 < $1 ? .orderedAscending : .orderedDescending) }
        case .lastUsed:
            return compare(lhs.lastUsedDate, rhs.lastUsedDate, direction: direction) { $0.compare($1) }
        case .added:
            return compare(lhs.addedDate, rhs.addedDate, direction: direction) { $0.compare($1) }
        case .modified:
            return compare(lhs.modifiedDate, rhs.modifiedDate, direction: direction) { $0.compare($1) }
        case .created:
            return compare(lhs.createdDate, rhs.createdDate, direction: direction) { $0.compare($1) }
        case .tags:
            return compare(sortedTags(lhs.tags), sortedTags(rhs.tags), direction: direction) { left, right in
                for (a, b) in zip(left, right) {
                    let result = a.localizedStandardCompare(b)
                    if result != .orderedSame { return result }
                }
                return left.count == right.count ? .orderedSame : (left.count < right.count ? .orderedAscending : .orderedDescending)
            }
        case .application:
            return compare(nonempty(lhs.applicationName), nonempty(rhs.applicationName), direction: direction) { $0.localizedStandardCompare($1) }
        }
    }

    private func compare<T>(_ lhs: T?, _ rhs: T?, direction: DesktopSortDirection,
                            using comparator: (T, T) -> ComparisonResult) -> ComparisonResult {
        switch (lhs, rhs) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        case let (left?, right?):
            let result = comparator(left, right)
            if direction == .descending && result != .orderedSame {
                return result == .orderedAscending ? .orderedDescending : .orderedAscending
            }
            return result
        }
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func sortedTags(_ tags: [String]) -> [String]? {
        let names = tags.filter { !$0.isEmpty }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return names.isEmpty ? nil : names
    }
}

enum DesktopSortDirection: String, CaseIterable, Sendable {
    case ascending, descending

    var title: String { self == .ascending ? "오름차순" : "내림차순" }
}
