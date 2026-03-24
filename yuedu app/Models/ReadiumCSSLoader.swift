import Foundation

struct ReadiumCSSConfiguration: Equatable {
    let fontSize: String
    let lineHeight: String
    let theme: String
    let fontFamily: String?
    let colWidth: Int?
    let pageGutter: Int?
    let scroll: Bool
    let dir: String

    init(
        fontSize: String = "100%",
        lineHeight: String = "1.5",
        theme: String = "readium-default-on",
        fontFamily: String? = nil,
        colWidth: Int? = nil,
        pageGutter: Int? = nil,
        scroll: Bool = false,
        dir: String = "ltr"
    ) {
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.theme = theme
        self.fontFamily = fontFamily
        self.colWidth = colWidth
        self.pageGutter = pageGutter
        self.scroll = scroll
        self.dir = dir
    }
}

struct ReadiumHTMLAttributes: Equatable {
    let dir: String
    let dataViewerTheme: String
    let inlineStyle: String

    func attributeString() -> String {
        "dir=\"\(dir)\" data-viewer-theme=\"\(dataViewerTheme)\" style=\"\(inlineStyle)\""
    }
}

struct ReadiumCSSBundle: Equatable {
    let htmlAttributes: ReadiumHTMLAttributes
    let beforeStyleTag: String
    let defaultStyleTag: String
    let afterStyleTag: String
}

enum ReadiumCSSLoaderError: LocalizedError, Equatable {
    case missingOrEmptyResources([String])

    var errorDescription: String? {
        switch self {
        case .missingOrEmptyResources(let resources):
            return "Readium CSS 資源缺失或為空: \(resources.joined(separator: ", "))"
        }
    }
}

/// 從 App Bundle 加載 Readium CSS 排版樣式表（CJK 橫排專用）。
///
/// Readium CSS 由三個層級組成（必須按「三明治」順序注入）：
/// 1. `ReadiumCSS-cjk-before.css` — 基礎重設（放在所有出版 CSS **之前**）
/// 2. 出版者原書 CSS（headContent + inlineBookCSS）
/// 3. `ReadiumCSS-cjk-default.css` — 預設排版規則（放在出版 CSS **之後**）
/// 4. `ReadiumCSS-cjk-after.css` — 使用者覆蓋 + 高優先級規則（最後注入）
enum ReadiumCSSLoader {

    // MARK: - 快取（只讀一次磁碟）

    private static let rawCSS: (before: String, default_: String, after: String) = {
        let before = readCSS("ReadiumCSS-cjk-before")
        let default_ = readCSS("ReadiumCSS-cjk-default")
        let after = readCSS("ReadiumCSS-cjk-after")
        return (before: before, default_: default_, after: after)
    }()

    /// 取得完整的 Readium CSS（三個檔案），已快取。
    static func load() -> (before: String, default_: String, after: String) {
        rawCSS
    }

    static func bundle(configuration: ReadiumCSSConfiguration) -> ReadiumCSSBundle {
        ReadiumCSSBundle(
            htmlAttributes: normalizedHtmlAttributes(configuration: configuration),
            beforeStyleTag: beforeCSS(),
            defaultStyleTag: defaultCSS(),
            afterStyleTag: afterCSS()
        )
    }

