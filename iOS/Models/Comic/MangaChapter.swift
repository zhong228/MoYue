import Foundation

// MARK: - Manga page model
//
// A manga chapter's content (fetched through the normal `ChapterFetchManager`
// pipeline) is a list of image URLs. `MangaChapterParser` turns that string into
// `MangaPage`s, attaching the per-source request headers and, when the chapter has
// been downloaded for offline reading, the local file URL.

struct MangaPage: Identifiable, Equatable {
    let id: Int               // page index within the chapter
    let imageURL: String      // remote URL
    let headers: [String: String]
    var localURL: URL?        // non-nil when downloaded for offline reading
}

enum MangaChapterParser {

    /// Extract the ordered image URL list from a fetched chapter's `content`.
    /// Handles a JSON array of strings or newline-separated URLs (the pipeline
    /// already resolves relative/protocol-relative URLs to absolute).
    static func imageURLs(from content: String) -> [String] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if trimmed.hasPrefix("["),
           let data = trimmed.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
            let urls = array
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { isImageURL($0) }
            if !urls.isEmpty { return urls }
        }

        return trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { isImageURL($0) }
    }

    /// Build pages, attaching `headers` and any downloaded local files in `localDir`.
    static func pages(from content: String, headers: [String: String], localDir: URL? = nil) -> [MangaPage] {
        let urls = imageURLs(from: content)

        var localByIndex: [Int: URL] = [:]
        if let localDir,
           let files = try? FileManager.default.contentsOfDirectory(
               at: localDir, includingPropertiesForKeys: nil) {
            for file in files {
                if let index = Int(file.deletingPathExtension().lastPathComponent) {
                    localByIndex[index] = file
                }
            }
        }

        return urls.enumerated().map { index, url in
            MangaPage(id: index, imageURL: url, headers: headers, localURL: localByIndex[index])
        }
    }

    private static func isImageURL(_ s: String) -> Bool {
        let lower = s.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("//")
    }

    // MARK: Offline storage layout (shared by downloader + reader)

    /// Persistent (non-purgeable) root for downloaded manga images.
    static var rootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("manga", isDirectory: true)
    }

    static func chapterDirectory(bookId: UUID, chapterIndex: Int) -> URL {
        rootDirectory
            .appendingPathComponent(bookId.uuidString, isDirectory: true)
            .appendingPathComponent(String(chapterIndex), isDirectory: true)
    }

    /// Whether a chapter has downloaded image files on disk.
    static func isChapterDownloaded(bookId: UUID, chapterIndex: Int) -> Bool {
        let dir = chapterDirectory(bookId: bookId, chapterIndex: chapterIndex)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return !files.isEmpty
    }
}
