# iOS EPUB 架構設計規格 (Architecture Design Specification)

## 概述 (Overview)
為了提供能媲美 iBooks 的頂級原生 iOS 閱讀體驗，我們將全面重構 EPUB 引擎（目前的 `LiveWebReader`），不再依賴純網頁的滑動手勢渲染。取而代之的是採用 **原生為主軸的翻頁容器 (Native-dominant page container)**，並搭配 **混合式漸進快照引擎 (Hybrid Snapshot Generation Engine)**。此架構能將 WebKit 渲染時的僵硬感與延遲，與 iOS 絲滑的原生物理動畫徹底隔離。

## 核心組件 (Core Components)

### 1. 原生翻頁容器 (Native Page Container - The Shell)
我們將使用 iOS 原生的容器（如 `UIPageViewController` 或經過封裝的自製 `UIScrollView`）來處理讀者的手勢操作、滑動物理慣性以及視覺轉換。
- 該容器會管理一系列的 `UIViewController` 或 `UIView`（每個視圖嚴格對應透過 EPUB 佈局算出的單一頁面）。
- **注意手勢衝突**：實作時需特別測試 `UIPageViewController` 內建的預載行為 (prefetching) 與我們的快照替換策略之間的衝突及 View Lifecycle (`viewDidAppear` 時機)。

### 2. 視圖呈現與佔位體驗 (View Delivery & Placeholder UX)
由於記憶體限制，應用程式不可能同時持有幾十個 `WKWebView`，每個原生頁面絕大部分時間顯示的都是一張擷取好的 `UIImage`（Snapshot 快照）。
- **佔位體驗 (Placeholder UX)**：當使用者快速翻頁，遇到快照尚未產生的頁面時，**絕對不用純白畫面或轉圈動畫 (spinner)**，而是顯示模糊的低解析度快照（若是跨章節可使用章節骨架 screen skeleton 或 thumbnail upscaling + blur），大幅改善感知延遲而不破壞閱讀沉浸感。
- **隨選掛載**：只有當使用者徹底停留在某一頁時，系統才會把真正的 `WKWebView` 實體掛載到當前畫面最上方，精準調整 `contentOffset.x` 覆蓋底圖，開放互動。

### 3. 混合式快照處理管線 (Hybrid Snapshot Pipeline - The Engine)
實作嚴謹的非同步快照排程機制：
- **優先權佇列 (Priority Queue)**：
  1. **Immediate (即時)**：目前頁面與其相鄰頁面 (Current ± N)。
  2. **On-Demand (隨選)**：拖曳進度條或目標跳轉的急迫需求。
  3. **Background (背景漸進)**：默默向後遍歷章節的剩餘頁數。
- **快照就緒握手 (Snapshot Readiness Handshake)**：
  絕對不依賴固定延遲 (fixed delay) 來截圖。必須在 Web 端實作明確的 Ready Signal（例如 JS 在字型、圖片、外部資源與分頁運算完全結束後，呼叫 `window.webkit.messageHandlers.renderReady.postMessage({pageIndex:...})`），收到訊號後再進行 iOS 端的 `takeSnapshot`，避免字體閃現或抓到未排版完成的破圖。
- **中斷與效能控制**：
  允許隨時中斷背景任務 (Cancelable API)。當偵測到極高頻翻頁 (> X flips/sec) 時，提升背景 worker 優先級或短暫增加併發；若系統處於記憶體壓力，則立刻暫停快照任務並啟動清理。
- **動態失效 (Invalidation)**：
  當裝置旋轉 (Device Rotation) 或改變字體大小 (Font-size change) 時，標記受影響的快照為 invalidated，並將它們重新送入佇列排程，避免舊圖殘留。

### 4. WebView 共用池與快取策略 (Worker Pool & Caching)
- **Worker Pool (2-3 個執行緒)**：
  起步設置 2 個 `WKWebView`（1 個 Active 用於目前閱讀，1 個 Background 用於背景截圖）。必要時可擴展至 3 個。背景 Worker 預設採用「受限的序列化執行 (Serial by default)」，避免過度爭搶 I/O 與渲染資源造成卡頓。
- **快取策略 (Cache Policy)**：
  - 記憶體 (Memory LRU)：預設上限約 6 頁。過度 eager 可能導致低階裝置崩潰。
  - 磁碟 (Disk LRU)：總量限制（如 50-100 MB），以 LRU 機制淘汰。
  - 格式：優先儲存符合螢幕解析度的 HEIF（支援的話）或 PNG，避免額外儲存超高解析度。

### 5. CFI 與 DOM 映射 (CFI and DOM mapping)
如果在 Web 端渲染前修改了 DOM（插入 wrapper、placeholder 等），必須保存「原始 EPUB node」到「修改後 node」的映射關係，確保 CFI 對齊、書籤與畫劃註記功能在翻頁時依然能精準對位，不受 DOM 結構變動干擾。

## 短期 MVP 實作清單 (Next Steps - Short Term MVP)
1. **實作 Worker-side JS 最小合約 (Minimal Contract)**：
   開發 `gotoPage(index)`、`getPaginationMetrics()` 與 `onRenderReady(pageIndex)` 通訊介面。確保在 images/fonts 聚合完成才發 ready。
2. **SnapshotManager MVP (Swift 層)**：
   實作 `requestSnapshot(chapter, page, priority)`、`prefetchRange(center, radius)` 與 `cancelRequests(forChapter)`。先完成 2-worker 的背景序列截圖機制。
3. **UI 層整合測試**：
   引入 `UIPageViewController`，驗證首次呈現延遲 (<150ms)、快速翻頁空白率，以及跳轉頁面的迅速反應。
4. **指標與體驗打磨 (Metrics & UX Polish)**：
   收集 snapshotLatency、missRate 與 memoryPressure 等事件，據此動態調整預載頁數 (N) 參數。實作模糊佔位圖與骨架屏的比對測試。

## 暫時擱置項目 (Ignoring for Now)
- TXT 與 HTML 的轉碼管線。待 EPUB 基礎穩固後再來適配新架構。
