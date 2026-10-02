import SwiftUI

/// 發現頁設定, behind the gear on a source's page: the categories the source returns as
/// chips, a card for each group the source draws (☆ 排行榜 ☆), to pick the ones the page
/// shows. With none picked the page shows every category; 全部顯示 clears the pick. Under
/// 快捷操作 with it sit the source's own controls — its buttons, inputs and toggles, run
/// as legado-E and MD3 run them — and its page links.
struct DiscoverPageSettingsSheet: View {
    @ObservedObject var discover: DiscoverViewModel
    /// Opens one of the source's page links; the source's page shows it once the sheet
    /// has gone.
    let onOpenPage: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .subheadline) private var chipMinWidth = DSLayout.discoverChipMinWidth
    @State private var query = ""
    /// The input being edited, and its text so far.
    @State private var editingInput: DiscoverQuickAction?
    @State private var inputDraft = ""

    /// Whether 快捷操作 has anything besides 全部顯示.
    private var hasControls: Bool {
        !discover.quickActions.isEmpty || !pageLinks.isEmpty
    }

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
                    // A search looks through the categories alone. The controls show even
                    // without categories: a source may list none until its login button
                    // has run.
                    if trimmedQuery.isEmpty && (!groups.isEmpty || hasControls) {
                        quickActions
                    }
                    if !groups.isEmpty {
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
                if groups.isEmpty && !hasControls {
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
            .alert(
                editingInput.map(discover.displayName(for:)) ?? "",
                isPresented: Binding(
                    get: { editingInput != nil },
                    set: { if !$0 { editingInput = nil } }
                ),
                presenting: editingInput
            ) { input in
                TextField(localized("輸入"), text: $inputDraft)
                Button(localized("取消"), role: .cancel) {}
                Button(localized("確定")) {
                    let text = inputDraft
                    Task { await discover.submitText(text, for: input, presentToast: Self.presentToast) }
                }
            }
        }
    }

    /// Toasts from the source's scripts, shown the way its login page shows them.
    private static func presentToast(_ message: String) {
        BookSourceFormLoginView.presentToastAlert(message: message)
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
            ForEach(discover.quickActions) { action in
                controlChip(action)
            }
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

    /// A source control as a chip: a button runs its script, an input opens for editing
    /// and shows what it holds, a toggle steps to its next value.
    private func controlChip(_ action: DiscoverQuickAction) -> some View {
        let name = discover.displayName(for: action)
        let value = discover.quickActionValues[action.title] ?? ""
        let isRunning = discover.runningQuickActionID == action.id
        return Button {
            switch action.kind {
            case .button:
                Task { await discover.runButton(action, presentToast: Self.presentToast) }
            case .text:
                inputDraft = value
                editingInput = action
            case .toggle:
                Task { await discover.cycleToggle(action, presentToast: Self.presentToast) }
            }
        } label: {
            switch action.kind {
            case .button:
                DSCapsuleLabel(title: name, fillsWidth: true, onCard: true)
            case .text:
                DSCapsuleLabel(
                    title: name,
                    fillsWidth: true,
                    onCard: true,
                    detail: value.isEmpty ? localized("輸入") : value
                )
            case .toggle:
                let current = action.toggleValue(in: discover.quickActionValues)
                DSCapsuleLabel(
                    title: action.valueTrails ? name + current : current + name,
                    fillsWidth: true,
                    onCard: true
                )
            }
        }
        .buttonStyle(.plain)
        .opacity(isRunning ? 0.5 : 1)
        .disabled(discover.runningQuickActionID != nil)
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

/// A card of chips under a title, in equal columns as many to a row as fit.
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
            ChipGrid(minimumColumnWidth: minimumChipWidth, spacing: DSSpacing.sm) {
                content()
            }
        }
        .padding(DSSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .interfaceCardSurface(in: RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous))
    }
}

/// Where each chip of a 發現頁設定 card goes: equal columns, as many to a row as fit, each
/// chip's name on one line — a chip whose name does not fit one column takes two, or as
/// many as it needs up to the whole row, rather than wrapping. The chips keep their order,
/// so one too wide for what is left of a row starts the next.
struct DiscoverChipGrid {
    struct Slot: Equatable {
        let row: Int
        let column: Int
        let span: Int
    }

    let columns: Int
    let columnWidth: CGFloat
    let spacing: CGFloat

    /// As many columns as fit `width` at `minimumColumnWidth`, as an adaptive `GridItem`
    /// makes them.
    init(width: CGFloat, minimumColumnWidth: CGFloat, spacing: CGFloat) {
        columns = max(1, Int((width + spacing) / (minimumColumnWidth + spacing)))
        columnWidth = max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        self.spacing = spacing
    }

    /// Each chip's slot, from its width with its name on one line.
    func slots(oneLineWidths: [CGFloat]) -> [Slot] {
        var slots: [Slot] = []
        slots.reserveCapacity(oneLineWidths.count)
        var row = 0
        var column = 0
        for width in oneLineWidths {
            let needed = ((width + spacing) / (columnWidth + spacing)).rounded(.up)
            let span = Int(min(CGFloat(columns), max(1, needed)))
            if column + span > columns {
                row += 1
                column = 0
            }
            slots.append(Slot(row: row, column: column, span: span))
            column += span
        }
        return slots
    }

    func x(of slot: Slot) -> CGFloat {
        CGFloat(slot.column) * (columnWidth + spacing)
    }

    func width(of slot: Slot) -> CGFloat {
        columnWidth * CGFloat(slot.span) + spacing * CGFloat(slot.span - 1)
    }
}

/// Lays chips out in a `DiscoverChipGrid`, each centred on the tallest in its row.
private struct ChipGrid: Layout {
    let minimumColumnWidth: CGFloat
    let spacing: CGFloat

    /// Each chip's width with its name on one line.
    func makeCache(subviews: Subviews) -> [CGFloat] {
        subviews.map { $0.sizeThatFits(.unspecified).width }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGFloat]) -> CGSize {
        let width = proposal.width ?? cache.reduce(spacing * CGFloat(max(cache.count - 1, 0)), +)
        let frames = frames(width: width, subviews: subviews, oneLineWidths: cache)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGFloat]) {
        let frames = frames(width: bounds.width, subviews: subviews, oneLineWidths: cache)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func frames(width: CGFloat, subviews: Subviews, oneLineWidths: [CGFloat]) -> [CGRect] {
        let grid = DiscoverChipGrid(width: width, minimumColumnWidth: minimumColumnWidth, spacing: spacing)
        let slots = grid.slots(oneLineWidths: oneLineWidths)
        let heights = zip(subviews, slots).map { subview, slot in
            subview.sizeThatFits(ProposedViewSize(width: grid.width(of: slot), height: nil)).height
        }
        // Rows come in order, each slot in the row it opened or in the one before.
        var rowHeights: [CGFloat] = []
        for (slot, height) in zip(slots, heights) {
            if slot.row == rowHeights.count {
                rowHeights.append(height)
            } else {
                rowHeights[slot.row] = max(rowHeights[slot.row], height)
            }
        }
        var rowTops: [CGFloat] = []
        var top: CGFloat = 0
        for height in rowHeights {
            rowTops.append(top)
            top += height + spacing
        }
        return zip(slots, heights).map { slot, height in
            CGRect(
                x: grid.x(of: slot),
                y: rowTops[slot.row] + (rowHeights[slot.row] - height) / 2,
                width: grid.width(of: slot),
                height: height
            )
        }
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
