# 開書／關書動畫 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 點擊書架書籍時，閱讀器從書籍列表格子縮放展開到全螢幕；關閉時縮小收回同一位置。

**Architecture:** 移除 `.fullScreenCover`，改在 `HomeView` 最外層 `ZStack` 疊一個 `BookReaderOverlay`。用 `BookFramePreferenceKey` 收集每本書的螢幕座標，用 `scaleEffect` + `offset` 動畫從書籍格子展開到全螢幕。`ReaderView` 新增 `onClose` callback 取代 `presentationMode.dismiss()`。

**Tech Stack:** SwiftUI, `PreferenceKey`, `GeometryReader`, `.spring()` 動畫

---

## 修改清單

| 檔案 | 動作 |
|------|------|
| `Views/HomeView.swift` | 加 `BookFramePreferenceKey`、更新 `BookRow`、加 `BookReaderOverlay`、改 `HomeView.body` |
| `Views/ReaderView.swift` | 加 `onClose` 參數，改 `presentationMode.dismiss()` 呼叫 |

---

### Task 1：新增 `BookFramePreferenceKey` + 讓 `BookRow` 回報 frame

**Files:**
- Modify: `Views/HomeView.swift`

- [ ] **Step 1：在 HomeView.swift 末尾（`BookRow` struct 之後、檔案結尾之前）加入 PreferenceKey**

找到最後一行 `}` 之前，加入：

```swift
// MARK: - Book Frame Preference Key
struct BookFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
```

- [ ] **Step 2：在 `BookRow.body` 的最外層 `HStack` 加上 `.background(GeometryReader)` 回報 frame**

找到 `BookRow` 的 `body`，在 `HStack { ... }.padding(.vertical, 4)` 後加 `.background`：

```swift
// 改前：
HStack(spacing: 14) {
    ...
}
.padding(.vertical, 4)

// 改後：
HStack(spacing: 14) {
    ...
}
.padding(.vertical, 4)
.background(GeometryReader { geo in
    Color.clear.preference(
        key: BookFramePreferenceKey.self,
        value: [book.id: geo.frame(in: .global)]
    )
})
```

- [ ] **Step 3：Build 確認無錯誤**

在 Xcode 按 ⌘B。預期：Build succeeded，無新錯誤。

- [ ] **Step 4：commit**

```bash
git add "yuedu app/Views/HomeView.swift"
git commit -m "feat(animation): add BookFramePreferenceKey and book row frame reporting"
```

---

### Task 2：加入 `BookReaderOverlay`、更新 `HomeView.body`

**Files:**
- Modify: `Views/HomeView.swift`

- [ ] **Step 1：在 `HomeView` 加入三個新 state**

在 `HomeView` 的現有 state 區段（`@State private var readerBookId: UUID? = nil` 那行之後）加入：

```swift
@State private var selectedBookFrame: CGRect = .zero
@State private var isReaderExpanded = false
@State private var bookFrames: [UUID: CGRect] = [:]
```

- [ ] **Step 2：更新 `bookList` 中的點擊動作，記錄 frame**

找到：
```swift
Button {
    readerBookId = book.id
} label: {
    BookRow(book: book)
}
```

改為：
```swift
Button {
    selectedBookFrame = bookFrames[book.id] ?? UIScreen.main.bounds
    readerBookId = book.id
} label: {
    BookRow(book: book)
}
```

- [ ] **Step 3：在 `HomeView.body` 最外層加 ZStack，移除 fullScreenCover**

找到 `HomeView.body`：
```swift
var body: some View {
    NavigationView {
        ...
    }
    .navigationViewStyle(.stack)
    .fullScreenCover(
        isPresented: Binding(
            get: { readerBookId != nil },
            set: { if !$0 { readerBookId = nil } }
        )
    ) {
        if let bookId = readerBookId {
            ReaderView(bookId: bookId).environmentObject(store)
        }
    }
}
```

改為（移除 `.fullScreenCover`，改用 ZStack）：

```swift
var body: some View {
    ZStack {
        NavigationView {
            ...
        }
        .navigationViewStyle(.stack)

        if let bookId = readerBookId {
            BookReaderOverlay(
                bookId: bookId,
                sourceFrame: selectedBookFrame,
                isExpanded: isReaderExpanded,
                onClose: {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                        isReaderExpanded = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        readerBookId = nil
                    }
                }
            )
            .environmentObject(store)
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    isReaderExpanded = true
                }
            }
            .ignoresSafeArea()
        }
    }
    .onPreferenceChange(BookFramePreferenceKey.self) { frames in
        bookFrames = frames
    }
}
```

