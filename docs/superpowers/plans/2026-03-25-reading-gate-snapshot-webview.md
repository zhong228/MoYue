# Reading Gate + EPUBSnapshotWebView 實施計劃

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用獨立的隱藏 WKWebView 生成截圖，並在 min(8, 章節頁數) 頁就緒前以 spinner 阻擋閱讀，消除空白頁、重複頁、封面白屏問題。

**Architecture:** `EPUBSnapshotWebView`（放在隱藏 UIWindow 中）串行截圖，完全不碰閱讀 WebView。`EPUBPageRenderer` 持有它，並在開書/跳章時觸發 `readingGate = .loading`。前 min(8,N) 頁就緒後 gate 變 `.open`，SwiftUI overlay 淡出。

**Tech Stack:** Swift, SwiftUI, UIKit, WKWebView, callAsyncJavaScript, @MainActor, Combine

---

## 文件映射

| 文件 | 操作 | 說明 |
|------|------|------|
| `Models/EPUBSnapshotWorker.swift` | **刪除** | 被新版取代 |
| `Models/EPUBSnapshotManager.swift` | **刪除** | 被新版取代 |
| `Models/Models.swift` | **修改** | 新增 `ReadingGateState` enum |
| `Models/LiveWebReader.swift` | **修改** | 暴露 schemeHandler、新增 storeSnapshot、chapterHTMLForSnapshot |
| `Models/EPUBPageRenderer.swift` | **修改** | 新增 readingGate、snapshotWebView、triggerGate、storeSnapshot |
| `Models/PageSnapshotProvider.swift` | **修改** | 新增 store(image:forGlobalPage:) |
| `Models/EPUBSnapshotWebView.swift` | **新建** | 核心：UIWindow、WKWebView、paginationReady、waitForPageReady、loadAndCapture |
| `Views/ReaderView.swift` | **修改** | spinner overlay、gate 監聽 |
| `Views/SnapshotReaderView.swift` | **清理** | 移除舊 workaround（保留 guard） |

---

## Task 1：刪除舊文件

**Files:**
- Delete: `yuedu app/Models/EPUBSnapshotWorker.swift`
- Delete: `yuedu app/Models/EPUBSnapshotManager.swift`

- [ ] **Step 1.1：刪除文件**

```bash
cd "/Users/zhangruilin/Desktop/yuedu app"
rm "yuedu app/Models/EPUBSnapshotWorker.swift"
rm "yuedu app/Models/EPUBSnapshotManager.swift"
```

- [ ] **Step 1.2：在 Xcode 中移除引用**

在 Xcode Project Navigator 中選中這兩個文件 → Delete → "Move to Trash"（若 git rm 未自動處理）。

- [ ] **Step 1.3：確認 build 仍可通過**

```bash
xcodebuild -scheme "yuedu app" -destination "platform=iOS Simulator,arch=arm64" build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

期望輸出：`** BUILD SUCCEEDED **`

- [ ] **Step 1.4：Commit**

```bash
git add -A
git commit -m "refactor: remove obsolete EPUBSnapshotWorker and EPUBSnapshotManager"
```

---

## Task 2：新增 ReadingGateState

**Files:**
- Modify: `yuedu app/Models/Models.swift`

- [ ] **Step 2.1：在 Models.swift 找到合適位置，加入 enum**

在 `Models.swift` 底部（或 `PageRenderState` 附近）加入：

```swift
enum ReadingGateState: Equatable {
    case loading   // 顯示 spinner，翻頁手勢不響應
    case open      // 允許閱讀
}
```

- [ ] **Step 2.2：Build 確認無錯誤**

```bash
xcodebuild -scheme "yuedu app" -destination "platform=iOS Simulator,arch=arm64" build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

- [ ] **Step 2.3：Commit**

```bash
git add "yuedu app/Models/Models.swift"
git commit -m "feat: add ReadingGateState enum"
```

---

## Task 3：LiveWebReader 暴露內部接口

**Files:**
- Modify: `yuedu app/Models/LiveWebReader.swift`

需要新增三個接口供 `EPUBSnapshotWebView` 和 `EPUBPageRenderer` 使用。

- [ ] **Step 3.1：將 `schemeHandler` 從 private 改為 internal**

找到：
```swift
private let schemeHandler = ReaderSchemeHandler()
```
改為：
```swift
let schemeHandler = ReaderSchemeHandler()
```

- [ ] **Step 3.2：在 `// MARK: - EPUBHTMLBuilder Proxy` 區塊附近新增 `chapterHTMLForSnapshot`**

