import Testing
import UIKit
@testable import yuedu_app

@Suite("Pull-down bookmark motion")
struct ReaderPullDownBookmarkMotionTests {
    @Test("only clearly downward drags may begin the gesture")
    func beginDirection() {
        #expect(ReaderPullDownBookmarkMotion.shouldBegin(velocity: CGPoint(x: 0, y: 300)))
        #expect(ReaderPullDownBookmarkMotion.shouldBegin(velocity: CGPoint(x: 100, y: 300)))
        // Upward drag belongs to the swipe-up exit gesture.
        #expect(!ReaderPullDownBookmarkMotion.shouldBegin(velocity: CGPoint(x: 0, y: -300)))
        // Horizontal-dominant drags stay with the page-turn gestures.
        #expect(!ReaderPullDownBookmarkMotion.shouldBegin(velocity: CGPoint(x: -400, y: 300)))
        #expect(!ReaderPullDownBookmarkMotion.shouldBegin(velocity: CGPoint(x: 400, y: 300)))
        // Diagonal drags near 45° are ambiguous; require clear vertical dominance.
        #expect(!ReaderPullDownBookmarkMotion.shouldBegin(velocity: CGPoint(x: 300, y: 310)))
    }

    @Test("the two vertical reader gestures never both accept the same drag")
    func mutuallyExclusiveWithSwipeUpExit() {
        for velocity in [
            CGPoint(x: 0, y: 300), CGPoint(x: 0, y: -300),
            CGPoint(x: 120, y: 400), CGPoint(x: -120, y: -400),
            CGPoint(x: 400, y: 20), CGPoint(x: -400, y: -20),
        ] {
            let down = ReaderPullDownBookmarkMotion.shouldBegin(velocity: velocity)
            let up = ReaderSwipeUpExitMotion.shouldBegin(velocity: velocity)
            #expect(!(down && up), "both gestures claimed \(velocity)")
        }
    }

    @Test("progress tracks downward travel and clamps to 0...1")
    func progressClamping() {
        #expect(ReaderPullDownBookmarkMotion.progress(forTranslationY: 0) == 0)
        // Upward travel maps to zero progress, not negative.
        #expect(ReaderPullDownBookmarkMotion.progress(forTranslationY: -120) == 0)
        let half = ReaderPullDownBookmarkMotion.progress(
            forTranslationY: ReaderPullDownBookmarkMotion.fullProgressTranslation / 2
        )
        #expect(abs(half - 0.5) < 0.0001)
        let beyond = ReaderPullDownBookmarkMotion.progress(
            forTranslationY: ReaderPullDownBookmarkMotion.fullProgressTranslation * 3
        )
        #expect(beyond == 1)
    }

