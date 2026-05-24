import Foundation
import Testing
import UIKit
@testable import yuedu_app

@MainActor
struct CoreTextScrollOnlineCacheTests {
    @Test("scroll engine requests uncached online chapter then retries insertion after cache is ready")
    func requestsMissingChapterAndRetriesAfterReady() async throws {
        let builder = MutableOnlineLikeBuilder(chapterCount: 2)
        builder.cachedChapters[1] = "Next chapter body"
        let settings = ReaderRenderSettings(
            theme: "test",
            textColor: .label,
            backgroundColor: .systemBackground,
            fontSize: 18,
            lineHeightMultiple: 1.4,
            lineSpacing: 2,
            paragraphSpacing: 8,
            letterSpacing: 0,
            marginH: 20,
            marginV: 20,
            footerHeight: 0,
            contentInsets: .zero,
            writingMode: .horizontal
        )
        let engine = CoreTextScrollEngine(builder: builder, renderSettings: settings)
        var requestedChapters: [Int] = []
        engine.onChapterContentRequired = { requestedChapters.append($0) }

        await engine.start(initialChapter: 1, contentWidth: 320)

        #expect(requestedChapters == [0])
        #expect(engine.chapterRanges[0] == nil)
        #expect(engine.chapterRanges[1] != nil)

        builder.cachedChapters[0] = "Previous chapter body"
        let didRetry = await engine.retryChapterIfNeeded(0)

        #expect(didRetry)
        #expect(engine.chapterRanges[0] != nil)
        #expect(engine.chunks.first?.chapterIndex == 0)
    }
}

private final class MutableOnlineLikeBuilder: AttributedStringBuilding {
    let chapterCount: Int
    var cachedChapters: [Int: String] = [:]

    init(chapterCount: Int) {
        self.chapterCount = chapterCount
    }

    func chapterTitle(at index: Int) -> String {
        "Chapter \(index)"
    }

    func chapterDataSize(at index: Int) async -> Int {
        cachedChapters[index]?.lengthOfBytes(using: .utf8) ?? 0
    }

    func buildChapter(
        at index: Int,
        settings: ReaderRenderSettings,
        themeTextColor: UIColor,
        themeBackgroundColor: UIColor
    ) async throws -> AttributedChapterBuildResult {
        guard index >= 0, index < chapterCount else {
            throw AttributedStringBuildingError.chapterOutOfRange(index)
        }
        guard let body = cachedChapters[index] else {
            throw AttributedStringBuildingError.contentNotCached(index)
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = settings.fontSize * settings.lineHeightMultiple
        paragraph.maximumLineHeight = settings.fontSize * settings.lineHeightMultiple

        return AttributedChapterBuildResult(
            attributedString: NSAttributedString(
                string: "\(chapterTitle(at: index))\n\(body)\n",
                attributes: [
                    .font: UIFont.systemFont(ofSize: settings.fontSize),
                    .foregroundColor: themeTextColor,
                    .paragraphStyle: paragraph
                ]
            ),
            imagePage: nil,
            pageBackgroundImage: nil,
            anchorOffsets: [:]
        )
    }
}
