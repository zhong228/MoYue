import SwiftUI
import Combine

struct LanServerView: View {
    @StateObject private var server = LanWebServer.shared
    @ObservedObject private var gs = GlobalSettings.shared
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BookStore

    var body: some View {
        List {
            // MARK: Status section
            Section {
                HStack(spacing: 12) {
                    Circle()
                        .fill(server.isRunning ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                    Text(server.isRunning ? gs.t("運行中") : gs.t("已停止"))
                        .foregroundColor(server.isRunning ? .green : DSColor.textSecondary)
                    Spacer()
                }
                .padding(.vertical, 2)

                if server.isRunning && !server.localIPAddress.isEmpty {
                    HStack {
                        Text(gs.t("地址"))
                            .foregroundColor(DSColor.textSecondary)
                        Spacer()
                        Text("http://\(server.localIPAddress):\(server.port)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(DSColor.accent)
                            .textSelection(.enabled)
                    }
                }
            } header: {
                Text(gs.t("服務狀態"))
            }

            // MARK: Toggle button
            Section {
                Button {
                    if server.isRunning {
                        server.stop()
                    } else {
                        server.bookProvider = store
                        server.start()
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text(server.isRunning ? gs.t("停止服務") : gs.t("啟動服務"))
                            .fontWeight(.semibold)
                            .foregroundColor(server.isRunning ? .red : DSColor.accent)
                        Spacer()
                    }
                }
            }

            // MARK: API endpoints
            Section {
                endpointRow(method: "GET", path: "/", description: gs.t("書架列表"))
                endpointRow(method: "GET", path: "/book/:id", description: gs.t("書籍詳情"))
                endpointRow(method: "GET", path: "/api/sources", description: gs.t("書源列表"))
                endpointRow(method: "GET", path: "/health", description: gs.t("健康檢查"))
            } header: {
                Text(gs.t("可用接口"))
            }
        }
        .navigationTitle(gs.t("局域網服務"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            server.bookProvider = store
        }
    }

    // MARK: - Helpers

    private func endpointRow(method: String, path: String, description: String) -> some View {
        HStack(spacing: 10) {
            Text(method)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DSColor.accent.opacity(0.15))
                .foregroundColor(DSColor.accent)
                .cornerRadius(4)
            Text(path)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(DSColor.textPrimary)
            Spacer()
            Text(description)
                .font(.caption)
                .foregroundColor(DSColor.textSecondary)
        }
        .padding(.vertical, 2)
    }
}
