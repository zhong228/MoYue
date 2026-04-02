# yuedu app Architecture Notes

## Overview
- App entry is [`/Users/zhangruilin/Desktop/yuedu app/yuedu app/yuedu_appApp.swift`](/Users/zhangruilin/Desktop/yuedu%20app/yuedu%20app/yuedu_appApp.swift).
- Main app state is centered on `BookStore`.
- The project currently mixes:
  - local reading
  - online book/source parsing
  - EPUB/TXT/HTML reading
  - CoreText rendering
  - Web renderer fallback paths

## Main Reading Flow
- The main reading view is [`/Users/zhangruilin/Desktop/yuedu app/yuedu app/Views/ReaderView.swift`](/Users/zhangruilin/Desktop/yuedu%20app/yuedu%20app/Views/ReaderView.swift).
- `ReaderView` currently owns too much responsibility:
  - reading mode selection
  - page state
  - chapter navigation
  - EPUB renderer state
  - CoreText engine state
  - theme, font size, margins
  - TTS / auto read
  - brightness and footer state
- This is the highest-risk file for future regressions.

## EPUB/CoreText Pipeline
- EPUB resource/session layer is [`/Users/zhangruilin/Desktop/yuedu app/yuedu app/Models/PublicationSession.swift`](/Users/zhangruilin/Desktop/yuedu%20app/yuedu%20app/Models/PublicationSession.swift).
- CoreText rendering path is mainly:
  - [`/Users/zhangruilin/Desktop/yuedu app/yuedu app/Models/CoreText/CoreTextPageEngine.swift`](/Users/zhangruilin/Desktop/yuedu%20app/yuedu%20app/Models/CoreText/CoreTextPageEngine.swift)
  - [`/Users/zhangruilin/Desktop/yuedu app/yuedu app/Models/CoreText/HTMLAttributedStringBuilder.swift`](/Users/zhangruilin/Desktop/yuedu%20app/yuedu%20app/Models/CoreText/HTMLAttributedStringBuilder.swift)
  - [`/Users/zhangruilin/Desktop/yuedu app/yuedu app/Models/CoreText/CoreTextPaginator.swift`](/Users/zhangruilin/Desktop/yuedu%20app/yuedu%20app/Models/CoreText/CoreTextPaginator.swift)
  - [`/Users/zhangruilin/Desktop/yuedu app/yuedu app/Models/CoreText/CoreTextPageView.swift`](/Users/zhangruilin/Desktop/yuedu%20app/yuedu%20app/Models/CoreText/CoreTextPageView.swift)

### Current mental model
- Readium is used as the container/resource layer.
- The intended rendering path is:
  - EPUB resource bytes
  - HTML/CSS ingestion
  - attributed string building
  - CoreText pagination
  - page drawing
- The biggest instability is not Readium itself.
- The biggest instability is the HTML/CSS to attributed-string layer.

## What Is Known To Work
- EPUB embedded font registration has been wired into the CoreText path.
- Publication resource access and deobfuscation are handled in `PublicationSession`.
- Basic page pagination and snapshot generation exist in the CoreText engine.
- Image-page style handling exists as a separate concept from normal text pages.

## What Is Still Fragile
- `HTMLAttributedStringBuilder` is the main regression hotspot.
- Paragraph breaking semantics are easy to break.
- CSS-to-geometry mapping is incomplete and dangerous if changed casually.
- `ReaderView` combines too many code paths and makes regressions harder to isolate.

## Practical Rules For Future Changes
- Treat `PublicationSession` as resource/container infrastructure, not a rendering layer.
- Treat `HTMLAttributedStringBuilder` as the most sensitive part of EPUB layout.
- Avoid mixing block layout, line-break semantics, and box geometry changes in one patch.
- When EPUB layout breaks, inspect the builder first before blaming Readium or CoreText.
- Verify changes with build output before claiming a fix.

## Current Repo State Notes
- There is an existing uncommitted modification in:
  - [`/Users/zhangruilin/Desktop/yuedu app/yuedu app/Models/CoreText/CoreTextPageView.swift`](/Users/zhangruilin/Desktop/yuedu%20app/yuedu%20app/Models/CoreText/CoreTextPageView.swift)
- A recent commit exists:
  - `9bcd158` `Refine CoreText EPUB rendering pipeline`

## Recommended Next Refactor Targets
1. Split `ReaderView` responsibilities.
2. Stabilize `HTMLAttributedStringBuilder` with smaller, testable layout rules.
3. Keep `PublicationSession` focused on resource lookup, href normalization, and transformed bytes.
4. Keep pagination and drawing concerns inside the CoreText modules only.
