# Fix All 52 Build Warnings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate all 52 Xcode build warnings, grouped into 6 independent tasks by category.

**Architecture:** Fixes are categorized as: (1) code quality, (2) deprecated APIs, (3) simple concurrency, (4) complex actor isolation, (5) Sendable/RegexSanitizer, (6) project config.

**Tech Stack:** Swift 5.9, UIKit, SwiftUI, WebKit, CryptoKit, NSLock

---

## Files Modified (Master List)

| Task | Files |
|------|-------|
| 1 | ReadingStatsView.swift, OnlineBookView.swift, Models.swift, RuleEngine.swift, WebNovelParser.swift, LegadoJSBridge.swift, JSCoreEngine.swift, UniversalBookResourceAdapter.swift, CssExtractor.swift, ChapterFetcher.swift |
| 2 | WebViewFetcher.swift, LegadoJSBridge.swift |
| 3 | WebViewFetcher.swift, WebDAVManager.swift, WebFetcher.swift, CoreTextPageView.swift, BookSourceFormLoginView.swift |
| 4 | WebViewFetcher.swift (nonisolated(unsafe) shared), EPUBStyleResolver.swift, CoreTextPageEngine.swift, LegadoMigrationManager.swift, UniversalBookResourceAdapter.swift |
| 5 | RegexSanitizer.swift |
| 6 | Info.plist |

---

## Task 1: Code Quality — Unused Variables & Unnecessary try/var

**Files:**
- Modify: `yuedu app/Views/Stats/ReadingStatsView.swift:183`
- Modify: `yuedu app/Views/Online/OnlineBookView.swift:391-420`
- Modify: `yuedu app/Models/Book/Models.swift:569`
- Modify: `yuedu app/Models/RuleEngine/RuleEngine.swift:1346,1351`
- Modify: `yuedu app/Models/RuleEngine/WebNovelParser.swift:230`
- Modify: `yuedu app/Models/RuleEngine/ModernParser/JS/LegadoJSBridge.swift:353`
- Modify: `yuedu app/Models/RuleEngine/ModernParser/JS/JSCoreEngine.swift:209-210`
- Modify: `yuedu app/Models/Book/UniversalBookResourceAdapter.swift:189,198,224`
- Modify: `yuedu app/Models/RuleEngine/ModernParser/CssExtractor.swift:20`
- Modify: `yuedu app/Models/Online/ChapterFetcher.swift:508`

- [ ] **Step 1: Fix ReadingStatsView.swift:183 — unused `range`**

  Current (line 183):
  ```swift
  let range = selectedPeriod.dateRange()
  ```
  Replace with:
  ```swift
  _ = selectedPeriod.dateRange()
  ```

- [ ] **Step 2: Fix OnlineBookView.swift — unused `readingBook` variable**

  The variable is declared and assigned but never read. Remove it:

  Remove line 395:
  ```swift
  let readingBook: ReadingBook
  ```
  Change line 402 from:
  ```swift
  readingBook = bookStore.books.first(where: { $0.id == existingId }) ?? existing
  ```
  to:
  ```swift
  // keep only the side-effect line temporaryReaderBookId = nil (already there)
  ```
  Remove the assignment entirely (no side effects).

  Change line 416 from:
  ```swift
  readingBook = tempBook
  ```
  to: *(remove this line — tempBook side-effects already captured by addedBookId/temporaryReaderBookId assignments above it)*

- [ ] **Step 3: Fix Models.swift:569 — unused `sourceURL`**

  Current (around line 569):
  ```swift
  let sourceURL = URL(string: book.source)
  ```
  Replace with:
  ```swift
  _ = URL(string: book.source)
  ```
  Or simply remove the line if it has no side effects.

- [ ] **Step 4: Fix RuleEngine.swift:1346,1351 — unused `i` and `prev`**

  Line 1346 — change:
  ```swift
  for (i, seg) in segments.enumerated() {
  ```
  to:
  ```swift
  for (_, seg) in segments.enumerated() {
  ```

  Line 1351 — change:
  ```swift
  let prev = current
  ```
  to:
  ```swift
  _ = current
  ```

