# iOS 17 Detail-to-Reader Navigation Hang

## Reproduction

On iOS 17.5, push an online book from Explore or Search, then choose Read Now.
The reader stops responding during entry. The production report described a
loading indicator followed by termination; the simulator could finish painting
the first page before its main thread became stuck.

The same deterministic source and navigation tests passed on iOS 27. On iOS 17,
repeated process samples showed approximately 100% CPU and a main-thread loop
through UIKit layout, SwiftUI, AttributeGraph, and `ReaderView.body`.

Temporary SwiftUI body-change logging identified the repeating dependency:

```
OnlineBookView: _dismiss changed.
BookReaderView: _dismiss changed.
ReaderView: @self changed.
```

## Fix

In this navigation hierarchy, iOS 17 repeatedly invalidates the `DismissAction`
environment value in both outer views. Those invalidations rebuild the reader
and feed back into navigation layout. Both views now use the presentation-mode
binding already used by `ReaderView`, including when performing their close
actions. The same iOS 17 tests then complete normally.

Keep the native push, hidden reader navigation bar, and reserved back-swipe
region. Do not restore `@Environment(\.dismiss)` in these two views without
running the actual iOS 17 entry tests. Delaying navigation or retrying chapter
loading does not address this dependency cycle.

`FixedPageReaderView` (manga, PDF, fixed-layout EPUB) is the format reader
below `BookReaderView` for those books and follows the same two rules as
`ReaderView`: it reads `presentationMode`, never `@Environment(\.dismiss)`, and
it lets `ReaderNavigationContainer` decide whether it needs a NavigationStack of
its own. A missing `readerNavigator` does not mean modal: a detail-origin reader
is pushed onto the detail's stack with `readerUsesParentNavigationStack`. When
the fixed-page reader moved its controls into the native toolbar it wrapped
itself in a NavigationStack whenever it had no navigator, nesting a second
stack inside that destination, and manga stopped opening from a book detail
(reported 2026-09-28). `DetailReaderStackTests` pins both the pushed and the
modal case; the two manga methods under Regression open a real manga from a
detail.

This is separate from the synchronous publication during bookshelf probe
teardown, addressed by owner-scoped deferred navigation detachment.
The iOS 17 coordinator regression also exposed that UIKit can release an
externally removed reader before reconciliation. An idle, cleared weak
controller reference must release the session too; a staged push remains guarded.

## Regression

Prepare and serve `scripts/navigation_swipe_fixture.py` for the installed app.
Run these methods with `scripts/xctest.sh` on iOS 17:

- `DetailReaderBackSwipeUITests.testDetailReaderLoadsAndReturns`
- `DetailReaderBackSwipeUITests.testSearchDetailReaderLoadsAndReturns`
- `DetailReaderBackSwipeUITests.testDetailMangaReaderLoadsAndReturns`
- `DetailReaderBackSwipeUITests.testSearchDetailMangaReaderLoadsAndReturns`

Each enters through the production UI and repeats entry. The text book requires
actual chapter text and swipes back to the same detail. The manga, from the same
fixture's image source, requires a page image on screen with the controls away,
raises them for the fixed-page reader's `Page 1 / 3`, and returns with the
reader's Back button. The tests use the repository's local StoreKit
configuration to avoid Apple ID dialogs on a new simulator.