    @Test("release commits past the distance threshold")
    func commitByDistance() {
        #expect(ReaderPullDownBookmarkMotion.shouldCommit(
            progress: ReaderPullDownBookmarkMotion.commitProgress, velocityY: 0
        ))
        #expect(!ReaderPullDownBookmarkMotion.shouldCommit(
            progress: ReaderPullDownBookmarkMotion.commitProgress - 0.05, velocityY: 0
        ))
    }

    @Test("fast downward fling commits early, but a stray flick cannot")
    func commitByVelocity() {
        #expect(ReaderPullDownBookmarkMotion.shouldCommit(
            progress: ReaderPullDownBookmarkMotion.flingMinimumProgress,
            velocityY: ReaderPullDownBookmarkMotion.commitVelocityY
        ))
        #expect(!ReaderPullDownBookmarkMotion.shouldCommit(
            progress: 0.05, velocityY: ReaderPullDownBookmarkMotion.commitVelocityY
        ))
        #expect(!ReaderPullDownBookmarkMotion.shouldCommit(progress: 0.4, velocityY: 200))
    }

    @Test("pill drops from the top safe area as progress grows")
    func pillDrop() {
        let safeTop: CGFloat = 59
        let rest = ReaderPullDownBookmarkMotion.pillCenterY(forProgress: 0, topSafeInset: safeTop)
        let low = ReaderPullDownBookmarkMotion.pillCenterY(forProgress: 1, topSafeInset: safeTop)
        #expect(rest == safeTop + ReaderPullDownBookmarkMotion.pillRestTopInset)
        #expect(low - rest == ReaderPullDownBookmarkMotion.pillDrop)
    }

    @Test("pill grows from its minimum scale and fades in early")
    func pillScaleAndAlpha() {
        #expect(ReaderPullDownBookmarkMotion.pillScale(forProgress: 0) == ReaderPullDownBookmarkMotion.minPillScale)
        #expect(ReaderPullDownBookmarkMotion.pillScale(forProgress: 1) == 1)
        #expect(ReaderPullDownBookmarkMotion.pillAlpha(forProgress: 0) == 0)
        #expect(ReaderPullDownBookmarkMotion.pillAlpha(forProgress: 0.4) == 1)
    }

    @Test("icon and wording say add on a clean page and remove on a bookmarked one")
    func iconAndWording() {
        #expect(ReaderPullDownBookmarkMotion.iconName(isBookmarked: false, phase: .pulling) == "bookmark")
        #expect(ReaderPullDownBookmarkMotion.iconName(isBookmarked: false, phase: .armed) == "bookmark.fill")
        #expect(ReaderPullDownBookmarkMotion.iconName(isBookmarked: true, phase: .pulling) == "bookmark.fill")
        #expect(ReaderPullDownBookmarkMotion.iconName(isBookmarked: true, phase: .armed) == "bookmark.slash.fill")

        #expect(ReaderPullDownBookmarkMotion.titleKey(isBookmarked: false, phase: .pulling) == "下拉加入書籤")
        #expect(ReaderPullDownBookmarkMotion.titleKey(isBookmarked: false, phase: .armed) == "放開加入書籤")
        #expect(ReaderPullDownBookmarkMotion.titleKey(isBookmarked: false, phase: .done) == "已加入書籤")
        #expect(ReaderPullDownBookmarkMotion.titleKey(isBookmarked: true, phase: .pulling) == "下拉移除書籤")
        #expect(ReaderPullDownBookmarkMotion.titleKey(isBookmarked: true, phase: .armed) == "放開移除書籤")
        #expect(ReaderPullDownBookmarkMotion.titleKey(isBookmarked: true, phase: .done) == "已移除書籤")
    }

    @Test("every icon name resolves to a real SF Symbol")
    func iconsExist() {
        for bookmarked in [true, false] {
            for phase in [
                ReaderPullDownBookmarkMotion.Phase.pulling, .armed, .done,
            ] {
                let name = ReaderPullDownBookmarkMotion.iconName(isBookmarked: bookmarked, phase: phase)
                #expect(UIImage(systemName: name) != nil, "missing SF Symbol \(name)")
            }
        }
    }

    @Test("every wording key is localized in every language")
    func wordingIsLocalized() {
        for bookmarked in [true, false] {
            for phase in [
                ReaderPullDownBookmarkMotion.Phase.pulling, .armed, .done,
            ] {
                let key = ReaderPullDownBookmarkMotion.titleKey(isBookmarked: bookmarked, phase: phase)
                for language in ["zh-Hant", "zh-Hans", "en", "ja", "ko"] {
                    guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
                          let bundle = Bundle(path: path) else {
                        Issue.record("missing \(language).lproj")
                        continue
                    }
                    let value = bundle.localizedString(forKey: key, value: "⚠️", table: nil)
                    #expect(value != "⚠️", "\(language) is missing \(key)")
                }
            }
        }
    }
}

@Suite("One bookmark per page")
struct ReaderPageBookmarkRangeTests {
    private func bookmark(
        spine: Int, offset: Int, kind: Bookmark.Kind = .bookmark
    ) -> Bookmark {
        Bookmark(
            chapterIndex: spine,
            chapterTitle: "第 \(spine + 1) 章",
            position: CoreTextReadingPosition(spineIndex: spine, charOffset: offset),
            length: kind == .bookmark ? 0 : 4,
            kind: kind
        )
    }

