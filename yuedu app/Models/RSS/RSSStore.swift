import Foundation
import Combine
import SwiftUI

class RSSStore: ObservableObject {
    static let shared = RSSStore()

    @Published var sources: [RSSSource] = []

    private let storageURL: URL = {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("rss_sources.json")
    }()

    private init() {
        load()
    }

    func addSource(_ source: RSSSource) {
        sources.append(source)
        save()
    }

    func removeSource(at offsets: IndexSet) {
        sources.remove(atOffsets: offsets)
        save()
    }

    func updateSource(_ source: RSSSource) {
        if let index = sources.firstIndex(where: { $0.id == source.id }) {
            sources[index] = source
            save()
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([RSSSource].self, from: data)
        else { return }
        sources = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sources) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
