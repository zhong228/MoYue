import UIKit

// MARK: - Fixed page reader container
//
// Owns the active mode reader (paged or webtoon), drives chapter fetching through
// the normal `ChapterFetchManager` pipeline, persists position, and bridges
// state/actions to the SwiftUI overlay via `FixedPageReaderState`.

final class FixedPageReaderViewController: UIViewController, FixedPageReaderContainer {

    private let book: ReadingBook
    private let source: BookSource?
    private weak var store: BookStore?
    private let state: FixedPageReaderState
    private let headers: [String: String]
    private let chapters: [OnlineChapterRef]

    private var chapterIndex: Int
    private var fixedPageReaderConfiguration: FixedPageReaderConfiguration
    private var reader: (any FixedPageModeReader)?
    private var loadToken = UUID()
    private var saveTask: Task<Void, Never>?

    init(book: ReadingBook, store: BookStore, state: FixedPageReaderState) {
        self.book = book
        self.store = store
        self.state = state
        let resolvedSource = book.bookSourceId.flatMap { id in
            BookSourceStore.shared.sources.first { $0.id == id }
        }
        self.source = resolvedSource
        self.headers = BookCoverLoader.headers(
            sourceBaseURL: resolvedSource?.bookSourceUrl,
            sourceHeaders: resolvedSource?.parsedHeaders ?? [:]
        )
        if !book.isOnline,
           (book.resolvedPipelineKind == .manga || book.resolvedPipelineKind == .fixedPage),
           (book.onlineChapters ?? []).isEmpty {
            self.chapters = [OnlineChapterRef(index: 0, title: book.title, url: book.contentFilename)]
        } else {
            self.chapters = book.onlineChapters ?? []
        }
        self.chapterIndex = min(max(0, book.mangaChapterIndex), max(0, self.chapters.count - 1))
        self.fixedPageReaderConfiguration = FixedPageReadingMode.savedConfiguration(for: book.id)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        state.fixedPageReaderConfiguration = fixedPageReaderConfiguration
        state.chapterListItems = FixedPageChapterListItem.items(from: chapters)
        state.currentChapterIndex = chapterIndex
        state.onJumpToPage = { [weak self] page in self?.reader?.goToPage(page, animated: false) }
        state.onSelectChapter = { [weak self] index in self?.selectChapter(at: index) }
        state.onSetConfiguration = { [weak self] configuration in self?.changeConfiguration(configuration) }
        state.onNextChapter = { [weak self] in self?.loadNextChapter() }
        state.onPrevChapter = { [weak self] in self?.loadPreviousChapter() }
        state.onReload = { [weak self] in
            guard let self else { return }
            self.loadChapter(at: self.chapterIndex, startPage: self.reader?.currentPageIndex() ?? 0)
        }

        store?.updateLastOpened(bookId: book.id)
        installReader()
        loadChapter(at: chapterIndex, startPage: book.mangaPage)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveTask?.cancel()
        store?.updateMangaPosition(
            bookId: book.id,
            chapter: chapterIndex,
            page: reader?.currentPageIndex() ?? 0,
            totalChapters: chapters.count
        )
    }

    // MARK: Reader installation

    private func installReader() {
        reader?.willMove(toParent: nil)
        reader?.view.removeFromSuperview()
        reader?.removeFromParent()

        let width = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        let newReader: any FixedPageModeReader = fixedPageReaderConfiguration.layout == .paged
            ? FixedPagePagedViewController(
                fixedPageReaderConfiguration: fixedPageReaderConfiguration,
                targetWidth: width
            )
            : FixedPageWebtoonViewController(
                fixedPageReaderConfiguration: fixedPageReaderConfiguration,
                targetWidth: width
            )
        newReader.container = self
        addChild(newReader)
        newReader.view.frame = view.bounds
        newReader.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(newReader.view, at: 0)
        newReader.didMove(toParent: self)
        reader = newReader
    }

    // MARK: Chapter loading

