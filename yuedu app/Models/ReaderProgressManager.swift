import Foundation

struct BookProgressSnapshot: Codable, Equatable {
    enum Mode: String, Codable {
        case coreText
        case paged
        case scroll
    }

    let bookId: UUID
    let mode: Mode
    let chapterIndex: Int
    let pageIndex: Int?
    let charOffset: Int?
    let percentage: Double
    let timestamp: Date
}

@MainActor
final class ReaderProgressManager {
    static let shared = ReaderProgressManager()

    private let defaults = UserDefaults.standard
    private let snapshotPrefix = "yd_reader_progress_snapshot_"
    private let legacyPagedPrefix = "readerPos_"

    private init() {}

    func saveCoreText(bookId: UUID, chapterIndex: Int, charOffset: Int, percentage: Double) {
        let snapshot = BookProgressSnapshot(
            bookId: bookId,
            mode: .coreText,
            chapterIndex: chapterIndex,
            pageIndex: nil,
            charOffset: charOffset,
            percentage: normalized(percentage),
            timestamp: Date()
        )
        saveSnapshot(snapshot)
    }

    func savePaged(bookId: UUID, chapterIndex: Int, pageInChapter: Int, percentage: Double) {
        let snapshot = BookProgressSnapshot(
            bookId: bookId,
            mode: .paged,
            chapterIndex: chapterIndex,
            pageIndex: pageInChapter,
            charOffset: nil,
            percentage: normalized(percentage),
            timestamp: Date()
        )
        saveSnapshot(snapshot)
        saveLegacyPagedPosition(
            bookId: bookId,
            chapterIndex: chapterIndex,
            pageInChapter: pageInChapter,
            percentage: percentage
        )
    }

    func saveScroll(bookId: UUID, chapterIndex: Int, percentage: Double) {
        let snapshot = BookProgressSnapshot(
            bookId: bookId,
            mode: .scroll,
            chapterIndex: chapterIndex,
            pageIndex: nil,
            charOffset: nil,
            percentage: normalized(percentage),
            timestamp: Date()
        )
        saveSnapshot(snapshot)
    }

    func loadSnapshot(bookId: UUID) -> BookProgressSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey(bookId: bookId)) else { return nil }
        return try? JSONDecoder().decode(BookProgressSnapshot.self, from: data)
    }

    private func saveSnapshot(_ snapshot: BookProgressSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey(bookId: snapshot.bookId))
    }

    private func saveLegacyPagedPosition(
        bookId: UUID,
        chapterIndex: Int,
        pageInChapter: Int,
        percentage: Double
    ) {
        let legacy = LegacyPagedPosition(
            chapterIndex: chapterIndex,
            charOffsetInChapter: pageInChapter,
            percentage: normalized(percentage)
        )
        guard let data = try? JSONEncoder().encode(legacy) else { return }
        defaults.set(data, forKey: legacyKey(bookId: bookId))
    }

    private func snapshotKey(bookId: UUID) -> String {
        snapshotPrefix + bookId.uuidString
    }

    private func legacyKey(bookId: UUID) -> String {
        legacyPagedPrefix + bookId.uuidString
    }

    private func normalized(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}

private struct LegacyPagedPosition: Codable {
    let chapterIndex: Int
    let charOffsetInChapter: Int
    let percentage: Double
}