在 `buildChapterHTML` 方法群組末尾加入：

```swift
/// 供 EPUBSnapshotWebView 用：以 snapshotBridge 名稱構建章節 HTML。
func chapterHTMLForSnapshot(at index: Int) async -> (html: String, baseURL: URL)? {
    guard let session = publicationSession else { return nil }
    do {
        let rawHTML = try await session.chapterHTML(at: index)
        let baseURL = session.chapterBaseURL(at: index)
        let wrapped = buildChapterHTML(
            chapterHTML: rawHTML,
            chapterBaseURL: baseURL,
            bridgeName: "snapshotBridge"
        )
        return (wrapped, baseURL)
    } catch {
        return nil
    }
}
```

- [ ] **Step 3.3：在截圖相關 MARK 區塊新增 `storeSnapshot`**

在 `snapshot(forPage:)` 方法附近加入：

```swift
/// 供 EPUBSnapshotWebView 直接推入截圖結果，繞過 scroll-capture 流程。
func storeSnapshot(image: UIImage, forGlobalPage page: Int) {
    snapshotImages[page] = image
    snapshotStates[page] = .full
    snapshotTasks[page]?.cancel()
    snapshotTasks.removeValue(forKey: page)
    snapshotVersion += 1   // 觸發 objectWillChange → PageSnapshotProvider 更新
}
```

- [ ] **Step 3.4：Build 確認無錯誤**

```bash
xcodebuild -scheme "yuedu app" -destination "platform=iOS Simulator,arch=arm64" build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

- [ ] **Step 3.5：Commit**

```bash
git add "yuedu app/Models/LiveWebReader.swift"
git commit -m "feat: expose schemeHandler, storeSnapshot, chapterHTMLForSnapshot on LiveWebReader"
```

---

## Task 4：PageSnapshotProvider 新增 store()

**Files:**
- Modify: `yuedu app/Models/PageSnapshotProvider.swift`

- [ ] **Step 4.1：在 `invalidate()` 方法後面加入 `store()`**

```swift
/// Gate 預渲染推入：直接寫入 NSCache，繞過 priority queue 的距離限制。
func store(image: UIImage, forGlobalPage page: Int) {
    cache.setObject(image, forKey: NSNumber(value: page))
    // version 已由 LiveWebReader.storeSnapshot → objectWillChange → sink 觸發更新
    // 此處直接寫 cache 是為了讓下次 cachedSnapshot() 立即命中，無需回調
}
```

- [ ] **Step 4.2：Build 確認**

```bash
xcodebuild -scheme "yuedu app" -destination "platform=iOS Simulator,arch=arm64" build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

- [ ] **Step 4.3：Commit**

```bash
git add "yuedu app/Models/PageSnapshotProvider.swift"
git commit -m "feat: add PageSnapshotProvider.store(image:forGlobalPage:)"
```

---

## Task 5：EPUBPageRenderer 新增 readingGate + 代理方法

**Files:**
- Modify: `yuedu app/Models/EPUBPageRenderer.swift`

- [ ] **Step 5.1：新增 readingGate @Published 屬性**

在 `private let engine = LiveWebReader()` 後加入：

```swift
@Published var readingGate: ReadingGateState = .loading
```

- [ ] **Step 5.2：新增代理方法（放在 snapshot 相關方法群組末尾）**

```swift
func storeSnapshot(image: UIImage, forGlobalPage page: Int) {
    engine.storeSnapshot(image: image, forGlobalPage: page)
}

func chapterHTMLForSnapshot(at index: Int) async -> (html: String, baseURL: URL)? {
    await engine.chapterHTMLForSnapshot(at: index)
}

var snapshotSchemeHandler: ReaderSchemeHandler {
    engine.schemeHandler
}
```

- [ ] **Step 5.3：Build 確認**

```bash
xcodebuild -scheme "yuedu app" -destination "platform=iOS Simulator,arch=arm64" build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

- [ ] **Step 5.4：Commit**

```bash
git add "yuedu app/Models/EPUBPageRenderer.swift"
git commit -m "feat: add readingGate and snapshot bridge methods to EPUBPageRenderer"
```

---

## Task 6：新建 EPUBSnapshotWebView.swift（骨架 + UIWindow + JS bridge）

**Files:**
- Create: `yuedu app/Models/EPUBSnapshotWebView.swift`

- [ ] **Step 6.1：建立文件，寫入骨架**

```swift
import UIKit
import WebKit

