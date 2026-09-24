import SwiftUI

struct AIBookCharactersView: View {
    let adapter: AIBookContentAdapter
    let progress: Double
    var onOpenCitation: ((LLMCitation) -> Void)? = nil
    @State private var query = ""
    @State private var snapshot = AIBookCharactersSnapshot()
    @State private var error: String?
    @State private var loading = true
    @ObservedObject private var memory = AICharacterMemoryService.shared

    var body: some View {
        List {
            Section {
                NavigationLink(localized("整理已讀人物")) { AICharacterMemoryView(adapter: adapter, onOpenCitation: onOpenCitation) }
            }
            if loading { ProgressView(localized("載入中…")) }
            if let error { Text(error).foregroundStyle(DSColor.destructive) }
            if !loading && snapshot.memory.cards.isEmpty && snapshot.profiles.isEmpty {
                ContentUnavailableView(localized("尚無人物資料"), systemImage: "person.2",
                    description: Text(localized("整理已讀內容，查看人物與原文依據。")))
            }
            Section {
                ForEach(snapshot.memory.cards.filter { query.isEmpty || $0.names.contains(where: { $0.localizedCaseInsensitiveContains(query) }) }) { card in
                    NavigationLink(card.names.joined(separator: "、")) {
                        AIMemoryCardView(entityID: card.entityIDs.sorted().first ?? card.id,
                            source: adapter, boundary: adapter.boundary(), onOpenCitation: onOpenCitation, showsDone: false)
                    }
                }
            } header: { if !snapshot.memory.cards.isEmpty { Text(localized("人物經歷")) } }
            Section {
                ForEach(snapshot.profiles.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }, id: \.name) { profile in
                    NavigationLink(profile.name) {
                        List {
                            if let role = profile.role { LabeledContent(localized("身分"), value: role) }
                            Text(profile.summary).textSelection(.enabled)
                            ForEach(profile.relationships, id: \.self) { Text($0) }
                            NavigationLink(localized("人物卡與朗讀別稱")) {
                                AICharacterListView(bookID: adapter.chunkBookID, adapter: adapter, progress: progress)
                            }
                        }
                        .navigationTitle(profile.name).toolbarTitleDisplayMode(.inline)
                    }
                }
                NavigationLink(localized("人物卡與朗讀別稱")) {
                    AICharacterListView(bookID: adapter.chunkBookID, adapter: adapter, progress: progress)
                }
            } header: { Text(localized("已保存人物卡")) }
        }
        .searchable(text: $query, prompt: localized("搜尋目前範圍的人物"))
        .navigationTitle(localized("書中人物"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .task(id: "\(adapter.contentFingerprint):\(memory.revisions[adapter.chunkBookID] ?? 0)") {
            loading = true
            do { snapshot = try await AIAssistantService.shared.characters(source: adapter); error = nil }
            catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}

#Preview { NavigationStack { AIBookCharactersView(adapter: .init(bookID: UUID(), chapters: [], textForChapter: { _ in nil }), progress: 0) } }
