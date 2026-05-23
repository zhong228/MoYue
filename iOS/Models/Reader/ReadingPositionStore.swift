import Foundation

protocol ReadingPositionStore: AnyObject, Sendable {
    func save(_ position: CoreTextReadingPosition, for bookId: String) async
    func load(for bookId: String) async -> CoreTextReadingPosition?
    func flush(for bookId: String) async
}

final class JSONFileReadingPositionStore: ReadingPositionStore {
    private let baseURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileManager = FileManager.default

    init() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.baseURL = docs.appendingPathComponent("reading_position", isDirectory: true)
        try? fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    private func fileURL(for bookId: String) -> URL {
        baseURL.appendingPathComponent("\(bookId).json")
    }

    func save(_ position: CoreTextReadingPosition, for bookId: String) async {
        guard let data = try? encoder.encode(position) else { return }
        let url = fileURL(for: bookId)
        let tmp = url.appendingPathExtension("tmp")
        try? data.write(to: tmp, options: .atomic)
        try? fileManager.replaceItemAt(url, withItemAt: tmp, backupItemName: nil, resultingItemURL: nil)
    }

    func load(for bookId: String) async -> CoreTextReadingPosition? {
        let url = fileURL(for: bookId)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(CoreTextReadingPosition.self, from: data)
    }

    func flush(for bookId: String) async {
    }
}
