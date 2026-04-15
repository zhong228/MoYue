import SwiftUI
import Combine

/// 負責處理閱讀器「資料獲取」與「狀態管理」的 ViewModel (遵循 MVVM)
@MainActor
final class ReaderViewModel: ObservableObject {
    // MARK: - 狀態管理 (State)
    @Published var fetchingChapters: Set<Int> = []
    @Published var failedChapters: Set<Int> = []
    @Published var lastChapterError: String = ""

    // ViewModel 只依賴「章節抓取」能力，不依賴書源快取的具體實作。
    // 快取命中判斷屬於優化策略，由呼叫端（View）決定是否先查快取再呼叫 ViewModel。
    private let chapterFetcher: ChapterFetching

    init(chapterFetcher: ChapterFetching) {
        self.chapterFetcher = chapterFetcher
    }
    
    // MARK: - 資料獲取 (Data Fetching)
    /// 擷取線上章節。
    /// ViewModel 不關心 book 是否「isOnline」——它只關心 book 有沒有可抓取的 onlineChapters。
    /// 多型設計：未來若有 WiFiBook、iCloudBook，只要有 onlineChapters 即可復用此方法。
    func fetchChapterIfNeeded(
        book: ReadingBook?,
        chapterIndex: Int,
        currentChapterIndex: Int,
        store: BookStore,
        onSuccess: @escaping @MainActor () -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) {
        guard let b = book,
              let refs = b.onlineChapters, refs.indices.contains(chapterIndex),
              !fetchingChapters.contains(chapterIndex) else {
            return
        }
        
        fetchingChapters.insert(chapterIndex)
        let priority: ChapterFetchPriority = (chapterIndex == currentChapterIndex) ? .jump : .immediate
        
        Task {
            do {
                let pkg = try await chapterFetcher.fetchChapter(
                    book: b,
                    chapterIndex: chapterIndex,
                    priority: priority,
                    store: store
                )

                guard !Task.isCancelled else {
                    self.fetchingChapters.remove(chapterIndex)
                    return
                }
                self.fetchingChapters.remove(chapterIndex)
                if pkg.state == .cached && !pkg.content.isEmpty {
                    self.failedChapters.remove(chapterIndex)
                    onSuccess()
                } else {
                    self.failedChapters.insert(chapterIndex)
                    let reason = pkg.failureReason ?? "empty"
                    self.lastChapterError = "ch\(chapterIndex): \(reason)"
                    onFailure(self.lastChapterError)
                }
            } catch is CancellationError {
                self.fetchingChapters.remove(chapterIndex)
            } catch {
                guard !Task.isCancelled else {
                    self.fetchingChapters.remove(chapterIndex)
                    return
                }
                self.fetchingChapters.remove(chapterIndex)
                self.failedChapters.insert(chapterIndex)
                self.lastChapterError = "ch\(chapterIndex): \(error.localizedDescription)"
                onFailure(self.lastChapterError)
            }
        }
    }
}

