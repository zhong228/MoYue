import Foundation

/// Block boundaries remain stable while streaming; inline Markdown is rendered by SwiftUI.
enum AIAnswerMarkdown {
    enum Kind: Equatable { case paragraph, heading, quote, list, code, table }
    struct Block: Equatable { let kind: Kind; let text: String }

    static func blocks(_ text: String) -> [Block] {
        var result: [Block] = []
        var buffer: [String] = []
        var kind: Kind = .paragraph
        var fence: String?
        func flush() {
            if !buffer.isEmpty { result.append(.init(kind: kind, text: buffer.joined(separator: "\n"))); buffer = [] }
        }
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let current = fence {
                if trimmed.hasPrefix(current) { flush(); fence = nil; kind = .paragraph }
                else { buffer.append(line) }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush(); fence = String(trimmed.prefix(3)); kind = .code
                continue
            }
            if trimmed.isEmpty { flush(); kind = .paragraph; continue }
            if trimmed.range(of: #"^#{1,6}\s"#, options: .regularExpression) != nil {
                flush(); result.append(.init(kind: .heading, text: String(trimmed.drop(while: { $0 == "#" || $0 == " " }))))
                continue
            }
            let next: Kind
            if trimmed.hasPrefix("> ") { next = .quote }
            else if trimmed.range(of: #"^(?:[-*+] |\d+[.)] )"#, options: .regularExpression) != nil { next = .list }
            else if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") { next = .table }
            else { next = .paragraph }
            if kind != next || next == .list { flush(); kind = next }
            buffer.append(next == .quote ? String(trimmed.dropFirst(2)) : line)
        }
        flush()
        return result
    }
}
