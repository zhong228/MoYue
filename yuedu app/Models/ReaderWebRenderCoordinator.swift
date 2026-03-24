import Foundation
import SwiftUI

struct ReaderWebRenderState {
    let chapters: [BookChapter]
    let pages: [PageContent]
    let currentPage: Int
    let useWebRenderer: Bool
    let hasInitializedWebPackage: Bool
    let isLoadingPipeline: Bool
    let isRestoringPosition: Bool
    let txtXHTMLBasePath: URL?
}

@MainActor
enum ReaderWebRenderCoordinator {
    static func epubPlaceholderState(for book: ReadingBook, using store: BookStore) -> ReaderWebRenderState {
        let initialChapters = store.chapters(for: book)
        return placeholderState(
            title: book.title,
            chapters: initialChapters.isEmpty
                ? [BookChapter(index: 0, title: book.title, content: "")]
                : initialChapters
        )
    }

    static func placeholderState(title: String, chapters: [BookChapter]? = nil) -> ReaderWebRenderState {
        let resolvedChapters = chapters?.isEmpty == false
            ? chapters!
            : [BookChapter(index: 0, title: title, content: "")]
        return ReaderWebRenderState(
            chapters: resolvedChapters,
            pages: [
                PageContent(
                    chapterIndex: 0,
                    chapterTitle: title,
                    content: "",
                    pageInChapter: 0
                )
            ],
            currentPage: 0,
            useWebRenderer: true,
            hasInitializedWebPackage: false,
            isLoadingPipeline: true,
            isRestoringPosition: true,
            txtXHTMLBasePath: nil
        )
    }

    static func apply(
        package: BookPackage,
        book: ReadingBook?,
        renderer: EPUBPageRenderer,
        settings: ReaderRenderSettings,
        viewportSize: CGSize,
        safeAreaInsets: UIEdgeInsets,
        bookId: UUID,
        store: BookStore,
        deferCurrentPageSync: Bool = false
    ) -> ReaderWebRenderState {
        let chapters = packageChapters(from: package, book: book)
        let title = package.title

        renderer.setTransition("horizontal")
        renderer.setViewport(size: viewportSize, safeAreaInsets: safeAreaInsets)
        renderer.load(package: package, settings: settings)
        renderer.onRelocated = { [weak store] _, pct in
            store?.updatePosition(bookId: bookId, position: pct)
        }

        return ReaderWebRenderState(
            chapters: chapters,
            pages: [
                PageContent(
                    chapterIndex: 0,
                    chapterTitle: title,
                    content: "",
                    pageInChapter: 0
                )
            ],
            currentPage: deferCurrentPageSync ? 0 : renderer.currentEpubPage,
            useWebRenderer: true,
            hasInitializedWebPackage: true,
            isLoadingPipeline: false,
            isRestoringPosition: false,
            txtXHTMLBasePath: package.pipelineKind == .epub ? nil : package.basePath
        )
    }

    static func apply(
        document: ReaderEPUBDocument,
        scrollMode: Bool,
        renderer: EPUBPageRenderer,
        settings: ReaderRenderSettings,
        viewportSize: CGSize,
        safeAreaInsets: UIEdgeInsets,
        store: BookStore
    ) -> ReaderWebRenderState {
        renderer.setTransition(scrollMode ? "vertical" : "horizontal")
        renderer.setViewport(size: viewportSize, safeAreaInsets: safeAreaInsets)
        if scrollMode {
            renderer.loadEPUBScroll(source: document.source, settings: settings)
        } else {
            renderer.loadEPUB(source: document.source, settings: settings)
        }
        renderer.onRelocated = { [weak store] _, pct in
            store?.updatePosition(bookId: document.book.id, position: pct)
        }

        return ReaderWebRenderState(
            chapters: document.chapters,
            pages: document.initialPages,
            currentPage: renderer.currentEpubPage,
            useWebRenderer: true,
            hasInitializedWebPackage: true,
            isLoadingPipeline: false,
            isRestoringPosition: false,
            txtXHTMLBasePath: nil
        )
    }

    static func restoreDisplayState(renderer: EPUBPageRenderer) -> (currentPage: Int, chapterIndex: Int)? {
        guard renderer.totalPages > 0 else { return nil }
        let page = max(0, min(renderer.currentEpubPage, renderer.totalPages - 1))
        return (page, renderer.chapterIndex(forGlobalPage: page))
    }

    static func syncProgress(
        bookId: UUID,
        currentPage: Int,
        isRestoringPosition: Bool,
        renderer: EPUBPageRenderer,
        store: BookStore,
        flush: Bool
    ) -> Int? {
        guard !isRestoringPosition else { return nil }
        let total = renderer.totalPages
        guard total > 0 else { return nil }
        renderer.syncProgressToPage(currentPage, flush: flush)
        let chapterIndex = renderer.chapterIndex(forGlobalPage: currentPage)
        let pct = Double(currentPage) / Double(max(total - 1, 1))
        store.updatePosition(bookId: bookId, position: min(1.0, max(0.0, pct)))
        return chapterIndex
    }

    private static func packageChapters(from package: BookPackage, book: ReadingBook?) -> [BookChapter] {
        let tocLevelMap: [String: Int] = Dictionary(
            package.manifest.toc.map { ($0.href, $0.level) },
            uniquingKeysWith: { first, _ in first }
        )

        if let onlineRefs = book?.onlineChapters, !onlineRefs.isEmpty, book?.isOnline == true {
            return onlineRefs.enumerated().map { i, ref in
                let href = "chapter_\(i).xhtml"
                let level =
                    tocLevelMap[href]
                    ?? tocLevelMap.first(where: {
                        href.hasSuffix($0.key) || $0.key.hasSuffix(href)
                    })?.value
                    ?? 0
                return BookChapter(
                    index: i,
                    title: ref.title,
                    content: "",
                    href: href,
                    level: level
                )
            }
        }

        if package.pipelineKind == .epub {
            return [BookChapter(index: 0, title: package.title, content: "")]
        }

        let parsedChapters = package.parsedBook.chapters.enumerated().map { i, ch in
            let level =
                tocLevelMap[ch.href]
                ?? tocLevelMap.first(where: {
                    ch.href.hasSuffix($0.key) || $0.key.hasSuffix(ch.href)
                })?.value
                ?? 0
            return BookChapter(
                index: i,
                title: ch.title,
                content: "",
                href: ch.href,
                level: level
            )
        }

        return parsedChapters.isEmpty
            ? [BookChapter(index: 0, title: package.title, content: "")]
            : parsedChapters
    }
}
