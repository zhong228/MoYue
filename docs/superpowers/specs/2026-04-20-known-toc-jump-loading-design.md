# 已知 TOC 任意跳章正文載入設計

## 問題

目前閱讀器對線上小說已具備單章 Lazy Loading 與鄰章預抓能力，但「任意跳章」的體驗仍不夠穩定：

1. `ReaderView` 主要依賴 `fetchingChapters`、`failedChapters`、`lastChapterError` 與 `content.isEmpty` 的組合來推測章節狀態。
2. 跳到已知 TOC 中但尚未抓正文的章節時，流程上雖然會觸發抓取，但 UI 缺少明確、可恢復的章節級 loading / failed 狀態。
3. 抓取成功、失敗、重試與頁面刷新邊界目前分散在 `ReaderView` 內，狀態來源不夠單一。

本設計僅處理**「已知 TOC 中任意章節保證進入正文載入流程」**，不處理閱讀中動態擴充 TOC，也不處理超出已知 TOC 的遠端任意跳章。

## 目標

1. 只要目標章節的 URL 已存在於 `book.onlineChapters` 中，從 TOC 點擊跳轉後一定進入可觀察、可恢復的正文載入流程。
2. 跳章時不再依賴 `content.isEmpty` 猜測是否該顯示 loading。
3. 章節抓取狀態只有一個來源，且狀態互斥。
4. 失敗時提供章節級錯誤顯示與重試入口。
5. 背景預抓不可以覆蓋使用者主動跳章的前台等待狀態。

## 非目標

1. 不支援跳到目前還沒有 URL 的遠端章節。
2. 不新增閱讀中自動補 TOC 或動態 append `chapters` 的機制。
3. 不在本期修改 `OnlineBookCoordinator` 的目錄抓取策略。
4. 不新增 `PageRenderingProvider.notifyChaptersAppended` 之類的動態 spine 擴充能力。

## 方案比較

### 方案 A：只修補 `ReaderView` 內既有 Set 狀態

- 做法：延續 `fetchingChapters` / `failedChapters` / `lastChapterError`，再補 overlay 與跳章重試。
- 優點：改動最少。
- 缺點：狀態仍需由多個來源交叉推導，容易出現「其實 ready 但 UI 仍認為 idle / failed」的分裂。

### 方案 B：引入章節狀態機並將抓取狀態收斂到 `ReaderViewModel`（採用）

- 做法：以 `chapterStates: [Int: ChapterLoadState]` 管理抓取流程狀態，`ReaderView` 僅負責導航與顯示。
- 優點：單一事實來源、可測試、容易加入章節級 loading / failed / retry。
- 缺點：需要把 `ReaderView` 目前散落的抓取狀態遷移出去。

### 方案 C：直接為動態 TOC 做完整架構升級

- 做法：同時改 TOC 擴充、跳章 loading、CoreText spine 動態擴容。
- 優點：終局能力最完整。
- 缺點：超出本期需求，風險與耦合面過大。

## 採用設計

採用**方案 B**。先把「已知 TOC 任意跳章」做穩，讓 Reader 層對章節抓取狀態有明確模型，後續若要做 TOC 動態擴充，可直接重用同一套狀態機與 overlay。

## 架構與職責切分

### `ReaderView`

保留：

1. `currentChapterIndex`、`currentPage`
2. 跳章入口 (`jumpToChapter`)
3. 頁面 overlay（loading / failed）
4. CoreText / non-CoreText 刷新觸發

移除：

1. `fetchingChapters`
2. `failedChapters`
3. `lastChapterError`

責任：

1. 收斂所有跳章入口到 `jumpToChapter`
2. 根據「當前章內容可用性 + `chapterStates[currentChapterIndex]`」決定畫面
3. 在章節狀態從 loading 轉為 ready 時通知引擎刷新

### `ReaderViewModel`

新增／收斂責任：

1. 持有 `chapterStates: [Int: ChapterLoadState]`
2. 提供 `ensureChapterReady(chapterIndex:priority:)`
3. 負責抓取去重、優先級提升、失敗封裝
4. 僅管理抓取流程狀態，不保存正文內容本體

### `BookStore / fetcher / cache`

責任不變，仍是正文真實來源。必要時補一個輕量 helper 用來判定「某章是否已有可讀快取」，避免 UI 只靠 `chapterStates` 推斷正文是否存在。

### `CoreText / provider`

本期不做章節數擴充，只使用既有：

1. `notifyChapterDataChanged(at:)`
2. `rebuildPages()`

## 資料模型

```swift
enum ChapterLoadState: Equatable {
    case idle
    case loading
    case ready
    case failed(reason: String)
}
```

