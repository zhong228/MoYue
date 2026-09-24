import SwiftUI

struct AICustomPromptListView: View {
    @ObservedObject private var store = AICustomPromptStore.shared
    @State private var editing: AICustomPrompt?
    @State private var error: String?

    var body: some View {
        List {
            if let failure = error ?? store.failure {
                Text(failure).foregroundStyle(DSColor.destructive)
            }
            ForEach(store.prompts) { prompt in
                Button { editing = prompt } label: {
                    LabeledContent(prompt.title, value: prompt.isEnabled ? prompt.context.title : localized("停用"))
                }
            }
            .onDelete { indices in update { $0.remove(atOffsets: indices) } }
            .onMove { source, destination in update { $0.move(fromOffsets: source, toOffset: destination) } }
            Button(localized("新增提示詞"), systemImage: "plus") {
                editing = .init(title: "", instruction: "")
            }
        }
        .navigationTitle(localized("自訂提示詞"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .toolbar { EditButton() }
        .sheet(item: $editing) { prompt in
            AICustomPromptEditor(prompt: prompt) { value in
                var values = store.prompts
                if let index = values.firstIndex(where: { $0.id == value.id }) { values[index] = value }
                else { values.append(value) }
                try store.save(values)
            }
        }
    }

    private func update(_ change: (inout [AICustomPrompt]) -> Void) {
        var values = store.prompts
        change(&values)
        do { try store.save(values) } catch { self.error = error.localizedDescription }
    }
}

private struct AICustomPromptEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var prompt: AICustomPrompt
    let save: (AICustomPrompt) throws -> Void
    @State private var failure: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(localized("名稱"), text: $prompt.title)
                    Picker(localized("使用情境"), selection: $prompt.context) {
                        ForEach(AICustomPrompt.Context.allCases, id: \.self) { context in
                            Text(context.title).tag(context)
                        }
                    }
                    Toggle(localized("啟用"), isOn: $prompt.isEnabled)
                }
                Section {
                    TextEditor(text: $prompt.instruction)
                        .frame(minHeight: DSLayout.minimumTapTarget * 4)
                        .accessibilityLabel(localized("提示詞內容"))
                } header: { Text(localized("提示詞內容")) }
                footer: { Text(localized("選文與閱讀內容會自動帶入，仍受對話的已讀範圍限制。")).dsSectionFooter() }
            }
            .alert(localized("無法儲存"), isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button(localized("確定"), role: .cancel) { failure = nil }
            } message: { Text(failure ?? "") }
            .navigationTitle(localized("自訂提示詞"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(localized("取消"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        do { try save(prompt); dismiss() } catch { failure = error.localizedDescription }
                    } label: { Image(systemName: "checkmark") }
                        .accessibilityLabel(localized("儲存"))
                        .disabled(prompt.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || prompt.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview { NavigationStack { AICustomPromptListView() } }