/// 獨立截圖 WebView：放在隱藏 UIWindow 中，串行為每頁截圖。
/// 與閱讀 WebView 完全分離，消除 scroll/render 競爭。
@MainActor
final class EPUBSnapshotWebView: NSObject {

    // MARK: - 公開接口
    private(set) var isCapturing = false
    private var currentCaptureTask: Task<Void, Never>?

    // MARK: - 私有狀態
    private let webView: WKWebView
    private let snapshotWindow: UIWindow
    private var paginationContinuation: CheckedContinuation<PaginationInfo?, Never>?

    struct PaginationInfo {
        let pageCount: Int
        let pageOffsets: [CGFloat]
    }

    // MARK: - 初始化

    init(schemeHandler: ReaderSchemeHandler) {
        // 1. 建立獨立的 WKWebViewConfiguration（獨立 bridge name）
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setURLSchemeHandler(schemeHandler, forURLScheme: PublicationSession.scheme)

        let ucc = WKUserContentController()
        config.userContentController = ucc

        // 2. 建立 WKWebView
        let size = UIScreen.main.bounds.size
        let wv = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: config)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = false
        self.webView = wv

        // 3. 建立隱藏 UIWindow（必須 visible 才能進渲染樹，alpha=0 對用戶不可見）
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
        }
        window.windowLevel = UIWindow.Level.normal - 1
        window.frame = UIScreen.main.bounds
        window.isHidden = false
        window.alpha = 0
        self.snapshotWindow = window

        super.init()

        // 4. 把 WebView 加入 window
        window.addSubview(wv)
        wv.frame = window.bounds

        // 5. 註冊 JS bridge
        ucc.add(self, name: "snapshotBridge")
        wv.navigationDelegate = self
    }

    deinit {
        snapshotWindow.isHidden = true
    }

    // MARK: - 公開方法

    func cancel() {
        currentCaptureTask?.cancel()
        currentCaptureTask = nil
        isCapturing = false
        paginationContinuation?.resume(returning: nil)
        paginationContinuation = nil
    }
}

// MARK: - WKNavigationDelegate
extension EPUBSnapshotWebView: WKNavigationDelegate {}

// MARK: - WKScriptMessageHandler
extension EPUBSnapshotWebView: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "snapshotBridge",
              let body = message.body as? [String: Any],
              let type = body["type"] as? String,
              type == "paginationReady",
              let payload = body["payload"] as? [String: Any] else { return }

        let pageCount = payload["pageCount"] as? Int ?? 0
        let offsets = (payload["pageOffsets"] as? [Double])?.map { CGFloat($0) } ?? []
        let info = PaginationInfo(pageCount: pageCount, pageOffsets: offsets)
        paginationContinuation?.resume(returning: info)
        paginationContinuation = nil
    }
}
```

- [ ] **Step 6.2：確認能加入 Xcode project（在 Xcode 中 Add Files to target）**

- [ ] **Step 6.3：Build 確認**

```bash
xcodebuild -scheme "yuedu app" -destination "platform=iOS Simulator,arch=arm64" build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

- [ ] **Step 6.4：Commit**

```bash
git add "yuedu app/Models/EPUBSnapshotWebView.swift"
git commit -m "feat: add EPUBSnapshotWebView skeleton with hidden UIWindow and JS bridge"
```

---

## Task 7：實現 waitForPageReady

**Files:**
- Modify: `yuedu app/Models/EPUBSnapshotWebView.swift`

- [ ] **Step 7.1：在 EPUBSnapshotWebView 內加入 waitForPageReady**

```swift
// MARK: - 渲染等待

/// 等待 WebView 渲染完成後再截圖。
/// 普通頁：等 2 個 rAF（~33ms @ 60fps）；圖片頁：額外等 img.onload（上限 600ms）。
private func waitForPageReady(hasImages: Bool) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        var workItem: DispatchWorkItem?
        var resumed = false

        let finish: () -> Void = {
            guard !resumed else { return }
            resumed = true
            workItem?.cancel()
            continuation.resume()
        }

        // 超時保底
        let timeout: TimeInterval = hasImages ? 0.6 : 0.08
        let item = DispatchWorkItem { finish() }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: item)

        // JS 路徑
        let js: String
        if hasImages {
            js = """
            await new Promise(resolve => {
                const imgs = [...document.images];
                if (imgs.every(i => i.complete)) { resolve(); return; }
                let count = imgs.filter(i => !i.complete).length;
                imgs.filter(i => !i.complete).forEach(i => {
                    i.addEventListener('load',  () => { if (--count === 0) resolve(); });
                    i.addEventListener('error', () => { if (--count === 0) resolve(); });
                });
            });
            await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
            """
        } else {
            js = "await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))"
        }

        webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { _ in finish() }
    }
}
```

