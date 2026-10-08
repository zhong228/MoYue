import UIKit
import UniformTypeIdentifiers

/// Accepts two kinds of share payloads:
///   1. Remote links (browser → share sheet) — queued as URLs.
///   2. Book-source JSON files (Files app / WeChat / QQ / browser downloads → share
///      sheet) — queued as raw JSON `Data`, the same format the main app's
///      `shared_book_sources_queue` already drains.
/// A Share extension cannot launch its containing app through a supported API, so both
/// payloads are stashed in the app group and merged on the next app launch.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first else {
            finish(success: false, message: localized("無法讀取分享內容"))
            return
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            loadRemoteLink(provider)
        } else if let fileType = Self.bookSourceFileType(from: provider) {
            loadBookSourceFile(provider, typeIdentifier: fileType)
        } else {
            finish(success: false,
                   message: localized("無法識別分享內容的類型，請分享 .json 書源文件或書源鏈接"))
        }
    }

    // MARK: - Remote link payload

    private func loadRemoteLink(_ provider: NSItemProvider) {
        provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.finish(success: false, message: error.localizedDescription)
                    return
                }
                guard let url = item as? URL,
                      ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                    self.finish(success: false, message: localized("無法讀取分享連結"))
                    return
                }
                self.enqueueLink(url)
            }
        }
    }

    private func enqueueLink(_ url: URL) {
        do {
            guard let defaults = UserDefaults(suiteName: "group.com.zhangruilin.yuedureader") else {
                finish(success: false, message: localized("無法儲存分享連結"))
                return
            }
            let encoded = try JSONEncoder().encode(LinkPayload(remoteURLString: url.absoluteString))
            let key = "shared_import_items_queue"
            var pending = defaults.array(forKey: key) as? [Data] ?? []
            pending.append(encoded)
            defaults.set(pending, forKey: key)
            defaults.synchronize()
            finish(success: true, message: localized("連結已儲存，下次開啟墨悅時匯入。"))
        } catch {
            finish(success: false, message: error.localizedDescription)
        }
    }

    // MARK: - Book-source JSON file payload

    /// Picks the most specific registered type the provider offers that we can read as a
    /// book source: `public.json` first, then generic text/content/data fallbacks —
    /// third-party apps (WeChat/QQ/email) often register a dynamic `dyn.*` UTI that still
    /// conforms to `public.data` without ever declaring `public.json`.
    static func bookSourceFileType(from provider: NSItemProvider) -> String? {
        let preferences = [
            UTType.json.identifier,
            UTType.plainText.identifier,
            UTType.text.identifier,
            UTType.content.identifier,
            UTType.data.identifier
        ]
        return preferences.first { provider.hasItemConformingToTypeIdentifier($0) }
    }

    private func loadBookSourceFile(_ provider: NSItemProvider, typeIdentifier: String) {
        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] item, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.finish(success: false, message: error.localizedDescription)
                    return
                }
                do {
                    let data: Data
                    switch item {
                    case let url as URL:
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer {
                            if scoped { url.stopAccessingSecurityScopedResource() }
                        }
                        data = try Data(contentsOf: url)
                    case let dataValue as Data:
                        data = dataValue
                    case let dataValue as NSData:
                        data = dataValue as Data
                    default:
                        self.finish(success: false, message: localized("無法讀取書源文件"))
                        return
                    }
                    // Defer the real JSON validation to the main app's shared import
                    // pipeline; here we only skip obviously empty blobs.
                    if data.isEmpty {
                        self.finish(success: false, message: localized("書源文件為空"))
                        return
                    }
                    self.enqueueBookSource(data)
                } catch {
                    self.finish(success: false, message: error.localizedDescription)
                }
            }
        }
    }

    private func enqueueBookSource(_ data: Data) {
        guard let defaults = UserDefaults(suiteName: "group.com.zhangruilin.yuedureader") else {
            finish(success: false, message: localized("無法儲存書源文件"))
            return
        }
        // Same key/format the main app's SharedImportQueueDrainer drains.
        let key = "shared_book_sources_queue"
        var pending = defaults.array(forKey: key) as? [Data] ?? []
        pending.append(data)
        defaults.set(pending, forKey: key)
        defaults.synchronize()
        finish(success: true, message: localized("書源已儲存，下次開啟墨悅時匯入。"))
    }

    private func finish(success: Bool, message: String) {
        let alert = UIAlertController(title: localized(success ? "匯入成功" : "匯入失敗"),
                                      message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: localized("關閉"), style: .default) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        })
        present(alert, animated: true)
    }
}

/// Matches the main app's existing queue format, including older installations.
private struct LinkPayload: Encodable {
    var id = UUID().uuidString
    var storageKind = "remoteURL"
    var remoteURLString: String
    var createdAt = Date()
}

private func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}