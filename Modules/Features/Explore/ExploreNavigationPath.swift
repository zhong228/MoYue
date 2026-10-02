import Foundation
import SwiftUI

enum ExploreNavigationRoute: Hashable {
    /// One explore source's discover page.
    case source(sourceURL: String)
    /// 我的發現: pinned categories from any sources.
    case myDiscover
    /// 我的發現's pinned categories, reordered and removed.
    case myDiscoverEditor
    case book(OnlineBook)
    /// A category of any source — from the source list or 我的發現.
    case sourceCategory(ExploreCategoryReference)
    /// Legado's 搜索 on a source: the search page scoped to that source alone.
    case searchInSource(sourceURL: String)
    /// 書源管理, pushed before iOS 18 (`BookSourceManagementPresentationPolicy`).
    case sourceManager

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.source(let lhsURL), .source(let rhsURL)):
            return lhsURL == rhsURL
        case (.myDiscover, .myDiscover), (.myDiscoverEditor, .myDiscoverEditor):
            return true
        case (.book(let lhsBook), .book(let rhsBook)):
            return lhsBook.id == rhsBook.id
        case (.sourceCategory(let lhsReference), .sourceCategory(let rhsReference)):
            return lhsReference == rhsReference
        case (.searchInSource(let lhsURL), .searchInSource(let rhsURL)):
            return lhsURL == rhsURL
        case (.sourceManager, .sourceManager):
            return true
        default:
            return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .source(let sourceURL):
            hasher.combine(0)
            hasher.combine(sourceURL)
        case .book(let book):
            hasher.combine(1)
            hasher.combine(book.id)
        case .sourceCategory(let reference):
            hasher.combine(3)
            hasher.combine(reference)
        case .searchInSource(let sourceURL):
            hasher.combine(4)
            hasher.combine(sourceURL)
        case .myDiscover:
            hasher.combine(5)
        case .myDiscoverEditor:
            hasher.combine(6)
        case .sourceManager:
            hasher.combine(7)
        }
    }
}

struct ExploreNavigationPath {
    // SearchView itself occupies this path before its result links append
    // SearchResultRoute values. Keep the stack heterogeneous and do not present
    // SearchView through a separate item-driven navigation state.
    var path = NavigationPath()

    mutating func push(_ route: ExploreNavigationRoute) {
        path.append(route)
    }

    mutating func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }
}
