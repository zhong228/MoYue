import Foundation

final class ModernRuleEngine {

    // MARK: - Global Extractor Registry（開閉原則）
    //
    // 要新增 Extractor（例如 AIExtractor）：
    //   ModernRuleEngine.registerExtractor(AIExtractor())
    // 不需要修改此檔案任何一行。核心引擎「對修改封閉」。
    //
    // 啟動時由 AppDependencies 填充；測試環境可隨時替換整張清單。

    private static var _registry: [RuleExtractor] = [
        JsonExtractor(),
        XPathExtractor(),
        CssExtractor(),
        JsoupDefaultExtractor(),
        LegacyFallbackExtractor(),
    ]
    private static let registryLock = NSLock()

    /// 向全域 Registry 末尾追加一個 Extractor。
    static func registerExtractor(_ extractor: RuleExtractor) {
        registryLock.withLock { _registry.append(extractor) }
    }

    /// 向全域 Registry 指定位置插入一個 Extractor（優先級控制用）。
    static func registerExtractor(_ extractor: RuleExtractor, at index: Int) {
        registryLock.withLock {
            _registry.insert(extractor, at: min(index, _registry.count))
        }
    }

    /// 取得當前 Registry 快照（測試 / Debug 用）。
    static var registeredExtractors: [RuleExtractor] {
        registryLock.withLock { _registry }
    }

    /// 完整替換 Registry（測試環境隔離用）。
    static func setExtractors(_ extractors: [RuleExtractor]) {
        registryLock.withLock { _registry = extractors }
    }

    // MARK: - Instance

    private let extractors: [RuleExtractor]

    /// 使用 Registry 中當下已註冊的 Extractor 集合建立引擎實例。
    /// 傳入 `extractors` 可完全覆蓋 Registry（適合單元測試注入 mock）。
    init(extractors: [RuleExtractor]? = nil) {
        self.extractors = extractors ?? ModernRuleEngine.registeredExtractors
    }

    func extractList(from content: String, rule: String, baseURL: String) throws -> [String] {
        let (cleanedRule, shouldReverse) = preprocessListRule(rule)
        let (mainRule, regexParts) = splitRuleAndRegex(cleanedRule)
        let (opType, opParts) = RuleSyntaxParser.splitRuleByOperators(mainRule)
        if opParts.count > 1 {
            switch opType {
            case "||":
                for part in opParts {
                    let result = try extractList(from: content, rule: part, baseURL: baseURL)
                    if !result.isEmpty { return shouldReverse ? result.reversed() : result }
                }
                return []
            case "&&":
                let merged = try opParts.flatMap { try extractList(from: content, rule: $0, baseURL: baseURL) }
                return shouldReverse ? merged.reversed() : merged
            case "%%":
                let lists = try opParts.map { try extractList(from: content, rule: $0, baseURL: baseURL) }
                guard lists.allSatisfy({ !$0.isEmpty }) else { return [] }
                let interleaved = interleave(lists)
                return shouldReverse ? interleaved.reversed() : interleaved
            default:
                break
            }
        }

        guard let extractor = extractors.first(where: { $0.canHandle(rule: cleanedRule) }) else {
            throw ModernRuleEngineError.unsupportedRule(cleanedRule)
        }
        let extracted = try extractor.extractList(from: content, rule: mainRule, baseURL: baseURL)
        let postProcessed = extracted.map { applyRegex(to: $0, parts: regexParts).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return shouldReverse ? postProcessed.reversed() : postProcessed
    }

    func extractValue(from content: String, rule: String, baseURL: String) throws -> String {
        let cleanedRule = preprocess(rule)
        let (mainRule, regexParts) = splitRuleAndRegex(cleanedRule)
        let (opType, opParts) = RuleSyntaxParser.splitRuleByOperators(mainRule)
        if opParts.count > 1 {
            switch opType {
            case "&&":
                let pieces = try opParts.compactMap { part -> String? in
                    let value = try extractValue(from: content, rule: part, baseURL: baseURL)
                    return value.isEmpty ? nil : value
                }
                return pieces.joined(separator: "\n")
            case "||":
                for part in opParts {
                    let value = try extractValue(from: content, rule: part, baseURL: baseURL)
                    if !value.isEmpty { return value }
                }
                return ""
            default:
                break
            }
        }

        guard let extractor = extractors.first(where: { $0.canHandle(rule: mainRule) }) else {
            throw ModernRuleEngineError.unsupportedRule(mainRule)
        }
        let extracted = try extractor.extractValue(from: content, rule: mainRule, baseURL: baseURL)
        let value: String
        if extracted.isEmpty && !regexParts.isEmpty {
            value = applyRegex(to: content, parts: regexParts)
        } else {
            value = applyRegex(to: extracted, parts: regexParts)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func preprocess(_ rawRule: String) -> String {
        var result = rawRule.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("@@") {
            result = String(result.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private func preprocessListRule(_ rawRule: String) -> (rule: String, shouldReverse: Bool) {
        var cleaned = preprocess(rawRule)
        var shouldReverse = false
        if cleaned.hasPrefix("-") {
            shouldReverse = true
            cleaned = String(cleaned.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (cleaned, shouldReverse)
    }

    private func interleave(_ lists: [[String]]) -> [String] {
        var result: [String] = []
        var index = 0
        while true {
            var appended = false
            for list in lists where index < list.count {
                result.append(list[index])
                appended = true
            }
            if !appended { break }
            index += 1
        }
        return result
    }

    private func splitRuleAndRegex(_ rule: String) -> (String, [String]) {
        let parts = rule.components(separatedBy: "##")
        let mainRule = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let regexParts = Array(parts.dropFirst())
        return (mainRule, regexParts)
    }

    private func applyRegex(to text: String, parts: [String]) -> String {
        guard !parts.isEmpty else { return text }
        let pattern = parts[0]
        guard !pattern.isEmpty else { return text }

        if parts.count >= 2 {
            let replacement = parts[1]
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(text.startIndex..., in: text)
                return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
            }
            return text
        }

        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(text.startIndex..., in: text)
            return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }
        return text
    }
}
