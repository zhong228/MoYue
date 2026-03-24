import Foundation

struct ReaderEPUBDocument {
    let book: ReadingBook
    let session: PublicationSession
    let source: EPUBReaderSource
    let chapters: [BookChapter]
    let initialPages: [PageContent]

    init(book: ReadingBook, session: PublicationSession) {
        self.book = book
        self.session = session
        self.source = .publication(session)
        let tocLevelMap: [String: Int] = Dictionary(
            session.tocEntries.map { ($0.href, $0.level) },
            uniquingKeysWith: { first, _ in first }
        )
        let resolvedChapters = session.chapters.map { chapter in
            let level =
                tocLevelMap[chapter.href]
                ?? tocLevelMap.first(where: {
                    chapter.href.hasSuffix($0.key) || $0.key.hasSuffix(chapter.href)
                })?.value
                ?? 0
            return BookChapter(
                index: chapter.index,
                title: chapter.title,
                content: "",
                href: chapter.href,
                level: level
            )
        }
        self.chapters = resolvedChapters.isEmpty
            ? [BookChapter(index: 0, title: session.bookTitle, content: "")]
            : resolvedChapters
        self.initialPages = [
            PageContent(
                chapterIndex: 0,
                chapterTitle: session.bookTitle,
                content: "",
                pageInChapter: 0
            )
        ]
    }
}
