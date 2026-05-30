import Combine
import Foundation
import SwiftUI

// MARK: - Discover Card Item

/// A single tappable entry on the 書源發現 (book-source discover) screen, derived
/// from a `ModernParserBridge.DiscoverItem`. Items are either *actions* (login /
/// open-in-browser) or *categories* (load a book list via `discoverBooks`).
struct DiscoverCardItem: Identifiable {
    let id = UUID()
    let title: String
    let raw: ModernParserBridge.DiscoverItem
    let isAction: Bool
    let actionURL: String?
    let isFetchable: Bool
}

// MARK: - Discover Showcase Section

/// How a showcase section renders its books. `featured` = horizontal cover
/// carousel (推薦/精選); `ranked` = numbered vertical list (榜單/排行).
enum DiscoverSectionStyle {
    case featured
    case ranked
}

/// Per-section loading lifecycle for the three-state UI (loading / empty / error).
enum DiscoverSectionPhase: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

/// One ranked/featured block on the redesigned 發現 showcase. Each section maps
/// directly to one of the *book source's own* explore categories — the source
/// owns the feed; we only present it faithfully.
struct DiscoverShowcaseSection: Identifiable {
    let id: UUID
    let item: DiscoverCardItem
    let style: DiscoverSectionStyle
    var books: [OnlineBook] = []
    var phase: DiscoverSectionPhase = .idle
    /// Short reason shown under the failed state, for on-device diagnosis.
    var errorReason: String?

    var title: String { item.title }

    init(item: DiscoverCardItem) {
        self.id = item.id
        self.item = item
        self.style = DiscoverViewModel.sectionStyle(for: item.title)
    }
}

// MARK: - Discover View Model

