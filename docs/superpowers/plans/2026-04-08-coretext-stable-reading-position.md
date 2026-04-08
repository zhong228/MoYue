# CoreText Stable Reading Position Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep CoreText chapter-boundary navigation and UI refresh anchored to stable `(spineIndex, charOffset)` content positions instead of unstable derived global page numbers.

**Architecture:** Add a CoreText-specific stable position type plus mapping helpers in the engine layer, then thread that position through CoreText page controllers and the `CoreTextPageEngineView` coordinator so notification-driven reloads and chapter-boundary backward navigation can recover the same content after offsets shift. Use unit tests to lock down the mapping behavior and placeholder position handoff before touching production code.

**Tech Stack:** Swift, Swift Testing, UIKit, CoreText, SwiftUI

---

### Task 1: Add failing tests for stable position mapping

**Files:**
- Modify: `/Users/zhangruilin/Desktop/yuedu app/yuedu appTests/yuedu_appTests.swift`
- Test: `/Users/zhangruilin/Desktop/yuedu app/yuedu appTests/yuedu_appTests.swift`

- [ ] **Step 1: Write the failing tests**

Add tests covering:

```swift
@Test func coreTextReadingPositionMapsToCurrentOffsets() {
    let layouts = makeSampleChapterLayouts()
    let position = CoreTextReadingPosition(spineIndex: 1, charOffset: 12)

    let page = CoreTextReadingPositionMapper.pageIndex(
        for: position,
        layouts: layouts,
        spinePageOffsets: [0, 5]
    )

    #expect(page == 6)
}

@Test func coreTextReadingPositionChapterEndResolvesToLastPage() {
    let layouts = makeSampleChapterLayouts()
    let position = CoreTextReadingPosition(spineIndex: 1, charOffset: .max)

    let page = CoreTextReadingPositionMapper.pageIndex(
        for: position,
        layouts: layouts,
        spinePageOffsets: [0, 5]
    )

    #expect(page == 7)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project '/Users/zhangruilin/Desktop/yuedu app/yuedu app.xcodeproj' -scheme 'yuedu app' -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:'yuedu appTests/yuedu_appTests'`
Expected: FAIL with missing `CoreTextReadingPosition` / `CoreTextReadingPositionMapper`

- [ ] **Step 3: Commit**

```bash
git add '/Users/zhangruilin/Desktop/yuedu app/yuedu appTests/yuedu_appTests.swift'
git commit -m "test: cover CoreText stable reading position mapping"
```

### Task 2: Implement stable position mapping in the CoreText engine layer

**Files:**
- Create: `/Users/zhangruilin/Desktop/yuedu app/yuedu app/Models/CoreText/CoreTextReadingPosition.swift`
- Modify: `/Users/zhangruilin/Desktop/yuedu app/yuedu app/Models/CoreText/PageRenderingProvider.swift`
- Modify: `/Users/zhangruilin/Desktop/yuedu app/yuedu app/Models/CoreText/CoreTextPageEngine.swift`
- Modify: `/Users/zhangruilin/Desktop/yuedu app/yuedu app/Models/CoreText/CoreTextPageView.swift`
- Test: `/Users/zhangruilin/Desktop/yuedu app/yuedu appTests/yuedu_appTests.swift`

- [ ] **Step 1: Write the minimal implementation**

Implement:

```swift
struct CoreTextReadingPosition: Equatable {
    let spineIndex: Int
    let charOffset: Int
}

enum CoreTextReadingPositionMapper {
    static func pageIndex(
        for position: CoreTextReadingPosition,
        layouts: [Int: CoreTextPaginator.ChapterLayout],
        spinePageOffsets: [Int]
    ) -> Int? { ... }
}
```

Then expose provider helpers:

```swift
func readingPosition(forPage page: Int) -> CoreTextReadingPosition?
func pageIndex(for position: CoreTextReadingPosition) -> Int?
func pageViewController(for position: CoreTextReadingPosition) -> UIViewController
```

Also let CoreText page/snapshot/placeholder controllers optionally carry a `CoreTextReadingPosition`.

- [ ] **Step 2: Run test to verify it passes**

Run: `xcodebuild test -project '/Users/zhangruilin/Desktop/yuedu app/yuedu app.xcodeproj' -scheme 'yuedu app' -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:'yuedu appTests/yuedu_appTests'`
Expected: PASS for the new stable-position tests

- [ ] **Step 3: Commit**

```bash
git add '/Users/zhangruilin/Desktop/yuedu app/yuedu app/Models/CoreText/CoreTextReadingPosition.swift' \
        '/Users/zhangruilin/Desktop/yuedu app/yuedu app/Models/CoreText/PageRenderingProvider.swift' \
        '/Users/zhangruilin/Desktop/yuedu app/yuedu app/Models/CoreText/CoreTextPageEngine.swift' \
        '/Users/zhangruilin/Desktop/yuedu app/yuedu app/Models/CoreText/CoreTextPageView.swift' \
        '/Users/zhangruilin/Desktop/yuedu app/yuedu appTests/yuedu_appTests.swift'
git commit -m "feat: add stable CoreText reading position mapping"
```

### Task 3: Switch the coordinator to stable position recovery

**Files:**
- Modify: `/Users/zhangruilin/Desktop/yuedu app/yuedu app/Views/ReaderView.swift`
- Modify: `/Users/zhangruilin/Desktop/yuedu app/yuedu app/Models/EPUBPageRenderer.swift`
- Test: `/Users/zhangruilin/Desktop/yuedu app/yuedu appTests/yuedu_appTests.swift`

- [ ] **Step 1: Update coordinator navigation to use stable positions**

Implement:

```swift
private var currentCoreTextPosition: CoreTextReadingPosition?

// On chapter-ready notification:
// prefer currentEngine.pageViewController(for: currentCoreTextPosition)

// On didFinishAnimating:
// capture currentCoreTextPosition before updating currentPage/onPageChanged

// On chapter-boundary backward navigation:
// request currentEngine.pageViewController(for: .init(spineIndex: previousSpine, charOffset: .max))
```

- [ ] **Step 2: Run targeted tests and build verification**

Run: `xcodebuild test -project '/Users/zhangruilin/Desktop/yuedu app/yuedu app.xcodeproj' -scheme 'yuedu app' -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:'yuedu appTests/yuedu_appTests'`
Expected: PASS

Run: `xcodebuild build -project '/Users/zhangruilin/Desktop/yuedu app/yuedu app.xcodeproj' -scheme 'yuedu app' -destination 'generic/platform=iOS Simulator'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add '/Users/zhangruilin/Desktop/yuedu app/yuedu app/Views/ReaderView.swift' \
        '/Users/zhangruilin/Desktop/yuedu app/yuedu app/Models/EPUBPageRenderer.swift'
git commit -m "fix: keep CoreText navigation anchored to stable positions"
```
