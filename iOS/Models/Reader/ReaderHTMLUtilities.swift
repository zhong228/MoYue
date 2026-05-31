import Foundation

enum ReaderHTMLUtilities {
    static func displayText(fromHTMLFragment text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return "" }

        result = result.replacingOccurrences(
            of: #"(?i)&lt;\s*br\s*/?\s*&gt;"#,
            with: "\n",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)<\s*br\s*/?\s*>"#,
            with: "\n",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)</(?:p|div|li|h[1-6]|section|article|blockquote|dt|dd|tr)>"#,
            with: "\n",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)

        let entities: [(String, String)] = [
            ("&nbsp;", " "),
            ("&#160;", " "),
            ("&ensp;", " "),
            ("&emsp;", " "),
            ("&thinsp;", ""),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&#34;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }

        return result
            .replacingOccurrences(of: #"[ \t\f\v\r\n]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func paragraphs(fromPlainText text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{000B}", with: " ")
            .replacingOccurrences(of: #"[ \t\f]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return [] }

        let explicitParagraphs = normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard explicitParagraphs.count <= 1,
              let onlyParagraph = explicitParagraphs.first,
              onlyParagraph.count >= 420 else {
            return explicitParagraphs
        }

        return sentenceChunks(from: onlyParagraph)
    }

    static func bodyParagraphs(fromPlainText text: String, excludingLeadingTitle title: String) -> [String] {
        let titleKey = normalizedTitleKey(title)
        guard !titleKey.isEmpty else { return paragraphs(fromPlainText: text) }

        return paragraphs(fromPlainText: text).enumerated().compactMap { index, paragraph in
            guard index < 6,
                  normalizedTitleKey(paragraph) == titleKey
            else {
                return paragraph
            }
            return nil
        }
    }

    static func isLikelyCollapsedChapterText(_ text: String) -> Bool {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 220 else { return false }

        let lines = normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.count <= 1 else { return false }

        let sentenceBreaks = normalized.reduce(into: 0) { count, character in
            if "。！？!?".contains(character) {
                count += 1
            }
        }
        return sentenceBreaks >= 6
    }

    // MARK: - Paragraph review (段評) markers

    /// A tappable paragraph-review target, used to present the source's review web page.
    struct ReviewTarget: Identifiable, Hashable {
        let url: String
        let title: String
        var id: String { url }
    }

    /// Decoded payload of a `ydreview://` review anchor: comment count + review URL + title.
    struct ReviewMarker: Equatable {
        let count: String
        let url: String
        let title: String
    }

    /// Custom URL scheme used internally to carry a paragraph-review action through the
    /// existing link/attachment pipeline. Never reaches a real network request.
    static let reviewURLScheme = "ydreview"

    /// Rewrites Legado iOS paragraph-review markers into plain anchors the renderer can carry.
    ///
    /// The `paraForiOS` jsLib emits, per paragraph:
    ///   `<comment count="12" onPress="java.showReadingBrowser('<absolute-url>','番茄段评')">`
    /// Relying on an obscure `<comment>` tag (and non-allowlisted `count`/`onPress` attributes)
    /// surviving SwiftSoup round-trips is fragile, so we convert each marker into:
    ///   `<a href="ydreview://r?d=<base64url(JSON{c,u,t})>" class="yd-review">12</a>`
    /// Anchors and their `href` are always preserved and `href` is in the builder allowlist.
    /// Idempotent: a string with no `<comment …>` markers is returned unchanged.
    static func rewriteReviewComments(_ html: String) -> String {
        guard html.range(of: "<comment", options: .caseInsensitive) != nil else { return html }
        guard let tagRegex = try? NSRegularExpression(
            pattern: #"<comment\b[^>]*>"#,
            options: [.caseInsensitive]
        ) else { return html }

        let ns = html as NSString
        let matches = tagRegex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return html }

        var result = ""
        var cursor = 0
        for match in matches {
            let range = match.range
            result += ns.substring(with: NSRange(location: cursor, length: range.location - cursor))
            let tag = ns.substring(with: range)
            if let anchor = anchorMarkup(forCommentTag: tag) {
                result += anchor
            } else {
                result += tag
            }
            cursor = range.location + range.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    private static func anchorMarkup(forCommentTag tag: String) -> String? {
        guard let count = firstCapture(in: tag, pattern: #"count\s*=\s*"([^"]*)""#),
              let args = showReadingBrowserArgs(in: tag)
        else { return nil }
        let url = unescapeHTMLEntities(args.url)
        let title = unescapeHTMLEntities(args.title)
        guard !url.isEmpty else { return nil }
        let payload: [String: String] = ["c": count, "u": url, "t": title]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let encoded = base64URLEncode(data)
        else { return nil }
        return "<a href=\"\(reviewURLScheme)://r?d=\(encoded)\" class=\"yd-review\">\(escapeHTML(count))</a>"
    }

    /// Decodes a `ydreview://` href back into its comment count, review URL, and title.
    static func decodeReviewHref(_ href: String) -> ReviewMarker? {
        guard href.hasPrefix("\(reviewURLScheme)://") else { return nil }
        guard let dRange = href.range(of: "d=") else { return nil }
        let encoded = String(href[dRange.upperBound...])
        guard let data = base64URLDecode(encoded),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let url = obj["u"], !url.isEmpty
        else { return nil }
        return ReviewMarker(count: obj["c"] ?? "", url: url, title: obj["t"] ?? "")
    }

    /// Convenience wrapper producing a `ReviewTarget` for sheet presentation.
    static func reviewTarget(fromHref href: String) -> ReviewTarget? {
        guard let marker = decodeReviewHref(href) else { return nil }
        return ReviewTarget(url: marker.url, title: marker.title)
    }

    private static func showReadingBrowserArgs(in tag: String) -> (url: String, title: String)? {
        guard let regex = try? NSRegularExpression(
            pattern: #"showReadingBrowser\(\s*'([^']*)'\s*,\s*'([^']*)'\s*\)"#,
            options: [.caseInsensitive]
        ) else { return nil }
        let ns = tag as NSString
        guard let m = regex.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 3
        else { return nil }
        return (ns.substring(with: m.range(at: 1)), ns.substring(with: m.range(at: 2)))
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2
        else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    private static func unescapeHTMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: "&lt;", with: "<", options: .caseInsensitive)
            .replacingOccurrences(of: "&gt;", with: ">", options: .caseInsensitive)
            .replacingOccurrences(of: "&quot;", with: "\"", options: .caseInsensitive)
            .replacingOccurrences(of: "&#39;", with: "'", options: .caseInsensitive)
            .replacingOccurrences(of: "&apos;", with: "'", options: .caseInsensitive)
    }

    private static func base64URLEncode(_ data: Data) -> String? {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecode(_ string: String) -> Data? {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = s.count % 4
        if remainder > 0 {
            s += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: s)
    }

    static func normalizedChapterHTML(
        title: String,
        paragraphs: [String],
        language: String = "zh-Hant"
    ) -> String {
        let trimmedTitle = displayText(fromHTMLFragment: title)
        let escapedTitle = escapeHTML(trimmedTitle.isEmpty ? "Untitled" : trimmedTitle)
        let heading =
            trimmedTitle.isEmpty
            ? ""
            : "<h1>\(escapeHTML(trimmedTitle))</h1>\n"
        let body = paragraphs.enumerated()
            .map { _, paragraph in
                "<p>\(escapeHTML(paragraph))</p>"
            }
            .joined(separator: "\n")

        return """
        <!DOCTYPE html>
        <html lang="\(language)">
        <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>\(escapedTitle)</title>
        </head>
        <body>
        <article id="reader-content">
        \(heading)\(body)
        </article>
        </body>
        </html>
        """
    }

    static func escapeHTML(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        return result
    }

    private static func normalizedTitleKey(_ text: String) -> String {
        displayText(fromHTMLFragment: text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .lowercased()
    }

    private static func sentenceChunks(from text: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        let strongBreaks = Set("。！？!?；;")
        let weakBreaks = Set("，,、")

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                chunks.append(trimmed)
            }
            current = ""
        }

        for character in text {
            current.append(character)
            if strongBreaks.contains(character), current.count >= 180 {
                flush()
            } else if weakBreaks.contains(character), current.count >= 260 {
                flush()
            } else if current.count >= 360 {
                flush()
            }
        }

        flush()
        return chunks.isEmpty ? [text] : chunks
    }
}