注意：`.onPreferenceChange` 掛在 ZStack 上，`.navigationViewStyle(.stack)` 已移進 ZStack 內的 NavigationView 後面。原本 NavigationView 的所有 modifier（`.sheet`、`.alert` 等）保持不變，仍掛在 NavigationView 上。

- [ ] **Step 4：在 HomeView.swift 末尾（`BookFramePreferenceKey` 前面）加入 `BookReaderOverlay`**

```swift
// MARK: - Book Reader Overlay
private struct BookReaderOverlay: View {
    let bookId: UUID
    let sourceFrame: CGRect
    let isExpanded: Bool
    let onClose: () -> Void
    @EnvironmentObject var store: BookStore

    var body: some View {
        GeometryReader { proxy in
            let globalFrame = proxy.frame(in: .global)
            let scaleX = isExpanded ? 1.0 : max(sourceFrame.width  / globalFrame.width,  0.01)
            let scaleY = isExpanded ? 1.0 : max(sourceFrame.height / globalFrame.height, 0.01)
            let offsetX = isExpanded ? 0.0 : sourceFrame.midX - globalFrame.midX
            let offsetY = isExpanded ? 0.0 : sourceFrame.midY - globalFrame.midY

            ReaderView(bookId: bookId, onClose: onClose)
                .environmentObject(store)
                .scaleEffect(x: scaleX, y: scaleY)
                .offset(x: offsetX, y: offsetY)
                .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}
```

- [ ] **Step 5：Build 確認無錯誤**

按 ⌘B。預期：Build succeeded。若出現 `'ReaderView' initializer` 錯誤，表示 Task 3 需先完成，可先忽略此錯誤繼續 Task 3。

- [ ] **Step 6：commit**

```bash
git add "yuedu app/Views/HomeView.swift"
git commit -m "feat(animation): add BookReaderOverlay and ZStack-based book open/close"
```

---

### Task 3：更新 `ReaderView` 接受 `onClose` callback

**Files:**
- Modify: `Views/ReaderView.swift`

- [ ] **Step 1：新增 `onClose` 參數到 `ReaderView`**

找到：
```swift
struct ReaderView: View {
    let bookId: UUID
    @EnvironmentObject var store: BookStore
```

改為：
```swift
struct ReaderView: View {
    let bookId: UUID
    var onClose: (() -> Void)? = nil
    @EnvironmentObject var store: BookStore
```

- [ ] **Step 2：更新 `onBack` 的 dismiss 呼叫（line ~1069）**

找到：
```swift
onBack: {
    saveProgress()
    presentationMode.wrappedValue.dismiss()
},
```

改為：
```swift
onBack: {
    saveProgress()
    if let onClose { onClose() } else { presentationMode.wrappedValue.dismiss() }
},
```

- [ ] **Step 3：Build 確認無錯誤**

按 ⌘B。預期：Build succeeded，無錯誤。

- [ ] **Step 4：commit**

```bash
git add "yuedu app/Views/ReaderView.swift"
git commit -m "feat(animation): add onClose callback to ReaderView for animated dismiss"
```

---

### Task 4：手動驗證動畫效果

**Files:** 無程式碼修改

- [ ] **Step 1：在模擬器或實機執行 app**

- [ ] **Step 2：驗證開書動畫**
  - 書架有至少一本書
  - 點擊書籍 → 閱讀器應從該書列表格子的位置縮放展開，spring 動畫
  - 確認展開後是完整的閱讀器畫面

- [ ] **Step 3：驗證關書動畫**
  - 在閱讀器點左上角返回按鈕
  - 閱讀器應縮小收回到書架上對應書籍的位置
  - 確認書架正常顯示

- [ ] **Step 4：驗證捲動後位置正確**
  - 書架捲動到下方書籍
  - 點擊下方書籍
  - 確認展開/收合動畫對應正確的格子位置（不是最上方）

- [ ] **Step 5：驗證快速操作不崩潰**
  - 快速連續點擊開書→關書→開書，確認不崩潰、狀態正確

- [ ] **Step 6：若動畫有問題，調整 spring 參數**
  - 展開過快/過慢：調整 `BookReaderOverlay.onAppear` 的 `response`（0.35–0.55）
  - 收合彈性過強/過弱：調整 `onClose` 的 `response` 和 `dampingFraction`
  - 收合後 view 沒消失：確認 `asyncAfter` 延遲 ≥ spring `response + 0.05`
