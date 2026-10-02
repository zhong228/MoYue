import Combine
import SwiftUI

// MARK: - A source's discover page

/// One explore source's whole discover page, opened from 探索's list: every category the
/// source lists with the source's own filters above them — as Apple Books lays out a
/// store, or as Legado lists them (探索設定 › 書源頁佈局). 設定 opens the source's login
/// page — where Legado sources keep their settings.
struct ExploreSourcePage: View {
    @StateObject private var discover: DiscoverViewModel
    @State private var showsLogin = false
    @AppStorage(ExploreSettings.sourcePageLayoutKey) private var layout = ExploreSourcePageLayout.default
    private let source: BookSource
    /// Opens a category that is a web page (a source's `java.startBrowser` link).
    let onNavigate: (String) -> Void

    init(source: BookSource, onNavigate: @escaping (String) -> Void) {
        self.source = source
        self.onNavigate = onNavigate
        _discover = StateObject(wrappedValue: DiscoverViewModel(source: source))
    }

    /// The source as the store has it now; an edit gives it a new session.
    private var currentSource: BookSource { discover.selectedSource ?? source }

    private var hasLogin: Bool {
        !currentSource.loginUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            switch layout {
            case .magazine:
                DiscoverShowcaseView(discover: discover, onOpenPage: onNavigate)
            case .list:
                DiscoverListLayoutView(discover: discover, onOpenPage: onNavigate)
            }
        }
            .background(PageBackgroundView(scope: .explore).ignoresSafeArea())
            .pageBackgroundToolbar(for: .explore)
            .navigationTitle(currentSource.bookSourceName)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                if hasLogin {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showsLogin = true } label: {
                            Label(localized("設定"), systemImage: "gearshape")
                        }
                    }
                }
            }
            .sheet(isPresented: $showsLogin) {
                BookSourceLoginSheet(source: currentSource) { showsLogin = false }
            }
            .onAppear { discover.refreshSources() }
            .onReceive(
                NotificationCenter.default.publisher(for: .bookSourceLoginInfoDidChange)
                    // Source JS posts from its worker; only UI delivery moves to main.
                    .receive(on: DispatchQueue.main)
            ) { notification in
                guard notification.userInfo?["sourceURL"] as? String == source.bookSourceUrl else { return }
                // The source's exploreUrl and header rule may both depend on the newly
                // stored credentials. Re-run the source instead of reusing the pre-login
                // category cache.
                discover.reload(forceRefresh: true)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .bookSourceUserVariableDidChange)
                    .receive(on: DispatchQueue.main)
            ) { notification in
                guard notification.userInfo?["sourceURL"] as? String == source.bookSourceUrl else { return }
                // A bare token is a valid Legado source variable. The previous snapshot
                // may have been produced before it existed, so saving the editor must
                // invalidate that live snapshot as well as the key-addressed category cache.
                discover.reload(forceRefresh: true)
            }
    }
}

#Preview {
    var source = BookSource()
    source.bookSourceName = "範例書源"
    source.bookSourceUrl = "https://example.com"
    source.loginUrl = "https://example.com/login"
    return NavigationStack {
        ExploreSourcePage(source: source, onNavigate: { _ in })
    }
}