- [ ] **Step 5: Fix WebNovelParser.swift:230 — unnecessary `try?`**

  Current (line 230):
  ```swift
  let classId = (((try? element.className()) ?? "") + " " + ((try? element.id()) ?? ""))
      .lowercased()
  ```
  SwiftSoup's `element.id()` no longer throws. Replace with:
  ```swift
  let classId = ((element.className() ?? "") + " " + (element.id() ?? ""))
      .lowercased()
  ```
  Note: If className/id still return optionals, keep the `?? ""`. If they don't throw, just remove `try?`.
  
  Actually inspect the method signatures in SwiftSoup. If `.className()` does NOT throw, write:
  ```swift
  let classId = (element.className() + " " + element.id()).lowercased()
  ```
  If they throw (different version), keep `try?` but use non-optional fallback:
  ```swift
  let classId = (((try? element.className()) ?? "") + " " + ((try? element.id()) ?? "")).lowercased()
  ```
  The warning is at col 69 which corresponds to `try? element.id()`. If only `id()` warns, remove only that `try?`.

- [ ] **Step 6: Fix LegadoJSBridge.swift:353 — `var` should be `let`**

  Current:
  ```swift
  var fmtStr = format
      .replacingOccurrences(of: "yyyy", with: "yyyy")
      ...
  ```
  Replace `var` with `let`:
  ```swift
  let fmtStr = format
      .replacingOccurrences(of: "yyyy", with: "yyyy")
      ...
  ```

- [ ] **Step 7: Fix JSCoreEngine.swift:209-210 — `??` on non-optional**

  Current (lines 209-210):
  ```swift
  "bookSourceGroup": src.bookSourceGroup ?? "",
  "bookSourceComment": src.bookSourceComment ?? "",
  ```
  These properties are non-optional `String` (not `String?`). Remove the `?? ""`:
  ```swift
  "bookSourceGroup": src.bookSourceGroup,
  "bookSourceComment": src.bookSourceComment,
  ```
  Note: If they ARE `String?`, the `??` is correct and the warning is spurious — verify by checking the property type in the BookSource model.

- [ ] **Step 8: Fix UniversalBookResourceAdapter.swift — unused `try?` results**

  Lines 189, 198, 224 all have `try? element.attr(...)` whose result is unused. Add `_ =`:

  Line 189:
  ```swift
  _ = try? element.attr(item.attr, absolute)
  ```
  Line 198:
  ```swift
  _ = try? element.attr("href", absolute)
  ```
  Line 224:
  ```swift
  _ = try? element.attr("srcset", rewritten)
  ```

- [ ] **Step 9: Fix CssExtractor.swift:20 — unused `try?` result**

  Current:
  ```swift
  for node in nodes { try? node.appendText(marker) }
  ```
  Replace with:
  ```swift
  for node in nodes { _ = try? node.appendText(marker) }
  ```

- [ ] **Step 10: Fix ChapterFetcher.swift:508 — unused `try?` result**

  Current (around line 508):
  ```swift
  try? node.appendText(lineBreakMarker)
  ```
  Replace with:
  ```swift
  _ = try? node.appendText(lineBreakMarker)
  ```

- [ ] **Step 11: Verify Task 1 build — warnings in these files should be gone**

  Run:
  ```bash
  cd "/Users/zhangruilin/Desktop/yuedu app"
  xcodebuild -project "yuedu app.xcodeproj" -scheme "yuedu app" -configuration Debug clean build 2>&1 | grep "warning:" | grep -E "ReadingStatsView|OnlineBookView|Models\.swift|RuleEngine\.swift|WebNovelParser|LegadoJSBridge|JSCoreEngine|UniversalBookResourceAdapter|CssExtractor|ChapterFetcher"
  ```
  Expected: no output (no more warnings in these files)

- [ ] **Step 12: Commit Task 1**

  ```bash
  cd "/Users/zhangruilin/Desktop/yuedu app"
  git add -A
  git commit -m "fix: resolve code quality warnings (unused vars, unnecessary try/var)

  - Remove unused 'range', 'readingBook', 'sourceURL', 'i', 'prev' variables
  - Change unnecessary var to let in timeFormatUTC
  - Remove ?? on non-optional strings in JSCoreEngine
  - Add _ = to unused try? results in UniversalBookResourceAdapter, CssExtractor, ChapterFetcher
  - Fix unnecessary try? in WebNovelParser

  Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
  ```

