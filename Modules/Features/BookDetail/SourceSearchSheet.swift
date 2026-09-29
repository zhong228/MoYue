import SwiftUI

struct SourceSearchSheet: View {
    let query: String
    let onSelectOrigin: (BookOrigin) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var aggregator = SearchAggregator()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if aggregator.isSearching && aggregator.results.isEmpty {
                    VStack(spacing: DSSpacing.md) {
                        ProgressView()
                        Text(localized("搜尋書源中…"))
                            .font(DSFont.subheadline)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if aggregator.results.isEmpty {
                    VStack(spacing: DSSpacing.md) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(DSColor.textTertiary)
                        Text(localized("未找到其他書源"))
                            .font(DSFont.subheadline)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(aggregator.results) { searchBook in
                            Section {
                                ForEach(searchBook.origins) { origin in
                                    Button {
                                        dismiss()
                                        onSelectOrigin(origin)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(origin.sourceName)
                                                    .font(DSFont.fixed(size: 15, weight: .medium))
                                                    .foregroundStyle(DSColor.textPrimary)
                                                if !origin.lastChapter.isEmpty {
                                                    Text(origin.lastChapter)
                                                        .font(DSFont.fixed(size: 12))
                                                        .foregroundStyle(DSColor.textSecondary)
                                                        .lineLimit(1)
                                                }
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(DSFont.fixed(size: 13))
                                                .foregroundStyle(DSColor.textSecondary.opacity(0.5))
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                HStack(spacing: DSSpacing.sm) {
                                    Text(searchBook.displayName)
                                        .font(DSFont.headline)
                                        .foregroundStyle(DSColor.textPrimary)
                                    if !searchBook.author.isEmpty {
                                        Text(searchBook.author)
                                            .font(DSFont.caption)
                                            .foregroundStyle(DSColor.textSecondary)
                                    }
                                }
                            }
                            .interfaceSectionSurface()
                        }
                    }
                    .softScrollEdges()
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(PageBackgroundView(scope: .bookshelf).ignoresSafeArea())
            .navigationTitle(localized("選擇來源"))
            .toolbarTitleDisplayMode(.inline)
            .pageBackgroundToolbar(for: .bookshelf)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .onAppear {
            aggregator.setResultPresentationActive(scenePhase == .active)
            if aggregator.results.isEmpty {
                let sources = BookSourceStore.shared.enabledSources
                aggregator.search(query: query, sources: sources)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            aggregator.setResultPresentationActive(phase == .active)
        }
    }
}
