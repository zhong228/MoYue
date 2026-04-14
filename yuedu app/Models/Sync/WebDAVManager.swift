import Foundation
import Combine

// MARK: - WebDAV 錯誤類型

enum WebDAVError: LocalizedError {
    case invalidURL
    case authenticationFailed
    case connectionFailed(Int)
    case noData
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .invalidURL:           return "伺服器網址格式無效"
        case .authenticationFailed: return "認證失敗，請確認帳號和密碼"
        case .connectionFailed(let code): return "連線失敗（HTTP \(code)）"
        case .noData:               return "伺服器未返回資料"
        case .fileNotFound:         return "雲端找不到備份檔案"
        }
    }
}

// MARK: - WebDAV 管理器

final class WebDAVManager: ObservableObject {

    static let shared = WebDAVManager()

    // MARK: 設定（持久化至 UserDefaults）

    @Published var serverUrl: String {
        didSet { UserDefaults.standard.set(serverUrl, forKey: "webdav_url") }
    }
    @Published var username: String {
        didSet { UserDefaults.standard.set(username, forKey: "webdav_username") }
    }
    @Published var password: String {
        didSet { UserDefaults.standard.set(password, forKey: "webdav_password") }
    }

    // MARK: 狀態

    @Published var isSyncing: Bool = false
    @Published var lastSyncDate: Date?
    @Published var statusMessage: String = ""

    // MARK: 初始化

    private init() {
        serverUrl = UserDefaults.standard.string(forKey: "webdav_url") ?? ""
        username  = UserDefaults.standard.string(forKey: "webdav_username") ?? ""
        password  = UserDefaults.standard.string(forKey: "webdav_password") ?? ""
    }

    // MARK: - 認證

    private var authHeader: String {
        let credentials = "\(username):\(password)"
        let encoded = Data(credentials.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    // MARK: - 公開介面

    /// 測試 WebDAV 連線，回傳是否成功。
    func testConnection() async -> Bool {
        do {
            return try await propfind(path: "/")
        } catch {
            return false
        }
    }

    /// 將三份本地資料備份至 WebDAV。
    func backup() async throws {
        await setSync(true, message: "備份中…")
        defer { Task { @MainActor in self.isSyncing = false } }

        // 確保 /yuedu/ 目錄存在（忽略失敗，部分伺服器自動建立）
        try? await mkcol(path: "/yuedu/")

        // 1. book_sources.json（BookSourceStore → documentDirectory）
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let bookSourcesURL = docsDir.appendingPathComponent("book_sources.json")
        if let data = try? Data(contentsOf: bookSourcesURL) {
            try await put(data: data, path: "/yuedu/book_sources.json")
        }

        // 2. books.json（BookStore → UserDefaults key "yd_books_meta"）
        if let booksData = UserDefaults.standard.data(forKey: "yd_books_meta") {
            try await put(data: booksData, path: "/yuedu/books.json")
        }

        // 3. replace_rules.json（ReplaceRuleStore → libraryDirectory）
        let libDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let replaceURL = libDir.appendingPathComponent("replace_rules.json")
        if let data = try? Data(contentsOf: replaceURL) {
            try await put(data: data, path: "/yuedu/replace_rules.json")
        }

        await MainActor.run {
            self.lastSyncDate = Date()
            self.statusMessage = "備份成功"
        }
    }

    /// 從 WebDAV 下載備份並覆寫本地資料，然後重新載入書源。
    func restore() async throws {
        await setSync(true, message: "還原中…")
        defer { Task { @MainActor in self.isSyncing = false } }

        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let libDir  = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!

        // 1. book_sources.json
        if let sourcesData = try? await get(path: "/yuedu/book_sources.json") {
            let url = docsDir.appendingPathComponent("book_sources.json")
            try sourcesData.write(to: url, options: .atomic)
            // 立即更新 BookSourceStore（sources 是 @Published var，可直接賦值）
            if let decoded = try? JSONDecoder().decode([BookSource].self, from: sourcesData) {
                await MainActor.run {
                    BookSourceStore.shared.sources = decoded
                }
            }
        }

        // 2. books.json（寫回 UserDefaults，下次 BookStore 初始化時生效）
        if let booksData = try? await get(path: "/yuedu/books.json") {
            UserDefaults.standard.set(booksData, forKey: "yd_books_meta")
        }

        // 3. replace_rules.json
        if let rulesData = try? await get(path: "/yuedu/replace_rules.json") {
            let url = libDir.appendingPathComponent("replace_rules.json")
            try rulesData.write(to: url, options: .atomic)
        }

        await MainActor.run {
            self.lastSyncDate = Date()
            self.statusMessage = "還原成功，書庫和替換規則需重啟 App 後完全生效"
        }
    }

    // MARK: - 私有 HTTP 方法

    /// PROPFIND：確認路徑存在（HTTP 200 或 207）。
    private func propfind(path: String) async throws -> Bool {
        var request = try makeRequest(path: path)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200 || http.statusCode == 207
    }

    /// MKCOL：建立目錄（忽略 405 = 已存在）。
    private func mkcol(path: String) async throws {
        var request = try makeRequest(path: path)
        request.httpMethod = "MKCOL"

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return }
        // 201 = created, 405 = already exists — both acceptable
        if http.statusCode != 201 && http.statusCode != 405 && http.statusCode != 200 {
            throw WebDAVError.connectionFailed(http.statusCode)
        }
    }

    /// PUT：上傳資料至指定路徑。
    private func put(data: Data, path: String) async throws {
        var request = try makeRequest(path: path)
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 { throw WebDAVError.authenticationFailed }
        if !(200...299).contains(http.statusCode) {
            throw WebDAVError.connectionFailed(http.statusCode)
        }
    }

    /// GET：從指定路徑下載資料。
    private func get(path: String) async throws -> Data {
        var request = try makeRequest(path: path)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WebDAVError.noData }
        if http.statusCode == 401 { throw WebDAVError.authenticationFailed }
        if http.statusCode == 404 { throw WebDAVError.fileNotFound }
        if !(200...299).contains(http.statusCode) {
            throw WebDAVError.connectionFailed(http.statusCode)
        }
        return data
    }

    // MARK: - 工具

    private func makeRequest(path: String) throws -> URLRequest {
        let base = serverUrl.hasSuffix("/") ? String(serverUrl.dropLast()) : serverUrl
        guard !base.isEmpty, let url = URL(string: base + path) else {
            throw WebDAVError.invalidURL
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        return request
    }

    @MainActor
    private func setSync(_ syncing: Bool, message: String) {
        isSyncing = syncing
        statusMessage = message
    }
}