    static func loadResult() -> Result<(before: String, default_: String, after: String), ReadiumCSSLoaderError> {
        let css = load()
        var invalid: [String] = []
        if css.before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            invalid.append("ReadiumCSS-cjk-before.css")
        }
        if css.default_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            invalid.append("ReadiumCSS-cjk-default.css")
        }
        if css.after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            invalid.append("ReadiumCSS-cjk-after.css")
        }
        if invalid.isEmpty {
            return .success(css)
        }
        return .failure(.missingOrEmptyResources(invalid))
    }

    /// 三明治第一層：before.css — 放在出版 CSS 之前
    static func beforeCSS() -> String {
        let css = load()
        return """
        <style data-readium-css="before">\(css.before)</style>
        """
    }

    /// 三明治第三層：default.css — 放在出版 CSS 之後
    static func defaultCSS() -> String {
        let css = load()
        return """
        <style data-readium-css="default">\(css.default_)</style>
        """
    }

    /// 三明治第四層：after.css — 最高優先級覆蓋
    static func afterCSS() -> String {
        let css = load()
        return """
        <style data-readium-css="after">\(css.after)</style>
        """
    }

    // MARK: - 向後兼容（保留舊名稱，內部轉發）

    /// 生成注入到 `<head>` 開頭的 CSS（before + default）
    @available(*, deprecated, message: "Use beforeCSS() + defaultCSS() for correct sandwich order")
    static func headCSS() -> String {
        return beforeCSS() + "\n" + defaultCSS()
    }

    /// 生成注入到 `</head>` 之前的 CSS（after），覆蓋優先級最高
    @available(*, deprecated, message: "Use afterCSS()")
    static func tailCSS() -> String {
        return afterCSS()
    }

    /// Readium CSS 需要的 `<html>` 屬性，用來啟用使用者設定。
    /// - Parameters:
    ///   - fontSize: 使用者字體大小（百分比，如 "112%"）
    ///   - lineHeight: 行高倍數
    ///   - theme: 閱讀主題（readium-default-on / readium-night-on / readium-sepia-on）
    ///   - fontFamily: 使用者字體（可選）
    ///   - colWidth: 欄寬（像素），通常 = viewport 寬度
    ///   - pageGutter: 頁面左右邊距（像素）
    ///   - scroll: 是否為滾動模式（true → readium-scroll-on）
    ///   - dir: 書籍文字方向（ltr/rtl/auto）
    static func htmlAttributes(
        fontSize: String = "100%",
        lineHeight: String = "1.5",
        theme: String = "readium-default-on",
        fontFamily: String? = nil,
        colWidth: Int? = nil,
        pageGutter: Int? = nil,
        scroll: Bool = false,
        dir: String = "ltr"
    ) -> String {
        normalizedHtmlAttributes(
            fontSize: fontSize,
            lineHeight: lineHeight,
            theme: theme,
            fontFamily: fontFamily,
            colWidth: colWidth,
            pageGutter: pageGutter,
            scroll: scroll,
            dir: dir
        ).attributeString()
    }

    static func htmlAttributes(configuration: ReadiumCSSConfiguration) -> String {
        normalizedHtmlAttributes(configuration: configuration).attributeString()
    }

    static func normalizedHtmlAttributes(configuration: ReadiumCSSConfiguration) -> ReadiumHTMLAttributes {
        normalizedHtmlAttributes(
            fontSize: configuration.fontSize,
            lineHeight: configuration.lineHeight,
            theme: configuration.theme,
            fontFamily: configuration.fontFamily,
            colWidth: configuration.colWidth,
            pageGutter: configuration.pageGutter,
            scroll: configuration.scroll,
            dir: configuration.dir
        )
    }

    private static func normalizedHtmlAttributes(
        fontSize: String,
        lineHeight: String,
        theme: String,
        fontFamily: String?,
        colWidth: Int?,
        pageGutter: Int?,
        scroll: Bool,
        dir: String
    ) -> ReadiumHTMLAttributes {
        let viewMode = scroll ? "readium-scroll-on" : "readium-paged-on"
        var styleParts: [String] = []
        styleParts.append("--USER__view: \(viewMode)")
        styleParts.append("--USER__fontSize: \(normalizeFontSize(fontSize))")
        styleParts.append("--USER__lineHeight: \(normalizeLineHeight(lineHeight))")
        styleParts.append("--USER__appearance: \(theme)")

        if let font = fontFamily?.trimmingCharacters(in: .whitespacesAndNewlines), !font.isEmpty {
            let escaped = font.replacingOccurrences(of: "\"", with: "'")
            styleParts.append("--USER__fontFamily: \"\(escaped)\"")
        }
        if let width = normalizedPositivePixel(colWidth) {
            styleParts.append("--RS__colWidth: \(width)px")
            styleParts.append("--RS__colCount: 1")
            styleParts.append("--RS__colGap: 0px")
        }
        if let gutter = normalizedNonNegativePixel(pageGutter) {
            styleParts.append("--RS__pageGutter: \(gutter)px")
        }

        return ReadiumHTMLAttributes(
            dir: normalizeDir(dir),
            dataViewerTheme: theme,
            inlineStyle: styleParts.joined(separator: "; ")
        )
    }

    private static func normalizeFontSize(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "100%" }
        if trimmed.hasSuffix("%") || trimmed.hasSuffix("px") || trimmed.hasSuffix("rem") {
            return trimmed
        }
        if Double(trimmed) != nil {
            return "\(trimmed)%"
        }
        return "100%"
    }

    private static func normalizeLineHeight(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "1.5" }
        return trimmed
    }

    private static func normalizedPositivePixel(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func normalizedNonNegativePixel(_ value: Int?) -> Int? {
        guard let value, value >= 0 else { return nil }
        return value
    }

    private static func normalizeDir(_ dir: String) -> String {
        switch dir.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "rtl": return "rtl"
        case "auto": return "auto"
        default: return "ltr"
        }
    }

    static func viewportVariablesBootstrapScript(
        viewportWidth: Int,
        viewportHeight: Int,
        safeTop: Int,
        safeBottom: Int,
        userMarginTop: Int,
        userMarginBottom: Int,
        userMarginLeft: Int,
        userMarginRight: Int
    ) -> String {
        """
        (function() {
            var root = document.documentElement;
            root.style.setProperty('--VIEWPORT__width', '\(max(viewportWidth, 1))px');
            root.style.setProperty('--VIEWPORT__height', '\(max(viewportHeight, 1))px');
            root.style.setProperty('--SAFE__top', '\(max(safeTop, 0))px');
            root.style.setProperty('--SAFE__bottom', '\(max(safeBottom, 0))px');
            root.style.setProperty('--USER__marginTop', '\(max(userMarginTop, 0))px');
            root.style.setProperty('--USER__marginBottom', '\(max(userMarginBottom, 0))px');
            root.style.setProperty('--USER__marginLeft', '\(max(userMarginLeft, 0))px');
            root.style.setProperty('--USER__marginRight', '\(max(userMarginRight, 0))px');
        })();
        """
    }

    // MARK: - 磁碟讀取

    private static func readCSS(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "css") else {
            print("[ReadiumCSSLoader] ⚠️ 找不到 CSS 檔案: \(name).css")
            return ""
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            print("[ReadiumCSSLoader] ⚠️ 讀取失敗: \(name).css — \(error)")
            return ""
        }
    }
}