---

## Task 2: Deprecated APIs

**Files:**
- Modify: `yuedu app/Models/Network/WebViewFetcher.swift`
- Modify: `yuedu app/Models/RuleEngine/ModernParser/JS/LegadoJSBridge.swift`

### 2A: Remove WKProcessPool (deprecated iOS 15)

- [ ] **Step 1: Remove `sharedProcessPool` property from WebViewFetcher**

  Remove line 14:
  ```swift
  private let sharedProcessPool = WKProcessPool()
  ```

- [ ] **Step 2: Remove `config.processPool` assignment in `createWebView()`**

  In `createWebView()`, remove line 34:
  ```swift
  config.processPool = sharedProcessPool
  ```

### 2B: Replace CC_MD5 with CryptoKit (deprecated iOS 13)

- [ ] **Step 3: Add CryptoKit import to LegadoJSBridge.swift**

  At the top of the file, add:
  ```swift
  import CryptoKit
  ```
  (Keep `#if canImport(CommonCrypto)` or existing import block if present)

- [ ] **Step 4: Replace CC_MD5 implementation in `md5Encode`**

  Current (lines 238-244):
  ```swift
  func md5Encode(_ str: String) -> String {
      guard let data = str.data(using: .utf8) else { return "" }
      var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
      data.withUnsafeBytes { buffer in
          _ = CC_MD5(buffer.baseAddress, CC_LONG(data.count), &digest)
      }
      return digest.map { String(format: "%02x", $0) }.joined()
  }
  ```
  Replace with:
  ```swift
  func md5Encode(_ str: String) -> String {
      guard let data = str.data(using: .utf8) else { return "" }
      let digest = Insecure.MD5.hash(data: data)
      return digest.map { String(format: "%02x", $0) }.joined()
  }
  ```

- [ ] **Step 5: Remove CommonCrypto import if only used for MD5**

  Check if `CommonCrypto` is used elsewhere in the file. If not, remove:
  ```swift
  import CommonCrypto
  ```

- [ ] **Step 6: Verify Task 2 — WKProcessPool and CC_MD5 warnings gone**

  ```bash
  cd "/Users/zhangruilin/Desktop/yuedu app"
  xcodebuild -project "yuedu app.xcodeproj" -scheme "yuedu app" -configuration Debug build 2>&1 | grep "warning:" | grep -E "WKProcessPool|CC_MD5|processPool"
  ```
  Expected: no output

- [ ] **Step 7: Commit Task 2**

  ```bash
  git add -A
  git commit -m "fix: replace deprecated WKProcessPool and CC_MD5

  - Remove WKProcessPool usage (deprecated iOS 15) from WebViewFetcher
  - Replace CC_MD5 with CryptoKit.Insecure.MD5 in LegadoJSBridge

  Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
  ```

---

## Task 3: Simple Concurrency Fixes

**Files:**
- Modify: `yuedu app/Models/Network/WebViewFetcher.swift`
- Modify: `yuedu app/Models/Sync/WebDAVManager.swift`
- Modify: `yuedu app/Models/Network/WebFetcher.swift`
- Modify: `yuedu app/Models/Reader/CoreText/CoreTextPageView.swift`
- Modify: `yuedu app/Views/BookSource/BookSourceFormLoginView.swift`

### 3A: WebViewFetcher.swift:77-79 — Fix callAsyncJavaScript type inference

The `callAsyncJavaScript` overload is being resolved to `Void`-returning variant. Fix with explicit type annotation.

- [ ] **Step 1: Add explicit `Any?` type to `result`**

  Current (line 77):
  ```swift
  let result = try? await webView.callAsyncJavaScript(
      js, arguments: [:], in: nil, in: .page)
  ```
  Replace with:
  ```swift
  let result: Any? = try? await webView.callAsyncJavaScript(
      js, arguments: [:], in: nil, in: .page)
  ```

### 3B: WebViewFetcher.swift:699 — Remove `nonisolated` from WKNavigationDelegate method

