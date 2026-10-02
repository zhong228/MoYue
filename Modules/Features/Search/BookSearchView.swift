import SwiftUI

private typealias BookSearchResultRoute = SearchResultRoute<SearchBook>

/// Navigation route for one frozen search-result snapshot.
///
/// Value-based navigation is deliberate. The closure form
/// `NavigationLink { destination } label: { … }` builds its destination for every
/// visible row on *every* list body evaluation. Before search-row presentation
/// snapshots were introduced, that repeatedly ran audio/text inference over
/// unbounded metadata such as full-page HTML intros. Value routing also keeps
/// destination creation out of the streaming list's redraw path.
///
/// The discover page never had this: it routes through `.navigationDestination`,
/// which resolves the destination once, on tap. The route retains that tapped
/// snapshot so later `SearchAggregator` publications cannot replace the data
/// under an active iOS 17 destination.

/// Installs only the navigation mechanism used by the active result renderer.
///
/// The UIKit renderer drives an item binding on iOS 17, while the native SwiftUI
/// list uses value routing on later systems. Delete the item-based branch
/// together with the native iOS 17 table when the deployment target reaches
/// iOS 18.
private struct SearchResultNavigationModifier<Destination: View>: ViewModifier {
    let mode: SearchResultNavigationMode
    @Binding var selectedRoute: BookSearchResultRoute?
    let destination: (BookSearchResultRoute) -> Destination

    @ViewBuilder
    func body(content: Content) -> some View {
        switch mode {
        case .selectedItem:
            content.navigationDestination(item: $selectedRoute, destination: destination)
        case .valueRoute:
            content.navigationDestination(
                for: BookSearchResultRoute.self,
                destination: destination
            )
        }
    }
}

/// Resolves a frozen route without capturing `BookSearchView` or its live
/// `SearchAggregator`. The inherited store is forwarded explicitly to preserve
/// the existing detail-view environment contract.
private struct SearchResultDestination: View {
    let route: BookSearchResultRoute
    @EnvironmentObject private var bookStore: BookStore

    @ViewBuilder
    var body: some View {
        let book = route.snapshot
        if BookSourceStore.shared.isAudiobook(book) {
            AudiobookDetailView(searchBook: book)
                .environmentObject(bookStore)
        } else {
            OnlineBookView(searchBook: book)
                .environmentObject(bookStore)
        }
    }
}

// MARK: - Book Search View

struct BookSearchView: View {
    var initialQuery: String = ""
    var showsCloseButton = false

    @EnvironmentObject var bookStore: BookStore
    @StateObject private var aggregator = SearchAggregator()
    @StateObject private var scopeStore = SearchSourceScopeStore.shared
    @ObservedObject private var sourceStore = BookSourceStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var query = ""
    @State private var errorMsg: String? = nil
    @State private var submittedQuery = ""
    @State private var selectedIOS17ResultRoute: BookSearchResultRoute?
    @State private var showsSourceScopeSheet = false
    @State private var needsSearchResubmission = false
    /// A book opened from 最近閱讀: pushed onto this stack, as a detail page pushes its
    /// reader. Audiobooks keep their own modal player.
    @State private var readerRoute: DetailReaderRoute?
    @State private var audiobookReaderRoute: DetailReaderRoute?
    @AppStorage(RecentSearchQueries.storageKey) private var recentQueries = RecentSearchQueries()

    var enabledSources: [BookSource] { sourceStore.enabledSources }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldShowEmptyResult: Bool {
        !submittedQuery.isEmpty && trimmedQuery == submittedQuery
    }

