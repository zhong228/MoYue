import Foundation
import Testing
@testable import yuedu_app

@Suite("Manga chapter parser")
struct MangaChapterParserTests {

    @Test("parses a JSON array of image URLs")
    func jsonArray() {
        let content = #"["https://cdn.example.com/1.jpg", "https://cdn.example.com/2.jpg"]"#
        let urls = MangaChapterParser.imageURLs(from: content)
        #expect(urls == ["https://cdn.example.com/1.jpg", "https://cdn.example.com/2.jpg"])
    }

    @Test("parses newline-separated URLs and drops non-URL lines")
    func newlineSeparated() {
        let content = """
        https://cdn.example.com/a.png
        not a url
        https://cdn.example.com/b.png
        """
        let urls = MangaChapterParser.imageURLs(from: content)
        #expect(urls == ["https://cdn.example.com/a.png", "https://cdn.example.com/b.png"])
    }

    @Test("keeps protocol-relative URLs")
    func protocolRelative() {
        let urls = MangaChapterParser.imageURLs(from: "//cdn.example.com/c.webp")
        #expect(urls == ["//cdn.example.com/c.webp"])
    }

    @Test("empty content yields no pages")
    func empty() {
        #expect(MangaChapterParser.imageURLs(from: "   \n  ").isEmpty)
    }

    @Test("pages attach headers and page indices")
    func pagesAttachHeaders() {
        let headers = ["Referer": "https://example.com"]
        let pages = MangaChapterParser.pages(
            from: "https://cdn.example.com/1.jpg\nhttps://cdn.example.com/2.jpg",
            headers: headers
        )
        #expect(pages.count == 2)
        #expect(pages[0].id == 0)
        #expect(pages[1].id == 1)
        #expect(pages[0].headers["Referer"] == "https://example.com")
        #expect(pages[0].localURL == nil)
    }
}
