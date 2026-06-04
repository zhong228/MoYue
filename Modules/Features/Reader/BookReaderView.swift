import SwiftUI

// MARK: - Book Reader Router
//
// Single branch point that picks the reader for a book: the shared fixed-page
// reader for image archives / FXL EPUB, otherwise the existing text/EPUB `ReaderView`.
// All shelf/online presentation sites go through this so `ReaderView` stays
// untouched.

struct BookReaderView: View {
    let bookId: UUID
    @EnvironmentObject var store: BookStore

    var body: some View {
        Group {
            if shouldUseFixedPageReader {
                FixedPageReaderView(bookId: bookId)
            } else {
                ReaderView(bookId: bookId)
            }
        }
        .onAppear {
            if store.books.first(where: { $0.id == bookId })?.lastOpenedDate == nil {
                store.updateLastOpened(bookId: bookId)
            }
        }
    }

    private var shouldUseFixedPageReader: Bool {
        guard let kind = store.books.first(where: { $0.id == bookId })?.resolvedPipelineKind else {
            return false
        }
        return kind == .manga || kind == .fixedPage
    }
}
