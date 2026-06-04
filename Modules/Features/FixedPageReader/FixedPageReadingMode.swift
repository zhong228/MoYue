import Foundation

// MARK: - Fixed page reading mode (ported concept from Aidoku's ReadingMode)

enum FixedPageReadingMode: Int, CaseIterable, Codable {
    case rtl = 1       // paged, right-to-left (default for CJK/Japanese manga)
    case ltr = 2       // paged, left-to-right
    case vertical = 3  // paged, vertical swipe
    case webtoon = 4   // continuous vertical scroll (manhua/manhwa)

    var localizedName: String {
        switch self {
        case .rtl:      return localized("從右到左")
        case .ltr:      return localized("從左到右")
        case .vertical: return localized("直向翻頁")
        case .webtoon:  return localized("條漫")
        }
    }

    var iconName: String {
        switch self {
        case .rtl:      return "arrow.left"
        case .ltr:      return "arrow.right"
        case .vertical: return "arrow.up.arrow.down"
        case .webtoon:  return "arrow.down"
        }
    }

    // MARK: Per-book persistence

    static func saved(for bookId: UUID, defaults: UserDefaults = .standard) -> FixedPageReadingMode {
        let raw = defaults.object(forKey: key(bookId)) as? Int
            ?? defaults.object(forKey: legacyKey(bookId)) as? Int
        return raw.flatMap { FixedPageReadingMode(rawValue: $0) } ?? .rtl
    }

    static func save(_ mode: FixedPageReadingMode, for bookId: UUID, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: key(bookId))
    }

    private static func key(_ bookId: UUID) -> String { "fixedPage.readingMode.\(bookId.uuidString)" }
    private static func legacyKey(_ bookId: UUID) -> String { "manga.readingMode.\(bookId.uuidString)" }
}
