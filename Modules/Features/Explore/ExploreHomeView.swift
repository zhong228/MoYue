import Combine
import SwiftUI

// MARK: - Explore Home

/// The landing screen of the 探索 (Explore) tab, redesigned in Apple Books Store style.
struct ExploreHomeView: View {
    @EnvironmentObject private var store: BookStore
    @ObservedObject private var sourceStore = BookSourceStore.shared
    @AppStorage(ExploreSettings.landingKey) private var landing = ExploreLanding.off.rawValue
    /// The browser's page and history, kept by `BrowserView` across visits.
    @ObservedObject var browser: BrowserState

    @State private var query = ""
    @State private var exploreSources: [BookSource] = []
    @State private var group: String?
    @State private var showSourceManager = false
    @State private var navigation = ExploreNavigationPath()
    @State private var sourceActionSheet: BookSourceActionSheet?
    @State private var sourcePendingDeletion: BookSource?
    @State private var browserPresentation: BrowserPresentation?
    @State private var showsSettings = false
    /// 首屏配置 opens its page once, the first time 探索 shows; going back stays here.
    @State private var appliedLanding = false
    @ObservedObject private var pageStore = CustomExplorePageStore.shared
    /// 新增自訂頁's or 重新命名's name prompt, and the name typed into it.
    @State private var pageNamePrompt: PageNamePrompt?
    @State private var pageName = ""
    @State private var pagePendingDeletion: CustomExplorePage?
    /// Currently selected source for the unified discover page.
    @State private var selectedSource: BookSource?
    /// 发现页选中书源的 URL，持久化后关闭 App 再打开仍保持选中（`ExploreSettings.selectedSourceURLKey`）。
    @AppStorage(ExploreSettings.selectedSourceURLKey) private var selectedSourceURL = ""
    @StateObject private var discoverVM = DiscoverViewModel()

    private struct BrowserPresentation: Identifiable {
        let id = UUID()
        let entry: BrowserEntry
    }

    /// One alert for both prompts: two on one view compete for one presenter.
    private enum PageNamePrompt: Identifiable {
        case create
        case rename(CustomExplorePage)

        var id: String {
            switch self {
            case .create: "create"
            case .rename(let page): page.id.uuidString
            }
        }

        var title: String {
            switch self {
            case .create: localized("新增自訂頁")
            case .rename: localized("重新命名")
            }
        }
    }