- [ ] **Step 7.2：Build 確認**

```bash
xcodebuild -scheme "yuedu app" -destination "platform=iOS Simulator,arch=arm64" build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

- [ ] **Step 7.3：Commit**

```bash
git add "yuedu app/Models/EPUBSnapshotWebView.swift"
git commit -m "feat: add waitForPageReady with rAF + img.onload + timeout fallback"
```

---

## Task 8：實現 loadAndCapture 串行截圖循環

**Files:**
- Modify: `yuedu app/Models/EPUBSnapshotWebView.swift`

- [ ] **Step 8.1：新增 paginationReady 等待方法**

```swift
/// 載入 HTML 後等待 paginationReady 信號（最多 5 秒）。
private func waitForPagination() async -> PaginationInfo? {
    await withCheckedContinuation { continuation in
        paginationContinuation = continuation
        // 5 秒超時：視為章節無法分頁，強制跳過 gate
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.paginationContinuation != nil else { return }
            self.paginationContinuation?.resume(returning: nil)
            self.paginationContinuation = nil
        }
    }
}
```

- [ ] **Step 8.2：新增頁面截圖輔助方法**

```swift
/// 截取當前 WebView 畫面。
private func captureCurrentPage() async -> UIImage? {
    await withCheckedContinuation { continuation in
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: webView.bounds.size)
        config.snapshotWidth = NSNumber(value: Double(webView.bounds.width))
        webView.takeSnapshot(with: config) { image, _ in
            continuation.resume(returning: image)
        }
    }
}

/// 偵測當前頁是否含有圖片元素。
private func pageHasImages() async -> Bool {
    let result = try? await webView.evaluateJavaScript("document.images.length > 0")
    return (result as? Bool) ?? false
}
```

- [ ] **Step 8.3：實現 loadAndCapture**

```swift
// MARK: - 主要截圖流程

/// 載入章節 HTML 並串行截圖。
/// - Parameters:
///   - html: 已用 snapshotBridge 構建好的章節 HTML
///   - baseURL: 章節資源基礎 URL
///   - globalPageOffset: 本章第一頁的全局頁碼（用於 onPageReady 回調）
///   - onPageReady: 每頁截圖完成時回調（全局頁碼，圖片）
///   - onGateReady: 前 min(8, total) 頁就緒時回調一次
func loadAndCapture(
    html: String,
    baseURL: URL,
    globalPageOffset: Int,
    onPageReady: @escaping (Int, UIImage) -> Void,
    onGateReady: @escaping () -> Void
) {
    cancel()  // 先取消正在進行的任務

    isCapturing = true
    currentCaptureTask = Task { [weak self] in
        guard let self else { return }
        defer { self.isCapturing = false }

        // 1. 載入 HTML
        self.webView.loadHTMLString(html, baseURL: baseURL)

        // 2. 等待 paginationReady
        guard let pagination = await self.waitForPagination() else {
            onGateReady()  // 超時：強制開 gate
            return
        }
        guard !Task.isCancelled else { return }

        let pageCount = max(pagination.pageCount, 1)
        let offsets = pagination.pageOffsets
        let gatePageCount = min(8, pageCount)
        var gateTriggered = false

        // 3. 串行截圖
        for localPage in 0..<pageCount {
            guard !Task.isCancelled else { return }

            // 滾到目標頁
            let targetOffset: CGFloat
            if offsets.indices.contains(localPage) {
                targetOffset = offsets[localPage]
            } else {
                targetOffset = CGFloat(localPage) * self.webView.bounds.width
            }
            self.webView.scrollView.setContentOffset(
                CGPoint(x: targetOffset, y: 0), animated: false
            )

            // 等待渲染
            let hasImages = await self.pageHasImages()
            await self.waitForPageReady(hasImages: hasImages)
            guard !Task.isCancelled else { return }

            // 截圖
            if let image = await self.captureCurrentPage() {
                let globalPage = globalPageOffset + localPage
                onPageReady(globalPage, image)
            }

            // gate 判斷：前 min(8, total) 頁截完後觸發一次
            if !gateTriggered && (localPage + 1) >= gatePageCount {
                gateTriggered = true
                onGateReady()
            }
        }

        // 若章節不足 gatePageCount（理論上不會，但作 fallback）
        if !gateTriggered {
            onGateReady()
        }
    }
}
```

- [ ] **Step 8.4：Build 確認**

```bash
xcodebuild -scheme "yuedu app" -destination "platform=iOS Simulator,arch=arm64" build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

