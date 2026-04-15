import SwiftUI
import AVFoundation

struct TTSSettingsView: View {
    @ObservedObject private var gs = GlobalSettings.shared
    @StateObject private var testCoordinator = TTSCoordinator()
    @State private var isTesting = false

    var body: some View {
        Form {
            // ── 引擎選擇 ──
            Section(header: Text(gs.t("語音引擎"))) {
                Picker(gs.t("引擎"), selection: $gs.ttsEngine) {
                    ForEach(GlobalSettings.TTSEngineType.allCases, id: \.self) { type in
                        Text(gs.t(type.displayName)).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }

            // ── HTTP TTS 設定（只在 HTTP 模式顯示） ──
            if gs.ttsEngine == .http {
                Section(header: Text(gs.t("HTTP TTS URL 模板"))) {
                    TextEditor(text: $gs.httpTtsUrlTemplate)
                        .frame(minHeight: 80)
                        .font(.system(.footnote, design: .monospaced))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(gs.t("支援的佔位符："))
                            .font(.caption)
                            .foregroundColor(DSColor.textSecondary)
                        placeholderRow("{{text}}", desc: gs.t("段落文字（URL 編碼）"))
                        placeholderRow("{{title}}", desc: gs.t("章節標題（URL 編碼）"))
                        placeholderRow("{{speakSpeed}}", desc: gs.t("語速，範圍 0.10–0.65"))
                    }
                    .padding(.vertical, 4)

                    // 測試播放
                    Button {
                        testPlay()
                    } label: {
                        HStack {
                            Image(systemName: isTesting ? "stop.circle" : "play.circle")
                            Text(isTesting ? gs.t("停止測試") : gs.t("測試播放"))
                        }
                    }
                    .disabled(gs.httpTtsUrlTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationTitle(gs.t("語音朗讀設定"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            testCoordinator.stop()
            isTesting = false
        }
    }

    // MARK: - Private

    private func placeholderRow(_ placeholder: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(placeholder)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(DSColor.accent)
            Text("—")
                .font(.caption)
                .foregroundColor(DSColor.textSecondary)
            Text(desc)
                .font(.caption)
                .foregroundColor(DSColor.textSecondary)
        }
    }

    private func testPlay() {
        if isTesting {
            testCoordinator.stop()
            isTesting = false
        } else {
            testCoordinator.onStop = { DispatchQueue.main.async { self.isTesting = false } }
            testCoordinator.speak(text: "這是一段測試文字，用於確認 HTTP TTS 引擎設定是否正確。", title: "測試")
            isTesting = true
        }
    }
}
