import SwiftUI

struct AIAssistantPanelView: View {
    let bookID: UUID
    let bookTitle: String
    let adapter: AIBookContentAdapter
    let progress: Double
    let onOpenCitation: (LLMCitation, AIReadingBoundary) -> Void
    var launch: AIReadingLaunch? = nil
    var sourceIdentity: String? = nil
    var isSourceReady = true
    var prepareContent: AIReadingConversation.Prepare = { $0 }
    var onSourcePrepared: (AIBookContentAdapter) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var conversation = AIReadingConversation()
    @ObservedObject private var prompts = AICustomPromptStore.shared
    @State private var draft = ""
    private enum SecondaryScreen: Hashable {
        case characters, settings, prompts, status
    }
    @State private var showMore = false
    @State private var pendingScreen: SecondaryScreen?
    @State private var navigationPath: [SecondaryScreen] = []
    @State private var showHistory = false
    @State private var selectedCitation: LLMCitation?
    @State private var profiles: [AIServiceProfile] = []
    @State private var settingsError: String?
    @State private var launchedID: UUID?
    @State private var detent: PresentationDetent = .medium
    @State private var followsLatest = true
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                if profiles.isEmpty {
                    ContentUnavailableView {
                        Label(localized("尚未設定 AI 服務"), systemImage: "sparkles")
                    } description: {
                        Text(settingsError ?? localized("填入自己的 API 服務，即可開始閱讀問答。"))
                    } actions: {
                        Button(localized("前往設定")) { openScreen(.settings) }
                    }
                } else {
                    transcript
                    composer
                }
            }
            .themedAppSurface(for: .settings)
            .navigationTitle(bookTitle)
            .toolbarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            // The chooser finishes dismissing before the shared navigation path changes.
            .sheet(isPresented: $showMore, onDismiss: {
                if let pendingScreen { openScreen(pendingScreen) }
                pendingScreen = nil
            }) {
                DismissalSequencedActionChooser(title: localized("更多"), actions: [
                    .init(route: SecondaryScreen.characters, title: localized("書中人物"), systemImage: "person.2"),
                    .init(route: .settings, title: localized("AI 助手設定"), systemImage: "gearshape"),
                    .init(route: .prompts, title: localized("自訂提示詞"), systemImage: "text.badge.plus"),
                    .init(route: .status, title: localized("AI 狀態與診斷"), systemImage: "info.circle")
                ], onSelect: { pendingScreen = $0 })
            }
            .navigationDestination(for: SecondaryScreen.self) { screen in
                switch screen {
                case .settings: AISettingsView(embedded: true)
                case .characters: AIBookCharactersView(adapter: currentSource, progress: progress, onOpenCitation: { onOpenCitation($0, currentSource.boundary()) })
                case .prompts: AICustomPromptListView()
                case .status: AIStatusView(adapter: currentSource)
                }
            }
            .sheet(isPresented: $showHistory) {
                NavigationStack {
                    AIChatHistoryView(sessions: conversation.history, currentID: conversation.session.id,
                        onSelect: { conversation.select($0); showHistory = false },
                        onDelete: { conversation.delete($0) },
                        onNew: { conversation.startNew(); showHistory = false })
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { showHistory = false } label: { Image(systemName: "xmark") }
                                .accessibilityLabel(localized("關閉"))
                        }
                    }
                }
            }
            .sheet(isPresented: Binding(get: { selectedCitation != nil }, set: { if !$0 { selectedCitation = nil } })) {
                if let citation = selectedCitation { citationPreview(citation) }
            }
        }
        // Reader chrome uses the book's ink color; assistant controls follow app UI colors.
        .tint(DSColor.accent)
        .presentationDetents(sizeClass == .regular ? [.large] : [.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onChange(of: inputFocused) { _, focused in if focused { detent = .large } }
        .onAppear {
            if sizeClass == .regular || dynamicTypeSize.isAccessibilitySize { detent = .large }
            reloadProfiles(); configure()
        }
        .onChange(of: navigationPath) { _, path in
            if path.isEmpty { reloadProfiles() }
        }
        .onChange(of: bookID) { _, _ in configure() }
        .onChange(of: sourceIdentity) { _, _ in configure() }
        .onChange(of: adapter.contentFingerprint) { _, _ in configure() }
        .onChange(of: adapter.boundary()) { _, _ in configure() }
        .onChange(of: isSourceReady) { _, _ in configure() }
        .onChange(of: conversation.source?.contentFingerprint) { _, _ in
            if let source = conversation.source { onSourcePrepared(source) }
        }
        .onDisappear { conversation.cancel() }
    }

    private func openScreen(_ screen: SecondaryScreen) {
        // Settings and reference lists need the full readable height, including when
        // returning from a service editor that displayed the keyboard.
        detent = .large
        navigationPath.append(screen)
    }

    private var currentSource: AIBookContentAdapter { conversation.source ?? adapter }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .accessibilityLabel(localized("關閉"))
        }
        ToolbarItem(placement: .primaryAction) {
            Button { showHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                .accessibilityLabel(localized("對話列表"))
        }
        ToolbarItem(placement: .primaryAction) {
            Button { conversation.startNew(); draft = "" } label: { Image(systemName: "square.and.pencil") }
                .accessibilityLabel(localized("新對話"))
        }
        ToolbarItem(placement: .primaryAction) {
            if #available(iOS 18.0, *) {
                Menu {
                    Button(localized("書中人物"), systemImage: "person.2") { openScreen(.characters) }
                    Button(localized("AI 助手設定"), systemImage: "gearshape") { openScreen(.settings) }
                    Button(localized("自訂提示詞"), systemImage: "text.badge.plus") { openScreen(.prompts) }
                    Button(localized("AI 狀態與診斷"), systemImage: "info.circle") { openScreen(.status) }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel(localized("更多"))
            } else {
                Button { showMore = true } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel(localized("更多"))
            }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DSSpacing.lg) {
                    if conversation.session.isEmpty {
                        ContentUnavailableView(localized("一起讀懂這本書"), systemImage: "text.bubble",
                            description: Text(localized("選取原文來解釋或翻譯，也可以直接提問。")))
                    }
                    ForEach(conversation.session.messages) { message in
                        messageView(message).id(message.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                        .onAppear { followsLatest = true }
                        .onDisappear { followsLatest = false }
                }
                .padding(DSSpacing.lg)
            }
            .accessibilityIdentifier("ai.chat.transcript")
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: conversation.session.messages.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: conversation.session.messages.last?.text) { _, _ in
                if followsLatest { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: conversation.isBusy) { _, busy in
                if !busy && followsLatest { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    @ViewBuilder private func messageView(_ message: AIChatMessage) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: DSSpacing.xl)
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    if let selection = message.selection {
                        Text(selection.displayText).font(DSFont.footnote).foregroundStyle(DSColor.textSecondary).lineLimit(3)
                    }
                    Text(message.text).textSelection(.enabled)
                }
                .padding(DSSpacing.md)
                .background(DSColor.surfaceTertiary, in: RoundedRectangle(cornerRadius: DSRadius.md))
            }
        } else {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                if let metadata = message.provenance, let boundary = conversation.boundary, !boundary.contains(metadata.boundary) {
                    Text(localized("此回覆超出目前可確認的來源或閱讀範圍，已暫時隱藏。"))
                        .font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                } else {
                    if !message.text.isEmpty { AIAnswerMarkdownView(text: message.text) }
                    if message.isPending {
                        HStack { ProgressView(); Text(conversation.stage.label).font(DSFont.footnote) }
                            .accessibilityElement(children: .combine)
                    }
                    if let error = message.errorMessage {
                        Label(error, systemImage: "exclamationmark.circle").font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                        if message.id == conversation.session.messages.last?.id {
                            Button(localized("重試這個問題")) { conversation.retry(prepare: prepareContent) }.disabled(conversation.isBusy)
                        }
                    }
                    if !message.citations.isEmpty {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(Array(message.citations.enumerated()), id: \.element.chunkID) { index, citation in
                                    Button { selectedCitation = citation } label: {
                                        Label("\(index + 1) · \(citation.sectionTitle ?? localized("原文"))", systemImage: "quote.opening")
                                            .font(DSFont.footnote)
                                    }.buttonStyle(.bordered).accessibilityIdentifier("ai.citation.\(index)")
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                    if !message.isPending && !message.text.isEmpty {
                        HStack {
                            Button { UIPasteboard.general.string = message.text } label: { Label(localized("複製"), systemImage: "doc.on.doc") }
                            if !message.hasEvidence { Text(localized("未附書中引用")).foregroundStyle(DSColor.textSecondary) }
                        }.font(DSFont.footnote)
                        if let notices = message.notices, !notices.isEmpty {
                            DisclosureGroup(localized("回答範圍")) {
                                ForEach(notices, id: \.self) { Text($0).font(DSFont.footnote).foregroundStyle(DSColor.textSecondary) }
                            }.font(DSFont.footnote)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            if let selection = conversation.selection {
                HStack(alignment: .top) {
                    Label(selection.displayText, systemImage: "text.quote").font(DSFont.footnote).lineLimit(3)
                    Spacer()
                    Button { conversation.selection = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .frame(minWidth: DSLayout.minimumTapTarget, minHeight: DSLayout.minimumTapTarget)
                        .accessibilityLabel(localized("移除選文"))
                }
            }
            HStack {
                modelMenu
                Spacer()
                Picker(localized("閱讀範圍"), selection: Binding(get: { conversation.wholeBook }, set: { conversation.setWholeBook($0) })) {
                    Text(localized("已讀")).tag(false)
                    Text(localized("全書")).tag(true)
                }.pickerStyle(.menu)
            }.font(DSFont.footnote)
            if conversation.wholeBook {
                Text(localized("全書模式可能包含尚未讀到的情節。")).font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
            }
            ScrollView(.horizontal) {
                HStack(spacing: DSSpacing.sm) {
                    ForEach(conversation.selection == nil ? [AIReadingAction.chapterSummary, .recap] : [.explain, .translate], id: \.self) { action in
                        Button(action.title) { sendAction(action) }.buttonStyle(.bordered)
                    }
                    ForEach(prompts.prompts.filter { $0.isEnabled && ($0.context != .selection || conversation.selection != nil) }) { prompt in
                        Button(prompt.title) { conversation.send(prompt.title, action: .custom, custom: prompt, prepare: prepareContent) }
                            .buttonStyle(.bordered)
                    }
                }.disabled(conversation.isBusy || !isSourceReady)
            }.scrollIndicators(.hidden)
            HStack(alignment: .bottom) {
                TextField(localized("問一個問題"), text: $draft, axis: .vertical)
                    .accessibilityIdentifier("ai.chat.input")
                    .lineLimit(1...5).focused($inputFocused)
                    .frame(minHeight: DSLayout.minimumTapTarget)
                Button {
                    if conversation.isBusy { conversation.cancel() }
                    else {
                        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !question.isEmpty else { return }
                        conversation.send(question, prepare: prepareContent)
                        draft = ""
                        if dynamicTypeSize.isAccessibilitySize { inputFocused = false }
                    }
                } label: {
                    Image(systemName: conversation.isBusy ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(DSFont.title2)
                        .frame(minWidth: DSLayout.minimumTapTarget, minHeight: DSLayout.minimumTapTarget)
                }
                .accessibilityLabel(conversation.isBusy ? localized("停止") : localized("送出"))
                .disabled(!conversation.isBusy && (!isSourceReady || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
            if !isSourceReady { ProgressView(localized("準備閱讀內容…")).font(DSFont.footnote) }
        }
        .padding(DSSpacing.md)
        .background(DSColor.surface)
    }

    private var modelMenu: some View {
        Menu {
            ForEach(profiles) { profile in
                Section(profile.name) {
                    ForEach(Array(Set(profile.models + [profile.configuration.defaultModel])).sorted(), id: \.self) { model in
                        Button(model) { conversation.setModel(profile: profile, model: model) }
                    }
                }
            }
        } label: {
            Label(conversation.session.model ?? profiles.first(where: { $0.id == AIProviderStore.shared.activeID })?.configuration.defaultModel ?? profiles.first?.configuration.defaultModel ?? localized("選擇模型"), systemImage: "cpu")
                .lineLimit(1)
                .frame(minHeight: DSLayout.minimumTapTarget, alignment: .leading)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(localized("選擇模型"))
    }

    private func citationPreview(_ citation: LLMCitation) -> some View {
        NavigationStack {
            List {
                Section { Text(citation.quote).textSelection(.enabled) } header: { Text(citation.sectionTitle ?? localized("原文")) }
            }
            .navigationTitle(localized("原文引用"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(localized("跳到原文"), systemImage: "arrow.turn.down.right") {
                        selectedCitation = nil
                        onOpenCitation(citation, currentSource.boundary(wholeBook: conversation.wholeBook))
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { selectedCitation = nil } label: { Image(systemName: "xmark") }.accessibilityLabel(localized("關閉"))
                }
            }
        }
    }

    private func reloadProfiles() {
        do { profiles = try AIProviderStore.shared.profiles(); settingsError = nil }
        catch { settingsError = error.localizedDescription }
    }
    private func configure() {
        guard isSourceReady else { conversation.cancel(); return }
        conversation.open(source: adapter, sourceIdentity: sourceIdentity)
        guard let launch, launchedID != launch.id else { return }
        launchedID = launch.id
        conversation.selection = launch.selection
        if launch.action != .question { sendAction(launch.action) }
    }
    private func sendAction(_ action: AIReadingAction) { conversation.send(action.title, action: action, prepare: prepareContent) }

    static func formatted(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
    static func quoteText(_ citation: LLMCitation) -> String { citation.quote }
}

struct AIChatHistoryView: View {
    let sessions: [AIChatSession]
    let currentID: UUID
    let onSelect: (AIChatSession) -> Void
    let onDelete: (UUID) -> Void
    let onNew: () -> Void
    var body: some View {
        List {
            Button(localized("新對話"), systemImage: "square.and.pencil", action: onNew)
            ForEach(sessions) { session in
                Button { onSelect(session) } label: {
                    LabeledContent(session.title) {
                        if session.id == currentID { Image(systemName: "checkmark").accessibilityLabel(localized("已選取")) }
                    }
                }
                .swipeActions { Button(localized("刪除"), role: .destructive) { onDelete(session.id) } }
            }
        }
        .navigationTitle(localized("對話列表"))
        .toolbarTitleDisplayMode(.inline)
    }
}

private struct AIAnswerMarkdownView: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            ForEach(Array(AIAnswerMarkdown.blocks(text).enumerated()), id: \.offset) { _, block in
                switch block.kind {
                case .heading:
                    Text(AIAssistantPanelView.formatted(block.text)).font(DSFont.headline).accessibilityAddTraits(.isHeader)
                case .code, .table:
                    ScrollView(.horizontal) {
                        Text(block.text).font(DSFont.body.monospaced()).fixedSize(horizontal: true, vertical: false)
                            .padding(DSSpacing.sm)
                    }.background(DSColor.surfaceTertiary, in: RoundedRectangle(cornerRadius: DSRadius.sm))
                case .quote:
                    HStack(alignment: .top, spacing: DSSpacing.sm) {
                        Image(systemName: "quote.opening").foregroundStyle(DSColor.textSecondary).accessibilityHidden(true)
                        Text(AIAssistantPanelView.formatted(block.text)).font(DSFont.body)
                    }
                case .paragraph, .list:
                    Text(AIAssistantPanelView.formatted(block.text)).font(DSFont.body)
                }
            }
        }.textSelection(.enabled)
    }
}

#Preview {
    AIAssistantPanelView(bookID: UUID(), bookTitle: "閱讀中的書", adapter: .init(bookID: UUID(), chapters: [], textForChapter: { _ in nil }), progress: 0.4, onOpenCitation: { _, _ in })
}
