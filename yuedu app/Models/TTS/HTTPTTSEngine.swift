import Combine
import Foundation

// MARK: - HTTP TTS 引擎（將章節 URL 解析為音頻 URL）

final class HTTPTTSEngine: ObservableObject {

    static let shared = HTTPTTSEngine()

    private init() {}

    // MARK: - URL 模板替換

    /// 將模板字串中的佔位符替換為實際值並回傳 URL。
    /// 支援的佔位符：{{title}}、{{text}}、{{speakSpeed}}
    func buildAudioUrl(
        template: String,
        text: String,
        title: String,
        speed: Double = 1.0
    ) -> URL? {
        let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        let encodedText  = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text

        let resolved = template
            .replacingOccurrences(of: "{{title}}", with: encodedTitle)
            .replacingOccurrences(of: "{{text}}", with: encodedText)
            .replacingOccurrences(of: "{{speakSpeed}}", with: speed.description)

        return URL(string: resolved)
    }

    // MARK: - 從書源取得音頻 URL

    /// 根據書源規則，將章節 URL 解析為可播放的音頻 URL。
    /// - 若 ruleContent.content 非空且以 "http" 開頭，視為直接音頻 URL 模板。
    /// - 其餘情況：對章節 URL 發 GET 請求，若回應本身是一個 http URL 字串則使用它，
    ///   否則直接把章節 URL 當作音頻 URL。
    func getAudioUrl(chapterUrl: String, source: BookSource) async throws -> URL? {
        let contentRule = source.ruleContent.content.trimmingCharacters(in: .whitespacesAndNewlines)

        // 規則明確是 URL 模板（含 {{text}} 或直接 http）→ 直接回傳
        if !contentRule.isEmpty, contentRule.hasPrefix("http") {
            return URL(string: contentRule)
        }

        // 嘗試 GET 請求，看回應是否為一個音頻 URL
        guard let requestUrl = URL(string: chapterUrl) else { return nil }

        var request = URLRequest(url: requestUrl, timeoutInterval: 15)
        request.httpMethod = "GET"

        // 附加書源 header
        if !source.header.isEmpty,
           let headerData = source.header.data(using: .utf8),
           let headerDict = try? JSONSerialization.jsonObject(with: headerData) as? [String: String] {
            for (key, value) in headerDict {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        let (data, _) = try await URLSession.shared.data(for: request)

        if let responseString = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           responseString.hasPrefix("http"),
           let audioUrl = URL(string: responseString) {
            return audioUrl
        }

        // 降級：直接使用章節 URL
        return URL(string: chapterUrl)
    }
}
