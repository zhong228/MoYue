# Round 3 Remaining Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成 Round 3 剩餘三項審查問題的修復：#3 JS 安全沙盒、#1 巨型視圖 + #2 Singleton DI 強制執行。

**Architecture:** #3 在 JSRuleEngineRunner.didFinish 中以 evaluateJavaScript 注入安全鎖定腳本。#1/#2 透過定義 OnlineBookCoordinating 協定、擴展 ReaderViewModel、並將 ReaderView 中的業務邏輯 .shared 呼叫遷移至 ViewModel 完成。

**Tech Stack:** Swift, SwiftUI, WKWebView, JavaScriptCore, Combine

---

## 修改的檔案

| 檔案 | 變更類型 | 說明 |
|------|----------|------|
| `yuedu app/Models/RuleEngine/JSRuleEngineRunner.swift` | Modify | 在 didFinish 注入安全鎖定 JS，先於 ruleEngine.js |
| `yuedu app/Models/App/AppDependencies.swift` | Modify | 新增 OnlineBookCoordinating 協定、擴展 AppDependencies |
| `yuedu app/Models/Online/OnlineReadingPipeline.swift` | Modify | 讓 OnlineBookCoordinator 遵循 OnlineBookCoordinating |
| `yuedu app/ViewModels/ReaderViewModel.swift` | Modify | 新增 bookCoordinator、bookSourceFetcher 依賴，新增 download/prefetch/cancelAll/loadOtherOrigins 方法及 @Published 狀態 |
| `yuedu app/Views/Reader/ReaderView.swift` | Modify | 替換所有 .shared 業務呼叫為 ViewModel 方法，移除重複的 @State changeSource 屬性 |

---

### Task 1: JS 安全鎖定（#3）

**Files:**
- Modify: `yuedu app/Models/RuleEngine/JSRuleEngineRunner.swift` (didFinish handler ~line 492)

- [ ] **Step 1: 在 didFinish 的 scriptToInject 前，先注入 API 鎖定腳本**

在 `didFinish` 的現有邏輯中，找到「以 evaluateJavaScript 注入 ruleEngine」的 `webView.evaluateJavaScript(scriptToInject, ...)` 呼叫前，插入：

```swift
// 先注入 API 鎖定腳本，確保書源腳本無法存取網路或儲存 API
let apiLockdownScript = """
(function() {
    'use strict';
    const deny = { get: () => null, set: () => {}, configurable: false };
    // 禁止網路 API：防止書源腳本將用戶資料滲漏至外部
    try { Object.defineProperty(window, 'fetch', deny); } catch(_) {}
    try { Object.defineProperty(window, 'XMLHttpRequest', deny); } catch(_) {}
    try { Object.defineProperty(window, 'WebSocket', deny); } catch(_) {}
    try { Object.defineProperty(window, 'EventSource', deny); } catch(_) {}
    // 禁止持久存儲
    try { Object.defineProperty(window, 'localStorage', deny); } catch(_) {}
    try { Object.defineProperty(window, 'sessionStorage', deny); } catch(_) {}
    try { Object.defineProperty(window, 'indexedDB', deny); } catch(_) {}
    try { Object.defineProperty(window, 'caches', deny); } catch(_) {}
    // 禁止 Beacon 與 Geolocation
    try { Object.defineProperty(navigator, 'sendBeacon', deny); } catch(_) {}
    try { Object.defineProperty(navigator, 'geolocation', deny); } catch(_) {}
    // 清空 Cookie 讀寫
    try {
        Object.defineProperty(document, 'cookie', {
            get: () => '',
            set: () => {},
            configurable: false
        });
    } catch(_) {}
})();
"""
webView.evaluateJavaScript(apiLockdownScript, in: nil, in: world) { [weak self] lockRes in
    if case .failure(let e) = lockRes {
        AppLogger.security("API 鎖定腳本注入失敗", context: ["error": e.localizedDescription])
        // 鎖定失敗不阻止引擎載入，但記錄警告
    }
    // 鎖定完成後再注入 ruleEngine.js
    // ... (原有的 scriptToInject 注入邏輯移至此 closure)
}
```

注意：原有的 `webView.evaluateJavaScript(scriptToInject, ...)` 呼叫要**巢狀到**鎖定腳本的 completion closure 裡，確保序列執行。

- [ ] **Step 2: 確認 didFinish 新結構正確**

驗證最終的 didFinish 呼叫順序：
1. `evaluateJavaScript(apiLockdownScript, ...)` → 完成後
2. `evaluateJavaScript(scriptToInject, ...)` (ruleEngine.js) → 成功後  
3. `evaluateJavaScript("typeof window.BookSourceEngine", ...)` → 完成 continuation