    private var groups: [String] {
        Array(Set(exploreSources.flatMap(Self.groupNames))).sorted()
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isFilteringSources: Bool { !trimmedQuery.isEmpty }

    private var visibleSources: [BookSource] {
        Self.sources(exploreSources, inGroup: group, matching: trimmedQuery)
    }

    static func sources(_ sources: [BookSource], inGroup group: String?, matching query: String) -> [BookSource] {
        sources.filter { source in
            if let group, !groupNames(of: source).contains(group) { return false }
            return query.isEmpty
                || source.bookSourceName.localizedStandardContains(query)
                || source.bookSourceGroup.localizedStandardContains(query)
        }
    }

    private static func groupNames(of source: BookSource) -> [String] {
        source.bookSourceGroup
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack(path: $navigation.path) {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.xl) {
                if !isFilteringSources {
                    heroBanner
                    quickAccessSection
                    selectedSourceDiscoverSection
                } else {
                    searchResultsView
                }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.sm)
            }
            .overlay {
                if isFilteringSources && !exploreSources.isEmpty && visibleSources.isEmpty {
                    ContentUnavailableView.search(text: trimmedQuery)
                }
            }
            .rootTabSearchScrollEdges()
            .scrollDismissesKeyboard(.immediately)
            .background(PageBackgroundView(scope: .explore).ignoresSafeArea())
            .pageBackgroundToolbar(for: .explore)
            .rootTabTitle(localized("发现"), onScroll: .minimizesBar)
            .toolbar {
                if groups.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) { groupMenu }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsSettings = true } label: {
                        Image(systemName: "gearshape")
                            .accessibilityHidden(true)
                    }
                    .accessibilityLabel(localized("探索設定"))
                }
            }
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: localized("搜索")
            )
            .sheet(isPresented: $showsSettings) {
                ExploreSettingsSheet(sources: exploreSources)
            }
            .onAppear(perform: applyLandingIfNeeded)
            .onReceive(sourceStore.$sources) { _ in
                exploreSources = DiscoverViewModel.exploreSources(in: sourceStore)
                if let group, !groups.contains(group) { self.group = nil }
                restorePersistedSourceIfNeeded()
                applyLandingIfNeeded()
            }
            .sheet(isPresented: $showSourceManager) {
                BookSourceListView()
            }
            .bookSourceActionSheets(sheet: $sourceActionSheet, pendingDeletion: $sourcePendingDeletion)
            .fullScreenCover(item: $browserPresentation) { presentation in
                NavigationStack {
                    BrowserPage(browser: browser, entry: presentation.entry)
                }
                .environmentObject(store)
            }
            .navigationDestination(for: ExploreNavigationRoute.self, destination: destination)
            .alert(
                pageNamePrompt?.title ?? "",
                isPresented: Binding(
                    get: { pageNamePrompt != nil },
                    set: { if !$0 { pageNamePrompt = nil } }
                ),
                presenting: pageNamePrompt
            ) { prompt in
                TextField(localized("名稱"), text: $pageName)
                switch prompt {
                case .create:
                    Button(localized("新建")) { pageStore.createPage(named: pageName) }
                case .rename(let page):
                    Button(localized("確定")) { pageStore.renamePage(id: page.id, to: pageName) }
                }
                Button(localized("取消"), role: .cancel) {}
            }
            .confirmationDialog(
                String(format: localized("刪除「%@」？"), pagePendingDeletion?.name ?? ""),
                isPresented: Binding(
                    get: { pagePendingDeletion != nil },
                    set: { if !$0 { pagePendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: pagePendingDeletion
            ) { page in
                Button(localized("刪除"), role: .destructive) { deletePage(page) }
                Button(localized("取消"), role: .cancel) {}
            } message: { _ in
                Text(localized("頁面裡的元件會一起刪除。"))
            }
        }
    }

    // MARK: - Hero Banner

    private var heroBanner: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: DSRadius.xl)
                .fill(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.8), Color.blue.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text(localized("发现好书"))
                    .font(DSFont.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text(localized("探索无尽阅读世界"))
                    .font(DSFont.callout)
                    .foregroundStyle(.white.opacity(0.9))
                HStack(spacing: DSSpacing.sm) {
                    sourceSelectorMenu
                    Button { openBrowser(.resume) } label: {
                        HStack(spacing: DSSpacing.xs) {
                            Image(systemName: "safari")
                                .font(.system(size: 13, weight: .semibold))
                            Text(localized("打开浏览器"))
                                .font(DSFont.footnote.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, DSSpacing.md)
                        .padding(.vertical, DSSpacing.xs)
                        .background {
                            RoundedRectangle(cornerRadius: DSRadius.md)
                                .fill(.white.opacity(0.25))
                        }
                    }
                }
            }
            .padding(DSSpacing.md)
        }
        .frame(height: 140)
    }

    // MARK: - Quick Access

    private var quickAccessSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text(localized("推荐"))
                .font(DSFont.title2.weight(.bold))
                .foregroundStyle(DSColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: DSSpacing.md) {
                    ForEach(pageStore.pages) { page in
                        NavigationLink(value: ExploreNavigationRoute.customPage(id: page.id)) {
                            QuickAccessCard(
                                icon: "doc.text",
                                title: page.name,
                                subtitle: localized("自定义页面"),
                                color: .orange,
                                action: { }
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .contextMenu { pageActions(page) }
                    }
                }
            }
        }
    }

    private var searchResultsView: some View {
        LazyVStack(spacing: DSSpacing.md) {
            ForEach(visibleSources) { source in
                NavigationLink(value: ExploreNavigationRoute.source(sourceURL: source.bookSourceUrl)) {
                    SearchResultRow(source: source)
                }
                .buttonStyle(PlainButtonStyle())
                .contextMenu { sourceActions(source) }
            }
        }
    }

    // MARK: - Source Selector Menu (embedded in hero banner)

    private var sourceSelectorMenu: some View {
        Menu {
            if exploreSources.isEmpty {
                Button { showSourceManager = true } label: {
                    Label(localized("前往书源管理添加"), systemImage: "plus.circle")
                }
            } else {
                ForEach(exploreSources) { source in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedSource = source
                            selectedSourceURL = source.bookSourceUrl
                            discoverVM.selectSource(source)
                            discoverVM.reload()
                        }
                    } label: {
                        HStack {
                            Text(source.bookSourceName)
                            if selectedSource?.id == source.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 13, weight: .semibold))
                Text(selectedSource?.bookSourceName ?? localized("选择书源"))
                    .font(DSFont.footnote.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.xs)
            .background {
                RoundedRectangle(cornerRadius: DSRadius.md)
                    .fill(.white.opacity(0.25))
            }
        }
    }

    // MARK: - Discover content (selected source's discover page)

    private var selectedSourceDiscoverSection: some View {
        Group {
            if let selectedSource {
                DiscoverShowcaseView(
                    discover: discoverVM,
                    onOpenPage: { address in openBrowser(.open(address)) },
                    embedsScrollView: false
                )
            } else if !exploreSources.isEmpty {
                ContentUnavailableView {
                    Label(localized("请选择上方书源"), systemImage: "arrow.up.circle")
                }
            }
        }
    }

    // MARK: - Actions

    private func openBrowser(_ entry: BrowserEntry) {
        browserPresentation = BrowserPresentation(entry: entry)
    }

    @ViewBuilder
    private func pageActions(_ page: CustomExplorePage) -> some View {
        Button {
            pageName = page.name
            pageNamePrompt = .rename(page)
        } label: {
            Label(localized("重新命名"), systemImage: "pencil")
        }
        Button(role: .destructive) {
            pagePendingDeletion = page
        } label: {
            Label(localized("刪除"), systemImage: "trash")
        }
    }

    /// Deletes the page; 首屏配置 set to it goes back to off.
    private func deletePage(_ page: CustomExplorePage) {
        if ExploreLanding(rawValue: landing) == .customPage(id: page.id) {
            landing = ExploreLanding.off.rawValue
        }
        pageStore.deletePage(id: page.id)
    }

    private func sourceActions(_ source: BookSource) -> some View {
        BookSourceActionMenuItems(
            source: source,
            onEdit: { sourceActionSheet = .edit(source) },
            onPinToTop: {
                BookSourceStore.shared.pinToTop(id: source.id)
                UIAccessibility.post(notification: .announcement, argument: localized("已置頂"))
            },
            onLogin: { sourceActionSheet = .login(source) },
            onSearch: { navigation.push(.searchInSource(sourceURL: source.bookSourceUrl)) },
            onRefresh: nil,
            onSetVariable: { sourceActionSheet = .variable(source) },
            onDelete: { sourcePendingDeletion = source }
        )
    }

    /// Group filter menu using a modern capsule/chip style.
    private var groupMenu: some View {
        Menu {
            Picker(localized("分組"), selection: $group) {
                Text(localized("全部")).tag(String?.none)
                ForEach(groups, id: \.self) { name in
                    Text(name).tag(Optional(name))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 12, weight: .semibold))
                if let group {
                    Text(group)
                        .font(.system(size: 13, weight: .medium))
                } else {
                    Text(localized("全部"))
                        .font(.system(size: 13, weight: .medium))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(DSBrandGradient.tint(for: "explore-filter").first ?? DSColor.accent)
            }
            .accessibilityHidden(true)
        }
        .accessibilityLabel(localized("分組"))
        .accessibilityValue(group ?? localized("全部"))
    }

    /// 首屏配置: the page 探索 opens straight onto, pushed the first time 探索 shows. A
    /// source's page waits for 探索's sources to load, so it never opens on one that only
    /// looks deleted because the list was not there yet; a source that has since gone
    /// opens nothing.
    private func applyLandingIfNeeded() {
        guard !appliedLanding, navigation.path.isEmpty else { return }
        // Landing disabled: stay on unified explore page.
        appliedLanding = true
    }

    /// 恢复上次选中的发现页书源：关闭 App 再打开仍保持选中。
    ///
    /// 只在还没有选中书源时恢复（本次会话的显式选择优先于持久化值）。持久化指向的
    /// 书源被禁用或删除后，清空持久化值，避免下一次启动反复尝试恢复一个不存在的源。
    private func restorePersistedSourceIfNeeded() {
        guard selectedSource == nil, !selectedSourceURL.isEmpty,
              !exploreSources.isEmpty else { return }
        if let source = exploreSources.first(where: { $0.bookSourceUrl == selectedSourceURL }) {
            selectedSource = source
            discoverVM.selectSource(source)
            discoverVM.reload()
        } else {
            selectedSourceURL = ""
        }
    }

    // MARK: - Destinations

    @ViewBuilder
    private func destination(_ route: ExploreNavigationRoute) -> some View {
        switch route {
        case .source(let sourceURL):
            if let source = sourceStore.sources.first(where: { $0.bookSourceUrl == sourceURL }) {
                ExploreSourcePage(source: source) { address in
                    openBrowser(.open(address))
                }
            } else {
                deletedSourceState
            }
        case .customPage(let id):
            CustomExplorePageView(pageID: id)
        case .customPageEditor(let id):
            CustomExplorePageEditor(pageID: id)
        case .book(let book):
            OnlineBookDetailDestination(.book(book)).environmentObject(store)
        case .sourceCategory(let reference):
            if let source = reference.source, let item = reference.cardItem {
                DiscoverCategoryView(
                    section: DiscoverShowcaseSection(
                        item: item,
                        coverBaseURL: source.bookSourceUrl,
                        coverHeaders: source.parsedHeaders
                    ),
                    source: source
                )
            } else {
                deletedSourceState
            }
        case .searchInSource(let sourceURL):
            SearchView(sessionScope: SearchSourceScope(
                mode: .custom, selectedSourceURLs: [sourceURL]
            ))
            .environmentObject(store)
        case .sourceManager:
            BookSourceListView(embedsNavigationStack: false)
        }
    }

    private var deletedSourceState: some View {
        ContentUnavailableView {
            UnavailableLabel(localized("書源已被刪除"), systemImage: "books.vertical")
        }
    }
}

// MARK: - QuickAccessCard

struct QuickAccessCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(color)
                Spacer()
                Text(title)
                    .font(DSFont.callout.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
            }
            .padding(DSSpacing.md)
            .frame(width: 140, height: 100)
            .background(DSColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
            .shadow(color: DSColor.shadow, radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - SearchResultRow

struct SearchResultRow: View {
    let source: BookSource

    private var gradientColors: [Color] {
        let hash = abs(source.bookSourceName.hashValue)
        let palette = DSColor.coverGradients
        return palette[hash % palette.count]
    }

    var body: some View {
        HStack(spacing: DSSpacing.md) {
            RoundedRectangle(cornerRadius: DSRadius.md)
                .fill(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 52, height: 78)
                .overlay {
                    Image(systemName: "book.closed")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.8))
                }
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(source.bookSourceName)
                    .font(DSFont.body.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                if !source.bookSourceGroup.isEmpty {
                    Text(source.bookSourceGroup)
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DSColor.textTertiary)
        }
        .padding(DSSpacing.md)
        .background(DSColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
    }
}

#Preview {
    ExploreHomeView(browser: BrowserState())
        .environmentObject(BookStore())
}
