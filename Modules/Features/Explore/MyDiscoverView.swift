import Combine
import SwiftUI

// MARK: - 我的發現

/// Categories pinned from any number of sources, one shelf each, gathered on one
/// page. Each shelf keeps its own source: its title leads to that source's full
/// category list and its books open with that source's rules. 編輯 reorders and
/// removes them.
struct MyDiscoverView: View {
    @ObservedObject private var pins = ExplorePinStore.shared
    @StateObject private var model = MyDiscoverModel()

    var body: some View {
        Group {
            if pins.pins.isEmpty {
                ContentUnavailableView {
                    UnavailableLabel(localized("我的發現"), systemImage: "star")
                } description: {
                    Text(localized("長按任何書源的分類標題，或在分類頁點星號，就能把它加進來。"))
                        .foregroundStyle(DSColor.textSecondary)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DSSpacing.xl) {
                        ForEach(model.shelves) { shelf in
                            shelfView(shelf)
                        }
                    }
                    .padding(.vertical, DSSpacing.lg)
                }
                .softScrollEdges()
                .refreshable { model.reload() }
            }
        }
        .background(PageBackgroundView(scope: .explore).ignoresSafeArea())
        .pageBackgroundToolbar(for: .explore)
        .navigationTitle(localized("我的發現"))
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            if !pins.pins.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(localized("編輯"), value: ExploreNavigationRoute.myDiscoverEditor)
                }
            }
        }
        .onAppear { model.sync(with: pins.pins) }
        .onChange(of: pins.pins) { _, newPins in model.sync(with: newPins) }
    }

    @ViewBuilder
    private func shelfView(_ shelf: MyDiscoverModel.Shelf) -> some View {
        if let section = shelf.section {
            DiscoverSectionView(
                section: section,
                source: shelf.source,
                route: .sourceCategory(shelf.reference),
                subtitle: shelf.source?.bookSourceName,
                onAppearLoad: { model.load(shelf.id) },
                onRetry: { model.retry(shelf.id) }
            )
        } else {
            // The source was deleted or its category no longer parses.
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(shelf.reference.title)
                    .font(DSFont.title3.weight(.bold))
                    .foregroundStyle(DSColor.textPrimary)
                Label(localized("書源已被刪除"), systemImage: "exclamationmark.triangle")
                    .font(DSFont.footnote)
                    .foregroundStyle(DSColor.textSecondary)
            }
            .padding(.horizontal, DSSpacing.lg)
            .contextMenu {
                Button(role: .destructive) {
                    ExplorePinStore.shared.remove(shelf.reference)
                } label: {
                    Label(localized("從我的發現移除"), systemImage: "star.slash")
                }
            }
        }
    }
}

// MARK: - 我的發現

/// The categories pinned into 我的發現, reordered and removed in place.
struct MyDiscoverPinsEditor: View {
    @ObservedObject private var pins = ExplorePinStore.shared

    var body: some View {
        List {
            ForEach(pins.pins) { pin in
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(pin.title)
                        .font(DSFont.body)
                        .foregroundStyle(DSColor.textPrimary)
                    Text(pin.source?.bookSourceName ?? localized("書源已被刪除"))
                        .font(DSFont.footnote)
                        .foregroundStyle(DSColor.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            .onMove { pins.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { pins.remove(atOffsets: $0) }
            .interfaceSectionSurface()
        }
        .environment(\.editMode, .constant(.active))
        .overlay {
            if pins.pins.isEmpty {
                ContentUnavailableView {
                    UnavailableLabel(localized("我的發現"), systemImage: "star")
                } description: {
                    Text(localized("長按任何書源的分類標題，或在分類頁點星號，就能把它加進來。"))
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
        }
        .navigationTitle(localized("我的發現"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .explore)
    }
}

/// Loads 我的發現's shelves one at a time, as `DiscoverViewModel` loads a source's
/// sections, so pinning many categories never fires every request at once.
@MainActor
final class MyDiscoverModel: ObservableObject {
    struct Shelf: Identifiable {
        let reference: ExploreCategoryReference
        let source: BookSource?
        var section: DiscoverShowcaseSection?
        var id: String { reference.id }
    }

    @Published private(set) var shelves: [Shelf] = []
    private var queueTail: Task<Void, Never>?
    private var requested: Set<String> = []

    func sync(with pins: [ExploreCategoryReference]) {
        let existing = Dictionary(uniqueKeysWithValues: shelves.map { ($0.id, $0) })
        shelves = pins.map { reference in
            if let kept = existing[reference.id] { return kept }
            let source = reference.source
            let section = source.flatMap { source in
                reference.cardItem.map {
                    DiscoverShowcaseSection(
                        item: $0,
                        coverBaseURL: source.bookSourceUrl,
                        coverHeaders: source.parsedHeaders
                    )
                }
            }
            return Shelf(reference: reference, source: source, section: section)
        }
        requested.formIntersection(Set(pins.map(\.id)))
    }

    func load(_ id: String) {
        guard !requested.contains(id) else { return }
        requested.insert(id)
        enqueue(id)
    }

    func retry(_ id: String) {
        enqueue(id)
    }

    func reload() {
        requested.removeAll()
        for index in shelves.indices {
            shelves[index].section?.books = []
            shelves[index].section?.phase = .idle
        }
        for shelf in shelves { load(shelf.id) }
    }

    private func enqueue(_ id: String) {
        let previous = queueTail
        queueTail = Task { [weak self] in
            await previous?.value
            await self?.fetch(id)
        }
    }

    private func fetch(_ id: String) async {
        guard let index = shelves.firstIndex(where: { $0.id == id }),
              let section = shelves[index].section,
              let source = shelves[index].source else { return }
        shelves[index].section?.phase = .loading
        shelves[index].section?.errorReason = nil
        do {
            let books = try await BookSourceFetcher.shared.discoverBooks(
                from: section.item.raw, page: 1, in: source
            )
            let displays = await DiscoverViewModel.makeDisplays(books, source: source)
            guard let current = shelves.firstIndex(where: { $0.id == id }) else { return }
            shelves[current].section?.books = displays
            shelves[current].section?.phase = .loaded
        } catch {
            AppLogger.network("⟐ 我的發現 shelf failed", error: error, context: ["category": id])
            guard let current = shelves.firstIndex(where: { $0.id == id }) else { return }
            shelves[current].section?.phase = .failed
            shelves[current].section?.errorReason = error.localizedDescription
        }
    }
}

#Preview("我的發現（空）") {
    NavigationStack {
        MyDiscoverView()
    }
}