---

### Task 2: OnlineBookCoordinating 協定（#2 前置）

**Files:**
- Modify: `yuedu app/Models/App/AppDependencies.swift`

- [ ] **Step 1: 新增 OnlineBookCoordinating 協定**

在 `AppDependencies.swift` 中，與其他協定（`WebContentFetching`, `BookSourceFetching`）並排，加入：

```swift
/// 線上書籍下載與預加載協定，讓閱讀器與具體 Coordinator 解耦
protocol OnlineBookCoordinating: AnyObject {
    func downloadBook(_ book: ReadingBook, store: BookStore?)
    func prefetchAround(book: ReadingBook, center: Int, store: BookStore?) async
}
```

- [ ] **Step 2: 將 AppDependencies 加入 onlineBookCoordinator**

```swift
struct AppDependencies {
    var webContentFetcher: WebContentFetching
    var bookSourceFetcher: BookSourceFetching
    var chapterFetcher: ChapterFetching
    var onlineBookCoordinator: OnlineBookCoordinating  // 新增

    static let live: AppDependencies = {
        // ...
        return AppDependencies(
            webContentFetcher: ...,
            bookSourceFetcher: ...,
            chapterFetcher: ...,
            onlineBookCoordinator: OnlineBookCoordinator.shared  // 注入 shared 實例
        )
    }()
}
```

---

### Task 3: OnlineBookCoordinator 遵循協定

**Files:**
- Modify: `yuedu app/Models/Online/OnlineReadingPipeline.swift`

- [ ] **Step 1: 讓 OnlineBookCoordinator 遵循 OnlineBookCoordinating**

在 `OnlineBookCoordinator` 類別（或其 extension）中加入 conformance：

```swift
extension OnlineBookCoordinator: OnlineBookCoordinating {}
```

`downloadBook` 與 `prefetchAround` 方法簽名已匹配，不需額外實作。

---

### Task 4: 擴展 ReaderViewModel（#1/#2 核心）

**Files:**
- Modify: `yuedu app/ViewModels/ReaderViewModel.swift`

- [ ] **Step 1: 新增依賴屬性與 Published 狀態**

```swift
@MainActor
final class ReaderViewModel: ObservableObject {
    @Published private(set) var chapterStates: [Int: ChapterLoadState] = [:]
    // 換源相關狀態（從 ReaderView 移入，由 ViewModel 管理）
    @Published private(set) var changeSourceOrigins: [BookOrigin] = []
    @Published private(set) var changeSourceLoading: Bool = false
    @Published private(set) var changeSourceError: String? = nil

    private var chapterFetcher: ChapterFetching
    private var bookCoordinator: OnlineBookCoordinating
    private var bookSourceFetcher: BookSourceFetching
    // ...
}
```

- [ ] **Step 2: 更新 init 加入新依賴**

```swift
convenience init() {
    self.init(
        chapterFetcher: AppDependencies.live.chapterFetcher,
        bookCoordinator: AppDependencies.live.onlineBookCoordinator,
        bookSourceFetcher: AppDependencies.live.bookSourceFetcher
    )
}

init(
    chapterFetcher: ChapterFetching,
    bookCoordinator: OnlineBookCoordinating,
    bookSourceFetcher: BookSourceFetching
) {
    self.chapterFetcher = chapterFetcher
    self.bookCoordinator = bookCoordinator
    self.bookSourceFetcher = bookSourceFetcher
}
```

- [ ] **Step 3: 新增 cancelAll 方法**

```swift
func cancelAll(for bookId: UUID) async {
    await chapterFetcher.cancelAll(for: bookId)
}
```

- [ ] **Step 4: 新增 downloadBook 方法**

```swift
/// 下載或取消下載書籍，取代 ReaderView 直接呼叫 OnlineBookCoordinator.shared
func handleDownloadAction(book: ReadingBook, store: BookStore) {
    switch book.offlineDownloadState {
    case .none, .failed:
        bookCoordinator.downloadBook(book, store: store)
    case .downloading, .available:
        break  // 下載中或已完成，由呼叫方決定後續動作
    }
}
```

- [ ] **Step 5: 新增 prefetchAround 方法**

```swift
func prefetchAround(book: ReadingBook, center: Int, store: BookStore) {
    Task {
        await bookCoordinator.prefetchAround(book: book, center: center, store: store)
    }
}
```

- [ ] **Step 6: 新增 loadOtherOrigins 方法**