    @Test("the page owns its own half-open char range")
    func rangeContainment() {
        let range = ReaderPageBookmarkRange(spineIndex: 2, startOffset: 400, endOffset: 800)
        #expect(range.contains(CoreTextReadingPosition(spineIndex: 2, charOffset: 400)))
        #expect(range.contains(CoreTextReadingPosition(spineIndex: 2, charOffset: 799)))
        // The next page's first character belongs to the next page.
        #expect(!range.contains(CoreTextReadingPosition(spineIndex: 2, charOffset: 800)))
        #expect(!range.contains(CoreTextReadingPosition(spineIndex: 2, charOffset: 399)))
        // Another chapter is never this page.
        #expect(!range.contains(CoreTextReadingPosition(spineIndex: 3, charOffset: 400)))
    }

    @Test("an open-ended range runs to the end of its chapter")
    func openEndedRange() {
        let range = ReaderPageBookmarkRange(spineIndex: 1, startOffset: 1200)
        #expect(range.contains(CoreTextReadingPosition(spineIndex: 1, charOffset: 1200)))
        #expect(range.contains(CoreTextReadingPosition(spineIndex: 1, charOffset: 999_999)))
        #expect(!range.contains(CoreTextReadingPosition(spineIndex: 1, charOffset: 1199)))
        #expect(!range.contains(CoreTextReadingPosition(spineIndex: 2, charOffset: 1200)))
    }

    @Test("a re-laid-out page still finds the bookmark that drifted off its first character")
    func survivesRepagination() {
        // Saved at the old page start; a larger font pushed that character into
        // the middle of the page. Equality would miss it and duplicate the bookmark.
        let saved = bookmark(spine: 4, offset: 620)
        let afterFontChange = ReaderPageBookmarkRange(spineIndex: 4, startOffset: 540, endOffset: 900)
        #expect(afterFontChange.pageBookmarks(in: [saved]).map(\.id) == [saved.id])
    }

    @Test("highlights and underlines on the page are not page bookmarks")
    func annotationsAreNotBookmarks() {
        let page = ReaderPageBookmarkRange(spineIndex: 0, startOffset: 0, endOffset: 500)
        let items = [
            bookmark(spine: 0, offset: 10, kind: .underline),
            bookmark(spine: 0, offset: 20, kind: .highlight),
            bookmark(spine: 0, offset: 30),
        ]
        #expect(page.pageBookmarks(in: items).map(\.position.charOffset) == [30])
    }

    @Test("the page's bookmark is written at the page's first character")
    func bookmarkPositionIsPageStart() {
        let range = ReaderPageBookmarkRange(spineIndex: 7, startOffset: 1024, endOffset: 1400)
        #expect(range.bookmarkPosition == CoreTextReadingPosition(spineIndex: 7, charOffset: 1024))
    }

    @Test("legacy chapter-start bookmarks land on the chapter's first page")
    func legacyChapterStartBookmarksBelongToPageOne() {
        let legacy = Bookmark(
            chapterIndex: 5, chapterTitle: "第六章", position: .chapterStart(5)
        )
        let firstPage = ReaderPageBookmarkRange(spineIndex: 5, startOffset: 0, endOffset: 600)
        let secondPage = ReaderPageBookmarkRange(spineIndex: 5, startOffset: 600, endOffset: 1200)
        #expect(firstPage.pageBookmarks(in: [legacy]).count == 1)
        #expect(secondPage.pageBookmarks(in: [legacy]).isEmpty)
    }
}

@Suite("Bookmark chapter grouping")
struct ReaderBookmarkChapterGroupTests {
    private func bookmark(spine: Int, offset: Int) -> Bookmark {
        Bookmark(
            chapterIndex: spine,
            chapterTitle: "第 \(spine + 1) 章",
            position: CoreTextReadingPosition(spineIndex: spine, charOffset: offset)
        )
    }