- [ ] **Step 8.5：Commit**

```bash
git add "yuedu app/Models/EPUBSnapshotWebView.swift"
git commit -m "feat: implement EPUBSnapshotWebView.loadAndCapture serial snapshot loop"
```

---

## Task 9：EPUBPageRenderer 持有 EPUBSnapshotWebView + 觸發 gate

**Files:**
- Modify: `yuedu app/Models/EPUBPageRenderer.swift`

- [ ] **Step 9.1：新增 snapshotWebView 惰性屬性**

在 `private let engine = LiveWebReader()` 下方加入：

```swift
private lazy var snapshotWebView = EPUBSnapshotWebView(schemeHandler: engine.schemeHandler)
```

- [ ] **Step 9.2：新增私有 triggerReadingGate 方法**

```swift
private func triggerReadingGate(forChapter chapterIdx: Int) {
    readingGate = .loading
    snapshotWebView.cancel()
    Task { [weak self] in
        guard let self else { return }
        guard let (html, baseURL) = await self.chapterHTMLForSnapshot(at: chapterIdx) else {
            self.readingGate = .open   // fallback：HTML 取不到直接放行
            return
        }
        let globalOffset = self.engine.firstGlobalPage(forChapter: chapterIdx) ?? 0
        await MainActor.run {
            self.snapshotWebView.loadAndCapture(
                html: html,
                baseURL: baseURL,
                globalPageOffset: globalOffset,
                onPageReady: { [weak self] globalPage, image in
                    guard let self else { return }
                    self.engine.storeSnapshot(image: image, forGlobalPage: globalPage)
                },
                onGateReady: { [weak self] in
                    withAnimation(.easeOut(duration: 0.2)) {
                        self?.readingGate = .open
                    }
                }
            )
        }
    }
}
```

- [ ] **Step 9.3：在 loadEPUB / loadEPUBScroll 後觸發 gate**

找到 `func loadEPUB(source:settings:)` 的 `engine.load(...)` 呼叫後加入：

```swift
readingGate = .loading
// 等待 engine 完成初始化（chapter 0 確定後再觸發截圖）
Task { [weak self] in
    guard let self else { return }
    // 等 engine 就緒（簡單等一個 run loop，engine.load 是同步觸發 async load）
    try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
    await MainActor.run { self.triggerReadingGate(forChapter: 0) }
}
```

對 `loadEPUBScroll` 做相同處理。

- [ ] **Step 9.4：覆寫 jumpToChapter 加入 gate 邏輯**

找到：
```swift
func jumpToChapter(_ chapterIdx: Int, preferredLocalPage: Int? = nil) {
    engine.jumpToChapter(chapterIdx, preferredLocalPage: preferredLocalPage)
}
```
改為：
```swift
func jumpToChapter(_ chapterIdx: Int, preferredLocalPage: Int? = nil) {
    engine.jumpToChapter(chapterIdx, preferredLocalPage: preferredLocalPage)
    // gate 判斷準則：目標章節頁 0 截圖不存在才觸發
    let firstPage = engine.firstGlobalPage(forChapter: chapterIdx) ?? -1
    if firstPage < 0 || engine.snapshot(forPage: firstPage) == nil {
        triggerReadingGate(forChapter: chapterIdx)
    }
}
```

- [ ] **Step 9.5：Build 確認**

```bash
xcodebuild -scheme "yuedu app" -destination "platform=iOS Simulator,arch=arm64" build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

- [ ] **Step 9.6：Commit**

```bash
git add "yuedu app/Models/EPUBPageRenderer.swift"
git commit -m "feat: wire EPUBSnapshotWebView into EPUBPageRenderer with gate trigger"
```

---

## Task 10：ReaderView 新增 spinner overlay

**Files:**
- Modify: `yuedu app/Views/ReaderView.swift`

- [ ] **Step 10.1：找到 EPUB 閱讀器容器 View（使用 `SnapshotReaderView` 的地方）**

使用 Grep 找到 SnapshotReaderView 的使用位置：

```bash
grep -n "SnapshotReaderView" "yuedu app/Views/ReaderView.swift"
```

- [ ] **Step 10.2：在 SnapshotReaderView 的外層容器加入 gate overlay**

在包含 `SnapshotReaderView(...)` 的 ZStack 或 Group 中，加入 overlay：

```swift
.overlay {
    if epubRenderer.readingGate == .loading {
        ZStack {
            Color.black.opacity(0.01)  // 吸收觸摸事件
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)
                .tint(.gray)
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }
}
.animation(.easeOut(duration: 0.2), value: epubRenderer.readingGate)
.allowsHitTesting(epubRenderer.readingGate == .open)
```

**重要**：`.allowsHitTesting(epubRenderer.readingGate == .open)` 在 gate `.loading` 時禁用翻頁手勢。

- [ ] **Step 10.3：Build 確認**

```bash
xcodebuild -scheme "yuedu app" -destination "platform=iOS Simulator,arch=arm64" build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