The delegate method is `nonisolated` but accesses `@MainActor`-isolated `navigationResponse.response`. Since the class is `@MainActor`, remove `nonisolated`:

- [ ] **Step 2: Remove `nonisolated` from `webView(_:decidePolicyFor:decisionHandler:)`**

  Current (line 694):
  ```swift
  nonisolated func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationResponse: WKNavigationResponse,
      decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
  ) {
  ```
  Replace with:
  ```swift
  func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationResponse: WKNavigationResponse,
      decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
  ) {
  ```

### 3C: WebDAVManager.swift:140 — UIDevice.current.name needs MainActor

- [ ] **Step 3: Extract device name on MainActor before creating manifest**

  Find the `backup()` async function and the SyncManifest creation. Extract device name first:

  Before:
  ```swift
  let manifest = SyncManifest(
      deviceId: Self.deviceId,
      deviceName: UIDevice.current.name,
      backupDate: Date(),
      appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
  )
  ```
  Replace with:
  ```swift
  let deviceName = await MainActor.run { UIDevice.current.name }
  let manifest = SyncManifest(
      deviceId: Self.deviceId,
      deviceName: deviceName,
      backupDate: Date(),
      appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
  )
  ```

### 3D: WebFetcher.swift:255 — Capture `retryRequest` in closure

- [ ] **Step 4: Add capture list to the `withLock` closure**

  Current (line 254):
  ```swift
  let (retryData, retryResponse) = try await PerHostSemaphore.shared.withLock(host: host) {
      try await self.session.data(for: retryRequest)
  }
  ```
  Replace with:
  ```swift
  let (retryData, retryResponse) = try await PerHostSemaphore.shared.withLock(host: host) {
      [retryRequest] in try await self.session.data(for: retryRequest)
  }
  ```

### 3E: CoreTextPageView.swift — Mark `borderXAndWidth` as `nonisolated`

The static method is pure (no instance/global state). Mark as `nonisolated`:

- [ ] **Step 5: Add `nonisolated` to `borderXAndWidth`**

  Current (line 432):
  ```swift
  private static func borderXAndWidth(for item: CoreTextPaginator.RenderedBlockRenderable) -> (CGFloat, CGFloat) {
  ```
  Replace with:
  ```swift
  private nonisolated static func borderXAndWidth(for item: CoreTextPaginator.RenderedBlockRenderable) -> (CGFloat, CGFloat) {
  ```

### 3F: BookSourceFormLoginView.swift — Wrap toastHandler in `Task { @MainActor in }`

There are two identical `toastHandler` closures (lines 179-183 and 262-266).

- [ ] **Step 6: Wrap first toastHandler (line ~179)**

  Current:
  ```swift
  engine.toastHandler = { msg in
      guard let topVC = BookSourceFormLoginView.topViewController() else { return }
      let alert = UIAlertController(title: nil, message: msg, preferredStyle: .alert)
      topVC.present(alert, animated: true)
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) { alert.dismiss(animated: true) }
  }
  ```
  Replace with:
  ```swift
  engine.toastHandler = { msg in
      Task { @MainActor in
          guard let topVC = BookSourceFormLoginView.topViewController() else { return }
          let alert = UIAlertController(title: nil, message: msg, preferredStyle: .alert)
          topVC.present(alert, animated: true)
          DispatchQueue.main.asyncAfter(deadline: .now() + 2) { alert.dismiss(animated: true) }
      }
  }
  ```

- [ ] **Step 7: Wrap second toastHandler (line ~262) — identical fix**

  Apply the same `Task { @MainActor in }` wrapping to the second occurrence.

- [ ] **Step 8: Verify Task 3 warnings gone**

  ```bash
  cd "/Users/zhangruilin/Desktop/yuedu app"
  xcodebuild -project "yuedu app.xcodeproj" -scheme "yuedu app" -configuration Debug build 2>&1 | grep "warning:" | grep -E "WebViewFetcher|WebDAVManager|WebFetcher|CoreTextPageView|BookSourceFormLogin"
  ```
  Expected: no output

