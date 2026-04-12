# yuedu app Code Review Implementation Plan

## Objective
Implement all remaining recommendations from the code review report for the `yuedu app` project to improve architecture, performance, stability, and maintainability.

## Status: 🔴 Not Started

## Phases

### Phase 1: Fix Error Swallowing in `BookStore`
- [ ] Find usages of `try?` in `BookStore.swift` (actually in `Models.swift` where `BookStore` resides).
- [ ] Replace `try?` with `do-catch` blocks for file operations (like `removeItem`, `write`).
- [ ] Add `Logger` (OSLog) to log the caught errors.
- status: complete

### Phase 2: Standardize Concurrency in `BookStore` & Initialization
- [ ] Look at `Models.swift` for mix of `async/await` and `DispatchQueue`.
- [ ] Clean up concurrency usage (use `@MainActor` and `Task` where appropriate).
- status: complete

### Phase 3: Add Concurrency Limit to `ChapterUpdater`
- [ ] Find `ChapterUpdater.refreshAll(bookStore:)` in network request logic.
- [ ] Modify the `TaskGroup` to limit concurrent updates (e.g., max 3-5 concurrent tasks) to avoid network storm and anti-scraping triggers on app startup.
- status: complete

### Phase 4: Extract Magic Numbers in `CoreTextPageEngineView`
- [ ] Locate `CoreTextPageEngineView` and the `handleCoverPan` method.
- [ ] Extract magic numbers (e.g., `-18`, `0.34`, `560`) into well-named constants.
- [ ] Add explanatory comments for these empirical values.
- status: complete

### Phase 5: Refactor `ReaderView` to use `ReaderViewModel` (MVVM)
- [ ] Create `ReaderViewModel.swift` inside `Views` or `Models` directory.
- [ ] Move state variables (current page, chapter index, brightness, etc.) from `ReaderView` to `ReaderViewModel`.
- [ ] Move data fetching logic (`loadContent`, `fetchChapterIfNeeded`) to `ReaderViewModel`.
- [ ] Refactor `ReaderView.swift` to consume `ReaderViewModel` and reduce its size/responsibilities.
- status: complete