    private func loadChapter(at index: Int, startPage: Int) {
        guard chapters.indices.contains(index) else { return }
        chapterIndex = index
        state.currentChapterIndex = index
        state.isLoading = true
        state.errorMessage = nil
        state.chapterTitle = chapters[index].title

        let token = UUID()
        loadToken = token
        if isLocalFixedPageBook {
            loadLocalChapter(at: index, startPage: startPage, token: token)
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let package = try await ChapterFetchManager.shared.fetchChapter(
                    book: self.book, chapterIndex: index, priority: .immediate, store: self.store)
                guard self.loadToken == token else { return }
                let localDir = MangaChapterParser.chapterDirectory(bookId: self.book.id, chapterIndex: index)
                let pages = MangaChapterParser.pages(from: package.content, headers: self.headers, localDir: localDir)
                self.state.isLoading = false
                guard !pages.isEmpty else {
                    self.state.errorMessage = localized("未找到圖片")
                    return
                }
                self.reader?.setPages(pages, startPage: max(0, min(startPage, pages.count - 1)))
            } catch {
                guard self.loadToken == token else { return }
                self.state.isLoading = false
                self.state.errorMessage = error.localizedDescription
            }
        }
    }

    private var isLocalFixedPageBook: Bool {
        !book.isOnline
            && (book.resolvedPipelineKind == .manga || book.resolvedPipelineKind == .fixedPage)
    }

    private var isLocalFixedLayoutEPUBBook: Bool {
        isLocalFixedPageBook
            && book.source == "local_epub"
            && book.contentFilename.lowercased().hasSuffix(".epub")
    }

    private func loadLocalChapter(at index: Int, startPage: Int, token: UUID) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let archiveFilename: String
                if self.isLocalFixedLayoutEPUBBook || self.chapters[index].url.isEmpty {
                    archiveFilename = self.book.contentFilename
                } else {
                    archiveFilename = self.chapters[index].url
                }
                let archiveURL = LocalMangaArchive.archiveURL(for: archiveFilename)
                let pages: [FixedPage]
                if self.isLocalFixedLayoutEPUBBook {
                    pages = [
                        FixedPage(
                            id: 0,
                            imageURL: archiveURL.absoluteString,
                            headers: [:],
                            localURL: nil,
                            renderSource: .fixedLayoutEPUB(
                                sourceFilename: self.book.contentFilename,
                                chapterIndex: index
                            )
                        )
                    ]
                } else {
                    var imagePages = LocalMangaArchive.pagesForExtractedChapter(
                        bookId: self.book.id,
                        chapterIndex: index
                    )
                    if imagePages.isEmpty {
                        imagePages = try await LocalMangaArchive.extractPages(
                            from: archiveURL,
                            to: LocalMangaArchive.chapterDirectory(bookId: self.book.id, chapterIndex: index)
                        )
                    }
                    pages = imagePages
                }
                guard self.loadToken == token else { return }
                self.state.isLoading = false
                guard !pages.isEmpty else {
                    self.state.errorMessage = localized("未找到圖片")
                    return
                }
                self.reader?.setPages(pages, startPage: max(0, min(startPage, pages.count - 1)))
            } catch {
                guard self.loadToken == token else { return }
                self.state.isLoading = false
                self.state.errorMessage = error.localizedDescription
            }
        }
    }

    private func selectChapter(at index: Int) {
        guard chapters.indices.contains(index), index != chapterIndex else { return }
        loadChapter(at: index, startPage: 0)
    }

    private func loadNextChapter() {
        guard chapterIndex + 1 < chapters.count else { return }
        loadChapter(at: chapterIndex + 1, startPage: 0)
    }

    private func loadPreviousChapter() {
        guard chapterIndex - 1 >= 0 else { return }
        loadChapter(at: chapterIndex - 1, startPage: 0)
    }

    private func changeConfiguration(_ newConfiguration: FixedPageReaderConfiguration) {
        guard newConfiguration != fixedPageReaderConfiguration else { return }
        let page = reader?.currentPageIndex() ?? 0
        fixedPageReaderConfiguration = newConfiguration
        FixedPageReadingMode.save(newConfiguration.mode, for: book.id)
        state.fixedPageReaderConfiguration = newConfiguration
        installReader()
        loadChapter(at: chapterIndex, startPage: page)
    }

    // MARK: FixedPageReaderContainer

    func reader(didMoveToPage page: Int, total: Int) {
        state.currentPage = page
        state.totalPages = total
        scheduleSave(page: page)
    }

    func readerRequestsNextChapter() { loadNextChapter() }
    func readerRequestsPreviousChapter() { loadPreviousChapter() }
    func readerToggleControls() { state.showControls.toggle() }

    private func scheduleSave(page: Int) {
        saveTask?.cancel()
        let index = chapterIndex
        let total = chapters.count
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard let self, !Task.isCancelled else { return }
            self.store?.updateMangaPosition(bookId: self.book.id, chapter: index, page: page, totalChapters: total)
        }
    }
}
