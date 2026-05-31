import Foundation
import Testing
@testable import yuedu_app

@Suite("OPDS Atom parser")
struct OPDSParserTests {

    private let feedURL = URL(string: "https://example.com/opds")!

    private let sample = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom" xmlns:opds="http://opds-spec.org/2010/catalog">
      <title>Sample Catalog</title>
      <link rel="next" href="?page=2" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
      <link rel="search" href="/opds/search.xml" type="application/opensearchdescription+xml"/>
      <entry>
        <title>Fiction</title>
        <id>nav-fiction</id>
        <link rel="subsection" href="/opds/fiction" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
      </entry>
      <entry>
        <title>The Great Book</title>
        <id>urn:book:1</id>
        <author><name>Jane Doe</name></author>
        <summary>A great book.</summary>
        <link rel="http://opds-spec.org/image/thumbnail" href="/covers/1-thumb.jpg" type="image/jpeg"/>
        <link rel="http://opds-spec.org/image" href="/covers/1.jpg" type="image/jpeg"/>
        <link rel="http://opds-spec.org/acquisition" href="/download/1.epub" type="application/epub+zip"/>
      </entry>
      <entry>
        <title>PDF Only</title>
        <id>urn:book:2</id>
        <link rel="http://opds-spec.org/acquisition/open-access" href="/download/2.pdf" type="application/pdf"/>
      </entry>
    </feed>
    """

    @Test("parses feed title, pagination and search links")
    func feedLevelLinks() throws {
        let feed = OPDSClient.parseFeed(data: Data(sample.utf8), feedURL: feedURL)
        #expect(feed.title == "Sample Catalog")
        #expect(feed.nextPageURL?.absoluteString == "https://example.com/opds?page=2")
        #expect(feed.searchDescriptionURL?.absoluteString == "https://example.com/opds/search.xml")
        #expect(feed.entries.count == 3)
    }

    @Test("classifies a navigation entry and resolves relative href")
    func navigationEntry() throws {
        let feed = OPDSClient.parseFeed(data: Data(sample.utf8), feedURL: feedURL)
        let nav = try #require(feed.entries.first { $0.title == "Fiction" })
        #expect(nav.isNavigation)
        #expect(!nav.isBook)
        #expect(nav.navigationURL?.absoluteString == "https://example.com/opds/fiction")
    }

    @Test("classifies a book entry with author, covers and EPUB acquisition")
    func bookEntry() throws {
        let feed = OPDSClient.parseFeed(data: Data(sample.utf8), feedURL: feedURL)
        let book = try #require(feed.entries.first { $0.title == "The Great Book" })
        #expect(book.isBook)
        #expect(book.author == "Jane Doe")
        #expect(book.thumbnailURL?.absoluteString == "https://example.com/covers/1-thumb.jpg")
        #expect(book.coverURL?.absoluteString == "https://example.com/covers/1.jpg")
        #expect(book.displayCoverURL == book.thumbnailURL)
        #expect(book.bestAcquisition?.importExtension == "epub")
    }

    @Test("an unsupported acquisition (PDF) is a book but not importable")
    func unsupportedAcquisition() throws {
        let feed = OPDSClient.parseFeed(data: Data(sample.utf8), feedURL: feedURL)
        let pdf = try #require(feed.entries.first { $0.title == "PDF Only" })
        #expect(pdf.isBook)
        #expect(pdf.bestAcquisition == nil)
    }
}