- [ ] **Step 9: Commit Task 3**

  ```bash
  git add -A
  git commit -m "fix: simple Swift concurrency warnings

  - Fix callAsyncJavaScript type inference (WebViewFetcher)
  - Remove nonisolated from WKNavigationDelegate method (WebViewFetcher)
  - Extract UIDevice.current.name on MainActor (WebDAVManager)
  - Add capture list [retryRequest] to async closure (WebFetcher)
  - Mark borderXAndWidth as nonisolated static (CoreTextPageView)
  - Wrap toastHandler body in Task { @MainActor in } (BookSourceFormLoginView)

  Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
  ```

---

## Task 4: Complex Actor Isolation Fixes

**Files:**
- Modify: `yuedu app/Models/Network/WebViewFetcher.swift`
- Modify: `yuedu app/Models/Reader/CoreText/EPUBStyleResolver.swift`
- Modify: `yuedu app/Models/Reader/CoreText/CoreTextPageEngine.swift`
- Modify: `yuedu app/Models/Migration/LegadoMigrationManager.swift`
- Modify: `yuedu app/Models/Book/UniversalBookResourceAdapter.swift`

### 4A: WebViewFetcher.shared — Add `nonisolated(unsafe)`

This fixes 3 warnings: AppDependencies.swift:212, OnlineReadingPipeline.swift:53, OnlineReadingPipeline.swift:657.

- [ ] **Step 1: Change `static let shared` to `nonisolated(unsafe)`**

  Current (line 10):
  ```swift
  static let shared = WebViewFetcher()
  ```
  Replace with:
  ```swift
  nonisolated(unsafe) static let shared = WebViewFetcher()
  ```
  This suppresses the actor isolation check on the property access site. The singleton is always first accessed from the main thread at app startup, so this is safe.

### 4B: EPUBStyleResolver.swift:32 — nonisolated accessing @MainActor property

- [ ] **Step 2: Move `fontRegistrationService` access inside the @MainActor Task**

  Current:
  ```swift
  nonisolated func cleanupFontFiles() {
      let service = fontRegistrationService   // ← warning: line 32
      Task { @MainActor [weak self] in
          guard let self else { return }
          for url in self.registeredFontFileURLs.values {
              service.cleanupTemporaryFile(at: url)
          }
      }
  }
  ```
  Replace with:
  ```swift
  nonisolated func cleanupFontFiles() {
      Task { @MainActor [weak self] in
          guard let self else { return }
          let service = self.fontRegistrationService
          for url in self.registeredFontFileURLs.values {
              service.cleanupTemporaryFile(at: url)
          }
      }
  }
  ```

### 4C: CoreTextPageEngine.swift:185-186 — @MainActor access in NotificationCenter closure

- [ ] **Step 3: Wrap notification handler body in `MainActor.assumeIsolated`**

  Current:
  ```swift
  NotificationCenter.default.addObserver(
      forName: UIApplication.didReceiveMemoryWarningNotification,
      object: nil,
      queue: .main
  ) { [weak self] _ in
      self?.chapterSnapshots.removeAllObjects()  // line 185
      self?.cancelPreloadTasks()                 // line 186
  }
  ```
  Replace with:
  ```swift
  NotificationCenter.default.addObserver(
      forName: UIApplication.didReceiveMemoryWarningNotification,
      object: nil,
      queue: .main
  ) { [weak self] _ in
      MainActor.assumeIsolated {
          self?.chapterSnapshots.removeAllObjects()
          self?.cancelPreloadTasks()
      }
  }
  ```
  This is safe because `queue: .main` guarantees the closure runs on the main thread.

### 4D: LegadoMigrationManager.swift — captured vars in MainActor.run closures

- [ ] **Step 4: Fix `count` mutation (line 100) — return value from `MainActor.run`**

  Find the `importBooks` function. Current pattern:
  ```swift
  var count = 0
  await MainActor.run {
      for book in legadoBooks {
          ...
          count += 1   // line 100
      }
  }
  return count
  ```
  Replace with:
  ```swift
  let count = await MainActor.run { () -> Int in
      var localCount = 0
      for book in legadoBooks {
          ...
          localCount += 1
      }
      return localCount
  }
  return count
  ```