    @Test("same-chapter bookmarks sit together, in reading order")
    func groupsFollowReadingOrder() {
        let groups = ReaderBookmarkChapterGroup.group([
            bookmark(spine: 3, offset: 200),
            bookmark(spine: 1, offset: 900),
            bookmark(spine: 3, offset: 0),
            bookmark(spine: 1, offset: 100),
            bookmark(spine: 3, offset: 1400),
        ])

        #expect(groups.map(\.chapterIndex) == [1, 3])
        #expect(groups[0].items.map(\.position.charOffset) == [100, 900])
        #expect(groups[1].items.map(\.position.charOffset) == [0, 200, 1400])
    }

    @Test("no bookmarks means no groups")
    func emptyInput() {
        #expect(ReaderBookmarkChapterGroup.group([]).isEmpty)
    }

    @Test("every bookmark lands in exactly one group")
    func groupingIsAPartition() {
        let items = (0..<12).map { bookmark(spine: $0 % 4, offset: $0 * 37) }
        let groups = ReaderBookmarkChapterGroup.group(items)
        #expect(groups.flatMap(\.items).count == items.count)
        #expect(Set(groups.flatMap(\.items).map(\.id)) == Set(items.map(\.id)))
        for group in groups {
            #expect(group.items.allSatisfy { $0.chapterIndex == group.chapterIndex })
        }
    }
}

@Suite("Bookmark card excerpt")
struct ReaderBookmarkExcerptTests {
    @Test("the chapter name the card already shows is dropped from the excerpt")
    func dropsRepeatedChapterTitle() {
        // 章首那一頁的排版文字就是「章名＋內文」。
        let excerpt = "第一回　灵根育孕源流出 心性修持大道生诗曰：盖闻天地之数"
        let title = "第一回 灵根育孕源流出 心性修持大道生"
        #expect(ReaderBookmarkExcerpt.body(of: excerpt, chapterTitle: title) == "诗曰：盖闻天地之数")
    }

    @Test("whitespace differences between the laid-out title and the TOC title do not matter")
    func ignoresWhitespaceShape() {
        #expect(ReaderBookmarkExcerpt.body(
            of: "第 三 章\n\n正文開始", chapterTitle: "第三章"
        ) == "正文開始")
        #expect(ReaderBookmarkExcerpt.body(
            of: "第三章正文開始", chapterTitle: "第 三 章"
        ) == "正文開始")
    }

    @Test("a mid-chapter page keeps its excerpt untouched")
    func keepsUnrelatedExcerpt() {
        let excerpt = "牛贺洲，曰南赡部洲，曰北俱芦洲。"
        #expect(ReaderBookmarkExcerpt.body(of: excerpt, chapterTitle: "第一回 灵根育孕源流出") == excerpt)
    }

    @Test("a partial match is not a prefix and is left alone")
    func partialTitleIsNotStripped() {
        // 摘錄比章名短：章名還沒比完就沒字了，不能當作命中。
        #expect(ReaderBookmarkExcerpt.body(of: "第一回", chapterTitle: "第一回 灵根育孕源流出") == "第一回")
    }

    @Test("a page that is nothing but the chapter name keeps it")
    func titleOnlyPageKeepsTheTitle() {
        #expect(ReaderBookmarkExcerpt.body(
            of: "第一回　灵根育孕源流出", chapterTitle: "第一回 灵根育孕源流出"
        ) == "第一回　灵根育孕源流出")
    }

    @Test("an empty title or excerpt is handled without trimming anything away")
    func emptyInputs() {
        #expect(ReaderBookmarkExcerpt.body(of: "正文", chapterTitle: "") == "正文")
        #expect(ReaderBookmarkExcerpt.body(of: "  ", chapterTitle: "第一回") == "")
    }
}
