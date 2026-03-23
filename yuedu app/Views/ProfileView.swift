import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: BookStore
    @ObservedObject private var gs = GlobalSettings.shared
    @State private var showSourceList = false
    @State private var showDownloadManager = false

    var body: some View {
        NavigationView {
            AdaptiveContentContainer(maxWidth: 760) {
                Form {
                    // ── App 語言 ──
                    Section(header: Text(gs.t("App 語言"))) {
                        Picker("", selection: $gs.appLanguage) {
                            ForEach(AppLanguage.allCases, id: \.self) { lang in
                                Text(lang.rawValue).tag(lang)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // ── 書源管理 ──
                    Section(header: Text(gs.t("書源管理"))) {
                        DSSettingsRow(
                            icon: "books.vertical.fill",
                            title: gs.t("管理書源"),
                            action: { showSourceList = true }
                        )

                        DSSettingsRow(
                            icon: "arrow.down.circle.fill",
                            title: gs.t("下載管理"),
                            detail: "\(downloadedBooksCount) \(gs.t("本"))",
                            action: { showDownloadManager = true }
                        )
                    }

                    // ── 關於 ──
                    Section(header: Text(gs.t("關於"))) {
                        HStack {
                            Text(gs.t("版本"))
                            Spacer()
                            Text("1.0.0").foregroundColor(DSColor.textSecondary)
                        }
                        HStack {
                            Text(gs.t("支援格式"))
                            Spacer()
                            Text(gs.t("TXT、EPUB、Web、書源")).foregroundColor(DSColor.textSecondary)
                        }
                        HStack {
                            Text(gs.t("反饋"))
                            Spacer()
                            Text(gs.t("請郵箱聯繫：<r3212239269@gmail.com>")).foregroundColor(DSColor.textSecondary)
                        }
                    }
                }
            }
            .navigationTitle(gs.t("設定"))
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showSourceList) {
                AdaptiveSheetContainer(maxWidth: 820) {
                    BookSourceListView()
                        .environmentObject(store)
                }
            }
            .sheet(isPresented: $showDownloadManager) {
                AdaptiveSheetContainer(maxWidth: 820) {
                    DownloadManagementView()
                        .environmentObject(store)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var downloadedBooksCount: Int {
        store.books.filter { $0.isOnline && $0.offlineDownloadState == .available }.count
    }
}