### 狀態語義

1. `idle`：尚未為該章建立前台抓取流程狀態。
2. `loading`：該章目前正被抓取。
3. `ready`：正文已成功抓取且可供畫面刷新。
4. `failed(reason:)`：本次抓取失敗，允許使用者重試。

### 重要約束

`chapterStates` 只代表**抓取流程狀態**，不直接等價於「正文是否可讀」。正文是否已存在，仍以 cache/provider 為準。否則那些已在快取內、但尚未寫入 `chapterStates` 的章節會被誤判為需要 loading。

## 顯示判斷規則

對當前章節 `currentChapterIndex`，顯示層使用兩個來源：

1. **內容可用性**：目前章正文是否已能從 cache/provider 取到。
2. **抓取狀態**：`chapterStates[currentChapterIndex]`

規則如下：

1. 若正文**可用**，即使狀態仍是 `idle`，也直接顯示正文，不覆蓋 loading。
2. 若正文**不可用**且狀態是 `idle` 或 `loading`，顯示 loading overlay。
3. 若正文**不可用**且狀態是 `failed(reason)`，顯示錯誤 overlay 與重試按鈕。
4. `ready` 僅代表「可以刷新」，真正的正文顯示仍在刷新完成後交由閱讀器引擎處理。

## 跳章流程

### 已快取章節

1. `jumpToChapter(idx)` 更新 `currentChapterIndex` 與頁面定位。
2. 因正文已可用，不顯示 loading overlay。
3. 視需要觸發最小刷新。

### 未快取章節

1. `jumpToChapter(idx)` 先更新 `currentChapterIndex` / `currentPage`。
2. 立刻呼叫 `viewModel.ensureChapterReady(idx, priority: .jump)`。
3. 畫面顯示該章專屬 loading overlay。
4. 抓取成功後：
   - 若使用者仍停留在該章，立即刷新正文。
   - 若使用者已離開該章，只更新狀態，不強制把畫面拉回來。
5. 抓取失敗後顯示章節級錯誤頁與重試入口。

## 優先級與去重規則

1. 同章若已在 `loading`，不得再發第二條抓取任務。
2. 若既有任務為背景 `.immediate`，新的前台 `.jump` 需要能提權，或至少被模型視為「前台正在等待」。
3. 背景預抓完成時，不得覆蓋目前章節的前台 loading / failed 顯示邏輯。
4. 背景預抓僅為性能優化，不得決定使用者當前章的顯示狀態。

## 刷新邊界

當 `chapterStates[idx]` 從 `loading` 轉為 `ready`：

1. 若當前使用 CoreText 引擎，呼叫 `engine.notifyChapterDataChanged(at: idx)`。
2. 若為非 CoreText / 重建型頁面來源，呼叫 `rebuildPages()`。
3. 只在需要時刷新，不重建整本書。

## 錯誤處理

### 顯示

章節抓取失敗時，顯示：

1. 章節載入失敗標題
2. 失敗原因文字
3. 重試按鈕

### 重試

重試按鈕統一走：

`ensureChapterReady(chapterIndex: currentChapterIndex, priority: .jump)`

不額外開分支邏輯。

## 測試策略

### 單元測試

`ReaderViewModel`

1. `idle -> loading -> ready`
2. `idle -> loading -> failed`
3. 同章去重
4. 失敗後重試
5. `.immediate` 被 `.jump` 提權

### 協調／UI 邊界測試

1. 當前章狀態轉為 ready 時，是否正確觸發 `notifyChapterDataChanged` / `rebuildPages`
2. 跳離目標章後，晚到的成功結果不會把畫面拉回去
3. 畫面 overlay 只受當前章與內容可用性影響

### 既有回歸

保留目前已存在的 paging 回歸測試：

1. `ReaderPageTransitionQueueTests`
2. `ProgrammaticPageTransitionPerformerTests`

避免跳章狀態調整再次破壞點擊翻頁與快速連點行為。

## 驗收標準

1. 對已知 TOC 任選一章，若未快取，畫面顯示 loading，而不是白頁。
2. 正文抓回後，當前章可立即顯示，不需退出重進。
3. 抓取失敗時，使用者能看見錯誤與重試入口。
4. 跳到別章後，前一章的晚到結果不會覆蓋目前畫面。
5. 不再以 `content.isEmpty` 作為唯一 loading 判斷依據。
6. 章節抓取狀態只有一個事實來源。

## 後續延伸

第二期若要做「閱讀中動態擴充 TOC」，可在本設計基礎上擴充：

1. 新增 TOC 更新通知
2. append `chapters`
3. CoreText spine 動態擴容

但這些都不屬於本期範圍。
