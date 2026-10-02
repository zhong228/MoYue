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

    @Test("with no limit every cover download goes straight through")
    func coverGateWithoutLimit() async {
        let gate = CoverDownloadGate()
        for _ in 0..<5 { await gate.enter(limit: 0) }
        #expect(await gate.runningCount == 5)
        #expect(await gate.waitingCount == 0)
    }
}
