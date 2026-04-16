import Foundation

// MARK: - 獲取目錄

extension BookSourceFetcher {

    /// 抓取目錄（Legado 相容：ruleToc.chapterList/name/url、多頁 nextTocUrl、preUpdateJs）。
    /// 若 ruleToc.preUpdateJs 有值，會用 WebView 載入目錄頁並先執行該 JS 再取 HTML。
    func fetchTOC(
        tocUrl: String,
        source: BookSource,
        runtimeVariables: [String: String]? = nil
    ) async throws -> [OnlineChapterRef] {
        let package = try await fetchTOCPackage(
            tocUrl: tocUrl,
            source: source,
            runtimeVariables: runtimeVariables
        )
        return package.chapters
    }

    func fetchTOCPackage(
        tocUrl: String,
        source: BookSource,
        runtimeVariables: [String: String]? = nil
    ) async throws -> TOCPackage {
        if let cached = loadTOCPackageSync(tocUrl: tocUrl, source: source), !cached.chapters.isEmpty {
            let hasBadURL = cached.chapters.contains { ch in
                ch.url.contains("<") || ch.url.contains("&lt;") || ch.url.contains("%3C")
            }
            if !hasBadURL {
                return cached
            }
        }
        // #region agent log
        _dbgLog(
            "fetchTOC 進入",
            data: [
                "tocUrl": String(tocUrl.prefix(80)),
                "source": source.bookSourceName,
                "chapterList": String(source.ruleToc.chapterList.prefix(80)),
                "chapterUrl": String(source.ruleToc.chapterUrl.prefix(40)),
                "chapterName": String(source.ruleToc.chapterName.prefix(40)),
                "needsWebView": source.needsWebView,
                "hasPreUpdateJs": !source.ruleToc.preUpdateJs.isEmpty,
            ], hyp: "T1")
        // #endregion
        // #region agent log
        if source.ruleToc.chapterList.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _dbgLog("fetchTOC chapterList 為空", data: ["source": source.bookSourceName], hyp: "H1")
        }
        // #endregion
        guard let url = safeURL(string: tocUrl) else { throw FetchError.invalidURL(tocUrl) }
        let html: String
        var usedWebView = false
        let baseForReferer = tocUrl
        if !source.ruleToc.preUpdateJs.isEmpty {
            html = try await WebViewFetcher.shared.fetchHTMLWithCustomJS(
                url: url, headers: source.parsedHeaders,
                jsAfterLoad: source.ruleToc.preUpdateJs, timeout: 20, jsWait: 2.0)
            usedWebView = true
        } else if source.needsWebView {
            html = try await Self.fetchViaWebView(url: url, headers: source.parsedHeaders)
            usedWebView = true
        } else {
            html = try await fetchHTML(
                url: url, method: "GET", body: nil,
                headers: source.parsedHeaders,
                baseURL: baseForReferer.isEmpty ? source.bookSourceUrl : baseForReferer)
        }
        // #region agent log
        _dbgLog(
            "fetchTOC 已取得 HTML",
            data: [
                "source": source.bookSourceName,
                "htmlLen": html.count,
                "htmlPreview": String(html.prefix(150)).replacingOccurrences(of: "\n", with: " "),
            ], hyp: "H2")
        // #endregion
        var chapters = try pipeline.parseTOC(
            html: html,
            baseURL: url.absoluteString,
            source: source,
            runtimeVariables: runtimeVariables
        )
        var htmlForNext = html

        // #region agent log
        _dbgLog(
            "fetchTOC 初次解析結果",
            data: [
                "source": source.bookSourceName,
                "chaptersCount": chapters.count,
                "htmlLen": html.count,
                "usedWebView": usedWebView,
                "htmlPreview": String(html.prefix(300)).replacingOccurrences(of: "\n", with: " "),
            ], hyp: "T1")
        // #endregion

        // 若 URLSession 取得空目錄，嘗試用 WebView 重試（許多站點目錄由 JS 動態載入）
        if chapters.isEmpty && !usedWebView {
            let webHtml = try await WebViewFetcher.shared.fetchHTML(
                url: url,
                headers: source.parsedHeaders,
                timeout: 20,
                jsWait: 4.0
            )
            chapters = try pipeline.parseTOC(
                html: webHtml,
                baseURL: url.absoluteString,
                source: source,
                runtimeVariables: runtimeVariables
            )
            htmlForNext = webHtml
            // #region agent log
            _dbgLog(
                "fetchTOC WebView 重試後",
                data: ["source": source.bookSourceName, "chaptersCount": chapters.count], hyp: "B")
            // #endregion
        }
        if chapters.isEmpty && usedWebView && source.ruleToc.preUpdateJs.isEmpty {
            let delayedHtml = try await WebViewFetcher.shared.fetchHTML(
                url: url,
                headers: source.parsedHeaders,
                timeout: 20,
                jsWait: 4.0
            )
            chapters = try pipeline.parseTOC(
                html: delayedHtml,
                baseURL: url.absoluteString,
                source: source,
                runtimeVariables: runtimeVariables
            )
            htmlForNext = delayedHtml
        }

        // 多頁目錄
        var rawHTMLPages: [String] = [htmlForNext]
        var nextURL = pipeline.extractNextTocURL(
            html: htmlForNext,
            baseURL: url.absoluteString,
            source: source,
            runtimeVariables: runtimeVariables
        )
        var pageCount = 0
        let usePreUpdateJs = !source.ruleToc.preUpdateJs.isEmpty
        while !nextURL.isEmpty && pageCount < 20 {
            guard let nextPageURL = URL(string: nextURL) else { break }
            let nextBase = nextURL.isEmpty ? source.bookSourceUrl : nextURL
            let nextHTML: String
            if usePreUpdateJs {
                nextHTML = try await WebViewFetcher.shared.fetchHTMLWithCustomJS(
                    url: nextPageURL, headers: source.parsedHeaders,
                    jsAfterLoad: source.ruleToc.preUpdateJs, timeout: 20, jsWait: 2.0)
            } else if source.needsWebView {
                nextHTML = try await Self.fetchViaWebView(
                    url: nextPageURL, headers: source.parsedHeaders)
            } else {
                nextHTML = try await fetchHTML(
                    url: nextPageURL, method: "GET", body: nil,
                    headers: source.parsedHeaders, baseURL: nextBase)
            }
            rawHTMLPages.append(nextHTML)
            chapters.append(
                contentsOf: try pipeline.parseTOC(
                    html: nextHTML,
                    baseURL: nextURL,
                    source: source,
                    runtimeVariables: runtimeVariables
                ))
            nextURL = pipeline.extractNextTocURL(
                html: nextHTML,
                baseURL: nextURL,
                source: source,
                runtimeVariables: runtimeVariables
            )
            pageCount += 1
        }
        let normalized = chapters.enumerated().map { i, ref in
            var r = ref
            r.index = i
            return r
        }
        let package = saveTOCPackage(
            tocUrl: tocUrl,
            source: source,
            runtimeVariables: runtimeVariables,
            chapters: normalized,
            rawHTML: rawHTMLPages.joined(separator: "\n<!-- toc-page-break -->\n")
        )
        return package
    }
}