- [ ] **Step 10.4：Commit**

```bash
git add "yuedu app/Views/ReaderView.swift"
git commit -m "feat: add ReadingGate spinner overlay to ReaderView"
```

---

## Task 11：清理 LiveWebReader 舊截圖代碼

**Files:**
- Modify: `yuedu app/Models/LiveWebReader.swift`

- [ ] **Step 11.1：移除 waitForWebViewRender 方法**

找到並刪除整個 `waitForWebViewRender` 方法（本次會話新增，約 15 行）。

- [ ] **Step 11.2：移除 per-WebView 互斥鎖**

找到並刪除以下屬性和方法（本次會話新增）：
- `private var snapshotLockByWebView: [ObjectIdentifier: Bool]`
- `private var snapshotWaitersByWebView: [ObjectIdentifier: [CheckedContinuation<Void, Never>]]`
- `acquireSnapshotLock(for:)` 方法
- `releaseSnapshotLock(for:)` 方法

同時在 `snapshotImage` 開頭刪除這幾行：
```swift
await acquireSnapshotLock(for: sourceWebView)
defer { releaseSnapshotLock(for: sourceWebView) }
```

並在 `clearMemoryCache` 中刪除相關的釋放代碼：
```swift
snapshotLockByWebView.removeAll()
let allWaiters = snapshotWaitersByWebView.values.flatMap { $0 }
snapshotWaitersByWebView.removeAll()
allWaiters.forEach { $0.resume() }
```

- [ ] **Step 11.3：還原 waitForWebViewRender 調用為原始 35ms sleep（保留舊代碼作後備）**

在 `snapshotImage` 中，將 `await waitForWebViewRender(sourceWebView)` 改回：

```swift
try? await Task.sleep(nanoseconds: 35_000_000)
```

> 注意：`snapshotImage` 現在主要被 `EPUBSnapshotWebView` 架構繞過。保留此代碼作為對舊代碼路徑的後備（不影響主路徑）。

- [ ] **Step 11.4：Build 確認**

```bash
xcodebuild -scheme "yuedu app" -destination "platform=iOS Simulator,arch=arm64" build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

- [ ] **Step 11.5：Commit**

```bash
git add "yuedu app/Models/LiveWebReader.swift"
git commit -m "refactor: remove per-WebView snapshot lock and rAF workaround from LiveWebReader"
```

---

## Task 12：最終整合驗證（手動測試）

- [ ] **Step 12.1：在 iOS 模擬器上運行 app**

在 Xcode 中 Run（Cmd+R），選擇 iPhone 15 模擬器。

- [ ] **Step 12.2：測試開書 gate**

打開一本 EPUB 書籍。預期：
- spinner 出現在閱讀器中央
- 約 1 秒後 spinner 淡出
- 第 1 頁顯示正確內容，無空白、無重複

- [ ] **Step 12.3：測試封面頁**

打開有封面圖的 EPUB。預期：
- spinner 淡出後封面圖完整顯示（不白屏）

- [ ] **Step 12.4：測試快速翻頁**

連續快速翻 10 頁。預期：每頁都有內容，無空白頁。

- [ ] **Step 12.5：測試跳章**

從目錄跳到第 10 章。預期：
- spinner 出現
- 約 1 秒後淡出
- 顯示正確章節內容

- [ ] **Step 12.6：測試快速連跳章節**

在目錄中快速選擇多個章節（間隔 < 0.5s）。預期：
- 最後選中的章節正確顯示
- 前一個章節的截圖任務被正確取消（不污染緩存）

- [ ] **Step 12.7：最終 commit**

```bash
git add -A
git commit -m "feat: complete Reading Gate + EPUBSnapshotWebView implementation"
```
