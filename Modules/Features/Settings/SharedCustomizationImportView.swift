import SwiftUI

struct SharedCustomizationImportView: View {
    let document: SharedCustomizationDocument
    @Environment(\.dismiss) private var dismiss
    @State private var pendingPlan: SharedCustomizationImportService.Plan?
    @State private var result: String?
    @State private var failed = false
    @State private var started = false

    var body: some View {
        NavigationStack {
            Form {
                if let result {
                    Section {
                        Text(result)
                            .textSelection(.enabled)
                    } header: {
                        Text(localized(failed ? "匯入失敗" : "匯入成功"))
                    }
                } else if let plan = pendingPlan {
                    Section {
                        Button(localized("套用")) { apply(plan, includeOverlayLayout: true) }
                        if plan.canSkipOverlayLayout {
                            Button(localized("略過")) { apply(plan, includeOverlayLayout: false) }
                        }
                        Button(localized("取消"), role: .cancel) { dismiss() }
                    } header: {
                        Text(localized("套用匯入的頁首頁尾？"))
                    } footer: {
                        Text(localized(plan.canSkipOverlayLayout
                            ? "這會取代目前的頁首頁尾組件、位置與正文保留空間。選擇「略過」會匯入外觀包的其他部分。"
                            : "這會取代目前的頁首頁尾組件、位置與正文保留空間。"))
                            .dsSectionFooter()
                    }
                } else {
                    ProgressView(localized("匯入中，請稍候…"))
                }
            }
            .navigationTitle(localized("匯入"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("關閉"), systemImage: "xmark") { dismiss() }
                        .disabled(result == nil && pendingPlan == nil)
                }
            }
            .task {
                guard !started else { return }
                started = true
                do {
                    let plan = try await SharedCustomizationImportService.load(document)
                    if plan.overwritesOverlayLayout {
                        pendingPlan = plan
                    } else {
                        result = try await SharedCustomizationImportService.apply(plan, includeOverlayLayout: false)
                    }
                } catch { report(error) }
            }
        }
    }

    private func apply(_ plan: SharedCustomizationImportService.Plan, includeOverlayLayout: Bool) {
        pendingPlan = nil
        Task {
            do {
                result = try await SharedCustomizationImportService.apply(plan, includeOverlayLayout: includeOverlayLayout)
            } catch { report(error) }
        }
    }

    private func report(_ error: Error) {
        failed = true
        if let themeError = error as? AppearanceThemeImportError {
            result = localized(themeError.messageKey)
        } else if let localizedError = error as? any LocalizedError,
                  let description = localizedError.errorDescription {
            result = description
        } else {
            result = localized("匯入主題失敗。")
        }
    }
}

#Preview {
    SharedCustomizationImportView(document: .init(data: Data(), kind: .appearanceJSON))
}
