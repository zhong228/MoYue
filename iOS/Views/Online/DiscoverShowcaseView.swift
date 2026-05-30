import SwiftUI

// MARK: - Discover Showcase

/// The redesigned 發現 (Discover) showcase. Renders the *book source's own*
/// explore categories as stacked ranking sections — a horizontal cover carousel
/// for 推薦/精選 categories and a numbered list for 榜單/排行 categories.
///
/// The source owns the feed; this view only presents it faithfully (see
/// `docs/design.md` §10 — Discover archetype).
struct DiscoverShowcaseView: View {
    @ObservedObject var discover: DiscoverViewModel
    let onOpenBook: (OnlineBook) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DSSpacing.xl) {
                if discover.isLoadingItems && discover.sections.isEmpty {
                    loadingState
                } else if discover.sections.isEmpty {
                    emptyState
                } else {
                    ForEach(discover.sections) { section in
                        DiscoverSectionView(
                            section: section,
                            onOpenBook: onOpenBook,
                            onAppearLoad: { discover.loadSection(section.id) },
                            onRetry: { discover.retrySection(section.id) }
                        )
                    }
                }
            }
            .padding(.vertical, DSSpacing.lg)
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable { discover.reload() }
    }

    private var loadingState: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .padding(.vertical, DSSpacing.xxl)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            localized("暫無發現內容"),
            systemImage: "sparkles",
            description: Text(localized("此書源未回傳發現內容，可下拉重新整理或切換書源"))
        )
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}

// MARK: - Section

/// One showcase section. Loads its books lazily the first time it scrolls on.
private struct DiscoverSectionView: View {
    let section: DiscoverShowcaseSection
    let onOpenBook: (OnlineBook) -> Void
    let onAppearLoad: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            header
            sectionBody
        }
        .task { onAppearLoad() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(section.title)
                .font(.title3.weight(.bold))
                .foregroundColor(DSColor.textPrimary)
                .lineLimit(1)
            Spacer(minLength: DSSpacing.sm)
            NavigationLink {
                DiscoverCategoryView(section: section, onOpenBook: onOpenBook)
            } label: {
                HStack(spacing: 2) {
                    Text(localized("查看全部"))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .font(DSFont.subheadline)
                .foregroundColor(DSColor.textSecondary)
            }
            .disabled(section.books.isEmpty)
            .opacity(section.books.isEmpty ? 0 : 1)
        }
        .padding(.horizontal, DSSpacing.lg)
    }

    @ViewBuilder
    private var sectionBody: some View {
        if !section.books.isEmpty {
            content
        } else {
            switch section.phase {
            case .failed:
                sectionFailed
            case .loaded:
                sectionEmpty
            case .idle, .loading:
                sectionLoading
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section.style {
        case .featured:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DSSpacing.md) {
                    ForEach(section.books) { book in
                        Button { onOpenBook(book) } label: {
                            DiscoverFeaturedCard(book: book)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DSSpacing.lg)
            }
            .scrollClipDisabled()
        case .ranked:
            VStack(spacing: 0) {
                let ranked = Array(section.books.prefix(6).enumerated())
                ForEach(ranked, id: \.element.id) { index, book in
                    Button { onOpenBook(book) } label: {
                        DiscoverRankedRow(rank: index + 1, book: book)
                    }
                    .buttonStyle(.plain)
                    if index < ranked.count - 1 {
                        Divider().padding(.leading, 88)
                    }
                }
            }
            .padding(.horizontal, DSSpacing.lg)
        }
    }

    private var sectionLoading: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .frame(height: section.style == .featured ? 170 : 120)
    }

    private var sectionEmpty: some View {
        Text(localized("暫無發現內容"))
            .font(DSFont.caption)
            .foregroundColor(DSColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, DSSpacing.lg)
            .padding(.horizontal, DSSpacing.lg)
    }

    private var sectionFailed: some View {
        Button(action: onRetry) {
            VStack(spacing: DSSpacing.xs) {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: "arrow.clockwise")
                    Text(localized("載入失敗，點按重試"))
                }
                .font(DSFont.subheadline)
                .foregroundColor(DSColor.accent)
                if let reason = section.errorReason, !reason.isEmpty {
                    Text(reason)
                        .font(DSFont.caption2)
                        .foregroundColor(DSColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, DSSpacing.lg)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, DSSpacing.lg)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Featured card (horizontal carousel item)

private struct DiscoverFeaturedCard: View {
    let book: OnlineBook

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            DiscoverCoverImage(book: book)
                .frame(width: 104, height: 138)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
            Text(book.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DSColor.textPrimary)
                .lineLimit(1)
            if !introText.isEmpty {
                Text(introText)
                    .font(DSFont.caption2)
                    .foregroundColor(DSColor.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(width: 104, alignment: .leading)
    }

    private var introText: String {
        ReaderHTMLUtilities.displayText(fromHTMLFragment: book.intro)
    }
}

// MARK: - Ranked row

private struct DiscoverRankedRow: View {
    let rank: Int
    let book: OnlineBook

    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.md) {
            rankBadge
            DiscoverCoverImage(book: book)
                .frame(width: 52, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.sm))

            VStack(alignment: .leading, spacing: 3) {
                Text(book.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DSColor.textPrimary)
                    .lineLimit(1)
                if !book.author.isEmpty {
                    Text(book.author)
                        .font(DSFont.caption)
                        .foregroundColor(DSColor.textSecondary)
                        .lineLimit(1)
                }
                if !introText.isEmpty {
                    Text(introText)
                        .font(DSFont.caption)
                        .foregroundColor(DSColor.textSecondary.opacity(0.85))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DSSpacing.md)
        .contentShape(Rectangle())
    }

    private var introText: String {
        ReaderHTMLUtilities.displayText(fromHTMLFragment: book.intro)
    }

    private var rankBadge: some View {
        Text("\(rank)")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundColor(rank <= 3 ? .white : DSColor.textSecondary)
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.sm)
                    .fill(rankColor)
            )
            .padding(.top, 2)
    }

    private var rankColor: Color {
        switch rank {
        case 1: return DSColor.destructive
        case 2: return DSColor.warning
        case 3: return Color.orange.opacity(0.7)
        default: return Color(.systemGray5)
        }
    }
}

// MARK: - Cover image (shared)

/// Async book cover with a graceful gradient/initial placeholder.
struct DiscoverCoverImage: View {
    let book: OnlineBook

    var body: some View {
        AsyncImage(url: URL(string: book.coverUrl)) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        let palette = DSColor.coverGradients
        let gradient = palette[abs(book.name.hashValue) % palette.count]
        return LinearGradient(
            colors: gradient,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Text(String(book.name.prefix(1)))
                .font(DSFont.headline)
                .foregroundColor(.white.opacity(0.9))
        )
    }
}

// MARK: - Category detail ("查看全部")

/// Full list of one explore category, reached from a section's 查看全部 link.
private struct DiscoverCategoryView: View {
    let section: DiscoverShowcaseSection
    let onOpenBook: (OnlineBook) -> Void

    var body: some View {
        List {
            ForEach(Array(section.books.enumerated()), id: \.element.id) { index, book in
                Button { onOpenBook(book) } label: {
                    DiscoverRankedRow(rank: index + 1, book: book)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .navigationTitle(section.title)
        .toolbarTitleDisplayMode(.inlineLarge)
    }
}

// MARK: - Preview

#Preview {
    let vm = DiscoverViewModel()
    return NavigationStack {
        DiscoverShowcaseView(discover: vm, onOpenBook: { _ in })
            .navigationTitle("探索")
            .toolbarTitleDisplayMode(.inlineLarge)
    }
}