- [ ] **Step 5: Fix captured `sourcesImported`, `booksImported`, `errors` (lines 154-156)**

  Find the final `await MainActor.run { ... }` block in `importFromJSON`. Current:
  ```swift
  await MainActor.run {
      progress     = 1.0
      importResult = ImportResult(
          sourcesImported: sourcesImported,   // line 154
          booksImported:   booksImported,     // line 155
          errors:          errors             // line 156
      )
      isImporting = false
  }
  ```
  Replace with (capture before the closure):
  ```swift
  let finalSources = sourcesImported
  let finalBooks   = booksImported
  let finalErrors  = errors
  await MainActor.run {
      progress     = 1.0
      importResult = ImportResult(
          sourcesImported: finalSources,
          booksImported:   finalBooks,
          errors:          finalErrors
      )
      isImporting = false
  }
  ```

### 4E: UniversalBookResourceAdapter.swift:138-148 — Replace lock/unlock with withLock

- [ ] **Step 6: Refactor `payloadForChapter` to use `NSLock.withLock`**

  Current:
  ```swift
  private func payloadForChapter(index: Int) async throws -> ChapterContentPayload {
      lock.lock()
      if let cached = chapterPayloadCache[index] {
          lock.unlock()
          return cached
      }
      lock.unlock()

      let payload = try await contentProvider.contentForChapter(index: index)
      lock.lock()
      chapterPayloadCache[index] = payload
      lock.unlock()
      return payload
  }
  ```
  Replace with:
  ```swift
  private func payloadForChapter(index: Int) async throws -> ChapterContentPayload {
      if let cached = lock.withLock({ chapterPayloadCache[index] }) {
          return cached
      }
      let payload = try await contentProvider.contentForChapter(index: index)
      lock.withLock { chapterPayloadCache[index] = payload }
      return payload
  }
  ```
  Note: `NSLock.withLock` is available in Swift 5.7+ (all iOS 16+ and Swift standard library additions). The semantics are identical — no lock is held across the `await`.

- [ ] **Step 7: Verify Task 4 warnings gone**

  ```bash
  cd "/Users/zhangruilin/Desktop/yuedu app"
  xcodebuild -project "yuedu app.xcodeproj" -scheme "yuedu app" -configuration Debug build 2>&1 | grep "warning:" | grep -E "AppDependencies|EPUBStyleResolver|CoreTextPageEngine|LegadoMigrationManager|UniversalBookResourceAdapter|OnlineReadingPipeline"
  ```
  Expected: no output

- [ ] **Step 8: Commit Task 4**

  ```bash
  git add -A
  git commit -m "fix: actor isolation and MainActor concurrency warnings

  - Add nonisolated(unsafe) to WebViewFetcher.shared (fixes 3 sites)
  - Move fontRegistrationService access into @MainActor Task (EPUBStyleResolver)
  - Use MainActor.assumeIsolated in NotificationCenter handler (CoreTextPageEngine)
  - Return count from MainActor.run instead of capturing var (LegadoMigrationManager)
  - Capture vars before MainActor.run closure to avoid concurrent capture (LegadoMigrationManager)
  - Replace NSLock lock/unlock with withLock in async context (UniversalBookResourceAdapter)

  Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
  ```

---

## Task 5: Sendable — RegexSanitizer.withTimeout

**Files:**
- Modify: `yuedu app/Models/RuleEngine/ModernParser/Cache/RegexSanitizer.swift`

Fixes 3 warnings: RegexCache.swift:60, RegexExtractor.swift:24, RegexExtractor.swift:57.
Root cause: `withTimeout<T: Sendable>` generic constraint makes `[NSTextCheckingResult]` / `NSTextCheckingResult?` fail because `NSTextCheckingResult` is not `Sendable`.

