import Foundation
import Testing
@testable import yuedu_app

struct ExploreSettingsTests {
    @Test("首屏配置 keeps its choice as a string and reads anything else as off")
    func landingRoundTrips() {
        for landing in [ExploreLanding.off, .myDiscover, .source(url: "https://fanqienovel.com")] {
            #expect(ExploreLanding(rawValue: landing.rawValue) == landing)
        }
        #expect(ExploreLanding(rawValue: "source:") == .off)
        #expect(ExploreLanding(rawValue: "something else") == .off)
    }

    @Test("chart keywords are stored one per line, blank lines dropped")
    func keywordsRoundTrip() {
        let keywords = ["榜", "排行", "top"]
        #expect(ExploreSettings.decodeKeywords(ExploreSettings.encodeKeywords(keywords)) == keywords)
        #expect(ExploreSettings.decodeKeywords("榜\n\n热门\n") == ["榜", "热门"])
        #expect(ExploreSettings.decodeKeywords("").isEmpty)
    }

    @Test("a category is a chart when its title holds any keyword, whatever the letter case")
    func sectionStyleFollowsKeywords() {
        let defaults = ExploreSettings.defaultRankedKeywords
        #expect(DiscoverViewModel.sectionStyle(for: "月票榜", rankedKeywords: defaults) == .ranked)
        #expect(DiscoverViewModel.sectionStyle(for: "TOP 50", rankedKeywords: defaults) == .ranked)
        #expect(DiscoverViewModel.sectionStyle(for: "精选推荐", rankedKeywords: defaults) == .featured)
        // An edited list decides on its own.
        #expect(DiscoverViewModel.sectionStyle(for: "精选推荐", rankedKeywords: ["推荐"]) == .ranked)
        #expect(DiscoverViewModel.sectionStyle(for: "月票榜", rankedKeywords: []) == .featured)
    }

    @Test("the cover gate holds a download past the limit until one finishes")
    func coverGateQueuesPastTheLimit() async {
        let gate = CoverDownloadGate()
        await gate.enter(limit: 2)
        await gate.enter(limit: 2)
        let third = Task { await gate.enter(limit: 2) }
        while await gate.waitingCount == 0 { await Task.yield() }
        #expect(await gate.runningCount == 2)

        await gate.leave()
        await third.value
        #expect(await gate.waitingCount == 0)
        #expect(await gate.runningCount == 2)
    }

    /// A source's explore list: two groups of categories with a filter and a page link
    /// among them, and one category the source lists twice.
    private static let discoverRaw: [ModernParserBridge.DiscoverItem] = [
        .init(title: "🟥 排行榜 🟥"),
        .init(title: "月票榜", url: "/rank/month"),
        .init(title: "畅销榜", url: "/rank/sales"),
        .init(title: "频道", type: "select", action: "频道", chars: ["男频", "女频"], default: "男频"),
        .init(title: "分類"),
        .init(title: "月票榜", url: "/rank/month"),
        .init(title: "玄幻", url: "/tag/fantasy"),
        .init(title: "官网", url: "@js:java.startBrowser(\"https://example.com\", \"官网\")"),
    ]

    @Test("發現頁設定 lists each category once, under the labels the source draws before them")
    func discoverCategoryGroups() {
        let groups = DiscoverViewModel.categoryGroups(from: Self.discoverRaw, defaultTitle: "分類")
        #expect(groups.map(\.title) == ["🟥 排行榜 🟥", "分類"])
        #expect(groups.map { $0.items.map(\.title) } == [["月票榜", "畅销榜"], ["玄幻"]])

        // A label that is only a drawn line names no group.
        let separated = DiscoverViewModel.categoryGroups(
            from: [.init(title: "━━━━━━"), .init(title: "推荐", url: "/recommend")],
            defaultTitle: "分類"
        )
        #expect(separated.map(\.title) == ["分類"])
    }

    @MainActor
    @Test("picked categories are the only ones shown, until none is picked")
    func discoverCategorySelection() throws {
        var source = BookSource()
        source.bookSourceName = "發現頁設定測試"
        source.bookSourceUrl = "https://discover-settings.test"
        let storageKey = "discover.categorySelection." + source.id.uuidString
        defer { UserDefaults.standard.removeObject(forKey: storageKey) }

        let discover = DiscoverViewModel(source: source)
        discover.items = Self.discoverRaw.compactMap(DiscoverViewModel.mapItem)
        let month = try #require(discover.items.first { $0.title == "月票榜" })
        let sales = try #require(discover.items.first { $0.title == "畅销榜" })
        #expect(discover.isCategoryShown(month) && !discover.isCategorySelected(month))
        #expect(!discover.hasCustomCategorySelection)

        discover.toggleCategorySelection(month)
        #expect(discover.isCategorySelected(month))
        #expect(!discover.isCategoryShown(sales))
        #expect(discover.sections.map(\.item.title) == ["月票榜"])
        // Another visit to the source's page keeps the pick.
        #expect(DiscoverViewModel(source: source).isCategorySelected(month))

        // Picking another keeps the section already there, books and all.
        let monthID = try #require(discover.sections.first?.id)
        discover.toggleCategorySelection(sales)
        #expect(discover.sections.map(\.item.title) == ["月票榜", "畅销榜"])
        #expect(discover.sections.first?.id == monthID)

        // Unpicking the last one shows every category again.
        discover.toggleCategorySelection(month)
        discover.toggleCategorySelection(sales)
        #expect(!discover.hasCustomCategorySelection)
        #expect(UserDefaults.standard.object(forKey: storageKey) == nil)
        #expect(discover.sections.map(\.item.title) == ["月票榜", "畅销榜", "玄幻"])
    }

    @Test("with no limit every cover download goes straight through")
    func coverGateWithoutLimit() async {
        let gate = CoverDownloadGate()
        for _ in 0..<5 { await gate.enter(limit: 0) }
        #expect(await gate.runningCount == 5)
        #expect(await gate.waitingCount == 0)
    }
}
