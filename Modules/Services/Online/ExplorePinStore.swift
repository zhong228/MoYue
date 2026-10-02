import Combine
import Foundation

// MARK: - 我的發現 (pinned explore categories)

/// One explore category of one source, addressed the way Legado addresses it: by the
/// source's URL plus the category's title and URL. Stable across launches and across
/// a source being re-imported (which mints a new id but keeps its URL).
struct ExploreCategoryReference: Codable, Hashable, Identifiable, Sendable {
    let sourceURL: String
    let title: String
    let url: String

    var id: String { "\(sourceURL)\u{1F}\(title)\u{1F}\(url)" }

    init(sourceURL: String, title: String, url: String) {
        self.sourceURL = sourceURL
        self.title = title
        self.url = url
    }

    init?(source: BookSource, item: DiscoverCardItem) {
        guard item.isFetchable, let url = item.raw.url else { return nil }
        self.init(sourceURL: source.bookSourceUrl, title: item.title, url: url)
    }

    var source: BookSource? {
        BookSourceStore.shared.sources.first { $0.bookSourceUrl == sourceURL }
    }

    /// The category as the discover pipeline consumes it.
    var cardItem: DiscoverCardItem? {
        DiscoverViewModel.mapItem(ModernParserBridge.DiscoverItem(title: title, url: url))
    }
}

/// The categories pinned into 我的發現 — categories from any number of sources,
/// gathered on one page. This is what huajideshutiao's 收藏 and MD3's custom
/// homepage sets do; like them it pins categories, it does not interleave the
/// sources' books into one feed (none of the three forks does).
@MainActor
final class ExplorePinStore: ObservableObject {
    static let shared = ExplorePinStore()

    @Published private(set) var pins: [ExploreCategoryReference] = []

    private let fileURL: URL

    init(fileURL: URL = StorageLocations.applicationSupportRoot.appendingPathComponent("explore_pins.json")) {
        self.fileURL = fileURL
        load()
    }

    func isPinned(_ reference: ExploreCategoryReference) -> Bool {
        pins.contains { $0.id == reference.id }
    }

    func toggle(_ reference: ExploreCategoryReference) {
        if isPinned(reference) {
            pins.removeAll { $0.id == reference.id }
        } else {
            pins.append(reference)
        }
        save()
    }

    func remove(_ reference: ExploreCategoryReference) {
        pins.removeAll { $0.id == reference.id }
        save()
    }

    func remove(atOffsets offsets: IndexSet) {
        pins = pins.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        save()
    }

    /// `List`'s `onMove` contract: `destination` is an offset in the list before the move.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { pins[$0] }
        var remaining = pins.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        remaining.insert(contentsOf: moving, at: destination - source.filter { $0 < destination }.count)
        pins = remaining
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            pins = try JSONDecoder().decode([ExploreCategoryReference].self, from: data)
        } catch {
            AppLogger.cache("⟐ explore pins could not be read", error: error)
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(pins)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLogger.cache("⟐ explore pins could not be saved", error: error)
        }
    }
}
