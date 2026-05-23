import Combine
import Foundation

@MainActor
final class ReadingPositionCoordinator: ObservableObject {
    private let store: any ReadingPositionStore
    private let bookId: String
    private var debounceTask: Task<Void, Never>?
    private let debounceInterval: UInt64 = 300_000_000

    @Published private(set) var committed: CoreTextReadingPosition
    @Published private(set) var isRestoring = true

    init(
        store: any ReadingPositionStore,
        bookId: String,
        fallback: CoreTextReadingPosition
    ) {
        self.store = store
        self.bookId = bookId
        self.committed = fallback
    }

    func restore() async {
        if let saved = await store.load(for: bookId) {
            committed = saved
        }
        isRestoring = false
    }

    func commit(_ position: CoreTextReadingPosition) {
        committed = position
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.debounceInterval)
            guard !Task.isCancelled else { return }
            await self.store.save(position, for: self.bookId)
        }
    }

    func flush() async {
        debounceTask?.cancel()
        await store.save(committed, for: self.bookId)
        await store.flush(for: self.bookId)
    }

    func positionForModeSwitch() -> CoreTextReadingPosition {
        committed
    }
}
