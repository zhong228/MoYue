import SwiftUI
import UniformTypeIdentifiers
import UIKit

private enum RSSAddPresentationRoute: Hashable {
    case importJSON
    case importFileJSON
}

enum RSSHomeActionRoute: Hashable, CaseIterable {
    case exportJSON
    case settings
}

struct RSSListView: View {
    @StateObject private var store = RSSStore.shared

    @AppStorage("rss_main_feed_hide_read_feeds") private var hideReadFeeds = false
    @AppStorage("rss_main_feed_smart_feeds_expanded") private var smartFeedsExpanded = true
    @AppStorage("rss_main_feed_local_expanded") private var localFeedsExpanded = true

    @State private var expandedFolderIDs: Set<String> = []
    @State private var didSeedExpandedFolders = false
    @State private var showJSONImporter = false
    @State private var showJSONExporter = false
    @State private var showJSONURLSheet = false
    @State private var importMessage = ""
    @State private var showImportResult = false
    @State private var safariURL: URL?
    @State private var sourceToEdit: RSSSource?
    @State private var folderToRename: RSSFolder?
    @State private var sourceForInfo: RSSSource?
    @State private var deleteTarget: RSSDeleteTarget?
    @State private var showSettings = false
    @State private var showLegacyAddChooser = false
    @State private var legacyAddSequence =
        DismissalSequencedPresentation<RSSAddPresentationRoute>()
    @State private var showLegacyTopActionChooser = false
    @State private var legacyTopActionSequence =
        DismissalSequencedPresentation<RSSHomeActionRoute>()

    private var folders: [RSSFolder] {
        store.orderedFolders()
    }

    private var visibleFolders: [RSSFolder] {
        folders.filter { folder in
            !hideReadFeeds || store.unreadCount(for: folder) > 0
        }
    }

