import Foundation

struct ChapterParsePayload {
    var content: String
    var title: String
    var sourceMatched: Bool
    var isPay: Bool
    var runtimeVariables: [String: String]? = nil
}

@MainActor
final class WebCrawlerDebugger {
    static let shared = WebCrawlerDebugger()

    func logParse(rule: String, matchCount: Int, url: String) {}
}