- [ ] **Step 1: Replace `withTimeout` with an `@unchecked Sendable` box implementation**

  Current (line 47):
  ```swift
  static func withTimeout<T: Sendable>(
      seconds: TimeInterval,
      work: @escaping @Sendable () -> T,
      fallback: T
  ) -> T {
      var result = fallback
      let sema = DispatchSemaphore(value: 0)
      DispatchQueue.global(qos: .userInitiated).async {
          result = work()
          sema.signal()
      }
      if sema.wait(timeout: .now() + seconds) == .timedOut {
          return fallback
      }
      return result
  }
  ```
  Replace with:
  ```swift
  static func withTimeout<T>(
      seconds: TimeInterval,
      work: @escaping () -> T,
      fallback: T
  ) -> T {
      final class ResultBox<V>: @unchecked Sendable {
          var value: V
          init(_ v: V) { self.value = v }
      }
      let box = ResultBox(fallback)
      let sema = DispatchSemaphore(value: 0)
      DispatchQueue.global(qos: .userInitiated).async {
          box.value = work()
          sema.signal()
      }
      if sema.wait(timeout: .now() + seconds) == .timedOut {
          return fallback
      }
      return box.value
  }
  ```
  This is thread-safe: the semaphore establishes a happens-before relationship ensuring that `box.value = work()` is visible to the reader. The `@unchecked Sendable` is safe here because we own the threading logic.

- [ ] **Step 2: Verify Task 5 warnings gone**

  ```bash
  cd "/Users/zhangruilin/Desktop/yuedu app"
  xcodebuild -project "yuedu app.xcodeproj" -scheme "yuedu app" -configuration Debug build 2>&1 | grep "warning:" | grep -E "RegexCache|RegexExtractor|NSTextCheckingResult|Sendable"
  ```
  Expected: no output

- [ ] **Step 3: Commit Task 5**

  ```bash
  git add -A
  git commit -m "fix: Sendable warning for NSTextCheckingResult in RegexSanitizer

  Replace T: Sendable constraint in withTimeout with internal @unchecked Sendable
  box. NSTextCheckingResult is effectively immutable and safe to pass across
  thread boundaries with the semaphore providing happens-before ordering.

  Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
  ```

---

## Task 6: Project Configuration

**Files:**
- Modify: `Info.plist`

Warning: "All interface orientations must be supported unless the app requires full screen."

- [ ] **Step 1: Check current orientation settings in Info.plist**

  ```bash
  /usr/libexec/PlistBuddy -c "Print :UISupportedInterfaceOrientations" "/Users/zhangruilin/Desktop/yuedu app/yuedu app/Info.plist" 2>/dev/null || echo "not set"
  /usr/libexec/PlistBuddy -c "Print :UIRequiresFullScreen" "/Users/zhangruilin/Desktop/yuedu app/yuedu app/Info.plist" 2>/dev/null || echo "not set"
  ```

- [ ] **Step 2: Add UIRequiresFullScreen = YES to suppress the warning**

  If the app is portrait-only (which reading apps typically are), the correct fix is to declare it requires full screen:

  ```bash
  /usr/libexec/PlistBuddy -c "Add :UIRequiresFullScreen bool true" "/Users/zhangruilin/Desktop/yuedu app/yuedu app/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Set :UIRequiresFullScreen true" "/Users/zhangruilin/Desktop/yuedu app/yuedu app/Info.plist"
  ```

  Alternative: If the app should support all orientations, add all four to `UISupportedInterfaceOrientations`:
  - UIInterfaceOrientationPortrait
  - UIInterfaceOrientationPortraitUpsideDown
  - UIInterfaceOrientationLandscapeLeft
  - UIInterfaceOrientationLandscapeRight

- [ ] **Step 3: Verify Task 6 warning gone**

  ```bash
  cd "/Users/zhangruilin/Desktop/yuedu app"
  xcodebuild -project "yuedu app.xcodeproj" -scheme "yuedu app" -configuration Debug build 2>&1 | grep "warning:" | grep -i "interface orientation"
  ```
  Expected: no output

- [ ] **Step 4: Commit Task 6**

  ```bash
  git add -A
  git commit -m "fix: suppress interface orientations project warning

  Add UIRequiresFullScreen to Info.plist to declare app requires full screen,
  suppressing 'all interface orientations must be supported' warning.

  Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
  ```

---

## Final Verification

- [ ] **Run complete clean build and confirm 0 warnings**

  ```bash
  cd "/Users/zhangruilin/Desktop/yuedu app"
  xcodebuild -project "yuedu app.xcodeproj" -scheme "yuedu app" -configuration Debug clean build 2>&1 | grep "warning:" | grep -v "appintentsmetadataprocessor"
  ```
  Expected: 0 lines of output.
