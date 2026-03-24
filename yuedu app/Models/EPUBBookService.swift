import UIKit

final class EPUBBookService {
    static let shared = EPUBBookService()

    private init() {}

    func localURL(for book: ReadingBook, using store: BookStore) -> URL {
        store.localEPUBURL(for: book)
    }

    func openPreparedSession(for book: ReadingBook, using store: BookStore) async throws -> (
        ReadingBook, PublicationSession
    ) {
        let resolvedBook = await MainActor.run {
            store.prepareLocalEPUBRecord(bookId: book.id) ?? book
        }
        let session = try await PublicationSession.open(sourceURL: localURL(for: resolvedBook, using: store))
        await MainActor.run {
            store.syncEPUBSession(session, for: resolvedBook.id)
        }
        let refreshedBook = await MainActor.run {
            store.books.first(where: { $0.id == resolvedBook.id }) ?? resolvedBook
        }
        return (refreshedBook, session)
    }

    func prepareReaderDocument(for book: ReadingBook, using store: BookStore) async throws
        -> ReaderEPUBDocument
    {
        let (resolvedBook, session) = try await openPreparedSession(for: book, using: store)
        return ReaderEPUBDocument(book: resolvedBook, session: session)
    }

    func openSession(for book: ReadingBook, using store: BookStore) async throws -> PublicationSession {
        let (_, session) = try await openPreparedSession(for: book, using: store)
        return session
    }

    func extractCoverImage(from sourceURL: URL) async -> UIImage? {
        await PublicationSession.extractCoverImage(sourceURL: sourceURL)
    }
}
