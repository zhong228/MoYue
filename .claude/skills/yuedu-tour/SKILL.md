---
name: yuedu-tour
description: yuedu iOS EPUB/TXT/web-novel reader codebase orientation. Use before touching reader rendering, CoreText, bookshelf, online reading, book sources, TTS, or localization.
---

# yuedu App Code Tour

## Area Map

| Area | Folders |
|------|---------|
| Reading rendering, layout, paging, scroll | `Models/Reader/CoreText/`, `Views/Reader/` |
| Bookshelf, book CRUD, grouping | `Models/Book/`, `Views/Bookshelf/` |
| Book sources, online reading, rule engine | `Models/BookSource/`, `Models/Online/`, `Models/RuleEngine/` |
| Global settings, theme, DI | `Models/App/` |
| TTS | `Models/TTS/`, `Views/TTS/` |
| RSS, comics | `Models/RSS/`, `Models/Comic/` |

## Entry Points

| Need | File |
|------|------|
| App launch, DI | `yuedu_appApp.swift` |
| Bookshelf | `Views/Bookshelf/HomeView.swift` |
| Book model, bookmarks | `Models/Book/Models.swift` |
| Book store | `Models/Book/BookStore.swift` |
| Reader | `Views/Reader/ReaderView.swift` |
| Paged CoreText layout | `Models/Reader/CoreText/CoreTextPaginator.swift` |
| Scroll engine | `Models/Reader/CoreText/CoreTextScrollEngine.swift` |
| Chunk slicing | `Models/Reader/CoreText/CoreTextChunkSlicer.swift` |
| Chunk rendering | `Views/Reader/CoreTextChunkCell.swift` |
| Page rendering | `Models/Reader/CoreText/CoreTextPageView.swift` |
| EPUB → attributed string | `Models/Reader/CoreText/EPUBAttributedStringBuilder.swift` |
| HTML → attributed string | `Models/Reader/CoreText/HTMLAttributedStringBuilder.swift` |
| EPUB CSS resolver | `Models/Reader/CoreText/EPUBStyleResolver.swift` |
| EPUB page renderer | `Models/Reader/EPUBPageRenderer.swift` |
| Settings | `Models/App/GlobalSettings.swift` |

## Search

```bash
ROOT="/Users/zhangruilin/Desktop/Yuedu-reader/iOS"
rg -n "YourSymbol" "$ROOT" -g '*.swift'
rg -n '"key"' "$ROOT"/*/zh-Hant.lproj/Localizable.strings
```

## Two Rendering Pipelines

| Path | Builder | Use case |
|------|---------|----------|
| Legacy | `HTMLAttributedStringBuilder.build()` | Paged engine preload (resourceProvider path) |
| RenderableNode | `HTMLAttributedStringBuilder.buildStyledAST()` → `NodeAttributedStringRenderer` | EPUB builder path |

Both share CSS parser, style resolver, CSS property appliers, and `ResolvedStyle`.

## Paged vs Scroll Engines

| Mode | Engine | View |
|------|--------|------|
| Paged | `CoreTextPageEngine` | `UIPageViewController` → `CoreTextPageView` |
| Scroll | `CoreTextScrollEngine` | `UICollectionView` → `CoreTextChunkCollectionCell` |

Both built from same `AttributedStringBuilding` in `EPUBPageRenderer.load()`.

## CoreText Pitfalls

- **Margin chain**: `ReaderConfig` → `ReaderRenderSettings.contentInsets` → `ChapterLayout` → `CoreTextPageView.draw()`. Don't bypass.
- **Position identity**: Use `(spineIndex, charOffset)`, never `globalPage` as stable identity.
- **`CTFrameGetLineOrigins`**: returns coords relative to path rect, not absolute.
- **`CTLineGetStringIndexForPosition`**: returns nearest char even far outside text bounds. Guard with typographic-width check.
- **Vertical mode**: `ascent`/`descent` = X-axis values, not Y. `paragraphSpacingBefore`/`firstLineHeadIndent` have no inline-direction effect in vertical-rl.
- **Inline images**: `CTFrameDraw` reserves space via CTRunDelegate; must draw images separately via `CoreTextChunkAttachmentExtractor`.
- **Image-only pages**: EPUB covers use `result.imagePage`, not attributed-string CTRunDelegate. Scroll must handle with `isImageOnly` chunk.
- **`prepareAttributedString`**: vertical glyph normalization, font cascade, paragraph defaults. Must be called before pagination AND scroll slicing.
- **Vertical inline annotations**: extracted from CTFrame with `CTRunDelegate` + `inlineAnnotationRunAttribute`; drawn separately from main frame.
- **CJK justification**: `isCJKDominant()` per line; don't justify Latin text without hyphenation.
- **Forbidden CJK punctuation**: use `CJKTypographyProcessor.protectedLineBreakOffset` for page/chunk breaks.

## Writing Mode

- `ReaderWritingMode.verticalRTL` flows through `ReaderRenderSettings` → `PaginationRequest` → `CoreTextPaginator` → `ChapterLayout` → rendering.
- `isVerticalEPUB` detected from EPUB metadata (`session.epubWritingMode`) or CSS `writing-mode: vertical-rl`.
- Scroll axis: vertical EPUB → `.horizontalRTL`; horizontal EPUB → `.vertical`.

## Online Reading

- `bookSourceId != nil` → book-source book (rule engine); `nil` → browser-imported.
- `ChapterFetchManager` is an `actor`; generation tokens prevent stale results.
- For browser-imported HTML, preserve semantic blocks; only synthesize `<p>` for true plain-text fallback.
- Inline tags (`<a>`, `<strong>`, `<em>`, `<span>`) must stay inside parent paragraphs.

## Localization

All UI strings use `localized()`:
```swift
Text(localized("選取"))
```
Update all 3 files per key: `zh-Hant.lproj/`, `zh-Hans.lproj/`, `en.lproj/`.

## Extension Points

| Add | Use |
|-----|-----|
| New file format | `BookParser` + `BookParserRegistry` |
| New chapter source | `BookContentProvider` |
| New attributed-string source | `AttributedStringBuilding` |
| New CSS property | `HTMLCSSPropertyApplier` in `CSSPropertyApplier.swift` |
| New TTS engine | `TTSPlayable` |
| New global service | Define protocol → `AppDependencies` → `@Environment` |

## Build

```bash
cd "/Users/zhangruilin/Desktop/Yuedu-reader"
xcodebuild -project "Yuedu-Reader.xcodeproj" -scheme "Yuedu-Reader" \
  -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
```
