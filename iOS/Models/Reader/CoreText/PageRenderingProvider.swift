import UIKit

// MARK: - PageIndexProviding / CoreTextReadingPositionProviding

/// A UIViewController that tracks its position in the global page sequence.
@MainActor
protocol PageIndexProviding: AnyObject {
    var globalPageIndex: Int { get }
}

protocol CoreTextReadingPositionProviding: AnyObject {
    var coreTextReadingPosition: CoreTextReadingPosition? { get }
}

// MARK: - PageLayoutEngine (pure layout layer, no UIKit types beyond basic geometry)
//
/// Layout engine abstraction: responsible only for "receive data → compute layout → output geometry data",
/// without creating any UIView / UIViewController.
/// To support vertical scrolling, webtoon, or other layout modes in the future, simply implement this protocol;
/// the upper UI container decides how to consume the layouts.
@MainActor
protocol PageLayoutEngine: AnyObject {
    /// Total pages across all chapters
    var totalPages: Int { get }
    /// Current global page (0-based)
    var currentPage: Int { get }
    /// Layout results (spineIndex → ChapterLayout)
    var layouts: [Int: CoreTextPaginator.ChapterLayout] { get }
    /// Current viewport size
    var renderSize: CGSize { get }
    /// CharOffset persistence store
    var offsetStore: CharOffsetStore { get }

    /// Chapter + charOffset → global page index
    func pageIndex(forSpine spineIndex: Int, charOffset: Int) -> Int
    /// Stable position → global page index
    func pageIndex(for position: CoreTextReadingPosition) -> Int?
    /// Best available global page estimate for a position (may be inexact if offsets not built yet)
    func estimatedGlobalPage(for position: CoreTextReadingPosition) -> Int?
    /// Global page → stable position
    func readingPosition(forPage page: Int) -> CoreTextReadingPosition?
    /// Global page → (spineIndex, charOffset)
    func charOffset(forPage page: Int) -> (spineIndex: Int, charOffset: Int)
    /// Global page → (spineIndex, localPage)
    func localPosition(for globalPage: Int) -> (spineIndex: Int, localPage: Int)
    /// Global page index of the last page of the specified chapter
    func lastPageIndex(ofChapter spineIndex: Int) -> Int?
    /// Global page → plain text (for TTS / search)
    func plainText(forPage page: Int) -> String
    /// Overall reading progress (0…1)
    func totalProgress(forSpine spineIndex: Int, charOffset: Int) -> Double
    /// Progress → position
    func position(forProgress progress: Double) -> (spineIndex: Int, charOffset: Int)
    /// Internal link resolution within a chapter
    func resolveInternalLink(_ href: String, fromSpineIndex spineIndex: Int) async -> Int?

    // MARK: Engine lifecycle
    func start(renderSize: CGSize, bookId: String) async
    func preloadChapter(at spineIndex: Int) async
    func invalidateLayout(newSize: CGSize) async
    func warmUpNext(currentGlobalPage: Int)
    func cancelPendingWork()

    /// Notify the engine that the underlying data for a chapter has been updated (e.g. network fetch completed).
    /// The engine clears that chapter's layout and reloads it, without affecting other chapters.
    func notifyChapterDataChanged(at spineIndex: Int) async

    // MARK: Style updates
    func applyThemeChange(textColor: UIColor, backgroundColor: UIColor)
    func updateRenderSettings(_ settings: ReaderRenderSettings)
    func setTextAnnotations(_ annotations: [CoreTextTextAnnotation])

    // MARK: Callbacks (replaces Notification broadcasting)
    var onChapterReady: ((Int?) -> Void)? { get set }
    var onNavigateToPage: ((Int) -> Void)? { get set }
}

// MARK: - PageViewControllerVending (UIKit bridge layer)
//
/// ViewController factory protocol.
/// Responsibility: wrap the geometry data produced by PageLayoutEngine into UIViewControllers
/// for use by UIPageViewController data source.
/// Deliberately separate from PageLayoutEngine, so a future ScrollReaderBridge only needs to implement
/// PageLayoutEngine without concerning itself with ViewController construction details.
@MainActor
protocol PageViewControllerVending: AnyObject {
    /// Get ViewController for page at index
    func pageViewController(at index: Int) -> UIViewController
    /// Get ViewController by stable position
    func pageViewController(for position: CoreTextReadingPosition) -> UIViewController
    /// Get snapshot ViewController for cross-chapter animation
    func snapshotViewController(at index: Int) -> UIViewController?
    /// Offscreen render as UIImage (cover animation)
    func renderSnapshot(forPage globalPage: Int) -> UIImage?
}

// MARK: - PageRenderingProvider (Composite type alias)

/// The complete engine type that ReaderView depends on.
/// Equivalent to the union of "layout engine + ViewController factory".
/// If implementing a vertical scroll reader in the future, only PageLayoutEngine
/// needs to be implemented, without requiring PageViewControllerVending.
typealias PageRenderingProvider = PageLayoutEngine & PageViewControllerVending

// MARK: - PageLayoutEngine Default Implementations

extension PageLayoutEngine {
    func pageIndex(for position: CoreTextReadingPosition) -> Int? { nil }
    func readingPosition(forPage page: Int) -> CoreTextReadingPosition? { nil }
    func estimatedGlobalPage(for position: CoreTextReadingPosition) -> Int? { nil }
    func lastPageIndex(ofChapter spineIndex: Int) -> Int? { nil }
    func localPosition(for globalPage: Int) -> (spineIndex: Int, localPage: Int) { (0, globalPage) }
    func resolveInternalLink(_ href: String, fromSpineIndex spineIndex: Int) async -> Int? { nil }
    func position(forProgress progress: Double) -> (spineIndex: Int, charOffset: Int) { (0, 0) }
    var onChapterReady: ((Int?) -> Void)? {
        get { nil }
        set {}
    }
    var onNavigateToPage: ((Int) -> Void)? {
        get { nil }
        set {}
    }
    func cancelPendingWork() {}
    func notifyChapterDataChanged(at spineIndex: Int) async {}
    func updateRenderSettings(_ settings: ReaderRenderSettings) {}
    func setTextAnnotations(_ annotations: [CoreTextTextAnnotation]) {}
}

// MARK: - PageViewControllerVending Default Implementations

extension PageViewControllerVending where Self: PageLayoutEngine {
    func pageViewController(for position: CoreTextReadingPosition) -> UIViewController {
        if let page = pageIndex(for: position) {
            return pageViewController(at: page)
        }
        return pageViewController(at: 0)
    }
    func snapshotViewController(at index: Int) -> UIViewController? { nil }
    func renderSnapshot(forPage globalPage: Int) -> UIImage? { nil }
}