    private var rootSources: [RSSSource] {
        visibleSources(store.rootSources())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PageBackgroundView(scope: .rss)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        smartFeedsSection
                        localFeedsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 36)
                    .rootTabTitleScrollAnchor()
                }
                .softScrollEdges()
                .scrollIndicators(.visible)
            }
            .rootTabTitle(localized("訂閱源"), onScroll: .minimizesBar)
            .pageBackgroundToolbar(for: .rss)
            .toolbar {
                // Two separate glass pills. A ToolbarSpacer (iOS 26+) breaks the
                // auto-merge so the add (+) and options (…) menus sit in their own
                // glass instead of fusing into one.
                ToolbarItem(placement: .topBarTrailing) {
                    rssAddToolbarControl
                }

                #if compiler(>=6.2)
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                #endif

                ToolbarItem(placement: .topBarTrailing) {
                    rssTopToolbarControl
                }
            }
            .sheet(
                isPresented: $showLegacyAddChooser,
                onDismiss: presentLegacyAddActionAfterChooserDismissal
            ) {
                AdaptiveSheetContainer(maxWidth: DSLayout.readableCompactWidth) {
                    DismissalSequencedActionChooser(
                        title: localized("匯入"),
                        actions: [
                            DismissalSequencedAction(
                                route: .importJSON,
                                title: localized("從網址匯入 Legado JSON"),
                                systemImage: "link.badge.plus"
                            ),
                            DismissalSequencedAction(
                                route: .importFileJSON,
                                title: localized("從文件匯入 Legado JSON"),
                                systemImage: "doc.badge.plus"
                            ),
                        ],
                        onSelect: { legacyAddSequence.select($0) }
                    )
                }
            }
            .sheet(
                isPresented: $showLegacyTopActionChooser,
                onDismiss: presentLegacyTopActionAfterChooserDismissal
            ) {
                AdaptiveSheetContainer(maxWidth: DSLayout.readableCompactWidth) {
                    DismissalSequencedActionChooser(
                        title: localized("更多"),
                        actions: [
                            DismissalSequencedAction(
                                route: .exportJSON,
                                title: localized("匯出 Legado JSON"),
                                systemImage: "doc.badge.arrow.up",
                                isEnabled: !store.sources.isEmpty
                            ),
                            DismissalSequencedAction(
                                route: .settings,
                                title: localized("設定"),
                                systemImage: "gearshape"
                            ),
                        ],
                        onSelect: { legacyTopActionSequence.select($0) }
                    )
                }
            }
            .sheet(isPresented: $showJSONURLSheet) {
                ImportLegadoJSONURLSheet(isPresented: $showJSONURLSheet, store: store)
            }
            .fileImporter(
                isPresented: $showJSONImporter,
                allowedContentTypes: [.json, .data],
                allowsMultipleSelection: false,
                onCompletion: importLegadoJSON
            )
            .fileExporter(
                isPresented: $showJSONExporter,
                document: RSSJSONDocument(sources: store.sources.sorted(by: { $0.sortOrder < $1.sortOrder })),
                contentType: .json,
                defaultFilename: "yuedu-rss-legado.json"
            ) { _ in }
            .sheet(isPresented: $showSettings) {
                RSSSettingsContentView(isPresented: $showSettings)
            }
            .alert(localized("訂閱源"), isPresented: $showImportResult) {
                Button(localized("確定"), role: .cancel) {}
            } message: {
                Text(importMessage)
            }
            .alert(
                deleteTarget?.title ?? localized("刪除"),
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                presenting: deleteTarget
            ) { target in
                Button(localized("刪除"), role: .destructive) {
                    performDelete(target)
                }
                Button(localized("取消"), role: .cancel) {}
            } message: { target in
                Text(target.message)
            }
            .task {
                seedExpandedFoldersIfNeeded()
            }
            .onChange(of: store.folders) { _, _ in
                seedExpandedFoldersIfNeeded()
            }
        }
    }

    private var smartFeedsSection: some View {
        RSSHomeSection(
            icon: "text.book.closed.fill",
            title: localized("訂閱"),
            unreadCount: 0,
            isExpanded: $smartFeedsExpanded
        ) {
            ForEach(RSSSmartFeedKind.allCases) { smartFeed in
                NavigationLink(destination: RSSSmartFeedView(kind: smartFeed)) {
                    RSSMainFeedRow(
                        title: smartFeed.title,
                        unreadCount: store.unreadCount(for: smartFeed),
                        icon: .system(smartFeed.systemImage, tint: smartFeed.tintColor)
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if store.unreadCount(for: smartFeed) > 0 {
                        Button {
                            store.markAllRead(smartFeed: smartFeed)
                        } label: {
                            Label(localized("標記全部已讀"), systemImage: "checkmark.circle")
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    RSSHomeDivider()
                }
            }
        }
    }

    private var localFeedsSection: some View {
        RSSHomeSection(
            icon: "externaldrive.fill",
            title: localized("本機"),
            unreadCount: store.totalUnreadCount(),
            isExpanded: $localFeedsExpanded
        ) {
            if hideReadFeeds && visibleFolders.isEmpty && rootSources.isEmpty && !store.sources.isEmpty {
                Text(localized("沒有未讀訂閱"))
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 14)
            }

            ForEach(visibleFolders) { folder in
                folderRow(folder)
                    .overlay(alignment: .bottom) {
                        RSSHomeDivider()
                    }

                if expandedFolderIDs.contains(folder.id) {
                    ForEach(visibleSources(store.sources(in: folder))) { source in
                        sourceRow(source, indent: 36)
                            .overlay(alignment: .bottom) {
                                RSSHomeDivider()
                            }
                    }
                }
            }

            ForEach(rootSources) { source in
                sourceRow(source, indent: 0)
                    .overlay(alignment: .bottom) {
                        RSSHomeDivider()
                    }
            }
        }
    }

    private func folderRow(_ folder: RSSFolder) -> some View {
        let isExpanded = expandedFolderIDs.contains(folder.id)
        let unreadCount = store.unreadCount(for: folder)

        return Button {
            toggleFolder(folder)
        } label: {
            RSSMainFeedFolderRow(
                title: folder.name,
                unreadCount: unreadCount,
                isExpanded: isExpanded
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if unreadCount > 0 {
                Button {
                    store.markAllRead(in: folder)
                } label: {
                    Label(localized("標記全部已讀"), systemImage: "checkmark.circle")
                }
            }

            Button {
                folderToRename = folder
            } label: {
                Label(localized("重新命名"), systemImage: "pencil")
            }

            Button(role: .destructive) {
                deleteTarget = .folder(folder)
            } label: {
                Label(localized("刪除"), systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteTarget = .folder(folder)
            } label: {
                Label(localized("刪除"), systemImage: "trash")
            }

            Button {
                folderToRename = folder
            } label: {
                Label(localized("重新命名"), systemImage: "pencil")
            }
            .tint(.orange)
        }
    }

    private func sourceRow(_ source: RSSSource, indent: CGFloat) -> some View {
        NavigationLink(destination: RSSFeedView(source: source)) {
            RSSMainFeedRow(
                title: source.name,
                unreadCount: store.unreadCount(for: source.id),
                icon: .source(source),
                indent: indent
            )
        }
        .buttonStyle(.plain)
        .tint(.primary)
        .contextMenu {
            Button {
                sourceForInfo = source
            } label: {
                Label(localized("取得資訊"), systemImage: "info.circle")
            }

            if let homepageURL = source.homepageURL, URL(string: homepageURL) != nil {
                Button {
                    openURLString(homepageURL)
                } label: {
                    Label(localized("開啟首頁"), systemImage: "safari")
                }
            }

            Button {
                copyURLString(source.url)
            } label: {
                Label(localized("複製訂閱 URL"), systemImage: "doc.on.doc")
            }

            if let homepageURL = source.homepageURL, URL(string: homepageURL) != nil {
                Button {
                    copyURLString(homepageURL)
                } label: {
                    Label(localized("複製首頁 URL"), systemImage: "doc.on.doc")
                }
            }

            if store.unreadCount(for: source.id) > 0 {
                Button {
                    store.markAllRead(sourceID: source.id)
                } label: {
                    Label(localized("標記全部已讀"), systemImage: "checkmark.circle")
                }
            }

            Button {
                sourceToEdit = source
            } label: {
                Label(localized("編輯訂閱"), systemImage: "pencil")
            }

            Button(role: .destructive) {
                deleteTarget = .source(source)
            } label: {
                Label(localized("刪除"), systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if store.unreadCount(for: source.id) > 0 {
                Button {
                    store.markAllRead(sourceID: source.id)
                } label: {
                    Label(localized("標記全部已讀"), systemImage: "checkmark.circle")
                }
                .tint(DSColor.accent)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteTarget = .source(source)
            } label: {
                Label(localized("刪除"), systemImage: "trash")
            }

            Button {
                sourceToEdit = source
            } label: {
                Label(localized("編輯訂閱"), systemImage: "pencil")
            }
            .tint(.orange)
        }
    }

    private func visibleSources(_ sources: [RSSSource]) -> [RSSSource] {
        sources.filter { source in
            !hideReadFeeds || store.unreadCount(for: source.id) > 0
        }
    }

    private func toggleFolder(_ folder: RSSFolder) {
        if expandedFolderIDs.contains(folder.id) {
            expandedFolderIDs.remove(folder.id)
        } else {
            expandedFolderIDs.insert(folder.id)
        }
    }

    private func seedExpandedFoldersIfNeeded() {
        guard !didSeedExpandedFolders else {
            expandedFolderIDs.formUnion(store.folders.map(\.id))
            return
        }
        didSeedExpandedFolders = true
        expandedFolderIDs = Set(store.folders.map(\.id))
    }

    private func performDelete(_ target: RSSDeleteTarget) {
        switch target {
        case .source(let source):
            store.removeSources(ids: [source.id])
        case .folder(let folder):
            store.removeFolder(folder, deleteSources: true)
        }
        deleteTarget = nil
    }

    private func source(for id: String) -> RSSSource? {
        store.source(id: id)
    }

    private func importLegadoJSON(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let shouldStopAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if shouldStopAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let sources = try LegadoSourceJSONParser.parse(data: data)
            let addedSources = store.addSourcesReturningAdded(sources)
            importMessage = String(format: localized("已匯入 %d 個訂閱源"), addedSources.count)
            showImportResult = true
        } catch {
            importMessage = String(format: localized("Legado JSON 匯入失敗：%@"), error.localizedDescription)
            showImportResult = true
        }
    }

    private func openURLString(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        safariURL = url
    }

    private func copyURLString(_ urlString: String) {
        UIPasteboard.general.string = urlString
    }

    @ViewBuilder
    private var rssAddToolbarControl: some View {
        if MenuModalPresentationPolicy.requiresDismissalSequencedChooser {
            Button {
                legacyAddSequence.cancel()
                showLegacyAddChooser = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel(localized("匯入"))
        } else {
            RSSHomeAddMenu(
                onImportJSON: { showJSONImporter = true }
            )
        }
    }

    @ViewBuilder
    private var rssTopToolbarControl: some View {
        if MenuModalPresentationPolicy.requiresDismissalSequencedChooser {
            Button {
                legacyTopActionSequence.cancel()
                showLegacyTopActionChooser = true
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel(localized("更多"))
        } else {
            RSSHomeTopMenu(
                hasSources: !store.sources.isEmpty,
                onExportJSON: { showJSONExporter = true },
                onSettings: { showSettings = true }
            )
        }
    }

    private func presentLegacyAddActionAfterChooserDismissal() {
        guard let route = legacyAddSequence.consumeAfterDismissal() else {
            return
        }
        switch route {
        case .importJSON:
            showJSONURLSheet = true
        case .importFileJSON:
            showJSONImporter = true
        }
    }

    private func presentLegacyTopActionAfterChooserDismissal() {
        guard let route = legacyTopActionSequence.consumeAfterDismissal() else {
            return
        }
        switch route {
        case .exportJSON:
            showJSONExporter = true
        case .settings:
            showSettings = true
        }
    }

}

private enum RSSDeleteTarget: Identifiable {
    case source(RSSSource)
    case folder(RSSFolder)

    var id: String {
        switch self {
        case .source(let source):
            return "source-\(source.id)"
        case .folder(let folder):
            return "folder-\(folder.id)"
        }
    }

    var title: String {
        switch self {
        case .source:
            return localized("刪除訂閱源")
        case .folder:
            return localized("刪除資料夾")
        }
    }

    var message: String {
        switch self {
        case .source(let source):
            return String(format: localized("確定要刪除「%@」訂閱源嗎？"), source.name)
        case .folder(let folder):
            return String(format: localized("確定要刪除「%@」資料夾以及其中的訂閱源嗎？"), folder.name)
        }
    }

}

private struct RSSHomeCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            // Keeps its own systemBackground fill rather than DSColor.surface — that is
            // the card color this screen shipped with, and 分組卡片 off has to reproduce it.
            .interfaceCardSurface(fill: Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct RSSHomeSection<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The section's leading badge — 墨悦 colours the 訂閱/本機 heads as rows are.
    var icon: String? = nil
    let title: String
    let unreadCount: Int
    @Binding var isExpanded: Bool
    let content: Content

    init(
        icon: String? = nil,
        title: String,
        unreadCount: Int,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.unreadCount = unreadCount
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(reduceMotion ? nil : DSAnimation.fast) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: DSSpacing.sm) {
                    if let icon {
                        DSIconBadge(
                            systemImage: icon,
                            gradient: DSBrandGradient.tint(for: icon),
                            side: 28,
                            iconSize: 15
                        )
                    }
                    Text(title)
                        .font(DSFont.title3.weight(.bold))
                        .foregroundStyle(DSColor.textPrimary)

                    Spacer()

                    if !isExpanded && unreadCount > 0 {
                        Text(unreadCount.formatted())
                            .font(DSFont.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background {
                                Capsule()
                                    .fill(DSBrandGradient.tint(for: title).first ?? DSColor.accent)
                            }
                            .accessibilityHint(localized("篇未讀"))
                    }

                    Image(systemName: "chevron.down")
                        .font(DSFont.fixed(size: 17, weight: .bold))
                        .foregroundStyle(DSColor.textPrimary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)

            if isExpanded {
                RSSHomeCard {
                    VStack(spacing: 0) {
                        content
                    }
                }
            }
        }
    }
}

private struct RSSHomeDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 58)
    }
}

private struct RSSHomeAddMenu: View {
    let onImportJSON: () -> Void

    var body: some View {
        Menu {
            Button {
                onImportJSON()
            } label: {
                Label(localized("匯入 Legado JSON"), systemImage: "doc.badge.plus")
            }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel(localized("匯入"))
    }
}

private struct RSSHomeTopMenu: View {
    let hasSources: Bool
    let onExportJSON: () -> Void
    let onSettings: () -> Void

    var body: some View {
        Menu {
            Button {
                onExportJSON()
            } label: {
                Label(localized("匯出 Legado JSON"), systemImage: "doc.badge.arrow.up")
            }
            .disabled(!hasSources)

            Divider()

            Button {
                onSettings()
            } label: {
                Label(localized("設定"), systemImage: "gearshape")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(localized("更多"))
    }
}

private struct RSSSettingsContentView: View {
    @Binding var isPresented: Bool

    var body: some View {
        SettingsView()
            .environmentObject(BookStore())
            .environmentObject(SubscriptionStore.shared)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isPresented = false
                    } label: {
                        Label(localized("完成"), systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel(localized("完成"))
                }
            }
    }
}

private extension RSSSmartFeedKind {
    var tintColor: Color {
        switch self {
        case .today:
            return .blue
        case .allUnread:
            return DSColor.accent
        case .starred:
            return .yellow
        }
    }
}

private enum RSSMainFeedIcon {
    case source(RSSSource)
    case system(String, tint: Color)
}

private struct RSSMainFeedSectionHeader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let unreadCount: Int
    @Binding var isExpanded: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.down")
                .font(DSFont.fixed(size: 11, weight: .semibold))
                .rotationEffect(.degrees(isExpanded ? 0 : -90))

            Text(title)
                .font(DSFont.footnote.weight(.semibold))

            Spacer()

            if !isExpanded && unreadCount > 0 {
                Text(unreadCount.formatted())
                    .font(DSFont.footnote.weight(.semibold))
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
        .foregroundStyle(DSColor.textSecondary)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(reduceMotion ? nil : DSAnimation.fast) {
                isExpanded.toggle()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct RSSMainFeedFolderRow: View {
    let title: String
    let unreadCount: Int
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 10) {
            DSIconBadge(
                systemImage: "folder.fill",
                gradient: DSBrandGradient.tint(for: title),
                side: 32,
                iconSize: 18
            )

            Text(title)
                .font(DSFont.body)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)

            Spacer()

            if !isExpanded && unreadCount > 0 {
                Text(unreadCount.formatted())
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textSecondary)
            }

            Image(systemName: "chevron.down")
                .font(DSFont.fixed(size: 13, weight: .bold))
                .foregroundStyle(DSColor.textSecondary)
                .rotationEffect(.degrees(isExpanded ? 0 : -90))
                .frame(width: 16)
        }
        .padding(.horizontal, 24)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct RSSMainFeedRow: View {
    let title: String
    let unreadCount: Int
    let icon: RSSMainFeedIcon
    var indent: CGFloat = 0

    var body: some View {
        HStack(spacing: 10) {
            iconView

            Text(title)
                .font(DSFont.body)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)

            Spacer()

            if unreadCount > 0 {
                Text(unreadCount.formatted())
                    .font(DSFont.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background {
                        Capsule()
                            .fill(DSBrandGradient.tint(for: title).first ?? DSColor.accent)
                    }
                    .accessibilityHint(localized("篇未讀"))
            }
        }
        .padding(.leading, 24 + indent)
        .padding(.trailing, 24)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .source(let source):
            RSSFaviconView(source: source, size: 26)
                .frame(width: 32, height: 32)
        case .system(let imageName, _):
            DSIconBadge(
                systemImage: imageName,
                gradient: DSBrandGradient.tint(for: imageName),
                side: 32,
                iconSize: 18
            )
        }
    }
}

// MARK: - JSON Document

struct RSSJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .data] }
    static var writableContentTypes: [UTType] { [.json] }

    var data: Data

    init(sources: [RSSSource]) {
        data = (try? LegadoSourceJSONParser.export(sources: sources)) ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Import Legado JSON URL Sheet

private struct ImportLegadoJSONURLSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var store: RSSStore

    @State private var urlString = ""
    @State private var isLoading = false
    @State private var message = ""
    @State private var showMessage = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(localized("Legado JSON 網址")).foregroundStyle(DSColor.textSecondary)) {
                    TextField("https://.../sources/xxx.json", text: $urlString)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                .interfaceSectionSurface()

                Section(header: Text(localized("常用訂閱源倉庫")).foregroundStyle(DSColor.textSecondary)) {
                    Button {
                        urlString = "https://www.yckceo.com/yuedu/rss/json/id/193.json"
                    } label: {
                        HStack {
                            Image(systemName: "building.columns")
                            VStack(alignment: .leading) {
                                Text(localized("源倉庫（官方純淨）"))
                                    .font(DSFont.body)
                                Text("yckceo.com")
                                    .font(DSFont.caption)
                                    .foregroundStyle(DSColor.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundStyle(DSColor.accent)
                        }
                    }
                }
                .interfaceSectionSurface()

            }
            .softScrollEdges()
            .navigationTitle(localized("從網址匯入 Legado JSON"))
            .toolbarTitleDisplayMode(.inline)
            .themedAppSurface(for: .rss)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await importFromURL() }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            }
            .alert(localized("匯入"), isPresented: $showMessage) {
                Button(localized("確定"), role: .cancel) {
                    if !message.hasPrefix("❌") { isPresented = false }
                }
            } message: {
                Text(message)
            }
            .disabled(isLoading)
            .overlay {
                if isLoading {
                    ProgressView(localized("匯入中，請稍候…"))
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    @MainActor
    private func importFromURL() async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
            message = "❌ \(localized("訂閱源網址無效"))"
            showMessage = true
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let sources = try LegadoSourceJSONParser.parse(data: data)
            let addedCount = store.addSources(sources)
            message = "\(localized("成功匯入")) \(addedCount) \(localized("個訂閱源"))"
            showMessage = true
        } catch {
            message = "❌ \(String(format: localized("Legado JSON 匯入失敗：%@"), error.localizedDescription))"
            showMessage = true
        }
    }
}

private struct AddRSSFolderSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var store: RSSStore

    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(localized("資料夾名稱")).foregroundStyle(DSColor.textSecondary)) {
                    TextField(localized("資料夾名稱"), text: $name)
                }
                .interfaceSectionSurface()
            }
            .softScrollEdges()
            .navigationTitle(localized("新增資料夾"))
            .toolbarTitleDisplayMode(.inline)
            .themedAppSurface(for: .rss)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addFolder()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func addFolder() {
        _ = store.addFolder(named: name)
        isPresented = false
    }
}

