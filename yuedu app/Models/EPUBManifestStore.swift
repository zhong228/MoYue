import Foundation

enum EPUBManifestStore {
    private static let sidecarSuffix = ".manifest.json"

    static func sidecarFilename(forEPUBFilename filename: String) -> String {
        if filename.hasSuffix(".epub") {
            return String(filename.dropLast(5)) + sidecarSuffix
        }
        if filename.hasSuffix("_epub.json") {
            return filename.replacingOccurrences(of: "_epub.json", with: sidecarSuffix)
        }
        return filename + sidecarSuffix
    }

    static func sidecarURL(forEPUBFilename filename: String, documentsRoot: URL) -> URL {
        documentsRoot.appendingPathComponent(sidecarFilename(forEPUBFilename: filename))
    }

    static func load(from url: URL) -> BookManifest? {
        guard
            FileManager.default.fileExists(atPath: url.path),
            let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return try? JSONDecoder().decode(BookManifest.self, from: data)
    }

    static func save(_ manifest: BookManifest, to url: URL) throws {
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    static func chapters(from manifest: BookManifest) -> [BookChapter] {
        let tocLevelMap: [String: Int] = Dictionary(
            manifest.toc.map { ($0.href, $0.level) },
            uniquingKeysWith: { first, _ in first }
        )

        return manifest.spine.enumerated().map { index, item in
            let level =
                tocLevelMap[item.href]
                ?? tocLevelMap.first(where: {
                    item.href.hasSuffix($0.key) || $0.key.hasSuffix(item.href)
                })?.value
                ?? 0
            return BookChapter(
                index: index,
                title: item.title,
                content: "",
                href: item.href,
                level: level
            )
        }
    }
}