    var body: some View {
        AdaptiveContentContainer(maxWidth: DSLayout.readableExpandedWidth) {
            VStack(spacing: 0) {
                // No rule under the scope row: as in Apple Books' search, the content
                // starts below the controls, and on iOS 26 the list's soft scroll edge
                // marks where it slides out of view.
                if !enabledSources.isEmpty {
                    sourceScopeBar
                }

                ZStack {
                    if !aggregator.results.isEmpty {
                        resultList
                    } else if aggregator.isSearching {
                        // Progress and the pause control sit in the scope row above.
                        VStack(spacing: 12) {
                            Spacer()
                            ProgressView(localized("搜索中…"))
                            Spacer()
                        }
                    } else if aggregator.isPaused {
                        pausedPlaceholder
                    } else if shouldShowEmptyResult {
                        emptyResultView
                    } else {
                        SearchIdleContent(
                            isQueryEmpty: trimmedQuery.isEmpty,
                            onSearch: searchAgain,
                            onOpenBook: openRecentBook
                        ) {
                            hintView
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PageBackgroundView(scope: .search))
        }
        .background(PageBackgroundView(scope: .search).ignoresSafeArea())
        .pageBackgroundToolbar(for: .search)
        .navigationTitle(localized("搜索書籍"))
        .toolbarTitleDisplayMode(.inline)
        // Declared here, outside the lazy result containers, so the navigation
        // stack can always see the active destination.
        .modifier(
            SearchResultNavigationModifier(
                mode: .current,
                selectedRoute: $selectedIOS17ResultRoute,
                destination: SearchResultDestination.init(route:)
            )
        )
        .navigationDestination(item: $readerRoute) { route in
            BookReaderView(bookId: route.id)
                .environmentObject(bookStore)
                .environment(\.readerNavigator, nil)
                .environment(\.readerUsesParentNavigationStack, true)
                .navigationBarBackButtonHidden(true)
                .reservingNavigationBackSwipe()
        }
        .fullScreenCover(item: $audiobookReaderRoute) { route in
            BookReaderView(bookId: route.id)
                .environmentObject(bookStore)
                .environment(\.readerNavigator, nil)
        }
        .searchable(text: $query, prompt: localized("輸入書名或作者"))
        .sheet(isPresented: $showsSourceScopeSheet) {
            SearchSourceScopeSheet(
                enabledSources: enabledSources,
                initialScope: scopeStore.scope,
                onSave: applySearchSourceScope
            )
        }
        .onSubmit(of: .search) { doSearch() }
        .onChange(of: query) { _, newValue in
            // Mirror the old clear button: emptying the field resets the search.
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                submittedQuery = ""
                needsSearchResubmission = false
                aggregator.cancelAndClear()
            }
        }
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .accessibilityHidden(true)
                    }
                    .accessibilityLabel(localized("關閉"))
                }
            }
        }
        .alert(
            localized("搜索失敗"),
            isPresented: Binding(get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } })
        ) {
            Button(localized("確認")) { errorMsg = nil }
        } message: {
            Text(errorMsg ?? "")
        }
        .onAppear {
            aggregator.setResultPresentationActive(scenePhase == .active)
            if !initialQuery.isEmpty && query.isEmpty {
                query = initialQuery
                doSearch()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            aggregator.setResultPresentationActive(phase == .active)
        }
    }

    // Shown when a search was paused before any result came back. The ring in the
    // scope row above carries the search on.
    private var pausedPlaceholder: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "pause.circle")
                .font(DSFont.fixed(size: 48))
                .foregroundStyle(DSColor.textSecondary.opacity(0.4))
            Text(localized("已暫停")).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
            Text(localized("點擊繼續搜索剩餘書源")).font(DSFont.subheadline).foregroundStyle(DSColor.textSecondary)
            Spacer()
        }
    }

    // MARK: Source Scope

    /// The scope capsule, and at the other end, while a search runs or is paused, its
    /// progress ring — the one pause / resume control on the page. Manual companion to
    /// the network-settings auto-pause: tap to pause the in-flight search (battery,
    /// traffic) and again to resume the sources not yet asked. Auto-pause lands in the
    /// same paused state, so the same ring resumes an automatically paused search.
    private var sourceScopeBar: some View {
        HStack {
            SearchSourceScopeCapsule(
                title: sourceScopeSummary,
                isCustom: scopeStore.scope.mode == .custom,
                action: { showsSourceScopeSheet = true }
            )
            Spacer(minLength: DSSpacing.sm)
            if isSearchInProgress {
                SearchProgressControl(
                    progress: aggregator.progress,
                    isPaused: aggregator.isPaused,
                    onPause: { aggregator.pause() },
                    onResume: { aggregator.resume() }
                )
                .transition(.opacity)
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.xs)
        .animation(reduceMotion ? nil : DSAnimation.standard, value: isSearchInProgress)
    }

    private var isSearchInProgress: Bool {
        aggregator.isSearching || aggregator.isPaused
    }

    private var sourceScopeSummary: String {
        switch scopeStore.scope.mode {
        case .all:
            return localized("全部書源")
        case .custom:
            return String(
                format: localized("已選 %d 個書源"),
                scopeStore.scope.resolvedSources(from: enabledSources).count
            )
        }
    }

    // MARK: Result List
    @ViewBuilder
    private var resultList: some View {
        if #available(iOS 18.0, *) {
            modernResultList
        } else {
            iOS17ResultList
        }
    }

    @available(iOS 18.0, *)
    private var modernResultList: some View {
        List {
            ForEach(aggregator.results) { book in
                resultLink(for: book)
                .listRowInsets(EdgeInsets(
                    top: 0,
                    leading: DSLayout.searchListHorizontalInset,
                    bottom: 0,
                    trailing: DSLayout.searchListHorizontalInset
                ))
                .listRowBackground(Color.clear)
                // No rule over the first result: the scope row above has none either.
                .listRowSeparator(
                    book.id == aggregator.results.first?.id ? .hidden : .automatic,
                    edges: .top
                )
            }

            // 載入更多: fetch the next result page from every source that
            // answered the last round and hasn't been exhausted yet.
            if canLoadMore {
                loadMoreButton
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .softScrollEdges()
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Apple Books' result rows carry no disclosure chevron; the whole row opens the book.
        .navigationLinkIndicatorVisibility(.hidden)
    }

    private var iOS17ResultList: some View {
        IOS17SearchResultTable(
            content: IOS17SearchResultTableContent(
                rows: aggregator.results.map(IOS17SearchResultTableRow.init(searchBook:)),
                showsLoadMore: canLoadMore
            ),
            onSelect: { id in
                guard let book = aggregator.results.first(where: { $0.id == id }) else {
                    return
                }
                selectedIOS17ResultRoute = BookSearchResultRoute(
                    id: id,
                    snapshot: book
                )
            },
            onLoadMore: {
                aggregator.loadMore()
            }
        )
    }

    private func resultLink(for book: SearchBook) -> some View {
        NavigationLink(
            value: BookSearchResultRoute(id: book.id, snapshot: book)
        ) {
            AggregatedResultRow(book: book)
        }
    }

    private var canLoadMore: Bool {
        aggregator.hasMoreResults && !aggregator.isSearching && !aggregator.isPaused
    }

    private var loadMoreButton: some View {
        Button {
            aggregator.loadMore()
        } label: {
            HStack {
                Spacer()
                Label(localized("載入更多"), systemImage: "arrow.down.circle")
                    .font(DSFont.subheadline)
                    .foregroundColor(.accentColor)
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: Empty State
    private var emptyResultView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "magnifyingglass").font(DSFont.fixed(size: 48)).foregroundStyle(
                DSColor.textSecondary.opacity(0.3))
            Text(String(format: localized("沒有找到「%@」"), submittedQuery)).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
            Text(localized("嘗試換個關鍵字，或切換書源")).font(DSFont.subheadline).foregroundStyle(DSColor.textSecondary)
            Spacer()
        }
    }

    private var hintView: some View {
        VStack(spacing: 16) {
            Spacer()
            if enabledSources.isEmpty {
                Image(systemName: "exclamationmark.triangle").font(DSFont.fixed(size: 48))
                    .foregroundColor(.orange)
                Text(localized("尚未設置書源")).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                Text(localized("請先在書源管理中新增並啟用書源")).font(DSFont.subheadline).foregroundStyle(DSColor.textSecondary)
            } else {
                Image(systemName: "text.magnifyingglass").font(DSFont.fixed(size: 48)).foregroundStyle(
                    DSColor.textSecondary.opacity(0.3))
                if needsSearchResubmission {
                    Text(localized("搜索範圍已更新，請再次搜索"))
                        .font(DSFont.subheadline)
                        .foregroundStyle(DSColor.textSecondary)
                } else {
                    Text(localized("輸入書名或作者搜索"))
                        .font(DSFont.subheadline)
                        .foregroundStyle(DSColor.textSecondary)
                }
                Text(String(format: localized("已啟用 %d 個書源"), enabledSources.count))
                    .font(DSFont.caption)
                    .foregroundStyle(
                        DSColor.textSecondary.opacity(0.7))
            }
            Spacer()
        }
    }

    // MARK: Search Logic
    private func applySearchSourceScope(_ newScope: SearchSourceScope) {
        guard newScope != scopeStore.scope else { return }
        scopeStore.save(newScope)
        submittedQuery = ""
        needsSearchResubmission = !trimmedQuery.isEmpty
        aggregator.cancelAndClear()
    }

    private func doSearch() {
        let q = trimmedQuery
        guard !q.isEmpty else { return }
        let sources = scopeStore.scope.resolvedSources(from: enabledSources)
        guard !sources.isEmpty else {
            errorMsg = scopeStore.scope.mode == .custom
                ? localized("請至少選擇一個可用書源")
                : localized("沒有可用的書源，請先啟用書源")
            return
        }

        needsSearchResubmission = false
        submittedQuery = q
        recentQueries = recentQueries.recording(q)
        aggregator.search(query: q, sources: sources)
    }

    /// 最近搜索: the same search again, as if typed and submitted.
    private func searchAgain(_ recent: String) {
        query = recent
        doSearch()
    }

    /// 最近閱讀: back into the book where it was left, moved to the front of 最近閱讀
    /// as opening it from the shelf does.
    private func openRecentBook(_ book: ReadingBook) {
        bookStore.updateLastOpened(bookId: book.id)
        if book.resolvedPipelineKind == .audio {
            audiobookReaderRoute = DetailReaderRoute(id: book.id)
        } else {
            readerRoute = DetailReaderRoute(id: book.id)
        }
    }
}

// MARK: - Aggregated Result Row

/// One search result as Apple Books lists one in its search (`SearchBookListRow`): the
/// cover, the title with the grey 有聲書 tag on audiobooks, the author, and the kind and
/// source count in grey — 「小說 · 3 源」. Mirrors `IOS17SearchResultTableCell`, which draws
/// the same row in UIKit on iOS 17.
struct AggregatedResultRow: View {
    let book: SearchBook

    var body: some View {
        SearchBookListRow(content: SearchBookListRowContent(result: book)) {
            BookCoverImage(
                coverURL: book.coverUrl,
                title: book.displayName,
                author: book.author
            )
        }
    }
}

// MARK: - Source Picker Sheet

struct SourcePickerSheet: View {
    @Environment(\.presentationMode) var dismiss
    let searchBook: SearchBook
    let onSelectOrigin: (BookOrigin) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    BookCoverImage(
                        coverURL: searchBook.coverUrl,
                        title: searchBook.displayName,
                        author: searchBook.author
                    )
                    .frame(width: 60, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(searchBook.displayName).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                        Text(searchBook.author).font(DSFont.subheadline).foregroundStyle(DSColor.textSecondary)
                        if !searchBook.detailIntro.isEmpty {
                            Text(searchBook.detailIntro)
                                .font(DSFont.caption)
                                .foregroundStyle(DSColor.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                }
                .padding()

                Divider()

                List(searchBook.origins) { origin in
                    Button {
                        dismiss.wrappedValue.dismiss()
                        onSelectOrigin(origin)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(origin.sourceName)
                                    .font(DSFont.fixed(size: 15, weight: .medium))
                                    .foregroundStyle(DSColor.textPrimary)
                                if !origin.lastChapter.isEmpty {
                                    Text(origin.lastChapter)
                                        .font(DSFont.fixed(size: 12))
                                        .foregroundStyle(DSColor.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(DSFont.fixed(size: 13))
                                .foregroundStyle(DSColor.textSecondary.opacity(0.5))
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
                .softScrollEdges()
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(PageBackgroundView(scope: .bookshelf).ignoresSafeArea())
            .navigationTitle(
                String(format: localized("選擇來源（%d 個）"), searchBook.origins.count))
            .toolbarTitleDisplayMode(.inline)
            .pageBackgroundToolbar(for: .bookshelf)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss.wrappedValue.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
}

// MARK: - OnlineBook Identifiable (for sheet item)
extension OnlineBook: Hashable {
    static func == (lhs: OnlineBook, rhs: OnlineBook) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - SearchBook Identifiable (for sheet item)
extension SearchBook: Hashable {
    static func == (lhs: SearchBook, rhs: SearchBook) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

#Preview("搜索書籍") {
    NavigationStack {
        BookSearchView()
            .environmentObject(BookStore())
    }
}
