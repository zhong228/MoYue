import Foundation
import Testing
@testable import yuedu_app

struct EPUBManifestStoreTests {
    @Test func sidecarRoundTripBuildsChapterList() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manifest = BookManifest(
            title: "測試 EPUB",
            author: "作者",
            pipelineKind: .epub,
            spine: [
                BookSpineItem(href: "Text/ch1.xhtml", title: "第一章", mediaType: "application/xhtml+xml"),
                BookSpineItem(href: "Text/ch2.xhtml", title: "第二章", mediaType: "application/xhtml+xml"),
            ],
            resources: [],
            toc: [
                EPUBTocEntry(href: "Text/ch1.xhtml", title: "第一章", level: 0),
                EPUBTocEntry(href: "Text/ch2.xhtml", title: "第二章", level: 1),
            ]
        )

        let sidecar = EPUBManifestStore.sidecarURL(forEPUBFilename: "sample.epub", documentsRoot: root)
        try EPUBManifestStore.save(manifest, to: sidecar)

        let loaded = try #require(EPUBManifestStore.load(from: sidecar))
        #expect(loaded == manifest)

        let chapters = EPUBManifestStore.chapters(from: loaded)
        #expect(chapters.count == 2)
        #expect(chapters[0].title == "第一章")
        #expect(chapters[1].level == 1)
    }

    @Test func prepareLocalEPUBRecordMigratesLegacyFilename() throws {
        let defaults = UserDefaults.standard
        let metaKey = "yd_books_meta"
        let originalMeta = defaults.data(forKey: metaKey)
        defer {
            if let originalMeta {
                defaults.set(originalMeta, forKey: metaKey)
            } else {
                defaults.removeObject(forKey: metaKey)
            }
        }

        let store = BookStore()
        store.books = []

        let basename = UUID().uuidString
        let legacyFilename = "\(basename)_epub.json"
        let epubFilename = "\(basename).epub"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let legacyURL = docs.appendingPathComponent(legacyFilename)
        let epubURL = docs.appendingPathComponent(epubFilename)

        try Data("{}".utf8).write(to: legacyURL, options: .atomic)
        try Data("epub".utf8).write(to: epubURL, options: .atomic)
        defer {
            try? FileManager.default.removeItem(at: legacyURL)
            try? FileManager.default.removeItem(at: epubURL)
        }

        var legacyBook = ReadingBook(
            title: "舊書",
            author: "作者",
            source: "local_epub",
            contentFilename: legacyFilename
        )
        legacyBook.contentPipelineKind = .epub
        store.books = [legacyBook]

        let prepared = try #require(store.prepareLocalEPUBRecord(bookId: legacyBook.id))
        #expect(prepared.contentFilename == epubFilename)
        #expect(store.books.first?.contentFilename == epubFilename)
    }

    @Test func chaptersForEPUBUsesSidecarManifest() throws {
        let defaults = UserDefaults.standard
        let metaKey = "yd_books_meta"
        let originalMeta = defaults.data(forKey: metaKey)
        defer {
            if let originalMeta {
                defaults.set(originalMeta, forKey: metaKey)
            } else {
                defaults.removeObject(forKey: metaKey)
            }
        }

        let store = BookStore()
        store.books = []

        let manifest = BookManifest(
            title: "側錄書",
            author: "作者",
            pipelineKind: .epub,
            spine: [
                BookSpineItem(href: "OPS/nav.xhtml", title: "導航", mediaType: "application/xhtml+xml"),
                BookSpineItem(href: "OPS/ch1.xhtml", title: "正文", mediaType: "application/xhtml+xml"),
            ],
            resources: [],
            toc: [
                EPUBTocEntry(href: "OPS/nav.xhtml", title: "導航", level: 0),
                EPUBTocEntry(href: "OPS/ch1.xhtml", title: "正文", level: 0),
            ]
        )

        let book = ReadingBook(
            title: "側錄書",
            author: "作者",
            source: "local_epub",
            contentFilename: "\(UUID().uuidString).epub"
        )
        store.saveEPUBManifest(manifest, forEPUBFilename: book.contentFilename)
        defer {
            try? FileManager.default.removeItem(at: store.epubManifestURL(for: book))
        }

        let chapters = store.chapters(for: book)
        #expect(chapters.count == 2)
        #expect(chapters[0].href == "OPS/nav.xhtml")
        #expect(chapters[1].title == "正文")
    }
}
