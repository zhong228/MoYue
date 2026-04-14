import SwiftUI

struct RSSListView: View {
    @StateObject private var store = RSSStore.shared
    @ObservedObject private var gs = GlobalSettings.shared

    @State private var showAddSheet = false
    @State private var newName = ""
    @State private var newURL = ""

    var body: some View {
        List {
            ForEach(store.sources.sorted(by: { $0.sortOrder < $1.sortOrder })) { source in
                NavigationLink(destination: RSSFeedView(source: source)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.name)
                            .foregroundColor(DSColor.textPrimary)
                        Text(source.url)
                            .font(.caption)
                            .foregroundColor(DSColor.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 4)
                }
            }
            .onDelete(perform: store.removeSource)
        }
        .navigationTitle(gs.t("RSS 訂閱"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    newName = ""
                    newURL = ""
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(DSColor.accent)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddRSSSourceSheet(isPresented: $showAddSheet, store: store, gs: gs)
        }
    }
}

// MARK: - Add Source Sheet

private struct AddRSSSourceSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var store: RSSStore
    @ObservedObject var gs: GlobalSettings

    @State private var name = ""
    @State private var url = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(gs.t("來源名稱"))) {
                    TextField(gs.t("例如：科技新聞"), text: $name)
                }
                Section(header: Text(gs.t("RSS 網址"))) {
                    TextField("https://", text: $url)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }
            .navigationTitle(gs.t("新增 RSS 訂閱"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(gs.t("取消")) {
                        isPresented = false
                    }
                    .foregroundColor(DSColor.accent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(gs.t("新增")) {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedName.isEmpty, !trimmedURL.isEmpty else { return }
                        let source = RSSSource(
                            name: trimmedName,
                            url: trimmedURL,
                            sortOrder: store.sources.count
                        )
                        store.addSource(source)
                        isPresented = false
                    }
                    .foregroundColor(DSColor.accent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
