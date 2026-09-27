import Foundation

/// 一頁一個書籤：一頁在它所屬章節裡佔用的字元範圍。
///
/// 書籤存的是**頁首**位置，但頁的邊界會隨字級、邊距、雙頁、整章翻譯重新排版而移動。
/// 所以「這頁有沒有書籤」要用範圍包含來問，不能用位置相等——換過字級之後，
/// 原本存在頁首的書籤會落到頁中間，相等判斷會說「沒有書籤」，於是同一頁被加上
/// 第二個書籤，而且舊的那個再也刪不掉。
struct ReaderPageBookmarkRange: Equatable {
    let spineIndex: Int
    /// 頁首字元位移（章節內）。
    let startOffset: Int
    /// 下一頁的頁首位移。`nil` 代表一路到章節結尾——章節最後一頁，
    /// 以及章節還沒排版完、引擎答不出下一頁在哪的時候。
    let endOffset: Int?

    init(spineIndex: Int, startOffset: Int, endOffset: Int? = nil) {
        self.spineIndex = spineIndex
        self.startOffset = max(0, startOffset)
        self.endOffset = endOffset
    }

    func contains(_ position: CoreTextReadingPosition) -> Bool {
        guard position.spineIndex == spineIndex, position.charOffset >= startOffset else { return false }
        guard let endOffset else { return true }
        return position.charOffset < endOffset
    }

    /// 落在這一頁上的書籤（只算書籤，底線／螢光筆標註不算）。
    func pageBookmarks(in bookmarks: [Bookmark]) -> [Bookmark] {
        bookmarks.filter { $0.kind == .bookmark && contains($0.position) }
    }

    /// 這一頁的書籤位置：就是頁首。
    var bookmarkPosition: CoreTextReadingPosition {
        CoreTextReadingPosition(spineIndex: spineIndex, charOffset: startOffset)
    }
}