```swift
func loadOtherOrigins(
    book: ReadingBook,
    currentSourceId: UUID,
    enabledSources: [BookSource],
    store: BookStore
) {
    changeSourceLoading = true
    changeSourceError = nil
    changeSourceOrigins = []
    let searchTitle = book.title
    let key = SearchBook.makeKey(name: book.title, author: book.author)
    let sources = enabledSources.filter { $0.id != currentSourceId }
    Task { [weak self] in
        guard let self else { return }
        var byKey: [String: [OnlineBook]] = [:]
        for source in sources {
            do {
                let list = try await self.bookSourceFetcher.search(query: searchTitle, in: source)
                for ob in list {
                    let k = SearchBook.makeKey(name: ob.name, author: ob.author)
                    if byKey[k] == nil { byKey[k] = [] }
                    byKey[k]?.append(ob)
                }
            } catch { continue }
        }
        let candidates = byKey[key] ?? []
        let origins: [BookOrigin] = candidates
            .filter { $0.sourceId != currentSourceId }
            .map { ob in
                BookOrigin(
                    sourceId: ob.sourceId,
                    sourceName: ob.sourceName,
                    bookUrl: ob.bookUrl,
                    tocUrl: ob.tocUrl,
                    coverUrl: ob.coverUrl,
                    intro: ob.intro,
                    lastChapter: ob.lastChapter,
                    wordCount: ob.wordCount,
                    kind: ob.kind,
                    runtimeVariables: ob.runtimeVariables
                )
            }
        await MainActor.run {
            self.changeSourceOrigins = origins
            self.changeSourceLoading = false
        }
    }
}
```

---

### Task 5: 更新 ReaderView（#1/#2 收尾）

**Files:**
- Modify: `yuedu app/Views/Reader/ReaderView.swift`

- [ ] **Step 1: 移除重複的 @State changeSource 屬性**

刪除：
```swift
@State private var changeSourceOrigins: [BookOrigin] = []
@State private var changeSourceLoading = false
@State private var changeSourceError: String?
```

改為讀取 ViewModel：
```swift
private var changeSourceOrigins: [BookOrigin] { readerViewModel.changeSourceOrigins }
private var changeSourceLoading: Bool { readerViewModel.changeSourceLoading }
private var changeSourceError: String? { readerViewModel.changeSourceError }
```

- [ ] **Step 2: 替換 onDisappear 中的 ChapterFetchManager.shared.cancelAll**

```swift
// 舊
await ChapterFetchManager.shared.cancelAll(for: b.id)
// 新
await readerViewModel.cancelAll(for: b.id)
```

- [ ] **Step 3: 替換 handleDownloadAction 中的 OnlineBookCoordinator.shared**

```swift
// 舊
private func handleDownloadAction() {
    guard let b = book, b.isOnline else { return }
    switch b.offlineDownloadState {
    case .none, .failed:
        OnlineBookCoordinator.shared.downloadBook(b, store: store)
    ...
    }
}
// 新
private func handleDownloadAction() {
    guard let b = book, b.isOnline else { return }
    if b.offlineDownloadState == .available {
        store.clearOnlineDownload(bookId: b.id)
        return
    }
    readerViewModel.handleDownloadAction(book: b, store: store)
}
```

- [ ] **Step 4: 替換 prefetchAdjacentChapters 中的 OnlineBookCoordinator.shared**

```swift
// 舊
private func prefetchAdjacentChapters(around chapterIndex: Int) {
    guard let b = book, b.isOnline else { return }
    Task { await OnlineBookCoordinator.shared.prefetchAround(book: b, center: chapterIndex, store: store) }
}
// 新
private func prefetchAdjacentChapters(around chapterIndex: Int) {
    guard let b = book, b.isOnline else { return }
    readerViewModel.prefetchAround(book: b, center: chapterIndex, store: store)
}
```

- [ ] **Step 5: 替換 maybeEarlyPrefetchIfNearChapterEnd 中的 OnlineBookCoordinator.shared**

```swift
// 找到最後的 Task { await OnlineBookCoordinator.shared.prefetchAround... }
// 替換為
readerViewModel.prefetchAround(book: b, center: chIdx, store: store)
```

- [ ] **Step 6: 替換 loadOtherOrigins 方法**

刪除現有的 `loadOtherOrigins()` 方法內容（含 Task），改為呼叫 ViewModel：

```swift
private func loadOtherOrigins() {
    guard let b = book, let currentSourceId = b.bookSourceId else { return }
    readerViewModel.loadOtherOrigins(
        book: b,
        currentSourceId: currentSourceId,
        enabledSources: BookSourceStore.shared.enabledSources,
        store: store
    )
}
```

（注意：`BookSourceStore.shared.enabledSources` 在此只是讀取靜態資料並傳入，ViewModel 本身不持有 BookSourceStore 參考，DI 邊界清晰。）

---