@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published var exploreSources: [BookSource] = []
    @Published var selectedSourceId: UUID?

    @Published var items: [DiscoverCardItem] = []
    @Published var books: [OnlineBook] = []
    @Published var booksSectionTitle: String = ""

    /// Showcase sections for the redesigned 發現 page (one per source category).
    @Published var sections: [DiscoverShowcaseSection] = []

    @Published var isLoadingItems = false
    @Published var isLoadingBooks = false

    /// Max number of source categories rendered as showcase sections.
    private let maxShowcaseSections = 12
    /// Serial loading queue for showcase sections (see `loadSection`).
    private var sectionQueue: [UUID] = []
    private var isPumpingSections = false

    @Published var selectedType = "小说"
    @Published var selectedChannel = "男频"
    @Published var selectedPlatform = "全部"

    let typeOptions = ["小说", "听书", "漫画", "短剧"]
    let channelOptions = ["男频", "女频"]

    private let sourceStore = BookSourceStore.shared
    private let runtimeStore = BookSourceRuntimeStateStore.shared
    private let selectedSourceKey = "discover.selectedSourceId"
    private var loadItemsTask: Task<Void, Never>?
    private var loadBooksTask: Task<Void, Never>?

    var selectedSource: BookSource? {
        exploreSources.first { $0.id == selectedSourceId }
    }

    var hasExploreSource: Bool { selectedSource != nil }

    var showsFilters: Bool {
        guard let source = selectedSource else { return false }
        return Self.sourceUsesDiscoverFilters(source)
    }

    /// 來源 (platform) chips, derived from the source's group list minus the aggregator name.
    var platformOptions: [String] {
        guard let group = selectedSource?.bookSourceGroup else { return ["全部"] }
        let parts = group
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "聚合" }
        return ["全部"] + parts
    }

    init() {
        if let stored = UserDefaults.standard.string(forKey: selectedSourceKey) {
            selectedSourceId = UUID(uuidString: stored)
        }
    }

    // MARK: - Source lifecycle

    func refreshSources() {
        exploreSources = sourceStore.enabledSources.filter {
            $0.enabledExplore
                && !$0.exploreUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if selectedSourceId == nil || !exploreSources.contains(where: { $0.id == selectedSourceId }) {
            selectedSourceId = exploreSources.first?.id
            persistSelectedSource()
        }
        if !platformOptions.contains(selectedPlatform) { selectedPlatform = "全部" }
        loadVariablesFromSource()
        if items.isEmpty, hasExploreSource { reload() }
    }

    func selectSource(_ id: UUID) {
        guard id != selectedSourceId else { return }
        selectedSourceId = id
        persistSelectedSource()
        if !platformOptions.contains(selectedPlatform) { selectedPlatform = "全部" }
        loadVariablesFromSource()
        reload()
    }

    // MARK: - Filters

    func setType(_ value: String) {
        guard value != selectedType else { return }
        selectedType = value
        if showsFilters { applyFilters() }
        reload()
    }

    func setChannel(_ value: String) {
        guard value != selectedChannel else { return }
        selectedChannel = value
        if showsFilters { applyFilters() }
        reload()
    }

    func setPlatform(_ value: String) {
        guard value != selectedPlatform else { return }
        selectedPlatform = value
        if showsFilters { applyFilters() }
        reload()
    }

    // MARK: - Loading

    func reload() {
        guard let source = selectedSource else {
            items = []
            books = []
            booksSectionTitle = ""
            cancelSectionTasks()
            sections = []
            return
        }
        loadItemsTask?.cancel()
        cancelSectionTasks()
        sections = []
        isLoadingItems = true
        loadItemsTask = Task { [weak self] in
            let raw = await BookSourceFetcher.shared.discoverItems(page: 1, in: source)
            guard let self, !Task.isCancelled else { return }
            let mapped = raw.compactMap(Self.mapItem)
            self.items = mapped
            self.isLoadingItems = false
            self.buildSections(from: mapped)
            if let first = mapped.first(where: { $0.isFetchable }) {
                self.loadBooks(for: first)
            } else {
                self.loadBooksTask?.cancel()
                self.books = []
                self.booksSectionTitle = ""
            }
        }
    }

    // MARK: - Showcase sections

    /// Turn the source's fetchable explore categories into showcase sections.
    private func buildSections(from items: [DiscoverCardItem]) {
        let fetchable = items.filter { $0.isFetchable }
        sections = fetchable.prefix(maxShowcaseSections).map { DiscoverShowcaseSection(item: $0) }
    }

    /// Enqueue one section's books to load — driven by the section view's `.task`.
    ///
    /// Loads run **serially** (one section at a time): a book source's explore
    /// fetch drives a JS runtime + shared login/cloud session, and firing several
    /// at once (LazyVStack renders multiple sections on first paint) can clobber
    /// that shared state. Sequential loading keeps each fetch deterministic.
    func loadSection(_ id: UUID) {
        guard let index = sections.firstIndex(where: { $0.id == id }) else { return }
        if sections[index].phase == .loading || sections[index].phase == .loaded { return }
        if sectionQueue.contains(id) { return }
        sectionQueue.append(id)
        pumpSectionQueue()
    }

    /// Retry a single failed section.
    func retrySection(_ id: UUID) {
        guard let index = sections.firstIndex(where: { $0.id == id }) else { return }
        sections[index].phase = .idle
        sections[index].errorReason = nil
        loadSection(id)
    }

    private func pumpSectionQueue() {
        guard !isPumpingSections, let id = sectionQueue.first else { return }
        guard let source = selectedSource,
              let index = sections.firstIndex(where: { $0.id == id }) else {
            if !sectionQueue.isEmpty { sectionQueue.removeFirst() }
            pumpSectionQueue()
            return
        }
        isPumpingSections = true
        sections[index].phase = .loading
        let raw = sections[index].item.raw
        Task { [weak self] in
            var loaded: [OnlineBook] = []
            var reason: String?
            var ok = false
            do {
                loaded = try await BookSourceFetcher.shared.discoverBooks(from: raw, page: 1, in: source)
                ok = true
            } catch {
                reason = (error as NSError).localizedDescription
            }
            guard let self else { return }
            // A reload may have cleared/rebuilt the queue mid-flight; only the
            // active pump (its id still at the front) advances shared state.
            guard self.sectionQueue.first == id else { return }
            self.sectionQueue.removeFirst()
            if let idx = self.sections.firstIndex(where: { $0.id == id }) {
                if ok {
                    self.sections[idx].books = loaded
                    self.sections[idx].phase = .loaded
                } else {
                    self.sections[idx].phase = .failed
                    self.sections[idx].errorReason = reason
                }
            }
            self.isPumpingSections = false
            self.pumpSectionQueue()
        }
    }

    private func cancelSectionTasks() {
        sectionQueue = []
        isPumpingSections = false
    }

    /// Section render style derived from the source's category title. The book
    /// source owns the categories; this only chooses a faithful presentation.
    nonisolated static func sectionStyle(for title: String) -> DiscoverSectionStyle {
        let featured = ["推荐", "推薦", "精选", "精選", "今日", "必读", "必讀",
                        "新书", "新書", "新作", "编辑", "編輯", "为你", "為你", "猜你"]
        if featured.contains(where: title.contains) { return .featured }
        let ranked = ["榜", "排行", "畅销", "暢銷", "热销", "熱銷", "热门", "熱門",
                      "完本", "完结", "完結", "top", "TOP", "Top"]
        if ranked.contains(where: title.contains) { return .ranked }
        return .featured
    }

    func handleTap(_ item: DiscoverCardItem, onNavigate: (String) -> Void) {
        if item.isAction, let url = item.actionURL {
            onNavigate(url)
        } else if item.isFetchable {
            loadBooks(for: item)
        }
    }

    func loadBooks(for item: DiscoverCardItem) {
        guard let source = selectedSource, item.isFetchable else { return }
        loadBooksTask?.cancel()
        isLoadingBooks = true
        booksSectionTitle = item.title
        loadBooksTask = Task { [weak self] in
            let result =
                (try? await BookSourceFetcher.shared.discoverBooks(from: item.raw, page: 1, in: source)) ?? []
            guard let self, !Task.isCancelled else { return }
            self.books = result
            self.isLoadingBooks = false
        }
    }

    // MARK: - Item mapping

    static func mapItem(_ raw: ModernParserBridge.DiscoverItem) -> DiscoverCardItem? {
        let title = (raw.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != "--" else { return nil }

        let url = (raw.url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let isAction = url.hasPrefix("{{") || url.contains("java.startBrowser")
        let actionURL = isAction ? extractHTTPURL(from: url) : nil
        let isFetchable = !isAction && !url.isEmpty

        // Skip pure labels (no url, no action) — e.g. a "username's 番茄" header.
        guard isAction || isFetchable else { return nil }

        return DiscoverCardItem(
            title: title,
            raw: raw,
            isAction: isAction,
            actionURL: actionURL,
            isFetchable: isFetchable
        )
    }

    static func extractHTTPURL(from string: String) -> String? {
        guard let range = string.range(of: "https?://[^\"')\\s]+", options: .regularExpression) else {
            return nil
        }
        return String(string[range])
    }

    // MARK: - Source runtime variables

    /// Filter selections persist as the source's Legado runtime variables, which the
    /// JS `exploreUrl` reads on its next run (`getVariable('频道')`, etc.).
    private func loadVariablesFromSource() {
        guard let source = selectedSource, showsFilters else { return }
        let dict = currentVariableDict(for: source)
        if let value = dict["频道"] as? String, channelOptions.contains(value) {
            selectedChannel = value
        }
        if let value = dict["发现页来源"] as? String {
            selectedPlatform = platformOptions.contains(value) ? value : "全部"
        }
        if let more = dict["更多设置"] as? [String: Any],
           let mode = more["搜索模式"] as? String, typeOptions.contains(mode) {
            selectedType = mode
        } else if let value = dict["发现页类型"] as? String, typeOptions.contains(value) {
            selectedType = value
        }
    }

    private func applyFilters() {
        guard let source = selectedSource, showsFilters else { return }
        var dict = currentVariableDict(for: source)
        dict["频道"] = selectedChannel
        dict["发现页来源"] = selectedPlatform
        dict["发现页类型"] = selectedType
        var more = (dict["更多设置"] as? [String: Any]) ?? [:]
        more["搜索模式"] = selectedType
        dict["更多设置"] = more
        writeVariableDict(dict, for: source)
    }

    private func currentVariableDict(for source: BookSource) -> [String: Any] {
        guard let json = runtimeStore.sourceVariableJSON(for: source.bookSourceUrl),
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    private func writeVariableDict(_ dict: [String: Any], for source: BookSource) {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
              let json = String(data: data, encoding: .utf8)
        else { return }
        runtimeStore.setSourceVariableJSON(json, for: source.bookSourceUrl)
    }

    private func persistSelectedSource() {
        guard let id = selectedSourceId else { return }
        UserDefaults.standard.set(id.uuidString, forKey: selectedSourceKey)
    }

    static func sourceUsesDiscoverFilters(_ source: BookSource) -> Bool {
        let probes = [source.exploreUrl, source.jsLib]
        let markers = ["频道", "发现页来源", "发现页类型", "搜索模式"]
        return probes.contains { text in
            markers.contains { text.contains($0) }
        }
    }
}
