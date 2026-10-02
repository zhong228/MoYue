import SwiftUI

/// 發現頁設定, behind the gear on a source's page: the categories the source returns as
/// chips, a card for each group the source draws (☆ 排行榜 ☆), to pick the ones the page
/// shows. With none picked the page shows every category; 全部顯示 clears the pick. The
/// source's page links sit with it under 快捷操作.
struct DiscoverPageSettingsSheet: View {
    @ObservedObject var discover: DiscoverViewModel
    /// Opens one of the source's page links; the source's page shows it once the sheet
    /// has gone.
    let onOpenPage: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .subheadline) private var chipMinWidth = DSLayout.discoverChipMinWidth
    @State private var query = ""

    private var groups: [DiscoverCategoryGroup] {
        discover.categoryGroups(defaultTitle: localized("分類"))
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The groups holding categories that match the search; a group whose own label
    /// matches keeps all of its categories.
    private var visibleGroups: [DiscoverCategoryGroup] {
        guard !trimmedQuery.isEmpty else { return groups }
        return groups.compactMap { group in
            if group.title.localizedStandardContains(trimmedQuery) { return group }
            let items = group.items.filter { $0.title.localizedStandardContains(trimmedQuery) }
            guard !items.isEmpty else { return nil }
            return DiscoverCategoryGroup(id: group.id, title: group.title, items: items)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    if !groups.isEmpty {
                        // A search looks through the categories alone.
                        if trimmedQuery.isEmpty {
                            quickActions
                        }
                        ForEach(visibleGroups) { group in
                            ChipCard(title: group.title, minimumChipWidth: chipMinWidth) {
                                // Keyed by the category: the groups are mapped afresh on
                                // every update of the page behind the sheet, each item with
                                // a new id, which would rebuild every chip each time.
                                ForEach(group.items, id: \.stableKey) { item in
                                    categoryChip(item)
                                }
                            }
                        }
                    }
                }
                // The full width even with nothing to list, as 探索's own page needs.
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.sm)
            }
            .overlay {
                if groups.isEmpty {
                    if discover.isLoadingItems {
                        ProgressView()
                    } else {
                        ContentUnavailableView {
                            UnavailableLabel(localized("暫無發現內容"), systemImage: "sparkles")
                        }
                    }
                } else if !trimmedQuery.isEmpty && visibleGroups.isEmpty {
                    ContentUnavailableView.search(text: trimmedQuery)
                }
            }
            .softScrollEdges()
            .scrollDismissesKeyboard(.immediately)
            .background(PageBackgroundView(scope: .explore).ignoresSafeArea())
            .navigationTitle(localized("發現頁設定"))
            .toolbarTitleDisplayMode(.inline)
            .modifier(SubtitleWhereAvailable(subtitle: localized("選擇想看的分區")))
            .pageBackgroundToolbar(for: .explore)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: localized("搜尋發現項目")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Label(localized("關閉"), systemImage: "xmark")
                    }
                }
            }
        }
    }

    /// 全部顯示, picked while no category is, then the source's page links.
    private var quickActions: some View {
        ChipCard(title: localized("快捷操作"), minimumChipWidth: chipMinWidth) {
            let showsAll = !discover.hasCustomCategorySelection
            Button { discover.showAllCategories() } label: {
                DSCapsuleLabel(title: localized("全部顯示"), isSelected: showsAll, fillsWidth: true, onCard: true)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(showsAll ? .isSelected : [])
            ForEach(pageLinks, id: \.stableKey) { item in
                if let url = item.actionURL {
                    Button {
                        onOpenPage(url)
                        dismiss()
                    } label: {
                        DSCapsuleLabel(
                            title: item.title,
                            trailingSystemImage: "arrow.up.right",
                            fillsWidth: true,
                            onCard: true
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(localized("在瀏覽器中開啟"))
                }
            }
        }
    }

    /// The source's page links, each once.
    private var pageLinks: [DiscoverCardItem] {
        var seen = Set<String>()
        return discover.pageItems.filter { seen.insert($0.stableKey).inserted }
    }

    private func categoryChip(_ item: DiscoverCardItem) -> some View {
        let selected = discover.isCategorySelected(item)
        return Button { discover.toggleCategorySelection(item) } label: {
            DSCapsuleLabel(title: item.title, isSelected: selected, fillsWidth: true, onCard: true)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A card of chips under a title, as many to a row as fit.
private struct ChipCard<Content: View>: View {
    let title: String
    let minimumChipWidth: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text(title)
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.textSecondary)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: minimumChipWidth), spacing: DSSpacing.sm)],
                alignment: .leading,
                spacing: DSSpacing.sm,
                content: content
            )
        }
        .padding(DSSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .interfaceCardSurface(in: RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous))
    }
}

/// The subtitle under the title, from iOS 26; earlier bars have no place for one.
private struct SubtitleWhereAvailable: ViewModifier {
    let subtitle: String

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.navigationSubtitle(subtitle)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#Preview {
    var source = BookSource()
    source.bookSourceName = "範例書源"
    source.bookSourceUrl = "https://example.com"
    return DiscoverPageSettingsSheet(discover: DiscoverViewModel(source: source), onOpenPage: { _ in })
}