private struct RenameRSSFolderSheet: View {
    let folder: RSSFolder
    @ObservedObject var store: RSSStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String

    init(folder: RSSFolder, store: RSSStore) {
        self.folder = folder
        self.store = store
        _name = State(initialValue: folder.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(localized("資料夾名稱")).foregroundStyle(DSColor.textSecondary)) {
                    TextField(localized("資料夾名稱"), text: $name)
                }
                .interfaceSectionSurface()
            }
            .softScrollEdges()
            .navigationTitle(localized("重新命名"))
            .toolbarTitleDisplayMode(.inline)
            .themedAppSurface(for: .rss)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        var updated = folder
                        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.updateFolder(updated)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct RSSSourceInfoSheet: View {
    let source: RSSSource
    @ObservedObject var store: RSSStore
    @Environment(\.dismiss) private var dismiss

    private var currentSource: RSSSource {
        store.source(id: source.id) ?? source
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(localized("基本資訊")).foregroundStyle(DSColor.textSecondary)) {
                    ThemedLabeledContent(localized("來源名稱"), value: currentSource.name)
                    ThemedLabeledContent(localized("訂閱源網址"), value: currentSource.url)
                    if let homepageURL = currentSource.homepageURL, !homepageURL.isEmpty {
                        ThemedLabeledContent(localized("首頁"), value: homepageURL)
                    }
                    if let faviconURL = currentSource.displayFaviconURL, !faviconURL.isEmpty {
                        ThemedLabeledContent(localized("圖示"), value: faviconURL)
                    }
                    if let group = currentSource.sourceGroup, !group.isEmpty {
                        ThemedLabeledContent(localized("資料夾"), value: group)
                    }
                }
                .interfaceSectionSurface()

                Section {
                    Button {
                        UIPasteboard.general.string = currentSource.url
                    } label: {
                        Label(localized("複製訂閱 URL"), systemImage: "doc.on.doc")
                    }

                    if let homepageURL = currentSource.homepageURL, let url = URL(string: homepageURL) {
                        Button {
                            UIApplication.shared.open(url)
                        } label: {
                            Label(localized("開啟首頁"), systemImage: "safari")
                        }
                    }
                }
                .interfaceSectionSurface()
            }
            .softScrollEdges()
            .navigationTitle(localized("取得資訊"))
            .toolbarTitleDisplayMode(.inline)
            .themedAppSurface(for: .rss)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Label(localized("完成"), systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel(localized("完成"))
                    .foregroundColor(DSColor.accent)
                }
            }
        }
    }
}

#Preview {
    RSSListView()
}
